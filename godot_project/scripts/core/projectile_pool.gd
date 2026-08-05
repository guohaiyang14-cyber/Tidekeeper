# ============================================================================
# ProjectilePool — 投射物对象池
# ============================================================================
class_name ProjectilePool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 200
	super._ready()
