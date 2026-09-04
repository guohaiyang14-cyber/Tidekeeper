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

## 基础拾取半径（§5.2：经验珠自动吸附范围，夜明珠被动可扩大；运行时由 pickups.json 覆盖）
@export var base_pickup_radius: float = 60.0

## 移速加成软上限（§5.2：+60%）
const MOVE_SPEED_SOFT_CAP: float = 1.6

## 单位→像素换算（§5.2：1 单位 = 60 像素，W2 调校）
const UNIT_TO_PIXEL: float = 60.0

# 运行时
var _move_speed_mult: float = 1.0
var _pickup_radius_mult: float = 1.0
var _hurt_flash: float = 0.0
## 锁链等：剩余束缚时间；>0 时乘 _bind_move_mult（0=完全定身，(0,1]=减速）
var _bind_timer: float = 0.0
var _bind_move_mult: float = 0.5


func _ready() -> void:
	# 从配置加载角色基础属性（§9.4 角色表）与拾取半径（pickups.json）
	_apply_character_stats()
	_apply_pickup_config()
	_ensure_gamepad_move_bindings()
	if not GameState.player_damaged.is_connected(_on_player_damaged):
		GameState.player_damaged.connect(_on_player_damaged)
	print("[Player] 就绪: character=%s move_speed=%.1f pickup_radius=%.0f" % [
		character_id, base_move_speed, base_pickup_radius,
	])


## 左摇杆绑定到 move_*（幂等；键盘事件已在 project.godot）
func _ensure_gamepad_move_bindings() -> void:
	_add_joy_axis_if_missing("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis_if_missing("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis_if_missing("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis_if_missing("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button_if_missing("interact", JOY_BUTTON_A)
	_add_joy_button_if_missing("skip", JOY_BUTTON_B)
	# 摇杆手感：0.5 过大；数字键仍为 0/1，降到 0.25 不影响键盘
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, 0.25)


func _add_joy_axis_if_missing(action: String, axis: int, axis_value: float) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			var jm: InputEventJoypadMotion = ev as InputEventJoypadMotion
			if jm.axis == axis and signf(jm.axis_value) == signf(axis_value):
				return
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = axis_value
	InputMap.action_add_event(action, motion)


func _add_joy_button_if_missing(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var btn := InputEventJoypadButton.new()
	btn.button_index = button
	InputMap.action_add_event(action, btn)


## 开局同步当前角色（World 在 start_new_run 后调用；覆盖场景默认 watcher）
func apply_run_character(id: String) -> void:
	character_id = id
	_apply_character_stats()


func _physics_process(_delta: float) -> void:
	if _bind_timer > 0.0:
		_bind_timer = maxf(0.0, _bind_timer - _delta)
	_handle_movement()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - _delta)
		queue_redraw()


## 从配置应用角色属性（§9.4；移速只读 characters.json）
func _apply_character_stats() -> void:
	if ConfigLoader.get_character(character_id).is_empty():
		push_warning("[Player] 未知角色 %s，使用默认移速" % character_id)
	base_move_speed = ConfigLoader.get_character_move_speed(character_id)


## 从 pickups.json 读取默认拾取半径
func _apply_pickup_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_exp_gem_config()
	if cfg.has("default_pickup_radius"):
		base_pickup_radius = float(cfg["default_pickup_radius"])


## 受击闪红反馈（GameState.player_damaged 触发，短时提示）
func _on_player_damaged(_amount: int) -> void:
	_hurt_flash = 0.18
	queue_redraw()


## 处理移动输入（WASD + 左摇杆，§5.2）；锁链等束缚期间按 bind_move_mult 减速（0 则定身）
func _handle_movement() -> void:
	# get_vector 合成键盘与摇杆（死区走 InputMap）
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 移速 = 基础 × 加成（受软上限约束）× 事件移速（W14 灯塔共鸣），单位→像素换算
	var speed: float = base_move_speed * _effective_move_mult()
	if _bind_timer > 0.0:
		if _bind_move_mult <= 0.0:
			velocity = Vector2.ZERO
			move_and_slide()
			return
		speed *= _bind_move_mult
	velocity = input_vector * speed * UNIT_TO_PIXEL
	move_and_slide()


## 设置移速加成（受软上限约束，§5.2）
func set_move_speed_mult(mult: float) -> void:
	_move_speed_mult = minf(mult, MOVE_SPEED_SOFT_CAP)


## 局内移速倍率：被动/其它加成受软上限，再乘事件移速（灯塔共鸣 0.80 为惩罚，独立于软上限）× 角色&灯塔移速（W15-W16）
func _effective_move_mult() -> float:
	return minf(_move_speed_mult, MOVE_SPEED_SOFT_CAP) * EventSystem.get_move_speed_mult() * MetaSystem.get_move_speed_mult()


## 获取当前移速（像素/秒）
func get_current_speed() -> float:
	return base_move_speed * _effective_move_mult() * UNIT_TO_PIXEL


## 获取有效拾取半径（基础 × 灯塔光环倍率 × 被动拾取桶，W12）
func get_pickup_radius() -> float:
	return base_pickup_radius * _pickup_radius_mult * PassiveSystem.get_pickup_radius_mult()


## 设置拾取半径倍率（局外灯塔光环等；夜明珠走 PassiveSystem 拾取桶，勿双乘）
func set_pickup_radius_mult(mult: float) -> void:
	_pickup_radius_mult = mult
	queue_redraw()


## 锁链等束缚：短时减速或定身（duration 取较长剩余；move_mult 取更严=更小）
## move_mult < 0 时从 config/enemies.json affixes.chain.bind_move_mult 读取（默认 0.5）
func apply_bind(duration: float, move_mult: float = -1.0) -> void:
	if duration <= 0.0:
		return
	var mult: float = move_mult
	if mult < 0.0:
		var ch: Dictionary = ConfigLoader.get_affix("chain")
		mult = float(ch.get("bind_move_mult", 0.5))
	if _bind_timer > 0.0:
		_bind_move_mult = minf(_bind_move_mult, mult)
	else:
		_bind_move_mult = mult
	_bind_timer = maxf(_bind_timer, duration)


func is_bound() -> bool:
	return _bind_timer > 0.0


## 当前束缚移速倍率（未束缚返回 1.0；0=定身）
func get_bind_move_mult() -> float:
	return _bind_move_mult if _bind_timer > 0.0 else 1.0


func _draw() -> void:
	# W2 占位视觉：白色圆 + 蓝边 + 拾取半径圈（虚线感）
	# 拾取半径范围（半透明圈，方便调试观察）
	var radius: float = get_pickup_radius()
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.3, 0.85, 1.0, 0.15), 2.0)
	# 玩家本体（受击闪红）
	var body_color: Color = Color(0.9, 0.95, 1.0, 0.9) if _hurt_flash <= 0.0 else Color(1.0, 0.25, 0.25, 0.95)
	draw_circle(Vector2.ZERO, 14.0, body_color)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.3, 0.6, 1.0, 1.0), 2.0)
