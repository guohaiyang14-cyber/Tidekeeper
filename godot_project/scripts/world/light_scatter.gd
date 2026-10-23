# ============================================================================
# LightScatter — 地图散落光源（荧光藻 / 贝类 / 夜明珠）
# 职责：按**区块（chunk）程序化**在地图上铺微型光源——玩家走到哪都有光，
#       每个光源 = 精灵（world/glow_*）+ 一层柔和径向光晕（恒定亮度，不脉冲）；
#       同时向 VisionOverlay 提供照明数据（位置/半径/强度），参与黑夜视野计算。
# 数据：config/map.json scattered_lights
#       （chunk_px / lights_per_chunk / chunk_radius / radius_units / intensity /
#        core_ratio / min_gap_units / halo_scale / sprite_scale / kinds）
# 注意：**照明半径（radius，交 VisionOverlay 开雾）与光晕半径（halo_radius，画在屏幕上）
#       是两条独立的量**——前者只读 config，后者由素材尺寸 × halo_scale 决定。
#       改外观不能顺手改照明，否则等于偷偷调难度。
# 红线：位置/颜色/半径只读 config；每个区块用**本地 RNG（区块坐标哈希）**，
#       不消耗全局 RNG、不 instantiate 场景。
#
# 2026-10-23 用户反馈：
#   ①「野生光源应该是常亮的」→ 去掉呼吸脉冲，恒定亮度；z_index 提到视野遮罩之上，
#     纯黑里也看得见，兼作路标。
#   ②「跑一会会出现页面内全黑什么都没有」→ 地图已无范围限制（arena.enabled=false），
#     原先「以灯塔为圆心固定环带撒 80 个」走远了就没光。改为**按区块确定性生成**：
#     玩家跨区块时重建周边 (2r+1)² 个区块内的光源，区块内容由坐标哈希决定，
#     因此来回走动看到的同一处光源位置完全一致（不会闪跳），且地图无限延伸都有光。
#   ③ 光晕原为 3 个硬边同心圆（看起来像贴片），后改 draw_polygon 单扇形径向渐变。
#   ④ 2026-10-23 第二轮（用户反馈「野外光源不发出扇形光，只需要沿着素材边缘发出
#     扩散光即可，并且不要挡住下方的视野，还要减少数量，现在野外光源太多了，
#     素材也要减小」）：
#      - **扇形 → 圆形均匀扩散**：光晕为**单扇形 fan draw_polygon**（中心顶点 +
#        `HALO_RING_SEGS=32` 段圆周，顶点色 alpha 0.55→0 径向渐隐），半径由
#        `halo_scale`（素材半边长 × 2.2）决定，紧贴素材边缘向外渐隐。
#        **「扇形感」的真因是圆周细分不足**：v3.22 用 20 段画 115px 大光晕，
#        每段弧长 36px，边缘棱角被读成扇形；现在半径降到 ~35px、细分 32 段
#        （每段弧长 ≈6.9px），肉眼不可辨，才是真正的圆形均匀扩散。
#        曾试过 `GradientTexture2D` 径向渐变贴图（128² FILL_RADIAL，纹理本身正确），
#        但**运行时 new 的渐变纹理首帧可能没上传到渲染服务器，而 `queue_redraw()`
#        只在跨区块时触发一次**，节点之后不再变脏 → 光晕永久不显示（实测：换成
#        实心品红圆立刻可见，渐变圆盘完全不可见）；也试过 6 层 × 24 段同心环带
#        draw_polygon，窗口里整个不显示（离线验证无自交/无重合点，疑多顶点环形
#        渲染路径问题），故最终回退 v3.25 已验证的 fan 程序化绘制；
#      - **不遮挡下方视野**：本节点 material = CanvasItemMaterial + BLEND_MODE_ADD
#        （加色混合：只提亮、不覆盖），地面/雾罩细节仍可见；子精灵各自独立
#        CanvasItem 用默认 MIX 材质，保留原调色板（CanvasItem.material 不向子节点继承）；
#      - **减量**：chunk_px 480→560、lights_per_chunk 3→2（密度约减半）；
#      - **素材缩小**：新增 sprite_scale=0.75（Sprite2D.scale，原按原生 48/42/30px 直绘）；
#        radius_units 维持 1.2、intensity 维持 1.0——只减数量与改外观，
#        不削弱单个光源的照亮能力（那是隐蔽的难度改动）。
# ============================================================================
extends Node2D
class_name LightScatter

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")
## 光晕径向分层数（fan 方案不使用；保留供机检断言「非环带路径」）
const HALO_RINGS: int = 1
## 光晕圆周细分数（**关键**：v3.22 用 20 段画 115px 大光晕，每段弧长 36px，
## 边缘棱角明显，被用户读成「扇形光」。半径变小 + 细分提到 32 段后每段弧长
## ≈6.9px，肉眼不可辨，才是真正的圆形均匀扩散）
const HALO_RING_SEGS: int = 32
## 光晕整体透明度上限（加色混合，过大容易糊成一片亮斑）
const HALO_MAX_ALPHA: float = 0.55
## 区块坐标哈希的固定盐值（同局可复现）
const HASH_SALT: int = 20261023
## 未初始化时的区块哨兵值
const NO_CHUNK: int = 0x7FFFFFFF

signal lights_changed(lights: Array[Dictionary])

## 光源数据：{pos, radius(照明), halo_radius(绘制), intensity, core_ratio, color}
var _lights: Array[Dictionary] = []
var _enabled: bool = false

var _chunk_px: float = 560.0
var _per_chunk: int = 2
var _chunk_radius: int = 2
var _min_gap: float = 150.0
var _radius: float = 72.0
var _intensity: float = 1.0
var _core: float = 0.4
var _sprite_scale: float = 0.75
var _halo_scale: float = 2.2
var _kinds: Array[Dictionary] = []

var _last_cx: int = NO_CHUNK
var _last_cy: int = NO_CHUNK


func _ready() -> void:
	# 加色混合：光晕只提亮不覆盖，避免挡住下方地面/雾罩细节
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	# 光晕是柔和渐变，用线性过滤；子精灵各自 NEAREST 保持像素风
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## 初始化（World 在灯塔碰撞设置后调用）；center 仅用于首次填充
func setup(center: Vector2) -> void:
	var cfg: Dictionary = ConfigLoader.get_scattered_lights_config()
	_enabled = bool(cfg.get("enabled", false))
	set_process(false)  # 常亮：无脉冲，无需逐帧重绘
	if not _enabled:
		return
	_chunk_px = maxf(64.0, float(cfg.get("chunk_px", 560.0)))
	_per_chunk = maxi(0, int(cfg.get("lights_per_chunk", 2)))
	_chunk_radius = maxi(1, int(cfg.get("chunk_radius", 2)))
	_min_gap = float(cfg.get("min_gap_px", 150.0))
	_radius = float(cfg.get("radius_px", 72.0))
	_intensity = float(cfg.get("intensity", 1.0))
	_core = float(cfg.get("core_ratio", 0.4))
	_sprite_scale = clampf(float(cfg.get("sprite_scale", 0.75)), 0.25, 2.0)
	_halo_scale = clampf(float(cfg.get("halo_scale", 2.2)), 1.0, 6.0)
	# JSON 解析出的是无类型 Array，不能整体赋给 Array[Dictionary]（运行时类型检查报错）；
	# 逐元素收编，顺带过滤坏数据（config 已由校验器保证结构，此处双保险）
	_kinds.clear()
	for _k in (cfg.get("kinds", []) as Array):
		if _k is Dictionary:
			_kinds.append(_k as Dictionary)
	update_around(center)


## 玩家位置变化时按区块重建；返回是否真的重建了（机检/World 用）
func update_around(pos: Vector2) -> bool:
	if not _enabled or _per_chunk <= 0 or _kinds.is_empty():
		return false
	var cx: int = int(floor(pos.x / _chunk_px))
	var cy: int = int(floor(pos.y / _chunk_px))
	if cx == _last_cx and cy == _last_cy and not _lights.is_empty():
		return false
	_last_cx = cx
	_last_cy = cy
	_rebuild(cx, cy)
	lights_changed.emit(_lights)
	return true


## 机检：当前光源列表
func get_light_data() -> Array[Dictionary]:
	return _lights


## 机检：光源数量
func get_light_count() -> int:
	return _lights.size()


## 机检：当前区块坐标
func get_chunk_coord() -> Vector2i:
	return Vector2i(_last_cx, _last_cy)


## 机检：区块边长（像素）
func get_chunk_px() -> float:
	return _chunk_px


func _rebuild(cx: int, cy: int) -> void:
	_lights.clear()
	for ch in get_children():
		ch.queue_free()
	for dy in range(-_chunk_radius, _chunk_radius + 1):
		for dx in range(-_chunk_radius, _chunk_radius + 1):
			_scatter_chunk(cx + dx, cy + dy)
	queue_redraw()


## 单个区块：坐标哈希 → 本地 RNG → 确定性放 lights_per_chunk 个光源
func _scatter_chunk(gx: int, gy: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_chunk(gx, gy)
	var placed: Array[Vector2] = []
	for _i in _per_chunk:
		var pos := Vector2(
			(float(gx) + rng.randf()) * _chunk_px,
			(float(gy) + rng.randf()) * _chunk_px
		)
		# 同区块内最小间距（跨区块不校验：区块间天然由哈希打散）
		var too_close: bool = false
		for q in placed:
			if q.distance_to(pos) < _min_gap:
				too_close = true
				break
		if too_close:
			continue
		placed.append(pos)
		var kind: Dictionary = _pick_kind(rng)
		var col: Color = kind.get("color", Color(0.5, 0.9, 0.9)) as Color
		var kind_id: String = String(kind.get("id", "glow_algae"))
		# 照明半径（交给 VisionOverlay 开雾）：只读 config，不随外观缩小而变
		var r: float = _radius * float(kind.get("radius_mult", 1.0))
		# 光晕绘制半径：紧贴素材边缘向外扩散（素材半边长 × halo_scale）
		var halo_r: float = maxf(8.0, _sprite_half_size(kind_id) * _halo_scale)
		_lights.append({
			"pos": pos,
			"radius": r,
			"halo_radius": halo_r,
			"intensity": _intensity,
			"core_ratio": _core,
			"color": col,
		})
		_spawn_sprite(pos, kind_id)


## 区块坐标 → 稳定 32 位种子（同坐标必得同值；不依赖全局 RNG）
func _hash_chunk(gx: int, gy: int) -> int:
	var h: int = (gx * 73856093) ^ (gy * 19349663) ^ HASH_SALT
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


## 按权重随机选一种光源类型
func _pick_kind(rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for k in _kinds:
		total += maxf(0.0, float((k as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return _kinds[0] as Dictionary
	var roll: float = rng.randf_range(0.0, total)
	var acc: float = 0.0
	for k in _kinds:
		acc += maxf(0.0, float((k as Dictionary).get("weight", 1.0)))
		if roll <= acc:
			return k as Dictionary
	return _kinds[_kinds.size() - 1] as Dictionary


## 素材（按 sprite_scale 缩放后）的半边长；取纹理长边的一半
func _sprite_half_size(sprite_id: String) -> float:
	var tex: Texture2D = _SPRITE_LIB.world(sprite_id)
	if tex == null:
		return 0.0
	return 0.5 * maxf(float(tex.get_width()), float(tex.get_height())) * _sprite_scale


func _spawn_sprite(pos: Vector2, sprite_id: String) -> void:
	var tex: Texture2D = _SPRITE_LIB.world(sprite_id)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos - global_position
	# 素材缩小：config sprite_scale（CanvasItem.material 不向子节点继承，
	# 因此精灵仍用默认 MIX 材质，保留自身调色板不被加色混合吃掉层次）
	s.scale = Vector2(_sprite_scale, _sprite_scale)
	add_child(s)


## 单个光源的圆形径向渐变光晕（沿素材边缘向外均匀扩散）
## 单扇形 fan：中心 1 点 + 圆周 HALO_RING_SEGS 点（边缘 alpha 0），draw_polygon
## 自动三角形化并对顶点色做双线性插值 → 平滑的圆形径向渐变。
## **曾试过「同心环带」拼曲线（6 环 × 32 段 = 64 顶点/环）**，几何上验证过无自交、
## 无重合点、日志也无 triangulation 报错，但窗口实测**整个光晕不显示**（只有精灵可见）；
## 实心 draw_circle 同帧却正常 → 问题出在多顶点环形多边形这条路径上。
## 故回到 v3.25 已验证可用的 fan 路径，只改两个参数：
##   · 圆周 20 → 32 段（半径 ~35px 下每段弧长 ≈6.9px，肉眼不可辨，消除 v3.22 的棱面/扇形感）；
##   · 半径 115px（照明半径×1.6）→ halo_radius（素材半边长×2.2 ≈ 35px），紧贴素材边缘。
func _draw_halo(center: Vector2, radius: float, col: Color) -> void:
	if radius <= 0.5:
		return
	var pts := PackedVector2Array([center])
	var cols := PackedColorArray([Color(col.r, col.g, col.b, HALO_MAX_ALPHA)])
	for s in HALO_RING_SEGS:
		var ang: float = TAU * float(s) / float(HALO_RING_SEGS)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
		cols.append(Color(col.r, col.g, col.b, 0.0))
	draw_polygon(pts, cols)


func _draw() -> void:
	if not _enabled or _lights.is_empty():
		return
	for L in _lights:
		var pos: Vector2 = (L.get("pos", Vector2.ZERO) as Vector2) - global_position
		var col: Color = L.get("color", Color(0.5, 0.9, 0.9)) as Color
		# 光晕半径独立于照明半径：只由素材尺寸决定，紧贴素材边缘向外渐隐
		_draw_halo(pos, float(L.get("halo_radius", 24.0)), col)


## 机检：素材缩放系数
func get_sprite_scale() -> float:
	return _sprite_scale


## 机检：光晕半径系数（素材半边长 × 该值）
func get_halo_scale() -> float:
	return _halo_scale


## 机检：节点材质是否为加色混合
func is_additive_blend() -> bool:
	var mat := material as CanvasItemMaterial
	return mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
