# ============================================================================
# PickupPool — 经验珠对象池（潮币走 CoinPool）
# 容量：下限对齐 difficulty.max_enemies；耗尽时软扩容至 2×max_enemies（珠可堆积超过同屏敌）
# ============================================================================
class_name PickupPool
extends ObjectPool

## 耗尽时单次扩容块
const _EXPAND_CHUNK: int = 64


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 150
	# 击杀掉珠后敌可补刷，场上未拾珠可逼近/超过同屏上限；下限对齐 max_enemies
	pool_size = maxi(pool_size, _max_enemies_cap())
	super._ready()


func acquire() -> Node:
	if available_count() <= 0:
		_try_expand_for_gems()
	return super.acquire()


func _max_enemies_cap() -> int:
	return int(ConfigLoader.get_difficulty_config().get("max_enemies", 350))


## 软扩容：硬顶 2×max_enemies，避免风筝拖尾时静默丢珠
func _try_expand_for_gems() -> void:
	var hard_cap: int = maxi(_max_enemies_cap() * 2, pool_size)
	if pool_size >= hard_cap:
		return
	expand(mini(_EXPAND_CHUNK, hard_cap - pool_size))
