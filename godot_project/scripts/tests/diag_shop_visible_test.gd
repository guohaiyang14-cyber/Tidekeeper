extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _CLEANUP := preload("res://scripts/tests/test_cleanup.gd")

func _ready() -> void:
	print("================ DIAG: ShopUI visible after DAY (faithful play) ================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	var shop_ui: Node = world.get_node("UI/ShopUI")
	var day_ui: Node = world.get_node("UI/DayPhaseUI")
	var shop_mgr: Node = world.get_node("ShopManager")
	dn.phase_changed.connect(func(p: int):
		print("[DIAG] phase_changed -> %s (night=%d)" % [DayNightStateMachine.Phase.keys()[p], GameState.current_night]))
	# 模拟真实游玩：出现升级三选一就选第 1 项（自然解暂停），不自动跳过
	UpgradeManager.upgrade_offered.connect(func(offers: Array, _f: bool):
		if offers.size() > 0:
			UpgradeManager.apply_offer(0)
		else:
			UpgradeManager.skip())
	var frame: int = 0
	var reached_day: bool = false
	var shop_visible_at_day: bool = false
	var day_ui_visible_at_day: bool = false
	var paused_at_day: bool = false
	while frame < 60 * 55:
		await get_tree().process_frame
		frame += 1
		if dn.get_phase() == DayNightStateMachine.Phase.DAY:
			reached_day = true
			shop_visible_at_day = shop_ui.visible
			day_ui_visible_at_day = day_ui.visible
			paused_at_day = get_tree().paused
			print("[DIAG] REACHED DAY t=%.1fs night=%d day_ui.visible=%s shop_ui.visible=%s tree_paused=%s shop_items=%d" % [
				frame / 60.0, GameState.current_night, day_ui_visible_at_day, shop_visible_at_day, paused_at_day, shop_mgr.get_current_items().size()])
			break
		if frame % 120 == 0:
			print("[DIAG] t=%.1fs phase=%s timer=%.2f hp=%d tree_paused=%s day_ui.visible=%s shop_ui.visible=%s" % [
				frame / 60.0, DayNightStateMachine.Phase.keys()[dn.get_phase()],
				dn.get_night_remaining(), GameState.player_health, get_tree().paused, day_ui.visible, shop_ui.visible])
		if GameState.is_over:
			print("[DIAG] GAME OVER at t=%.1fs phase=%s" % [frame / 60.0, DayNightStateMachine.Phase.keys()[dn.get_phase()]])
			break
	_CLEANUP.free_node(main)
	var ok: bool = reached_day and shop_visible_at_day and day_ui_visible_at_day and not paused_at_day
	print("[DIAG] RESULT reached_day=%s day_ui_visible=%s shop_visible=%s not_paused=%s => %s" % [
		reached_day, day_ui_visible_at_day, shop_visible_at_day, not paused_at_day, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
