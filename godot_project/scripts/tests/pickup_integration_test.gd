# ============================================================================
# PickupIntegrationTest — 经验珠吸附/收集集成测试（W2）
# 运行：godot --headless --path godot_project res://scenes/tests/pickup_integration_test.tscn
# 退出码：0=全部通过，1=有失败
# ============================================================================
extends Node

const EXP_GEM_SCENE := preload("res://scenes/exp_gem.tscn")

var _passed: int = 0
var _failed: int = 0
var _player: Player
var _pool: PickupPool
var _pickup_system: PickupSystem
var _test_phase: int = 0  # 0=setup, 1=spawning, 2=waiting_collect, 3=done


func _ready() -> void:
	print("============================================================")
	print("Pickup Integration Test (W2)")
	print("============================================================")
	_setup_scene()
	# 等一帧让对象池初始化
	await get_tree().process_frame
	_test_spawn_and_collect()


func _setup_scene() -> void:
	# 初始化 GameState
	GameState.start_new_run("watcher", 42)

	# 创建 Player
	_player = Player.new()
	_player.character_id = "watcher"
	_player.global_position = Vector2(400, 300)
	add_child(_player)

	# 创建 PickupPool
	_pool = PickupPool.new()
	_pool.name = "TestPickupPool"
	_pool.scene = EXP_GEM_SCENE
	_pool.pool_size = 20
	add_child(_pool)
	await get_tree().process_frame

	# 创建 PickupSystem（手动接线，不用场景路径）
	_pickup_system = PickupSystem.new()
	_pickup_system.name = "TestPickupSystem"
	add_child(_pickup_system)
	_pickup_system.bind(_pool, _player)

	print("[Test] 场景搭建完成: player=%s pool=%d" % [
		_player.global_position, _pool.available_count(),
	])


var _expected_exp_near: int = 0  # 近距离珠子总经验（品质随机，运行时计算）
var _expected_exp_far: int = 0   # 远距离珠子经验


func _test_spawn_and_collect() -> void:
	print("[Test] === 阶段1：生成经验珠（品质随机）===")

	# 在玩家附近生成 3 颗经验珠（在拾取半径内）
	var near_pos: Vector2 = _player.global_position + Vector2(30, 0)
	var g1: ExpGem = _pickup_system.spawn_exp_gem(near_pos, 5)
	var g2: ExpGem = _pickup_system.spawn_exp_gem(near_pos + Vector2(0, 20), 3)
	var g3: ExpGem = _pickup_system.spawn_exp_gem(near_pos + Vector2(-15, 10), 2)
	_expected_exp_near = g1.exp_value + g2.exp_value + g3.exp_value
	print("[Test] 品质: %s/%s/%s → 经验 %d/%d/%d (合计 %d)" % [
		ExpGem.QUALITY_NAMES[g1.get_quality()], ExpGem.QUALITY_NAMES[g2.get_quality()],
		ExpGem.QUALITY_NAMES[g3.get_quality()], g1.exp_value, g2.exp_value, g3.exp_value,
		_expected_exp_near,
	])

	_assert(_pickup_system.active_gem_count() == 3, "生成 3 颗经验珠")
	_assert(GameState.player_exp == 0, "初始经验为 0")

	print("[Test] === 阶段2：等待吸附收集（半径内，应自动飞向玩家）===")
	_test_phase = 2

	# 等待足够帧让吸附完成（速度 120px/s，距离 30px，约 0.25s ≈ 15 帧）
	for i in 30:
		await get_tree().process_frame

	_assert(_pickup_system.active_gem_count() == 0, "3 颗珠全部被收集")
	_assert(GameState.player_exp == _expected_exp_near, "经验总计 %d (含品质倍率)" % _expected_exp_near)

	print("[Test] === 阶段3：远距离珠子不吸附 ===")
	# 在远处生成 1 颗（超出拾取半径 60）
	var far_pos: Vector2 = _player.global_position + Vector2(200, 0)
	var gf: ExpGem = _pickup_system.spawn_exp_gem(far_pos, 8)
	_expected_exp_far = gf.exp_value
	print("[Test] 远珠品质: %s → 经验 %d" % [ExpGem.QUALITY_NAMES[gf.get_quality()], _expected_exp_far])

	for i in 10:
		await get_tree().process_frame

	_assert(_pickup_system.active_gem_count() == 1, "远珠仍在场")
	_assert(GameState.player_exp == _expected_exp_near, "远珠未被收集，经验不变")

	print("[Test] === 阶段4：玩家移动靠近后收集 ===")
	# 移动玩家靠近远珠
	_player.global_position = far_pos - Vector2(30, 0)
	for i in 30:
		await get_tree().process_frame

	_assert(_pickup_system.active_gem_count() == 0, "移动后远珠被收集")
	_assert(GameState.player_exp == _expected_exp_near + _expected_exp_far, "经验总计 %d" % (_expected_exp_near + _expected_exp_far))

	print("[Test] === 阶段5：spawn_exp_gems 总经验守恒（单次品质 × 拆分）===")
	_pickup_system.clear_all()
	var batch_base: int = 10
	var batch_count: int = 3
	var far_batch: Vector2 = _player.global_position + Vector2(300, 0)
	_pickup_system.spawn_exp_gems(far_batch, batch_base, batch_count)
	_assert(_pickup_system.active_gem_count() == batch_count, "批量生成 %d 颗" % batch_count)
	var batch_total: int = _pickup_system.active_exp_total()
	var valid_mult: bool = (
		batch_total == batch_base
		or batch_total == batch_base * 2
		or batch_total == batch_base * 5
		or batch_total == batch_base * 10
	)
	_assert(valid_mult, "批量总经验=%d 为 base×品质倍率" % batch_total)

	_print_result()
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _print_result() -> void:
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	print("============================================================")
