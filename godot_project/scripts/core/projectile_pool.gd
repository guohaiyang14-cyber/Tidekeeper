# ============================================================================
# ProjectilePool — 投射物对象池
# ============================================================================
class_name ProjectilePool
extends ObjectPool


func _ready() -> void:
	# 正式局容量由 main.tscn 配置（≥128）；此处不强制抬升，避免压掉测试场景小池
	if pool_size <= 0:
		pool_size = 200
	super._ready()
