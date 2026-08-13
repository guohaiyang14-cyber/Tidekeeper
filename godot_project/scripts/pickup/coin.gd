# ============================================================================
# Coin — 潮币掉落物（W4 商店闭环）
# 职责：敌人死亡掉落的潮币，玩家靠近自动吸附拾取，计入 GameState.tidecoins
# 数据源：§5.2 拾取（潮币靠近拾取）、§4.2 商店（潮币购买）
# 红线：走对象池（CoinPool），禁止运行时 instantiate；不用 Physics2D
# 接口：与 ExpGem 对齐（start_attract / update_attract / is_attracted），由 PickupSystem 驱动
# ============================================================================
class_name Coin
extends Node2D

enum State {
	IDLE,
	ATTRACTED,
}

## 潮币价值（由 PickupSystem.spawn_coin 设置）
var value: int = 1

var _state: State = State.IDLE
var _attract_speed: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 4


func _draw() -> void:
	draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.84, 0.2, 0.95))
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.5), 1.0)


func _on_acquire() -> void:
	_state = State.IDLE
	value = 1
	_attract_speed = 0.0
	_target_pos = Vector2.ZERO
	queue_redraw()


func _on_release() -> void:
	_state = State.IDLE
	value = 1
	_attract_speed = 0.0
	_target_pos = Vector2.ZERO
	queue_redraw()


func start_attract(target: Vector2, speed: float) -> void:
	if _state == State.ATTRACTED:
		return
	_state = State.ATTRACTED
	_attract_speed = speed
	_target_pos = target
	queue_redraw()


func update_attract(target: Vector2, delta: float) -> void:
	_target_pos = target
	var to_target: Vector2 = _target_pos - global_position
	var dist: float = to_target.length()
	if dist < 1.0:
		return
	var speed: float = _attract_speed * (1.0 + (1.0 - clampf(dist / 80.0, 0.0, 1.0)) * 0.5)
	global_position += to_target.normalized() * speed * delta


func is_attracted() -> bool:
	return _state == State.ATTRACTED


func reset_to_idle() -> void:
	_state = State.IDLE
	queue_redraw()
