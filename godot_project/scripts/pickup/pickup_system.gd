# ============================================================================
# PickupSystem — 拾取系统（W2）
# 职责：管理经验珠的生成、吸附检测、飞行、收集
# 数据源：§5.2 拾取（自动吸附）、玩家拾取半径（Player.get_pickup_radius）
# 红线：走对象池（PickupPool）；不用 Physics2D，纯距离判定
# 架构：World 子节点，持有 PickupPool 引用 + Player 引用
# W2 范围：经验珠；潮币（靠近拾取）为 W4 商店系统
# ============================================================================
class_name PickupSystem
extends Node2D

## 经验珠收集信号（UI 可连接显示经验变化）
signal exp_collected(amount: int)

## 玩家进入此距离时，经验珠开始吸附（由 Player.pickup_radius 决定）
## 收集距离（珠子离玩家足够近时回收并加经验）
const COLLECT_RADIUS: float = 10.0

## 基础吸附飞行速度（像素/秒）
const ATTRACT_SPEED_BASE: float = 120.0

## 品质概率权重（索引对应 ExpGem.Quality：普通65% / 精良25% / 稀有8% / 史诗2%）
const QUALITY_WEIGHTS: Array[float] = [65.0, 25.0, 8.0, 2.0]

## 品质经验倍率（普通1× / 精良2× / 稀有5× / 史诗10×）
const QUALITY_EXP_MULT: Array[float] = [1.0, 2.0, 5.0, 10.0]

## 拾取半径倍率（夜明珠被动可扩大，W7 被动系统接入）
var _pickup_radius_mult: float = 1.0

## 对象池引用（World 注入）
@onready var _pool: ObjectPool = get_node_or_null("../PickupPool")

## 玩家引用（World 注入）
@onready var _player: Node2D = get_node_or_null("../Player")

## 活跃经验珠列表（用于每帧更新）
var _active_gems: Array[ExpGem] = []


func _ready() -> void:
	print("[PickupSystem] 就绪 (pool=%s player=%s)" % [
		_pool.name if _pool else "null",
		_player.name if _player else "null",
	])


func _process(delta: float) -> void:
	if _player == null or _active_gems.is_empty():
		return

	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = _get_effective_pickup_radius()

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
			if new_dist <= COLLECT_RADIUS:
				_collect(gem, i)
		else:
			# 未吸附：检查是否进入拾取半径
			if dist <= pickup_radius:
				gem.start_attract(player_pos, ATTRACT_SPEED_BASE)

		i -= 1


# ============================================================================
# 公共接口
# ============================================================================

## 生成经验珠（敌人死亡时调用；品质随机决定，影响经验倍率）
func spawn_exp_gem(pos: Vector2, base_exp: int) -> ExpGem:
	if _pool == null:
		push_error("[PickupSystem] PickupPool 未就绪")
		return null
	var gem: ExpGem = _pool.acquire() as ExpGem
	if gem == null:
		return null
	# 随机品质 + 经验倍率
	var quality: ExpGem.Quality = _roll_quality()
	var final_exp: int = roundi(float(base_exp) * QUALITY_EXP_MULT[quality])
	gem.global_position = pos
	gem.exp_value = final_exp
	gem.set_quality(quality)
	_active_gems.append(gem)
	return gem


## 批量生成经验珠（大额掉落时拆分为多颗，视觉更好）
func spawn_exp_gems(pos: Vector2, total_exp: int, gem_count: int = 3) -> void:
	if total_exp <= 0:
		return
	var per_gem: int = maxi(1, total_exp / gem_count)
	var remainder: int = total_exp - per_gem * gem_count
	for i in gem_count:
		var value: int = per_gem + (remainder if i == 0 else 0)
		# 在掉落点附近散开
		var offset: Vector2 = Vector2(
			RNG.randf_range(-12.0, 12.0),
			RNG.randf_range(-12.0, 12.0)
		)
		spawn_exp_gem(pos + offset, value)


## 设置拾取半径倍率（夜明珠被动调用）
func set_pickup_radius_mult(mult: float) -> void:
	_pickup_radius_mult = mult


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


# ============================================================================
# 内部方法
# ============================================================================

## 随机滚动品质（使用确定性 RNG，权重见 QUALITY_WEIGHTS）
func _roll_quality() -> ExpGem.Quality:
	var roll: float = RNG.randf_range(0.0, 100.0)
	var cumulative: float = 0.0
	for i in QUALITY_WEIGHTS.size():
		cumulative += QUALITY_WEIGHTS[i]
		if roll <= cumulative:
			return i as ExpGem.Quality
	return ExpGem.Quality.COMMON


## 获取有效拾取半径（Player 基础半径 × 被动倍率）
func _get_effective_pickup_radius() -> float:
	var base: float = Player.DEFAULT_PICKUP_RADIUS
	if _player != null and _player.has_method("get_pickup_radius"):
		base = _player.get_pickup_radius()
	return base * _pickup_radius_mult


## 收集经验珠
func _collect(gem: ExpGem, index: int) -> void:
	var value: int = gem.exp_value
	GameState.add_exp(value)
	exp_collected.emit(value)
	_active_gems.remove_at(index)
	_pool.release(gem)
