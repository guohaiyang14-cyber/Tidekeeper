# ============================================================================
# WeaponAnchorChain — 锚链（环绕型，behavior_type=orbit_tick）
# 行为：以玩家为中心脉冲结算环绕伤害，对玩家周围敌人造成 leveled 伤害。
# 数据：config/weapons.json anchor_chain.behavior
# 可视化（2026-10-22）：持久环绕链视觉（跟随玩家的旋转链段，tick 时脉冲闪光）。
# ============================================================================
class_name WeaponAnchorChain
extends WeaponBase

const _ORBIT_VIS = preload("res://scripts/combat/orbit_chain_visual.gd")

var _orbit_vis: OrbitChainVisual = null


func fire(_target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var spatial_hash: SpatialHash = mgr.get_hash()
	if spatial_hash == null:
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
		_hit_annulus(spatial_hash, origin, inner, outer)
	# 视觉：同步持久环绕链（半径/圈数/ tick 脉冲）
	_sync_orbit_visual(radius, spacing, rings)
	if _orbit_vis != null:
		_orbit_vis.pulse()
	# 近战销毁敌方弹幕（2026-10-23 用户反馈「近身类武器应该有销毁敌方子弹的功能」）：
	# 环绕半径内的敌方弹道全部回收，每个销毁点一枚 deflect 火花
	if get_behavior_bool("clear_enemy_projectiles", false):
		for hit_pos in clear_enemy_projectiles(origin, radius):
			mgr.spawn_area_effect(hit_pos, 12.0, get_behavior_color("chain_color", "b8c4d4"), "deflect")


## 确保环绕链视觉存在且参数同步（首次 fire 时创建；挂武器下随武器回收）
func _sync_orbit_visual(radius: float, spacing: float, rings: int) -> void:
	if _orbit_vis == null or not is_instance_valid(_orbit_vis):
		_orbit_vis = _ORBIT_VIS.create(get_owner_pos)
		add_child(_orbit_vis)
	_orbit_vis.setup(radius, spacing, rings, get_behavior_color("chain_color", "b8c4d4"), 2.4, get_owner_pos)


## 对距 origin 在 (inner, outer] 的敌人各造成一次命中（inner=0 含圆心）
func _hit_annulus(spatial_hash: SpatialHash, origin: Vector2, inner: float, outer: float) -> void:
	var pts: Array = spatial_hash.query_radius(origin, outer)
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
