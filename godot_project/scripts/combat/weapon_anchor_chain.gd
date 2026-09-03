# ============================================================================
# WeaponAnchorChain — 锚链（环绕型，behavior_type=orbit_tick）
# 行为：以玩家为中心脉冲结算环绕伤害，对玩家周围敌人造成 leveled 伤害。
# 数据：config/weapons.json anchor_chain.behavior
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
	var base_r: float = get_behavior_float("base_radius", 60.0)
	var per_lv: float = get_behavior_float("radius_per_level", 15.0)
	var radius: float = scale_area_radius(base_r + per_lv * float(level - 1))
	# 弹道+1：额外外圈环绕（环形，不与内圈叠伤）；圈距用表内 radius_per_level
	var rings: int = 1 + MetaSystem.get_extra_projectiles()
	var spacing: float = scale_area_radius(per_lv)
	for i in rings:
		var inner: float = 0.0 if i == 0 else radius + spacing * float(i - 1)
		var outer: float = radius + spacing * float(i)
		_hit_annulus(hash, origin, inner, outer)


## 对距 origin 在 (inner, outer] 的敌人各造成一次命中（inner=0 含圆心）
func _hit_annulus(hash: SpatialHash, origin: Vector2, inner: float, outer: float) -> void:
	var pts: Array = hash.query_radius(origin, outer)
	for p in pts:
		if not (p is EnemyBase):
			continue
		var enemy: EnemyBase = p as EnemyBase
		var d: float = origin.distance_to(enemy.global_position)
		if inner > 0.0 and d <= inner:
			continue
		if d > outer:
			continue
		enemy.take_damage(roll_hit_damage(), true, false, weapon_id)
