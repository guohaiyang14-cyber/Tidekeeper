# ============================================================================
# WeaponAlbatross — 信天翁（召唤俯冲，behavior_type=summon_dive）
# 行为：对最近若干敌人发动俯冲打击。
# 数据：config/weapons.json albatross（pulse_rate + behavior）
# 原型：无飞行实体节点，脉冲结算俯冲伤害
#       （验收口径：W6 行为可辨；视觉召唤实体延后至成长/特效周）
# ============================================================================
class_name WeaponAlbatross
extends WeaponBase


func fire(target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var hash: SpatialHash = mgr.get_hash()
	if hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var base_r: float = get_behavior_float("base_radius", 280.0)
	var r_per: float = get_behavior_float("radius_per_level", 20.0)
	var radius: float = scale_area_radius(base_r + r_per * float(level - 1))
	var dive_count: int = get_behavior_int("base_targets", 2) + get_behavior_int("targets_per_level", 1) * (level - 1) + MetaSystem.get_extra_projectiles()
	var ranked: Array[EnemyBase] = query_nearest_enemies(hash, origin, radius, dive_count)
	if ranked.is_empty():
		target.take_damage(roll_hit_damage())
		return
	for e in ranked:
		e.take_damage(roll_hit_damage())
