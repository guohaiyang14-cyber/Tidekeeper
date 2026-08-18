# ============================================================================
# WeaponSpore — 水母孢子（召唤型，behavior_type=summon_jellyfish）
# 行为：以玩家为中心脉冲结算召唤物叮咬；优先打击最近的若干敌人。
# 数据：config/weapons.json spore（pulse_rate + behavior）
# 原型：无独立召唤实体节点，用 SpatialHash 脉冲模拟召唤物 DPS
#       （验收口径：W6 行为可辨；视觉召唤实体延后至成长/特效周）
# ============================================================================
class_name WeaponSpore
extends WeaponBase


func fire(_target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var base_r: float = get_behavior_float("base_radius", 120.0)
	var r_per: float = get_behavior_float("radius_per_level", 10.0)
	var radius: float = scale_area_radius(base_r + r_per * float(level - 1))
	var sting_count: int = get_behavior_int("base_targets", 3) + get_behavior_int("targets_per_level", 1) * (level - 1) + MetaSystem.get_extra_projectiles()
	var ranked: Array[EnemyBase] = query_nearest_enemies(hash, origin, radius, sting_count)
	for e in ranked:
		e.take_damage(roll_hit_damage())
