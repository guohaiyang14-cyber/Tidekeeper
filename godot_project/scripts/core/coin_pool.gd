# ============================================================================
# CoinPool — 潮币对象池（W4）
# 容量：下限对齐 difficulty.max_enemies；耗尽时软扩容至 4×max_enemies（风筝/AOE 清场未拾可堆很高）
# ============================================================================
class_name CoinPool
extends ObjectPool

## 耗尽时单次扩容块（AOE 击杀峰值需较快追上）
const _EXPAND_CHUNK: int = 128
## 相对 max_enemies 的硬顶倍率（原 2× 在风暴清场 + Bot×4 下不够）
const _HARD_CAP_MULT: int = 4
const _HARD_CAP_FLOOR: int = 1200


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 200
	# 击杀掉币后敌可补刷，场上未拾币可逼近/超过同屏上限；下限对齐 max_enemies
	pool_size = maxi(pool_size, difficulty_max_enemies())
	super._ready()


func acquire() -> Node:
	if available_count() <= 0:
		_try_expand_for_coins()
	return super.acquire()


## 软扩容：硬顶 4×max_enemies（且不少于 1200）
func _try_expand_for_coins() -> void:
	soft_expand_toward(pickup_soft_hard_cap(_HARD_CAP_MULT, _HARD_CAP_FLOOR), _EXPAND_CHUNK)
