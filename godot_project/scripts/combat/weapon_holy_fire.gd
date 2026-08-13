# ============================================================================
# WeaponHolyFire — 灯塔圣火（范围灼烧，behavior_type=area_burn）
# 行为：在最近敌人位置爆出范围伤害，对范围内所有敌人造成 leveled 伤害。
# 数据：config/weapons.json holy_fire（level_1_trait: 范围 +80%）
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
	var dmg: int = get_leveled_damage()
	# 范围随等级：基础 80，每级 +80%→ 简化 +15%/级（原型占位，W12 校准）
	var radius: float = 80.0 * (1.0 + 0.15 * float(level - 1))
	var targets: Array = hash.query_radius(origin, radius)
	for e in targets:
		if e is EnemyBase:
			(e as EnemyBase).take_damage(dmg)
