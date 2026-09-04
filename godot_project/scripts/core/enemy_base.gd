# ============================================================================
# EnemyBase — 敌人基类（W2-W3 五种基础行为 + W8 四种进阶行为）
# 职责：数据驱动配置（configure 读 config/enemies.json + §8.2 难度公式缩放）；
#       按 behavior_type 分派行为；接触/弹幕/自爆伤害走 GameState；
#       死亡 emit enemy_died 供 World 掉落经验珠+潮币；注册自定义 SpatialHash。
# 红线：不走 Physics2D；随机走 RNG；不分帧外分配；运行时零 instantiate（弹道/召唤走对象池）
# 注册：通过 "spatial_hash" group 查 SpatialHashHolder；"enemy_projectile_pool" group 查弹道池
# ============================================================================
class_name EnemyBase
extends Node2D

const _AFFIX_SYSTEM = preload("res://scripts/combat/affix_system.gd")
const _BOSS_BRAIN = preload("res://scripts/combat/boss_brain.gd")

signal enemy_died(enemy: EnemyBase)

# ---- 配置注入（由 EnemySpawner 调用 configure） ----
var enemy_id: String = ""
## 分裂/召唤用的原型表 id（精英可与 enemy_id 不同，如 giant_claw_king → iron_crab）
var prototype_id: String = ""
var behavior_type: String = "charge_linear"
var danger: int = 1
var update_group: int = 2
var base_exp: int = 1
var coin_drop: int = 1
var night: int = 1

# ---- 运行时属性（configure 写入） ----
var max_health: int = 30
var health: int = 0
var move_speed: float = 60.0
var contact_damage: int = 8
var contact_radius: float = 18.0
var is_flying: bool = false
var _fire_interval: float = 2.0
var _ranged_damage: int = 0
var _explode_radius: float = 40.0
var _self_destruct_damage: int = 0
var _burrow_duration: float = 3.0
var _contact_interval: float = 0.5
var _burrow_cooldown_cfg: float = 2.0
var _burrow_initial_delay: float = 1.0
## 浮现时沿玩家速度反向偏移（0=脚下必中；>0 使保持移动可躲同帧接触）
var _burrow_emerge_behind: float = 40.0
## 判定玩家「在移动」的 velocity.length_squared 阈值（config metadata.combat）
var _burrow_move_detect_speed_sq: float = 40.0
var _summon_id: String = "small_goblin"
var _summon_interval: float = 3.0
var _summon_count: int = 1
var _keep_distance: float = 180.0
var _charge_dr: float = 0.5
var _charge_speed_mult: float = 2.2
var _charge_duration: float = 0.8
var _charge_cooldown: float = 2.0
var _charge_trigger_range: float = 160.0
var _share_ratio: float = 0.4
var _share_radius: float = 90.0
var _share_max_allies: int = 8
var _visual_size: float = 20.0
var _tint: Color = Color(0.85, 0.25, 0.25)

# ---- Boss 标记（configure_boss 置 true，configure 复位 false） ----
var is_boss: bool = false
## 命名精英（巨钳王等；进化道具掉落用）
var is_elite: bool = false
## 预算耗尽后的密度 floor 补刷（维持压力，不掉经验/潮币/进化道具）
var is_floor_refill: bool = false
var _boss_brain: BossBrain
var _boss_data: Dictionary = {}
## 灯塔位置（潮汐波安全区圆心；由 Spawner 注入）
var lighthouse_position: Vector2 = Vector2.ZERO

# ---- 词缀（W8） ----
var affix_ids: Array[String] = []
var affix_state: Dictionary = {}
var aura_speed_bonus: float = 0.0
var aura_timer: float = 0.0

# ---- 状态 ----
var target: Node2D
## 本实例刷出时的世界坐标（TestBot 死亡距离/刷点分析；池复用时在 spawn_at 覆盖）
var spawn_position: Vector2 = Vector2.ZERO
## 刷出瞬间相对追击目标的距离（缓存；避免死亡时用「当前玩家位置」污染 avg_sdist）
var spawn_distance_to_target: float = -1.0
var _hash: SpatialHash
var _dead: bool = false
## 生成时刻（秒，Time.get_ticks_msec）；供 TestBot 存活时间统计
var _alive_since_sec: float = 0.0
var _contact_cd: float = 0.0
var _fire_timer: float = 0.0
var _burrowed: bool = false
var _burrow_timer: float = 0.0
var _burrow_cooldown: float = 1.0
var _enemy_proj_pool: ObjectPool
var _charging: bool = false
var _charge_timer: float = 0.0
var _charge_cd: float = 0.0
var _charge_dir: Vector2 = Vector2.RIGHT
var _summon_timer: float = 0.0

# ---- 减速（水母炮等弹道命中） ----
var _move_speed_mult: float = 1.0
var _slow_timer: float = 0.0

@onready var _visual: ColorRect = $Visual


# ============================================================================
# 池生命周期（ObjectPool 约定）
# ============================================================================

## acquire 时调用：仅重置状态，不注册哈希
func _on_acquire() -> void:
	_dead = false
	health = max_health
	_alive_since_sec = float(Time.get_ticks_msec()) * 0.001
	_contact_cd = 0.0
	_fire_timer = 0.0
	_burrowed = false
	_burrow_timer = 0.0
	_burrow_cooldown = _burrow_initial_delay
	_move_speed_mult = 1.0
	_slow_timer = 0.0
	_charging = false
	_charge_timer = 0.0
	_charge_cd = 0.0
	_summon_timer = 0.0
	prototype_id = ""
	is_boss = false
	is_elite = false
	is_floor_refill = false
	_boss_brain = null
	_boss_data = {}
	affix_ids.clear()
	affix_state.clear()
	aura_speed_bonus = 0.0
	aura_timer = 0.0
	spawn_position = Vector2.ZERO
	spawn_distance_to_target = -1.0
	_ensure_hash()
	_ensure_enemy_projectile_pool()


## release 时调用：从哈希移除；标记死亡，避免 clear_all 后武器仍结算触发二次 _die
func _on_release() -> void:
	_dead = true
	if _hash != null:
		_hash.remove(self, global_position)


func _ensure_hash() -> void:
	if _hash != null:
		return
	var holders: Array = get_tree().get_nodes_in_group("spatial_hash")
	if not holders.is_empty():
		var holder: SpatialHashHolder = holders[0] as SpatialHashHolder
		if holder != null:
			_hash = holder.get_hash()


func get_spatial_hash() -> SpatialHash:
	return _hash


func _ensure_enemy_projectile_pool() -> void:
	if _enemy_proj_pool != null:
		return
	var pools: Array = get_tree().get_nodes_in_group("enemy_projectile_pool")
	if not pools.is_empty():
		_enemy_proj_pool = pools[0] as ObjectPool


## 刷怪生成：设位置与目标，并注册到空间哈希（由 Spawner 调用）
func spawn_at(pos: Vector2, tgt: Node2D) -> void:
	global_position = pos
	spawn_position = pos
	target = tgt
	if tgt != null and is_instance_valid(tgt):
		spawn_distance_to_target = pos.distance_to(tgt.global_position)
	else:
		spawn_distance_to_target = -1.0
	_alive_since_sec = float(Time.get_ticks_msec()) * 0.001
	if _hash != null:
		_hash.insert(self)


## 与追击目标的距离（无目标时返回 -1）
func get_distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return -1.0
	return global_position.distance_to(target.global_position)


## 刷出瞬间相对目标的距离（spawn_at 缓存；无目标时为 -1）
func get_spawn_distance_to_target() -> float:
	return spawn_distance_to_target


## 已存活秒数（生成起算；TestBot / 调试）
func get_alive_seconds() -> float:
	return maxf(0.0, float(Time.get_ticks_msec()) * 0.001 - _alive_since_sec)


## 数据驱动配置：读 config 并按 §8.2 难度公式缩放血量/伤害
## scale=false 时跳过难度缩放（Boss 用 config 表中的 base_health 原值）
func configure(data: Dictionary, night_value: int, scale: bool = true) -> void:
	enemy_id = data.get("id", "")
	prototype_id = String(data.get("prototype_id", enemy_id))
	behavior_type = data.get("behavior_type", "charge_linear")
	danger = int(data.get("danger", 1))
	update_group = int(data.get("update_group", 2))
	base_exp = int(data.get("base_exp", 1))
	night = night_value
	is_boss = false
	is_elite = false
	is_floor_refill = false
	_boss_brain = null
	_boss_data = {}
	affix_ids.clear()
	affix_state.clear()
	aura_speed_bonus = 0.0
	aura_timer = 0.0
	_charging = false
	_charge_timer = 0.0
	_charge_cd = 0.0
	_summon_timer = 0.0

	var diff: Dictionary = ConfigLoader.get_enemy_difficulty()
	var region_coeff: float = float(diff.get("region_coeff", 1.0))
	var hp_per_night: float = float(diff.get("health_per_night", 0.10))
	var hp_per_5: float = float(diff.get("health_per_5nights", 0.15))
	var dmg_per_night: float = float(diff.get("damage_per_night", 0.04))

	# W18 难度档位 + 教学宽容（守夜人 0.7× / 灯塔 1.0×；教学夜 1~4 敌人数值减半）
	var tier_hp: float = DifficultySystem.enemy_hp_multiplier(night_value)
	var tier_dmg: float = DifficultySystem.enemy_damage_multiplier(night_value)

	var hp_scale: float = 1.0
	var dmg_scale: float = 1.0
	if scale:
		hp_scale = region_coeff * tier_hp * (1.0 + hp_per_night * float(night)) * (1.0 + hp_per_5 * floor(float(night) / 5.0))
		dmg_scale = tier_dmg * (1.0 + dmg_per_night * float(night))

	max_health = int(roundi(float(data.get("base_health", 30)) * hp_scale))
	contact_damage = int(roundi(float(data.get("base_contact_damage", 8)) * dmg_scale))
	coin_drop = maxi(1, int(roundi(float(base_exp))))  # 原型：潮币≈经验
	health = max_health

	# 运行期参数（数据驱动，§4.2 不硬编码）
	move_speed = float(data.get("move_speed", 60.0))
	contact_radius = float(data.get("contact_radius", 18.0))
	_fire_interval = float(data.get("fire_interval", 2.0))
	_ranged_damage = int(roundi(float(data.get("ranged_projectile_damage", 0)) * dmg_scale))
	_explode_radius = float(data.get("explode_radius", 40.0))
	_self_destruct_damage = int(roundi(float(data.get("self_destruct_damage", 0)) * dmg_scale))
	_burrow_duration = float(data.get("burrow_duration", 3.0))
	var combat: Dictionary = ConfigLoader.get_enemy_combat()
	_contact_interval = float(data.get("contact_interval", combat.get("contact_interval", 0.5)))
	_burrow_cooldown_cfg = float(data.get("burrow_cooldown", combat.get("burrow_cooldown", 2.0)))
	_burrow_initial_delay = float(data.get("burrow_initial_delay", combat.get("burrow_initial_delay", 1.0)))
	_burrow_emerge_behind = float(data.get("burrow_emerge_behind", combat.get("burrow_emerge_behind", 40.0)))
	_burrow_move_detect_speed_sq = float(data.get(
		"burrow_move_detect_speed_sq", combat.get("burrow_move_detect_speed_sq", 40.0)
	))
	_burrow_cooldown = _burrow_initial_delay
	_summon_id = String(data.get("summons", "small_goblin"))
	_summon_interval = float(data.get("summon_interval", 3.0))
	_summon_count = int(data.get("summon_count", 1))
	_keep_distance = float(data.get("keep_distance", 180.0))
	_charge_dr = float(data.get("charge_damage_reduction", 0.5))
	_charge_speed_mult = float(data.get("charge_speed_mult", 2.2))
	_charge_duration = float(data.get("charge_duration", 0.8))
	_charge_cooldown = float(data.get("charge_cooldown", 2.0))
	_charge_trigger_range = float(data.get("charge_trigger_range", 160.0))
	_share_ratio = float(data.get("damage_share_ratio", 0.4))
	_share_radius = float(data.get("damage_share_radius", 90.0))
	_share_max_allies = int(data.get("damage_share_max_allies", 8))
	_visual_size = float(data.get("visual_size", 20.0))
	_tint = _parse_tint(data.get("tint", [0.85, 0.25, 0.25]))
	is_flying = _has_flag(data.get("flags", []), "flying")
	_apply_visual(1.0)


## Boss 配置（W9）：不走 §8.2 难度缩放；挂载 BossBrain
func configure_boss(boss_data: Dictionary) -> void:
	enemy_id = boss_data.get("id", "")
	prototype_id = enemy_id
	behavior_type = String(boss_data.get("behavior_type", "charge_linear"))
	danger = int(boss_data.get("danger", 5))
	update_group = int(boss_data.get("update_group", 1))
	is_boss = true
	is_elite = false
	is_floor_refill = false
	_boss_data = boss_data
	night = GameState.current_night
	var bexp: int = int(boss_data.get("base_exp", 50))
	base_exp = bexp
	max_health = int(boss_data.get("base_health", 1000))
	contact_damage = int(boss_data.get("contact_damage", 20))
	var coin_mult: float = float(boss_data.get("coin_drop_mult", 2.0))
	coin_drop = maxi(1, roundi(float(bexp) * coin_mult))
	health = max_health
	move_speed = float(boss_data.get("move_speed", 40.0))
	contact_radius = float(boss_data.get("contact_radius", 30.0))
	_fire_interval = float(boss_data.get("fire_interval", 2.0))
	_ranged_damage = int(boss_data.get("ranged_projectile_damage", 0))
	_explode_radius = float(boss_data.get("explode_radius", 40.0))
	_self_destruct_damage = int(boss_data.get("self_destruct_damage", 0))
	_burrow_duration = float(boss_data.get("burrow_duration", 3.0))
	var combat: Dictionary = ConfigLoader.get_enemy_combat()
	_contact_interval = float(boss_data.get("contact_interval", combat.get("contact_interval", 0.5)))
	_burrow_cooldown_cfg = float(boss_data.get("burrow_cooldown", combat.get("burrow_cooldown", 2.0)))
	_burrow_initial_delay = float(boss_data.get("burrow_initial_delay", combat.get("burrow_initial_delay", 1.0)))
	_burrow_emerge_behind = float(boss_data.get("burrow_emerge_behind", combat.get("burrow_emerge_behind", 40.0)))
	_burrow_move_detect_speed_sq = float(boss_data.get(
		"burrow_move_detect_speed_sq", combat.get("burrow_move_detect_speed_sq", 40.0)
	))
	_burrow_cooldown = _burrow_initial_delay
	affix_ids.clear()
	affix_state.clear()
	_visual_size = float(boss_data.get("visual_size", 48.0))
	_tint = _parse_tint(boss_data.get("tint", [0.7, 0.2, 0.8]))
	_apply_visual(1.0)
	_boss_brain = BossBrain.create(behavior_type)
	if _boss_brain != null:
		_boss_brain.setup(self, boss_data)


func apply_affixes(ids: Array[String]) -> void:
	AffixSystem.apply(self, ids)


func has_affix(id: String) -> bool:
	return id in affix_ids


func apply_visual_scale(mult: float) -> void:
	_apply_visual(mult)


func _parse_tint(raw: Variant) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw as Array
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
	return Color(0.85, 0.25, 0.25)


func _has_flag(raw: Variant, flag: String) -> bool:
	if raw is Array:
		return flag in (raw as Array)
	return false


func _apply_visual(size_mult: float) -> void:
	var vis: ColorRect = _visual
	if vis == null:
		vis = get_node_or_null("Visual") as ColorRect
	if vis == null:
		return
	var s: float = _visual_size * size_mult
	vis.offset_left = -s * 0.5
	vis.offset_top = -s * 0.5
	vis.offset_right = s * 0.5
	vis.offset_bottom = s * 0.5
	vis.color = _tint


# ============================================================================
# 每帧行为
# ============================================================================

func _process(delta: float) -> void:
	if _dead or target == null:
		return
	var player_pos: Vector2 = target.global_position

	# 计时器每帧累加（不受分帧影响）
	_contact_cd -= delta
	_fire_timer -= delta
	if _burrowed:
		_burrow_timer -= delta
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_move_speed_mult = 1.0

	AffixSystem.tick(self, delta)

	# 分帧：仅移动逻辑走 update_group（SKILL.md §5.3）
	var do_move: bool = (Engine.get_process_frames() % update_group == 0)

	if is_boss and _boss_brain != null:
		_boss_brain.tick(delta, player_pos, do_move)
	else:
		match behavior_type:
			"burrow_ambush":
				_tick_burrow(delta, player_pos, do_move)
			"ranged_barrage":
				if do_move:
					_move_toward(player_pos, delta)
				if _fire_timer <= 0.0:
					_fire_timer = _fire_interval
					_fire_enemy_projectile(player_pos)
			"self_destruct":
				if do_move:
					_move_toward(player_pos, delta)
				if global_position.distance_to(player_pos) <= _explode_radius:
					_explode()
			"summoner":
				_tick_summoner(delta, player_pos, do_move)
			"charge_damage_reduction":
				_tick_charge(delta, player_pos, do_move)
			_:
				# charge_linear / slow_melee_armor_break / flying_swarm / damage_share / 默认
				if do_move:
					_move_toward(player_pos, delta)

	# 接触伤害（潜地中无敌且不可接触）
	if not _burrowed:
		_try_contact_damage(player_pos)


func _effective_speed() -> float:
	# 事件「暴风雨」全场敌人移速倍率（W14；无事件时为 1.0）
	var event_mult: float = EventSystem.get_enemy_speed_mult()
	if _charging:
		return move_speed * _charge_speed_mult * _move_speed_mult * event_mult
	return move_speed * _move_speed_mult * (1.0 + aura_speed_bonus) * event_mult


func _move_toward(player_pos: Vector2, delta: float) -> void:
	_move_in_dir(player_pos - global_position, delta)


func _move_in_dir(dir: Vector2, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var old_pos: Vector2 = global_position
	global_position += dir.normalized() * _effective_speed() * delta
	if _hash != null:
		_hash.update(self, old_pos)


## 施加移速减速（factor=0.8 → 移速×0.8；取更强减速并刷新持续时间）
func apply_slow(factor: float, duration: float) -> void:
	if duration <= 0.0 or factor >= 1.0:
		return
	_move_speed_mult = minf(_move_speed_mult, factor)
	_slow_timer = maxf(_slow_timer, duration)


func get_move_speed_mult() -> float:
	return _move_speed_mult


func get_effective_move_speed() -> float:
	return _effective_speed()


func _try_contact_damage(player_pos: Vector2) -> void:
	if _contact_cd > 0.0:
		return
	if global_position.distance_to(player_pos) <= contact_radius:
		GameState.damage_player(contact_damage, "contact:%s" % enemy_id)
		_contact_cd = _contact_interval


func _tick_burrow(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if _burrowed:
		if _burrow_timer <= 0.0:
			# 突袭浮现：站桩打脚下；若玩家在移动则落在速度反向，使走位可躲开同帧接触
			# 传送须更新 SpatialHash（与 boss_teleport 同契约，避免武器/弹道查旧格）
			_burrowed = false
			visible = true
			boss_teleport(_burrow_emerge_position(player_pos))
			_burrow_cooldown = _burrow_cooldown_cfg
		elif do_move:
			_move_toward(player_pos, delta)
	else:
		_burrow_cooldown -= delta
		if _burrow_cooldown <= 0.0:
			_burrowed = true
			visible = false
			_burrow_timer = _burrow_duration


## 突袭浮现点（站桩=脚下；移动=速度反向偏移）。机检可直接调用。
func compute_burrow_emerge_position(player_pos: Vector2) -> Vector2:
	return _burrow_emerge_position(player_pos)


func _burrow_emerge_position(player_pos: Vector2) -> Vector2:
	if _burrow_emerge_behind <= 0.0:
		return player_pos
	var move_dir: Vector2 = Vector2.ZERO
	var detect_sq: float = maxf(_burrow_move_detect_speed_sq, 0.0)
	var player_node: Player = target as Player
	if player_node != null and player_node.velocity.length_squared() > detect_sq:
		move_dir = player_node.velocity.normalized()
	elif target != null and target.get("velocity") is Vector2:
		var vel: Vector2 = target.get("velocity") as Vector2
		if vel.length_squared() > detect_sq:
			move_dir = vel.normalized()
	if move_dir.length_squared() < 0.0001:
		return player_pos
	return player_pos - move_dir * _burrow_emerge_behind


func _tick_summoner(delta: float, player_pos: Vector2, do_move: bool) -> void:
	var dist: float = global_position.distance_to(player_pos)
	if do_move:
		if dist < _keep_distance:
			_move_in_dir(global_position - player_pos, delta)
		elif dist > _keep_distance * 1.5:
			_move_toward(player_pos, delta)
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_summon_timer = _summon_interval
		_try_summon()


func _try_summon() -> void:
	if get_tree() == null:
		return
	var nodes: Array = get_tree().get_nodes_in_group("enemy_spawner")
	if nodes.is_empty():
		return
	var spawner: Node = nodes[0]
	if not spawner.has_method("spawn_enemy"):
		return
	var def: Dictionary = ConfigLoader.get_enemy(_summon_id)
	if def.is_empty():
		return
	var no_affix: Array[String] = []
	for _i in _summon_count:
		var angle: float = RNG.randf_range(0.0, TAU)
		var pos: Vector2 = global_position + Vector2.from_angle(angle) * 36.0
		if spawner.call("spawn_enemy", def, pos, no_affix, true) == null:
			break


func _tick_charge(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if _charging:
		_charge_timer -= delta
		if do_move:
			_move_in_dir(_charge_dir, delta)
		if _charge_timer <= 0.0:
			_charging = false
			_charge_cd = _charge_cooldown
		return
	_charge_cd -= delta
	var dist: float = global_position.distance_to(player_pos)
	if _charge_cd <= 0.0 and dist <= _charge_trigger_range:
		_charging = true
		_charge_timer = _charge_duration
		var dir: Vector2 = player_pos - global_position
		_charge_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	elif do_move:
		_move_toward(player_pos, delta)


func _fire_enemy_projectile(player_pos: Vector2) -> void:
	if _enemy_proj_pool == null:
		_ensure_enemy_projectile_pool()
	if _enemy_proj_pool == null:
		return
	var p: Node = _enemy_proj_pool.acquire()
	if p == null or not p.has_method("launch"):
		return
	var dir: Vector2 = (player_pos - global_position).normalized()
	p.launch(global_position, dir, _ranged_damage)


# ============================================================================
# BossBrain 接口（公开给战斗脚本）
# ============================================================================

func boss_move_toward(pos: Vector2, delta: float) -> void:
	_move_toward(pos, delta)


func boss_move_away(pos: Vector2, delta: float) -> void:
	_move_in_dir(global_position - pos, delta)


func boss_teleport(pos: Vector2) -> void:
	var old_pos: Vector2 = global_position
	global_position = pos
	if _hash != null:
		_hash.update(self, old_pos)


func boss_fire_projectile(dir: Vector2, damage: int) -> void:
	if _enemy_proj_pool == null:
		_ensure_enemy_projectile_pool()
	if _enemy_proj_pool == null:
		return
	var p: Node = _enemy_proj_pool.acquire()
	if p == null or not p.has_method("launch"):
		return
	p.launch(global_position, dir, damage)


func find_spawner() -> Node:
	if get_tree() == null:
		return null
	var nodes: Array = get_tree().get_nodes_in_group("enemy_spawner")
	if nodes.is_empty():
		return null
	return nodes[0] as Node


func get_lighthouse_position() -> Vector2:
	return lighthouse_position


func get_boss_phase() -> int:
	if _boss_brain == null:
		return 0
	return _boss_brain.phase


func _explode() -> void:
	GameState.damage_player(_self_destruct_damage, "explode:%s" % enemy_id)
	_die()


# ============================================================================
# 受伤 / 死亡
# ============================================================================

## 受伤（潜地中免伤）；is_melee 供荆棘反伤；from_share 避免分摊递归/重入分裂
## source_id：武器 id（TestBot 伤害归因；空串跳过记账）
func take_damage(amount: int, is_melee: bool = false, from_share: bool = false, source_id: String = "") -> bool:
	if _dead or _burrowed:
		return false
	if amount <= 0:
		return false
	if is_boss and _boss_brain != null:
		amount = _boss_brain.modify_incoming_damage(amount)
	if amount <= 0:
		return false
	if _charging:
		amount = maxi(1, int(round(float(amount) * (1.0 - _charge_dr))))
	if not from_share and behavior_type == "damage_share":
		amount = _share_damage(amount, source_id)
	health -= amount
	_notify_bot_damage(source_id, amount)
	if is_boss and _boss_brain != null:
		_boss_brain.on_health_changed()
	if not from_share:
		AffixSystem.on_damaged(self, amount, is_melee)
	else:
		if has_affix("regen"):
			affix_state["regen_t"] = 0.0
	if health <= 0:
		# 分摊致死不触发分裂，避免 take_damage → _die → split 重入
		_die(not from_share)
		return true
	return false


func _share_damage(amount: int, source_id: String = "") -> int:
	if _hash == null or amount <= 0:
		return amount
	var shared: int = int(round(float(amount) * _share_ratio))
	if shared <= 0:
		return amount
	var candidates: Array = _hash.query_radius(global_position, _share_radius)
	var allies: Array[EnemyBase] = []
	for n in candidates:
		if not (n is EnemyBase) or n == self:
			continue
		var other: EnemyBase = n as EnemyBase
		if other.is_dead() or other.is_burrowed() or other.behavior_type == "damage_share":
			continue
		if global_position.distance_to(other.global_position) > _share_radius:
			continue
		allies.append(other)
		if allies.size() >= _share_max_allies:
			break
	if allies.is_empty():
		return amount
	var each: int = maxi(1, int(round(float(shared) / float(allies.size()))))
	for ally in allies:
		ally.take_damage(each, false, true, source_id)
	return maxi(1, amount - shared)


func _die(trigger_split: bool = true) -> void:
	if _dead:
		return
	_dead = true
	_notify_bot_death()
	if trigger_split:
		AffixSystem.on_death(self)
	enemy_died.emit(self)
	# W17 挣扎模式：每次击杀累计（floor 补刷怪不计入，避免无掉落压力怪刷复活进度）
	if not is_floor_refill:
		GameState.register_enemy_kill()
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)


## 是否已死亡（测试 / 外部查询）
func is_dead() -> bool:
	return _dead


## 是否处于潜地状态（测试 / 外部查询）
func is_burrowed() -> bool:
	return _burrowed


func is_charging() -> bool:
	return _charging


## 可选战斗遥测槽（TestBot 启用时注册自身；未注册时命中路径仅一次 null 判断）
static var _combat_telemetry: Object = null


## TestBot 启用/关闭时调用；sink 需实现 note_damage / note_enemy_death / note_enemy_spawn
static func set_combat_telemetry(sink: Object) -> void:
	_combat_telemetry = sink


static func get_combat_telemetry() -> Object:
	return _combat_telemetry


func _notify_bot_damage(source_id: String, amount: int) -> void:
	if _combat_telemetry == null or source_id == "" or amount <= 0:
		return
	_combat_telemetry.note_damage(source_id, amount)


func _notify_bot_death() -> void:
	if _combat_telemetry == null:
		return
	_combat_telemetry.note_enemy_death(self)
