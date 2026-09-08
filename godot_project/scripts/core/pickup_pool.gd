# ============================================================================
# PickupPool — 经验珠对象池（潮币走 CoinPool）
# 容量：下限对齐 difficulty.max_enemies；耗尽时软扩容至 ObjectPool.pickup_hard_cap()
# ============================================================================
class_name PickupPool
extends ObjectPool

## 耗尽时单次扩容块（AOE 击杀峰值需较快追上）
const _EXPAND_CHUNK: int = 128


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 150
	# 击杀掉珠后敌可补刷，场上未拾珠可逼近/超过同屏上限；下限对齐 max_enemies
	pool_size = maxi(pool_size, difficulty_max_enemies())
	super._ready()


func acquire() -> Node:
	if available_count() <= 0:
		_try_expand_for_gems()
	return super.acquire()


## 软扩容：硬顶见 ObjectPool.PICKUP_HARD_CAP_*
func _try_expand_for_gems() -> void:
	soft_expand_toward(pickup_hard_cap(), _EXPAND_CHUNK)
