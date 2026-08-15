# ============================================================================
# WeaponManager — 武器管理器（W5，挂在 World 下）
# 职责：按 GameState.weapon_slots 增删武器实例；_process 驱动所有武器 tick；
#       注入索敌（SpatialHash 最近敌人）与玩家位置；提供投射物池 / hash 给武器
# 红线：运行时禁止 instantiate（武器实例按 behavior_type new，弹道走 projectile_pool）
# ============================================================================
class_name WeaponManager
extends Node

# 显式预加载武器类脚本，确保 headless 下 class_name 注册（_create_weapon 用 .new()）
const _WEAPON_BASE = preload("res://scripts/combat/weapon_base.gd")
const _WEAPON_HARPOON = preload("res://scripts/combat/weapon_harpoon.gd")
const _WEAPON_HOLY_FIRE = preload("res://scripts/combat/weapon_holy_fire.gd")
const _WEAPON_ANCHOR = preload("res://scripts/combat/weapon_anchor_chain.gd")
const _WEAPON_ANCHOR_HAMMER = preload("res://scripts/combat/weapon_anchor_hammer.gd")
const _WEAPON_SPORE = preload("res://scripts/combat/weapon_spore.gd")
const _WEAPON_STORM = preload("res://scripts/combat/weapon_storm_cloud.gd")
const _WEAPON_JELLY = preload("res://scripts/combat/weapon_jellyfish_cannon.gd")
const _WEAPON_ALBATROSS = preload("res://scripts/combat/weapon_albatross.gd")

var _weapons: Array[WeaponBase] = []
var _player: Node2D
var _hash: SpatialHash
var _projectile_pool: ProjectilePool


func setup(player: Node2D, hash: SpatialHash, projectile_pool: ProjectilePool) -> void:
	_player = player
	_hash = hash
	_projectile_pool = projectile_pool


func _process(delta: float) -> void:
	for w in _weapons:
		w.tick(delta)


## 当前激活的武器实例（供测试 / 调试）
func get_weapons() -> Array[WeaponBase]:
	return _weapons


func get_projectile_pool() -> ProjectilePool:
	return _projectile_pool


func get_hash() -> SpatialHash:
	return _hash


## 同步 GameState.weapon_slots → 武器实例（升级获得武器后由 World 调用）
func sync_from_game_state() -> void:
	var owned: Array[String] = GameState.weapon_slots
	for id in owned:
		if not _has_weapon(id):
			_add_weapon_instance(id)
	for i in range(_weapons.size() - 1, -1, -1):
		var w: WeaponBase = _weapons[i]
		if w.weapon_id not in owned:
			_remove_weapon_instance(w)
		else:
			# 已持有：同步等级（三选一/商店升级后实例需跟上 GameState）
			w.level = GameState.get_weapon_level(w.weapon_id)


func _has_weapon(id: String) -> bool:
	for w in _weapons:
		if w.weapon_id == id:
			return true
	return false


func _add_weapon_instance(id: String) -> void:
	var data: Dictionary = ConfigLoader.get_weapon(id)
	if data.is_empty():
		return
	var w: WeaponBase = _create_weapon(data.get("behavior_type", ""))
	if w == null:
		return
	w.configure(data, GameState.get_weapon_level(id))
	w.get_owner_pos = _owner_pos_provider
	w.get_target = _target_node_provider
	add_child(w)
	_weapons.append(w)
	print("[WeaponManager] 装备武器: %s (lv%d)" % [id, w.level])


func _create_weapon(behavior_type: String) -> WeaponBase:
	match behavior_type:
		"directional_pierce":
			return WeaponHarpoon.new()
		"area_burn":
			return WeaponHolyFire.new()
		"orbit_tick":
			return WeaponAnchorChain.new()
		"melee_burst":
			return WeaponAnchorHammer.new()
		"summon_jellyfish":
			return WeaponSpore.new()
		"area_lightning":
			return WeaponStormCloud.new()
		"ring_barrage":
			return WeaponJellyfishCannon.new()
		"summon_dive":
			return WeaponAlbatross.new()
		_:
			push_warning("[WeaponManager] 未知 behavior_type: %s，跳过" % behavior_type)
			return null


func _remove_weapon_instance(w: WeaponBase) -> void:
	_weapons.erase(w)
	w.queue_free()


func _owner_pos_provider() -> Vector2:
	return _player.global_position if _player != null else Vector2.ZERO


## 索敌：从 SpatialHash 查玩家周围最近敌人（返回 EnemyBase 或 null）
func _target_node_provider() -> EnemyBase:
	if _hash == null or _player == null:
		return null
	var enemies: Array = _hash.query_radius(_player.global_position, 600.0)
	var best: EnemyBase = null
	var best_dist: float = INF
	for e in enemies:
		if e is EnemyBase:
			var d: float = _player.global_position.distance_to(e.global_position)
			if d < best_dist:
				best_dist = d
				best = e
	return best
