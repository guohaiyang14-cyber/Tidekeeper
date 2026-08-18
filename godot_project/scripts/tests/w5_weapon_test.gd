# ============================================================================
# W5WeaponTest — W5/W6 武器系统单测（headless 验收）
# 验收项：
#   T15-a 武器可升至 7 级（max_weapon_level），满级后再获得返回 false
#   T15-b 武器槽上限 4（MAX_WEAPON_SLOTS），第 5 个被拒
#   T15-c 鱼叉枪（directional_pierce）自动索敌并发射投射物命中造成伤害
#   T15-d 灯塔圣火（area_burn）范围伤害命中敌人
#   T15-e 锚链（orbit_tick）环绕伤害命中玩家周围敌人
#   T15-f 索敌返回最近敌人
#   T15-g 弹道 MAX_LIFE 回收
#   T16-a~e W6 五武器：锚锤/孢子/雷暴云/水母炮/信天翁均可造成伤害
# 红线：仅走对象池 / SpatialHash；不 instantiate；断言不依赖渲染
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w5_weapon_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node2D

const _WEAPON_MANAGER = preload("res://scripts/combat/weapon_manager.gd")
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")
const _SPATIAL_HASH_HOLDER = preload("res://scripts/core/spatial_hash_holder.gd")

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Node2D = $Player
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var projectile_pool: ProjectilePool = $ProjectilePool
@onready var enemy_pool: EnemyPool = $EnemyPool

var _pass_count: int = 0
var _fail_count: int = 0
var _fail_msgs: Array[String] = []


func _ready() -> void:
	if not ConfigLoader.is_loaded:
		push_error("[W5WeaponTest] ConfigLoader 未加载，无法运行")
		get_tree().quit(1)
		return
	# 注册空间哈希 group（敌人/投射物通过 group 查找）
	spatial_hash_holder.add_to_group("spatial_hash")
	weapon_manager.setup(player, spatial_hash_holder.get_hash(), projectile_pool)
	await _run_all()
	_finish()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		_fail_msgs.append(label)
		print("[FAIL] %s" % label)


## 重置竞技场：回收所有敌人/投射物，清空哈希，并按 GameState 同步武器实例
func _reset_arena() -> void:
	enemy_pool.release_all()
	projectile_pool.release_all()
	spatial_hash_holder.get_hash().clear()
	weapon_manager.sync_from_game_state()


## 设置单个被测武器：新局清槽 → 去掉开局默认武器 → 仅装备 id
func _setup_weapon(id: String) -> void:
	GameState.start_new_run("watcher")
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	_reset_arena()
	GameState.add_weapon(id)
	weapon_manager.sync_from_game_state()


## 推进 n 帧（headless 下引擎尽快跑完）
func _simulate(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _run_all() -> void:
	await _test_leveling()
	await _test_slot_cap()
	await _test_harpoon_auto_fire()
	await _test_holy_fire()
	await _test_anchor_chain()
	await _test_targeting()
	await _test_projectile_recycle()
	await _test_w6_anchor_hammer()
	await _test_w6_spore()
	await _test_w6_storm_cloud()
	await _test_w6_jellyfish_cannon()
	await _test_w6_albatross()
	await _test_all_behavior_types_creatable()
	await _test_projectile_bonus_hammer_chain()


## 在玩家附近刷一只敌人，等待武器造成掉血
func _assert_weapon_damages(weapon_id: String, offset: Vector2, frames: int, label: String) -> void:
	_setup_weapon(weapon_id)
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.spawn_at(player.global_position + offset, player)
	var start_health: int = e.health
	for _i in frames:
		await get_tree().process_frame
		if e.health < start_health:
			break
	_assert(e.health < start_health, label)
	if e != null and enemy_pool.get_active().find(e) != -1:
		enemy_pool.release(e)


# ---- T15-a 武器升级至 7 级 --------------------------------------------------
func _test_leveling() -> void:
	GameState.start_new_run("watcher")
	# 开局已按配置授予默认武器（§4.2）→ 用 holy_fire 验证纯升级链路，避免与默认武器冲突
	var wid: String = "holy_fire"
	GameState.add_weapon(wid)  # 入槽并置 1 级
	var added: int = 1
	for _i in 6:  # 再获得 6 次 → 1+6 = 7 级
		if GameState.add_weapon(wid):
			added += 1
	_assert(GameState.get_weapon_level(wid) == 7, "武器可升至 7 级 (max_weapon_level)")
	_assert(added == 7, "holy_fire 累计获得 7 次均成功")
	var eighth: bool = GameState.add_weapon(wid)
	_assert(eighth == false, "满级(7)后再获得同一武器返回 false")
	_assert(GameState.get_weapon_level(wid) == 7, "满级后等级维持 7 不变")


# ---- T15-b 武器槽上限 4 -----------------------------------------------------
func _test_slot_cap() -> void:
	GameState.start_new_run("watcher")
	var ids: Array[String] = ["harpoon", "holy_fire", "anchor_chain", "anchor_hammer", "spore"]
	var added: int = 0
	for id in ids:
		if GameState.add_weapon(id):
			added += 1
	_assert(GameState.weapon_slots.size() == GameState.MAX_WEAPON_SLOTS, "武器槽上限 = %d (MAX_WEAPON_SLOTS)" % GameState.MAX_WEAPON_SLOTS)
	_assert(added == GameState.MAX_WEAPON_SLOTS, "最多入槽 %d 个武器（第 5 个被拒）" % GameState.MAX_WEAPON_SLOTS)
	_assert(GameState.add_weapon("storm_cloud") == false, "槽满后再获得新武器返回 false")


# ---- T15-c 鱼叉枪自动开火命中 ----------------------------------------------
func _test_harpoon_auto_fire() -> void:
	_setup_weapon("harpoon")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.spawn_at(player.global_position + Vector2(200.0, 0.0), player)
	var start_health: int = e.health
	var max_active: int = 0
	for _i in 180:
		await get_tree().process_frame
		max_active = maxi(max_active, projectile_pool.active_count())
		if e.health < start_health:
			break
	_assert(max_active > 0, "鱼叉枪自动开火发射了投射物 (active_count > 0)")
	_assert(e.health < start_health, "鱼叉枪投射物命中并造成敌人掉血")


# ---- T15-d 灯塔圣火范围伤害 ------------------------------------------------
func _test_holy_fire() -> void:
	_setup_weapon("holy_fire")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.spawn_at(player.global_position + Vector2(100.0, 0.0), player)
	var start_health: int = e.health
	for _i in 150:
		await get_tree().process_frame
		if e.health < start_health:
			break
	_assert(e.health < start_health, "灯塔圣火范围伤害命中敌人 (area_burn)")


# ---- T15-e 锚链环绕伤害 -----------------------------------------------------
func _test_anchor_chain() -> void:
	_setup_weapon("anchor_chain")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	# 锚链 lv1 环绕半径 60，敌人置于玩家 40u 内
	e.spawn_at(player.global_position + Vector2(40.0, 0.0), player)
	var start_health: int = e.health
	for _i in 120:
		await get_tree().process_frame
		if e.health < start_health:
			break
	_assert(e.health < start_health, "锚链环绕伤害命中玩家周围敌人 (orbit_tick)")


# ---- T15-f 索敌返回最近敌人 ------------------------------------------------
func _test_targeting() -> void:
	_reset_arena()
	GameState.start_new_run("watcher")
	weapon_manager.sync_from_game_state()  # 无武器，仅清空实例
	var near: EnemyBase = enemy_pool.acquire() as EnemyBase
	near.spawn_at(player.global_position + Vector2(100.0, 0.0), player)
	var far: EnemyBase = enemy_pool.acquire() as EnemyBase
	far.spawn_at(player.global_position + Vector2(500.0, 0.0), player)
	await get_tree().process_frame  # 确保哈希包含两敌
	var tgt: EnemyBase = weapon_manager._target_node_provider()
	_assert(tgt == near, "索敌返回最近敌人 (100u) 而非 (500u)")
	enemy_pool.release(near)
	enemy_pool.release(far)


# ---- T15-g 弹道生命周期回收（防止对象池耗尽导致武器停火） -----------------
func _test_projectile_recycle() -> void:
	_setup_weapon("harpoon")
	# 直接发射一枚不命中任何敌人的弹道（朝右飞，2s 仅 ~840 单位，未达 5000 出界阈值）
	# 旧实现：仅靠命中/出界回收 → _active 恒 true → 池被持续发射占满 → 武器停火
	# 新实现：Projectile.MAX_LIFE(2s) 强制回收 → 有界
	var p: Projectile = projectile_pool.acquire() as Projectile
	_assert(p != null, "可获取弹道实例")
	p.launch(player.global_position, Vector2.RIGHT, 10, 0)
	await _simulate(2)
	_assert(projectile_pool.active_count() >= 1, "弹道发射后处于活跃态")
	var recycled: bool = false
	for _i in 200:  # ≈3.3s @60fps > MAX_LIFE(2s)
		await get_tree().process_frame
		if projectile_pool.get_active().find(p) == -1:
			recycled = true
			break
	_assert(recycled, "未命中弹道在 MAX_LIFE(2s) 内被回收（修复对象池耗尽）")


# ---- T16-a 锚锤近战爆发 -----------------------------------------------------
func _test_w6_anchor_hammer() -> void:
	# 前方半球内 50u，应被 melee_burst 打到
	await _assert_weapon_damages("anchor_hammer", Vector2(50.0, 0.0), 180, "锚锤近战爆发命中前方敌人 (melee_burst)")


# ---- T16-b 水母孢子召唤叮咬 -------------------------------------------------
func _test_w6_spore() -> void:
	await _assert_weapon_damages("spore", Vector2(80.0, 0.0), 120, "水母孢子召唤叮咬命中敌人 (summon_jellyfish)")


# ---- T16-c 雷暴云落雷（约 3s 一击） ------------------------------------------
func _test_w6_storm_cloud() -> void:
	# attack_rate=0.33 → 约 3s；固定 60fps 下留足余量
	await _assert_weapon_damages("storm_cloud", Vector2(100.0, 0.0), 240, "雷暴云落雷命中敌人 (area_lightning)")


# ---- T16-d 水母炮环形弹幕 ---------------------------------------------------
func _test_w6_jellyfish_cannon() -> void:
	_setup_weapon("jellyfish_cannon")
	# 敌人放在右侧弹道路径上（环形有向右的一道）；锁死移速避免走开被接触伤害误伤
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.spawn_at(player.global_position + Vector2(120.0, 0.0), player)
	e.move_speed = 0.0
	var start_health: int = e.health
	var saw_proj: bool = false
	for _i in 150:
		await get_tree().process_frame
		if projectile_pool.active_count() > 0:
			saw_proj = true
		if e.health < start_health:
			break
	_assert(saw_proj, "水母炮发射了环形弹道 (ring_barrage)")
	_assert(e.health < start_health, "水母炮环形弹幕命中敌人")
	_assert(e.get_move_speed_mult() < 1.0, "水母炮命中施加减速 (hit_slow 20%)")
	if enemy_pool.get_active().find(e) != -1:
		enemy_pool.release(e)


# ---- T16-e 信天翁俯冲 -------------------------------------------------------
func _test_w6_albatross() -> void:
	await _assert_weapon_damages("albatross", Vector2(150.0, 0.0), 120, "信天翁俯冲命中敌人 (summon_dive)")


# ---- T16-f 八种 behavior_type 均可实例化 ------------------------------------
func _test_all_behavior_types_creatable() -> void:
	var ids: Array[String] = [
		"harpoon", "holy_fire", "anchor_hammer", "spore",
		"storm_cloud", "jellyfish_cannon", "anchor_chain", "albatross",
	]
	var created: int = 0
	for id in ids:
		GameState.start_new_run("watcher")
		_reset_arena()
		if id != "harpoon":
			GameState.add_weapon(id)
		weapon_manager.sync_from_game_state()
		var found: bool = false
		for w in weapon_manager.get_weapons():
			if w.weapon_id == id:
				found = true
				break
		if found:
			created += 1
		else:
			_assert(false, "可创建武器实例: %s" % id)
	_assert(created == 8, "8 种武器 behavior_type 均可创建实例 (%d/8)" % created)


## 星象师弹道+1：锚锤额外挥击打身后；锚链外圈打到原半径外
func _test_projectile_bonus_hammer_chain() -> void:
	MetaSystem.reset_progress()
	MetaSystem.record_night_cleared(5)  # 解锁星象师（否则 get_active_character 回退守望者）
	MetaSystem.set_active_character("stargazer")
	MetaSystem.begin_run()
	_assert(MetaSystem.get_extra_projectiles() == 1, "星象师弹道 +1")
	var origin: Vector2 = player.global_position
	# 锚锤：身前更近，保证第一锤朝前；弹道+1 第二锤朝身后
	_setup_weapon("anchor_hammer")
	var front: EnemyBase = enemy_pool.acquire() as EnemyBase
	front.spawn_at(origin + Vector2(40.0, 0.0), player)
	front.move_speed = 0.0
	var back: EnemyBase = enemy_pool.acquire() as EnemyBase
	back.spawn_at(origin + Vector2(-50.0, 0.0), player)
	back.move_speed = 0.0
	await get_tree().process_frame
	var hammer: WeaponBase = _weapon_by_id("anchor_hammer")
	_assert(hammer != null, "锚锤实例存在")
	var back_hp: int = back.health
	if hammer != null:
		hammer.fire(front)
	_assert(back.health < back_hp, "弹道+1 锚锤额外挥击打到身后敌人")
	enemy_pool.release(front)
	enemy_pool.release(back)
	# 正面两敌同半球：跨挥击不叠伤（与锚链外圈不叠伤同口径）
	var pack_a: EnemyBase = enemy_pool.acquire() as EnemyBase
	pack_a.spawn_at(origin + Vector2(40.0, 0.0), player)
	pack_a.move_speed = 0.0
	pack_a.max_health = 200
	pack_a.health = 200
	var pack_b: EnemyBase = enemy_pool.acquire() as EnemyBase
	pack_b.spawn_at(origin + Vector2(55.0, 0.0), player)
	pack_b.move_speed = 0.0
	pack_b.max_health = 200
	pack_b.health = 200
	await get_tree().process_frame
	var expected: int = hammer.get_leveled_damage() if hammer != null else 0
	if hammer != null:
		hammer.fire(pack_a)
	_assert(200 - pack_a.health == expected, "弹道+1 锚锤正面集群不叠伤（近敌一次）")
	_assert(200 - pack_b.health == expected, "弹道+1 锚锤正面集群不叠伤（远敌一次）")
	enemy_pool.release(pack_a)
	enemy_pool.release(pack_b)
	# 锚链：敌人在 lv1 半径 60 外、外圈 60+15 内
	_setup_weapon("anchor_chain")
	var outer: EnemyBase = enemy_pool.acquire() as EnemyBase
	outer.spawn_at(origin + Vector2(68.0, 0.0), player)
	outer.move_speed = 0.0
	await get_tree().process_frame
	var chain: WeaponBase = _weapon_by_id("anchor_chain")
	_assert(chain != null, "锚链实例存在")
	var outer_hp: int = outer.health
	if chain != null:
		chain.fire(outer)
	_assert(outer.health < outer_hp, "弹道+1 锚链外圈打到原半径外敌人")
	enemy_pool.release(outer)
	MetaSystem.end_run()
	MetaSystem.set_active_character("watcher")
	MetaSystem.reset_progress()


func _weapon_by_id(id: String) -> WeaponBase:
	for w in weapon_manager.get_weapons():
		if w.weapon_id == id:
			return w
	return null


func _finish() -> void:
	print("========================================")
	print("[W5WeaponTest] 通过 %d / 失败 %d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("[W5WeaponTest] 失败项: " + ", ".join(_fail_msgs))
		get_tree().quit(1)
	else:
		print("[W5WeaponTest] 全部通过 ✅")
		get_tree().quit(0)
