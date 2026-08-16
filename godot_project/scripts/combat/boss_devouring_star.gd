# ============================================================================
# BossDevouringStar — 吞噬之星（第 20 夜）
# 阶段：护盾（减伤）→ 狂暴（加速/加伤）→ 分身（刷出小怪）
# 分身在 tick 中延后生成，避免 take_damage → on_health_changed 重入刷怪
# ============================================================================
class_name BossDevouringStar
extends BossBrain

var _spawned_clones: bool = false
var _pending_clones: bool = false
var _base_contact: int = 0
var _base_speed: float = 0.0


func _on_setup() -> void:
	_spawned_clones = false
	_pending_clones = false
	_base_contact = host.contact_damage
	_base_speed = host.move_speed
	phase = 0


func _tick(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if _pending_clones:
		_pending_clones = false
		_spawn_clones()
	if do_move:
		host.boss_move_toward(player_pos, delta)


func modify_incoming_damage(amount: int) -> int:
	if phase == 0:
		var taken: float = get_float("shield_damage_taken", 0.5)
		return maxi(1, int(round(float(amount) * taken)))
	return amount


func on_health_changed() -> void:
	_update_phase()


func _update_phase() -> void:
	if host == null or host.max_health <= 0:
		return
	var ratio: float = float(host.health) / float(host.max_health)
	var thresholds: Array = data.get("phase_hp_thresholds", [0.7, 0.35])
	var t0: float = 0.7
	var t1: float = 0.35
	if thresholds is Array and thresholds.size() >= 2:
		t0 = float(thresholds[0])
		t1 = float(thresholds[1])

	var new_phase: int = 0
	if ratio <= t1:
		new_phase = 2
	elif ratio <= t0:
		new_phase = 1

	if new_phase == phase:
		return
	phase = new_phase
	_apply_phase()


func _apply_phase() -> void:
	match phase:
		1:
			host.move_speed = _base_speed * get_float("enrage_speed_mult", 1.8)
			host.contact_damage = int(round(float(_base_contact) * get_float("enrage_contact_mult", 1.4)))
		2:
			host.move_speed = _base_speed * get_float("enrage_speed_mult", 1.8)
			host.contact_damage = int(round(float(_base_contact) * get_float("enrage_contact_mult", 1.4)))
			if not _spawned_clones:
				_spawned_clones = true
				_pending_clones = true
		_:
			host.move_speed = _base_speed
			host.contact_damage = _base_contact


func _spawn_clones() -> void:
	if host == null or not is_instance_valid(host) or host.is_dead():
		return
	var sid: String = get_string("clone_enemy_id", "small_goblin")
	var n: int = get_int("clone_count", 2)
	var hp_ratio: float = get_float("clone_hp_ratio", 0.2)
	var def: Dictionary = ConfigLoader.get_enemy(sid)
	if def.is_empty():
		return
	var spawner: Node = host.find_spawner()
	if spawner == null or not spawner.has_method("spawn_enemy"):
		return
	var child_hp: int = maxi(1, int(round(float(host.max_health) * hp_ratio)))
	var no_affix: Array[String] = []
	for i in n:
		var angle: float = TAU * float(i) / float(n)
		var pos: Vector2 = host.global_position + Vector2.from_angle(angle) * 48.0
		var child: EnemyBase = spawner.call("spawn_enemy", def, pos, no_affix, true, true) as EnemyBase
		if child == null:
			push_warning("[BossDevouringStar] 分身生成失败 %d/%d" % [i, n])
			break
		child.max_health = child_hp
		child.health = child_hp
		child.apply_visual_scale(0.85)
