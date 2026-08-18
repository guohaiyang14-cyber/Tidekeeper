# ============================================================================
# RestSystem — 休息 + 灯塔回血（W13，autoload）
# 职责：判定休息夜；抉择之昼入口由 World 调用 try_apply_rest_for_night
# 设计：§3.2 休息——每 N 夜免费大回血（N 读 upgrade.json rest_interval_nights）
# 红线：间隔/回血走 config + GameState；自身无状态
# ============================================================================
extends Node


func _ready() -> void:
	print("[RestSystem] 就绪")


## 该夜是否为休息夜（每 N 夜：N/2N/…；第 0 夜非休息）
func is_rest_night(night: int) -> bool:
	var interval: int = ConfigLoader.get_rest_interval_nights()
	if interval <= 0:
		return false
	return night > 0 and night % interval == 0


## 灯塔回血：将玩家生命回复至上限，返回实际回复量（已回满返回 0）
func apply_rest() -> int:
	return GameState.heal_player_to_full()


## 若该夜为休息夜则回血至上限，否则返回 0（World 进昼时调用）
func try_apply_rest_for_night(night: int) -> int:
	if not is_rest_night(night):
		return 0
	var healed: int = apply_rest()
	if healed > 0:
		print("[RestSystem] 第 %d 夜休息：灯塔回血 +%d" % [night, healed])
	else:
		print("[RestSystem] 第 %d 夜休息：生命已满" % night)
	return healed


## 灯塔 regen_per_night：每次进昼、未满血时回复（休息夜若已回满则自然为 0）
func try_apply_night_regen() -> int:
	var regen: int = MetaSystem.get_regen_per_night()
	if regen <= 0:
		return 0
	var healed: int = GameState.heal_player(regen)
	if healed > 0:
		print("[RestSystem] 灯塔 regen +%d" % healed)
	return healed
