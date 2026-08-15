# ============================================================================
# WeaponAnchorHammer — 锚锤（爆发近战，behavior_type=melee_burst）
# 行为：朝最近敌人方向做近战范围爆发，对扇形/圆内敌人造成高额 leveled 伤害。
# 数据：config/weapons.json anchor_hammer.behavior
# ============================================================================
class_name WeaponAnchorHammer
extends WeaponBase


func fire(target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var forward: Vector2 = (target.global_position - origin).normalized()
	var dmg: int = get_leveled_damage()
	var base_r: float = get_behavior_float("base_radius", 70.0)
	var l1_mult: float = get_behavior_float("l1_radius_mult", 1.6)
	var per_lv: float = get_behavior_float("radius_per_level", 0.15)
	var radius: float = base_r * l1_mult * (1.0 + per_lv * float(level - 1))
	var targets: Array = hash.query_radius(origin, radius)
	for e in targets:
		if e is EnemyBase:
			var to_e: Vector2 = (e as EnemyBase).global_position - origin
			# 前方半球（点积 ≥ 0）；身后漏打以区分「爆发近战」与全周环绕
			if forward.dot(to_e) >= 0.0:
				(e as EnemyBase).take_damage(dmg)
