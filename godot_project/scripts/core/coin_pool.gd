# ============================================================================
# CoinPool — 潮币对象池（W4）
# ============================================================================
class_name CoinPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 200
	super._ready()
