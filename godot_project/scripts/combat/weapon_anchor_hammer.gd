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
	var spatial_hash: SpatialHash = mgr.get_hash()
	if spatial_hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var base_r: float = get_behavior_float("base_radius", 70.0)
	var l1_mult: float = get_behavior_float("l1_radius_mult", 1.6)
	var per_lv: float = get_behavior_float("radius_per_level", 0.15)
	var radius: float = scale_area_radius(base_r * l1_mult * (1.0 + per_lv * float(level - 1)))
	# 弹道+1：额外朝近战半径内其他敌人各挥一锤；跨挥击同一敌人只结算一次（与锚链不叠伤同口径）
	var swing_count: int = 1 + MetaSystem.get_extra_projectiles()
	var ranked: Array[EnemyBase] = query_nearest_enemies(spatial_hash, origin, radius, swing_count)
	var hit: Dictionary = {}
	var swing_aims: Array[Vector2] = []
	if ranked.is_empty():
		_burst_toward(spatial_hash, origin, radius, target.global_position, hit)
		swing_aims.append(target.global_position)
	else:
		for e in ranked:
			_burst_toward(spatial_hash, origin, radius, e.global_position, hit)
			swing_aims.append(e.global_position)
	# 视觉反馈：每次挥击在玩家位置落一圈朝目标方向的锤击（attack_fx.kind=slam）；
	# 冲击环圆心与伤害判定同心（都是 origin），弧线扫向瞄准方向
	var fx_color: Color = get_behavior_color("effect_color", "cfd8e0")
	for aim in swing_aims:
		mgr.spawn_area_effect(origin, radius, fx_color, get_attack_fx_kind("slam"),
			(aim - origin).normalized())
	# 近战销毁敌方弹幕（2026-10-23 用户反馈「近身类武器应该有销毁敌方子弹的功能」）：
	# 挥击范围内敌方弹道全部回收，每个销毁点一枚 deflect 火花（attack_fx.kind=deflect）
	if get_behavior_bool("clear_enemy_projectiles", false):
		for hit_pos in clear_enemy_projectiles(origin, radius):
			mgr.spawn_area_effect(hit_pos, 12.0, fx_color, "deflect")


## 朝 aim_at 方向对前方半球内未命中敌人各造成一次伤害（暴击独立掷骰）
func _burst_toward(spatial_hash: SpatialHash, origin: Vector2, radius: float, aim_at: Vector2, hit: Dictionary) -> void:
	var forward: Vector2 = (aim_at - origin).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var r2: float = radius * radius
	var targets: Array = spatial_hash.query_radius(origin, radius)
	for node in targets:
		if not (node is EnemyBase):
			continue
		var enemy: EnemyBase = node as EnemyBase
		var to_e: Vector2 = enemy.global_position - origin
		if to_e.length_squared() > r2:
			continue
		if forward.dot(to_e) < 0.0:
			continue
		var eid: int = enemy.get_instance_id()
		if hit.has(eid):
			continue
		hit[eid] = true
		enemy.take_damage(roll_hit_damage(), true, false, weapon_id)
