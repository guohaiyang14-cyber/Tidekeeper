# ============================================================================
# WeaponHolyFire — 灯塔圣火（范围灼烧，behavior_type=area_burn）
# 行为：在最近敌人位置爆出范围伤害，对范围内所有敌人造成 leveled 伤害。
# 数据：config/weapons.json holy_fire.behavior
# 原型：以 attack_rate 脉冲结算范围伤害（持续灼烧地面为 MVP 演进）
# ============================================================================
class_name WeaponHolyFire
extends WeaponBase


func fire(target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var origin: Vector2 = target.global_position
	var base_r: float = get_behavior_float("base_radius", 80.0)
	var per_lv: float = get_behavior_float("radius_per_level", 0.15)
	var radius: float = scale_area_radius(base_r * (1.0 + per_lv * float(level - 1)))
	var targets: Array = hash.query_radius(origin, radius)
	for e in targets:
		if e is EnemyBase:
			(e as EnemyBase).take_damage(roll_hit_damage())
