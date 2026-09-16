# ============================================================================
# A5FeelTest — 手感收口机检（1.1.5 / 1.2.1 / 1.2.4）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/a5_feel_test.tscn
# 退出码：0=全部通过，1=有失败
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _CLEANUP := preload("res://scripts/tests/test_cleanup.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("A5 Feel Test (skip focus / move speed / lighthouse collision)")
	print("============================================================")
	await _test_watcher_move_speed()
	await _test_lighthouse_pushout()
	await _test_day_skip_focus_and_keys()
	print("------------------------------------------------------------")
	print("机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


## 1.2.1：守望者基础移速 4.2 单位/秒 → 252 px/s（无局内加成）
func _test_watcher_move_speed() -> void:
	print("[1.2.1 基础移速]")
	# 未 begin_run：Meta 特性不计入，保证纯基线
	if MetaSystem.is_run_active():
		MetaSystem.end_run()
	var cfg_speed: float = ConfigLoader.get_character_move_speed("watcher")
	_assert(is_equal_approx(cfg_speed, 4.2), "config watcher.move_speed == 4.2 (got %.3f)" % cfg_speed)
	var p: Player = Player.new()
	p.character_id = "watcher"
	add_child(p)
	await get_tree().process_frame
	# 再确认一次：Player._ready 期间其它系统不应 begin_run
	if MetaSystem.is_run_active():
		MetaSystem.end_run()
	p.apply_run_character("watcher")
	_assert(is_equal_approx(p.base_move_speed, 4.2), "Player.base_move_speed == 4.2")
	var want_px: float = 4.2 * Player.UNIT_TO_PIXEL
	_assert(
		is_equal_approx(p.get_current_speed(), want_px),
		"get_current_speed == %.1f px/s (got %.1f)" % [want_px, p.get_current_speed()]
	)
	# 固定输入一帧：位移 ≈ speed * delta（--fixed-fps 60 → delta=1/60）
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_right")
	var moved: float = p.global_position.x
	var expect_step: float = want_px / 60.0
	# 允许 2 帧累计与浮点误差
	_assert(
		moved > expect_step * 0.5 and moved < expect_step * 3.5,
		"右移一帧量级 ≈ speed*delta（moved=%.2f expect~%.2f）" % [moved, expect_step]
	)
	_CLEANUP.free_node(p)


## 1.2.4：侵入灯塔圆 → resolve 后距圆心 ≥ 本体+灯塔半径
func _test_lighthouse_pushout() -> void:
	print("[1.2.4 灯塔碰撞推出]")
	var units: float = ConfigLoader.get_lighthouse_collision_radius_units()
	_assert(units > 0.0, "map.json lighthouse.collision_radius_units > 0 (got %.3f)" % units)
	var radius_px: float = units * Player.UNIT_TO_PIXEL
	var center: Vector2 = Vector2(400, 300)
	var p: Player = Player.new()
	add_child(p)
	await get_tree().process_frame
	p.set_lighthouse_obstacle(center, radius_px)
	p.global_position = center + Vector2(2, 0)
	p.resolve_lighthouse_collision()
	var min_dist: float = Player.BODY_RADIUS_PX + radius_px
	var dist: float = p.global_position.distance_to(center)
	_assert(
		dist >= min_dist - 0.05,
		"推出后 distance=%.2f >= min=%.2f" % [dist, min_dist]
	)
	_assert(
		is_equal_approx(p.get_lighthouse_min_distance(), min_dist),
		"get_lighthouse_min_distance == %.2f" % min_dist
	)
	_CLEANUP.free_node(p)


## 1.1.5：进昼后 Skip 获焦；skip / Esc → 回 NIGHT
func _test_day_skip_focus_and_keys() -> void:
	print("[1.1.5 跳过焦点与快捷键]")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: World = main as World
	if world == null:
		_assert(false, "main 根节点应为 World")
		_CLEANUP.free_node(main)
		return
	UpgradeManager.upgrade_offered.connect(func(_o: Array, _f: bool):
		UpgradeManager.skip())
	# 快进首夜计时 → 抉择之昼（与 prototype_acceptance 同路径）
	world.day_night._process(world.day_night.get_night_duration() + 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(
		world.day_night.get_phase() == DayNightStateMachine.Phase.DAY,
		"夜尽进入抉择之昼"
	)
	_assert(world.shop_ui.visible, "昼阶段商店可见")
	_assert(world.shop_ui.has_skip_focus(), "开店后 Skip 获焦")
	# skip 动作（Space/Enter/Q 同绑）
	var skip_ev := InputEventAction.new()
	skip_ev.action = "skip"
	skip_ev.pressed = true
	world._unhandled_input(skip_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(
		world.day_night.get_phase() == DayNightStateMachine.Phase.NIGHT,
		"skip 动作 → 回 NIGHT（夜=%d）" % world.day_night.get_current_night()
	)
	# 再进昼测 Esc
	world.day_night._process(world.day_night.get_night_duration() + 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(
		world.day_night.get_phase() == DayNightStateMachine.Phase.DAY,
		"第二夜尽再进昼"
	)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	world._unhandled_input(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(
		world.day_night.get_phase() == DayNightStateMachine.Phase.NIGHT,
		"Esc → 回 NIGHT"
	)
	_CLEANUP.free_node(main)
