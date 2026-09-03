# ============================================================================
# W2W3EnemyTest — 敌人全量（5 行为）/ Boss 占位 / 商店闭环 机检（W2-W3 + W4）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w2w3_enemy_test.tscn
# 退出码：0=全部机检通过，1=有失败
# 覆盖：验收清单 2.2.1 / 2.2.2 / 2.2.3 / 2.2.4 / 2.3.1 / 2.3.2 / 3.1 / 3.2
# ============================================================================
extends Node2D

var _passed: int = 0
var _failed: int = 0

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Node2D = $Player
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var coin_pool: ObjectPool = $CoinPool
@onready var eproj_pool: ObjectPool = $EnemyProjectilePool
@onready var pickup_pool: ObjectPool = $PickupPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var shop_manager: ShopManager = $ShopManager
@onready var shop_ui: ShopUI = $ShopUI


func _ready() -> void:
	print("============================================================")
	print("W2-W3 敌人全量 / Boss 占位 / W4 商店 机检")
	print("============================================================")
	GameState.start_new_run("watcher", 20260813)
	spatial_hash_holder.add_to_group("spatial_hash")
	player.add_to_group("player")
	eproj_pool.add_to_group("enemy_projectile_pool")
	spawner.setup(enemy_pool, player, pickup_system)
	shop_manager.setup(shop_ui)
	shop_ui.setup(shop_manager)
	await get_tree().process_frame

	await _test_five_enemy_types()      # 2.2.1 至少 5 种敌人 + 2.2.2 行为可辨
	await _test_ranged_fires_projectile()  # 2.2.2 远程行为
	await _test_enemy_projectile_max_life()  # 敌方弹道 MAX_LIFE 回收（防池耗尽）
	await _test_burrow_ambush()         # 2.2.2 潜地行为
	await _test_self_destruct()         # 2.2.2 自爆行为
	await _test_spawn_loop_and_cap()    # 2.2.3 潮汐刷怪 + 2.2.4 同屏上限
	await _test_quota_preserved_when_full()  # 池满不烧配额
	await _test_day_clears_enemy_projectiles()  # 进昼清弹道契约
	await _test_elite_night5()          # 2.3.1 精英夜（巨钳王）
	await _test_boss_night10()          # 2.3.2 天灾夜 Boss 占位
	await _test_coin_loop()             # 3.2 潮币闭环（掉落→拾取）
	await _test_shop()                  # 3.1 商店刷新 + 3.2 购买
	await _test_teaching_night_density()  # 教学夜密度回归（修复「一半时间没怪」空窗）

	print("------------------------------------------------------------")
	print("W2-W3 机检通过=%d 失败=%d" % [_passed, _failed])
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


func _run_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 击杀掉落回调（命名方法，避免 lambda 闭包捕获问题）
func _on_test_enemy_died(en: EnemyBase) -> void:
	pickup_system.spawn_exp_gem(en.global_position, en.base_exp)
	pickup_system.spawn_coin(en.global_position, en.coin_drop)


# ---------------------------------------------------------------------------
# 2.2.1 至少 5 种敌人（小水鬼/铁壳蟹/水母浮游/深潜者/爆炸贝）
# 2.2.2 行为可辨（各类型 behavior_type 正确注入）
# ---------------------------------------------------------------------------
func _test_five_enemy_types() -> void:
	print("[2.2.1/2.2.2 五种敌人 + 行为注入]")
	var ids: Array[String] = [
		"small_goblin", "iron_crab", "jellyfish_drifter", "deep_diver", "bomb_shell",
	]
	for id in ids:
		var def: Dictionary = ConfigLoader.get_enemy(id)
		var e: EnemyBase = enemy_pool.acquire() as EnemyBase
		if e == null:
			_assert(false, "可 acquire %s" % id)
			continue
		e.configure(def, 5)
		var ok_type: bool = (e.behavior_type == def.get("behavior_type", ""))
		var ok_health: bool = (e.max_health > 0 and e.health > 0)
		_assert(ok_type and ok_health, "%s → behavior=%s, hp=%d" % [id, e.behavior_type, e.max_health])
		enemy_pool.release(e)


# ---------------------------------------------------------------------------
# 2.2.2 远程弹幕：水母浮游开火产生敌方弹道
# ---------------------------------------------------------------------------
func _test_ranged_fires_projectile() -> void:
	print("[2.2.2 远程弹幕行为]")
	var def: Dictionary = ConfigLoader.get_enemy("jellyfish_drifter")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, 3)
	e.spawn_at(player.global_position + Vector2(120.0, 0.0), player)
	await _run_frames(3)
	var fired: bool = eproj_pool.active_count() > 0
	_assert(fired, "水母浮游开火 → 敌方弹道活跃数=%d" % eproj_pool.active_count())
	enemy_pool.release(e)
	eproj_pool.release_all()


# ---------------------------------------------------------------------------
# 敌方弹道 MAX_LIFE：未命中也须在时限内回收（对齐玩家弹道；修机器人日志池耗尽）
# ---------------------------------------------------------------------------
func _test_enemy_projectile_max_life() -> void:
	print("[敌方弹道 MAX_LIFE 回收]")
	eproj_pool.release_all()
	var p: EnemyProjectile = eproj_pool.acquire() as EnemyProjectile
	_assert(p != null, "取得敌方弹道")
	# 朝远离玩家方向发射，确保靠寿命回收而非命中
	p.launch(Vector2(-2000.0, -2000.0), Vector2.LEFT, 1)
	var before: int = eproj_pool.active_count()
	_assert(before == 1, "发射后 active=1")
	# ≈4.0s @60fps > MAX_LIFE(3.5s)
	for _i in 260:
		await get_tree().process_frame
		if eproj_pool.active_count() == 0:
			break
	_assert(eproj_pool.active_count() == 0, "未命中弹道在 MAX_LIFE(3.5s) 内被回收")


# ---------------------------------------------------------------------------
# 2.2.2 潜地突袭：深潜者会进入潜地状态
# ---------------------------------------------------------------------------
func _test_burrow_ambush() -> void:
	print("[2.2.2 潜地突袭行为]")
	var def: Dictionary = ConfigLoader.get_enemy("deep_diver")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, 4)
	e.spawn_at(player.global_position + Vector2(120.0, 0.0), player)
	var burrowed: bool = false
	for i in 240:
		await get_tree().process_frame
		if is_instance_valid(e) and e.is_burrowed():
			burrowed = true
			break
	_assert(burrowed, "深潜者进入潜地状态")
	enemy_pool.release(e)


# ---------------------------------------------------------------------------
# 2.2.2 自爆：爆炸贝贴近玩家即自爆（死亡 + 玩家受伤）
# ---------------------------------------------------------------------------
func _test_self_destruct() -> void:
	print("[2.2.2 自爆行为]")
	GameState.player_health = GameState.player_max_health
	var def: Dictionary = ConfigLoader.get_enemy("bomb_shell")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, 5)
	e.spawn_at(player.global_position, player)
	await _run_frames(10)
	# 自爆 → _die → is_dead（玩家受伤由 explosion 接触伤害体现）
	var died: bool = is_instance_valid(e) and e.is_dead()
	var hurt: bool = GameState.player_health < GameState.player_max_health
	_assert(died and hurt, "爆炸贝自爆致死 + 玩家受伤 (hp=%d, dead=%s)" % [GameState.player_health, died])


# ---------------------------------------------------------------------------
# 2.2.3 潮汐刷怪（稀疏→密集→加压）/ 2.2.4 同屏上限（difficulty.json max_enemies）
# ---------------------------------------------------------------------------
func _test_spawn_loop_and_cap() -> void:
	print("[2.2.3/2.2.4 潮汐刷怪 + 同屏上限]")
	spawner.start_night(1)
	await _run_frames(180)  # 3s（稀疏段）
	var active: int = enemy_pool.active_count()
	var cap: int = spawner.max_enemies
	var within_cap: bool = active <= cap
	_assert(active >= 1 and within_cap, "第1夜刷怪活跃数=%d（≤%d）" % [active, cap])
	spawner.clear_all()


# ---------------------------------------------------------------------------
# 池满 / 达上限时不空耗刷怪配额；腾出名额后可继续刷
# ---------------------------------------------------------------------------
func _test_quota_preserved_when_full() -> void:
	print("[配额] 池满不烧 remaining")
	spawner.clear_all()
	GameState.player_health = GameState.player_max_health
	var def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	# 用远距小水鬼填满对象池（避免残留行为在原点接触/自爆）
	var fill_i: int = 0
	while enemy_pool.available_count() > 0:
		var filler: EnemyBase = enemy_pool.acquire() as EnemyBase
		if filler == null:
			break
		filler.configure(def, 1)
		filler.spawn_at(player.global_position + Vector2(2000.0 + float(fill_i) * 40.0, 0.0), player)
		fill_i += 1
	_assert(enemy_pool.available_count() == 0, "对象池已填满 available=0")
	spawner.start_night(1)
	var rem0: int = spawner.get_remaining()
	await _run_frames(30)
	var rem1: int = spawner.get_remaining()
	_assert(rem0 > 0 and rem1 == rem0, "池满时配额不变 (%d→%d)" % [rem0, rem1])
	# 腾出一个名额后应能刷出并扣配额
	var actives: Array[Node] = enemy_pool.get_active()
	if not actives.is_empty():
		enemy_pool.release(actives[0])
	await _run_frames(20)
	var rem2: int = spawner.get_remaining()
	_assert(rem2 < rem1, "腾出名额后配额下降 (%d→%d)" % [rem1, rem2])
	spawner.clear_all()
	GameState.player_health = GameState.player_max_health


# ---------------------------------------------------------------------------
# 进昼清场契约：与 World._clear_night_entities 同序（停刷→清敌→清弹道→清掉落）
# ---------------------------------------------------------------------------
func _test_day_clears_enemy_projectiles() -> void:
	print("[进昼清场] 敌方弹道回收")
	var def: Dictionary = ConfigLoader.get_enemy("jellyfish_drifter")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, 3)
	e.spawn_at(player.global_position + Vector2(80.0, 0.0), player)
	await _run_frames(5)
	_assert(eproj_pool.active_count() > 0, "清场前有活跃弹道=%d" % eproj_pool.active_count())
	# 镜像 World._clear_night_entities
	spawner.stop()
	spawner.clear_all()
	eproj_pool.release_all()
	pickup_system.clear_all()
	_assert(eproj_pool.active_count() == 0, "清场后敌方弹道=0")
	_assert(enemy_pool.active_count() == 0, "清场后敌人=0")


# ---------------------------------------------------------------------------
# 2.3.1 第 5 夜精英夜：巨钳王（强化铁壳蟹）登场
# ---------------------------------------------------------------------------
func _test_elite_night5() -> void:
	print("[2.3.1 精英夜 巨钳王]")
	spawner.start_night(5)
	await _run_frames(2)
	var found: bool = false
	for en in enemy_pool.get_active():
		if en is EnemyBase and en.enemy_id == "giant_claw_king":
			found = true
	_assert(found, "第5夜出现精英 巨钳王")
	spawner.clear_all()


# ---------------------------------------------------------------------------
# 2.3.2 第 10 夜天灾夜：Boss 占位（高血、不走缩放）
# ---------------------------------------------------------------------------
func _test_boss_night10() -> void:
	print("[2.3.2 天灾夜 Boss 占位]")
	spawner.start_night(10)
	await _run_frames(2)
	var boss: EnemyBase = null
	for en in enemy_pool.get_active():
		if en is EnemyBase and en.is_boss:
			boss = en
	_assert(boss != null and boss.max_health >= 2000, "第10夜 Boss 占位 (hp=%d)" % (boss.max_health if boss != null else 0))
	spawner.clear_all()


# ---------------------------------------------------------------------------
# 3.2 潮币闭环：击杀掉落 → 拾取 → 入账
# ---------------------------------------------------------------------------
func _test_coin_loop() -> void:
	print("[3.2 潮币闭环 掉落→拾取]")
	GameState.tidecoins = 0
	var def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, 1)
	e.spawn_at(player.global_position, player)
	e.enemy_died.connect(_on_test_enemy_died)
	e.take_damage(999)
	await _run_frames(30)
	var got: bool = GameState.tidecoins > 0
	_assert(got, "击杀掉落潮币被拾取入账 (tidecoins=%d)" % GameState.tidecoins)


# ---------------------------------------------------------------------------
# 3.1 商店刷新（≥4 件）/ 3.2 购买扣币并入库
# ---------------------------------------------------------------------------
func _test_shop() -> void:
	print("[3.1/3.2 商店刷新 + 购买]")
	GameState.tidecoins = 1000
	shop_manager.open_shop()
	var items: Array[Dictionary] = shop_manager.get_current_items()
	_assert(items.size() >= 4, "商店在售件数=%d (≥4)" % items.size())

	var w_item: Dictionary = {}
	var p_item: Dictionary = {}
	for it in items:
		if it.get("kind") == "weapon" and w_item.is_empty():
			w_item = it
		elif it.get("kind") == "passive" and p_item.is_empty():
			p_item = it
	_assert(not w_item.is_empty() and not p_item.is_empty(), "同时含武器与被动项")

	var before: int = GameState.tidecoins
	var ok_w: bool = shop_manager.buy(w_item)
	var after_w: int = GameState.tidecoins
	_assert(ok_w and GameState.weapon_slots.has(w_item.get("id", "")), "购买武器入库: %s" % w_item.get("id", ""))
	_assert(after_w == before - int(w_item.get("cost", 0)), "购买武器扣币 %d→%d" % [before, after_w])

	var before_p: int = GameState.tidecoins
	var ok_p: bool = shop_manager.buy(p_item)
	_assert(ok_p and GameState.passive_slots.has(p_item.get("id", "")), "购买被动入库: %s" % p_item.get("id", ""))
	_assert(GameState.tidecoins == before_p - int(p_item.get("cost", 0)), "购买被动扣币正确")
	shop_manager.close_shop()


# ---------------------------------------------------------------------------
# 教学夜密度回归（修复「一半时间没怪」长空窗）
# 根因：旧 _process 在 _remaining（本夜预算）耗尽即 _spawning=false 停刷；
#       教学夜预算仅 10~19 只，被快速清光后剩余 28~40s 全空窗。
# 修复：预算耗尽后，只要 active < min_active 就持续补刷直到夜晚结束。
# 本机检：把教学夜跑到预算耗尽 → 模拟清场 → 断言仍回补至 min_active。
# ---------------------------------------------------------------------------
func _test_teaching_night_density() -> void:
	print("[教学夜密度] 预算耗尽后清场仍维持最低在屏密度 (min_active)")
	spawner.clear_all()
	GameState.player_health = GameState.player_max_health
	spawner.start_night(1)  # 教学夜（夜1）：数值减半但不降密度 floor
	# 1) 跑到本夜预算耗尽（_remaining 降到 0）
	var safe: int = 0
	while spawner.get_remaining() > 0 and safe < 2400:
		await get_tree().process_frame
		safe += 1
	_assert(spawner.get_remaining() == 0, "教学夜预算已耗尽 remaining=0 (帧=%d)" % safe)
	# 2) 模拟玩家在夜晚进行中持续清场：直接 release 当前活跃敌人（保持 _spawning=true）
	var actives: Array[Node] = enemy_pool.get_active()
	for a in actives:
		enemy_pool.release(a)
	await get_tree().process_frame
	# 3) 清场后应在数秒内回补到 min_active（修复前 _remaining<=0 即停刷，永远回补不上）
	var spawn_meta: Dictionary = ConfigLoader.get_enemy_spawn()
	var min_active: int = int(spawn_meta.get("min_active", 0))
	var max_floor_refill: int = int(spawn_meta.get("max_floor_refill", 0))
	_assert(min_active > 0, "config metadata.spawn.min_active 应 > 0")
	_assert(max_floor_refill == 0 or max_floor_refill >= min_active,
		"config metadata.spawn.max_floor_refill 应 ≥ min_active（0=不封顶）")
	var refilled: bool = false
	var reached: int = 0
	for i in 600:  # 最多 10s
		await get_tree().process_frame
		reached = enemy_pool.active_count()
		if reached >= min_active:
			refilled = true
			break
	_assert(refilled, "清场后回补至 min_active（活跃数=%d ≥ %d）" % [reached, min_active])
	# 3b) 反复清场鲁棒性（锁定空窗修复）：连续 5 次清空，断言全程不再出现长空窗
	#     （旧实现 max_floor_refill=32 封顶，多次清场耗尽后剩余夜段全空 → 5~10s 无怪）
	var no_long_gap: bool = true
	for _w in 5:
		var actives2: Array[Node] = enemy_pool.get_active()
		for a in actives2:
			enemy_pool.release(a)
		await get_tree().process_frame
		var zero_streak: int = 0
		for _f in 240:  # 每轮采样 4s
			await get_tree().process_frame
			if enemy_pool.active_count() == 0:
				zero_streak += 1
				if zero_streak > 12:  # 单帧偶发为 0 可接受；>0.2s 视为异常长空窗
					no_long_gap = false
					break
			else:
				zero_streak = 0
		if not no_long_gap:
			break
	_assert(no_long_gap, "反复清场后无长空窗（active 始终能快速回补到 min_active）")
	# 4) 经济解耦验证：回补的敌是 is_floor_refill（预算耗尽后的密度补刷），
	#    其死亡不应掉落经验珠/潮币（enemy_spawner._on_enemy_died 的 not enemy.is_floor_refill 守卫）。
	#    这是「维持 min_active 密度修复」与「经济回到成长曲线」解耦的关键机制。
	var floor_enemy: EnemyBase = null
	for en in enemy_pool.get_active():
		if en is EnemyBase and en.is_floor_refill:
			floor_enemy = en
			break
	_assert(floor_enemy != null, "回补的敌人为 is_floor_refill（预算耗尽补刷，无掉落）")
	if floor_enemy != null:
		pickup_system.clear_all()
		await get_tree().process_frame
		var g0: int = pickup_system.active_gem_count()
		var c0: int = pickup_system.active_coin_count()
		floor_enemy.take_damage(99999)
		await _run_frames(30)
		var g1: int = pickup_system.active_gem_count()
		var c1: int = pickup_system.active_coin_count()
		_assert(g1 == g0 and c1 == c0,
			"floor_refill 敌死亡不掉经验珠/潮币 (gem %d→%d, coin %d→%d)" % [g0, g1, c0, c1])
		_assert(spawner.get_floor_refills_used() > 0,
			"floor 补刷计数 > 0 (used=%d)" % spawner.get_floor_refills_used())
		if max_floor_refill > 0:
			_assert(spawner.get_floor_refills_used() <= max_floor_refill,
				"floor 补刷未超 max_floor_refill (used=%d cap=%d)" % [
					spawner.get_floor_refills_used(), max_floor_refill])
		else:
			_assert(spawner.get_floor_refills_used() > 0,
				"floor 补刷不封顶仍持续补刷 (used=%d)" % spawner.get_floor_refills_used())
	spawner.clear_all()
	GameState.player_health = GameState.player_max_health
