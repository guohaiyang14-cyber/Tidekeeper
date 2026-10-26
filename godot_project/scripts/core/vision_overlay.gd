# ============================================================================
# VisionOverlay — 黑夜多光源渐变照明
# 职责：进夜激活雾罩（全屏黑暗）；多光源叠加照亮区域：
#       ① 灯塔灯室固定辉光 ② 灯塔旋转光束 ③ 玩家随身视野（被动/全局成长）
#       光源中心最亮（雾 alpha=0），边缘按 smooth 二次缓出衰减至 base_alpha
#       多光源取 max（最亮者决定该点可见度），实现由近及远渐变、边缘极致漆黑。
# 渲染：48 扇区 × N 径向段极坐标网格；每单元格四顶点独立 alpha，
#       draw_colored_polygon 自动插值形成平滑径向渐变。
# **两层渲染**（2026-10-23 用户反馈「灯塔的光束不能挡住下面视野，所有的光都不应该会
# 挡住下面内容」）：
#   · 雾罩层（本节点，MIX 混合，绝对 z=80）——负责「遮挡」，必须保持 MIX，
#     挂 ADD 会让黑夜彻底失效；
#   · 光效层（子节点 VisionLightFx，BLEND_MODE_ADD，绝对 z=81）——负责「提亮」，
#     画灯塔旋转光束楔形 + 命中闪光的底光/冲击环。加色只增亮不覆盖，
#     所以光束下面的地面 / 敌人 / 掉落物依旧清晰可见。
# 激活源两路（_refresh_active 合成）：
#   ① 进夜 set_night(true)（night_restricted 开启时）；
#   ② 事件视野惩罚（月食等，倍率 <1）。
# 数据：config/night.json vision（night_restricted / fog_color / fog_alpha /
#       player_base_vision_units / lighthouse_glow_units / lighthouse_glow_intensity /
#       falloff / radial_segments）
#       config/map.json lighthouse.beam（length_units / half_angle_deg / rotation_speed_deg
#       / color / alpha，由 World.set_light_source 注入）
#       PassiveSystem.get_vision_radius_units() × 60 = 玩家随身视野半径
# 红线：所有数值只读 config；昼日 clear_overlay 全关；挂 Player 下随父节点移动。
# ============================================================================
class_name VisionOverlay
extends Node2D

const SEGMENTS: int = 48
## 雾罩网格外半径下限（实际值按视口对角线自动放大，见 _compute_outer_radius）
const OUTER_RADIUS_MIN: float = 900.0
## 光效层（光束 / 命中闪光）的绝对层级：紧贴雾罩之上。
## 2026-10-23 用户反馈「灯塔的光束不能挡住下面视野，所有的光都不应该会挡住下面内容」：
## 雾罩必须保持 MIX 混合（否则黑夜直接失效），但光束/闪光这类**光**不能遮挡雾下的
## 地面与敌人，故单独拆一个 CanvasItem 挂 BLEND_MODE_ADD（只提亮、不覆盖）。
const _RENDER_Z := preload("res://scripts/core/render_z.gd")
const LIGHT_FX_Z_INDEX: int = _RENDER_Z.ABOVE_FOG
const _VISION_LIGHT_FX := preload("res://scripts/core/vision_light_fx.gd")

var _fog_color := Color(0.01, 0.02, 0.05, 0.98)
var _base_alpha: float = 0.98
var _active: bool = false
var _night_on: bool = false
## 视野限制总开关（night.json vision.enabled；false = 全图可见、无雾、无发光）
var _vision_enabled: bool = true

# ---- 网格缓存（以 Player 为中心的极坐标网格）----
var _radial_segments: int = 8
var _outer_radius: float = OUTER_RADIUS_MIN
var _last_viewport: Vector2 = Vector2.ZERO
var _grid_verts_local: Array[Vector2] = []
var _grid_cells: Array[Array] = []
var _grid_cache_valid: bool = false

# ---- 光源 ----
var _lighthouse_pos: Vector2 = Vector2.ZERO
var _lighthouse_glow_radius: float = 0.0
var _lighthouse_glow_intensity: float = 0.8
## 辉光核心亮区比例：半径的该比例内全亮（形成明确亮圈），之外按 falloff 渐变
var _lighthouse_glow_core_ratio: float = 0.55

var _light_origin: Vector2 = Vector2.ZERO
var _lamp_offset: Vector2 = Vector2.ZERO
var _beam_enabled: bool = false
var _beam_angle: float = 0.0
var _beam_length: float = 0.0
var _beam_half_angle: float = 0.0
var _beam_rotation_speed: float = 0.0
## 光束颜色（2026-10-23 用户反馈「光束不需要有颜色……加了颜色又看不清了」：
## 暖白改中性白——光效层是加色混合，暖色会把下方内容染糊；中性白只提亮不染色）
var _beam_color := Color(1.0, 1.0, 1.0, 0.5)

var _player_vision_radius: float = 0.0

## 散落光源（荧光藻/贝类/夜明珠；LightScatter 注入）
## 用 Packed 数组存储以加速每帧遍历（顶点数 × 光源数）
var _sl_pos: PackedVector2Array = PackedVector2Array()
var _sl_radius: PackedFloat32Array = PackedFloat32Array()
var _sl_intensity: PackedFloat32Array = PackedFloat32Array()
var _sl_core: PackedFloat32Array = PackedFloat32Array()

## 逐帧视口裁剪后的散落光源（只保留可能落在画面内的光源）。
## 光源数量提上去后，「顶点数 × 全部光源」会成为夜间主要热点，故每帧裁一次。
var _cull_active: bool = false
var _cv_pos: PackedVector2Array = PackedVector2Array()
var _cv_radius: PackedFloat32Array = PackedFloat32Array()
var _cv_intensity: PackedFloat32Array = PackedFloat32Array()
var _cv_core: PackedFloat32Array = PackedFloat32Array()

var _falloff: String = "smooth"
var _event_vision_mult: float = 1.0

# ---- 命中闪光（瞬态光源）----
# 2026-10-23 用户反馈「子弹击中敌人时应该给亮度显示出来」：
# 命中瞬间在命中点开一个短寿命光源，让藏在雾下的敌人被照亮、显形一下。
# 注意：**只画亮斑没用**——敌人本体在雾罩之下，亮斑会把它盖住；
# 必须真的参与照明计算（把雾开一个洞），敌人才看得见。
var _hit_radius: float = 108.0
var _hit_intensity: float = 1.0
var _hit_duration: float = 0.25
var _hit_max: int = 12
var _hit_core: float = 0.45
var _hit_color: Color = Color(1.0, 0.86, 0.55)
## 命中点（世界坐标）与剩余寿命，一一对应
var _hit_pos: PackedVector2Array = PackedVector2Array()
var _hit_ttl: PackedFloat32Array = PackedFloat32Array()
## 光效层（加色混合）：光束楔形 + 命中闪光，只提亮不遮挡雾下内容
var _light_fx: Node2D = null


func _ready() -> void:
	# 本节点是**玩家的子节点**（跟随相机）。Godot 的 z_index 默认相对父级
	# （z_as_relative=true），若保持相对，玩家本体抬高到雾罩之上时会把雾罩一起抬上去，
	# 等于没改。故这里改成**绝对层级**：雾罩恒定在 80。
	# 层级栈：地面/敌人 0 < 雾罩 80（绝对）< 光效层 81（加色）< 灯塔塔身 82
	#          < 散落光源 83（加色）< 玩家 84
	z_as_relative = false
	z_index = _RENDER_Z.FOG
	visible = false
	set_process(false)
	_apply_night_vision_config()
	_setup_light_fx()


## 光效层：独立 CanvasItem + BLEND_MODE_ADD。
## 不能给雾罩本体挂 ADD——那会让黑夜彻底失效（雾不再遮挡任何东西）。
func _setup_light_fx() -> void:
	if _light_fx != null and is_instance_valid(_light_fx):
		return
	var fx := (_VISION_LIGHT_FX.new() as Node2D)
	fx.name = "LightFx"
	if fx.has_method("bind"):
		fx.call("bind", self)
	fx.z_index = LIGHT_FX_Z_INDEX  # 层级常量单一来源在 RenderZ；光效层自身不硬编码
	add_child(fx)
	_light_fx = fx


## 统一的刷新入口：雾罩与光效层都要重画（光效层是子节点，不会随父节点自动重绘）
func _request_redraw() -> void:
	queue_redraw()
	if _light_fx != null and is_instance_valid(_light_fx):
		_light_fx.queue_redraw()


func _apply_night_vision_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_night_vision_config()
	# 总开关：false 时整个视野限制系统停用（雾罩不画、事件惩罚不生效、命中闪光不触发）
	_vision_enabled = bool(cfg.get("enabled", true))
	_fog_color = cfg.get("fog_color", Color(0.01, 0.02, 0.05)) as Color
	_base_alpha = clampf(float(cfg.get("fog_alpha", 0.98)), 0.0, 1.0)
	_fog_color.a = _base_alpha
	_radial_segments = maxi(3, int(cfg.get("radial_segments", 8)))
	_lighthouse_glow_radius = maxf(0.0, float(cfg.get("lighthouse_glow_radius_px", 0.0)))
	_lighthouse_glow_intensity = clampf(float(cfg.get("lighthouse_glow_intensity", 0.8)), 0.0, 1.0)
	_lighthouse_glow_core_ratio = clampf(float(cfg.get("lighthouse_glow_core_ratio", 0.55)), 0.0, 1.0)
	_falloff = String(cfg.get("falloff", "smooth"))
	_player_vision_radius = maxf(0.0, float(cfg.get("player_base_vision_radius_px", 0.0)))
	_hit_radius = maxf(0.0, float(cfg.get("hit_flash_radius_px", 108.0)))
	_hit_intensity = clampf(float(cfg.get("hit_flash_intensity", 1.0)), 0.0, 1.0)
	_hit_duration = maxf(0.02, float(cfg.get("hit_flash_duration", 0.3)))
	_hit_max = clampi(int(cfg.get("hit_flash_max", 12)), 1, 64)
	_hit_core = clampf(float(cfg.get("hit_flash_core_ratio", 0.45)), 0.0, 1.0)
	_hit_color = cfg.get("hit_flash_color", Color(1.0, 0.86, 0.55)) as Color
	_invalidate_grid_cache()


## 进夜 / 进昼（World 调）：夜视线限制激活源
## 2026-10-26 用户反馈「黑夜遮挡视线实际游戏体验影响不大，去掉所有发光、视线限制设定」：
## night.json vision.enabled=false 为总开关——关掉后进夜/事件惩罚/命中闪光全部不生效
func set_night(on: bool) -> void:
	var cfg: Dictionary = ConfigLoader.get_night_vision_config()
	_night_on = _vision_enabled and bool(on) and bool(cfg.get("night_restricted", true))
	_refresh_active()


## 按当前事件倍率刷新半径与激活态（World 进夜 begin_night 后调用）
func refresh_from_event() -> void:
	if not _vision_enabled:
		_event_vision_mult = 1.0
		_refresh_active()
		return
	_event_vision_mult = EventSystem.get_vision_mult()
	_refresh_active()


## 两个激活源合成：进夜（night_restricted 开启）或事件视野惩罚（月食等）
func _refresh_active() -> void:
	_active = _vision_enabled and (_night_on or _event_vision_mult < 0.999)
	visible = _active
	if _active:
		_rebuild_grid_if_needed()
	else:
		_grid_verts_local.clear()
		_grid_cells.clear()
		_grid_cache_valid = false
	set_process(_active and _beam_enabled and _beam_rotation_speed > 0.001)
	_request_redraw()


## 进昼 / 关遮罩：清激活态与进夜源
func clear_overlay() -> void:
	_night_on = false
	_active = false
	visible = false
	_grid_verts_local.clear()
	_grid_cells.clear()
	_grid_cache_valid = false
	# 命中闪光是夜间特效，进昼一并清掉（否则残留光源会在白天无意义地参与计算）
	_hit_pos.clear()
	_hit_ttl.clear()
	set_process(false)
	_request_redraw()


## 注入灯塔光源（World 在 _setup_lighthouse_collision 后调用；headless 机检可直接调）
func set_light_source(center: Vector2, beam_cfg: Dictionary) -> void:
	_light_origin = center
	_lamp_offset = Vector2(0.0, -ConfigLoader.get_lighthouse_lamp_height_px())
	_lighthouse_pos = _light_origin + _lamp_offset
	_beacon_from_cfg(beam_cfg)


func _beacon_from_cfg(beam_cfg: Dictionary) -> void:
	_beam_enabled = bool(beam_cfg.get("enabled", false))
	_beam_length = maxf(0.0, float(beam_cfg.get("length_px", 0.0)))
	_beam_half_angle = maxf(0.0, float(beam_cfg.get("half_angle_rad", 0.0)))
	_beam_rotation_speed = maxf(0.0, float(beam_cfg.get("rotation_speed", 0.0)))
	var col: Variant = beam_cfg.get("color", Color(1.0, 1.0, 1.0))
	if col is Color:
		_beam_color = (col as Color)
	var alpha: float = clampf(float(beam_cfg.get("alpha", 0.5)), 0.05, 1.0)
	_beam_color.a = alpha
	set_process(_active and _beam_enabled and _beam_rotation_speed > 0.001)


## 设置玩家随身视野半径（像素；被动/全局成长提供）
func set_player_vision_radius(radius_px: float) -> void:
	_player_vision_radius = maxf(0.0, radius_px)
	_request_redraw()


## 注入散落光源（LightScatter.get_light_data()）；世界坐标
func set_scattered_lights(lights: Array[Dictionary]) -> void:
	_sl_pos.clear()
	_sl_radius.clear()
	_sl_intensity.clear()
	_sl_core.clear()
	for L in lights:
		if not (L is Dictionary):
			continue
		var d: Dictionary = L as Dictionary
		_sl_pos.append(d.get("pos", Vector2.ZERO) as Vector2)
		_sl_radius.append(maxf(0.0, float(d.get("radius", 0.0))))
		_sl_intensity.append(clampf(float(d.get("intensity", 0.9)), 0.0, 1.0))
		_sl_core.append(clampf(float(d.get("core_ratio", 0.4)), 0.0, 1.0))
	_request_redraw()


## 机检：散落光源数量
func get_scattered_light_count() -> int:
	return _sl_pos.size()


## 命中闪光：在命中点开一个短寿命光源（世界坐标）。
## 同一帧多次命中会累积；超过 hit_flash_max 丢最旧的
## （灼烧 DoT 每跳都调也不会把数组撑爆，视觉上只是最近的命中在亮）。
func add_hit_flash(world_pos: Vector2) -> void:
	if not _active or _hit_radius <= 0.001 or _hit_duration <= 0.001:
		return
	while _hit_pos.size() >= _hit_max:
		_hit_pos.remove_at(0)
		_hit_ttl.remove_at(0)
	_hit_pos.append(world_pos)
	_hit_ttl.append(_hit_duration)
	# 光束未旋转时 process 是关的，这里显式打开才能逐帧衰减
	set_process(true)
	_request_redraw()


## 机检：当前活跃命中闪光数量
func get_hit_flash_count() -> int:
	return _hit_pos.size()


## 机检：命中闪光参数（配置是否生效）
func get_hit_flash_config() -> Dictionary:
	return {
		"radius": _hit_radius,
		"intensity": _hit_intensity,
		"duration": _hit_duration,
		"max": _hit_max,
		"core_ratio": _hit_core,
	}


## 当前有效最大视野半径（所有光源中的最大半径 × 事件倍率）
func get_vision_radius() -> float:
	var max_r: float = _player_vision_radius
	max_r = maxf(max_r, _lighthouse_glow_radius)
	if _beam_enabled:
		max_r = maxf(max_r, _beam_length)
	return max_r * _event_vision_mult


## 遮罩是否激活
func is_vision_restricted() -> bool:
	return _active


## 机检：光束状态
func get_beam_state() -> Dictionary:
	return {
		"enabled": _beam_enabled,
		"angle": _beam_angle,
		"length": _beam_length,
		"half_angle": _beam_half_angle,
	}


## 机检：世界坐标点是否被照亮（任意光源照明强度 > 0.35）
func is_point_lit(world_pos: Vector2) -> bool:
	if not _active:
		return true
	var player_pos: Vector2 = global_position
	var illumination: float = _compute_illumination(world_pos, player_pos)
	return illumination > 0.35


func _process(delta: float) -> void:
	var dirty: bool = false
	# 光束旋转（原逻辑；未启用光束时也要继续跑，见下）
	if _active and _beam_enabled and _beam_rotation_speed > 0.001:
		_beam_angle = wrapf(_beam_angle + _beam_rotation_speed * delta, 0.0, TAU)
		dirty = true
	# 命中闪光衰减（瞬态光源）
	if not _hit_ttl.is_empty():
		var i: int = _hit_ttl.size() - 1
		while i >= 0:
			_hit_ttl[i] = _hit_ttl[i] - delta
			if _hit_ttl[i] <= 0.0:
				_hit_ttl.remove_at(i)
				_hit_pos.remove_at(i)
			i -= 1
		dirty = true
		# 全部熄灭且光束本身不需要逐帧刷新 → 关掉 process，回到静默
		if _hit_ttl.is_empty() and not (_active and _beam_enabled and _beam_rotation_speed > 0.001):
			set_process(false)
	if dirty:
		_request_redraw()


func _invalidate_grid_cache() -> void:
	_grid_cache_valid = false


## 雾罩网格外半径：只需盖住视口（网格以玩家为中心 ≈ 屏幕中心）。
## 原固定 2400px 覆盖了 4800×4800 的区域，远超 1280×720 视口，
## 大部分顶点在屏幕外白算，且径向分辨率被摊薄。
func _compute_outer_radius() -> float:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return OUTER_RADIUS_MIN
	return maxf(OUTER_RADIUS_MIN, vp.length() * 0.5 + 80.0)


func _rebuild_grid_if_needed() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp != _last_viewport:
		_last_viewport = vp
		_grid_cache_valid = false
	if _grid_cache_valid and not _grid_verts_local.is_empty():
		return
	_grid_verts_local.clear()
	_grid_cells.clear()
	_outer_radius = _compute_outer_radius()

	var n_rings: int = _radial_segments + 1
	var dtheta: float = TAU / float(SEGMENTS)

	# 顶点按 ring 从内到外，每个 ring 上按角度
	# 2026-10-23 用户反馈「光线由近及远渐变」：径向改为**内密外疏**（平方律）。
	# 原均匀分段下 240px 灯塔亮圈只落在 1 个径向带内，渐变被压成 48 个三角面片
	# → 画面上出现放射状细条（棱面感）。平方律 + 外半径收紧到视口后，
	# 近处细到几像素，240px 亮圈可跨 7 个带，渐变平滑。
	for r in n_rings:
		var t: float = float(r) / float(_radial_segments)
		var radius: float = _outer_radius * t * t
		for s in SEGMENTS:
			var angle: float = float(s) * dtheta
			_grid_verts_local.append(Vector2(cos(angle), sin(angle)) * radius)

	# 单元格：每个单元格是 (ring, seg) 到 (ring+1, seg+1) 的四边形
	for r in _radial_segments:
		for s in SEGMENTS:
			var s_next: int = (s + 1) % SEGMENTS
			var i0: int = r * SEGMENTS + s
			var i1: int = r * SEGMENTS + s_next
			var i2: int = (r + 1) * SEGMENTS + s_next
			var i3: int = (r + 1) * SEGMENTS + s
			_grid_cells.append([i0, i1, i2, i3])

	_grid_cache_valid = true


func _draw() -> void:
	if not _active:
		return
	_rebuild_grid_if_needed()

	var player_pos: Vector2 = global_position
	_build_view_lights(player_pos)
	_cull_active = true

	# 预计算所有顶点的照明强度 → alpha
	var vert_alphas: Array[float] = []
	vert_alphas.resize(_grid_verts_local.size())
	for i in _grid_verts_local.size():
		var world_pos: Vector2 = player_pos + _grid_verts_local[i]
		var illum: float = _compute_illumination(world_pos, player_pos)
		vert_alphas[i] = _base_alpha * (1.0 - illum)

	# 画每个单元格（四顶点颜色不同 → draw_colored_polygon 自动插值渐变）
	for cell in _grid_cells:
		var i0: int = cell[0]
		var i1: int = cell[1]
		var i2: int = cell[2]
		var i3: int = cell[3]
		var pts := PackedVector2Array([
			_grid_verts_local[i0],
			_grid_verts_local[i1],
			_grid_verts_local[i2],
			_grid_verts_local[i3],
		])
		var cols := PackedColorArray([
			Color(_fog_color.r, _fog_color.g, _fog_color.b, vert_alphas[i0]),
			Color(_fog_color.r, _fog_color.g, _fog_color.b, vert_alphas[i1]),
			Color(_fog_color.r, _fog_color.g, _fog_color.b, vert_alphas[i2]),
			Color(_fog_color.r, _fog_color.g, _fog_color.b, vert_alphas[i3]),
		])
		draw_polygon(pts, cols)  # draw_polygon 支持多顶点颜色插值；draw_colored_polygon 只接受单色

	# 光效层单独重画（加色混合：只提亮，不遮挡雾下的地面/敌人/掉落物）
	if _light_fx != null and is_instance_valid(_light_fx):
		_light_fx.queue_redraw()

	# 绘制结束：外部再调 _compute_illumination（如 is_point_lit）必须用全量光源
	_cull_active = false


## 光效层绘制入口（由子节点 LightFx 的 _draw 回调）。
## 注意：draw_* 是 CanvasItem 方法，必须在**正在绘制的那个节点**上调用，
## 所以这里统一走 target.draw_*(...)。
func draw_light_fx(target: Node2D) -> void:
	if not _active or target == null:
		return
	# 光束楔形（加色：只在雾罩开洞处再提亮，不覆盖任何东西）
	if _beam_enabled and _beam_length > 0.001 and _beam_half_angle > 0.001:
		_draw_beam(target)
	# 命中闪光亮核（加色：命中点真的「亮一下」，不只是开雾）
	if not _hit_pos.is_empty():
		_draw_hit_flashes(target)


## 逐帧裁剪：只保留可能出现在画面内的散落光源
func _build_view_lights(player_pos: Vector2) -> void:
	_cv_pos.clear()
	_cv_radius.clear()
	_cv_intensity.clear()
	_cv_core.clear()
	var cull_r: float = _outer_radius + 160.0
	for i in _sl_pos.size():
		var r: float = _sl_radius[i]
		var reach: float = cull_r + r
		if _sl_pos[i].distance_squared_to(player_pos) <= reach * reach:
			_cv_pos.append(_sl_pos[i])
			_cv_radius.append(r)
			_cv_intensity.append(_sl_intensity[i])
			_cv_core.append(_sl_core[i])


## 计算某世界坐标点的照明强度（0.0=完全黑暗，1.0=完全照亮）
func _compute_illumination(world_pos: Vector2, player_pos: Vector2) -> float:
	var illum: float = 0.0
	var mult: float = _event_vision_mult

	# 1) 玩家随身视野
	if _player_vision_radius > 0.001 and mult > 0.001:
		var d: float = world_pos.distance_to(player_pos)
		var eff_r: float = _player_vision_radius * mult
		if d < eff_r:
			illum = maxf(illum, _falloff_intensity(d / eff_r))

	# 2) 灯塔灯室辉光（核心区全亮形成明确亮圈，外圈按 falloff 渐变）
	if _lighthouse_glow_radius > 0.001 and mult > 0.001:
		var d: float = world_pos.distance_to(_lighthouse_pos)
		var eff_r: float = _lighthouse_glow_radius * mult
		if d < eff_r:
			var t: float = d / eff_r
			var core: float = _lighthouse_glow_core_ratio
			var intensity: float = 1.0
			if t > core and core < 0.999:
				# 核心区外：从 1.0 按 falloff 衰减到 0（t=1 时）
				intensity = _falloff_intensity((t - core) / (1.0 - core))
			illum = maxf(illum, _lighthouse_glow_intensity * intensity)

	# 3) 灯塔光束
	if _beam_enabled and _beam_length > 0.001 and _beam_half_angle > 0.001 and mult > 0.001:
		var offset: Vector2 = world_pos - _lighthouse_pos
		var d: float = offset.length()
		var eff_len: float = _beam_length * mult
		if d < eff_len and d > 0.001:
			var diff: float = absf(wrapf(offset.angle() - _beam_angle, -PI, PI))
			if diff < _beam_half_angle:
				var length_t: float = d / eff_len
				var angle_t: float = diff / _beam_half_angle
				# 沿长度二次衰减 + 沿角度二次衰减 = 中心最亮
				var beam_intensity: float = (1.0 - length_t * length_t) * (1.0 - angle_t * angle_t)
				illum = maxf(illum, beam_intensity)

	# 4) 散落光源（荧光藻/贝类/夜明珠；LightScatter 注入）
	#    绘制时走视口裁剪后的子集（_cv_*），外部查询（is_point_lit）走全量（_sl_*）
	var sl_pos: PackedVector2Array = _cv_pos if _cull_active else _sl_pos
	var sl_rad: PackedFloat32Array = _cv_radius if _cull_active else _sl_radius
	var sl_int: PackedFloat32Array = _cv_intensity if _cull_active else _sl_intensity
	var sl_core: PackedFloat32Array = _cv_core if _cull_active else _sl_core
	for i in sl_pos.size():
		var eff_r: float = sl_rad[i] * mult
		if eff_r <= 0.001:
			continue
		var d: float = world_pos.distance_to(sl_pos[i])
		if d >= eff_r:
			continue
		var t: float = d / eff_r
		var core: float = sl_core[i]
		var inten: float = 1.0
		if t > core and core < 0.999:
			inten = _falloff_intensity((t - core) / (1.0 - core))
		illum = maxf(illum, sl_int[i] * inten)

	# 5) 命中闪光（瞬态光源，最多 _hit_max 个）
	#    强度随剩余寿命线性淡出；核心区全亮 → 外圈按 falloff 渐隐。
	for i in _hit_pos.size():
		var eff_r: float = _hit_radius * mult
		if eff_r <= 0.001:
			continue
		var d: float = world_pos.distance_to(_hit_pos[i])
		if d >= eff_r:
			continue
		var fade: float = clampf(_hit_ttl[i] / _hit_duration, 0.0, 1.0)
		var t: float = d / eff_r
		var hit_inten: float = 1.0
		if t > _hit_core and _hit_core < 0.999:
			hit_inten = _falloff_intensity((t - _hit_core) / (1.0 - _hit_core))
		illum = maxf(illum, _hit_intensity * hit_inten * fade)

	return clampf(illum, 0.0, 1.0)


func _falloff_intensity(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match _falloff:
		"linear":
			return 1.0 - t
		"inverse_square":
			return 1.0 / (1.0 + t * t * 3.0)
		_:
			# "smooth" 二次缓出
			return (1.0 - t) * (1.0 - t)


## 命中闪光视觉：**底光 + 冲击环**，刻意不在中心画高亮实心盘。
## 原因：敌人本体在雾罩之下，若在命中点盖一个高亮实心盘，等于把刚照亮的敌人又糊住；
## 中心留空 + 向外扩散的环，既读得出「打中了」，又不会遮挡目标。
## 2026-10-23 用户反馈「所有的光都不应该会挡住下面内容」→ 改到加色混合的光效层绘制。
func _draw_hit_flashes(target: Node2D) -> void:
	if _hit_pos.is_empty():
		return
	const FLASH_SEGS: int = 14
	for i in _hit_pos.size():
		var fade: float = clampf(_hit_ttl[i] / _hit_duration, 0.0, 1.0)
		if fade <= 0.001:
			continue
		var center: Vector2 = _hit_pos[i] - global_position
		# 环半径随淡出**向外扩散**（命中瞬间 0.45R → 熄灭时 1.0R），像冲击波
		var r: float = _hit_radius * (0.45 + 0.55 * (1.0 - fade))
		# ① 低强度暖色底光（只提亮氛围，alpha 低到不会盖住敌人剪影）
		var pts := PackedVector2Array([center])
		var cols := PackedColorArray([
			Color(_hit_color.r, _hit_color.g, _hit_color.b, 0.22 * fade),
		])
		for s in FLASH_SEGS:
			var ang: float = TAU * float(s) / float(FLASH_SEGS)
			pts.append(center + Vector2(cos(ang), sin(ang)) * r * 0.9)
			cols.append(Color(_hit_color.r, _hit_color.g, _hit_color.b, 0.0))
		target.draw_polygon(pts, cols)
		# ② 冲击环（中心透明，不遮目标）
		target.draw_arc(center, r, 0.0, TAU, 28,
			Color(_hit_color.r, _hit_color.g, _hit_color.b, 0.80 * fade), 2.5, true)


func _draw_beam(target: Node2D) -> void:
	var origin_local: Vector2 = _lighthouse_pos - global_position
	# 三层楔形：外宽内窄、越内越亮；顶点 alpha 从灯室 1.0 线性渐隐到远端 0.0。
	# 2026-10-23 用户反馈「人物有的时候会投射出光束，是哪里来的」——
	# 原实现是**等 alpha 的硬边楔形**（draw_colored_polygon 单色、远端一刀切），
	# 灯塔在屏幕外时光锥没有可见源头，看起来就像人物在打手电。
	# 改成沿长度 + 沿角度双向渐隐的柔光锥后，亮部始终聚在灯室（apex），
	# 远端与两侧自然消失，不再像一条从人身上射出的光柱。
	# 2026-10-23 第二轮「灯塔的光束不能挡住下面视野」→ 改到加色混合的光效层绘制：
	# 加色只提亮，地面/敌人/掉落物在光束下面依然清晰可见。
	var bands: Array[float] = [0.30, 0.55, 0.88]
	var shrinks: Array[float] = [1.0, 0.58, 0.26]
	const BEAM_ARC_SEGS: int = 12
	for bi in bands.size():
		var ha: float = _beam_half_angle * shrinks[bi]
		if ha <= 0.001:
			continue
		var a_apex: float = clampf(_beam_color.a * bands[bi] * 1.45, 0.0, 1.0)
		var pts := PackedVector2Array([origin_local])
		var cols := PackedColorArray([
			Color(_beam_color.r, _beam_color.g, _beam_color.b, a_apex),
		])
		for s in BEAM_ARC_SEGS + 1:
			var a: float = _beam_angle - ha + (2.0 * ha) * float(s) / float(BEAM_ARC_SEGS)
			pts.append(origin_local + Vector2(cos(a), sin(a)) * _beam_length)
			cols.append(Color(_beam_color.r, _beam_color.g, _beam_color.b, 0.0))
		target.draw_polygon(pts, cols)
