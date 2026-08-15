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
	var origin: Vector2 = target.global_position
	var dmg: int = get_leveled_damage()
	var base_r: float = get_behavior_float("base_radius", 90.0)
	var per_lv: float = get_behavior_float("radius_per_level", 0.12)
	var radius: float = base_r * (1.0 + per_lv * float(level - 1))
	var targets: Array = hash.query_radius(origin, radius)
	for e in targets:
		if e is EnemyBase:
			(e as EnemyBase).take_damage(dmg)
