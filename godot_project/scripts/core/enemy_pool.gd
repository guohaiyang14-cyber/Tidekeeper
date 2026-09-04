# ============================================================================
# EnemyPool — 敌人对象池（W1 子类骨架，W5+ 挂真实敌人场景）
# ============================================================================
class_name EnemyPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 100
	# 同屏上限 + 分裂/召唤预留：父体死亡时尚未 release，分裂需额外可用实例
	var max_enemies: int = int(ConfigLoader.get_difficulty_config().get("max_enemies", 350))
	var headroom: int = int(ConfigLoader.get_difficulty_config().get("enemy_pool_headroom", 32))
	pool_size = maxi(pool_size, max_enemies + maxi(headroom, 0))
	super._ready()
