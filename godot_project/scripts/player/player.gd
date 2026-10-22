# ============================================================================
# Player — 玩家节点（W2：移动 + 拾取 + 经验）
# 职责：WASD 移动 + 拾取半径 + 角色属性
# 数据源：§9.4 角色表 + §5.2 玩家节点（基础移速 4.2，+60% 软上限）
# W2 范围：移动手感调校 + 拾取半径（经验珠由 PickupSystem 驱动）
# ============================================================================
extends CharacterBody2D
class_name Player

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")

## 角色标识（watcher/blacksmith/stargazer）
@export var character_id: String = "watcher"

## 基础移速（§5.2：4.2 单位/秒）
@export var base_move_speed: float = 4.2

## 基础拾取半径（§5.2：经验珠自动吸附范围，夜明珠被动可扩大；运行时由 pickups.json 覆盖）
@export var base_pickup_radius: float = 60.0

## 单位→像素换算（§5.2：1 单位 = 60 像素，W2 调校）
const UNIT_TO_PIXEL: float = 60.0

## 玩家本体碰撞半径（像素；与精灵视觉尺寸一致）
const BODY_RADIUS_PX: float = 14.0

## 角色精灵的显示直径（像素）：精灵原生 48px（16 逻辑×3），缩放到略大于碰撞体，
## 让角色在敌人中间显眼（用户反馈「看不到角色/开局分不清」）。
const SPRITE_DISPLAY_PX: float = 40.0


## 移速软上限阈值（GDD §6.9 / passives.json soft_caps.move_speed；缺省 +60%）
static func move_speed_soft_cap() -> float:
	return PassiveSystem.get_soft_cap_threshold("move_speed", 1.6)

# 运行时
var _move_speed_mult: float = 1.0
var _pickup_radius_mult: float = 1.0
var _hurt_flash: float = 0.0
## 锁链等：剩余束缚时间；>0 时乘 _bind_move_mult（0=完全定身，(0,1]=减速）
var _bind_timer: float = 0.0
var _bind_move_mult: float = 0.5
## A5 灯塔障碍（圆心 + 半径像素；不用 Physics2D）
var _lh_center: Vector2 = Vector2.ZERO
var _lh_radius_px: float = 0.0
var _lh_enabled: bool = false
## 竞技场边界（以灯塔/开局点为圆心的活动半径像素；≤0 不限制）
var _arena_radius_px: float = 0.0
var _arena_soft_push: bool = true
## 每帧 resolve_arena_bounds 真正钳位时递增（供 Debug TestBot ACCEPT 1.2.5 观测）
var arena_clamp_count: int = 0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# 从配置加载角色基础属性（§9.4 角色表）与拾取半径（pickups.json）
	_apply_character_stats()
	_apply_pickup_config()
	_apply_sprite()
	_init_arena()
	_ensure_gamepad_move_bindings()
	if not GameState.player_damaged.is_connected(_on_player_damaged):
		GameState.player_damaged.connect(_on_player_damaged)
	print("[Player] 就绪: character=%s move_speed=%.1f pickup_radius=%.0f" % [
		character_id, base_move_speed, base_pickup_radius,
	])


## 按 character_id 加载角色精灵（缺失时保留空 Sprite，靠 _draw 的圆兜底）
func _apply_sprite() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	var tex: Texture2D = _SPRITE_LIB.player(character_id)
	if tex == null:
		_sprite.texture = null
		_sprite.visible = false
		return
	_sprite.texture = tex
	_sprite.visible = true
	var s: float = SPRITE_DISPLAY_PX / maxf(float(tex.get_width()), 1.0)
	_sprite.scale = Vector2(s, s)


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
	motion.axis = axis as JoyAxis
	motion.axis_value = axis_value
	InputMap.action_add_event(action, motion)


func _add_joy_button_if_missing(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var btn := InputEventJoypadButton.new()
	btn.button_index = button as JoyButton
	InputMap.action_add_event(action, btn)


## 开局同步当前角色（World 在 start_new_run 后调用；覆盖场景默认 watcher）
func apply_run_character(id: String) -> void:
	character_id = id
	_apply_character_stats()
	_apply_sprite()


func _physics_process(_delta: float) -> void:
	if _bind_timer > 0.0:
		_bind_timer = maxf(0.0, _bind_timer - _delta)
	_handle_movement()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - _delta)
		_update_sprite_tint()
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
	_update_sprite_tint()
	queue_redraw()


## 受击闪红：精灵存在时给 modulate 染红（无精灵才由 _draw 画红圆）
func _update_sprite_tint() -> void:
	if _sprite == null:
		return
	if _sprite.texture == null:
		return
	_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0) if _hurt_flash > 0.0 else Color(1, 1, 1, 1)


## 处理移动输入（WASD + 左摇杆，§5.2）；锁链等束缚期间按 bind_move_mult 减速（0 则定身）
func _handle_movement() -> void:
	# get_vector 合成键盘与摇杆（死区走 InputMap）
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 移速 = 基础 × 加成（受软上限约束）× 事件移速（W14 灯塔共鸣），单位→像素换算
	var speed: float = base_move_speed * _effective_move_mult() * arena_speed_factor()
	if _bind_timer > 0.0:
		if _bind_move_mult <= 0.0:
			velocity = Vector2.ZERO
			move_and_slide()
			resolve_lighthouse_collision()
			resolve_arena_bounds()
			return
		speed *= _bind_move_mult
	velocity = input_vector * speed * UNIT_TO_PIXEL
	move_and_slide()
	resolve_lighthouse_collision()
	resolve_arena_bounds()


## 注入灯塔障碍（圆心世界坐标 + 碰撞半径像素；radius≤0 关闭）
func set_lighthouse_obstacle(center: Vector2, radius_px: float) -> void:
	_lh_center = center
	_lh_radius_px = maxf(radius_px, 0.0)
	_lh_enabled = _lh_radius_px > 0.0
	resolve_lighthouse_collision()


## 玩家与灯塔最小间距（像素）
func get_lighthouse_min_distance() -> float:
	if not _lh_enabled:
		return 0.0
	return BODY_RADIUS_PX + _lh_radius_px


## 灯塔推出：若侵入碰撞圆则推至边界（几何推出，非 Physics2D；机检可直调）
func resolve_lighthouse_collision() -> void:
	if not _lh_enabled:
		return
	var min_dist: float = BODY_RADIUS_PX + _lh_radius_px
	var offset: Vector2 = global_position - _lh_center
	var dist: float = offset.length()
	if dist >= min_dist:
		return
	if dist < 0.001:
		offset = Vector2.RIGHT
	else:
		offset = offset / dist
	global_position = _lh_center + offset * min_dist


## ---- 竞技场边界（config/map.json arena）----
## 以灯塔/开局点为圆心限制活动半径；避免地图无限大 + 怪刷太近的割裂感。
func _init_arena() -> void:
	var units: float = ConfigLoader.get_arena_radius_units()
	_arena_radius_px = units * UNIT_TO_PIXEL
	_arena_soft_push = ConfigLoader.get_arena_soft_push()


## 边界圆心（复用灯塔中心；未启用灯塔碰撞时 _lh_center 仍会被 set_lighthouse_obstacle 写入）
func get_arena_center() -> Vector2:
	return _lh_center


## 活动半径（像素；≤0 = 不限制）
func get_arena_radius() -> float:
	return _arena_radius_px


## 把玩家钳回竞技场内（几何钳位，非 Physics2D；每帧移动后调用）
func resolve_arena_bounds() -> void:
	if _arena_radius_px <= 0.0:
		return
	var limit: float = maxf(0.0, _arena_radius_px - BODY_RADIUS_PX)
	var offset: Vector2 = global_position - _lh_center
	var dist: float = offset.length()
	if dist <= limit or dist < 0.001:
		return
	global_position = _lh_center + offset / dist * limit
	arena_clamp_count += 1


## 活动半径启用且玩家曾触发过钳位（供 Debug 观测）
func has_arena_clamped() -> bool:
	return arena_clamp_count > 0


## 靠近边界时的移速衰减系数（soft_push=true 时生效；越界随距离线性衰减到 0.5）
func arena_speed_factor() -> float:
	if _arena_radius_px <= 0.0 or not _arena_soft_push:
		return 1.0
	var limit: float = maxf(1.0, _arena_radius_px - BODY_RADIUS_PX)
	var dist: float = (global_position - _lh_center).length()
	if dist <= limit:
		return 1.0
	# 越界后随超限距离线性衰减，取 60px 作为衰减宽度（约 1 秒跨越距离）
	var overshoot: float = dist - limit
	return clampf(1.0 - 0.5 * overshoot / 60.0, 0.5, 1.0)


## 设置移速加成（原始倍率；与角色&灯塔同乘区加算后在 _effective_move_mult 软衰减）
func set_move_speed_mult(mult: float) -> void:
	_move_speed_mult = mult


## 局内移速倍率：局内加成 + 角色&灯塔同乘区加算后软上限，再乘事件移速（灯塔共鸣 0.80 为惩罚，独立于软上限）
func _effective_move_mult() -> float:
	var raw: float = _move_speed_mult + (MetaSystem.get_move_speed_mult() - 1.0)
	return PassiveSystem.apply_soft_cap(raw, "move_speed") * EventSystem.get_move_speed_mult()


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
	# 拾取半径范围（半透明圈，方便调试观察）
	var radius: float = get_pickup_radius()
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.3, 0.85, 1.0, 0.15), 2.0)
	# 玩家本体：优先用 Sprite2D 精灵（见 _apply_sprite）；
	# 仅当精灵缺失（如资源未生成 / headless 无导入）时，才退回画一个圆。
	if _sprite == null or _sprite.texture == null:
		var body_color: Color = Color(0.9, 0.95, 1.0, 0.9) if _hurt_flash <= 0.0 else Color(1.0, 0.25, 0.25, 0.95)
		draw_circle(Vector2.ZERO, BODY_RADIUS_PX, body_color)
		draw_arc(Vector2.ZERO, BODY_RADIUS_PX, 0.0, TAU, 24, Color(0.3, 0.6, 1.0, 1.0), 2.0)
