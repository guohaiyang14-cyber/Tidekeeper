# ============================================================================
# Player — 玩家节点（W1 骨架 / W2 完善移动+拾取+升级）
# 职责：WASD 移动 + 基础属性
# 数据源：§9.4 角色表 + §5.2 玩家节点（基础移速 4.2，+60% 软上限）
# W1 范围：仅移动骨架；W2 加经验珠拾取、升级弹窗、武器槽管理
# ============================================================================
extends CharacterBody2D
class_name Player

## 角色标识（watcher/blacksmith/stargazer）
@export var character_id: String = "watcher"

## 基础移速（§5.2：4.2 单位/秒）
@export var base_move_speed: float = 4.2

## 移速加成软上限（§5.2：+60%）
const MOVE_SPEED_SOFT_CAP: float = 1.6

# 运行时
var _move_speed_mult: float = 1.0


func _ready() -> void:
	# 从配置加载角色基础属性（§9.4 角色表）
	_apply_character_stats()
	print("[Player] 就绪: character=%s move_speed=%.1f" % [character_id, base_move_speed])


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
	# 移速 = 基础 × 加成（受软上限约束）
	var speed: float = base_move_speed * minf(_move_speed_mult, MOVE_SPEED_SOFT_CAP)
	# 单位/秒 → 像素/秒（假设 1 单位 = 60 像素，W2 调整）
	velocity = input_vector * speed * 60.0
	move_and_slide()


## 设置移速加成（受软上限约束）
func set_move_speed_mult(mult: float) -> void:
	_move_speed_mult = minf(mult, MOVE_SPEED_SOFT_CAP)


## 获取当前移速（像素/秒）
func get_current_speed() -> float:
	return base_move_speed * minf(_move_speed_mult, MOVE_SPEED_SOFT_CAP) * 60.0
