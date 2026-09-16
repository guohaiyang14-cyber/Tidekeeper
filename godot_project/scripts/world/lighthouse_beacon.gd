# ============================================================================
# LighthouseBeacon — 灯塔视觉占位（A5）
# 职责：在灯塔圆心绘制光晕/塔身；碰撞由 Player 推出处理，不用 Physics2D
# ============================================================================
extends Node2D
class_name LighthouseBeacon

var _radius_px: float = 30.0


func setup(center: Vector2, radius_px: float) -> void:
	global_position = center
	_radius_px = maxf(radius_px, 1.0)
	queue_redraw()


func _draw() -> void:
	# 外环光晕
	draw_circle(Vector2.ZERO, _radius_px * 2.2, Color(0.95, 0.85, 0.45, 0.08))
	draw_arc(Vector2.ZERO, _radius_px * 2.2, 0.0, TAU, 48, Color(0.95, 0.82, 0.40, 0.35), 2.0)
	# 碰撞边界（调试可见）
	draw_arc(Vector2.ZERO, _radius_px, 0.0, TAU, 32, Color(0.90, 0.75, 0.35, 0.85), 2.5)
	# 塔身占位
	draw_circle(Vector2.ZERO, maxf(_radius_px * 0.45, 8.0), Color(0.85, 0.78, 0.55, 0.95))
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.95, 0.70, 1.0))
