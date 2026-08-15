# ============================================================================
# GameOverHaltTest — 加载真实 main 场景的端到端集成测试
# 修复验证：
#   1) 开局授予数据驱动默认武器（§4.2），且武器实例已生成可自动开火
#   2) 玩家血量归零触发游戏结束，昼夜循环冻结（不滚入抉择之昼）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/game_over_halt_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("GameOverHalt Integration Test (加载真实 main 场景)")
	print("============================================================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	# 等待 World._ready 完成（start_new_run + sync_from_game_state + day_night.start_run）
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	var wm: Node = world.get_node("WeaponManager")

	# 1) 开局应授予默认武器，且实例已生成
	_assert(GameState.weapon_slots.has("harpoon"), "开局授予 harpoon（数据驱动默认武器）")
	_assert(dn.get_phase() == DayNightStateMachine.Phase.NIGHT, "开局进入夜晚战斗阶段")
	_assert(wm.get_weapons().size() >= 1, "开局已生成武器实例（可自动开火）")

	# 2) 夜晚计时器在跑动（循环确实在运行）
	var rem0: float = dn.get_night_remaining()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var rem1: float = dn.get_night_remaining()
	_assert(rem1 < rem0, "夜晚计时器在递减（循环运行：%.2f→%.2f）" % [rem0, rem1])

	# 3) 强制血量归零 → 游戏结束 → 昼夜循环冻结，不滚入抉择之昼
	GameState.damage_player(99999)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(GameState.is_over, "hp 归零触发 is_over 标记")
	_assert(dn.get_phase() == DayNightStateMachine.Phase.INIT, "游戏结束后昼夜循环冻结(INIT)，未滚入 DAY")
	# 即便再推进 30 帧，仍保持冻结（夜晚计时器不再递减）
	for _i in 30:
		await get_tree().process_frame
	_assert(dn.get_phase() == DayNightStateMachine.Phase.INIT, "冻结后 30 帧内仍保持 INIT（不进入抉择之昼）")

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
