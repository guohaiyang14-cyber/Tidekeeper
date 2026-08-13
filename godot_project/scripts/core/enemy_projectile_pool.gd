# ============================================================================
# EnemyProjectilePool — 敌方弹道对象池（W2-W3）
# ============================================================================
class_name EnemyProjectilePool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 200
	super._ready()
