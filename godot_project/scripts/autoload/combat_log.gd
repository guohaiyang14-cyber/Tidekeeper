# ============================================================================
# CombatLog — 战斗局次详细日志（autoload）
# 职责：记录人物/武器/升级/伤害/BD/宝箱/走位/刷怪/怪物/事件等，落盘 JSONL；
#       仅保留最近 max_runs 局（config/combat_log.json，默认 10）。
# 路径：user://combat_logs/（index.json + run_*.jsonl）
# 红线：数值只读 config；不改玩法；headless 单测默认跳过
# ============================================================================
extends Node

const INDEX_NAME: String = "index.json"
const DEFAULT_DIR: String = "user://combat_logs/"
const DEFAULT_MAX_RUNS: int = 10

var _cfg: Dictionary = {}
var _enabled: bool = false
var _max_runs: int = DEFAULT_MAX_RUNS
var _dir: String = DEFAULT_DIR
var _categories: Dictionary = {}
var _movement_interval: float = 2.0
var _damage_flush_interval: float = 5.0
var _spawn_elite_always: bool = true
var _spawn_budget_cap: int = 12
var _spawn_floor_every: int = 40
var _death_elite_detail: bool = true
var _death_agg_normal: bool = true
var _debug_only: bool = true

var _active: bool = false
var _run_id: String = ""
var _run_path: String = ""
var _run_started_unix: int = 0
var _file: FileAccess = null
var _t0_msec: int = 0

var _move_accum: float = 0.0
var _dealt_flush_accum: float = 0.0
## weapon_id → {dealt:int, hits:int}
var _dealt_buf: Dictionary = {}
## agg_key → {id,tier,affix,killed,alive_sum,ddist_sum,ddist_n}
var _kill_buf: Dictionary = {}
var _spawn_budget_n: int = 0
var _spawn_floor_n: int = 0
var _chest_connected: bool = false
var _shop_connected: bool = false
var _telemetry_registered: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reload_config()
	if not _enabled:
		print("[CombatLog] 已关闭（config/combat_log.json enabled=false）")
		return
	if not _passes_runtime_gate():
		print("[CombatLog] 已跳过（debug_only / headless 门控）")
		_enabled = false
		return
	_ensure_dir()
	_connect_signals()
	# 启动时顺手清一次孤儿 jsonl（不改索引）
	_prune_orphan_files(_load_index().get("runs", []) as Array)
	print("[CombatLog] 就绪 | dir=%s max_runs=%d" % [_dir, _max_runs])


func _exit_tree() -> void:
	_finalize_run("aborted", {})


func _process(delta: float) -> void:
	if not _active or not _enabled:
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return
	_dealt_flush_accum += delta
	if _dealt_flush_accum >= _damage_flush_interval:
		_dealt_flush_accum = 0.0
		_flush_combat_buffers()
	if not _cat("movement"):
		return
	if GameState.is_day_phase or GameState.is_over:
		return
	_move_accum += delta
	if _move_accum < _movement_interval:
		return
	_move_accum = 0.0
	_sample_movement()


## 遥测：武器造成伤害（聚合后按间隔/夜末落盘）
func note_damage(source_id: String, amount: int) -> void:
	if not _active or not _cat("damage") or source_id == "" or amount <= 0:
		return
	var row: Variant = _dealt_buf.get(source_id)
	if row == null:
		row = {"dealt": 0, "hits": 0}
	row["dealt"] = int(row["dealt"]) + amount
	row["hits"] = int(row["hits"]) + 1
	_dealt_buf[source_id] = row


func note_enemy_death(enemy: EnemyBase) -> void:
	if not _active or not _cat("monster") or enemy == null:
		return
	# 精英/Boss：逐条；普通/floor：聚合（避免热路径逐杀写盘）
	if _death_elite_detail and (enemy.is_boss or enemy.is_elite):
		_write_event("monster", {
			"action": "death",
			"id": enemy.enemy_id,
			"tier": _enemy_tier(enemy),
			"affix": _affix_token(enemy),
			"alive_sec": snappedf(enemy.get_alive_seconds(), 0.1),
			"death_dist": snappedf(enemy.get_distance_to_target(), 1.0),
			"pos": _vec2(enemy.global_position),
			"max_hp": enemy.max_health,
			"is_floor": enemy.is_floor_refill,
		})
		return
	if not _death_agg_normal:
		return
	var key: String = "%s|%s|%s" % [enemy.enemy_id, _enemy_tier(enemy), _affix_token(enemy)]
	var row: Variant = _kill_buf.get(key)
	if row == null:
		row = {
			"id": enemy.enemy_id,
			"tier": _enemy_tier(enemy),
			"affix": _affix_token(enemy),
			"killed": 0,
			"alive_sum": 0.0,
			"ddist_sum": 0.0,
			"ddist_n": 0,
		}
	row["killed"] = int(row["killed"]) + 1
	row["alive_sum"] = float(row["alive_sum"]) + enemy.get_alive_seconds()
	var ddist: float = enemy.get_distance_to_target()
	if ddist >= 0.0:
		row["ddist_sum"] = float(row["ddist_sum"]) + ddist
		row["ddist_n"] = int(row["ddist_n"]) + 1
	_kill_buf[key] = row


func note_enemy_spawn(enemy: EnemyBase) -> void:
	if not _active or not _cat("monster") or enemy == null:
		return
	if not _should_log_spawn(enemy):
		return
	var player_pos: Vector2 = Vector2.ZERO
	if enemy.target != null and is_instance_valid(enemy.target):
		player_pos = enemy.target.global_position
	_write_event("monster", {
		"action": "spawn",
		"id": enemy.enemy_id,
		"tier": _enemy_tier(enemy),
		"affix": _affix_token(enemy),
		"pos": _vec2(enemy.global_position),
		"player": _vec2(player_pos),
		"spawn_dist": snappedf(enemy.get_spawn_distance_to_target(), 1.0),
		"spd": snappedf(enemy.move_speed, 1.0),
		"max_hp": enemy.max_health,
		"cdmg": enemy.contact_damage,
		"is_floor": enemy.is_floor_refill,
	})


# ============================================================================
# 信号
# ============================================================================

func _connect_signals() -> void:
	GameState.run_started.connect(_on_run_started)
	GameState.night_started.connect(_on_night_started)
	GameState.night_ended.connect(_on_night_ended)
	GameState.day_started.connect(_on_day_started)
	GameState.game_over.connect(_on_game_over)
	GameState.game_win.connect(_on_game_win)
	GameState.level_up.connect(_on_level_up)
	GameState.player_damaged.connect(_on_player_damaged)
	GameState.loadout_changed.connect(_on_loadout_changed)
	GameState.player_revived.connect(_on_player_revived)
	GameState.player_down.connect(_on_player_down)
	UpgradeManager.upgrade_resolved.connect(_on_upgrade_resolved)
	UpgradeManager.upgrade_offered.connect(_on_upgrade_offered)
	EventSystem.event_armed.connect(_on_event_armed)
	EvolutionSystem.evolved.connect(_on_evolved)
	RefineSystem.refined.connect(_on_refined)
	if get_tree() != null:
		get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	_chest_connected = false
	_shop_connected = false
	# 离开 World（回选角 / 单测 / 其它场景）时收口未结束局
	if _active and _current_world() == null:
		var reason: String = "test_scene" if _should_skip_scene() else "scene_left"
		_finalize_run("aborted", {"reason": reason})
	_try_bind_world_hooks()


func _on_run_started(character: String, seed_value: int) -> void:
	if not _enabled:
		return
	if _should_skip_environment() or _should_skip_scene():
		return
	_begin_run(character, seed_value)


func _on_night_started(night: int) -> void:
	if not _active:
		return
	_spawn_budget_n = 0
	_spawn_floor_n = 0
	_move_accum = 0.0
	_dealt_flush_accum = 0.0
	_try_bind_world_hooks()
	if _cat("character"):
		_write_event("character", _snapshot_character("night_start"))
	if _cat("weapon"):
		_write_event("weapon", {"action": "sheet", "weapons": _snapshot_weapons()})
	if _cat("build"):
		_write_event("build", _snapshot_build("night_start"))
	if _cat("map"):
		call_deferred("_log_map_refresh", night)


func _on_night_ended(night: int) -> void:
	if not _active:
		return
	_flush_combat_buffers()
	if _cat("map"):
		_write_event("map", {
			"action": "night_end",
			"night": night,
			"active_enemies": _count_active_enemies(),
		})


func _on_day_started() -> void:
	if not _active:
		return
	_flush_combat_buffers()
	if _cat("build"):
		_write_event("build", _snapshot_build("day_start"))


func _on_game_over(reason: String) -> void:
	if not _active:
		return
	_flush_combat_buffers()
	var death: Dictionary = GameState.get_death_analysis()
	_finalize_run("death", {
		"reason": reason,
		"nights": GameState.current_night,
		"level": GameState.player_level,
		"death": death,
		"build": _snapshot_build("end"),
		"weapons": _snapshot_weapons(),
	})


func _on_game_win() -> void:
	if not _active:
		return
	_flush_combat_buffers()
	_finalize_run("win", {
		"nights": GameState.current_night,
		"level": GameState.player_level,
		"build": _snapshot_build("end"),
		"weapons": _snapshot_weapons(),
	})


func _on_level_up(new_level: int) -> void:
	if not _active or not _cat("build"):
		return
	_write_event("build", {
		"action": "level_up",
		"level": new_level,
		"exp": GameState.player_exp,
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
	})


func _on_player_damaged(amount: int) -> void:
	if not _active or not _cat("damage"):
		return
	_write_event("damage", {
		"action": "taken",
		"amount": amount,
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
		"source": GameState.get_last_hit_source(),
	})


func _on_loadout_changed() -> void:
	if not _active:
		return
	if _cat("weapon"):
		_write_event("weapon", {"action": "loadout", "weapons": _snapshot_weapons()})
	if _cat("build"):
		_write_event("build", _snapshot_build("loadout"))


func _on_player_revived(kind: String) -> void:
	if not _active or not _cat("character"):
		return
	_write_event("character", {
		"action": "revived",
		"kind": kind,
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
	})


func _on_player_down(kind: String) -> void:
	if not _active or not _cat("character"):
		return
	_write_event("character", {"action": "down", "kind": kind})


func _on_upgrade_offered(offers: Array, can_free_reroll: bool) -> void:
	if not _active or not _cat("upgrade"):
		return
	var compact: Array = []
	for o in offers:
		if o is Dictionary:
			compact.append({
				"type": String(o.get("type", "")),
				"id": String(o.get("id", "")),
				"name": String(o.get("name", "")),
			})
	_write_event("upgrade", {
		"action": "offered",
		"level": GameState.player_level,
		"free_reroll": can_free_reroll,
		"offers": compact,
	})


func _on_upgrade_resolved(offer: Dictionary, is_skip: bool) -> void:
	if not _active or not _cat("upgrade"):
		return
	_write_event("upgrade", {
		"action": "skip" if is_skip else "pick",
		"level": GameState.player_level,
		"type": String(offer.get("type", "")),
		"id": String(offer.get("id", "")),
		"name": String(offer.get("name", "")),
		"build": _snapshot_build("after_upgrade") if not is_skip else {},
	})


func _on_event_armed(event_id: String, event_name: String, for_night: int) -> void:
	if not _active or not _cat("event"):
		return
	_write_event("event", {
		"action": "armed",
		"id": event_id,
		"name": event_name,
		"for_night": for_night,
	})


func _on_evolved(weapon_id: String, evolved_name: String) -> void:
	if not _active or not (_cat("evolution") or _cat("build")):
		return
	_write_event("evolution", {
		"action": "fuse",
		"weapon_id": weapon_id,
		"evolved_name": evolved_name,
		"items_left": GameState.evolution_items,
	})


func _on_refined(weapon_id: String, tier: int, path_name: String) -> void:
	if not _active or not (_cat("refine") or _cat("build")):
		return
	_write_event("refine", {
		"action": "refine",
		"weapon_id": weapon_id,
		"tier": tier,
		"path": path_name,
		"essence": GameState.refine_essence,
	})


func _on_chest_opened(kind: String, amount: int, rarity_name: String) -> void:
	if not _active or not _cat("chest"):
		return
	var pos: Vector2 = Vector2.ZERO
	var world: World = _current_world()
	if world != null and world.player != null:
		pos = world.player.global_position
	_write_event("chest", {
		"action": "open",
		"kind": kind,
		"amount": amount,
		"rarity": rarity_name,
		"player": _vec2(pos),
		"coins": GameState.tidecoins,
		"evo_items": GameState.evolution_items,
	})


func _on_purchase_made(item: Dictionary) -> void:
	if not _active or not _cat("shop"):
		return
	_write_event("shop", {
		"action": "buy",
		"id": String(item.get("id", "")),
		"name": String(item.get("name", "")),
		"kind": String(item.get("kind", "")),
		"cost": int(item.get("cost", 0)),
		"coins": GameState.tidecoins,
		"build": _snapshot_build("after_shop"),
	})


# ============================================================================
# 局生命周期
# ============================================================================

func _begin_run(character: String, seed_value: int) -> void:
	_finalize_run("aborted", {"reason": "superseded"})
	_run_started_unix = int(Time.get_unix_time_from_system())
	# use_space=false → YYYY-MM-DDTHH:MM:SS，再压成无空格文件名
	var stamp: String = Time.get_datetime_string_from_unix_time(_run_started_unix, false)
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	_run_id = "run_%s_s%d" % [stamp, seed_value]
	_run_path = _dir.path_join("%s.jsonl" % _run_id)
	_t0_msec = Time.get_ticks_msec()
	_dealt_buf.clear()
	_kill_buf.clear()
	_spawn_budget_n = 0
	_spawn_floor_n = 0
	_move_accum = 0.0
	_dealt_flush_accum = 0.0
	_file = FileAccess.open(_run_path, FileAccess.WRITE)
	if _file == null:
		push_error("[CombatLog] 无法创建: %s (err=%d)" % [_run_path, FileAccess.get_open_error()])
		_active = false
		return
	_active = true
	_register_telemetry()
	_write_event("run", {
		"action": "start",
		"run_id": _run_id,
		"character": character,
		"seed": str(seed_value),
		"max_hp": GameState.player_max_health,
		"bot": TestBot.is_active() if TestBot != null else false,
		"started_at": Time.get_datetime_string_from_unix_time(_run_started_unix, true),
	})
	if _cat("character"):
		_write_event("character", _snapshot_character("run_start"))
	if _cat("weapon"):
		_write_event("weapon", {"action": "sheet", "weapons": _snapshot_weapons()})
	if _cat("build"):
		_write_event("build", _snapshot_build("run_start"))
	_index_add_pending()
	_try_bind_world_hooks()
	_flush_file()
	print("[CombatLog] 开局落盘 %s" % _run_path)


func _finalize_run(outcome: String, summary: Dictionary) -> void:
	if not _active:
		return
	_flush_combat_buffers()
	summary = summary.duplicate(true)
	summary["action"] = "end"
	summary["outcome"] = outcome
	summary["run_id"] = _run_id
	summary["elapsed_sec"] = snappedf(float(Time.get_ticks_msec() - _t0_msec) / 1000.0, 0.01)
	summary["ended_at"] = Time.get_datetime_string_from_system(true)
	_write_event("run", summary)
	_flush_file()
	if _file != null:
		_file.close()
		_file = null
	_index_finalize(_run_id, _run_path, outcome, int(summary.get("nights", GameState.current_night)))
	_prune_old_runs()
	print("[CombatLog] 局结束 outcome=%s path=%s" % [outcome, _run_path])
	_active = false
	_unregister_telemetry()
	_run_id = ""
	_run_path = ""


# ============================================================================
# 快照 / 采样
# ============================================================================

func _snapshot_character(phase: String) -> Dictionary:
	return {
		"action": "snapshot",
		"phase": phase,
		"character": GameState.current_character,
		"level": GameState.player_level,
		"exp": GameState.player_exp,
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
		"coins": GameState.tidecoins,
		"evo_items": GameState.evolution_items,
		"refine_essence": GameState.refine_essence,
		"seed": str(GameState.run_seed),
		"night": GameState.current_night,
	}


func _snapshot_weapons() -> Array:
	var out: Array = []
	for wid_v in GameState.weapon_slots:
		var wid: String = String(wid_v)
		out.append({
			"id": wid,
			"lv": GameState.get_weapon_level(wid),
			"evo": GameState.is_weapon_evolved(wid),
			"evo_name": GameState.get_evolved_name(wid) if GameState.is_weapon_evolved(wid) else "",
			"refine": GameState.get_refine_tier(wid),
		})
	return out


func _snapshot_build(phase: String) -> Dictionary:
	var passives: Array = []
	for pid_v in GameState.passive_slots:
		var pid: String = String(pid_v)
		passives.append({"id": pid, "lv": GameState.get_passive_level(pid)})
	return {
		"action": "snapshot",
		"phase": phase,
		"level": GameState.player_level,
		"weapons": _snapshot_weapons(),
		"passives": passives,
		"dmg_m": snappedf(PassiveSystem.get_damage_mult() * MetaSystem.get_damage_mult(), 0.01),
		"atk_m": snappedf(
			PassiveSystem.get_attack_speed_mult() * EventSystem.get_attack_speed_mult() * MetaSystem.get_attack_speed_mult(),
			0.01
		),
		"dr": snappedf(PassiveSystem.get_damage_reduction(), 0.01),
		"crit": snappedf(PassiveSystem.get_crit_chance(), 0.01),
		"area_m": snappedf(PassiveSystem.get_area_mult() * MetaSystem.get_area_mult(), 0.01),
		"cd_r": snappedf(PassiveSystem.get_cd_reduction(), 0.01),
		"exp_m": snappedf(
			PassiveSystem.get_exp_mult() * EventSystem.get_exp_mult() * MetaSystem.get_exp_mult(),
			0.01
		),
	}


func _sample_movement() -> void:
	var world: World = _current_world()
	if world == null or world.player == null:
		return
	var player: Player = world.player as Player
	if player == null:
		return
	_write_event("movement", {
		"action": "sample",
		"pos": _vec2(player.global_position),
		"spd": snappedf(player.get_current_speed(), 1.0),
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
		"active_enemies": _count_active_enemies(),
	})


func _log_map_refresh(night: int) -> void:
	if not _active or not _cat("map"):
		return
	var pincer: bool = EventSystem.is_event_pincer()
	var active_event: String = EventSystem.get_active_event_id()
	var candidate_n: int = _count_active_enemies()
	_write_event("map", {
		"action": "night_refresh",
		"night": night,
		"event": active_event,
		"event_name": EventSystem.get_active_event_name(),
		"pincer": pincer,
		"active_enemies": candidate_n,
	})


func _flush_combat_buffers() -> void:
	_flush_dealt_buf()
	_flush_kill_buf()
	_flush_file()


func _flush_dealt_buf() -> void:
	if not _active or _dealt_buf.is_empty() or not _cat("damage"):
		return
	var rows: Array = []
	var ids: Array = _dealt_buf.keys()
	ids.sort()
	var total: int = 0
	var hits: int = 0
	for wid_v in ids:
		var wid: String = String(wid_v)
		var row: Dictionary = _dealt_buf[wid]
		var dealt: int = int(row.get("dealt", 0))
		var h: int = int(row.get("hits", 0))
		total += dealt
		hits += h
		rows.append({"id": wid, "dealt": dealt, "hits": h})
	_dealt_buf.clear()
	_write_event("damage", {
		"action": "dealt_agg",
		"total": total,
		"hits": hits,
		"by_weapon": rows,
	})


func _flush_kill_buf() -> void:
	if not _active or _kill_buf.is_empty() or not _cat("monster"):
		return
	var keys: Array = _kill_buf.keys()
	keys.sort()
	var rows: Array = []
	var killed_total: int = 0
	for key_v in keys:
		var row: Dictionary = _kill_buf[key_v]
		var k: int = int(row.get("killed", 0))
		killed_total += k
		var dn: int = int(row.get("ddist_n", 0))
		rows.append({
			"id": String(row.get("id", "?")),
			"tier": String(row.get("tier", "normal")),
			"affix": String(row.get("affix", "-")),
			"killed": k,
			"avg_alive": snappedf((float(row.get("alive_sum", 0.0)) / float(k)) if k > 0 else 0.0, 0.1),
			"avg_ddist": snappedf((float(row.get("ddist_sum", 0.0)) / float(dn)) if dn > 0 else -1.0, 1.0),
		})
	_kill_buf.clear()
	_write_event("monster", {
		"action": "death_agg",
		"killed_total": killed_total,
		"by_enemy": rows,
	})


# ============================================================================
# 索引 / 裁剪
# ============================================================================

func _index_path() -> String:
	return _dir.path_join(INDEX_NAME)


func _load_index() -> Dictionary:
	var path: String = _index_path()
	if not FileAccess.file_exists(path):
		return {"version": 1, "runs": []}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return {"version": 1, "runs": []}
	var d: Dictionary = parsed as Dictionary
	if not d.has("runs") or not (d["runs"] is Array):
		d["runs"] = []
	d["version"] = 1
	return d


func _save_index(index: Dictionary) -> void:
	var path: String = _index_path()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[CombatLog] 无法写索引: %s" % path)
		return
	file.store_string(JSON.stringify(index, "\t"))
	file.close()


func _index_add_pending() -> void:
	var index: Dictionary = _load_index()
	var runs: Array = index.get("runs", [])
	runs.append({
		"id": _run_id,
		"path": _run_path,
		"started_at": Time.get_datetime_string_from_unix_time(_run_started_unix, true),
		"outcome": "in_progress",
		"nights": 0,
		"character": GameState.current_character,
		"seed": str(GameState.run_seed),
	})
	index["runs"] = runs
	_save_index(index)


func _index_finalize(run_id: String, path: String, outcome: String, nights: int) -> void:
	var index: Dictionary = _load_index()
	var runs: Array = index.get("runs", [])
	var found: bool = false
	for i in runs.size():
		var row: Dictionary = runs[i]
		if String(row.get("id", "")) == run_id:
			row["outcome"] = outcome
			row["nights"] = nights
			row["path"] = path
			row["ended_at"] = Time.get_datetime_string_from_system(true)
			runs[i] = row
			found = true
			break
	if not found:
		runs.append({
			"id": run_id,
			"path": path,
			"outcome": outcome,
			"nights": nights,
			"ended_at": Time.get_datetime_string_from_system(true),
		})
	index["runs"] = runs
	_save_index(index)


func _prune_old_runs() -> void:
	var index: Dictionary = _load_index()
	var runs: Array = index.get("runs", [])
	if runs.size() > _max_runs:
		var remove_n: int = runs.size() - _max_runs
		for i in range(remove_n):
			var row: Dictionary = runs[i]
			var p: String = String(row.get("path", ""))
			if p != "" and FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		var kept: Array = []
		for i in range(remove_n, runs.size()):
			kept.append(runs[i])
		index["runs"] = kept
		_save_index(index)
		print("[CombatLog] 已裁剪旧局 ×%d，保留最近 %d" % [remove_n, _max_runs])
	_prune_orphan_files(index.get("runs", []) as Array)


## 删除目录内不在索引中的 run_*.jsonl（含历史坏名/崩溃残留）
func _prune_orphan_files(kept_runs: Array) -> void:
	var keep_names: Dictionary = {}
	keep_names[INDEX_NAME] = true
	for row_v in kept_runs:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var p: String = String(row.get("path", "")).replace("\\", "/")
		var rid: String = String(row.get("id", ""))
		if p != "":
			keep_names[p.get_file()] = true
		if rid != "":
			keep_names["%s.jsonl" % rid] = true
	var da: DirAccess = DirAccess.open(_dir)
	if da == null:
		return
	var removed: int = 0
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.begins_with("run_") and fname.ends_with(".jsonl"):
			if not keep_names.has(fname):
				if da.remove(fname) == OK:
					removed += 1
		fname = da.get_next()
	da.list_dir_end()
	if removed > 0:
		print("[CombatLog] 已清理孤儿日志 ×%d" % removed)


# ============================================================================
# 工具
# ============================================================================

func _reload_config() -> void:
	_cfg = ConfigLoader.get_combat_log_config()
	if _cfg.is_empty():
		_cfg = {
			"enabled": true,
			"debug_only": true,
			"max_runs": DEFAULT_MAX_RUNS,
			"dir": DEFAULT_DIR,
			"skip_headless": true,
			"skip_test_scenes": true,
			"movement_interval_sec": 2.0,
			"damage_dealt_flush_sec": 5.0,
			"spawn_sample": {"elite_boss_always": true, "budget_cap": 12, "floor_every": 40},
			"death_sample": {"elite_boss_detail": true, "aggregate_normal": true},
			"categories": {},
		}
	_enabled = bool(_cfg.get("enabled", true))
	_debug_only = bool(_cfg.get("debug_only", true))
	_max_runs = maxi(1, int(_cfg.get("max_runs", DEFAULT_MAX_RUNS)))
	_dir = _sanitize_log_dir(String(_cfg.get("dir", DEFAULT_DIR)))
	_categories = _cfg.get("categories", {}) as Dictionary
	_movement_interval = maxf(0.25, float(_cfg.get("movement_interval_sec", 2.0)))
	_damage_flush_interval = maxf(1.0, float(_cfg.get("damage_dealt_flush_sec", 5.0)))
	var spawn_cfg: Dictionary = _cfg.get("spawn_sample", {}) as Dictionary
	_spawn_elite_always = bool(spawn_cfg.get("elite_boss_always", true))
	_spawn_budget_cap = maxi(0, int(spawn_cfg.get("budget_cap", 12)))
	_spawn_floor_every = maxi(1, int(spawn_cfg.get("floor_every", 40)))
	var death_cfg: Dictionary = _cfg.get("death_sample", {}) as Dictionary
	_death_elite_detail = bool(death_cfg.get("elite_boss_detail", true))
	_death_agg_normal = bool(death_cfg.get("aggregate_normal", true))


## 日志目录必须落在 user://，否则回退默认
func _sanitize_log_dir(raw: String) -> String:
	var d: String = raw.strip_edges().replace("\\", "/")
	if not d.begins_with("user://"):
		push_warning("[CombatLog] dir 必须为 user://，已回退 %s（原=%s）" % [DEFAULT_DIR, raw])
		d = DEFAULT_DIR
	if not d.ends_with("/"):
		d += "/"
	return d


func _ensure_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _cat(name: String) -> bool:
	if _categories.is_empty():
		return true
	return bool(_categories.get(name, true))


## debug_only + headless：启动时决定是否接线；开局再判 scene
func _passes_runtime_gate() -> bool:
	if _debug_only and not OS.is_debug_build() and not OS.has_feature("editor"):
		return false
	if bool(_cfg.get("skip_headless", true)) and DisplayServer.get_name() == "headless":
		return false
	return true


func _should_skip_environment() -> bool:
	return not _passes_runtime_gate()


func _should_skip_scene() -> bool:
	if not bool(_cfg.get("skip_test_scenes", true)):
		return false
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return false
	var path: String = String(tree.current_scene.scene_file_path)
	return path.contains("/tests/") or path.contains("\\tests\\")


func _register_telemetry() -> void:
	if _telemetry_registered:
		return
	EnemyBase.add_combat_telemetry(self)
	_telemetry_registered = true


func _unregister_telemetry() -> void:
	if not _telemetry_registered:
		return
	EnemyBase.remove_combat_telemetry(self)
	_telemetry_registered = false


func _flush_file() -> void:
	if _file != null:
		_file.flush()


func _write_event(cat: String, data: Dictionary) -> void:
	if not _active or _file == null:
		return
	var payload: Dictionary = {
		"t": snappedf(float(Time.get_ticks_msec() - _t0_msec) / 1000.0, 0.01),
		"night": GameState.current_night,
		"day": GameState.is_day_phase,
		"cat": cat,
		"data": data,
	}
	_file.store_line(JSON.stringify(payload))


func _try_bind_world_hooks() -> void:
	var world: World = _current_world()
	if world == null:
		return
	if world.pickup_system != null and not _chest_connected:
		if not world.pickup_system.chest_opened.is_connected(_on_chest_opened):
			world.pickup_system.chest_opened.connect(_on_chest_opened)
		_chest_connected = true
	if world.shop_manager != null and not _shop_connected:
		if not world.shop_manager.purchase_made.is_connected(_on_purchase_made):
			world.shop_manager.purchase_made.connect(_on_purchase_made)
		_shop_connected = true


func _current_world() -> World:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene as World


func _count_active_enemies() -> int:
	var world: World = _current_world()
	if world == null or world.enemy_spawner == null or world.enemy_spawner.enemy_pool == null:
		return 0
	var n: int = 0
	for node in world.enemy_spawner.enemy_pool.get_active():
		var e: EnemyBase = node as EnemyBase
		if e != null and not e.is_dead():
			n += 1
	return n


func _should_log_spawn(enemy: EnemyBase) -> bool:
	if _spawn_elite_always and (enemy.is_boss or enemy.is_elite):
		return true
	if enemy.is_floor_refill:
		_spawn_floor_n += 1
		return (_spawn_floor_n <= 2) or (_spawn_floor_n % _spawn_floor_every == 0)
	_spawn_budget_n += 1
	return _spawn_budget_n <= _spawn_budget_cap


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


func _vec2(v: Vector2) -> Dictionary:
	return {"x": snappedf(v.x, 1.0), "y": snappedf(v.y, 1.0)}
