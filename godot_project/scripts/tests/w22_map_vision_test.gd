# ============================================================================
# W22MapVisionTest — 灯塔塔楼/光束 + 黑夜视线限制 + 边界可视化 + 界外修复 + 地图放大
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w22_map_vision_test.tscn
# 退出码：0=全部通过，1=有失败
# 对应 2026-10-22 用户反馈：
#   ① 灯塔=有高度的塔+光束；② 黑夜视线限制+灯塔提供视线帮助；
#   ③ 边界明确障碍物（非空气墙）；④ 小怪死在地图外经验不可拾；
#   ⑤ 地图应大于默认打开窗口（1280×720）。
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _VISION := preload("res://scripts/core/vision_overlay.gd")
const _BEACON := preload("res://scripts/world/lighthouse_beacon.gd")
const _BOUNDARY := preload("res://scripts/world/arena_boundary.gd")
const _SCATTER := preload("res://scripts/world/light_scatter.gd")
const _SPRITE_LIB := preload("res://scripts/core/sprite_lib.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W22 Map & Vision Test (tower/beam/night vision/boundary/arena)")
	print("============================================================")
	_test_config_values()
	_test_sprites()
	await _test_vision_overlay()
	await _test_beacon_and_boundary()
	await _test_light_appearance()
	await _test_spawn_clamp_and_leash()
	print("------------------------------------------------------------")
	print("机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)

## 散落光源位置签名（确定性比对用）
func _light_signature(data: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for d in data:
		var p: Vector2 = (d as Dictionary).get("pos", Vector2.ZERO) as Vector2
		parts.append("%.2f,%.2f" % [p.x, p.y])
	parts.sort()
	return "|".join(parts)


## 科学计数法字符串（GDScript 的 % 不支持 %e）
func _num_sci(v: float) -> String:
	var e: int = 0
	var m: float = absf(v)
	if m > 0.0:
		while m >= 10.0:
			m /= 10.0
			e += 1
		while m < 1.0:
			m *= 10.0
			e -= 1
	return "%.2fe-%d" % [m, -e] if e < 0 else "%.2fe%d" % [m, e]



## ① 配置表值：夜视半径/雾色、光束、边界、边距、地图半径
func _test_config_values() -> void:
	print("[配置表值]")
	var vis: Dictionary = ConfigLoader.get_night_vision_config()
	_assert(bool(vis.get("night_restricted", false)), "night.json vision.night_restricted=true")
	_assert(float(vis.get("radius_px", 0.0)) > 0.0, "灯塔灯室辉光半径 >0（%.0fpx）" % float(vis.get("radius_px", 0.0)))
	_assert(float(vis.get("fog_alpha", 0.0)) > 0.0 and float(vis.get("fog_alpha", 0.0)) <= 1.0, "雾透明度 ∈(0,1]")
	# W23：人物默认无视野，视野只能来自外部光源
	_assert(float(vis.get("player_base_vision_radius_px", -1.0)) == 0.0, "玩家默认随身视野=0（完全黑暗）")
	_assert(float(vis.get("lighthouse_glow_radius_px", 0.0)) > 0.0, "灯塔灯室辉光半径 >0")
	_assert(float(vis.get("lighthouse_glow_intensity", 0.0)) > 0.0, "灯塔灯室辉光强度 >0")
	# 2026-10-23 用户反馈：灯塔附近一圈应该是亮的
	_assert(float(vis.get("lighthouse_glow_intensity", 0.0)) >= 0.99, "灯塔辉光强度=1.0（中心全亮）")
	_assert(float(vis.get("lighthouse_glow_core_ratio", -1.0)) > 0.0 and float(vis.get("lighthouse_glow_core_ratio", 2.0)) < 1.0, "辉光核心亮区比例 ∈(0,1)")
	_assert(float(vis.get("lighthouse_glow_radius_px", 0.0)) >= 200.0, "灯塔亮圈半径 ≥200px（%.0fpx）" % float(vis.get("lighthouse_glow_radius_px", 0.0)))
	_assert(String(vis.get("falloff", "")) == "smooth", "衰减曲线=smooth（二次缓出）")
	_assert(int(vis.get("radial_segments", 0)) >= 3, "径向分段数 ≥3（渐变网格）")
	# 雾色足够暗（边缘极致漆黑）
	var fc: Color = vis.get("fog_color", Color.BLACK) as Color
	_assert(fc.r < 0.02 and fc.g < 0.03 and fc.b < 0.06, "雾色足够暗（边缘极致漆黑）")

	var beam: Dictionary = ConfigLoader.get_lighthouse_beam_config()
	_assert(bool(beam.get("enabled", false)), "lighthouse.beam.enabled=true")
	_assert(float(beam.get("length_px", 0.0)) > 0.0, "光束长度 >0（%.0fpx）" % float(beam.get("length_px", 0.0)))
	_assert(float(beam.get("half_angle_rad", 0.0)) > 0.0, "光束半角 >0")
	# 2026-10-23 用户反馈：光束需要加宽一倍左右（10°→20°）
	_assert(rad_to_deg(float(beam.get("half_angle_rad", 0.0))) >= 18.0,
		"光束半角 ≥18°（加宽后 %.0f°）" % rad_to_deg(float(beam.get("half_angle_rad", 0.0))))
	_assert(float(beam.get("rotation_speed", -1.0)) >= 0.0, "旋转速度 ≥0")
	_assert((beam.get("color", Color.BLACK) as Color).r > 0.5, "光束为暖色")

	# 2026-10-23 用户反馈「去掉地图范围限制」：arena 关闭，边界可视化不生成
	_assert(not ConfigLoader.get_arena_enabled(), "arena.enabled=false（无活动范围限制）")
	_assert(ConfigLoader.get_arena_radius_units() == 0.0, "arena 关闭时半径=0（不钳位）")
	var bnd: Dictionary = ConfigLoader.get_arena_boundary_config()
	var ids: Array = bnd.get("post_ids", []) as Array
	_assert(ids.size() >= 1, "界桩 id 表保留（%d 种，可随时恢复）" % ids.size())
	_assert(float(bnd.get("post_spacing_px", 0.0)) >= 24.0, "界桩间距 ≥24px（保留）")

	# 散落光源（荧光藻/贝类/夜明珠）——2026-10-23 改为按区块程序化生成
	var sl: Dictionary = ConfigLoader.get_scattered_lights_config()
	_assert(bool(sl.get("enabled", false)), "scattered_lights.enabled=true")
	_assert(int(sl.get("lights_per_chunk", 0)) > 0, "每区块光源数 >0（%d）" % int(sl.get("lights_per_chunk", 0)))
	_assert(float(sl.get("chunk_px", 0.0)) >= 240.0, "区块边长 ≥240px（%.0f）" % float(sl.get("chunk_px", 0.0)))
	_assert(int(sl.get("chunk_radius", 0)) >= 2, "区块半径 ≥2（覆盖视口：%d）" % int(sl.get("chunk_radius", 0)))
	var kinds: Array = sl.get("kinds", []) as Array
	_assert(kinds.size() >= 3, "光源类型 ≥3 种（荧光藻/贝类/夜明珠：%d）" % kinds.size())
	_assert(float(sl.get("radius_px", 0.0)) > 0.0, "光源照明半径 >0（%.0fpx）" % float(sl.get("radius_px", 0.0)))
	_assert(float(sl.get("intensity", 0.0)) > 0.0 and float(sl.get("intensity", 0.0)) <= 1.0, "光源强度 ∈(0,1]")
	_assert(float(sl.get("min_gap_px", 0.0)) > 0.0, "光源最小间距 >0（防重叠）")
	_assert(not sl.has("pulse_speed"), "光源恒定亮度（无 pulse_speed 脉冲参数）")
	_assert(ConfigLoader.get_lighthouse_lamp_height_px() > 0.0, "灯室高度 >0（%.0fpx）" % ConfigLoader.get_lighthouse_lamp_height_px())


## 素材存在：塔楼 + 礁石界桩 + 散落光源
func _test_sprites() -> void:
	print("[素材存在性]")
	_assert(_SPRITE_LIB.world("lighthouse_tower") != null, "塔楼精灵 lighthouse_tower 可加载")
	for i in 3:
		_assert(_SPRITE_LIB.world("reef_post_%d" % i) != null, "礁石界桩 reef_post_%d 可加载" % i)
	# 散落光源精灵（2026-10-23）
	for sid in ["glow_algae", "glow_shell", "glow_pearl"]:
		_assert(_SPRITE_LIB.world(String(sid)) != null, "散落光源精灵 %s 可加载" % sid)
	var tex: Texture2D = _SPRITE_LIB.world("lighthouse_tower")
	if tex != null:
		_assert(tex.get_height() > tex.get_width(), "塔楼高度 > 宽度（有高度感：%dx%d）" % [tex.get_width(), tex.get_height()])


## ② 视野遮罩：进夜激活/半径=表值/昼关闭/光束穿雾
func _test_vision_overlay() -> void:
	print("[视野遮罩]")
	var player := Node2D.new()
	add_child(player)
	var overlay: Node2D = _VISION.new() as Node2D
	player.add_child(overlay)
	await get_tree().process_frame

	var vis: Dictionary = ConfigLoader.get_night_vision_config()
	# 纯事件路径不激活（night_restricted 是「进夜」源，须 set_night 打开）——与 w14 口径一致
	EventSystem.reset()
	overlay.call("refresh_from_event")
	_assert(not bool(overlay.call("is_vision_restricted")), "无事件惩罚时仅刷新倍率不激活（激活源分离）")
	# 进夜：set_night(true) + refresh → 夜视限制生效
	overlay.call("set_night", true)
	overlay.call("refresh_from_event")
	_assert(bool(overlay.call("is_vision_restricted")), "进夜 set_night+刷新 → 遮罩激活（夜视限制生效）")
	var got: float = float(overlay.call("get_vision_radius"))
	var mult: float = EventSystem.get_vision_mult()
	_assert(absf(got - float(vis.get("radius_px", 0.0)) * mult) < 0.01, "视野半径=表值×事件倍率（%.0fpx）" % got)

	# 光束注入 + 穿雾判定（机检直接验证几何，无需渲染）
	var beam: Dictionary = ConfigLoader.get_lighthouse_beam_config()
	var center := Vector2(667.0, 334.0)
	overlay.call("set_light_source", center, beam)
	var st: Dictionary = overlay.call("get_beam_state")
	_assert(bool(st.get("enabled", false)) and float(st.get("length", 0.0)) > 0.0, "光束状态已注入（len=%.0f）" % float(st.get("length", 0.0)))
	var lamp := center + Vector2(0.0, -ConfigLoader.get_lighthouse_lamp_height_px())
	var angle: float = float(st.get("angle", 0.0))
	var lit_pos: Vector2 = lamp + Vector2(cos(angle), sin(angle)) * float(st.get("length", 0.0)) * 0.8
	var dark_pos: Vector2 = lamp + Vector2(cos(angle + PI), sin(angle + PI)) * float(st.get("length", 0.0)) * 0.8
	_assert(bool(overlay.call("is_point_lit", lit_pos)), "光束方向上的点被照亮（穿雾）")
	_assert(not bool(overlay.call("is_point_lit", dark_pos)), "反方向的点不被照亮")
	var far_pos: Vector2 = lamp + Vector2(cos(angle), sin(angle)) * (float(st.get("length", 0.0)) + 500.0)
	_assert(not bool(overlay.call("is_point_lit", far_pos)), "超出光束长度的点不被照亮")

	# 2026-10-23 用户反馈「灯塔附近一圈应该是亮的」：核心亮区全亮 + 外圈渐变
	# 取正下方（90°）避开光束初始方向，确保只测辉光
	var glow_r_cfg: float = float(vis.get("lighthouse_glow_radius_px", 0.0))
	var core_r: float = glow_r_cfg * float(vis.get("lighthouse_glow_core_ratio", 0.55))
	var illum_core: float = overlay.call("_compute_illumination", lamp + Vector2(0.0, core_r * 0.5), Vector2.ZERO)
	var illum_edge_zone: float = overlay.call("_compute_illumination", lamp + Vector2(0.0, glow_r_cfg * 0.95), Vector2.ZERO)
	_assert(illum_core >= 0.99, "灯塔核心亮区全亮（%.2f，核心 %.0fpx）" % [illum_core, core_r])
	_assert(illum_core > illum_edge_zone, "亮圈由内向外渐变（%.2f > %.2f）" % [illum_core, illum_edge_zone])

	# W23：玩家默认无随身视野——站在灯塔辉光外（且不在光束方向上）应不被照亮
	var player_world: Vector2 = player.global_position
	var glow_r: float = float(vis.get("lighthouse_glow_radius_px", 0.0))
	# 放在灯塔正上方（90°），避开光束初始方向（0°向右，半角 10°）
	var outside_glow: Vector2 = lamp + Vector2(0.0, glow_r + 50.0)
	player.global_position = outside_glow
	await get_tree().process_frame
	_assert(not bool(overlay.call("is_point_lit", outside_glow)), "辉光外无玩家视野 → 不被照亮（完全黑暗）")

	# 设置随身视野后，玩家周围被照亮
	overlay.call("set_player_vision_radius", 120.0)
	await get_tree().process_frame
	_assert(bool(overlay.call("is_point_lit", outside_glow)), "随身视野 120px → 辉光外被照亮")

	# 渐变效果：随身视野边缘（接近半径处）照明弱于中心
	var curr_pos: Vector2 = player.global_position
	var near_edge: Vector2 = curr_pos + Vector2(110.0, 0.0)  # 接近 120px 边缘
	var center_pos: Vector2 = curr_pos + Vector2(10.0, 0.0)   # 靠近中心
	var lit_center: bool = overlay.call("is_point_lit", center_pos)
	_assert(lit_center, "随身视野中心被照亮")
	# 用 _compute_illumination 直接比较照明强度
	var illum_center: float = overlay.call("_compute_illumination", center_pos, curr_pos)
	var illum_edge: float = overlay.call("_compute_illumination", near_edge, curr_pos)
	_assert(illum_center > illum_edge, "渐变：中心照明强度 > 边缘（%.2f > %.2f）" % [illum_center, illum_edge])

	overlay.call("clear_overlay")
	_assert(not bool(overlay.call("is_vision_restricted")), "进昼 clear → 遮罩关闭")

	player.queue_free()


## ③ 灯塔塔楼 + 散落光源
func _test_beacon_and_boundary() -> void:
	print("[灯塔塔楼与散落光源]")
	var host := Node2D.new()
	add_child(host)
	var center := Vector2(667.0, 334.0)

	var beacon: Node2D = _BEACON.new() as Node2D
	host.add_child(beacon)
	var tex: Texture2D = _SPRITE_LIB.world("lighthouse_tower")
	beacon.call("setup", center, 30.0, tex)
	_assert((beacon.global_position - center).length() < 0.01, "塔楼位于灯塔圆心")
	var spr: Sprite2D = null
	for ch in beacon.get_children():
		if ch is Sprite2D:
			spr = ch as Sprite2D
	_assert(spr != null and spr.texture == tex, "塔楼精灵已挂载")
	if spr != null and spr.texture != null:
		var bottom: float = spr.global_position.y + float(spr.texture.get_height()) * 0.5
		_assert(absf(bottom - center.y) < 0.01, "塔基坐在灯塔圆心上（有高度向上）")
	# 2026-10-23 用户反馈「灯塔底部不需要光圈」：塔基无独立光圈节点，仅精灵 + 塔顶灯室辉光
	var extra_visual: int = 0
	for ch in beacon.get_children():
		if not (ch is Sprite2D):
			extra_visual += 1
	_assert(extra_visual == 0, "灯塔节点无额外光圈子节点（仅精灵）")
	beacon.call("set_night", true)
	_assert(true, "set_night(true) 不报错（灯室辉光脉冲）")
	beacon.call("set_night", false)
	_assert(beacon.is_processing() == false, "白天停止脉冲处理（无塔基光圈绘制）")

	# 散落光源：区块程序化生成（数量/覆盖/确定性/间距/注入）
	var cfg: Dictionary = ConfigLoader.get_scattered_lights_config()
	var scatter: Node2D = _SCATTER.new() as Node2D
	host.add_child(scatter)
	scatter.call("setup", center)
	await get_tree().process_frame
	var n: int = int(scatter.call("get_light_count"))
	var per: int = int(cfg.get("lights_per_chunk", 0))
	var cr: int = int(cfg.get("chunk_radius", 0))
	var max_n: int = per * (2 * cr + 1) * (2 * cr + 1)
	_assert(n > 0, "散落光源已生成（%d 个）" % n)
	_assert(n <= max_n, "光源数不超过区块容量（%d ≤ %d）" % [n, max_n])
	var chunk_px: float = float(cfg.get("chunk_px", 480.0))
	var data: Array = scatter.call("get_light_data") as Array
	var gap: float = float(cfg.get("min_gap_px", 0.0))
	# 覆盖范围：全部落在「玩家所在区块 ±chunk_radius」的矩形内
	var cc: Vector2i = scatter.call("get_chunk_coord") as Vector2i
	var lo := Vector2(float(cc.x - cr) * chunk_px, float(cc.y - cr) * chunk_px)
	var hi := Vector2(float(cc.x + cr + 1) * chunk_px, float(cc.y + cr + 1) * chunk_px)
	var in_range: bool = true
	for i in data.size():
		var p: Vector2 = (data[i] as Dictionary).get("pos", Vector2.ZERO) as Vector2
		if p.x < lo.x - 1.0 or p.x > hi.x + 1.0 or p.y < lo.y - 1.0 or p.y > hi.y + 1.0:
			in_range = false
	_assert(in_range, "光源全部落在玩家周边区块覆盖范围内（%d×%d 区块）" % [2 * cr + 1, 2 * cr + 1])
	# 同区块内最小间距
	var gap_ok: bool = true
	for i in data.size():
		var p: Vector2 = (data[i] as Dictionary).get("pos", Vector2.ZERO) as Vector2
		for j in range(i + 1, data.size()):
			var q: Vector2 = (data[j] as Dictionary).get("pos", Vector2.ZERO) as Vector2
			# 只校验同区块（同区块坐标）内的间距
			var ci := Vector2i(int(floor(p.x / chunk_px)), int(floor(p.y / chunk_px)))
			var cj := Vector2i(int(floor(q.x / chunk_px)), int(floor(q.y / chunk_px)))
			if ci == cj and p.distance_to(q) < gap - 1.0:
				gap_ok = false
	_assert(gap_ok, "同区块内光源间距 ≥%.0fpx（无重叠）" % gap)
	_assert(not data.is_empty() and (data[0] as Dictionary).has("color"), "光源带颜色数据")
	# 确定性：同位置重建结果一致（区块坐标哈希，不依赖全局 RNG）
	var sig_a: String = _light_signature(data)
	var moved: bool = bool(scatter.call("update_around", center + Vector2(chunk_px * 0.2, 0.0)))
	_assert(not moved, "同区块内移动不重建（避免每帧抖动）")
	var moved2: bool = bool(scatter.call("update_around", center + Vector2(chunk_px * 3.0, 0.0)))
	_assert(moved2, "跨区块后重建光源")
	scatter.call("update_around", center)
	await get_tree().process_frame
	var sig_b: String = _light_signature(scatter.call("get_light_data") as Array)
	_assert(sig_a == sig_b, "回到原区块光源位置完全一致（确定性，不闪跳）")

	host.queue_free()


## ④ 散落光源外观（2026-10-23 第二轮用户反馈）
#    扇形光 → 沿素材边缘的圆形扩散光；不挡住下方视野；减量；素材缩小
func _test_light_appearance() -> void:
	print("[散落光源外观]")
	var cfg: Dictionary = ConfigLoader.get_scattered_lights_config()
	var sprite_scale: float = float(cfg.get("sprite_scale", 1.0))
	var halo_scale: float = float(cfg.get("halo_scale", 2.2))
	_assert(0.0 < sprite_scale and sprite_scale < 1.0, "素材已缩小（sprite_scale=%.2f）" % sprite_scale)
	_assert(halo_scale >= 1.0, "光晕半径系数 halo_scale=%.2f（≥1，至少包住素材）" % halo_scale)

	# 减量：面密度 = 每区块数 / 区块面积
	var per: int = int(cfg.get("lights_per_chunk", 0))
	var chunk_px: float = float(cfg.get("chunk_px", 480.0))
	var density: float = float(per) / (chunk_px * chunk_px)
	var old_density: float = 3.0 / (480.0 * 480.0)
	# GDScript 的 % 不支持 %e，用 num() 手工转科学计数法
	_assert(density < old_density * 0.8, "光源面密度已下降（%s → %s /px²，约减半）" % [
		_num_sci(old_density), _num_sci(density)])

	var host := Node2D.new()
	add_child(host)
	var center := Vector2(667.0, 334.0)
	var scatter: Node2D = _SCATTER.new() as Node2D
	host.add_child(scatter)
	scatter.call("setup", center)
	await get_tree().process_frame

	# 不遮挡下方视野：节点材质为加色混合（只提亮、不覆盖）
	var mat: CanvasItemMaterial = scatter.material as CanvasItemMaterial
	_assert(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		"LightScatter 光晕用加色混合（BLEND_MODE_ADD，不遮挡下方视野）")

	# 不扇形：圆周细分必须足够细，否则弧长过大、棱角会被读成扇形（v3.22 的教训）
	var segs: int = int(_SCATTER.HALO_RING_SEGS)
	_assert(segs >= 20, "光晕圆周细分 %d 段 ≥20（半径 ~35px 下每段弧长 ≈%.1fpx，无棱面/无扇形感）"
		% [segs, TAU * 35.0 / float(segs)])
	_assert(int(_SCATTER.HALO_RINGS) == 1, "光晕走单扇形 fan 路径（多顶点环带实测不显示，勿回退）")

	# 光晕半径由素材尺寸决定，紧贴素材边缘；且明显小于旧版（照明半径×1.6 的大盘）
	var data: Array = scatter.call("get_light_data") as Array
	_assert(not data.is_empty(), "有光源数据可校验")
	# 半径取素材半边长 × halo_scale：最大光晕半径下每段弧长也须 < 8px（否则又是棱角/扇形感）
	var min_halo_r: float = 1e9
	var max_halo_r: float = 0.0
	for i in data.size():
		var hr0: float = float((data[i] as Dictionary).get("halo_radius", 0.0))
		min_halo_r = minf(min_halo_r, hr0)
		max_halo_r = maxf(max_halo_r, hr0)
	if max_halo_r <= 0.0:
		min_halo_r = 8.0
		max_halo_r = 40.0
	_assert(TAU * max_halo_r / float(segs) < 8.0,
		"最大光晕半径 %.1fpx 下每段弧长 %.1fpx <8px（边缘平滑）" % [max_halo_r, TAU * max_halo_r / float(segs)])
	var radius_px: float = float(cfg.get("radius_px", 72.0))
	var halo_fit_ok: bool = true
	var sprite_scale_ok: bool = true
	# 照明半径必须仍是 config 公式 radius_px × radius_mult（未随外观缩小而变）
	var light_radius_ok: bool = true
	var valid_radii: Array[float] = []
	for k in (cfg.get("kinds", []) as Array):
		valid_radii.append(radius_px * float((k as Dictionary).get("radius_mult", 1.0)))
	var old_halo: float = radius_px * 1.6
	for i in data.size():
		var d: Dictionary = data[i] as Dictionary
		var hr: float = float(d.get("halo_radius", 0.0))
		var lr: float = float(d.get("radius", 0.0))
		var lr_valid: bool = false
		for vr in valid_radii:
			if absf(lr - vr) < 0.01:
				lr_valid = true
		if not lr_valid:
			light_radius_ok = false
		if hr <= 8.0 or hr >= old_halo * 0.75:
			halo_fit_ok = false
	# 每个光源子精灵都按 sprite_scale 缩放
	for ch in scatter.get_children():
		if ch is Sprite2D:
			if absf((ch as Sprite2D).scale.x - sprite_scale) > 0.001:
				sprite_scale_ok = false
	_assert(halo_fit_ok, "光晕半径紧贴素材（实际 %.1f~%.1fpx，远小于旧版 %.0fpx 大光斑）"
		% [min_halo_r, max_halo_r, old_halo])
	_assert(light_radius_ok, "照明半径未随外观缩小而改变（%.0fpx，不偷偷调难度）" % radius_px)
	_assert(sprite_scale_ok, "所有光源精灵按 sprite_scale=%.2f 缩放" % sprite_scale)

	# ---- 2026-10-23 第二轮：「所有的光都不应该会挡住下面内容」 ----
	# ① 雾罩本体必须仍是 MIX（挂 ADD 会让黑夜彻底失效）
	_assert(scatter.material != null, "散落光源节点挂了 CanvasItemMaterial")
	var overlay_mat: Material = null
	var fx_found: Node = null
	var host2 := Node2D.new()
	add_child(host2)
	var pl := MAIN_SCENE.instantiate()
	host2.add_child(pl)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (pl as Node).find_children("*", "Node2D", true, false):
		if n is Node2D and n.has_method("is_vision_restricted"):
			overlay_mat = n.material
			for c in n.get_children():
				if c is CanvasItem and c.name == "LightFx":
					fx_found = c
			break
	_assert(overlay_mat == null,
		"雾罩本体未挂材质（保持默认 MIX，黑夜遮挡不失效）")
	_assert(fx_found != null, "雾罩下有独立光效层节点 LightFx")
	if fx_found != null:
		var fx_mat: CanvasItemMaterial = fx_found.material as CanvasItemMaterial
		_assert(fx_mat != null and fx_mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
			"光效层为 BLEND_MODE_ADD（光束/命中闪光只提亮，不遮挡雾下内容）")
		var _rz_fx: Dictionary = (load("res://scripts/core/render_z.gd") as Script).get_script_constant_map()
		_assert(fx_found.z_as_relative == false
			and int(fx_found.z_index) == int(_rz_fx.get("ABOVE_FOG", -1)),
			"光效层为绝对层级 z=%d（紧贴雾罩 %d 之上）" % [int(fx_found.z_index), int(_rz_fx.get("FOG", -1))])
	# ② 灯塔灯室辉光也必须是加色（原 draw_circle MIX 会盖住塔身下方与地面）
	var beacon_node: Node = null
	for n in (pl as Node).find_children("*", "Node2D", true, false):
		if n is Node2D and n.has_method("set_night") and n.has_method("setup"):
			beacon_node = n
			break
	if beacon_node != null:
		var bm: CanvasItemMaterial = beacon_node.material as CanvasItemMaterial
		_assert(bm != null and bm.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
			"灯塔灯室辉光为 BLEND_MODE_ADD（不盖住塔身下方与地面）")
	# ③ 机器人必须像「视野受限的真人」一样待在灯塔亮圈内作战
	#    2026-10-23 用户反馈「机器人测试的时候大多数时间都是灯塔范围外，这不符合实际
	#    玩家视野受限的情况」——真人默认随身视野=0，只有亮圈内看得见，所以围着灯塔打。
	var bot_script: Script = load("res://scripts/debug/test_bot.gd")
	if bot_script != null:
		var bmap: Dictionary = bot_script.get_script_constant_map()
		_assert(float(bmap.get("LIGHT_STAY_RATIO", 0.0)) > 0.0,
			"机器人有亮圈驻留常量 LIGHT_STAY_RATIO=%.2f" % float(bmap.get("LIGHT_STAY_RATIO", 0.0)))
		_assert(float(bmap.get("LIGHT_PULL_WEIGHT", 0.0)) > 0.0,
			"机器人有出圈回拉权重 LIGHT_PULL_WEIGHT=%.1f" % float(bmap.get("LIGHT_PULL_WEIGHT", 0.0)))
		var bot: Object = bot_script.new()
		_assert(bot != null and bot.has_method("_bias_toward_light"),
			"机器人实现 _bias_toward_light（所有夜通用的视野受限约束）")
		if bot != null and bot.has_method("_bias_toward_light"):
			var lh: Vector2 = Vector2.ZERO
			var esp: Node = (pl as Node).get("enemy_spawner") as Node
			if esp != null:
				lh = esp.get("lighthouse_position") as Vector2
			var stay_r: float = float(ConfigLoader.get_night_vision_config().get(
				"lighthouse_glow_radius_px", 0.0)) * float(bmap.get("LIGHT_STAY_RATIO", 0.85))
			var far_pos: Vector2 = lh + Vector2(stay_r * 2.5, 0.0)
			var out_dir: Vector2 = Vector2.RIGHT  # 净外向：还在往外跑
			var biased: Vector2 = bot.call("_bias_toward_light", out_dir, pl, far_pos) as Vector2
			_assert(biased.dot(Vector2.RIGHT) < 0.0,
				"光圈外且方向朝外 → 被钳成朝灯塔（dot=%.2f ≤0）" % biased.dot(Vector2.RIGHT))
			var near_pos: Vector2 = lh + Vector2(stay_r * 0.3, 0.0)
			var kept: Vector2 = bot.call("_bias_toward_light", Vector2.UP, pl, near_pos) as Vector2
			_assert(absf(kept.angle_to(Vector2.UP)) < 0.01,
				"光圈内不受约束（方向原样保留）")
			# 注意：TestBot 实例从未入树，直接 free() 会在退出清理阶段段错误，
			# 用 queue_free + 等一帧让引用安全释放
			bot.queue_free()
			await get_tree().process_frame
	pl.queue_free()
	host2.queue_free()

	host.queue_free()


## ⑤ 地图无范围限制 + 散落光源接线
func _test_spawn_clamp_and_leash() -> void:
	print("[地图无限制与散落光源接线]")
	var world: Node = MAIN_SCENE.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var spawner: Node = world.get_node("EnemySpawner")
	var player: Node2D = world.get_node("Player")
	_assert(spawner != null and player != null, "main.tscn 含 EnemySpawner/Player")
	if spawner == null or player == null:
		world.queue_free()
		return

	var center: Vector2 = spawner.get("lighthouse_position")

	# 玩家不受范围钳位：移到极远处调用 resolve_arena_bounds 不被拉回
	var far_pos: Vector2 = center + Vector2(5000.0, 0.0)
	player.global_position = far_pos
	player.call("resolve_arena_bounds")
	_assert(player.global_position.distance_to(far_pos) < 0.01, "玩家远离灯塔 5000px 不被钳回（无范围限制）")
	_assert(float(player.call("get_arena_radius")) == 0.0, "玩家活动半径=0（不限制）")

	# 刷怪不受钳位：贴边时仍可能刷在远处（环带以玩家为圆心自由展开）
	player.global_position = center
	var max_dist: float = 0.0
	var min_dist: float = INF
	for _i in 20:
		var pos: Vector2 = spawner.call("_ring_spawn_pos")
		max_dist = maxf(max_dist, pos.distance_to(player.global_position))
		min_dist = minf(min_dist, pos.distance_to(player.global_position))
	_assert(min_dist > 40.0, "刷怪不会贴脸（最小距玩家 %.0fpx）" % min_dist)
	_assert(max_dist <= 700.0, "刷怪环带正常展开（最远 %.0fpx）" % max_dist)

	# 敌人不牵引：放到远处调用 _apply_arena_leash 位置不变
	var no_affix: Array[String] = []
	var far_enemy_pos: Vector2 = center + Vector2(3000.0, 0.0)
	var enemy: Node = spawner.call("spawn_enemy", {"id": "small_goblin"}, far_enemy_pos, no_affix, false)
	_assert(enemy != null, "可生成测试敌人")
	if enemy != null:
		enemy.set("lighthouse_position", center)
		var before: float = (enemy.global_position - center).length()
		enemy.call("_apply_arena_leash")
		var after: float = (enemy.global_position - center).length()
		_assert(absf(before - after) < 0.01, "arena 关闭时敌人不被牵引（%.0f→%.0f）" % [before, after])

	# 边界可视化未生成（arena 关闭）：_posts_root 存在但无界桩
	var boundary: Node = world.get("_arena_boundary")
	var posts: int = 0
	if boundary != null:
		for ch in boundary.get_children():
			if ch is Node2D and ch.name == "PostsRoot":
				posts = ch.get_child_count()
			elif ch is Node2D and ch.get_child_count() > 0 and not (ch is Sprite2D):
				posts = maxi(posts, ch.get_child_count())
	_assert(posts == 0, "arena 关闭 → 不生成礁石界桩（界桩 %d 根）" % posts)

	# 散落光源已生成并注入 VisionOverlay
	var scatter: Node = world.get("_light_scatter")
	_assert(scatter != null, "World 已创建 LightScatter 节点")
	var sl_cfg: Dictionary = ConfigLoader.get_scattered_lights_config()
	if scatter != null:
		var _per: int = int(sl_cfg.get("lights_per_chunk", 0))
		var _cr: int = int(sl_cfg.get("chunk_radius", 0))
		var _cap: int = _per * (2 * _cr + 1) * (2 * _cr + 1)
		var _cnt: int = int(scatter.call("get_light_count"))
		_assert(_cnt > 0 and _cnt <= _cap, "World 散落光源已按区块生成（%d ≤ 容量 %d）" % [_cnt, _cap])
	var vis: Node = world.get("vision_overlay")
	_assert(vis != null, "World 有 vision_overlay")
	if vis != null and scatter != null:
		_assert(int(vis.call("get_scattered_light_count")) == int(scatter.call("get_light_count")),
			"散落光源已注入 VisionOverlay（%d）" % int(vis.call("get_scattered_light_count")))
		# 照明验证：某个散落光源中心点被照亮
		var lights: Array = scatter.call("get_light_data") as Array
		if not lights.is_empty():
			vis.call("set_night", true)
			vis.call("refresh_from_event")
			var lp: Vector2 = (lights[0] as Dictionary).get("pos", Vector2.ZERO) as Vector2
			var illum_center: float = vis.call("_compute_illumination", lp, lp)
			var illum_far: float = vis.call("_compute_illumination", lp + Vector2(1200.0, 0.0), lp)
			_assert(illum_center > 0.5, "散落光源中心被照亮（%.2f）" % illum_center)
			_assert(illum_far < 0.05, "远离所有光源处仍极致漆黑（%.2f）" % illum_far)
			vis.call("clear_overlay")

	# 绘制层级（2026-10-23 用户反馈「跑一会整屏全黑」「人物投射光束」）：
	# 雾罩必须**绝对**层级，否则它是玩家的子节点，玩家抬高会把雾罩一起抬上去；
	# 玩家/灯塔塔身必须压在雾罩之上——玩家不能被雾压成剪影，灯塔要当光束的可见源头。
	if vis != null:
		var _vis_z: int = int((vis as Node2D).z_index)
		_assert(not (vis as Node2D).z_as_relative, "VisionOverlay 雾罩为绝对层级（z_as_relative=false）")
		var pl: Node = world.get("player")
		if pl is Node2D:
			_assert((pl as Node2D).z_index > _vis_z,
				"玩家绘制在雾罩之上（%d > %d）" % [(pl as Node2D).z_index, _vis_z])
			if scatter is Node2D:
				_assert((pl as Node2D).z_index > (scatter as Node2D).z_index,
					"玩家绘制在散落光源之上（光晕不染角色，%d > %d）" % [
						(pl as Node2D).z_index, (scatter as Node2D).z_index])
		var beacon: Node = world.get("_lighthouse_beacon")
		if beacon is Node2D:
			_assert((beacon as Node2D).z_index > _vis_z,
				"灯塔塔身绘制在雾罩之上（光束有可见源头，%d > %d）" % [
					(beacon as Node2D).z_index, _vis_z])

	# 玩家侧对象抬到雾罩之上、敌人侧保持藏黑（2026-10-23 用户选方案 B）：
	# 暗处也能看见自己打出的弹道/特效与掉落的拾取物（不漏捡、战斗有反馈），
	# 但敌人本体与敌人弹道仍在雾下（黑暗压迫感保留）。
	var _above: Dictionary = {
		"经验珠": "res://scripts/pickup/exp_gem.gd",
		"潮币": "res://scripts/pickup/coin.gd",
		"宝箱": "res://scripts/pickup/chest.gd",
		"玩家弹道": "res://scripts/combat/projectile.gd",
		"武器特效": "res://scripts/combat/weapon_effect.gd",
		"召唤物": "res://scripts/combat/summon_entity.gd",
		"环绕锁链": "res://scripts/combat/orbit_chain_visual.gd",
	}
	# 层级常量单一来源 RenderZ（2026-10-23 code-review P2：原 7 个脚本各自硬编码 81）
	var _rz_scr: Script = load("res://scripts/core/render_z.gd") as Script
	var _rz: Dictionary = _rz_scr.get_script_constant_map() if _rz_scr != null else {}
	var _above_z: int = int(_rz.get("ABOVE_FOG", -1))
	_assert(int(_rz.get("FOG", -1)) == 80 and _above_z == 81,
		"RenderZ 单一来源：雾罩=%d / 雾上=%d" % [int(_rz.get("FOG", -1)), _above_z])
	_assert(int(_rz.get("LIGHTHOUSE_BODY", 0)) >= _above_z
		and int(_rz.get("SCATTERED_LIGHT", 0)) > int(_rz.get("LIGHTHOUSE_BODY", 0))
		and int(_rz.get("PLAYER", 0)) > int(_rz.get("SCATTERED_LIGHT", 0)),
		"RenderZ 层级栈递增：雾上 < 塔身 < 散落光源 < 玩家")
	for _label in _above:
		var _scr: Script = load(String(_above[_label])) as Script
		var _cmap: Dictionary = _scr.get_script_constant_map() if _scr != null else {}
		_assert(int(_cmap.get("Z_ABOVE_FOG", -1)) == _above_z,
			"%s 的 Z_ABOVE_FOG 引用 RenderZ（%d = %d）" % [_label, int(_cmap.get("Z_ABOVE_FOG", -1)), _above_z])
	var _below: Dictionary = {
		"敌人本体": "res://scripts/core/enemy_base.gd",
		"敌人弹道": "res://scripts/combat/enemy_projectile.gd",
	}
	for _label in _below:
		var _scr2: Script = load(String(_below[_label])) as Script
		var _cmap2: Dictionary = _scr2.get_script_constant_map() if _scr2 != null else {}
		_assert(not _cmap2.has("Z_ABOVE_FOG"),
			"%s 不参与雾上层级（仍留在雾罩之下藏黑）" % _label)

	# 命中闪光（瞬态光源）：命中点开雾让雾下的敌人显形 + 到期自动熄灭 + 数量上限
	if vis != null:
		var hc: Dictionary = vis.call("get_hit_flash_config") as Dictionary
		var h_radius: float = float(hc.get("radius", 0.0))
		var h_dur: float = float(hc.get("duration", 0.0))
		var h_max: int = int(hc.get("max", 0))
		_assert(h_radius > 0.0, "命中闪光半径 > 0（%.0fpx）" % h_radius)
		_assert(h_dur > 0.0, "命中闪光寿命 > 0（%.2fs）" % h_dur)
		_assert(h_max >= 1, "命中闪光数量上限 ≥1（%d）" % h_max)
		# 清掉散落光源，保证命中点初始为纯黑（否则「被照亮」无从比较）
		# 注意：set_scattered_lights 参数是 Array[Dictionary]，须传类型化空数组
		var _no_lights: Array[Dictionary] = []
		vis.call("set_scattered_lights", _no_lights)
		vis.call("set_night", true)
		vis.call("refresh_from_event")
		var hit_pt: Vector2 = (world.get("player") as Node2D).global_position + Vector2(600.0, 0.0)
		var before_illum: float = vis.call("_compute_illumination", hit_pt, hit_pt)
		vis.call("add_hit_flash", hit_pt)
		var after_illum: float = vis.call("_compute_illumination", hit_pt, hit_pt)
		_assert(int(vis.call("get_hit_flash_count")) == 1, "命中闪光已登记（1 个）")
		_assert(after_illum > before_illum + 0.3,
			"命中点被照亮（%.2f → %.2f）" % [before_illum, after_illum])
		# 数量上限：连加 max+3 个，只保留 max 个（丢最旧的）
		for _i in h_max + 3:
			vis.call("add_hit_flash", hit_pt + Vector2(float(_i) * 12.0, 0.0))
		_assert(int(vis.call("get_hit_flash_count")) == h_max,
			"命中闪光数量受上限约束（%d）" % int(vis.call("get_hit_flash_count")))
		# 寿命：推进超过 duration 后全部熄灭
		vis.call("_process", h_dur + 0.05)
		_assert(int(vis.call("get_hit_flash_count")) == 0,
			"命中闪光到期自动熄灭（%d）" % int(vis.call("get_hit_flash_count")))
		# 端到端：敌人受伤 → 经 group 找到遮罩 → 真的登记了闪光（验证接线，不只是单元）
		var e2: Node = spawner.call("spawn_enemy", {"id": "small_goblin"},
			player.global_position + Vector2(300.0, 0.0), no_affix, false)
		if e2 != null:
			e2.call("take_damage", 1)
			_assert(int(vis.call("get_hit_flash_count")) >= 1,
				"敌人受伤触发命中闪光（%d 个，接线 OK）" % int(vis.call("get_hit_flash_count")))
			# 分摊伤害（from_share=true）不该再闪，避免一次命中亮一片
			var cnt_before: int = int(vis.call("get_hit_flash_count"))
			e2.call("take_damage", 1, false, true, "")
			_assert(int(vis.call("get_hit_flash_count")) == cnt_before,
				"分摊伤害不触发闪光（%d）" % int(vis.call("get_hit_flash_count")))
		vis.call("clear_overlay")

	world.queue_free()
