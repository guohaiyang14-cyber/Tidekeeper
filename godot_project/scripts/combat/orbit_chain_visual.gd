# ============================================================================
# OrbitChainVisual — 锚链武器持久环绕视觉（2026-10-22）
# 行为：跟随玩家绘制旋转的锚链圈（链段 +  faint 半径圈）；tick 时脉冲闪光。
# 红线：纯视觉；挂武器实例下（queue_free 武器即回收）；程序化 .new() 构建。
# 数据：半径/圈距/颜色由 WeaponAnchorChain 按 weapons.json behavior 注入。
# ============================================================================
class_name OrbitChainVisual
extends Node2D

const LINKS_PER_RING: int = 10

## 绘制层级：玩家侧视觉画在黑夜雾罩（VisionOverlay z=80）**之上**（2026-10-23 方案 B）
## 层级栈：雾罩 80 < 玩家弹道/特效/召唤物/拾取物 81 < 灯塔塔身 82 < 散落光源 83 < 玩家 84
const _RENDER_Z := preload("res://scripts/core/render_z.gd")
const Z_ABOVE_FOG: int = _RENDER_Z.ABOVE_FOG

var _radius: float = 60.0
var _spacing: float = 15.0
var _rings: int = 1
var _color: Color = Color(0.72, 0.78, 0.86)
var _get_owner_pos: Callable = Callable()
var _angle: float = 0.0
var _speed: float = 2.4
var _flash: float = 0.0


func setup(radius: float, spacing: float, rings: int, color: Color, speed: float, get_owner_pos: Callable) -> void:
	_radius = radius
	_spacing = spacing
	_rings = maxi(1, rings)
	_color = color
	_speed = speed
	_get_owner_pos = get_owner_pos


## tick 脉冲：链圈瞬时提亮（视觉节拍，与伤害 tick 同步）
func pulse() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_angle += delta * _speed
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
	if _get_owner_pos.is_valid():
		var p: Variant = _get_owner_pos.call()
		if p is Vector2:
			global_position = p as Vector2
	queue_redraw()


func _draw() -> void:
	var base: Color = _color
	var hot: Color = _color.lightened(0.5)
	for ring in _rings:
		# 每圈起点复位（上一圈的链段用过 draw_set_transform，不复位会把半径圈画偏）
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var r: float = _radius + _spacing * float(ring)
		# faint 半径圈（提示作用范围）
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(base.r, base.g, base.b, 0.16 + 0.25 * _flash), 1.0)
		# 链段：环上均布小方块，随角度旋转
		for i in LINKS_PER_RING:
			var a: float = _angle + TAU * float(i) / float(LINKS_PER_RING) + float(ring) * 0.15
			var c: Vector2 = Vector2(cos(a), sin(a)) * r
			var s: float = 3.2 + 1.6 * _flash
			var col: Color = hot if _flash > 0.5 else base
			draw_set_transform(c, a, Vector2.ONE)
			draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(col.r, col.g, col.b, 0.95))
			draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(col.r, col.g, col.b, 0.95), false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 工厂（与 SummonEntity 同策略：程序化构建）
static func create(get_owner_pos: Callable) -> OrbitChainVisual:
	var v := OrbitChainVisual.new()
	# 环绕锁链属于玩家侧视觉：抬到黑夜雾罩（VisionOverlay z=80）之上（方案 B 同层）
	v.z_index = Z_ABOVE_FOG
	v._get_owner_pos = get_owner_pos
	return v
