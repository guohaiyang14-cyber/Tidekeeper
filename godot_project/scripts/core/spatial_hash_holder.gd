# ============================================================================
# SpatialHashHolder — 场景树节点，持有 SpatialHash 实例
# 职责：把 RefCounted 的 SpatialHash 挂到 World 子树，供刷怪/投射物查询
# ============================================================================
class_name SpatialHashHolder
extends Node

## 网格尺寸（敌人半径 × 4 ≈ 80，SKILL.md §2.4）
@export var cell_size: float = 80.0

var _hash: SpatialHash


func _ready() -> void:
	_hash = SpatialHash.new(cell_size)
	print("[SpatialHashHolder] 就绪 cell_size=%.0f" % cell_size)


## 获取空间哈希实例
func get_hash() -> SpatialHash:
	return _hash


## 清空（场景重置 / 新局）
func clear() -> void:
	if _hash:
		_hash.clear()
