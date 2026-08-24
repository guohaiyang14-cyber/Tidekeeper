# ============================================================================
# EnemyPool — 敌人对象池（W1 子类骨架，W5+ 挂真实敌人场景）
# ============================================================================
class_name EnemyPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 100
	# W19：容量下限对齐同屏敌人上限（difficulty.json max_enemies），保证 350 敌可常驻
	pool_size = maxi(pool_size, int(ConfigLoader.get_difficulty_config().get("max_enemies", 350)))
	super._ready()
