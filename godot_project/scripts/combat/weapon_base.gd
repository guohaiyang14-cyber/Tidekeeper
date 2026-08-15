# ============================================================================
# WeaponBase — 武器基类（W5）
# 职责：持有武器配置与等级；tick 计时到 attack_rate 自动 fire；伤害按等级缩放
# 红线：数值来自 config/（ConfigLoader）；随机走 RNG；运行时禁止 instantiate
# 索敌：get_target（返回 EnemyBase 或 null）、get_owner_pos（返回玩家位置）由 WeaponManager 注入
# fire(target) 为虚函数，具体武器子类实现差异化行为
# ============================================================================
class_name WeaponBase
extends Node

# 显式预加载 EnemyBase，确保 headless 下 class_name 注册（fire 参数类型依赖）
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

var weapon_id: String = ""
var weapon_data: Dictionary = {}
var level: int = 1
var attack_timer: float = 0.0

## 注入：索敌（返回最近 EnemyBase 或 null）/ 玩家位置
var get_target: Callable = Callable()
var get_owner_pos: Callable = Callable()


func configure(data: Dictionary, lv: int) -> void:
	weapon_data = data
	weapon_id = data.get("id", "")
	level = lv
	attack_timer = 0.0


func get_attack_rate() -> float:
	# 召唤型表载 attack_rate 可为 null；改读 pulse_rate（默认 1.0，§4.2）
	var raw: Variant = weapon_data.get("attack_rate", 1.0)
	if raw == null:
		return float(weapon_data.get("pulse_rate", 1.0))
	return float(raw)


func get_base_damage() -> int:
	return int(weapon_data.get("base_damage", 0))


## 等级缩放伤害（§6.3：每级系数来自 weapons.json metadata.damage_per_level）
func get_leveled_damage() -> int:
	var per_lv: float = ConfigLoader.get_damage_per_level()
	return int(round(float(get_base_damage()) * (1.0 + per_lv * float(level - 1))))


## 读取 behavior 子表数值（缺省回退 default）
func get_behavior_float(key: String, default_value: float) -> float:
	var beh: Variant = weapon_data.get("behavior", {})
	if beh is Dictionary:
		return float((beh as Dictionary).get(key, default_value))
	return default_value


func get_behavior_int(key: String, default_value: int) -> int:
	var beh: Variant = weapon_data.get("behavior", {})
	if beh is Dictionary:
		return int((beh as Dictionary).get(key, default_value))
	return default_value


## 从 SpatialHash 取距 origin 最近的至多 count 个敌人（O(n·k)，k=count，避免全量 sort）
func query_nearest_enemies(hash: SpatialHash, origin: Vector2, radius: float, count: int) -> Array[EnemyBase]:
	var result: Array[EnemyBase] = []
	if hash == null or count <= 0:
		return result
	var best_d2: Array[float] = []
	var candidates: Array = hash.query_radius(origin, radius)
	for node in candidates:
		if not (node is EnemyBase):
			continue
		var enemy: EnemyBase = node as EnemyBase
		var d2: float = origin.distance_squared_to(enemy.global_position)
		_insert_nearest(result, best_d2, enemy, d2, count)
	return result


func _insert_nearest(out_enemies: Array[EnemyBase], out_d2: Array[float], enemy: EnemyBase, d2: float, limit: int) -> void:
	if out_enemies.size() < limit:
		var i: int = out_enemies.size()
		out_enemies.append(enemy)
		out_d2.append(d2)
		while i > 0 and out_d2[i] < out_d2[i - 1]:
			var td: float = out_d2[i - 1]
			out_d2[i - 1] = out_d2[i]
			out_d2[i] = td
			var te: EnemyBase = out_enemies[i - 1]
			out_enemies[i - 1] = out_enemies[i]
			out_enemies[i] = te
			i -= 1
		return
	if d2 >= out_d2[limit - 1]:
		return
	out_enemies[limit - 1] = enemy
	out_d2[limit - 1] = d2
	var j: int = limit - 1
	while j > 0 and out_d2[j] < out_d2[j - 1]:
		var td2: float = out_d2[j - 1]
		out_d2[j - 1] = out_d2[j]
		out_d2[j] = td2
		var te2: EnemyBase = out_enemies[j - 1]
		out_enemies[j - 1] = out_enemies[j]
		out_enemies[j] = te2
		j -= 1


## 每帧推进计时；到点自动开火（无目标不发射、不累积）
func tick(delta: float) -> void:
	if get_target.is_null() or get_owner_pos.is_null():
		return
	var rate: float = get_attack_rate()
	if rate <= 0.0:
		return
	var target: EnemyBase = get_target.call()
	if target == null:
		return
	attack_timer += delta
	var interval: float = 1.0 / rate
	while attack_timer >= interval:
		attack_timer -= interval
		fire(target)


## 开火（子类实现；target 为当前索敌到的敌人）
func fire(_target: EnemyBase) -> void:
	pass
