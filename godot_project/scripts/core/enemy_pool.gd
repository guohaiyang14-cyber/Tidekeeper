# ============================================================================
# EnemyPool — 敌人对象池（W1 子类骨架，W5+ 挂真实敌人场景）
# ============================================================================
class_name EnemyPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 100
	super._ready()
