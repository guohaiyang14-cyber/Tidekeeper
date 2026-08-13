# ============================================================================
# W5WeaponTest — W5 武器系统单测（headless 验收）
# 验收项：
#   T15-a 武器可升至 7 级（max_weapon_level），满级后再获得返回 false
#   T15-b 武器槽上限 4（MAX_WEAPON_SLOTS），第 5 个被拒
#   T15-c 鱼叉枪（directional_pierce）自动索敌并发射投射物命中造成伤害
#   T15-d 灯塔圣火（area_burn）范围伤害命中敌人
#   T15-e 锚链（orbit_tick）环绕伤害命中玩家周围敌人
#   T15-f 索敌返回最近敌人
# 红线：仅走对象池 / SpatialHash；不 instantiate；断言不依赖渲染
# 运行：godot --headless --path godot_project res://scenes/tests/w5_weapon_test.tscn
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


## 设置单个被测武器：新局清槽 → 清场 → 仅装备 id（避免对上一测试的武器误建实例）
func _setup_weapon(id: String) -> void:
	GameState.start_new_run("watcher")  # 先清槽（weapon_slots/weapon_levels）
	_reset_arena()                      # 回收敌人/投射物 + 按空槽同步（移除所有武器实例）
	GameState.add_weapon(id)
	weapon_manager.sync_from_game_state()  # 新增 id 武器实例


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


# ---- T15-a 武器升级至 7 级 --------------------------------------------------
func _test_leveling() -> void:
	GameState.start_new_run("watcher")
	var added: int = 0
	if GameState.add_weapon("harpoon"):
		added += 1
	for _i in 6:  # 再获得 6 次 → 累计 7 次入槽/升级
		if GameState.add_weapon("harpoon"):
			added += 1
	_assert(GameState.get_weapon_level("harpoon") == 7, "武器可升至 7 级 (max_weapon_level)")
	_assert(added == 7, "harpoon 累计获得 7 次均成功")
	var eighth: bool = GameState.add_weapon("harpoon")
	_assert(eighth == false, "满级(7)后再获得同一武器返回 false")
	_assert(GameState.get_weapon_level("harpoon") == 7, "满级后等级维持 7 不变")


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


func _finish() -> void:
	print("========================================")
	print("[W5WeaponTest] 通过 %d / 失败 %d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("[W5WeaponTest] 失败项: " + ", ".join(_fail_msgs))
		get_tree().quit(1)
	else:
		print("[W5WeaponTest] 全部通过 ✅")
		get_tree().quit(0)
