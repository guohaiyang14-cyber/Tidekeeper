# ============================================================================
# BotCombatStats — TestBot 按夜战斗统计（Debug）
# 职责：玩家属性/加成快照、武器造成伤害、敌人属性与存活时间（击杀+夜末未击杀）
# 落盘：仅 print 结构化 [TestBot] STAT 行，供 tools/view_bot_runs.py 解析
# ============================================================================
class_name BotCombatStats
extends RefCounted

var _night: int = 0
var _active: bool = false
## weapon_id → {dealt:int, hits:int}
var _weapon_damage: Dictionary = {}
## agg_key → {killed, unkilled, alive_k_sum, alive_u_sum, maxhp_sum, spd_sum, cdmg_sum, samples}
var _enemy_agg: Dictionary = {}


func reset_run() -> void:
	_night = 0
	_active = false
	_weapon_damage.clear()
	_enemy_agg.clear()


func begin_night(night: int, world: World) -> void:
	_flush_if_needed(world)
	_night = night
	_active = true
	_weapon_damage.clear()
	_enemy_agg.clear()
	_print_player_snapshot(night, world)
	_print_bonus_snapshot(night)
	_print_weapon_sheet(night, world)
	_print_passive_sheet(night)


func end_night(night: int, world: World) -> void:
	if not _active:
		return
	_snapshot_unkilled(world)
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
	_accumulate_enemy(enemy, true, enemy.get_alive_seconds())


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
		_accumulate_enemy(enemy, false, enemy.get_alive_seconds())


func _accumulate_enemy(enemy: EnemyBase, killed: bool, alive_sec: float) -> void:
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
			"maxhp_sum": 0,
			"spd_sum": 0.0,
			"cdmg_sum": 0,
			"samples": 0,
		}
	if killed:
		row["killed"] = int(row["killed"]) + 1
		row["alive_k_sum"] = float(row["alive_k_sum"]) + alive_sec
	else:
		row["unkilled"] = int(row["unkilled"]) + 1
		row["alive_u_sum"] = float(row["alive_u_sum"]) + alive_sec
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
		"[TestBot] STAT night=%d phase=start hp=%d/%d lv=%d coins=%d move=%.2f pickup=%.1f dmg_m=%.2f atk_m=%.2f dr=%.2f crit=%.2f area_m=%.2f cd_r=%.2f exp_m=%.2f"
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
		print(
			"[TestBot] STAT night=%d phase=end kind=enemy id=%s tier=%s affix=%s killed=%d unkilled=%d avg_alive_k=%.1f avg_alive_u=%.1f avg_maxhp=%d avg_spd=%.0f avg_cdmg=%d"
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
			]
		)
	print(
		"[TestBot] STAT night=%d phase=end kind=summary dealt_total=%d hits_total=%d kills=%d unkilled=%d"
		% [night, dealt_total, hits_total, kills, unkilled]
	)
