# ============================================================================
# EnemyBase — 敌人基类（W2-W3 全量行为）
# 职责：数据驱动配置（configure 读 config/enemies.json + §8.2 难度公式缩放）；
#       按 behavior_type 分派 5 种原型行为；接触/弹幕/自爆伤害走 GameState；
#       死亡 emit enemy_died 供 World 掉落经验珠+潮币；注册自定义 SpatialHash。
# 红线：不走 Physics2D；随机走 RNG；不分帧外分配；运行时零 instantiate（弹道走对象池）
# 注册：通过 "spatial_hash" group 查 SpatialHashHolder；"enemy_projectile_pool" group 查弹道池
# ============================================================================
class_name EnemyBase
extends Node2D

signal enemy_died(enemy: EnemyBase)

# ---- 配置注入（由 EnemySpawner 调用 configure） ----
var enemy_id: String = ""
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
var _fire_interval: float = 2.0
var _ranged_damage: int = 0
var _explode_radius: float = 40.0
var _self_destruct_damage: int = 0
var _burrow_duration: float = 3.0

# ---- Boss 标记（configure_boss 置 true，configure 复位 false） ----
var is_boss: bool = false

# ---- 状态 ----
var target: Node2D
var _hash: SpatialHash
var _dead: bool = false
var _contact_cd: float = 0.0
var _fire_timer: float = 0.0
var _burrowed: bool = false
var _burrow_timer: float = 0.0
var _burrow_cooldown: float = 1.0
var _enemy_proj_pool: ObjectPool


# ============================================================================
# 池生命周期（ObjectPool 约定）
# ============================================================================

## acquire 时调用：仅重置状态，不注册哈希
func _on_acquire() -> void:
	_dead = false
	health = max_health
	_contact_cd = 0.0
	_fire_timer = 0.0
	_burrowed = false
	_burrow_timer = 0.0
	_burrow_cooldown = 1.0
	_ensure_hash()
	_ensure_enemy_projectile_pool()


## release 时调用：从哈希移除
func _on_release() -> void:
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


func _ensure_enemy_projectile_pool() -> void:
	if _enemy_proj_pool != null:
		return
	var pools: Array = get_tree().get_nodes_in_group("enemy_projectile_pool")
	if not pools.is_empty():
		_enemy_proj_pool = pools[0] as ObjectPool


## 刷怪生成：设位置与目标，并注册到空间哈希（由 Spawner 调用）
func spawn_at(pos: Vector2, tgt: Node2D) -> void:
	global_position = pos
	target = tgt
	if _hash != null:
		_hash.insert(self)


## 数据驱动配置：读 config 并按 §8.2 难度公式缩放血量/伤害
## scale=false 时跳过难度缩放（Boss 用 config 表中的 base_health 原值）
func configure(data: Dictionary, night_value: int, scale: bool = true) -> void:
	enemy_id = data.get("id", "")
	behavior_type = data.get("behavior_type", "charge_linear")
	danger = int(data.get("danger", 1))
	update_group = int(data.get("update_group", 2))
	base_exp = int(data.get("base_exp", 1))
	night = night_value
	is_boss = false

	var diff: Dictionary = ConfigLoader.get_enemy_difficulty()
	var region_coeff: float = float(diff.get("region_coeff", 1.0))
	var hp_per_night: float = float(diff.get("health_per_night", 0.10))
	var hp_per_5: float = float(diff.get("health_per_5nights", 0.15))
	var dmg_per_night: float = float(diff.get("damage_per_night", 0.04))

	var hp_scale: float = 1.0
	var dmg_scale: float = 1.0
	if scale:
		hp_scale = region_coeff * (1.0 + hp_per_night * float(night)) * (1.0 + hp_per_5 * floor(float(night) / 5.0))
		dmg_scale = 1.0 + dmg_per_night * float(night)

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


## Boss 占位配置（W3）：不走 §8.2 难度缩放，base_health 直接用 bosses.json 原值
## 行为用 charge_linear 占位（完整 Boss 阶段技见 MVP W5）
func configure_boss(boss_data: Dictionary) -> void:
	enemy_id = boss_data.get("id", "")
	behavior_type = "charge_linear"
	danger = 5
	update_group = 2
	is_boss = true
	night = GameState.current_night
	var bexp: int = int(boss_data.get("base_exp", 50))
	base_exp = bexp
	max_health = int(boss_data.get("base_health", 1000))
	var cd: Variant = boss_data.get("contact_damage", null)
	contact_damage = int(cd) if cd != null else 20
	coin_drop = maxi(1, roundi(float(bexp) * 2.0))
	health = max_health
	move_speed = 40.0
	contact_radius = 30.0
	_fire_interval = 2.0
	_ranged_damage = 0
	_explode_radius = 40.0
	_self_destruct_damage = 0
	_burrow_duration = 3.0


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

	# 分帧：仅移动逻辑走 update_group（SKILL.md §5.3）
	var do_move: bool = (Engine.get_process_frames() % update_group == 0)

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
		_:
			# charge_linear / slow_melee_armor_break / 默认：朝玩家移动
			if do_move:
				_move_toward(player_pos, delta)

	# 接触伤害（潜地中无敌且不可接触）
	if not _burrowed:
		_try_contact_damage(player_pos)


func _move_toward(player_pos: Vector2, delta: float) -> void:
	var old_pos: Vector2 = global_position
	var dir: Vector2 = (player_pos - global_position).normalized()
	global_position += dir * move_speed * delta
	if _hash != null:
		_hash.update(self, old_pos)


func _try_contact_damage(player_pos: Vector2) -> void:
	if _contact_cd > 0.0:
		return
	if global_position.distance_to(player_pos) <= contact_radius:
		GameState.damage_player(contact_damage)
		_contact_cd = 0.5


func _tick_burrow(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if _burrowed:
		if _burrow_timer <= 0.0:
			# 突袭：在玩家脚下浮现
			_burrowed = false
			visible = true
			global_position = player_pos
			_burrow_cooldown = 2.0
		elif do_move:
			_move_toward(player_pos, delta)
	else:
		_burrow_cooldown -= delta
		if _burrow_cooldown <= 0.0:
			_burrowed = true
			visible = false
			_burrow_timer = _burrow_duration


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


func _explode() -> void:
	GameState.damage_player(_self_destruct_damage)
	_die()


# ============================================================================
# 受伤 / 死亡
# ============================================================================

## 受伤（潜地中免伤）；返回是否致死
func take_damage(amount: int) -> bool:
	if _dead or _burrowed:
		return false
	health -= amount
	if health <= 0:
		_die()
		return true
	return false


func _die() -> void:
	if _dead:
		return
	_dead = true
	enemy_died.emit(self)
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)
