# ============================================================================
# PickupSystem — 拾取系统（W2）
# 职责：管理经验珠的生成、吸附检测、飞行、收集
# 数据源：config/pickups.json + Player.get_pickup_radius()
# 红线：走对象池（PickupPool）；不用 Physics2D，纯距离判定
# 架构：World 子节点，持有 PickupPool 引用 + Player 引用
# W2 范围：经验珠；潮币（靠近拾取）为 W4 商店系统
# ============================================================================
class_name PickupSystem
extends Node2D

## 经验珠收集信号（UI 可连接显示经验变化）
signal exp_collected(amount: int)

## 对象池引用（主场景 @onready；测试可用 bind()）
@onready var _pool: ObjectPool = get_node_or_null("../PickupPool") as ObjectPool

## 玩家引用（主场景 @onready；测试可用 bind()）
@onready var _player: Player = get_node_or_null("../Player") as Player

## 活跃经验珠列表（用于每帧更新）
var _active_gems: Array[ExpGem] = []

## 自 config/pickups.json 加载的运行时参数
var _collect_radius: float = 10.0
var _attract_speed: float = 120.0
var _scatter_range: float = 12.0
var _quality_weights: Array[float] = [65.0, 25.0, 8.0, 2.0]
var _quality_exp_mult: Array[float] = [1.0, 2.0, 5.0, 10.0]


func _ready() -> void:
	_load_config()
	print("[PickupSystem] 就绪 (pool=%s player=%s)" % [
		_pool.name if _pool else "null",
		_player.name if _player else "null",
	])


## 测试 / 手动注入引用（绕过场景路径）
func bind(pool: ObjectPool, player: Player) -> void:
	_pool = pool
	_player = player


func _process(delta: float) -> void:
	if _player == null or _active_gems.is_empty():
		return

	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = _player.get_pickup_radius()

	# 倒序遍历以便安全删除已收集的珠子
	var i: int = _active_gems.size() - 1
	while i >= 0:
		var gem: ExpGem = _active_gems[i]
		if not is_instance_valid(gem):
			_active_gems.remove_at(i)
			i -= 1
			continue

		var dist: float = gem.global_position.distance_to(player_pos)

		if gem.is_attracted():
			# 已吸附：飞向玩家 + 检查收集
			gem.update_attract(player_pos, delta)
			var new_dist: float = gem.global_position.distance_to(player_pos)
			if new_dist <= _collect_radius:
				_collect(gem, i)
		else:
			# 未吸附：检查是否进入拾取半径
			if dist <= pickup_radius:
				gem.start_attract(player_pos, _attract_speed)

		i -= 1


# ============================================================================
# 公共接口
# ============================================================================

## 生成经验珠（敌人死亡时调用；品质随机决定经验倍率）
func spawn_exp_gem(pos: Vector2, base_exp: int) -> ExpGem:
	var quality: ExpGem.Quality = _roll_quality()
	var final_exp: int = maxi(1, roundi(float(base_exp) * _quality_exp_mult[quality]))
	return _spawn_gem(pos, final_exp, quality)


## 批量生成：对整次掉落只滚一次品质，再拆成多颗（总经验 = total_exp × 倍率）
func spawn_exp_gems(pos: Vector2, total_exp: int, gem_count: int = 3) -> void:
	if total_exp <= 0 or gem_count <= 0:
		return
	var quality: ExpGem.Quality = _roll_quality()
	var final_total: int = maxi(1, roundi(float(total_exp) * _quality_exp_mult[quality]))
	var per_gem: int = final_total / gem_count
	var remainder: int = final_total % gem_count
	for i in gem_count:
		var value: int = per_gem + (1 if i < remainder else 0)
		if value <= 0:
			continue
		var offset: Vector2 = Vector2(
			RNG.randf_range(-_scatter_range, _scatter_range),
			RNG.randf_range(-_scatter_range, _scatter_range)
		)
		_spawn_gem(pos + offset, value, quality)


## 清除所有活跃经验珠（场景重置 / 新局）
func clear_all() -> void:
	if _pool == null:
		_active_gems.clear()
		return
	for gem in _active_gems:
		if is_instance_valid(gem):
			_pool.release(gem)
	_active_gems.clear()


## 当前活跃经验珠数（调试 / 性能监控用）
func active_gem_count() -> int:
	return _active_gems.size()


## 当前活跃珠经验总和（测试 / 调试用）
func active_exp_total() -> int:
	var total: int = 0
	for gem in _active_gems:
		if is_instance_valid(gem):
			total += gem.exp_value
	return total


# ============================================================================
# 内部方法
# ============================================================================

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_exp_gem_config()
	if cfg.is_empty():
		push_warning("[PickupSystem] pickups.json.exp_gem 缺失，使用内置回退值")
		return
	_collect_radius = float(cfg.get("collect_radius", _collect_radius))
	_attract_speed = float(cfg.get("attract_speed", _attract_speed))
	_scatter_range = float(cfg.get("scatter_range", _scatter_range))
	_quality_weights = _to_float_array(cfg.get("quality_weights", _quality_weights), _quality_weights)
	_quality_exp_mult = _to_float_array(cfg.get("quality_exp_mult", _quality_exp_mult), _quality_exp_mult)


func _to_float_array(raw: Variant, fallback: Array[float]) -> Array[float]:
	if raw is Array:
		var out: Array[float] = []
		for v in raw as Array:
			out.append(float(v))
		if not out.is_empty():
			return out
	return fallback


func _spawn_gem(pos: Vector2, exp_value: int, quality: ExpGem.Quality) -> ExpGem:
	if _pool == null:
		push_error("[PickupSystem] PickupPool 未就绪")
		return null
	var gem: ExpGem = _pool.acquire() as ExpGem
	if gem == null:
		return null
	gem.global_position = pos
	gem.exp_value = exp_value
	gem.set_quality(quality)
	_active_gems.append(gem)
	return gem


## 随机滚动品质（确定性 RNG，权重见 pickups.json）
func _roll_quality() -> ExpGem.Quality:
	var roll: float = RNG.randf_range(0.0, 100.0)
	var cumulative: float = 0.0
	for i in _quality_weights.size():
		cumulative += _quality_weights[i]
		if roll <= cumulative:
			return i as ExpGem.Quality
	return ExpGem.Quality.COMMON


## 收集经验珠
func _collect(gem: ExpGem, index: int) -> void:
	var value: int = gem.exp_value
	GameState.add_exp(value)
	exp_collected.emit(value)
	_active_gems.remove_at(index)
	_pool.release(gem)
