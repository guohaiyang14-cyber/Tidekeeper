# ============================================================================
# BossJellyQueen — 深渊水母后（第 10 夜）
# 行为：保持距离 + 环形弹幕 + 周期召唤水母浮游
# ============================================================================
class_name BossJellyQueen
extends BossBrain

var _barrage_cd: float = 0.0
var _split_cd: float = 0.0


func _on_setup() -> void:
	_barrage_cd = get_float("barrage_interval", 3.0) * 0.5
	_split_cd = get_float("split_interval", 8.0) * 0.4


func _tick(delta: float, player_pos: Vector2, do_move: bool) -> void:
	var keep: float = get_float("keep_distance", 160.0)
	if do_move:
		var dist: float = host.global_position.distance_to(player_pos)
		if dist < keep:
			host.boss_move_away(player_pos, delta)
		elif dist > keep * 1.4:
			host.boss_move_toward(player_pos, delta)

	_barrage_cd -= delta
	if _barrage_cd <= 0.0:
		_barrage_cd = get_float("barrage_interval", 3.0)
		_fire_ring()

	_split_cd -= delta
	if _split_cd <= 0.0:
		_split_cd = get_float("split_interval", 8.0)
		_spawn_minions()


func _fire_ring() -> void:
	var count: int = get_int("barrage_count", 8)
	var dmg: int = get_int("barrage_damage", 12)
	if count <= 0:
		return
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		host.boss_fire_projectile(Vector2.from_angle(angle), dmg)


func _spawn_minions() -> void:
	var sid: String = get_string("split_enemy_id", "jellyfish_drifter")
	var n: int = get_int("split_count", 3)
	var def: Dictionary = ConfigLoader.get_enemy(sid)
	if def.is_empty():
		return
	var spawner: Node = host.find_spawner()
	if spawner == null or not spawner.has_method("spawn_enemy"):
		return
	var no_affix: Array[String] = []
	for i in n:
		var angle: float = TAU * float(i) / float(n)
		var pos: Vector2 = host.global_position + Vector2.from_angle(angle) * 40.0
		if spawner.call("spawn_enemy", def, pos, no_affix, true, true) == null:
			break
