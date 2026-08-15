extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

func _ready() -> void:
	print("================ DIAG: day -> skip hides DayPhaseUI, returns to NIGHT ================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	var shop_ui: Node = world.get_node("UI/ShopUI")
	var day_ui: Node = world.get_node("UI/DayPhaseUI")
	var shop_mgr: Node = world.get_node("ShopManager")
	# 自动处理升级三选一（出现即跳过），避免树卡暂停
	UpgradeManager.upgrade_offered.connect(func(_o: Array, _f: bool):
		UpgradeManager.skip())
	var frame: int = 0
	var reached_day: bool = false
	while frame < 60 * 55 and not reached_day:
		await get_tree().process_frame
		frame += 1
		if dn.get_phase() == DayNightStateMachine.Phase.DAY:
			reached_day = true
			break
		if GameState.is_over:
			break
	if not reached_day:
		print("[DIAG SKIP] FAIL: never reached DAY")
		main.queue_free()
		get_tree().quit(1)
		return
	# 模拟玩家点「继续下一夜」(触发 _on_shop_skip：exit_day + close + skip_day_phase)
	shop_ui.skip_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var day_hidden: bool = not day_ui.visible
	var shop_hidden: bool = not shop_ui.visible
	var back_to_night: bool = dn.get_phase() == DayNightStateMachine.Phase.NIGHT
	print("[DIAG SKIP] after skip: day_ui.visible=%s shop_ui.visible=%s phase=%s night=%d" % [
		day_ui.visible, shop_ui.visible, DayNightStateMachine.Phase.keys()[dn.get_phase()], GameState.current_night])
	main.queue_free()
	var ok: bool = day_hidden and shop_hidden and back_to_night
	print("[DIAG SKIP] RESULT day_hidden=%s shop_hidden=%s back_to_night=%s => %s" % [
		day_hidden, shop_hidden, back_to_night, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
