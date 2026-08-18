# ============================================================================
# WeaponStormCloud — 雷暴云（范围落雷，behavior_type=area_lightning）
# 行为：在最近敌人位置落下高伤 AoE（attack_rate 约 0.33 → 3 秒一击）。
# 数据：config/weapons.json storm_cloud.behavior
# ============================================================================
class_name WeaponStormCloud
extends WeaponBase


func fire(target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var base_r: float = get_behavior_float("base_radius", 90.0)
	var per_lv: float = get_behavior_float("radius_per_level", 0.12)
	var radius: float = scale_area_radius(base_r * (1.0 + per_lv * float(level - 1)))
	# 弹道+1（星象师 / 潮汐之径）：在最近 1+extra 个敌人位置各落一次 AoE
	var strike_points: int = 1 + MetaSystem.get_extra_projectiles()
	var ranked: Array[EnemyBase] = query_nearest_enemies(hash, get_owner_pos.call(), 4000.0, strike_points)
	if ranked.is_empty():
		_strike_at(hash, target.global_position, radius)
		return
	for e in ranked:
		_strike_at(hash, e.global_position, radius)


## 在 at 位置半径 radius 内所有敌人各造成一次命中伤害（暴击独立掷骰）
func _strike_at(hash: SpatialHash, at: Vector2, radius: float) -> void:
	var pts: Array = hash.query_radius(at, radius)
	for p in pts:
		if p is EnemyBase:
			(p as EnemyBase).take_damage(roll_hit_damage())
