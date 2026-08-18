# ============================================================================
# DiagResultWinRestart — 验证「通关结算界面」显示 + 「重开」回到干净战斗
# 说明：reload_current_scene() 会重载当前场景（测试场景下即本测试场景，会自循环），
#       故重开流程用「手动新建一份 main 实例」代理验证（reload 的本质就是新建 clean main）。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/diag_result_win_restart_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _CLEANUP := preload("res://scripts/tests/test_cleanup.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("DiagResultWinRestart (通关结算 + 重开)")
	print("============================================================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	var result_ui: Node = world.get_node("UI/ResultUI")

	# 1) 模拟通关：强制第 20 夜并触发 game_win
	GameState.current_night = 20
	GameState.trigger_game_win()
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(result_ui.visible, "通关后 ResultUI 显示（通关结算界面）")
	_assert(get_tree().paused, "通关后树暂停")
	_assert(GameState.is_over, "通关置 is_over（与 game_over 共用结束标记，重开由 start_new_run 复位）")
	_assert(result_ui.get_child_count() > 0, "ResultUI 已构建结算页框架")

	# 2) 代理「重开」：手动新建一份 clean main（等价于 reload_current_scene 的结果）
	#    验证新局回到干净战斗（world._ready → UpgradeManager.reset 会解除暂停）
	var fresh: Node = MAIN_SCENE.instantiate()
	add_child(fresh)
	await get_tree().process_frame
	await get_tree().process_frame

	var fdn: Node = fresh.get_node("DayNightStateMachine")
	var fres: Node = fresh.get_node("UI/ResultUI")
	_assert(fdn.get_phase() == DayNightStateMachine.Phase.NIGHT, "重开后回到夜晚战斗阶段")
	_assert(not get_tree().paused, "重开后树恢复未暂停（UpgradeManager.reset 兜底）")
	_assert(fres != null and not fres.visible, "重开后结算界面隐藏")
	_assert(GameState.is_over == false, "重开后 is_over 复位")
	_assert(GameState.player_health == GameState.player_max_health, "重开后 HP 满血")

	_CLEANUP.free_node(main)
	_CLEANUP.free_node(fresh)
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
