# ============================================================================
# ChestPool — 夜场宝箱对象池（MVP）
# 容量：≥ per_night_max × 常见 chest_drop_mult（2×2=4）；预留余量防事件叠乘
# ============================================================================
class_name ChestPool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 8
	super._ready()
