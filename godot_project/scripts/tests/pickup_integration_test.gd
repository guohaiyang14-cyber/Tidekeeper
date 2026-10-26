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


## 2026-10-26 经验表改为「按每夜收入反推目标等级」模型（E1=18，20 夜目标 Lv3~Lv21），
## 不再是原来的 E1=42。收集 21 点就会升到 Lv2 且余 3，所以不能再直接断言
## player_exp == 累计值——改为按 ExpTable 把累计经验折算成「预期等级 + 预期余量」再比对。
func _expected_progress(total_exp: int) -> Vector2i:
	var lv: int = 1
	var rem: int = total_exp
	while true:
		var need: int = ExpTable.get_exp(lv)
		if need <= 0 or rem < need:
			break
		rem -= need
		lv += 1
	return Vector2i(lv, rem)


func _assert_exp_state(total_exp: int, label: String) -> void:
	var want: Vector2i = _expected_progress(total_exp)
	var ok: bool = GameState.player_level == want.x and GameState.player_exp == want.y
	_assert(ok, "%s（累计 %d → 期望 Lv%d+%d，实际 Lv%d+%d）" % [
		label, total_exp, want.x, want.y, GameState.player_level, GameState.player_exp])


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
	_assert_exp_state(_expected_exp_near, "经验总计 %d（含品质倍率）" % _expected_exp_near)

	print("[Test] === 阶段3：远距离珠子不吸附 ===")
	# 在远处生成 1 颗（超出拾取半径 60）
	var far_pos: Vector2 = _player.global_position + Vector2(200, 0)
	var gf: ExpGem = _pickup_system.spawn_exp_gem(far_pos, 8)
	_expected_exp_far = gf.exp_value
	print("[Test] 远珠品质: %s → 经验 %d" % [ExpGem.QUALITY_NAMES[gf.get_quality()], _expected_exp_far])

	for i in 10:
		await get_tree().process_frame

	_assert(_pickup_system.active_gem_count() == 1, "远珠仍在场")
	_assert_exp_state(_expected_exp_near, "远珠未被收集，经验不变")

	print("[Test] === 阶段4：玩家移动靠近后收集 ===")
	# 移动玩家靠近远珠
	_player.global_position = far_pos - Vector2(30, 0)
	for i in 30:
		await get_tree().process_frame

	_assert(_pickup_system.active_gem_count() == 0, "移动后远珠被收集")
	_assert_exp_state(_expected_exp_near + _expected_exp_far, "经验总计 %d" % (_expected_exp_near + _expected_exp_far))

	print("[Test] === 阶段4b：全速远离时珠子仍吸完（不跟跑）===")
	_pickup_system.clear_all()
	# 清掉前序经验，避免本段入账触发三选一暂停后续用例
	GameState.player_exp = 0
	while UpgradeManager.is_presenting():
		UpgradeManager.skip()
	_player.set_move_speed_mult(Player.move_speed_soft_cap())
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
	var essence_before: int = GameState.refine_essence
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
		or GameState.refine_essence > essence_before
	)
	_assert(gained, "开箱发放了潮币/回血/进化道具/淬炼精华之一")

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

	# 史诗箱：分测 evolution / refine_essence / heal（固定奖励表，避开 alternatives RNG）
	_pickup_system.clear_all()
	# 开局已有鱼叉；升至满级以满足 has_evolvable_owned
	while GameState.get_weapon_level("harpoon") < GameState.max_weapon_level:
		if not GameState.add_weapon("harpoon"):
			break
	_assert(EvolutionSystem.has_evolvable_owned(), "满级鱼叉视为可进化持有")
	var soft: int = int(ConfigLoader.get_evolution_rules().get("soft_cap_unused_items", 2))
	GameState.evolution_items = soft
	var evo0: int = GameState.evolution_items

	# A) evolution + 软上限 → 回退潮币，进化道具不增
	_pickup_system.set_chest_rewards_for_test([
		{"kind": "tidecoins", "amount": 15},
		{"kind": "tidecoins", "amount": 35},
		{"kind": "tidecoins", "amount": 60},
		{"kind": "evolution", "amount": 1, "fallback_tidecoins": 80},
	])
	var coins_a: int = GameState.tidecoins
	var epic_a: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.EPIC)
	_assert(epic_a != null, "evolution 分支可生成史诗箱")
	_player.global_position = epic_a.global_position
	for _ia in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "evolution 分支史诗箱已开启")
	_assert(GameState.evolution_items == evo0, "软上限下进化道具未增加")
	_assert(GameState.tidecoins == coins_a + 80, "evolution 软上限回退潮币 80")

	# B) refine_essence → 授精华
	_pickup_system.clear_all()
	_pickup_system.set_chest_rewards_for_test([
		{"kind": "tidecoins", "amount": 15},
		{"kind": "tidecoins", "amount": 35},
		{"kind": "tidecoins", "amount": 60},
		{"kind": "refine_essence", "amount": 2, "fallback_tidecoins": 70},
	])
	var essence0: int = GameState.refine_essence
	var epic_b: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.EPIC)
	_assert(epic_b != null, "refine_essence 分支可生成史诗箱")
	_player.global_position = epic_b.global_position
	for _ib in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "refine_essence 分支史诗箱已开启")
	_assert(GameState.refine_essence == essence0 + 2, "史诗箱发放淬炼精华 ×2")

	# C) heal → 回复生命（先扣血避免满血回退潮币）
	_pickup_system.clear_all()
	_pickup_system.set_chest_rewards_for_test([
		{"kind": "tidecoins", "amount": 15},
		{"kind": "tidecoins", "amount": 35},
		{"kind": "tidecoins", "amount": 60},
		{"kind": "heal", "amount": 50},
	])
	GameState.player_health = mini(GameState.player_max_health, 40)
	var hp0: int = GameState.player_health
	var coins_c: int = GameState.tidecoins
	var epic_c: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.EPIC)
	_assert(epic_c != null, "heal 分支可生成史诗箱")
	_player.global_position = epic_c.global_position
	for _ic in 3:
		await get_tree().process_frame
	_assert(_pickup_system.active_chest_count() == 0, "heal 分支史诗箱已开启")
	_assert(GameState.player_health > hp0, "heal 分支回复生命")
	_assert(GameState.tidecoins == coins_c, "有效治疗时不回退潮币")

	# 恢复 config 奖励表，避免污染后续用例
	_pickup_system.reload_chest_config_for_test()

	# alternatives 随机路径：刷箱不耗 RNG；同种子预抽期望下标后立即开箱（避免 process_frame 污染 RNG）
	_pickup_system.clear_all()
	_pickup_system.set_chest_rewards_for_test([
		{"kind": "tidecoins", "amount": 15},
		{"kind": "tidecoins", "amount": 35},
		{"kind": "tidecoins", "amount": 60},
		{"alternatives": [
			{"kind": "tidecoins", "amount": 99},
			{"kind": "heal", "amount": 25},
		]},
	])
	GameState.player_health = mini(GameState.player_max_health, 40)
	var hp_alt0: int = GameState.player_health
	var coins_alt0: int = GameState.tidecoins
	var epic_alt: Chest = _pickup_system.spawn_chest_at(_player.global_position, Chest.Rarity.EPIC)
	_assert(epic_alt != null, "alternatives 路径可生成史诗箱")
	_player.global_position = epic_alt.global_position
	RNG.set_seed(1)
	var expect_alt: int = RNG.randi_range(0, 1)
	RNG.set_seed(1)
	_pickup_system.force_open_chests_at_for_test(_player.global_position)
	_assert(_pickup_system.active_chest_count() == 0, "alternatives 路径史诗箱已开启")
	if expect_alt == 0:
		_assert(GameState.tidecoins == coins_alt0 + 99, "alternatives[0] tidecoins×99")
		_assert(GameState.player_health == hp_alt0, "未抽到 heal")
	else:
		_assert(GameState.player_health == hp_alt0 + 25, "alternatives[1] heal×25")
		_assert(GameState.tidecoins == coins_alt0, "未抽到 tidecoins")
	_pickup_system.reload_chest_config_for_test()

	# 挣扎中开箱：不发奖、不转潮币（选在首夜保护窗口之后，避免首夜保护复活抢占挣扎）
	_pickup_system.clear_all()
	MetaSystem.begin_run()
	var fn_cfg: Dictionary = ConfigLoader.get_frustration_config().get("first_night", {})
	var protect_nights: int = int(fn_cfg.get("protect_nights", 4))
	GameState.current_night = protect_nights + 1
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

	_test_chest_schedule()

	_print_result()
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


## 宝箱夜间动态刷新的排期拟合（2026-10-26 code-review P1）
## 原缺陷：事件把预算翻倍（2→4）后，固定 22s 间隔在常规 45s 夜里只够刷 2 只
## （12s / 34s），第 3、4 只排到夜后 → 倍率形同无效。
## 这条路径此前零覆盖，所以断言直接锁「预算能否塞进本夜」。
func _test_chest_schedule() -> void:
	print("[Test] === 宝箱动态刷新排期拟合（事件翻倍预算必须能刷完）===")
	const FIRST := 12.0
	const NOMINAL := 22.0
	const TAIL := 3.0
	const NIGHT := 45.0

	# ① 常规夜 + 事件翻倍（4 只）：间隔必须被压缩到能把 4 只都排进本夜
	var iv4: float = PickupSystem.fit_chest_interval(4, FIRST, NOMINAL, NIGHT, TAIL)
	_assert(iv4 < NOMINAL, "4 只塞进 45s 夜 → 间隔压缩（%.2f < %.1f）" % [iv4, NOMINAL])
	_assert(FIRST + iv4 * 3.0 <= NIGHT,
		"第 4 只落地 %.1fs ≤ 夜长 %.0fs" % [FIRST + iv4 * 3.0, NIGHT])

	# ② 预算没翻倍时不压缩——常规手感必须不变
	_assert(is_equal_approx(PickupSystem.fit_chest_interval(2, FIRST, NOMINAL, NIGHT, TAIL), NOMINAL),
		"2 只时不压缩（默认 22s 本就够）")

	# ③ 长夜（天灾 90s）不压缩
	_assert(is_equal_approx(PickupSystem.fit_chest_interval(4, FIRST, NOMINAL, 90.0, TAIL), NOMINAL),
		"天灾 90s 夜 4 只仍用 22s")

	# ④ 极端预算也不会退化成一帧连刷
	var iv_many: float = PickupSystem.fit_chest_interval(20, FIRST, NOMINAL, NIGHT, TAIL)
	_assert(iv_many >= PickupSystem.MIN_CHEST_INTERVAL,
		"极端预算间隔 ≥ 下限 %.1fs（实际 %.2f）" % [PickupSystem.MIN_CHEST_INTERVAL, iv_many])

	# ⑤ 单只 / 夜长未知：原样返回（不制造奇怪节奏）
	_assert(is_equal_approx(PickupSystem.fit_chest_interval(1, FIRST, NOMINAL, NIGHT, TAIL), NOMINAL),
		"单只箱不压缩")
	_assert(is_equal_approx(PickupSystem.fit_chest_interval(4, FIRST, NOMINAL, 0.0, TAIL), NOMINAL),
		"夜长未知（0）时不压缩")

	# ⑥ 端到端：真事件「潮汐反转」把预算翻倍（2→4），排期必须跟着压缩
	#    种子扫描让 base_count 抽到上限（per_night_max=2），避免测试依赖运气
	EventSystem.apply_event("tidal_reversal")
	_assert(is_equal_approx(EventSystem.get_chest_mult(), 2.0), "潮汐反转给出 2 倍宝箱预算")
	var budget: int = 0
	var iv_eff: float = 0.0
	for s in range(1, 400):
		RNG.set_seed(s)
		_pickup_system.begin_night_chests(_player.global_position, NIGHT)
		budget = _pickup_system.chest_budget_left()
		if budget >= 3:
			break
	iv_eff = _pickup_system.chest_spawn_interval_eff()
	_assert(budget >= 3, "翻倍后预算 ≥3（实际 %d 只）" % budget)
	_assert(iv_eff < NOMINAL, "翻倍预算触发间隔压缩（%.2f < %.1f）" % [iv_eff, NOMINAL])
	var last_at: float = _pickup_system.chest_first_delay() + iv_eff * float(maxi(0, budget - 1))
	_assert(last_at <= NIGHT,
		"翻倍预算 %d 只全部排进本夜（最后一只 %.1fs ≤ %.0fs）" % [budget, last_at, NIGHT])
	EventSystem.reset()
	_pickup_system.clear_all()

	# ⑦ 单参调用（不传夜长）也能拟合：按 GameState.current_night 查表
	_pickup_system.begin_night_chests(_player.global_position)
	_assert(_pickup_system.chest_spawn_interval_eff() > 0.0
		and _pickup_system.chest_spawn_interval_eff() <= NOMINAL,
		"单参调用按当前夜次查表拟合（%.2f）" % _pickup_system.chest_spawn_interval_eff())

	# ⑧ 清场后回落默认节奏（下一夜重新拟合）
	_pickup_system.clear_all()
	_assert(is_equal_approx(_pickup_system.chest_spawn_interval_eff(), NOMINAL),
		"清场后有效间隔回落默认 22s")


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
