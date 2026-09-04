# ============================================================================
# VisionOverlay — 事件视野倍率遮罩（月食等）
# 职责：消费 EventSystem.get_vision_mult()；以玩家为圆心绘制暗色环带，缩小可视半径。
# 数据：基准半径 config/events.json metadata.base_vision_radius（默认 320）
# 红线：倍率 1.0 时隐藏；不改 Camera zoom；数值只读 config
# ============================================================================
class_name VisionOverlay
extends Node2D

const SEGMENTS: int = 48
const OUTER_RADIUS: float = 2400.0
const FOG_COLOR := Color(0.02, 0.03, 0.08, 0.82)

var _base_radius: float = 320.0
var _vision_radius: float = 320.0
var _active: bool = false
## 扇区多边形缓存（半径变化时重建；避免每帧分配）
var _fog_polys: Array[PackedVector2Array] = []
var _fog_cache_radius: float = -1.0


func _ready() -> void:
	z_index = 80
	_base_radius = ConfigLoader.get_base_vision_radius()
	_vision_radius = _base_radius
	visible = false
	set_process(false)  # 挂在 Player 下随父节点移动，无需每帧 process


## 按当前事件倍率刷新（World 进夜 begin_night 后调用）
func refresh_from_event() -> void:
	_base_radius = ConfigLoader.get_base_vision_radius()
	var mult: float = EventSystem.get_vision_mult()
	_vision_radius = _base_radius * mult
	_active = mult < 0.999
	visible = _active
	if _active:
		_rebuild_fog_cache_if_needed()
	else:
		_fog_polys.clear()
		_fog_cache_radius = -1.0
	queue_redraw()


## 进昼 / 关遮罩：清激活态，避免不可见时仍占绘制状态
func clear_overlay() -> void:
	_active = false
	visible = false
	_fog_polys.clear()
	_fog_cache_radius = -1.0
	queue_redraw()


## 机检 / 调试：当前有效视野半径（像素）
func get_vision_radius() -> float:
	return _vision_radius


## 机检：遮罩是否激活
func is_vision_restricted() -> bool:
	return _active


func _rebuild_fog_cache_if_needed() -> void:
	var inner: float = maxf(8.0, _vision_radius)
	if absf(inner - _fog_cache_radius) < 0.01 and not _fog_polys.is_empty():
		return
	_fog_cache_radius = inner
	_fog_polys.clear()
	var outer: float = OUTER_RADIUS
	for i in SEGMENTS:
		var a0: float = TAU * float(i) / float(SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(SEGMENTS)
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(cos(a0), sin(a0)) * inner,
			Vector2(cos(a1), sin(a1)) * inner,
			Vector2(cos(a1), sin(a1)) * outer,
			Vector2(cos(a0), sin(a0)) * outer,
		])
		_fog_polys.append(pts)


func _draw() -> void:
	if not _active:
		return
	for pts in _fog_polys:
		draw_colored_polygon(pts, FOG_COLOR)
