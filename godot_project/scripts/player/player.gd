# ============================================================================
# Player — 玩家节点（W2：移动 + 拾取 + 经验）
# 职责：WASD 移动 + 拾取半径 + 角色属性
# 数据源：§9.4 角色表 + §5.2 玩家节点（基础移速 4.2，+60% 软上限）
# W2 范围：移动手感调校 + 拾取半径（经验珠由 PickupSystem 驱动）
# ============================================================================
extends CharacterBody2D
class_name Player

## 角色标识（watcher/blacksmith/stargazer）
@export var character_id: String = "watcher"

## 基础移速（§5.2：4.2 单位/秒）
@export var base_move_speed: float = 4.2

## 基础拾取半径默认值（§5.2：经验珠自动吸附范围，夜明珠被动可扩大）
const DEFAULT_PICKUP_RADIUS: float = 60.0

## 基础拾取半径（可通过 Inspector 调整）
@export var base_pickup_radius: float = 60.0

## 移速加成软上限（§5.2：+60%）
const MOVE_SPEED_SOFT_CAP: float = 1.6

## 单位→像素换算（§5.2：1 单位 = 60 像素，W2 调校）
const UNIT_TO_PIXEL: float = 60.0

# 运行时
var _move_speed_mult: float = 1.0
var _pickup_radius_mult: float = 1.0


func _ready() -> void:
	# 从配置加载角色基础属性（§9.4 角色表）
	_apply_character_stats()
	print("[Player] 就绪: character=%s move_speed=%.1f pickup_radius=%.0f" % [
		character_id, base_move_speed, base_pickup_radius,
	])


func _physics_process(_delta: float) -> void:
	_handle_movement()


## 从配置应用角色属性（§9.4）
func _apply_character_stats() -> void:
	# §9.4 角色表：守望者 100/4.2，铁匠 120/4.0，星象师 85/4.2
	match character_id:
		"watcher":
			base_move_speed = 4.2
		"blacksmith":
			base_move_speed = 4.0
		"stargazer":
			base_move_speed = 4.2
		_:
			push_warning("[Player] 未知角色 %s，使用默认属性" % character_id)


## 处理移动输入（WASD，§5.2）
func _handle_movement() -> void:
	var input_vector: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1.0
	if Input.is_action_pressed("move_down"):
		input_vector.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0

	input_vector = input_vector.normalized()
	# 移速 = 基础 × 加成（受软上限约束），单位→像素换算
	var speed: float = base_move_speed * minf(_move_speed_mult, MOVE_SPEED_SOFT_CAP)
	velocity = input_vector * speed * UNIT_TO_PIXEL
	move_and_slide()


## 设置移速加成（受软上限约束，§5.2）
func set_move_speed_mult(mult: float) -> void:
	_move_speed_mult = minf(mult, MOVE_SPEED_SOFT_CAP)


## 获取当前移速（像素/秒）
func get_current_speed() -> float:
	return base_move_speed * minf(_move_speed_mult, MOVE_SPEED_SOFT_CAP) * UNIT_TO_PIXEL


## 获取有效拾取半径（基础 × 被动倍率，夜明珠被动可扩大）
func get_pickup_radius() -> float:
	return base_pickup_radius * _pickup_radius_mult


## 设置拾取半径倍率（夜明珠被动 / 灯塔光环局外升级调用）
func set_pickup_radius_mult(mult: float) -> void:
	_pickup_radius_mult = mult


func _draw() -> void:
	# W2 占位视觉：白色圆 + 蓝边 + 拾取半径圈（虚线感）
	# 拾取半径范围（半透明圈，方便调试观察）
	var radius: float = get_pickup_radius()
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.3, 0.85, 1.0, 0.15), 2.0)
	# 玩家本体
	draw_circle(Vector2.ZERO, 14.0, Color(0.9, 0.95, 1.0, 0.9))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.3, 0.6, 1.0, 1.0), 2.0)
