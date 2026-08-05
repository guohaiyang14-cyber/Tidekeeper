# ============================================================================
# RNG — 确定性随机数单例（autoload）
# 职责：全局唯一随机源，基于种子确定性（SKILL.md §5.5）
# 红线：所有随机决策走此单例；整数采样优先避免浮点跨平台误差
# 用法：
#   var dmg := RNG.randi_range(10, 20)
#   var pick := RNG.pick(arr)
#   RNG.set_seed(12345)  # 设置种子用于回放
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 RNG 访问

var _generator: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# 默认用时间种子；正式局会用 set_seed 写入存档
	_generator.randomize()
	print("[RNG] 初始种子: %d" % _generator.seed)


## 设置种子（用于每日挑战 / 回放）
func set_seed(seed_value: int) -> void:
	_generator.seed = seed_value
	print("[RNG] 种子已设置: %d" % seed_value)


## 获取当前种子（存档用）
func get_seed() -> int:
	return _generator.seed


## 整数随机 [from, to]（闭区间）
func randi_range(from: int, to: int) -> int:
	return _generator.randi_range(from, to)


## 整数随机 [0, to)
func randi_below(to: int) -> int:
	return _generator.randi() % to


## 浮点随机 [0, 1)
func randf() -> float:
	return _generator.randf()


## 浮点随机 [from, to]
func randf_range(from: float, to: float) -> float:
	return _generator.randf_range(from, to)


## 概率判定（p 为 [0,1] 成功概率）
func chance(p: float) -> bool:
	return _generator.randf() < p


## 从数组随机取一个元素
func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_generator.randi() % arr.size()]


## 从数组随机取 n 个不重复元素
func pick_n(arr: Array, n: int) -> Array:
	if n >= arr.size():
		return arr.duplicate()
	var pool: Array = arr.duplicate()
	var result: Array = []
	for i in n:
		var idx: int = _generator.randi() % pool.size()
		result.append(pool[idx])
		pool.remove_at(idx)
	return result


## 随机打乱数组（返回新数组，不修改原数组）
func shuffle(arr: Array) -> Array:
	var result: Array = arr.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j: int = _generator.randi() % (i + 1)
		var tmp: Variant = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result
