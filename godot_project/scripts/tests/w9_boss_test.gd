# ============================================================================
# W9BossTest — 3 Boss 行为 + 精英夜/天灾夹击 机检
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w9_boss_test.tscn
# ============================================================================
extends Node2D

const _BOSS_BRAIN = preload("res://scripts/combat/boss_brain.gd")
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

var _passed: int = 0
var _failed: int = 0

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Player = $Player
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var eproj_pool: ObjectPool = $EnemyProjectilePool
@onready var pickup_pool: ObjectPool = $PickupPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	print("============================================================")
	print("W9 Boss / 精英夜 / 天灾夹击 机检")
	print("============================================================")
	GameState.start_new_run("watcher", 20260816)
	spatial_hash_holder.add_to_group("spatial_hash")
	player.add_to_group("player")
	eproj_pool.add_to_group("enemy_projectile_pool")
	spawner.add_to_group("enemy_spawner")
	spawner.setup(enemy_pool, player, pickup_system)
	spawner.lighthouse_position = Vector2.ZERO
	player.global_position = Vector2.ZERO
	await get_tree().process_frame

	await _test_boss_brains_created()
	await _test_jelly_queen_barrage_and_split()
	await _test_tide_archon_wave_aura()
	await _test_devouring_star_phases()
	await _test_elite_night5()
	await _test_calamity_affix_night10()
	await _test_pincer_night15()
	await _test_event_tidal_reversal_pincer()
	await _test_event_fish_migration_elite_wave()
	await _test_final_boss_kill_wins()

	print("------------------------------------------------------------")
	print("W9 机检通过=%d 失败=%d" % [_passed, _failed])
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
	eproj_pool.release_all()
	GameState.clear_over_state()
	GameState.player_health = GameState.player_max_health
	player.global_position = Vector2.ZERO


func _find_boss() -> EnemyBase:
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).is_boss:
			return n as EnemyBase
	return null


func _test_boss_brains_created() -> void:
	print("[BossBrain 工厂]")
	for bt in ["boss_jelly_queen", "boss_tide_archon", "boss_devouring_star"]:
		var brain: BossBrain = BossBrain.create(bt)
		_assert(brain != null, "可创建 %s" % bt)


func _test_jelly_queen_barrage_and_split() -> void:
	print("[水母后 弹幕环+分裂]")
	_clear()
	GameState.current_night = 10
	spawner.start_night(10)
	await _run_frames(2)
	spawner.stop()
	var boss: EnemyBase = _find_boss()
	_assert(boss != null and boss.enemy_id == "jellyfish_queen", "第10夜水母后登场")
	if boss == null:
		return
	_assert(boss.behavior_type == "boss_jelly_queen", "behavior=boss_jelly_queen")
	var saw_proj: bool = false
	var saw_minion: bool = false
	for _i in 240:
		await get_tree().process_frame
		if eproj_pool.active_count() > 0:
			saw_proj = true
		for n in enemy_pool.get_active():
			if n is EnemyBase and (n as EnemyBase).enemy_id == "jellyfish_drifter":
				saw_minion = true
		if saw_proj and saw_minion:
			break
	_assert(saw_proj, "水母后发射环形弹幕")
	_assert(saw_minion, "水母后分裂出水母浮游")
	_clear()


func _test_tide_archon_wave_aura() -> void:
	print("[执政官 潮汐波光晕]")
	_clear()
	spawner.lighthouse_position = Vector2.ZERO
	GameState.current_night = 15
	spawner.start_night(15)
	await _run_frames(2)
	spawner.stop()
	var boss: EnemyBase = _find_boss()
	_assert(boss != null and boss.enemy_id == "tide_archon", "第15夜执政官登场")
	if boss == null:
		return
	# 玩家在灯塔外 → 潮汐波应掉血
	player.global_position = Vector2(400.0, 0.0)
	GameState.player_health = 100
	var hurt: bool = false
	for _i in 480:
		await get_tree().process_frame
		if GameState.player_health < 100:
			hurt = true
			break
	_assert(hurt, "光晕外吃到潮汐波")
	# 玩家回到光晕内 → 潮汐波应免伤
	# 隔离接触伤害（杂兵/Boss 向心移动会触发 _try_contact_damage，与潮汐波光晕判定无关），
	# 仅验证「潮汐波在光晕内不造成伤害」。
	player.global_position = Vector2.ZERO
	boss.lighthouse_position = Vector2.ZERO
	for n in enemy_pool.get_active():
		if n is EnemyBase:
			(n as EnemyBase).contact_radius = 0.0
			(n as EnemyBase).contact_damage = 0
	GameState.player_health = 100
	await _run_frames(480)
	_assert(GameState.player_health == 100, "光晕内潮汐波免伤")
	_clear()


func _test_devouring_star_phases() -> void:
	print("[吞噬之星 三阶段]")
	_clear()
	GameState.current_night = 20
	spawner.start_night(20)
	await _run_frames(2)
	spawner.stop()
	var boss: EnemyBase = _find_boss()
	_assert(boss != null and boss.enemy_id == "devouring_star", "第20夜吞噬之星登场")
	if boss == null:
		return
	_assert(boss.get_boss_phase() == 0, "初始阶段 0 护盾")
	var hp0: int = boss.health
	boss.take_damage(100)
	var lost_shield: int = hp0 - boss.health
	_assert(lost_shield > 0 and lost_shield < 100, "护盾阶段减伤 (掉 %d/100)" % lost_shield)

	# 打到 70% 以下进狂暴
	var target_hp: int = int(float(boss.max_health) * 0.65)
	while boss.health > target_hp and not boss.is_dead():
		boss.take_damage(200)
	_assert(boss.get_boss_phase() >= 1, "进入狂暴阶段 phase=%d" % boss.get_boss_phase())

	# 打到 35% 以下出分身（分身延后到下一 tick，需再推进帧）
	target_hp = int(float(boss.max_health) * 0.30)
	while boss.health > target_hp and not boss.is_dead():
		boss.take_damage(400)
	await _run_frames(5)
	_assert(boss.get_boss_phase() == 2, "进入分身阶段")
	var goblins: int = 0
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "small_goblin":
			goblins += 1
	_assert(goblins >= 2, "分身刷出小水鬼 (≥2, 实际 %d)" % goblins)
	_clear()


func _test_elite_night5() -> void:
	print("[精英夜]")
	_clear()
	spawner.start_night(5)
	await _run_frames(2)
	var found: bool = false
	var aff_ok: bool = false
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).enemy_id == "giant_claw_king":
			found = true
			aff_ok = (n as EnemyBase).affix_ids.size() >= 2
	_assert(found and aff_ok, "第5夜巨钳王 + 2~3 词缀")
	_clear()


func _test_calamity_affix_night10() -> void:
	print("[天灾 +1 词缀]")
	_clear()
	spawner.start_night(10)
	await _run_frames(20)
	var bonus: Array[String] = spawner.get_night_bonus_affixes()
	_assert(bonus.size() == 1, "第10夜全场词缀 1 个")
	_clear()


func _test_pincer_night15() -> void:
	print("[潮汐夹击]")
	_clear()
	spawner.start_night(15)
	_assert(spawner.is_pincer_mode(), "第15夜夹击模式开启")
	# 夹击：直接验证刷怪点位两侧交替（避免被敌人向心移动导致收敛、误判为单侧）
	spawner._pincer_side = 1
	var ps1: Vector2 = spawner._pincer_spawn_pos()
	var ps2: Vector2 = spawner._pincer_spawn_pos()
	var ps3: Vector2 = spawner._pincer_spawn_pos()
	var saw_left: bool = ps1.x < 0.0 or ps2.x < 0.0 or ps3.x < 0.0
	var saw_right: bool = ps1.x > 0.0 or ps2.x > 0.0 or ps3.x > 0.0
	_assert(saw_left and saw_right, "夹击两侧均有刷怪点位")
	_clear()


## 潮汐反转事件：非 15 夜也强制夹击（与天灾 OR）
func _test_event_tidal_reversal_pincer() -> void:
	print("[潮汐反转事件→夹击]")
	_clear()
	EventSystem.reset()
	EventSystem.apply_event("tidal_reversal")
	spawner.start_night(7)
	_assert(spawner.is_pincer_mode(), "非15夜+潮汐反转 → 夹击开启")
	spawner._pincer_side = 1
	var a: Vector2 = spawner._pincer_spawn_pos()
	var b: Vector2 = spawner._pincer_spawn_pos()
	_assert(a.x * b.x < 0.0, "事件夹击点位左右交替")
	EventSystem.reset()
	_clear()
	spawner.start_night(7)
	_assert(not spawner.is_pincer_mode(), "无事件第7夜不夹击")
	_clear()


## 鱼群回游：start_night 消费精英波标记并刷出 is_elite
func _test_event_fish_migration_elite_wave() -> void:
	print("[鱼群回游→精英波实刷]")
	_clear()
	EventSystem.reset()
	EventSystem.apply_event("fish_migration")
	_assert(EventSystem.has_elite_wave(), "arm/apply 后精英波 pending")
	var want: int = EventSystem.get_elite_wave_count()
	_assert(want == 3, "精英波数量=config 3")
	spawner.start_night(3)
	await _run_frames(2)
	_assert(not EventSystem.has_elite_wave(), "start_night 后精英波已消费")
	var elites: int = 0
	for n in enemy_pool.get_active():
		if n is EnemyBase and (n as EnemyBase).is_elite and not (n as EnemyBase).is_boss:
			elites += 1
	_assert(elites >= want, "刷出 ≥%d 只精英（实际 %d）" % [want, elites])
	_clear()


func _test_final_boss_kill_wins() -> void:
	print("[终局击杀通关]")
	_clear()
	GameState.start_new_run("watcher", 42)
	GameState.current_night = 20
	GameState.clear_over_state()
	spawner.setup(enemy_pool, player, pickup_system)
	spawner.start_night(20)
	await _run_frames(2)
	spawner.stop()
	var boss: EnemyBase = _find_boss()
	_assert(boss != null, "终局 Boss 存在")
	if boss == null:
		return
	# 低血 + 贴身杂兵：同帧接触不得抢先判负
	GameState.player_health = 1
	var goblin_def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	if not goblin_def.is_empty():
		spawner.spawn_enemy(goblin_def, player.global_position, [], true, true)
	boss.take_damage(999999)
	# arm 应立刻锁 is_over；接触伤害不得改写为失败
	_assert(GameState.is_over, "击杀终局 Boss 立刻锁通关")
	GameState.damage_player(999)
	_assert(GameState.player_health == 1, "通关锁定后接触不再掉血")
	await _run_frames(5)
	_assert(GameState.is_over, "击杀第20夜 Boss 触发通关")
	_clear()
