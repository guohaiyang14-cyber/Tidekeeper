# ============================================================================
# DayNightStateMachine — 昼夜循环状态机（W1 人工主导）
# 职责：管理「夜晚 ↔ 抉择之昼」状态切换
# 时长常量（SKILL.md §5.1）：常规 45s / 精英 60s / 天灾 90s / 终局 120s
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

## 夜晚时长常量（秒，SKILL.md §5.1）
const NIGHT_DURATION_NORMAL: float = 45.0   # 常规夜
const NIGHT_DURATION_ELITE: float = 60.0    # 精英夜（第 5 夜）
const NIGHT_DURATION_CALAMITY: float = 90.0 # 天灾夜（第 10/15/20 夜）
const NIGHT_DURATION_FINAL: float = 120.0   # 终局夜（第 20 夜 Boss 战）

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
	# 通关判定：第 20 夜结束 = 通关
	if _current_night >= 20:
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


## 根据夜次计算时长（§5.1）
func _get_night_duration(night: int) -> float:
	# 第 20 夜 = 终局
	if night == 20:
		return NIGHT_DURATION_FINAL
	# 第 10/15/20 夜 = 天灾夜
	if night == 10 or night == 15:
		return NIGHT_DURATION_CALAMITY
	# 第 5 夜 = 精英夜
	if night == 5:
		return NIGHT_DURATION_ELITE
	# 其他 = 常规
	return NIGHT_DURATION_NORMAL


## 获取夜次类型标签（调试/UI 用）
func _get_night_type_label(night: int) -> String:
	if night == 20:
		return "终局"
	if night == 10 or night == 15:
		return "天灾"
	if night == 5:
		return "精英"
	return "常规"


## 是否天灾夜
func is_calamity_night() -> bool:
	return _current_night in [10, 15, 20]


## 是否精英夜
func is_elite_night() -> bool:
	return _current_night == 5
