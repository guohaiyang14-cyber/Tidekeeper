# ============================================================================
# WeaponHarpoon — 鱼叉枪（定向弹幕，behavior_type=directional_pierce）
# 行为：朝最近敌人发射扇形弹幕；穿透命中敌人。弹道数/穿透随等级提升。
# 数据：config/weapons.json harpoon.behavior
# ============================================================================
class_name WeaponHarpoon
extends WeaponBase


func fire(target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var pool: ProjectilePool = mgr.get_projectile_pool()
	if pool == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var dir: Vector2 = (target.global_position - origin).normalized()
	# 弹道携带 leveled 伤害；暴击在 Projectile 每次命中时独立掷骰
	var dmg: int = get_leveled_damage()
	var count: int = get_behavior_int("base_count", 5) + get_behavior_int("count_per_level", 1) * (level - 1) + MetaSystem.get_extra_projectiles()
	var pierce: int = get_behavior_int("base_pierce", 2) + get_behavior_int("pierce_per_level", 1) * (level - 1)
	var spread_deg: float = get_behavior_float("spread_deg", 6.0)
	for i in count:
		var p: Projectile = pool.acquire() as Projectile
		if p == null:
			break
		var angle_offset: float = deg_to_rad(float(i - (count - 1) / 2.0) * spread_deg)
		var d: Vector2 = dir.rotated(angle_offset)
		p.launch(origin, d, dmg, pierce, 1.0, 0.0, weapon_id)
