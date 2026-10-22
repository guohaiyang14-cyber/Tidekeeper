# ============================================================================
# DayNightStateMachine — 昼夜循环状态机（W1 人工主导）
# 职责：管理「夜晚 ↔ 抉择之昼」状态切换
# 夜长与夜型映射：config/night.json（ConfigLoader.get_night_config()）——
#   常规/精英/天灾/终局时长与夜次映射均在表内（当前值 45/60/90/120s，
#   对齐主设计文档 §5.1）；调参改表不改脚本（SKILL.md §4.2 禁止硬编码数值）
# 红线：夜晚结束无条件进昼（敌人未清完也切换）；抉择之昼无强制倒计时
# 架构：World 节点持有本状态机实例
# ============================================================================
class_name DayNightStateMachine
extends Node

# 状态枚举
enum Phase {
	INIT,       # 初始（未开始）
	NIGHT,      # 夜晚（战斗）
	DAY,        # 抉择之昼（商店/三选一/事件）
	TRANSITION  # 切换过渡（动画/淡入淡出）
}

# 信号
signal phase_changed(phase: Phase)
signal night_tick(remaining: float)

var _phase: Phase = Phase.INIT
var _current_night: int = 0
var _night_timer: float = 0.0
var _night_duration: float = 0.0


func _ready() -> void:
	print("[DayNight] 状态机就绪（等待开始）")


func _process(delta: float) -> void:
	if _phase == Phase.NIGHT:
		_night_timer -= delta
		night_tick.emit(maxf(0.0, _night_timer))
		if _night_timer <= 0.0:
			_end_night()


## 开始新局（进入第 1 夜前的初始化）
func start_run() -> void:
	_current_night = 0
	_phase = Phase.INIT
	enter_next_night()


## 进入下一夜
func enter_next_night() -> void:
	_current_night += 1
	_night_duration = _get_night_duration(_current_night)
	_night_timer = _night_duration
	_set_phase(Phase.NIGHT)
	GameState.enter_night(_current_night)
	print("[DayNight] 进入第 %d 夜 (时长 %.0fs, 类型=%s)" % [
		_current_night, _night_duration, _get_night_type_label(_current_night)
	])


## 夜晚结束（无条件进昼，SKILL.md §5.1）
func _end_night() -> void:
	_set_phase(Phase.TRANSITION)
	GameState.end_night()
	# 挣扎未达标会在 end_night 判负；World.stop() 已把阶段打成 INIT，禁止再进昼开商店
	if GameState.is_over:
		return
	# 通关判定：终局夜结束 = 通关（终局夜次来自 config/night.json night_types.final_night）
	if is_final_night_number(_current_night):
		GameState.trigger_game_win()
		_set_phase(Phase.INIT)
		return
	_set_phase(Phase.DAY)


## 玩家在抉择之昼手动跳过 → 进入下一夜
func skip_day_phase() -> void:
	if _phase != Phase.DAY:
		push_warning("[DayNight] 非昼阶段无法跳过")
		return
	enter_next_night()


## 强制停止昼夜循环（游戏结束/通关时调用，冻结夜晚计时器并阻止后续阶段切换）
func stop() -> void:
	_night_timer = 0.0
	_phase = Phase.INIT
	print("[DayNight] 循环已停止（冻结）")


## 获取当前阶段
func get_phase() -> Phase:
	return _phase


## 获取当前夜数
func get_current_night() -> int:
	return _current_night


## 获取夜晚剩余时间
func get_night_remaining() -> float:
	return maxf(0.0, _night_timer)


## 获取夜晚总时长
func get_night_duration() -> float:
	return _night_duration


## 设置阶段（发射信号）
func _set_phase(new_phase: Phase) -> void:
	if _phase == new_phase:
		return
	_phase = new_phase
	phase_changed.emit(new_phase)


## 根据夜次计算时长（§5.1）；静态入口供 EnemySpawner / BotSuite 共用，避免双份常量漂移
## 时长与夜型映射均来自 config/night.json（durations / night_types）
static func duration_for_night(night: int) -> float:
	return ConfigLoader.get_night_type_duration(_night_type_for(night))


## 夜次 → 夜型（normal/elite/calamity/final；config/night.json night_types）
static func _night_type_for(night: int) -> String:
	var types: Dictionary = ConfigLoader.get_night_config().get("night_types", {}) as Dictionary
	if night == int(types.get("final_night", 20)):
		return "final"
	if night in _as_int_array(types.get("calamity_nights", [])):
		return "calamity"
	if night in _as_int_array(types.get("elite_nights", [])):
		return "elite"
	return String(types.get("default_type", "normal"))


## Variant → int 数组（容错：非数组返回空表）
static func _as_int_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			out.append(int(x))
	return out


## 是否精英夜（表 night_types.elite_nights）
static func is_elite_night_number(night: int) -> bool:
	return _night_type_for(night) == "elite"


## 是否天灾夜（表 night_types.calamity_nights，含终局夜）
static func is_calamity_night_number(night: int) -> bool:
	var t: String = _night_type_for(night)
	return t == "calamity" or t == "final"


## 是否终局夜（表 night_types.final_night）
static func is_final_night_number(night: int) -> bool:
	return _night_type_for(night) == "final"


## 实例包装（机检 / 内部调用）
func _get_night_duration(night: int) -> float:
	return duration_for_night(night)


## 获取夜次类型标签（调试/UI 用；映射来自 config/night.json）
func _get_night_type_label(night: int) -> String:
	match _night_type_for(night):
		"final":
			return "终局"
		"calamity":
			return "天灾"
		"elite":
			return "精英"
	return "常规"


## 是否天灾夜（含终局夜；表 night_types.calamity_nights + final_night）
func is_calamity_night() -> bool:
	return is_calamity_night_number(_current_night)


## 是否精英夜（表 night_types.elite_nights）
func is_elite_night() -> bool:
	return is_elite_night_number(_current_night)
