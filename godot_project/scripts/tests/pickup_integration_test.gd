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

	# 等待足够帧让吸附完成（snap≈0.1s / 560px/s，距离 30px，数帧即可）
	for i in 20:
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

	print("[Test] === 阶段4b：全速远离时珠子仍吸完（不跟跑）===")
	_pickup_system.clear_all()
	# 清掉前序经验，避免本段入账触发三选一暂停后续用例
	GameState.player_exp = 0
	while UpgradeManager.is_presenting():
		UpgradeManager.skip()
	_player.set_move_speed_mult(Player.MOVE_SPEED_SOFT_CAP)
	var chase_origin: Vector2 = Vector2(400, 300)
	_player.global_position = chase_origin
	var chase_gem: ExpGem = _pickup_system.spawn_exp_gem(chase_origin + Vector2(45, 0), 1)
	_assert(chase_gem != null, "跟跑回归：生成半径内经验珠")
	var chase_exp: int = chase_gem.exp_value
	var exp_before_chase: int = GameState.player_exp
	var run_speed: float = _player.get_current_speed()
	_assert(run_speed >= 400.0, "软上限移速 ≥400px/s（实际=%.1f）" % run_speed)
	# 旧 attract_speed=120 时无法追上；现应在 ~0.2s 内吸完
	for _f in 30:
		_player.global_position.x += run_speed / 60.0
		await get_tree().process_frame
	_assert(_pickup_system.active_gem_count() == 0, "全速远离时珠子仍被吸完（不跟跑）")
	_assert(GameState.player_exp == exp_before_chase + chase_exp, "跟跑回归经验入账 +%d" % chase_exp)
	while UpgradeManager.is_presenting():
		UpgradeManager.skip()
	_player.set_move_speed_mult(1.0)
	_player.global_position = Vector2(400, 300)

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

	print("[Test] === 阶段6：夜场宝箱触碰开启 ===")
	_pickup_system.clear_all()
	var chest_pool: ChestPool = ChestPool.new()
	chest_pool.name = "TestChestPool"
	chest_pool.scene = load("res://scripts/pickup/chest.tscn") as PackedScene
	chest_pool.pool_size = 8
	add_child(chest_pool)
	await get_tree().process_frame
	_pickup_system.bind_chest_pool(chest_pool)
	EventSystem.reset()
	RNG.set_seed(20260903)
	var spawned: int = _pickup_system.spawn_night_chests(_player.global_position)
	_assert(spawned >= 0 and spawned <= 2, "本夜宝箱数量在 0~2（实际=%d）" % spawned)
	# 固定种子下多次刷箱，确保至少开到 1 箱以覆盖触碰路径
	for _attempt in 8:
		_pickup_system.clear_all()
		if _pickup_system.spawn_night_chests(_player.global_position) > 0:
			break
	_assert(_pickup_system.active_chest_count() >= 1, "固定种子多次尝试后至少有 1 箱")
	GameState.damage_player(30, "test")
	var coins_before: int = GameState.tidecoins
	var hp_before: int = GameState.player_health
	var evo_before: int = GameState.evolution_items
	var chest_pos: Array[Vector2] = [Vector2.ZERO]
	_assert(_pickup_system.try_nearest_chest_position(_player.global_position, chest_pos, 2000.0), "能查到宝箱坐标")
	_player.global_position = chest_pos[0]
	for _i in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "触碰后宝箱已开启回收")
	var gained: bool = (
		GameState.tidecoins > coins_before
		or GameState.player_health > hp_before
		or GameState.evolution_items > evo_before
	)
	_assert(gained, "开箱发放了潮币/回血/进化道具之一")

	# 潮汐反转：get_chest_mult 消费端可刷出 > per_night_max 的箱数
	_pickup_system.clear_all()
	EventSystem.reset()
	EventSystem.apply_event("tidal_reversal")
	_assert(EventSystem.get_chest_mult() == 2.0, "潮汐反转宝箱倍率 =2")
	var saw_over_cap: bool = false
	for seed_i in 24:
		RNG.set_seed(20260904 + seed_i)
		_pickup_system.clear_all()
		if _pickup_system.spawn_night_chests(_player.global_position) > 2:
			saw_over_cap = true
			break
	_assert(saw_over_cap, "倍率×2 时可刷出超过 per_night_max(2) 的箱")
	EventSystem.reset()

	print("[Test] === 阶段7：刷箱先清场 + 灯塔圆心 + 软上限回退 ===")
	_pickup_system.clear_all()
	var lighthouse: Vector2 = Vector2(1000, 1000)
	RNG.set_seed(42)
	var n_a: int = _pickup_system.spawn_night_chests(lighthouse)
	var count_a: int = _pickup_system.active_chest_count()
	RNG.set_seed(42)
	var n_b: int = _pickup_system.spawn_night_chests(lighthouse)
	_assert(n_a == n_b, "同种子重复刷箱数量一致")
	_assert(_pickup_system.active_chest_count() == count_a, "重复刷箱先清场不叠箱（%d→%d）" % [
		count_a, _pickup_system.active_chest_count(),
	])
	if _pickup_system.active_chest_count() > 0:
		var cpos: Array[Vector2] = [Vector2.ZERO]
		_assert(_pickup_system.try_nearest_chest_position(lighthouse, cpos, 500.0), "箱在灯塔附近可查")
		var ring_dist: float = lighthouse.distance_to(cpos[0])
		_assert(ring_dist >= 180.0 - 0.5 and ring_dist <= 220.0 + 0.5, "箱距灯塔在外环 180~220（实际=%.1f）" % ring_dist)

	# 史诗箱 + 软上限 → 潮币回退
	_pickup_system.clear_all()
	# 开局已有鱼叉；升至满级以满足 has_evolvable_owned
	while GameState.get_weapon_level("harpoon") < GameState.max_weapon_level:
		if not GameState.add_weapon("harpoon"):
			break
	_assert(EvolutionSystem.has_evolvable_owned(), "满级鱼叉视为可进化持有")
	var soft: int = int(ConfigLoader.get_evolution_rules().get("soft_cap_unused_items", 2))
	GameState.evolution_items = soft
	var coins0: int = GameState.tidecoins
	var evo0: int = GameState.evolution_items
	var epic: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.EPIC)
	_assert(epic != null, "可生成史诗箱")
	_player.global_position = epic.global_position
	for _i2 in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "史诗箱已开启")
	_assert(GameState.evolution_items == evo0, "软上限下进化道具未增加")
	_assert(GameState.tidecoins > coins0, "软上限下史诗箱回退潮币")

	# 挣扎中开箱：不发奖、不转潮币（第5夜，避开首夜保护）
	_pickup_system.clear_all()
	MetaSystem.begin_run()
	GameState.current_night = 5
	GameState.player_health = 1
	GameState.damage_player(999, "test")
	_assert(GameState.is_struggling(), "已进入挣扎")
	var coins_s: int = GameState.tidecoins
	var evo_s: int = GameState.evolution_items
	var rare: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.RARE)
	_assert(rare != null, "挣扎测试可刷稀有箱")
	_player.global_position = rare.global_position
	for _i3 in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "挣扎中开箱仍回收")
	_assert(GameState.tidecoins == coins_s, "挣扎中开箱不发潮币")
	_assert(GameState.evolution_items == evo_s, "挣扎中开箱不发进化道具")
	MetaSystem.end_run()

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
