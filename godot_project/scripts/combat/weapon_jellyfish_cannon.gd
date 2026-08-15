# ============================================================================
# WeaponJellyfishCannon — 水母炮（环形弹幕，behavior_type=ring_barrage）
# 行为：自玩家向四周发射环形弹道；命中施加减速（表载 hit_slow_*）。
# 数据：config/weapons.json jellyfish_cannon.behavior
# ============================================================================
class_name WeaponJellyfishCannon
extends WeaponBase


func fire(_target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var pool: ProjectilePool = mgr.get_projectile_pool()
	if pool == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var dmg: int = get_leveled_damage()
	var count: int = get_behavior_int("base_count", 4) + get_behavior_int("count_per_level", 1) * (level - 1)
	var slow_factor: float = get_behavior_float("hit_slow_factor", 0.8)
	var slow_dur: float = get_behavior_float("hit_slow_duration", 1.0)
	for i in count:
		var p: Projectile = pool.acquire() as Projectile
		if p == null:
			break
		var angle: float = TAU * float(i) / float(count)
		var dir: Vector2 = Vector2.from_angle(angle)
		p.launch(origin, dir, dmg, 0, slow_factor, slow_dur)
