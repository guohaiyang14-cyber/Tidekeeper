# ============================================================================
# WeaponAnchorChain — 锚链（环绕型，behavior_type=orbit_tick）
# 行为：以玩家为中心脉冲结算环绕伤害，对玩家周围敌人造成 leveled 伤害。
# 数据：config/weapons.json anchor_chain（level_1_trait: 3 圈环绕、中等伤害）
# 原型：以 attack_rate 脉冲结算玩家周围范围伤害（视觉环绕链为 MVP 演进）
# ============================================================================
class_name WeaponAnchorChain
extends WeaponBase


func fire(_target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var dmg: int = get_leveled_damage()
	# 环绕半径随等级：基础 60，每级 +15
	var radius: float = 60.0 + 15.0 * float(level - 1)
	var targets: Array = hash.query_radius(origin, radius)
	for e in targets:
		if e is EnemyBase:
			(e as EnemyBase).take_damage(dmg)
