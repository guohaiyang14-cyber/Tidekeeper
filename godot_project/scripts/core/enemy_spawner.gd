# ============================================================================
# EnemySpawner — 潮汐刷怪（W2-W3 + W8 进阶敌人/词缀）
# 职责：按 config/enemies.json 的 spawn_night 解锁 9 种行为敌人；
#       依据 metadata.spawn 密度曲线（前 12s 稀疏 → 中段密集 → 末段加压）刷怪；
#       精英夜（第 5 夜=巨钳王 + 2~3 词缀）/ 天灾夜（第 10/15/20 夜= Boss 占位 + 全场 +1 词缀）；
#       敌人死亡 → 经 PickupSystem 掉经验珠 + 潮币。
# 红线：运行时禁止 instantiate（走 EnemyPool 对象池）；随机走 RNG；难度走 §8.2（Boss 除外）
# 架构：World 子节点；setup 注入 EnemyPool/Player/PickupSystem（也可从父节点自动解析）
# ============================================================================
class_name EnemySpawner
extends Node2D

## 同屏敌人上限（原型验收 2.2.4：峰值 100）
const MAX_ENEMIES: int = 100

const _AFFIX_SYSTEM = preload("res://scripts/combat/affix_system.gd")
const _BOSS_BRAIN = preload("res://scripts/combat/boss_brain.gd")

## 已实现的 9 种行为（W7 基础 5 + W8 进阶 4）
const IMPLEMENTED_BEHAVIORS: Array[String] = [
	"charge_linear",
	"slow_melee_armor_break",
	"ranged_barrage",
	"burrow_ambush",
	"self_destruct",
	"flying_swarm",
	"summoner",
	"charge_damage_reduction",
	"damage_share",
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
## start_night 缓存的 metadata.spawn（避免每帧/每次刷怪反复查表）
var _spawn_meta: Dictionary = {}

# 当前夜可刷敌人定义缓存
var _eligible: Array[Dictionary] = []
## 天灾夜全场统一词缀（§5.5 第 10 夜 +1；当夜抽取一次后复用）
var _night_bonus_affixes: Array[String] = []
## 第 15 夜潮汐夹击：两侧刷怪
var _pincer_mode: bool = false
var _pincer_side: int = 1
## 灯塔位置（执政官潮汐波安全区）
var lighthouse_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("enemy_spawner")
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
	if player != null:
		lighthouse_position = player.global_position


## 开始第 night 夜刷怪（由 World 在 NIGHT 阶段调用）
func start_night(night: int) -> void:
	if enemy_pool == null or target == null:
		push_warning("[EnemySpawner] 引用未就绪，无法刷怪")
		return
	_night = night
	_night_duration = _get_night_duration(night)
	_spawn_meta = ConfigLoader.get_enemy_spawn()
	_elapsed = 0.0
	_spawn_timer = 0.0
	_remaining = _compute_count(night)
	_eligible = _build_eligible(night)
	_night_bonus_affixes = _pick_night_bonus_affixes(night)
	_pincer_mode = _is_pincer_night(night)
	_pincer_side = 1
	_spawning = true
	print("[EnemySpawner] 第 %d 夜刷怪开始 (count=%d, 候选=%d, 夜词缀=%s, 夹击=%s)" % [
		night, _remaining, _eligible.size(), ",".join(_night_bonus_affixes), str(_pincer_mode),
	])
	# 精英 / Boss（开局立即登场；同样受 MAX_ENEMIES 约束）
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


## 本夜剩余刷怪配额（测试 / 调试）
func get_remaining() -> int:
	return _remaining


func _process(delta: float) -> void:
	if not _spawning or enemy_pool == null or target == null:
		return
	_elapsed += delta
	if _remaining <= 0:
		_spawning = false
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		if _spawn_one():
			_remaining -= 1
			if _remaining <= 0:
				_spawning = false
			else:
				_spawn_timer = _current_interval(_elapsed)
		else:
			# 达上限 / 池耗尽 / 无候选：不扣配额，短退避后重试（避免每帧空转）
			_spawn_timer = float(_spawn_meta.get("retry_delay", 0.1))


# ============================================================================
# 刷怪实现
# ============================================================================

## 从池中刷一只敌人并施加词缀。
## skip_night_affix：召唤物/分裂体不吃天灾全场词缀。
## allow_over_cap：分裂时父体尚未 release，允许短暂超过 MAX_ENEMIES。
func spawn_enemy(def: Dictionary, pos: Vector2, extra_affixes: Array[String] = [], skip_night_affix: bool = false, allow_over_cap: bool = false) -> EnemyBase:
	if target == null or enemy_pool == null:
		return null
	if enemy_pool.available_count() <= 0:
		return null
	if not allow_over_cap and enemy_pool.active_count() >= MAX_ENEMIES:
		return null
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	if e == null:
		return null
	e.configure(def, _night)
	e.lighthouse_position = lighthouse_position
	e.spawn_at(pos, target)
	_connect_died(e)
	var ids: Array[String] = []
	if not skip_night_affix:
		ids.append_array(_night_bonus_affixes)
	for a in extra_affixes:
		if a not in ids:
			ids.append(a)
	if not ids.is_empty():
		e.apply_affixes(ids)
	return e


## 成功刷出一只返回 true（失败不扣 _remaining）
func _spawn_one() -> bool:
	var def: Dictionary = _pick_enemy_def()
	if def.is_empty():
		return false
	var pos: Vector2
	if _pincer_mode:
		pos = _pincer_spawn_pos()
	else:
		var ring_min: float = float(_spawn_meta.get("ring_min", 180.0))
		var ring_extra: float = float(_spawn_meta.get("ring_extra", 220.0))
		var angle: float = RNG.randf_range(0.0, TAU)
		var dist: float = ring_min + RNG.randf_range(0.0, ring_extra)
		pos = target.global_position + Vector2(cos(angle), sin(angle)) * dist
	return spawn_enemy(def, pos) != null


func _pincer_spawn_pos() -> Vector2:
	var calamity: Dictionary = ConfigLoader.get_boss_calamity()
	var ox: float = float(calamity.get("pincer_offset_x", 220.0))
	var jy: float = float(calamity.get("pincer_offset_y_jitter", 80.0))
	var side: int = _pincer_side
	_pincer_side = -_pincer_side
	return target.global_position + Vector2(float(side) * ox, RNG.randf_range(-jy, jy))


func _is_pincer_night(night: int) -> bool:
	var calamity: Dictionary = ConfigLoader.get_boss_calamity()
	var nights: Variant = calamity.get("pincer_nights", [15])
	if nights is Array:
		for v in nights:
			if int(v) == night:
				return true
	return false


## 同屏未达上限且池仍有可用实例
func _can_spawn_more() -> bool:
	if enemy_pool == null:
		return false
	if enemy_pool.active_count() >= MAX_ENEMIES:
		return false
	return enemy_pool.available_count() > 0


## 精英夜：巨钳王 = 强化铁壳蟹（倍率见 metadata.elite；叠 §8.2 后约为表内倍率）
func _spawn_elite(night: int) -> void:
	if not _can_spawn_more():
		push_warning("[EnemySpawner] 同屏已满，跳过精英登场")
		return
	var elite: Dictionary = ConfigLoader.get_enemy_elite()
	var base_id: String = String(elite.get("base_enemy_id", "iron_crab"))
	var base: Dictionary = ConfigLoader.get_enemy(base_id)
	if base.is_empty():
		return
	var hp_m: int = int(elite.get("health_mult", 3))
	var exp_m: int = int(elite.get("exp_mult", 3))
	var dmg_m: int = int(elite.get("contact_damage_mult", 2))
	var edata: Dictionary = base.duplicate()
	edata["id"] = String(elite.get("id", "giant_claw_king"))
	edata["prototype_id"] = base_id
	edata["name"] = String(elite.get("name", "巨钳王"))
	edata["base_health"] = int(base.get("base_health", 55)) * hp_m
	edata["base_exp"] = int(base.get("base_exp", 5)) * exp_m
	edata["base_contact_damage"] = int(base.get("base_contact_damage", 12)) * dmg_m
	var offset_y: float = float(_spawn_meta.get("elite_offset_y", -200.0))
	var pos: Vector2 = target.global_position + Vector2(0.0, offset_y)
	var rules: Dictionary = ConfigLoader.get_affix_rules()
	var amin: int = int(rules.get("elite_affix_min", 2))
	var amax: int = int(rules.get("elite_affix_max", 3))
	if amax < amin:
		amax = amin
	var extra: Array[String] = AffixSystem.pick(RNG.randi_range(amin, amax))
	var e: EnemyBase = spawn_enemy(edata, pos, extra, false)
	if e == null:
		return
	print("[EnemySpawner] 精英登场：%s 词缀=%s" % [edata.get("name", "精英"), ",".join(e.affix_ids)])


## 天灾夜：Boss（configure_boss + BossBrain）
func _spawn_boss(night: int) -> void:
	if not _can_spawn_more():
		push_warning("[EnemySpawner] 同屏已满，跳过 Boss 登场")
		return
	var b: Dictionary = ConfigLoader.get_boss_by_night(night)
	if b.is_empty():
		return
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	if e == null:
		return
	e.configure_boss(b)
	e.lighthouse_position = lighthouse_position
	var offset_y: float = float(_spawn_meta.get("boss_offset_y", -220.0))
	var pos: Vector2 = target.global_position + Vector2(0.0, offset_y)
	e.spawn_at(pos, target)
	_connect_died(e)
	print("[EnemySpawner] 天灾夜 Boss 登场：%s (%s)" % [b.get("name", "未知"), b.get("behavior_type", "")])


## 连接敌人死亡信号（幂等：同一实例仅连一次，避免 release 复用后重复连接）
func _connect_died(e: EnemyBase) -> void:
	if not e.enemy_died.is_connected(_on_enemy_died):
		e.enemy_died.connect(_on_enemy_died)


## 敌人死亡：掉经验珠 + 潮币；第 20 夜 Boss 击杀通关
func _on_enemy_died(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy):
		return
	var pos: Vector2 = enemy.global_position
	var was_final_boss: bool = enemy.is_boss and GameState.current_night >= 20
	if pickup_system != null:
		pickup_system.spawn_exp_gem(pos, enemy.base_exp)
		pickup_system.spawn_coin(pos, enemy.coin_drop)
	if was_final_boss:
		# 立刻锁通关（挡同帧接触判负）；信号/清场延后，避免死亡栈内嵌套切阶段
		stop()
		GameState.arm_game_win()
		call_deferred("_deferred_final_win")


func _deferred_final_win() -> void:
	GameState.trigger_game_win()


func is_pincer_mode() -> bool:
	return _pincer_mode


# ============================================================================
# 数据 / 公式
# ============================================================================

## 本夜总刷怪数（来自 metadata.spawn 的 base_count / per_night，封顶 MAX_ENEMIES）
func _compute_count(night: int) -> int:
	var base_count: int = int(_spawn_meta.get("base_count", 10))
	var per_night: int = int(_spawn_meta.get("per_night", 3))
	var count: int = base_count + per_night * (night - 1)
	return mini(count, MAX_ENEMIES)


## 当前夜密度曲线间隔（秒）：前 sparse 秒稀疏 → 0.6×时长密集 → 末段加压
func _current_interval(elapsed: float) -> float:
	var sparse: float = float(_spawn_meta.get("sparse_seconds", 12.0))
	var interval_start: float = float(_spawn_meta.get("interval_start", 2.0))
	var interval_dense: float = float(_spawn_meta.get("interval_dense", 0.8))
	var interval_pressure: float = float(_spawn_meta.get("interval_pressure", 0.4))
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


## 天灾夜全场统一词缀（当夜抽取一次）；教学夜 / 非天灾返回空
func _pick_night_bonus_affixes(night: int) -> Array[String]:
	var rules: Dictionary = ConfigLoader.get_affix_rules()
	var teaching: int = int(rules.get("teaching_nights_no_affix", 4))
	if night <= teaching:
		return []
	if not _is_calamity_night(night, rules):
		return []
	var n: int = int(rules.get("calamity_bonus_affixes", 1))
	return AffixSystem.pick(n)


func _is_calamity_night(night: int, rules: Dictionary) -> bool:
	var calamity: Variant = rules.get("calamity_nights", [10, 15, 20])
	if calamity is Array:
		for v in calamity:
			if int(v) == night:
				return true
	return false


func get_night_bonus_affixes() -> Array[String]:
	return _night_bonus_affixes


## 夜晚时长（镜像 DayNightStateMachine §5.1）
func _get_night_duration(night: int) -> float:
	if night == 20:
		return NIGHT_DURATION_FINAL
	if night == 10 or night == 15:
		return NIGHT_DURATION_CALAMITY
	if night == 5:
		return NIGHT_DURATION_ELITE
	return NIGHT_DURATION_NORMAL
