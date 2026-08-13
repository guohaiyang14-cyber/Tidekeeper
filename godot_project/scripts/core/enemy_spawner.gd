# ============================================================================
# EnemySpawner — 潮汐刷怪（W2-W3）
# 职责：按 config/enemies.json 的 spawn_night 解锁 5 种行为敌人；
#       依据 metadata.spawn 密度曲线（前 12s 稀疏 → 中段密集 → 末段加压）刷怪；
#       精英夜（第 5 夜=巨钳王，强化铁壳蟹）/ 天灾夜（第 10/15/20 夜= Boss 占位）；
#       敌人死亡 → 经 PickupSystem 掉经验珠 + 潮币。
# 红线：运行时禁止 instantiate（走 EnemyPool 对象池）；随机走 RNG；难度走 §8.2（Boss 除外）
# 架构：World 子节点；setup 注入 EnemyPool/Player/PickupSystem（也可从父节点自动解析）
# ============================================================================
class_name EnemySpawner
extends Node2D

## 同屏敌人上限（原型验收 2.2.4：峰值 100）
const MAX_ENEMIES: int = 100

## 已实现的 5 种行为（spawn_night ≤5 的敌人）；其余敌人行为占位到 MVP
const IMPLEMENTED_BEHAVIORS: Array[String] = [
	"charge_linear",
	"slow_melee_armor_break",
	"ranged_barrage",
	"burrow_ambush",
	"self_destruct",
]

# 夜晚时长常量（镜像 SKILL.md §5.1，供密度曲线分段；与 DayNightStateMachine 保持一致）
const NIGHT_DURATION_NORMAL: float = 45.0
const NIGHT_DURATION_ELITE: float = 60.0
const NIGHT_DURATION_CALAMITY: float = 90.0
const NIGHT_DURATION_FINAL: float = 120.0

# 注入引用
var enemy_pool: ObjectPool
var target: Node2D
var pickup_system: PickupSystem

# 刷怪状态
var _night: int = 1
var _spawning: bool = false
var _spawn_timer: float = 0.0
var _remaining: int = 0
var _elapsed: float = 0.0
var _night_duration: float = NIGHT_DURATION_NORMAL

# 当前夜可刷敌人定义缓存
var _eligible: Array[Dictionary] = []


func _ready() -> void:
	# 未显式 setup 时，从父节点（Main/World）自动解析引用
	if enemy_pool == null or target == null or pickup_system == null:
		var parent: Node = get_parent()
		if parent != null:
			if enemy_pool == null:
				enemy_pool = parent.get_node_or_null("EnemyPool") as ObjectPool
			if target == null:
				target = parent.get_node_or_null("Player") as Node2D
			if pickup_system == null:
				pickup_system = parent.get_node_or_null("PickupSystem") as PickupSystem
	if enemy_pool == null:
		push_warning("[EnemySpawner] 未找到 EnemyPool，刷怪将不可用")


## 注入引用（World 在 _ready 中调用）
func setup(pool: ObjectPool, player: Node2D, pickups: PickupSystem) -> void:
	enemy_pool = pool
	target = player
	pickup_system = pickups


## 开始第 night 夜刷怪（由 World 在 NIGHT 阶段调用）
func start_night(night: int) -> void:
	if enemy_pool == null or target == null:
		push_warning("[EnemySpawner] 引用未就绪，无法刷怪")
		return
	_night = night
	_night_duration = _get_night_duration(night)
	_elapsed = 0.0
	_spawn_timer = 0.0
	_remaining = _compute_count(night)
	_eligible = _build_eligible(night)
	_spawning = true
	print("[EnemySpawner] 第 %d 夜刷怪开始 (count=%d, 候选=%d)" % [night, _remaining, _eligible.size()])
	# 精英 / Boss 占位（开局立即登场）
	if night == 5:
		_spawn_elite(night)
	elif night in [10, 15, 20]:
		_spawn_boss(night)


## 停止刷怪（夜晚结束 / 进入昼）
func stop() -> void:
	_spawning = false


## 清除全部活跃敌人（进入昼 / 新局 / 游戏结束）
func clear_all() -> void:
	_spawning = false
	if enemy_pool != null:
		enemy_pool.release_all()


func _process(delta: float) -> void:
	if not _spawning or enemy_pool == null or target == null:
		return
	_elapsed += delta
	if _remaining <= 0:
		_spawning = false
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_one()
		_remaining -= 1
		if _remaining <= 0:
			_spawning = false
		else:
			_spawn_timer = _current_interval(_elapsed)


# ============================================================================
# 刷怪实现
# ============================================================================

func _spawn_one() -> void:
	if enemy_pool.active_count() >= MAX_ENEMIES:
		return
	var def: Dictionary = _pick_enemy_def()
	if def.is_empty():
		return
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	if e == null:
		return
	e.configure(def, _night)
	var angle: float = RNG.randf_range(0.0, TAU)
	var dist: float = 180.0 + RNG.randf_range(0.0, 220.0)
	var pos: Vector2 = target.global_position + Vector2(cos(angle), sin(angle)) * dist
	e.spawn_at(pos, target)
	_connect_died(e)


## 精英夜：巨钳王 = 强化铁壳蟹（base_health×3 / base_exp×3 / contact_damage×2）
## 注：该 3× 在 configure() 后仍会叠加 §8.2 夜晚缩放，故实战为「正常缩放后约 3×」
func _spawn_elite(night: int) -> void:
	var base: Dictionary = ConfigLoader.get_enemy("iron_crab")
	if base.is_empty():
		return
	var edata: Dictionary = base.duplicate()
	edata["id"] = "giant_claw_king"
	edata["name"] = "巨钳王"
	edata["base_health"] = int(base.get("base_health", 55)) * 3
	edata["base_exp"] = int(base.get("base_exp", 5)) * 3
	edata["base_contact_damage"] = int(base.get("base_contact_damage", 12)) * 2
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	if e == null:
		return
	e.configure(edata, night)
	var pos: Vector2 = target.global_position + Vector2(0.0, -200.0)
	e.spawn_at(pos, target)
	_connect_died(e)
	print("[EnemySpawner] 精英登场：巨钳王")


## 天灾夜：Boss 占位（configure_boss，不走 §8.2 缩放）
func _spawn_boss(night: int) -> void:
	var b: Dictionary = ConfigLoader.get_boss_by_night(night)
	if b.is_empty():
		return
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	if e == null:
		return
	e.configure_boss(b)
	var pos: Vector2 = target.global_position + Vector2(0.0, -220.0)
	e.spawn_at(pos, target)
	_connect_died(e)
	print("[EnemySpawner] 天灾夜 Boss 登场：%s" % b.get("name", "未知"))


## 连接敌人死亡信号（幂等：同一实例仅连一次，避免 release 复用后重复连接）
func _connect_died(e: EnemyBase) -> void:
	if not e.enemy_died.is_connected(_on_enemy_died):
		e.enemy_died.connect(_on_enemy_died)


## 敌人死亡：掉经验珠 + 潮币
func _on_enemy_died(enemy: EnemyBase) -> void:
	if pickup_system == null or not is_instance_valid(enemy):
		return
	var pos: Vector2 = enemy.global_position
	pickup_system.spawn_exp_gem(pos, enemy.base_exp)
	pickup_system.spawn_coin(pos, enemy.coin_drop)


# ============================================================================
# 数据 / 公式
# ============================================================================

## 本夜总刷怪数（来自 metadata.spawn 的 base_count / per_night，封顶 MAX_ENEMIES）
func _compute_count(night: int) -> int:
	var meta: Dictionary = ConfigLoader.get_enemy_spawn()
	var base_count: int = int(meta.get("base_count", 10))
	var per_night: int = int(meta.get("per_night", 3))
	var count: int = base_count + per_night * (night - 1)
	return mini(count, MAX_ENEMIES)


## 当前夜密度曲线间隔（秒）：前 sparse 秒稀疏 → 0.6×时长密集 → 末段加压
func _current_interval(elapsed: float) -> float:
	var meta: Dictionary = ConfigLoader.get_enemy_spawn()
	var sparse: float = float(meta.get("sparse_seconds", 12.0))
	var interval_start: float = float(meta.get("interval_start", 2.0))
	var interval_dense: float = float(meta.get("interval_dense", 0.8))
	var interval_pressure: float = float(meta.get("interval_pressure", 0.4))
	if elapsed < sparse:
		return interval_start
	if elapsed < _night_duration * 0.6:
		return interval_dense
	return interval_pressure


## 构建本夜可刷敌人列表（spawn_night ≤ night 且行为已实现）
func _build_eligible(night: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ConfigLoader.get_all_enemy_ids():
		var def: Dictionary = ConfigLoader.get_enemy(id)
		if def.is_empty():
			continue
		if int(def.get("spawn_night", 99)) > night:
			continue
		var bt: String = def.get("behavior_type", "")
		if not (bt in IMPLEMENTED_BEHAVIORS):
			continue
		out.append(def)
	if out.is_empty():
		# 兜底：至少小水鬼
		var fallback: Dictionary = ConfigLoader.get_enemy("small_goblin")
		if not fallback.is_empty():
			out.append(fallback)
	return out


## 从候选池均匀随机选一种（确定性 RNG）
func _pick_enemy_def() -> Dictionary:
	if _eligible.is_empty():
		return {}
	var idx: int = RNG.randi_range(0, _eligible.size() - 1)
	return _eligible[idx]


## 夜晚时长（镜像 DayNightStateMachine §5.1）
func _get_night_duration(night: int) -> float:
	if night == 20:
		return NIGHT_DURATION_FINAL
	if night == 10 or night == 15:
		return NIGHT_DURATION_CALAMITY
	if night == 5:
		return NIGHT_DURATION_ELITE
	return NIGHT_DURATION_NORMAL
