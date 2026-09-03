# ============================================================================
# W8EnemyAffixTest — 4 进阶敌人 + 6 词缀 + 100 敌刷怪机检
# 验收：9 种敌人可配置；鸦群/召唤师/长枪兵/巨人行为可辨；6 词缀生效；
#       教学夜无词缀；天灾夜全场 +1；精英 2~3 词缀；100 敌可刷不崩。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w8_enemy_affix_test.tscn
# ============================================================================
extends Node2D

const _AFFIX_SYSTEM = preload("res://scripts/combat/affix_system.gd")
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

var _passed: int = 0
var _failed: int = 0

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Player = $Player
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var pickup_pool: ObjectPool = $PickupPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	print("============================================================")
	print("W8 进阶敌人 / 词缀 / 100 敌 机检")
	print("============================================================")
	GameState.start_new_run("watcher", 20260816)
	spatial_hash_holder.add_to_group("spatial_hash")
	player.add_to_group("player")
	spawner.add_to_group("enemy_spawner")
	spawner.setup(enemy_pool, player, pickup_system)
	await get_tree().process_frame

	await _test_nine_enemy_types()
	await _test_flying_swarm()
	await _test_summoner()
	await _test_pikeman_charge_dr()
	await _test_reef_giant_share()
	await _test_affix_split()
	await _test_elite_split_uses_prototype()
	await _test_share_kill_skips_nested_split()
	await _test_affix_teleport()
	await _test_affix_thorns()
	await _test_affix_swift()
	await _test_affix_regen()
	await _test_affix_chain()
	await _test_teaching_night_no_affix()
	await _test_calamity_night_affix()
	await _test_elite_affixes()
	await _test_hundred_enemies()

	print("------------------------------------------------------------")
	print("W8 机检通过=%d 失败=%d" % [_passed, _failed])
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
	for _i in n:
		await get_tree().process_frame


func _clear() -> void:
	spawner.stop()
	spawner.clear_all()
	GameState.is_over = false
	GameState.player_health = GameState.player_max_health
	if player != null:
		player.global_position = Vector2.ZERO


func _spawn(id: String, offset: Vector2, night: int = 1) -> EnemyBase:
	var def: Dictionary = ConfigLoader.get_enemy(id)
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.configure(def, night)
	e.spawn_at(player.global_position + offset, player)
	return e


# ---------------------------------------------------------------------------
# 9 种敌人均可配置
# ---------------------------------------------------------------------------
func _test_nine_enemy_types() -> void:
	print("[9 种敌人]")
	var ids: Array[String] = [
		"small_goblin", "iron_crab", "jellyfish_drifter", "deep_diver", "bomb_shell",
		"raven_flock", "tide_summoner", "abyssal_pikeman", "reef_giant",
	]
	_assert(ids.size() == 9, "MVP 9 种敌人 id")
	_assert(ConfigLoader.get_all_affix_ids().size() == 6, "6 种词缀 id")
	for id in ids:
		var def: Dictionary = ConfigLoader.get_enemy(id)
		var e: EnemyBase = enemy_pool.acquire() as EnemyBase
		e.configure(def, 1)
		_assert(e.behavior_type == String(def.get("behavior_type", "")), "%s behavior=%s" % [id, e.behavior_type])
		enemy_pool.release(e)


# ---------------------------------------------------------------------------
# 鸦群：飞行旗 + 高速
# ---------------------------------------------------------------------------
func _test_flying_swarm() -> void:
	print("[鸦群 flying_swarm]")
	_clear()
	var e: EnemyBase = _spawn("raven_flock", Vector2(200.0, 0.0), 7)
	_assert(e.is_flying, "鸦群 flags.flying")
	_assert(e.move_speed >= 120.0, "鸦群高速 (speed=%.0f)" % e.move_speed)
	var gob: EnemyBase = _spawn("small_goblin", Vector2(0.0, 200.0), 1)
	_assert(e.move_speed > gob.move_speed, "鸦群快于小水鬼")
	enemy_pool.release(e)
	enemy_pool.release(gob)


# ---------------------------------------------------------------------------
# 潮汐召唤师：召唤小水鬼且不贴身冲撞
# ---------------------------------------------------------------------------
func _test_summoner() -> void:
	print("[潮汐召唤师 summoner]")
	_clear()
	var e: EnemyBase = _spawn("tide_summoner", Vector2(250.0, 0.0), 8)
	var start_active: int = enemy_pool.active_count()
	var saw_minion: bool = false
	for _i in 30:
		await get_tree().process_frame
		for n in enemy_pool.get_active():
			if n is EnemyBase and (n as EnemyBase).enemy_id == "small_goblin":
				saw_minion = true
				break
		if saw_minion:
			break
	_assert(saw_minion, "召唤师刷出小水鬼 (active %d→%d)" % [start_active, enemy_pool.active_count()])
	_assert(e.global_position.distance_to(player.global_position) > 40.0, "召唤师不主动贴身")
	_clear()


# ---------------------------------------------------------------------------
# 渊潮长枪兵：冲锋中受伤减免 50%
# ---------------------------------------------------------------------------
func _test_pikeman_charge_dr() -> void:
	print("[渊潮长枪兵 charge DR]")
	_clear()
	var e: EnemyBase = _spawn("abyssal_pikeman", Vector2(80.0, 0.0), 11)
	var charged: bool = false
	for _i in 10:
		await get_tree().process_frame
		if e.is_charging():
			charged = true
			break
	_assert(charged, "长枪兵进入冲锋")
	var hp0: int = e.health
	e.take_damage(100)
	var lost: int = hp0 - e.health
	_assert(lost > 0 and lost < 100, "冲锋中免伤 50%% (掉血 %d / 100)" % lost)
	_clear()


# ---------------------------------------------------------------------------
# 暗礁巨人：伤害分摊给周围小怪
# ---------------------------------------------------------------------------
func _test_reef_giant_share() -> void:
	print("[暗礁巨人 damage_share]")
	_clear()
	var giant: EnemyBase = _spawn("reef_giant", Vector2(300.0, 0.0), 14)
	var gob: EnemyBase = _spawn("small_goblin", Vector2(330.0, 0.0), 1)
	var g0: int = giant.health
	var m0: int = gob.health
	giant.take_damage(20)
	_assert(gob.health < m0, "分摊使周围小怪掉血 (%d→%d)" % [m0, gob.health])
	_assert(g0 - giant.health < 20, "巨人自身少吃伤害 (掉 %d / 20)" % (g0 - giant.health))
	_clear()


# ---------------------------------------------------------------------------
# 分裂：死亡出 2 只小号且子体不再分裂
# ---------------------------------------------------------------------------
func _test_affix_split() -> void:
	print("[词缀 分裂]")
	_clear()
	spawner.start_night(1)
	spawner.stop()
	var parent: EnemyBase = _spawn("small_goblin", Vector2(400.0, 0.0), 1)
	parent.apply_affixes(["split"])
	_assert(parent.has_affix("split"), "父体带分裂词缀")
	var parent_max: int = parent.max_health
	parent.take_damage(999)
	await _run_frames(2)
	var children: Array[EnemyBase] = []
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "small_goblin":
			children.append(n as EnemyBase)
	_assert(children.size() == 2, "分裂出 2 只 (实际 %d)" % children.size())
	var no_split: bool = true
	for c in children:
		if c.has_affix("split"):
			no_split = false
		_assert(c.max_health < parent_max, "分裂体血量低于父体 (%d < %d)" % [c.max_health, parent_max])
	_assert(no_split, "分裂体不再带分裂词缀")
	if children.size() >= 1:
		var remain: int = children.size()
		children[0].take_damage(999)
		await _run_frames(2)
		var after: int = 0
		for n2 in enemy_pool.get_active():
			if n2 is EnemyBase and (n2 as EnemyBase).enemy_id == "small_goblin":
				after += 1
		_assert(after == remain - 1, "分裂体死亡不再分裂 (%d→%d)" % [remain, after])
	_clear()


# ---------------------------------------------------------------------------
# 精英分裂：prototype_id → base_enemy（giant_claw_king 不在 enemies 表）
# ---------------------------------------------------------------------------
func _test_elite_split_uses_prototype() -> void:
	print("[词缀 精英分裂 prototype]")
	_clear()
	spawner.start_night(5)
	await _run_frames(2)
	spawner.stop()
	var elite: EnemyBase = null
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "giant_claw_king":
			elite = n as EnemyBase
			break
	_assert(elite != null, "巨钳王存在")
	if elite == null:
		_clear()
		return
	_assert(elite.prototype_id == "iron_crab", "精英 prototype_id=iron_crab (实际 %s)" % elite.prototype_id)
	# 记录精英死亡前已存在的铁壳蟹（start_night 首帧可能已刷出普通铁壳蟹），
	# 只统计精英分裂新增的子体，避免把既有杂兵一起计入（原断言「实际 3」的根因）。
	var pre_crabs: int = 0
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "iron_crab":
			pre_crabs += 1
	elite.apply_affixes(["split"])
	elite.take_damage(99999)
	await _run_frames(2)
	var total_crabs: int = 0
	for n3 in enemy_pool.get_active():
		if n3 is EnemyBase and (n3 as EnemyBase).enemy_id == "iron_crab":
			total_crabs += 1
	_assert(total_crabs - pre_crabs == 2, "精英分裂出 2 只铁壳蟹 (实际新增 %d)" % (total_crabs - pre_crabs))
	_clear()


# ---------------------------------------------------------------------------
# 分摊致死不重入分裂（from_share → _die(skip split)）
# ---------------------------------------------------------------------------
func _test_share_kill_skips_nested_split() -> void:
	print("[分摊] 致死不嵌套分裂")
	_clear()
	var giant: EnemyBase = _spawn("reef_giant", Vector2(300.0, 0.0), 14)
	var gob: EnemyBase = _spawn("small_goblin", Vector2(320.0, 0.0), 1)
	gob.apply_affixes(["split"])
	gob.health = 1
	gob.max_health = 1
	var before: int = enemy_pool.active_count()
	# 大伤害使分摊足以击杀 gob；gob 不应在重入中分裂
	giant.take_damage(50)
	await _run_frames(2)
	var splits: int = 0
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "small_goblin":
			splits += 1
	_assert(gob.is_dead() or enemy_pool.get_active().find(gob) == -1, "分摊可击杀小怪")
	_assert(splits == 0, "分摊致死不触发分裂 (残留小水鬼=%d, before=%d)" % [splits, before])
	_clear()


# ---------------------------------------------------------------------------
# 传送：8 秒内位置变化
# ---------------------------------------------------------------------------
func _test_affix_teleport() -> void:
	print("[词缀 传送]")
	_clear()
	var e: EnemyBase = _spawn("iron_crab", Vector2(500.0, 0.0), 2)
	e.move_speed = 0.0
	e.apply_affixes(["teleport"])
	var origin: Vector2 = e.global_position
	var moved: bool = false
	for _i in 500:
		await get_tree().process_frame
		if e.global_position.distance_to(origin) > 20.0:
			moved = true
			break
	_assert(moved, "传送词缀使位置变化")
	_clear()


# ---------------------------------------------------------------------------
# 荆棘：近战反伤、远程不反
# ---------------------------------------------------------------------------
func _test_affix_thorns() -> void:
	print("[词缀 荆棘]")
	_clear()
	GameState.player_health = 100
	var e: EnemyBase = _spawn("small_goblin", Vector2(600.0, 0.0), 1)
	e.apply_affixes(["thorns"])
	# 隔离荆棘机制：显式抬血，避免难度缩放（如教学夜减半）使小水鬼被首击打死，
	# 导致第二次近战命中在 _dead 守卫处提前返回、thorns 永不触发。
	e.health = 100
	e.max_health = 100
	e.take_damage(10, false)
	_assert(GameState.player_health == 100, "远程命中不触发荆棘")
	e.take_damage(10, true)
	_assert(GameState.player_health < 100, "近战命中触发荆棘反伤 (hp=%d)" % GameState.player_health)
	_clear()


# ---------------------------------------------------------------------------
# 迅捷光环：周围敌人移速加成
# ---------------------------------------------------------------------------
func _test_affix_swift() -> void:
	print("[词缀 迅捷光环]")
	_clear()
	var aura: EnemyBase = _spawn("small_goblin", Vector2(700.0, 0.0), 1)
	var other: EnemyBase = _spawn("small_goblin", Vector2(730.0, 0.0), 1)
	aura.apply_affixes(["swift"])
	await _run_frames(3)
	_assert(other.aura_speed_bonus > 0.0, "光环使周围敌人移速加成 (bonus=%.2f)" % other.aura_speed_bonus)
	_assert(aura.aura_speed_bonus > 0.0, "光环自身也吃加成")
	_clear()


# ---------------------------------------------------------------------------
# 再生：脱战 5 秒回血
# ---------------------------------------------------------------------------
func _test_affix_regen() -> void:
	print("[词缀 再生]")
	_clear()
	var e: EnemyBase = _spawn("iron_crab", Vector2(800.0, 0.0), 2)
	e.apply_affixes(["regen"])
	e.take_damage(20)
	var after_hit: int = e.health
	var healed: bool = false
	for _i in 360:
		await get_tree().process_frame
		if e.health > after_hit:
			healed = true
			break
	_assert(healed, "脱战 5 秒后再生回血 (%d→%d)" % [after_hit, e.health])
	_clear()


# ---------------------------------------------------------------------------
# 锁链：被攻击绑定玩家
# ---------------------------------------------------------------------------
func _test_affix_chain() -> void:
	print("[词缀 锁链]")
	_clear()
	var e: EnemyBase = _spawn("small_goblin", Vector2(900.0, 0.0), 1)
	e.apply_affixes(["chain"])
	_assert(not player.is_bound(), "攻击前玩家未束缚")
	e.take_damage(5)
	_assert(player.is_bound(), "锁链词缀束缚玩家")
	var ch: Dictionary = ConfigLoader.get_affix("chain")
	var expect_mult: float = float(ch.get("bind_move_mult", 0.5))
	_assert(abs(player.get_bind_move_mult() - expect_mult) < 0.001, "锁链为减速非定身（bind_move_mult）")
	_assert(expect_mult > 0.0, "锁链 bind_move_mult>0（可走位）")
	_clear()


# ---------------------------------------------------------------------------
# 前 4 夜教学：常规刷怪无词缀
# ---------------------------------------------------------------------------
func _test_teaching_night_no_affix() -> void:
	print("[教学夜无词缀]")
	_clear()
	spawner.start_night(1)
	await _run_frames(20)
	var any_affix: bool = false
	for n in enemy_pool.get_active():
		if n is EnemyBase and not (n as EnemyBase).affix_ids.is_empty():
			any_affix = true
	_assert(spawner.get_night_bonus_affixes().is_empty(), "第1夜无全场词缀")
	_assert(not any_affix, "第1夜刷出的敌人无词缀")
	_clear()


# ---------------------------------------------------------------------------
# 天灾夜：全场统一 +1 词缀（Boss 除外）
# ---------------------------------------------------------------------------
func _test_calamity_night_affix() -> void:
	print("[天灾夜全场词缀]")
	_clear()
	spawner.start_night(10)
	await _run_frames(15)
	var bonus: Array[String] = spawner.get_night_bonus_affixes()
	_assert(bonus.size() == 1, "第10夜全场 +1 词缀 (%s)" % ",".join(bonus))
	var with_bonus: int = 0
	for n in enemy_pool.get_active():
		if n is EnemyBase and not (n as EnemyBase).is_boss:
			if bonus.size() == 1 and (n as EnemyBase).has_affix(bonus[0]):
				with_bonus += 1
	_assert(with_bonus >= 1, "天灾夜至少 1 只小怪带当夜词缀 (n=%d)" % with_bonus)
	_clear()


# ---------------------------------------------------------------------------
# 精英夜：巨钳王 2~3 词缀
# ---------------------------------------------------------------------------
func _test_elite_affixes() -> void:
	print("[精英 2~3 词缀]")
	_clear()
	spawner.start_night(5)
	await _run_frames(2)
	var elite: EnemyBase = null
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "giant_claw_king":
			elite = n as EnemyBase
			break
	_assert(elite != null, "第5夜巨钳王登场")
	if elite != null:
		var n_aff: int = elite.affix_ids.size()
		_assert(n_aff >= 2 and n_aff <= 3, "精英词缀数=%d (2~3)" % n_aff)
	_clear()


# ---------------------------------------------------------------------------
# 350 敌：对象池可撑满且持续 tick 不崩（W19 同屏上限）
# ---------------------------------------------------------------------------
func _test_hundred_enemies() -> void:
	print("[350 敌]")
	_clear()
	var cap: int = spawner.max_enemies
	var def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	var spawned: int = 0
	while spawned < cap and enemy_pool.available_count() > 0:
		var e: EnemyBase = enemy_pool.acquire() as EnemyBase
		if e == null:
			break
		e.configure(def, 1)
		e.move_speed = 0.0
		e.spawn_at(Vector2(float(spawned % 20) * 40.0, float(spawned / 20) * 40.0 + 1200.0), player)
		spawned += 1
	_assert(spawned == cap, "刷满 %d 敌 (实际 %d)" % [cap, spawned])
	await _run_frames(20)
	_assert(enemy_pool.active_count() == cap, "20 帧后仍为 %d 敌" % cap)
	_clear()
