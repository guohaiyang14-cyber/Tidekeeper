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

## 潮币池引用（W4 商店闭环）
@onready var _coin_pool: ObjectPool = get_node_or_null("../CoinPool") as ObjectPool

## 玩家引用（主场景 @onready；测试可用 bind()）
@onready var _player: Player = get_node_or_null("../Player") as Player

## 活跃经验珠列表（用于每帧更新）
var _active_gems: Array[ExpGem] = []

## 活跃潮币列表（用于每帧更新）
var _active_coins: Array[Coin] = []

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


## 注入潮币池（测试用）
func bind_coin_pool(pool: ObjectPool) -> void:
	_coin_pool = pool


func _process(delta: float) -> void:
	if _player == null:
		return
	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = _player.get_pickup_radius()

	if not _active_gems.is_empty():
		_process_gems(delta, player_pos, pickup_radius)
	if not _active_coins.is_empty():
		_process_coins(delta, player_pos, pickup_radius)


func _process_gems(delta: float, player_pos: Vector2, pickup_radius: float) -> void:
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


## 生成潮币（敌人死亡时调用；amount 为掉落实 value）
func spawn_coin(pos: Vector2, amount: int) -> Coin:
	if _coin_pool == null or amount <= 0:
		return null
	var coin: Coin = _coin_pool.acquire() as Coin
	if coin == null:
		return null
	coin.global_position = pos
	coin.value = amount
	_active_coins.append(coin)
	return coin


## 潮币每帧更新（吸引 + 收集 → 入账）
func _process_coins(delta: float, player_pos: Vector2, pickup_radius: float) -> void:
	var i: int = _active_coins.size() - 1
	while i >= 0:
		var coin: Coin = _active_coins[i]
		if not is_instance_valid(coin):
			_active_coins.remove_at(i)
			i -= 1
			continue
		var dist: float = coin.global_position.distance_to(player_pos)
		if coin.is_attracted():
			coin.update_attract(player_pos, delta)
			if coin.global_position.distance_to(player_pos) <= _collect_radius:
				GameState.add_tidecoins(coin.value)
				_active_coins.remove_at(i)
				_coin_pool.release(coin)
		else:
			if dist <= pickup_radius:
				coin.start_attract(player_pos, _attract_speed)
		i -= 1


## 当前活跃潮币数（调试用）
func active_coin_count() -> int:
	return _active_coins.size()


## 清除所有活跃经验珠 / 潮币（场景重置 / 新局）
func clear_all() -> void:
	if _pool != null:
		for gem in _active_gems:
			if is_instance_valid(gem):
				_pool.release(gem)
	_active_gems.clear()
	if _coin_pool != null:
		for coin in _active_coins:
			if is_instance_valid(coin):
				_coin_pool.release(coin)
	_active_coins.clear()


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


## 距 from 最近的经验珠世界坐标；无珠或均超出 max_range 时返回 Vector2.ZERO。
## 注意：原点也可能有珠，故「无珠」请用 try_nearest_gem_position，勿把 ZERO 当失败哨兵。
func find_nearest_gem_position(from: Vector2, max_range: float = 2400.0) -> Vector2:
	var out_pos: Array[Vector2] = [Vector2.ZERO]
	if try_nearest_gem_position(from, out_pos, max_range):
		return out_pos[0]
	return Vector2.ZERO


## 查找最近经验珠；找到时写入 out_pos[0] 并返回 true（可区分「原点有珠」与「无珠」）。
func try_nearest_gem_position(from: Vector2, out_pos: Array[Vector2], max_range: float = 2400.0) -> bool:
	var best_dist: float = max_range
	var best_pos: Vector2 = Vector2.ZERO
	var found: bool = false
	for gem in _active_gems:
		if not is_instance_valid(gem):
			continue
		var dist: float = from.distance_to(gem.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = gem.global_position
			found = true
	if not found:
		return false
	if out_pos.is_empty():
		out_pos.append(best_pos)
	else:
		out_pos[0] = best_pos
	return true


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
	# 品质数组长度必须与 Quality 枚举（4）一致，否则 _roll_quality 索引越界
	if _quality_weights.size() != 4 or _quality_exp_mult.size() != 4:
		push_warning("[PickupSystem] quality_weights/exp_mult 长度应为 4，回退默认值")
		_quality_weights = [65.0, 25.0, 8.0, 2.0]
		_quality_exp_mult = [1.0, 2.0, 5.0, 10.0]


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
