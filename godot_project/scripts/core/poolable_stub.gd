# ============================================================================
# PoolableStub — W1 占位可池化节点（无美术；供对象池预分配与单测）
# ============================================================================
extends Node2D

var acquire_count: int = 0
var release_count: int = 0


func _on_acquire() -> void:
	acquire_count += 1


func _on_release() -> void:
	release_count += 1
