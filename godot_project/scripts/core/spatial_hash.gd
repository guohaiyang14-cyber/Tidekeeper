# ============================================================================
# SpatialHash — 自定义空间哈希网格（W1 agent 生成）
# 职责：替代 Godot Physics2D 做碰撞查询（SKILL.md §2.4）
# 红线：不走 Physics2D；网格尺寸 = 敌人半径 × 4（约 80 游戏单位）
# 查询：投射物查所在网格 + 8 邻格；敌人↔敌人仅分离检测
# ============================================================================
class_name SpatialHash
extends RefCounted

## 网格单元尺寸（敌人半径 × 4 ≈ 80）
var _cell_size: float = 80.0

## 哈希表：Vector2i -> Array[Node2D]
var _cells: Dictionary = {}


func _init(cell_size: float = 80.0) -> void:
	_cell_size = cell_size


## 计算位置对应的网格坐标
func _cell_coord(pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / _cell_size)),
		int(floor(pos.y / _cell_size))
	)


## 插入节点到哈希表
func insert(node: Node2D) -> void:
	var coord: Vector2i = _cell_coord(node.global_position)
	if not _cells.has(coord):
		_cells[coord] = []
	_cells[coord].append(node)


## 移除节点（需提供原位置，或遍历查找）
func remove(node: Node2D, last_pos: Vector2) -> void:
	var coord: Vector2i = _cell_coord(last_pos)
	if not _cells.has(coord):
		return
	var arr: Array = _cells[coord]
	var idx: int = arr.find(node)
	if idx >= 0:
		arr.remove_at(idx)
	if arr.is_empty():
		_cells.erase(coord)


## 更新节点位置（先移除旧位置，再插入新位置）
func update(node: Node2D, old_pos: Vector2) -> void:
	remove(node, old_pos)
	insert(node)


## 查询单格内所有节点
func query_cell(pos: Vector2) -> Array:
	var coord: Vector2i = _cell_coord(pos)
	return _cells.get(coord, [])


## 查询位置 + 8 邻格内所有节点（投射物碰撞用）
func query_radius(pos: Vector2, radius: float = 0.0) -> Array:
	var center: Vector2i = _cell_coord(pos)
	var result: Array = []
	# 计算覆盖的网格范围
	var span: int = maxi(1, int(ceil(radius / _cell_size)))
	for x in range(center.x - span, center.x + span + 1):
		for y in range(center.y - span, center.y + span + 1):
			var coord: Vector2i = Vector2i(x, y)
			if _cells.has(coord):
				result.append_array(_cells[coord])
	return result


## 查询矩形区域内所有节点
func query_rect(top_left: Vector2, size: Vector2) -> Array:
	var min_coord: Vector2i = _cell_coord(top_left)
	var max_coord: Vector2i = _cell_coord(top_left + size)
	var result: Array = []
	for x in range(min_coord.x, max_coord.x + 1):
		for y in range(min_coord.y, max_coord.y + 1):
			var coord: Vector2i = Vector2i(x, y)
			if _cells.has(coord):
				result.append_array(_cells[coord])
	return result


## 清空哈希表（场景重置时调用）
func clear() -> void:
	_cells.clear()


## 当前网格数
func cell_count() -> int:
	return _cells.size()


## 当前总节点数
func total_nodes() -> int:
	var count: int = 0
	for arr in _cells.values():
		count += arr.size()
	return count


## 获取网格尺寸
func get_cell_size() -> float:
	return _cell_size


## 遍历所有节点（用于全局更新，如分帧 AI）
func for_each(callback: Callable) -> void:
	for arr in _cells.values():
		for node in arr:
			callback.call(node)
