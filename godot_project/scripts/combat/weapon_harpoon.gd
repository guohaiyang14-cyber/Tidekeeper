# ============================================================================
# WeaponHarpoon — 鱼叉枪（定向弹幕，behavior_type=directional_pierce）
# 行为：朝最近敌人发射扇形弹幕；穿透命中敌人。弹道数/穿透随等级提升。
# 数据：config/weapons.json harpoon（level_1_trait: 5 弹道、穿透 2）
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
	var dmg: int = get_leveled_damage()
	# 规模随等级：5 弹道起，每级 +1；穿透 2 起，每级 +1
	var count: int = 5 + (level - 1)
	var pierce: int = 2 + (level - 1)
	for i in count:
		var p: Projectile = pool.acquire() as Projectile
		if p == null:
			break
		var angle_offset: float = deg_to_rad(float(i - (count - 1) / 2.0) * 6.0)
		var d: Vector2 = dir.rotated(angle_offset)
		p.launch(origin, d, dmg, pierce)
