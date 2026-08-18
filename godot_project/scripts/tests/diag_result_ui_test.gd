# ============================================================================
# DiagResultUI — 加载真实 main 场景，验证「血量归零 → 结算/死因界面出现 + 树暂停」
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/diag_result_ui_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("DiagResultUI (加载真实 main 场景，验证结算界面显示)")
	print("============================================================")
	# 清空局外进度：本场景加载真实 World（会 begin_run），需干净存档才能断言 max_health=100
	MetaSystem.reset_progress()
	# W17 挫败感复活会改变致死语义；本诊断专验「致死→结算界面」管线，故关闭复活以验证原始流程
	ConfigLoader.frustration["first_night"]["enabled"] = false
	ConfigLoader.frustration["struggle"]["enabled"] = false
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	var result_ui: Node = world.get_node("UI/ResultUI")

	# 1) 初始：ResultUI 隐藏，树未暂停
	_assert(not result_ui.visible, "初始 ResultUI 隐藏")
	_assert(not get_tree().paused, "初始树未暂停")

	# 2) 触发游戏结束（血量归零）
	GameState.damage_player(99999)
	await get_tree().process_frame
	await get_tree().process_frame

	# 3) 结算界面显示 + 树暂停 + 阶段冻结 + game_over 触发
	_assert(result_ui.visible, "血量归零后 ResultUI 显示（结算/死因界面）")
	_assert(get_tree().paused, "血量归零后树暂停（结算页阻止继续操作）")
	_assert(dn.get_phase() == DayNightStateMachine.Phase.INIT, "阶段冻结到 INIT（不滚入抉择之昼）")
	_assert(GameState.is_over, "is_over 标记已置位")
	_assert(result_ui.get_child_count() > 0, "ResultUI 已构建结算页框架（标题/死因/统计/按钮）")

	# 4) HUD 在游戏结束（树暂停、_process 停跑）后仍显示真实 HP，不冻结致死前旧值
	var dbg: Node = world.get_node_or_null("UI/HUD/DebugLabel")
	_assert(dbg != null and "HP: 0/100" in dbg.text, "游戏结束后 HUD 显示真实 HP 0/100（不冻结旧值 21）")

	get_tree().paused = false  # 结算曾暂停树；释放前恢复以免 ObjectDB 泄漏
	main.queue_free()
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
