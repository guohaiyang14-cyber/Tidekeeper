# ============================================================================
# ArenaBoundary — 竞技场边界可视化（2026-10-22 用户反馈：
# 「边界没有用明确的障碍物显示出来，空气墙的感觉不好」）
# 职责：沿竞技场圆周实例化礁石界桩（ assets/sprites/world/reef_post_*.png ）+
#       能量虚线弧 + 界外深色海域，把隐形钳位变成可读的实体边界。
# 数据：config/map.json arena.boundary（post_ids / post_spacing_px / post_scale /
#       energy_arc / outer_tint）；圆心与半径由 World.setup 注入（复用灯塔圆心）。
# 红线：参数只读 config；界桩角度抖动用确定性哈希（不消耗游戏 RNG）。
# ============================================================================
class_name ArenaBoundary
extends Node2D

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")
const OUTER_RADIUS: float = 2400.0
const TINT_SEGMENTS: int = 64

var _center: Vector2 = Vector2.ZERO
var _radius: float = 0.0
var _post_ids: Array[String] = []
var _post_spacing: float = 130.0
var _post_scale: float = 1.0
var _arc_color := Color(0.45, 0.85, 1.0, 0.35)
var _arc_width: float = 3.0
var _arc_dash_px: float = 26.0
var _arc_enabled: bool = true
var _tint_color := Color(0.03, 0.06, 0.12, 0.55)
var _tint_enabled: bool = true
var _posts_root: Node2D = null


func _ready() -> void:
	# 界外暗环在 ground(-100) 之上、实体(0)之下；界桩子节点再高一级
	z_index = -50
	_posts_root = Node2D.new()
	_posts_root.z_index = 5
	add_child(_posts_root)


## World 调用：圆心 + 半径（像素）。重复调用会重建界桩。
func setup(center: Vector2, radius_px: float) -> void:
	_center = center
	_radius = maxf(radius_px, 1.0)
	global_position = _center
	_read_config()
	_rebuild_posts()
	queue_redraw()


func _read_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_arena_boundary_config()
	_post_ids.clear()
	for v in cfg.get("post_ids", []) as Array:
		_post_ids.append(String(v))
	if _post_ids.is_empty():
		_post_ids.append("reef_post_0")
	_post_spacing = maxf(24.0, float(cfg.get("post_spacing_px", 130.0)))
	_post_scale = clampf(float(cfg.get("post_scale", 1.0)), 0.25, 4.0)
	var arc: Dictionary = cfg.get("energy_arc", {}) as Dictionary
	_arc_enabled = bool(arc.get("enabled", true))
	_arc_color = _color_from(arc.get("color", [0.45, 0.85, 1.0]), float(arc.get("alpha", 0.35)))
	_arc_width = maxf(1.0, float(arc.get("width", 3.0)))
	_arc_dash_px = maxf(8.0, float(arc.get("dash_px", 26.0)))
	var tint: Dictionary = cfg.get("outer_tint", {}) as Dictionary
	_tint_enabled = bool(tint.get("enabled", true))
	_tint_color = _color_from(tint.get("color", [0.03, 0.06, 0.12]), float(tint.get("alpha", 0.55)))


func _color_from(raw: Variant, alpha: float) -> Color:
	var r := 1.0
	var g := 1.0
	var b := 1.0
	if raw is Array and (raw as Array).size() >= 3:
		r = float((raw as Array)[0])
		g = float((raw as Array)[1])
		b = float((raw as Array)[2])
	return Color(r, g, b, clampf(alpha, 0.0, 1.0))


## 确定性角度抖动（不耗游戏 RNG，保证多端一致）
func _hash01(i: int) -> float:
	return fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) * 0.5 + 0.5


func _rebuild_posts() -> void:
	if _posts_root == null:
		return
	for ch in _posts_root.get_children():
		ch.queue_free()
	if _radius <= 1.0:
		return
	var circumference: float = TAU * _radius
	var count: int = maxi(8, int(circumference / _post_spacing))
	for i in count:
		var jitter_a: float = (_hash01(i) - 0.5) * (TAU / float(count)) * 0.6
		var angle: float = TAU * float(i) / float(count) + jitter_a
		var r_jitter: float = (_hash01(i + 977) - 0.5) * 10.0
		var pos := Vector2(cos(angle), sin(angle)) * (_radius + r_jitter)
		var spr := Sprite2D.new()
		spr.texture = _SPRITE_LIB.world(_post_ids[i % _post_ids.size()])
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(_post_scale, _post_scale)
		if spr.texture != null:
			# 底部对齐圆周：界桩「长在」边界上
			spr.position = Vector2(0.0, -float(spr.texture.get_height()) * _post_scale * 0.5)
		spr.z_index = 5
		_posts_root.add_child(spr)
		spr.position = pos + spr.position


func _draw() -> void:
	if _radius <= 1.0:
		return
	# 1) 界外深色海域（内半径=arena，外半径=OUTER_RADIUS 的环带）
	if _tint_enabled:
		for i in TINT_SEGMENTS:
			var a0: float = TAU * float(i) / float(TINT_SEGMENTS)
			var a1: float = TAU * float(i + 1) / float(TINT_SEGMENTS)
			var pts := PackedVector2Array([
				Vector2(cos(a0), sin(a0)) * _radius,
				Vector2(cos(a1), sin(a1)) * _radius,
				Vector2(cos(a1), sin(a1)) * OUTER_RADIUS,
				Vector2(cos(a0), sin(a0)) * OUTER_RADIUS,
			])
			draw_colored_polygon(pts, _tint_color)
	# 2) 能量虚线弧（贴界桩内侧）
	if _arc_enabled:
		var arc_r: float = _radius - 6.0
		var step: float = _arc_dash_px / maxf(arc_r, 1.0)
		var a: float = 0.0
		while a < TAU:
			var a1: float = minf(a + step * 0.62, TAU)
			draw_arc(Vector2.ZERO, arc_r, a, a1, 6, _arc_color, _arc_width)
			a += step
