extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _CLEANUP := preload("res://scripts/tests/test_cleanup.gd")

func _ready() -> void:
	print("================ DIAG: night timer -> DAY transition ================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: Node = main
	var dn: Node = world.get_node("DayNightStateMachine")
	dn.phase_changed.connect(func(p: int):
		print("[DIAG] phase_changed -> %s (night=%d)" % [DayNightStateMachine.Phase.keys()[p], GameState.current_night]))
	# 自动处理升级三选一（出现即跳过），避免树卡在暂停导致夜晚不结束
	UpgradeManager.upgrade_offered.connect(func(_o: Array, _f: bool):
		UpgradeManager.skip())
	var frame: int = 0
	var reached_day: bool = false
	while frame < 60 * 55:  # 最多 55s
		await get_tree().process_frame
		frame += 1
		if dn.get_phase() == DayNightStateMachine.Phase.DAY:
			reached_day = true
			print("[DIAG] REACHED DAY at t=%.1fs (night=%d)" % [frame / 60.0, GameState.current_night])
			break
		if frame % 120 == 0:
			print("[DIAG] t=%.1fs phase=%s timer=%.2f hp=%d tree_paused=%s" % [
				frame / 60.0, DayNightStateMachine.Phase.keys()[dn.get_phase()],
				dn.get_night_remaining(), GameState.player_health, get_tree().paused])
		if GameState.is_over:
			print("[DIAG] GAME OVER at t=%.1fs phase=%s" % [frame / 60.0, DayNightStateMachine.Phase.keys()[dn.get_phase()]])
			break
	_CLEANUP.free_node(main)
	get_tree().quit(0 if reached_day else 1)
