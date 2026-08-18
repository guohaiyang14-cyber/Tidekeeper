# ============================================================================
# AffixSystem — 精英词缀（W8，§5.4）
# 职责：抽取 / 施加 / 每帧 tick / 受伤 / 死亡 结算 6 种词缀。
# 数据：config/enemies.json affixes + metadata.affix_rules
# 红线：分裂/召唤走 EnemyPool（禁止 instantiate）；随机走 RNG；数值只读 config
# ============================================================================
class_name AffixSystem
extends RefCounted


## 全部词缀 id（排除 _meta）
static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k in ConfigLoader.affixes.keys():
		var id: String = String(k)
		if id == "_meta":
			continue
		out.append(id)
	return out


## 无放回抽取 count 个词缀（确定性 RNG）
static func pick(count: int) -> Array[String]:
	var pool: Array[String] = all_ids()
	var out: Array[String] = []
	var n: int = mini(maxi(count, 0), pool.size())
	while out.size() < n and not pool.is_empty():
		var idx: int = RNG.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out


## 写入敌人词缀并初始化计时器（不复制已有 split 到分裂体）
static func apply(enemy: EnemyBase, ids: Array[String]) -> void:
	enemy.affix_ids.clear()
	enemy.affix_state.clear()
	for id in ids:
		if id == "" or id == "_meta":
			continue
		if id in enemy.affix_ids:
			continue
		enemy.affix_ids.append(id)
	if enemy.has_affix("teleport"):
		var tel: Dictionary = ConfigLoader.get_affix("teleport")
		enemy.affix_state["teleport_cd"] = float(tel.get("interval", 8.0))
	if enemy.has_affix("chain"):
		enemy.affix_state["chain_cd"] = 0.0
	if enemy.has_affix("regen"):
		enemy.affix_state["regen_t"] = 0.0


static func tick(enemy: EnemyBase, delta: float) -> void:
	if enemy == null or enemy.is_dead():
		return
	_tick_aura_decay(enemy, delta)
	if enemy.has_affix("swift"):
		_tick_swift(enemy)
	if enemy.has_affix("teleport") and not enemy.is_burrowed():
		_tick_teleport(enemy, delta)
	if enemy.has_affix("regen"):
		_tick_regen(enemy, delta)
	if enemy.has_affix("chain"):
		var cd: float = float(enemy.affix_state.get("chain_cd", 0.0))
		if cd > 0.0:
			enemy.affix_state["chain_cd"] = cd - delta


static func on_damaged(enemy: EnemyBase, amount: int, is_melee: bool) -> void:
	if enemy == null or amount <= 0:
		return
	if enemy.has_affix("regen"):
		enemy.affix_state["regen_t"] = 0.0
	if is_melee and enemy.has_affix("thorns"):
		var th: Dictionary = ConfigLoader.get_affix("thorns")
		var ratio: float = float(th.get("melee_reflect_ratio", 0.3))
		var reflect: int = maxi(1, int(round(float(amount) * ratio)))
		GameState.damage_player(reflect, "affix_thorns")
	if enemy.has_affix("chain"):
		_try_chain_bind(enemy)


static func on_death(enemy: EnemyBase) -> void:
	if enemy == null or enemy.is_boss:
		return
	if not enemy.has_affix("split"):
		return
	_do_split(enemy)


# ============================================================================
# 内部
# ============================================================================

static func _tick_aura_decay(enemy: EnemyBase, delta: float) -> void:
	if enemy.aura_timer <= 0.0:
		return
	enemy.aura_timer -= delta
	if enemy.aura_timer <= 0.0:
		enemy.aura_speed_bonus = 0.0


static func _tick_swift(enemy: EnemyBase) -> void:
	var sw: Dictionary = ConfigLoader.get_affix("swift")
	var radius: float = float(sw.get("aura_radius", 90.0))
	var bonus: float = float(sw.get("speed_bonus", 0.25))
	var refresh: float = float(sw.get("aura_refresh", 0.25))
	_apply_aura_to(enemy, bonus, refresh)
	var hash: SpatialHash = enemy.get_spatial_hash()
	if hash == null:
		return
	var nearby: Array = hash.query_radius(enemy.global_position, radius)
	for n in nearby:
		if n is EnemyBase and n != enemy:
			var other: EnemyBase = n as EnemyBase
			if other.is_dead():
				continue
			if enemy.global_position.distance_to(other.global_position) > radius:
				continue
			_apply_aura_to(other, bonus, refresh)


static func _apply_aura_to(target: EnemyBase, bonus: float, refresh: float) -> void:
	if bonus > target.aura_speed_bonus:
		target.aura_speed_bonus = bonus
	target.aura_timer = maxf(target.aura_timer, refresh)


static func _tick_teleport(enemy: EnemyBase, delta: float) -> void:
	var cd: float = float(enemy.affix_state.get("teleport_cd", 0.0)) - delta
	if cd > 0.0:
		enemy.affix_state["teleport_cd"] = cd
		return
	var tel: Dictionary = ConfigLoader.get_affix("teleport")
	enemy.affix_state["teleport_cd"] = float(tel.get("interval", 8.0))
	var rng_range: float = float(tel.get("range", 140.0))
	var angle: float = RNG.randf_range(0.0, TAU)
	var dist: float = RNG.randf_range(rng_range * 0.4, rng_range)
	var old_pos: Vector2 = enemy.global_position
	enemy.global_position = old_pos + Vector2.from_angle(angle) * dist
	var hash: SpatialHash = enemy.get_spatial_hash()
	if hash != null:
		hash.update(enemy, old_pos)


static func _tick_regen(enemy: EnemyBase, delta: float) -> void:
	var t: float = float(enemy.affix_state.get("regen_t", 0.0)) + delta
	var rg: Dictionary = ConfigLoader.get_affix("regen")
	var need: float = float(rg.get("out_of_combat", 5.0))
	if t < need:
		enemy.affix_state["regen_t"] = t
		return
	enemy.affix_state["regen_t"] = 0.0
	var ratio: float = float(rg.get("heal_ratio", 0.3))
	var heal: int = maxi(1, int(round(float(enemy.max_health) * ratio)))
	enemy.health = mini(enemy.max_health, enemy.health + heal)


static func _try_chain_bind(enemy: EnemyBase) -> void:
	var cd: float = float(enemy.affix_state.get("chain_cd", 0.0))
	if cd > 0.0:
		return
	var ch: Dictionary = ConfigLoader.get_affix("chain")
	enemy.affix_state["chain_cd"] = float(ch.get("cooldown", 2.0))
	var dur: float = float(ch.get("bind_duration", 0.5))
	if enemy.get_tree() == null:
		return
	var players: Array = enemy.get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p: Node = players[0]
	if p.has_method("apply_bind"):
		p.apply_bind(dur)


static func _do_split(enemy: EnemyBase) -> void:
	var sp: Dictionary = ConfigLoader.get_affix("split")
	var count: int = int(sp.get("count", 2))
	var hp_ratio: float = float(sp.get("hp_ratio", 0.4))
	var offset: float = float(sp.get("offset", 24.0))
	var spawner: Node = _find_spawner(enemy)
	if spawner == null or not spawner.has_method("spawn_enemy"):
		push_warning("[AffixSystem] 分裂失败：无 EnemySpawner")
		return
	var def: Dictionary = _resolve_split_def(enemy)
	if def.is_empty():
		push_warning("[AffixSystem] 分裂失败：无原型配置 id=%s prototype=%s" % [
			enemy.enemy_id, enemy.prototype_id,
		])
		return
	var child_hp: int = maxi(1, int(round(float(enemy.max_health) * hp_ratio)))
	var no_affix: Array[String] = []
	var spawned: int = 0
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		var pos: Vector2 = enemy.global_position + Vector2.from_angle(angle) * offset
		var child: EnemyBase = spawner.call("spawn_enemy", def, pos, no_affix, true, true) as EnemyBase
		if child == null:
			push_warning("[AffixSystem] 分裂体生成失败（池耗尽或达上限）parent=%s %d/%d" % [
				enemy.enemy_id, spawned, count,
			])
			break
		child.max_health = child_hp
		child.health = child_hp
		child.apply_visual_scale(0.7)
		spawned += 1


## 分裂查表：优先 prototype_id（精英 → base_enemy_id），再回退 elite 元数据
static func _resolve_split_def(enemy: EnemyBase) -> Dictionary:
	var proto: String = enemy.prototype_id if enemy.prototype_id != "" else enemy.enemy_id
	var def: Dictionary = ConfigLoader.get_enemy(proto)
	if not def.is_empty():
		return def
	def = ConfigLoader.get_enemy(enemy.enemy_id)
	if not def.is_empty():
		return def
	var elite: Dictionary = ConfigLoader.get_enemy_elite()
	if enemy.enemy_id == String(elite.get("id", "")):
		return ConfigLoader.get_enemy(String(elite.get("base_enemy_id", "iron_crab")))
	return {}


static func _find_spawner(enemy: EnemyBase) -> Node:
	if enemy.get_tree() == null:
		return null
	var nodes: Array = enemy.get_tree().get_nodes_in_group("enemy_spawner")
	if nodes.is_empty():
		return null
	return nodes[0] as Node
