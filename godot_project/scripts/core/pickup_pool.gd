# ============================================================================
# PickupPool — 拾取物对象池（经验珠 / 潮币）
# ============================================================================
class_name PickupPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 150
	super._ready()
