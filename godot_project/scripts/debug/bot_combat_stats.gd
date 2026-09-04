# ============================================================================
# BotCombatStats — TestBot 按夜战斗统计（Debug）
# 职责：玩家属性/加成快照、武器造成伤害、敌人属性与存活时间（击杀+夜末未击杀）
#       刷怪/死亡相对玩家距离（诊断「屏内怪少、追不上机器人」）
# 落盘：仅 print 结构化 [TestBot] STAT 行，供 tools/view_bot_runs.py 解析
# ============================================================================
class_name BotCombatStats
extends RefCounted

## 约半屏可见半径（诊断近似：默认 1280×720、无 zoom；非玩法数值）
const SCREEN_NEAR_DIST: float = 420.0
## 贴脸/围堵半径（诊断近似）
const CONTACT_NEAR_DIST: float = 80.0
## 预算怪前 N 次刷点全量落盘
const SPAWN_LOG_BUDGET_CAP: int = 12
## floor 补刷每隔 N 次落一条样例
const SPAWN_LOG_FLOOR_EVERY: int = 40

var _night: int = 0
var _active: bool = false
## weapon_id → {dealt:int, hits:int}
var _weapon_damage: Dictionary = {}
## agg_key → {killed, unkilled, alive_*, dist_*, maxhp_sum, spd_sum, cdmg_sum, samples}
var _enemy_agg: Dictionary = {}
## 本夜刷怪样例计数（预算 / floor 分流）
var _spawn_log_budget: int = 0
var _spawn_log_floor: int = 0
## 本夜汇总距离
var _death_dist_sum: float = 0.0
var _death_dist_n: int = 0
var _death_dist_min: float = 0.0
var _death_near_contact: int = 0
var _death_near_screen: int = 0
var _spawn_dist_sum: float = 0.0
var _spawn_dist_n: int = 0
var _player_spd_px: float = 0.0


func reset_run() -> void:
	_night = 0
	_active = false
	_weapon_damage.clear()
	_enemy_agg.clear()
	_reset_night_meters()


func begin_night(night: int, world: World) -> void:
	_flush_if_needed(world)
	_night = night
	_active = true
	_weapon_damage.clear()
	_enemy_agg.clear()
	_reset_night_meters()
	_player_spd_px = _read_player_spd_px(world)
	_print_player_snapshot(night, world)
	_print_bonus_snapshot(night)
	_print_weapon_sheet(night, world)
	_print_passive_sheet(night)


func end_night(night: int, world: World) -> void:
	if not _active:
		return
	_snapshot_unkilled(world)
	_print_proximity_snapshot(night, world)
	_print_end_report(night)
	_active = false


## 局中死亡/通关：若仍在夜中则补打本夜报告
func flush_open_night(world: World) -> void:
	_flush_if_needed(world)


func record_damage(source_id: String, amount: int) -> void:
	if not _active or amount <= 0 or source_id == "":
		return
	var row: Variant = _weapon_damage.get(source_id)
	if row == null:
		row = {"dealt": 0, "hits": 0}
	row["dealt"] = int(row["dealt"]) + amount
	row["hits"] = int(row["hits"]) + 1
	_weapon_damage[source_id] = row


func record_enemy_death(enemy: EnemyBase) -> void:
	if not _active or enemy == null:
		return
	var death_dist: float = enemy.get_distance_to_target()
	_accumulate_enemy(enemy, true, enemy.get_alive_seconds(), death_dist, enemy.get_spawn_distance_to_target())
	if death_dist >= 0.0:
		_note_death_dist(death_dist)


func record_enemy_spawn(enemy: EnemyBase) -> void:
	if not _active or enemy == null:
		return
	var spawn_dist: float = enemy.get_spawn_distance_to_target()
	if spawn_dist >= 0.0:
		_spawn_dist_sum += spawn_dist
		_spawn_dist_n += 1
	_maybe_log_spawn_sample(enemy, spawn_dist)


func _reset_night_meters() -> void:
	_spawn_log_budget = 0
	_spawn_log_floor = 0
	_death_dist_sum = 0.0
	_death_dist_n = 0
	_death_dist_min = 0.0
	_death_near_contact = 0
	_death_near_screen = 0
	_spawn_dist_sum = 0.0
	_spawn_dist_n = 0
	_player_spd_px = 0.0


func _note_death_dist(dist: float) -> void:
	_death_dist_sum += dist
	_death_dist_n += 1
	if _death_dist_n == 1 or dist < _death_dist_min:
		_death_dist_min = dist
	if dist <= CONTACT_NEAR_DIST:
		_death_near_contact += 1
	if dist <= SCREEN_NEAR_DIST:
		_death_near_screen += 1


func _maybe_log_spawn_sample(enemy: EnemyBase, spawn_dist: float) -> void:
	var should_log: bool = false
	if enemy.is_boss or enemy.is_elite:
		should_log = true
	elif enemy.is_floor_refill:
		_spawn_log_floor += 1
		should_log = (_spawn_log_floor <= 2) or (_spawn_log_floor % SPAWN_LOG_FLOOR_EVERY == 0)
	else:
		_spawn_log_budget += 1
		should_log = _spawn_log_budget <= SPAWN_LOG_BUDGET_CAP
	if not should_log:
		return
	var player_pos: Vector2 = Vector2.ZERO
	if enemy.target != null and is_instance_valid(enemy.target):
		player_pos = enemy.target.global_position
	var tier: String = _enemy_tier(enemy)
	print(
		"[TestBot] STAT night=%d phase=spawn kind=pos id=%s tier=%s affix=%s pos=(%.0f,%.0f) player=(%.0f,%.0f) dist=%.0f spd=%.0f player_spd=%.0f"
		% [
			_night,
			enemy.enemy_id,
			tier,
			_affix_token(enemy),
			enemy.global_position.x,
			enemy.global_position.y,
			player_pos.x,
			player_pos.y,
			spawn_dist,
			enemy.move_speed,
			_player_spd_px,
		]
	)


func _flush_if_needed(world: World) -> void:
	if _active:
		end_night(_night, world)


func _snapshot_unkilled(world: World) -> void:
	if world == null or world.enemy_spawner == null or world.enemy_spawner.enemy_pool == null:
		return
	for node in world.enemy_spawner.enemy_pool.get_active():
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		# 未击杀只累计存活/刷点；当前距离由 proximity 快照覆盖，避免污染 avg_ddist
		_accumulate_enemy(enemy, false, enemy.get_alive_seconds(), -1.0, enemy.get_spawn_distance_to_target())


func _accumulate_enemy(
	enemy: EnemyBase,
	killed: bool,
	alive_sec: float,
	death_dist: float,
	spawn_dist: float,
) -> void:
	var key: String = _enemy_key(enemy)
	var row: Variant = _enemy_agg.get(key)
	if row == null:
		row = {
			"id": enemy.enemy_id,
			"tier": _enemy_tier(enemy),
			"affix": _affix_token(enemy),
			"killed": 0,
			"unkilled": 0,
			"alive_k_sum": 0.0,
			"alive_u_sum": 0.0,
			"ddist_sum": 0.0,
			"ddist_n": 0,
			"ddist_min": 0.0,
			"sdist_sum": 0.0,
			"sdist_n": 0,
			"maxhp_sum": 0,
			"spd_sum": 0.0,
			"cdmg_sum": 0,
			"samples": 0,
		}
	if killed:
		row["killed"] = int(row["killed"]) + 1
		row["alive_k_sum"] = float(row["alive_k_sum"]) + alive_sec
		if death_dist >= 0.0:
			row["ddist_sum"] = float(row["ddist_sum"]) + death_dist
			row["ddist_n"] = int(row["ddist_n"]) + 1
			var dmin: float = float(row["ddist_min"])
			var dn: int = int(row["ddist_n"])
			if dn == 1 or death_dist < dmin:
				row["ddist_min"] = death_dist
	else:
		row["unkilled"] = int(row["unkilled"]) + 1
		row["alive_u_sum"] = float(row["alive_u_sum"]) + alive_sec
	if spawn_dist >= 0.0:
		row["sdist_sum"] = float(row["sdist_sum"]) + spawn_dist
		row["sdist_n"] = int(row["sdist_n"]) + 1
	row["maxhp_sum"] = int(row["maxhp_sum"]) + enemy.max_health
	row["spd_sum"] = float(row["spd_sum"]) + enemy.move_speed
	row["cdmg_sum"] = int(row["cdmg_sum"]) + enemy.contact_damage
	row["samples"] = int(row["samples"]) + 1
	_enemy_agg[key] = row


func _enemy_tier(enemy: EnemyBase) -> String:
	if enemy.is_boss:
		return "boss"
	if enemy.is_floor_refill:
		return "floor"
	if enemy.is_elite:
		return "elite"
	return "normal"


func _affix_token(enemy: EnemyBase) -> String:
	if enemy.affix_ids.is_empty():
		return "-"
	var ids: Array[String] = enemy.affix_ids.duplicate()
	ids.sort()
	return "+".join(ids)


func _enemy_key(enemy: EnemyBase) -> String:
	return "%s|%s|%s" % [enemy.enemy_id, _enemy_tier(enemy), _affix_token(enemy)]


func _read_player_spd_px(world: World) -> float:
	if world == null or world.player == null:
		return 0.0
	var player: Player = world.player as Player
	if player == null:
		return 0.0
	return player.get_current_speed()


func _print_player_snapshot(night: int, world: World) -> void:
	var move: float = 0.0
	var pickup: float = 0.0
	if world != null and world.player != null:
		var player: Player = world.player as Player
		if player != null:
			# get_current_speed 为像素/秒；单位移速 = px / UNIT_TO_PIXEL
			move = player.get_current_speed() / Player.UNIT_TO_PIXEL
			pickup = player.get_pickup_radius()
	print(
		"[TestBot] STAT night=%d phase=start hp=%d/%d lv=%d coins=%d move=%.2f pickup=%.1f dmg_m=%.2f atk_m=%.2f dr=%.2f crit=%.2f area_m=%.2f cd_r=%.2f exp_m=%.2f player_spd_px=%.0f"
		% [
			night,
			GameState.player_health,
			GameState.player_max_health,
			GameState.player_level,
			GameState.tidecoins,
			move,
			pickup,
			PassiveSystem.get_damage_mult() * MetaSystem.get_damage_mult(),
			PassiveSystem.get_attack_speed_mult() * EventSystem.get_attack_speed_mult() * MetaSystem.get_attack_speed_mult(),
			PassiveSystem.get_damage_reduction(),
			PassiveSystem.get_crit_chance(),
			PassiveSystem.get_area_mult() * MetaSystem.get_area_mult(),
			PassiveSystem.get_cd_reduction(),
			PassiveSystem.get_exp_mult() * EventSystem.get_exp_mult() * MetaSystem.get_exp_mult(),
			_player_spd_px,
		]
	)


func _print_bonus_snapshot(night: int) -> void:
	print(
		"[TestBot] STAT night=%d phase=start kind=bonus dmg_pass=%.2f dmg_meta=%.2f atk_pass=%.2f atk_meta=%.2f atk_evt=%.2f area_pass=%.2f area_meta=%.2f dr=%.2f crit=%.2f cd_r=%.2f"
		% [
			night,
			PassiveSystem.get_damage_mult(),
			MetaSystem.get_damage_mult(),
			PassiveSystem.get_attack_speed_mult(),
			MetaSystem.get_attack_speed_mult(),
			EventSystem.get_attack_speed_mult(),
			PassiveSystem.get_area_mult(),
			MetaSystem.get_area_mult(),
			PassiveSystem.get_damage_reduction(),
			PassiveSystem.get_crit_chance(),
			PassiveSystem.get_cd_reduction(),
		]
	)


func _print_weapon_sheet(night: int, world: World) -> void:
	var weapons: Array[WeaponBase] = []
	if world != null and world.weapon_manager != null:
		weapons = world.weapon_manager.get_weapons()
	if weapons.is_empty():
		for wid in GameState.weapon_slots:
			var id: String = String(wid)
			print(
				"[TestBot] STAT night=%d phase=start kind=weapon id=%s lv=%d dmg=-1 evo=%d refine=%d rate=-1"
				% [
					night, id, GameState.get_weapon_level(id),
					1 if GameState.is_weapon_evolved(id) else 0,
					GameState.get_refine_tier(id),
				]
			)
		return
	for w in weapons:
		if w == null or w.weapon_id == "":
			continue
		print(
			"[TestBot] STAT night=%d phase=start kind=weapon id=%s lv=%d dmg=%d evo=%d refine=%d rate=%.2f"
			% [
				night,
				w.weapon_id,
				w.level,
				w.get_leveled_damage(),
				1 if GameState.is_weapon_evolved(w.weapon_id) else 0,
				GameState.get_refine_tier(w.weapon_id),
				w.get_attack_rate(),
			]
		)


func _print_passive_sheet(night: int) -> void:
	for pid in GameState.passive_slots:
		var id: String = String(pid)
		print(
			"[TestBot] STAT night=%d phase=start kind=passive id=%s lv=%d"
			% [night, id, GameState.get_passive_level(id)]
		)


func _print_proximity_snapshot(night: int, world: World) -> void:
	if world == null or world.player == null or world.enemy_spawner == null:
		return
	if world.enemy_spawner.enemy_pool == null:
		return
	var player: Player = world.player as Player
	if player == null:
		return
	var origin: Vector2 = player.global_position
	var n_total: int = 0
	var n_contact: int = 0
	var n_screen: int = 0
	var dist_sum: float = 0.0
	var samples: Array[Dictionary] = []
	for node in world.enemy_spawner.enemy_pool.get_active():
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		var dist: float = enemy.global_position.distance_to(origin)
		n_total += 1
		dist_sum += dist
		if dist <= CONTACT_NEAR_DIST:
			n_contact += 1
		if dist <= SCREEN_NEAR_DIST:
			n_screen += 1
		if samples.size() < 8:
			samples.append({
				"id": enemy.enemy_id,
				"tier": _enemy_tier(enemy),
				"x": enemy.global_position.x,
				"y": enemy.global_position.y,
				"dist": dist,
				"spd": enemy.move_speed,
			})
	var avg_d: float = (dist_sum / float(n_total)) if n_total > 0 else 0.0
	print(
		"[TestBot] STAT night=%d phase=end kind=proximity active=%d near_contact=%d near_screen=%d avg_dist=%.0f player=(%.0f,%.0f) player_spd=%.0f"
		% [night, n_total, n_contact, n_screen, avg_d, origin.x, origin.y, _player_spd_px]
	)
	for s in samples:
		print(
			"[TestBot] STAT night=%d phase=end kind=alive_pos id=%s tier=%s pos=(%.0f,%.0f) dist=%.0f spd=%.0f"
			% [night, String(s["id"]), String(s["tier"]), float(s["x"]), float(s["y"]), float(s["dist"]), float(s["spd"])]
		)


func _print_end_report(night: int) -> void:
	var dealt_total: int = 0
	var hits_total: int = 0
	var weapon_ids: Array = _weapon_damage.keys()
	weapon_ids.sort()
	for wid_v in weapon_ids:
		var wid: String = String(wid_v)
		var row: Dictionary = _weapon_damage[wid]
		var dealt: int = int(row.get("dealt", 0))
		var hits: int = int(row.get("hits", 0))
		dealt_total += dealt
		hits_total += hits
		print(
			"[TestBot] STAT night=%d phase=end kind=weapon id=%s dealt=%d hits=%d"
			% [night, wid, dealt, hits]
		)
	var kills: int = 0
	var unkilled: int = 0
	var keys: Array = _enemy_agg.keys()
	keys.sort()
	for key_v in keys:
		var row: Dictionary = _enemy_agg[key_v]
		var k: int = int(row.get("killed", 0))
		var u: int = int(row.get("unkilled", 0))
		kills += k
		unkilled += u
		var samples: int = maxi(1, int(row.get("samples", 1)))
		var avg_k: float = (float(row.get("alive_k_sum", 0.0)) / float(k)) if k > 0 else 0.0
		var avg_u: float = (float(row.get("alive_u_sum", 0.0)) / float(u)) if u > 0 else 0.0
		var dn: int = int(row.get("ddist_n", 0))
		var sn: int = int(row.get("sdist_n", 0))
		var avg_dd: float = (float(row.get("ddist_sum", 0.0)) / float(dn)) if dn > 0 else -1.0
		var min_dd: float = float(row.get("ddist_min", -1.0)) if dn > 0 else -1.0
		var avg_sd: float = (float(row.get("sdist_sum", 0.0)) / float(sn)) if sn > 0 else -1.0
		print(
			"[TestBot] STAT night=%d phase=end kind=enemy id=%s tier=%s affix=%s killed=%d unkilled=%d avg_alive_k=%.1f avg_alive_u=%.1f avg_maxhp=%d avg_spd=%.0f avg_cdmg=%d avg_ddist=%.0f min_ddist=%.0f avg_sdist=%.0f"
			% [
				night,
				String(row.get("id", "?")),
				String(row.get("tier", "normal")),
				String(row.get("affix", "-")),
				k,
				u,
				avg_k,
				avg_u,
				int(round(float(row.get("maxhp_sum", 0)) / float(samples))),
				float(row.get("spd_sum", 0.0)) / float(samples),
				int(round(float(row.get("cdmg_sum", 0)) / float(samples))),
				avg_dd,
				min_dd,
				avg_sd,
			]
		)
	var avg_death: float = (_death_dist_sum / float(_death_dist_n)) if _death_dist_n > 0 else -1.0
	var avg_spawn: float = (_spawn_dist_sum / float(_spawn_dist_n)) if _spawn_dist_n > 0 else -1.0
	var min_death: float = _death_dist_min if _death_dist_n > 0 else -1.0
	print(
		"[TestBot] STAT night=%d phase=end kind=summary dealt_total=%d hits_total=%d kills=%d unkilled=%d avg_death_dist=%.0f min_death_dist=%.0f death_near_contact=%d death_near_screen=%d avg_spawn_dist=%.0f player_spd=%.0f"
		% [
			night, dealt_total, hits_total, kills, unkilled,
			avg_death, min_death, _death_near_contact, _death_near_screen, avg_spawn, _player_spd_px,
		]
	)
