# ============================================================================
# ExpGem — 经验珠可池化节点（W2）
# 职责：经验掉落物，被玩家拾取后增加 GameState 经验
# 数据源：§5.2 拾取（自动吸附）、§6.2 经验表
# 红线：走对象池（PickupPool），禁止运行时 instantiate；不用 Physics2D
# 状态：IDLE（静止）→ ATTRACTED（飞向玩家）→ 被 PickupSystem 回收
# ============================================================================
class_name ExpGem
extends Node2D

## 经验珠状态
enum State {
	IDLE,       # 静止等待
	ATTRACTED,  # 被玩家吸引，飞向玩家
}

## 经验珠品质（影响颜色、大小、经验倍率）
enum Quality {
	COMMON,     # 普通 — 淡青
	UNCOMMON,   # 精良 — 翠绿
	RARE,       # 稀有 — 深蓝
	EPIC,       # 史诗 — 紫色
}

## 品质名称（调试 / UI 用）
const QUALITY_NAMES: Array[String] = ["普通", "精良", "稀有", "史诗"]

## 品质颜色（静止时实心色）
const QUALITY_COLORS: Array[Color] = [
	Color(0.7, 0.85, 1.0, 0.9),   # COMMON — 淡青
	Color(0.3, 1.0, 0.4, 0.95),   # UNCOMMON — 翠绿
	Color(0.3, 0.55, 1.0, 1.0),   # RARE — 深蓝
	Color(0.85, 0.35, 1.0, 1.0),  # EPIC — 紫色
]

## 品质光晕色（飞行时外圈发光）
const QUALITY_GLOWS: Array[Color] = [
	Color(0.7, 0.85, 1.0, 0.20),  # COMMON
	Color(0.3, 1.0, 0.4, 0.25),   # UNCOMMON
	Color(0.3, 0.55, 1.0, 0.30),  # RARE
	Color(0.85, 0.35, 1.0, 0.35), # EPIC
]

## 品质大小倍率（高品质珠子更大）
const QUALITY_SIZE_MULT: Array[float] = [1.0, 1.15, 1.3, 1.5]

## 珠子基础半径（绘制 + 碰撞判定用）
const GEM_RADIUS: float = 8.0

## 光晕基础半径（飞行时外圈发光）
const GLOW_RADIUS: float = 14.0

## 经验值（由 PickupSystem.spawn_exp_gem 设置，已含品质倍率）
var exp_value: int = 1

## 当前品质
var _quality: Quality = Quality.COMMON

## 当前状态
var _state: State = State.IDLE

## 吸引速度（像素/秒，由 PickupSystem 每帧驱动；须高于玩家移速）
var _attract_speed: float = 0.0

## 最大吸附时长（秒）：由 start_attract 写入（表驱动）；0=未吸附
var _attract_snap_time: float = 0.0

## 飞行目标（玩家位置，由 PickupSystem 每帧更新）
var _target_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 5  # 经验珠画在敌人之上


func _draw() -> void:
	# W2 占位视觉：品质决定颜色和大小；飞行时额外光晕
	var base_color: Color = QUALITY_COLORS[_quality]
	var glow_color: Color = QUALITY_GLOWS[_quality]
	var size_mult: float = QUALITY_SIZE_MULT[_quality]
	var radius: float = GEM_RADIUS * size_mult
	var glow_r: float = GLOW_RADIUS * size_mult

	if _state == State.ATTRACTED:
		# 飞行中：外圈光晕 + 内圈实心 + 高亮描边
		draw_circle(Vector2.ZERO, glow_r, glow_color)
		draw_circle(Vector2.ZERO, radius, base_color)
		draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.8), 1.5)
	else:
		# 静止：实心 + 淡白边
		draw_circle(Vector2.ZERO, radius, base_color)
		draw_arc(Vector2.ZERO, radius + 1.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.4), 1.0)


# ============================================================================
# 对象池接口（_on_acquire / _on_release 由 ObjectPool 调用）
# ============================================================================

## 从池中取出时重置状态
func _on_acquire() -> void:
	_state = State.IDLE
	_quality = Quality.COMMON
	exp_value = 1
	_attract_speed = 0.0
	_attract_snap_time = 0.0
	_target_pos = Vector2.ZERO
	queue_redraw()


## 归还池中时清理
func _on_release() -> void:
	_state = State.IDLE
	_quality = Quality.COMMON
	exp_value = 1
	_attract_speed = 0.0
	_attract_snap_time = 0.0
	_target_pos = Vector2.ZERO
	queue_redraw()


# ============================================================================
# 拾取系统驱动接口
# ============================================================================

## 开始被吸引（PickupSystem 检测到玩家进入拾取半径时调用；snap_time 来自 pickups.json）
func start_attract(target: Vector2, speed: float, snap_time: float) -> void:
	if _state == State.ATTRACTED:
		return
	_state = State.ATTRACTED
	_attract_speed = speed
	_attract_snap_time = maxf(0.05, snap_time)
	_target_pos = target
	queue_redraw()


## 每帧更新位置（由 PickupSystem._process 调用）
func update_attract(target: Vector2, delta: float) -> void:
	_target_pos = target
	var to_target: Vector2 = _target_pos - global_position
	var dist: float = to_target.length()
	if dist < 1.0:
		return
	# 基础速 + 按 snap_time 抬升：半径内快速吸完，且快于玩家移速
	var snap: float = maxf(_attract_snap_time, 0.05)
	var speed: float = maxf(_attract_speed, dist / snap)
	var step: float = minf(speed * delta, dist)
	global_position += to_target.normalized() * step


## 是否处于吸引状态
func is_attracted() -> bool:
	return _state == State.ATTRACTED


## 重置为 IDLE（PickupSystem 可在特殊情况下取消吸引）
func reset_to_idle() -> void:
	_state = State.IDLE
	queue_redraw()


## 设置品质（影响颜色、大小；由 PickupSystem 在生成时调用）
func set_quality(q: Quality) -> void:
	_quality = q
	queue_redraw()


## 获取当前品质
func get_quality() -> Quality:
	return _quality
