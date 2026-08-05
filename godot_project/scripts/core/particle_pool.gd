# ============================================================================
# ParticlePool — 粒子/特效对象池（全局上限约 200，SKILL.md §2.5）
# ============================================================================
class_name ParticlePool
extends ObjectPool


func _ready() -> void:
	if pool_size <= 0:
		pool_size = 200
	super._ready()
