# ============================================================================
# BossTideArchon — 潮汐执政官（第 15 夜）
# 行为：周期传送 + 潮汐波（灯塔光晕外受伤）
# ============================================================================
class_name BossTideArchon
extends BossBrain

var _teleport_cd: float = 0.0
var _wave_cd: float = 0.0


func _on_setup() -> void:
	_teleport_cd = get_float("teleport_interval", 5.0)
	_wave_cd = get_float("wave_initial_delay", 2.0)


func _tick(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if do_move:
		host.boss_move_toward(player_pos, delta)

	_teleport_cd -= delta
	if _teleport_cd <= 0.0:
		_teleport_cd = get_float("teleport_interval", 5.0)
		_do_teleport()

	_wave_cd -= delta
	if _wave_cd <= 0.0:
		_wave_cd = get_float("wave_interval", 7.0)
		_do_tidal_wave()


func _do_teleport() -> void:
	var rng_range: float = get_float("teleport_range", 160.0)
	var angle: float = RNG.randf_range(0.0, TAU)
	var dist: float = RNG.randf_range(rng_range * 0.4, rng_range)
	host.boss_teleport(host.global_position + Vector2.from_angle(angle) * dist)


func _do_tidal_wave() -> void:
	var dmg: int = get_int("wave_damage", 28)
	var aura: float = _lighthouse_aura_radius()
	var light_pos: Vector2 = host.get_lighthouse_position()
	if host.target == null:
		return
	var dist: float = host.target.global_position.distance_to(light_pos)
	if dist > aura:
		GameState.damage_player(dmg, "boss_tide_archon")


func _lighthouse_aura_radius() -> float:
	var light: Dictionary = ConfigLoader.get_lighthouse_meta()
	return float(light.get("aura_radius", 140.0))
