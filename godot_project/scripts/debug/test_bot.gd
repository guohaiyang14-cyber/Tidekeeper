# ============================================================================
# TestBot — Debug 模式自动试玩机器人
# 职责：debug.bat（--debug）启动时模拟玩家：选角开局、夜间走位拾取、
#       三选一/商店/结算自动推进，便于无人值守冒烟试玩。
# 红线：仅 debug 启动且非 headless/单测场景；不修改 GameState 数值逻辑。
# 倍速：启用时 Engine.time_scale ∈ [2,10]（默认 4；--bot-speed=N / [ ] 调节）
# 局外：每局随机/指定灯塔树初始状态（会话覆盖，不写存档）
#       --bot-lighthouse=none|partial|full|random|cycle|sweep（默认 random）
#       cycle=串行 none→partial→full 循环；sweep=扫完一轮后 quit
#       --bot-runs-per-config=N（默认 1；每种配置连跑 N 局再切下一档）
# 验收任务（对齐 docs/原型验证验收清单.md / docs/TestBot验收任务.md）：
#       --bot-suite=smoke|crash|full|meta|acceptance
#       --bot-character=watcher|blacksmith|stargazer|cycle|random
#       --bot-difficulty=lighthouse|watcher|cycle
#       --bot-max-night=N（0=不截断；到 N 夜昼后计完成并重开）
#       --bot-max-runs=N（0=不限；完成 N 局后 quit）
# ============================================================================
extends Node

const MAIN_SCENE: String = "res://scenes/main.tscn"
const CHAR_SELECT_SCENE: String = "res://scenes/character_select.tscn"

const UI_ACTION_DELAY: float = 0.55
const CHAR_SELECT_DELAY: float = 0.9
const RESULT_RESTART_DELAY: float = 1.1
const SHOP_DWELL: float = 1.8
const MAX_NIGHT_CUTOFF_DELAY: float = 0.35

## 机器人试玩墙钟加速（非玩法数值；仅 Debug Bot）
const BOT_SPEED_MIN: float = 2.0
const BOT_SPEED_MAX: float = 10.0
const BOT_SPEED_DEFAULT: float = 4.0

## 合法 --bot-lighthouse / TIDEKEEPER_BOT_LIGHTHOUSE 取值
const LH_MODE_VALUES: Array[String] = ["none", "partial", "full", "random", "cycle", "sweep"]
## 串行扫档顺序（cycle / sweep）
const LH_SERIAL_PROFILES: Array[String] = ["none", "partial", "full"]
const BOT_RUNS_PER_CONFIG_DEFAULT: int = 1

# 夜间走位（仅 Debug 机器人；非玩法数值表）
# N15 执政官：潮汐波在灯塔光晕外受伤（bosses.json aura_radius）；远距风筝=吃波致死。
const ORBIT_SPEED: float = 1.85
const STRUGGLE_HUNT_RADIUS: float = 520.0
const STRUGGLE_SAFE_ELITE: float = 420.0
const STRUGGLE_SAFE_THORNS: float = 140.0
const ELITE_SCAN_RADIUS: float = 1000.0
const BOSS_SCAN_RADIUS: float = 1400.0
const ELITE_MIN_DIST_N5: float = 560.0
const ELITE_MIN_DIST: float = 300.0
## 锁链精英：被打会减速，需拉得更开（夜结束靠计时，不强制击杀精英）
const ELITE_MIN_DIST_CHAIN: float = 680.0
## Boss / 非执政官天灾：拉开距离（N10 水母后等）
const BOSS_MIN_DIST: float = 780.0
const BOSS_MIN_DIST_CALAMITY: float = 920.0
## N15 执政官：光晕内环绕（对齐 metadata.lighthouse.aura_radius；勿用远距风筝）
const ARCHON_AURA_STAY_RATIO: float = 0.78
const ARCHON_AURA_HARD_RATIO: float = 0.92
const ARCHON_PREF_RING_RATIO: float = 0.52
const ARCHON_BOSS_SOFT_DIST: float = 78.0
const ARCHON_ORBIT_SPEED: float = 2.55
## 执政官夜捡箱：光晕内 Boss 常在，禁用 CHEST_SAFE_BOSS=720；仅拒脚下/贴脸
const ARCHON_CHEST_SAFE_ENEMY: float = 70.0
const ARCHON_CHEST_SAFE_BOSS: float = 55.0
## N4 起深潜者登场：扩大逃离半径（不必等到 N5）
const FLEE_RADIUS_N4: float = 420.0
const FLEE_RADIUS_N5: float = 540.0
const FLEE_RADIUS_CALAMITY: float = 640.0
const FLEE_RADIUS: float = 260.0
const DANGER_HP_RATIO: float = 0.90
const CHEST_SEEK_RANGE: float = 420.0
const CHEST_SAFE_ENEMY: float = 110.0
const CHEST_SAFE_ELITE: float = 420.0
const CHEST_SAFE_BOSS: float = 720.0
const GEM_SEEK_RANGE: float = 360.0
const GEM_SAFE_ENEMY: float = 80.0
const GEM_SAFE_ELITE: float = 360.0
const ELITE_FLEE_WEIGHT: float = 6.5
const BOSS_FLEE_WEIGHT: float = 9.5
const SWIFT_FLEE_WEIGHT: float = 2.4
const CHAIN_FLEE_WEIGHT: float = 2.8
const BURROW_FLEE_WEIGHT: float = 4.0
## 自爆怪（爆炸贝）逃离权重：日志常见收尾死因
const BOMB_FLEE_WEIGHT: float = 3.4
## 贴脸/突袭后锁定逃跑方向，避免轨道掉头又撞回去
const PANIC_STICK_SEC: float = 1.15
const PANIC_CONTACT_DIST: float = 52.0
const BURROW_SCAN_RADIUS: float = 720.0
const PROJ_LOOK: float = 280.0
const PROJ_LOOK_CALAMITY: float = 400.0
## 弹幕逃离向量长度²超过此值：优先闪避（可触发短恐慌，避免捡箱/珠）
const PROJ_DANGER_LEN_SQ: float = 0.42
const PROJ_PANIC_LEN_SQ: float = 1.15
const THORNS_FLEE_WEIGHT: float = 5.2
## 对齐 config/enemies.json → metadata.affix_rules.calamity_nights（Bot 不读表，改夜次须同步）
const CALAMITY_NIGHTS: Array[int] = [10, 15, 20]
## 第 15 夜执政官（潮汐波光晕机制；与 bosses.json tide_archon.night 对齐）
const ARCHON_NIGHT: int = 15
## 第 3 夜昼起囤减伤（N4 深潜者 / N5 精英前）
const SURVIVAL_BIAS_FROM_NIGHT: int = 3
## 三选一潮汐币启发式门槛（Debug Bot；非玩法数值表）
const COINS_BROKE: int = 80
const COINS_LOW: int = 100
const COINS_MID: int = 250
const COINS_OK: int = 450
const COINS_RICH: int = 900
const COINS_CALAMITY_WANT: int = 380
const COINS_ARCHON_WANT: int = 450
const COINS_EVO_WANT: int = 520
## 危血 heal 须压过 _evolution_build_boost 上限（钥被动满级约 210）
const HEAL_CRITICAL_SCORE: int = 220
const HEAL_CRITICAL_HP_RATIO: float = 0.40

const _BotCombatStats = preload("res://scripts/debug/bot_combat_stats.gd")
const _BotSuite = preload("res://scripts/debug/bot_suite.gd")

var _enabled: bool = false
var _action_timer: float = 0.0
var _char_select_started: bool = false
var _orbit_angle: float = 0.0
## 上一帧有效移动方向（贴脸 dist≈0 时作逃离基准）
var _last_move_dir: Vector2 = Vector2.RIGHT
var _panic_timer: float = 0.0
var _panic_dir: Vector2 = Vector2.RIGHT
## BotCombatStats（preload.new）；不写 class_name 注解以免 autoload 启动时类型未注册
var _combat_stats: Variant = null
## 当前倍速（仅 _enabled 时写入 Engine.time_scale）
var _speed_scale: float = BOT_SPEED_DEFAULT
## 串行档：当前下标 / 本档已完赛局数 / 每档连跑数 / sweep 是否已扫完待退出
var _serial_index: int = 0
var _serial_runs_on_profile: int = 0
var _runs_per_config: int = BOT_RUNS_PER_CONFIG_DEFAULT
var _sweep_pending_quit: bool = false
## 本局是否已推进串行（game_over/win 与结算页双入口幂等）
var _serial_advanced_for_run: bool = false
## 验收 suite（空=无预设，兼容旧行为）
var _suite_name: String = ""
var _character_mode: String = "auto"
var _difficulty_mode: String = "auto"
var _max_night: int = 0
var _max_runs: int = 0
var _unlock_all_chars: bool = false
var _char_cycle_index: int = 0
var _diff_cycle_index: int = 0
var _completed_runs: int = 0
var _runs_reached_n8: int = 0
var _runs_reached_n10: int = 0
var _wins: int = 0
var _run_peak_night: int = 0
var _move_speed_checked: bool = false
var _refine_clicked: bool = false
var _cutoff_restart_pending: bool = false
var _run_outcome_recorded: bool = false
var _accept_pass: Dictionary = {}
var _accept_fail: Dictionary = {}
var _suite_checklist: Array[String] = []
## suite 强制的灯塔模式（非空时优先于 random 默认，仍可被 CLI 覆盖）
var _forced_lighthouse_mode: String = ""
## ACCEPT_SUMMARY 只打一次（quit 与 _exit_tree 双入口）
var _summary_printed: bool = false
## 本会话已校验过的夜长（秒→已打 ACCEPT），避免每夜刷屏
var _duration_checked: Dictionary = {}
## godot.log 扫描偏移 + SCRIPT ERROR 计数（5.2 辅助）
var _log_scan_offset: int = 0
var _script_error_count: int = 0
var _log_scan_path: String = ""
## 近期功能 ACCEPT：软上限 / 词缀 / 荆棘 / 宝箱 / 同屏峰值（会话级）
var _soft_caps_checked: bool = false
var _affix_cfg_checked: bool = false
var _affix_cfg_ok: bool = false
var _elite_affix_checked: bool = false
var _chest_hooked_world: World = null
var _peak_enemies: int = 0
var _seen_affix_ids: Dictionary = {}
var _thorns_hits: int = 0
var _thorns_hit_max: int = 0
var _chest_kinds_seen: Dictionary = {}
var _enemy_sample_timer: float = 0.0
## 最近一次已打印的 ACCEPT（id → "status|detail"），同内容不重打
var _accept_last_emit: Dictionary = {}
## 同屏峰值 ACCEPT 下限底数（再与 max_enemies/4 取较大）
const ACCEPT_ENEMY_PEAK_FLOOR: int = 100
## 敌人/词缀采样间隔（秒，游戏时间）
const ACCEPT_ENEMY_SAMPLE_INTERVAL: float = 0.5
## 宝箱开箱视为有效奖励的 kind（对齐 pickups.json.chest.rewards）
const ACCEPT_CHEST_KINDS: Array[String] = ["tidecoins", "heal", "evolution", "refine_essence"]


func _ready() -> void:
	_enabled = _compute_enabled()
	if _enabled:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_combat_stats = _BotCombatStats.new()
		## TestBot 启停：用 add/remove，避免清掉 CombatLog 遥测
		EnemyBase.add_combat_telemetry(self)
		_apply_suite_config()
		_speed_scale = _resolve_initial_speed()
		_runs_per_config = _resolve_runs_per_config()
		_serial_index = 0
		_serial_runs_on_profile = 0
		_sweep_pending_quit = false
		_serial_advanced_for_run = false
		_summary_printed = false
		_soft_caps_checked = false
		_affix_cfg_checked = false
		_affix_cfg_ok = false
		_elite_affix_checked = false
		_peak_enemies = 0
		_seen_affix_ids.clear()
		_thorns_hits = 0
		_thorns_hit_max = 0
		_chest_kinds_seen.clear()
		_accept_last_emit.clear()
		_init_script_error_scan()
		_apply_speed_scale()
		if _suite_name != "" and not GameState.player_damaged.is_connected(_on_player_damaged_accept):
			GameState.player_damaged.connect(_on_player_damaged_accept)
		print(
			"[TestBot] 已启用 — 自动模拟玩家 ×%.0f（[ / ] 调速 2~10；关闭：TIDEKEEPER_NO_TEST_BOT=1 或 --no-test-bot）"
			% _speed_scale
		)
		if _suite_name != "":
			print(
				"[TestBot] 验收套件 suite=%s character=%s difficulty=%s max_night=%d max_runs=%d unlock_all=%s checklist=%s"
				% [
					_suite_name,
					_character_mode,
					_difficulty_mode,
					_max_night,
					_max_runs,
					str(_unlock_all_chars),
					",".join(_suite_checklist),
				]
			)
		var lh_mode: String = _resolve_lighthouse_mode()
		print(
			"[TestBot] 灯塔模式 mode=%s（--bot-lighthouse=none|partial|full|random|cycle|sweep）"
			% lh_mode
		)
		if _is_serial_lighthouse_mode(lh_mode):
			print(
				"[TestBot] 串行扫档 order=none→partial→full runs_per_config=%d%s"
				% [_runs_per_config, "（sweep 一轮后退出）" if lh_mode == "sweep" else "（cycle 循环）"]
			)
		get_tree().scene_changed.connect(_on_scene_changed)
		GameState.night_started.connect(_on_night_started)
		GameState.night_ended.connect(_on_night_ended)
		GameState.game_over.connect(_on_game_over_stats)
		GameState.game_win.connect(_on_game_win_stats)
		_reset_scene_timers()
	else:
		EnemyBase.remove_combat_telemetry(self)
		process_mode = Node.PROCESS_MODE_DISABLED


func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	EnemyBase.remove_combat_telemetry(self)
	if GameState.player_damaged.is_connected(_on_player_damaged_accept):
		GameState.player_damaged.disconnect(_on_player_damaged_accept)
	_disconnect_chest_hook()
	if _enabled:
		MetaSystem.clear_lighthouse_override()
		MetaSystem.clear_unlock_all_characters_override()
		_print_accept_summary()


func is_active() -> bool:
	return _enabled


## 当前试玩倍速（未启用时恒为 1）
func get_speed_scale() -> float:
	return _speed_scale if _enabled else 1.0


## 武器命中记账（EnemyBase 静态遥测调用；非 Bot 时不应被注册）
func note_damage(source_id: String, amount: int) -> void:
	if _combat_stats == null:
		return
	_combat_stats.record_damage(source_id, amount)


## 敌人死亡记账
func note_enemy_death(enemy: EnemyBase) -> void:
	if _combat_stats == null:
		return
	_combat_stats.record_enemy_death(enemy)


## 敌人刷出记账（位置样例 + 刷点距离）
func note_enemy_spawn(enemy: EnemyBase) -> void:
	if _combat_stats == null:
		return
	_combat_stats.record_enemy_spawn(enemy)


func _on_night_started(night: int) -> void:
	_panic_timer = 0.0
	_enemy_sample_timer = 0.0
	_run_peak_night = maxi(_run_peak_night, night)
	if night == ARCHON_NIGHT:
		print(
			"[TestBot] N%d 执政官策略：贴灯塔光晕内环绕（aura=%.0f）"
			% [night, _lighthouse_aura_radius()]
		)
	_accept_on_night_start(night)
	if _combat_stats == null:
		return
	_combat_stats.begin_night(night, _current_world())


func _on_night_ended(night: int) -> void:
	_run_peak_night = maxi(_run_peak_night, night)
	if _combat_stats != null:
		_combat_stats.end_night(night, _current_world())
	if _suite_name != "":
		_accept_sample_enemies(_current_world())
	_accept_on_night_end(night)
	if _max_night > 0 and night >= _max_night:
		_cutoff_restart_pending = true
		_action_timer = MAX_NIGHT_CUTOFF_DELAY


func _on_game_over_stats(_reason: String) -> void:
	if _combat_stats != null:
		_combat_stats.flush_open_night(_current_world())
	_note_serial_run_finished()
	_finalize_run_outcome(false)


func _on_game_win_stats() -> void:
	if _combat_stats != null:
		_combat_stats.flush_open_night(_current_world())
	_note_serial_run_finished()
	_wins += 1
	_record_accept("2.5.3", "pass", "win_n20")
	_record_accept("4.10.1", "pass", "full_clear_proxy")
	_finalize_run_outcome(true)


func _current_world() -> World:
	return get_tree().current_scene as World


func _compute_enabled() -> bool:
	if OS.has_environment("TIDEKEEPER_NO_TEST_BOT"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	if _has_cmdline_flag("--no-test-bot"):
		return false
	if _has_cmdline_flag("--test-bot"):
		return true
	return _has_cmdline_flag("--debug")


func _has_cmdline_flag(flag: String) -> bool:
	for arg in OS.get_cmdline_args():
		if arg == flag:
			return true
	return false


func _resolve_initial_speed() -> float:
	var from_cli: float = _parse_bot_speed_arg()
	if from_cli > 0.0:
		return clampf(roundf(from_cli), BOT_SPEED_MIN, BOT_SPEED_MAX)
	if OS.has_environment("TIDEKEEPER_BOT_SPEED"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_SPEED").strip_edges()
		if env_raw.is_valid_float():
			return clampf(roundf(env_raw.to_float()), BOT_SPEED_MIN, BOT_SPEED_MAX)
	return BOT_SPEED_DEFAULT


func _parse_bot_speed_arg() -> float:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		var arg: String = args[i]
		if arg.begins_with("--bot-speed="):
			var raw: String = arg.substr("--bot-speed=".length()).strip_edges()
			if raw.is_valid_float():
				return raw.to_float()
			return -1.0
		if arg == "--bot-speed" and i + 1 < args.size():
			var next_raw: String = String(args[i + 1]).strip_edges()
			if next_raw.is_valid_float():
				return next_raw.to_float()
			return -1.0
	return -1.0


func _apply_speed_scale() -> void:
	if _enabled:
		Engine.time_scale = _speed_scale
	else:
		Engine.time_scale = 1.0


func _set_speed_scale(value: float) -> void:
	var clamped: float = clampf(roundf(value), BOT_SPEED_MIN, BOT_SPEED_MAX)
	if is_equal_approx(clamped, _speed_scale) and is_equal_approx(Engine.time_scale, clamped):
		return
	_speed_scale = clamped
	_apply_speed_scale()
	print("[TestBot] 倍速 ×%.0f（[ / ] 调节，--bot-speed=N）" % _speed_scale)


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_BRACKETRIGHT, KEY_EQUAL:
			_set_speed_scale(_speed_scale + 1.0)
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT, KEY_MINUS:
			_set_speed_scale(_speed_scale - 1.0)
			get_viewport().set_input_as_handled()


func _on_scene_changed() -> void:
	_char_select_started = false
	_reset_scene_timers()
	_release_move_actions()
	_panic_timer = 0.0
	# World 首帧 scene_changed 可能晚于 night_started：不可在此 reset，否则夜 1 开局统计被清掉
	if _combat_stats != null and _is_char_select_scene():
		_combat_stats.reset_run()


func _reset_scene_timers() -> void:
	_action_timer = CHAR_SELECT_DELAY if _is_char_select_scene() else UI_ACTION_DELAY


func _process(delta: float) -> void:
	if not _enabled:
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	if _is_test_scene(scene):
		return
	if _is_char_select_scene(scene):
		_tick_character_select(delta)
		return
	var world: World = scene as World
	if world == null:
		_release_move_actions()
		return
	_tick_world(world, delta)


func _is_test_scene(scene: Node) -> bool:
	var path: String = scene.scene_file_path
	return path.contains("/tests/") or path.contains("/scenes/tests/")


func _is_char_select_scene(scene: Node = null) -> bool:
	var n: Node = scene if scene != null else get_tree().current_scene
	if n == null:
		return false
	return n.scene_file_path == CHAR_SELECT_SCENE or n.name == "CharacterSelect"


func _tick_character_select(delta: float) -> void:
	_action_timer -= delta
	if _action_timer > 0.0 or _char_select_started:
		return
	_char_select_started = true
	_prepare_new_run_meta()
	var char_id: String = _pick_run_character()
	MetaSystem.set_active_character(char_id)
	_apply_lighthouse_for_new_run()
	_emit_run_start_accepts(char_id)
	print(
		"[TestBot] 选择角色 %s 难度=%s 并开始游戏"
		% [char_id, DifficultySystem.get_tier()]
	)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _pick_unlocked_character() -> String:
	return _pick_run_character()


func _pick_run_character() -> String:
	match _character_mode:
		"cycle":
			var cid: String = _BotSuite.CHAR_CYCLE[_char_cycle_index % _BotSuite.CHAR_CYCLE.size()]
			_char_cycle_index = (_char_cycle_index + 1) % _BotSuite.CHAR_CYCLE.size()
			return cid
		"random":
			var unlocked: Array[String] = MetaSystem.get_unlocked_characters()
			if unlocked.is_empty():
				return "watcher"
			return unlocked[RNG.randi_range(0, unlocked.size() - 1)]
		"watcher", "blacksmith", "stargazer":
			if MetaSystem.is_character_unlocked(_character_mode):
				return _character_mode
			push_warning("[TestBot] 角色 %s 未解锁，回落 watcher" % _character_mode)
			return "watcher"
		_:
			var fallback: String = MetaSystem.get_active_character()
			if MetaSystem.is_character_unlocked(fallback):
				return fallback
			for id in ConfigLoader.get_all_character_ids():
				var cid2: String = String(id)
				if MetaSystem.is_character_unlocked(cid2):
					return cid2
			return "watcher"


func _prepare_new_run_meta() -> void:
	_run_peak_night = 0
	_move_speed_checked = false
	_refine_clicked = false
	_cutoff_restart_pending = false
	_run_outcome_recorded = false
	_serial_advanced_for_run = false
	_elite_affix_checked = false
	if _unlock_all_chars:
		MetaSystem.set_unlock_all_characters_override(true)
	_apply_run_difficulty()


func _apply_run_difficulty() -> void:
	if _difficulty_mode == "" or _difficulty_mode == "auto":
		return
	var tier: String = _difficulty_mode
	if _difficulty_mode == "cycle":
		tier = _BotSuite.DIFF_CYCLE[_diff_cycle_index % _BotSuite.DIFF_CYCLE.size()]
		_diff_cycle_index = (_diff_cycle_index + 1) % _BotSuite.DIFF_CYCLE.size()
	DifficultySystem.set_tier(tier, false)
	_record_accept("4.8.1", "pass", "tier=%s" % tier)


## 每局开局前：随机/指定/串行灯塔树初始状态（会话覆盖，不写存档）
func _apply_lighthouse_for_new_run() -> void:
	_serial_advanced_for_run = false
	var mode: String = _resolve_lighthouse_mode()
	var profile: String = mode
	if _is_serial_lighthouse_mode(mode):
		profile = _current_serial_profile()
	elif mode == "random":
		# 等权：无升级 / 部分 / 全满
		match RNG.randi_range(0, 2):
			0:
				profile = "none"
			1:
				profile = "full"
			_:
				profile = "partial"
	var depths: Dictionary = _roll_lighthouse_depths(profile)
	var purchased: Dictionary = _build_lighthouse_purchased(depths)
	MetaSystem.set_lighthouse_override(purchased)
	var lit: int = 0
	for nid in purchased.keys():
		if bool(purchased[nid]):
			lit += 1
	var total: int = ConfigLoader.get_all_lighthouse_nodes().size()
	var vigil: int = int(depths.get("vigil", 0))
	var edge: int = int(depths.get("edge", 0))
	var tide: int = int(depths.get("tide", 0))
	if _is_serial_lighthouse_mode(mode):
		print(
			"[TestBot] 灯塔初始 profile=%s vigil=%d edge=%d tide=%d lit=%d/%d | serial=%d/%d run=%d/%d mode=%s"
			% [
				profile,
				vigil,
				edge,
				tide,
				lit,
				total,
				_serial_index + 1,
				LH_SERIAL_PROFILES.size(),
				_serial_runs_on_profile + 1,
				_runs_per_config,
				mode,
			]
		)
	else:
		print(
			"[TestBot] 灯塔初始 profile=%s vigil=%d edge=%d tide=%d lit=%d/%d"
			% [profile, vigil, edge, tide, lit, total]
		)


func _resolve_lighthouse_mode() -> String:
	var from_cli: String = _parse_bot_lighthouse_arg()
	if from_cli != "":
		return from_cli
	if OS.has_environment("TIDEKEEPER_BOT_LIGHTHOUSE"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_LIGHTHOUSE").strip_edges().to_lower()
		if env_raw in LH_MODE_VALUES:
			return env_raw
		if env_raw != "":
			push_warning("[TestBot] 非法 TIDEKEEPER_BOT_LIGHTHOUSE=%s，回落 random" % env_raw)
	if _forced_lighthouse_mode != "" and _forced_lighthouse_mode in LH_MODE_VALUES:
		return _forced_lighthouse_mode
	return "random"


func _parse_bot_lighthouse_arg() -> String:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		var arg: String = args[i]
		if arg.begins_with("--bot-lighthouse="):
			var raw: String = arg.substr("--bot-lighthouse=".length()).strip_edges().to_lower()
			if raw in LH_MODE_VALUES:
				return raw
			push_warning("[TestBot] 非法 --bot-lighthouse=%s，回落 random" % raw)
			return ""
		if arg == "--bot-lighthouse" and i + 1 < args.size():
			var next_raw: String = String(args[i + 1]).strip_edges().to_lower()
			if next_raw in LH_MODE_VALUES:
				return next_raw
			push_warning("[TestBot] 非法 --bot-lighthouse %s，回落 random" % next_raw)
			return ""
	return ""


func _is_serial_lighthouse_mode(mode: String) -> bool:
	return mode == "cycle" or mode == "sweep"


func _current_serial_profile() -> String:
	if LH_SERIAL_PROFILES.is_empty():
		return "none"
	var idx: int = clampi(_serial_index, 0, LH_SERIAL_PROFILES.size() - 1)
	return LH_SERIAL_PROFILES[idx]


## 一局结束后推进串行档（幂等：game_over/win 与结算页只计一次）
func _note_serial_run_finished() -> void:
	if not _enabled or _serial_advanced_for_run:
		return
	var mode: String = _resolve_lighthouse_mode()
	if not _is_serial_lighthouse_mode(mode):
		return
	_serial_advanced_for_run = true
	_advance_serial_after_run(mode)
	if _sweep_pending_quit:
		# 结算页缺失时也能退出；有结算页则 _tick_result 也会走到 quit
		call_deferred("_quit_after_sweep_if_pending")


func _quit_after_sweep_if_pending() -> void:
	if not _sweep_pending_quit:
		return
	print("[TestBot] 串行 sweep 完成（none→partial→full ×%d），退出" % _runs_per_config)
	_print_accept_summary()
	if get_tree() != null:
		get_tree().paused = false
		get_tree().quit()


## 一局结束后推进串行档；sweep 在最后一档跑满后置位退出
func _advance_serial_after_run(mode: String) -> void:
	_serial_runs_on_profile += 1
	if _serial_runs_on_profile < _runs_per_config:
		return
	_serial_runs_on_profile = 0
	var next_index: int = _serial_index + 1
	if next_index >= LH_SERIAL_PROFILES.size():
		if mode == "sweep":
			_sweep_pending_quit = true
			return
		next_index = 0
	_serial_index = next_index
	print(
		"[TestBot] 串行切换 → profile=%s (%d/%d)"
		% [_current_serial_profile(), _serial_index + 1, LH_SERIAL_PROFILES.size()]
	)


func _resolve_runs_per_config() -> int:
	var from_cli: int = _parse_bot_runs_per_config_arg()
	if from_cli > 0:
		return from_cli
	if OS.has_environment("TIDEKEEPER_BOT_RUNS_PER_CONFIG"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_RUNS_PER_CONFIG").strip_edges()
		if env_raw.is_valid_int():
			return maxi(1, env_raw.to_int())
	if _suite_name != "":
		var defs: Dictionary = _BotSuite.suite_defaults(_suite_name)
		var suite_rpc: int = _BotSuite.suite_runs_per_config_if_unset(int(defs.get("runs_per_config", 1)))
		if suite_rpc > 0:
			return suite_rpc
	return BOT_RUNS_PER_CONFIG_DEFAULT


func _parse_bot_runs_per_config_arg() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		var arg: String = args[i]
		if arg.begins_with("--bot-runs-per-config="):
			var raw: String = arg.substr("--bot-runs-per-config=".length()).strip_edges()
			if raw.is_valid_int():
				return maxi(1, raw.to_int())
			push_warning("[TestBot] 非法 --bot-runs-per-config=%s，回落 %d" % [raw, BOT_RUNS_PER_CONFIG_DEFAULT])
			return -1
		if arg == "--bot-runs-per-config" and i + 1 < args.size():
			var next_raw: String = String(args[i + 1]).strip_edges()
			if next_raw.is_valid_int():
				return maxi(1, next_raw.to_int())
			push_warning("[TestBot] 非法 --bot-runs-per-config %s，回落 %d" % [next_raw, BOT_RUNS_PER_CONFIG_DEFAULT])
			return -1
	return -1


## 配置分支 id 列表（稳定顺序，便于日志）
func _lighthouse_branch_ids() -> Array[String]:
	var out: Array[String] = []
	var branches: Dictionary = ConfigLoader.get_lighthouse_branches()
	for bid in branches.keys():
		out.append(String(bid))
	out.sort()
	return out


## 某分支按 tier 升序的节点 id
func _lighthouse_branch_node_ids(branch_id: String) -> Array[String]:
	var branch: Dictionary = ConfigLoader.get_lighthouse_branches().get(branch_id, {})
	var nodes: Dictionary = branch.get("nodes", {})
	var entries: Array[Dictionary] = []
	for nid in nodes.keys():
		var node: Dictionary = nodes[nid]
		entries.append({"id": String(nid), "tier": int(node.get("tier", 0))})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tier"]) < int(b["tier"])
	)
	var ids: Array[String] = []
	for e in entries:
		ids.append(String(e["id"]))
	return ids


## profile → 各分支深度（partial 每支独立随机，排除全 0 / 全满）
func _roll_lighthouse_depths(profile: String) -> Dictionary:
	var branch_ids: Array[String] = _lighthouse_branch_ids()
	var depths: Dictionary = {}
	var max_depths: Dictionary = {}
	var total_nodes: int = 0
	for bid in branch_ids:
		var n: int = _lighthouse_branch_node_ids(bid).size()
		max_depths[bid] = n
		depths[bid] = 0
		total_nodes += n
	match profile:
		"none":
			return depths
		"full":
			for b in branch_ids:
				depths[b] = int(max_depths[b])
			return depths
		_:
			for _attempt in 8:
				var sum: int = 0
				for b2 in branch_ids:
					var cap: int = int(max_depths[b2])
					var d: int = RNG.randi_range(0, cap) if cap > 0 else 0
					depths[b2] = d
					sum += d
				if sum > 0 and sum < total_nodes:
					return depths
			# 兜底：点亮第一支路径的第 1 个节点
			if not branch_ids.is_empty() and int(max_depths[branch_ids[0]]) > 0:
				depths[branch_ids[0]] = 1
			return depths


## 按分支深度点亮节点（ConfigLoader 按 tier 排序，尊重前置链）
func _build_lighthouse_purchased(depths: Dictionary) -> Dictionary:
	var purchased: Dictionary = {}
	for branch_id in _lighthouse_branch_ids():
		var ids: Array[String] = _lighthouse_branch_node_ids(branch_id)
		var depth: int = clampi(int(depths.get(branch_id, 0)), 0, ids.size())
		for i in depth:
			purchased[ids[i]] = true
	return purchased


func _tick_world(world: World, delta: float) -> void:
	if world.result_ui != null and world.result_ui.visible:
		_tick_result(world, delta)
		_release_move_actions()
		return
	if UpgradeManager.is_presenting():
		_tick_upgrade(delta)
		_release_move_actions()
		return
	if world.day_night.get_phase() == DayNightStateMachine.Phase.DAY:
		_tick_day_shop(world, delta)
		_release_move_actions()
		return
	if world.day_night.get_phase() == DayNightStateMachine.Phase.NIGHT:
		_tick_night_movement(world, delta)
		return
	_release_move_actions()


func _tick_result(_world: World, delta: float) -> void:
	_action_timer -= delta
	if _action_timer > 0.0:
		return
	# 正常路径：game_over/win 已推进；此处兜底（信号未到仍可推进）
	_note_serial_run_finished()
	if _sweep_pending_quit:
		_quit_after_sweep_if_pending()
		return
	if _should_quit_after_runs():
		_quit_bot_suite("max_runs")
		return
	print("[TestBot] 结算页 → 重开")
	_begin_next_bot_run()


func _tick_upgrade(delta: float) -> void:
	_action_timer -= delta
	if _action_timer > 0.0:
		return
	var idx: int = _pick_upgrade_index(UpgradeManager.get_current_offers())
	if idx < 0:
		UpgradeManager.skip()
	else:
		UpgradeManager.apply_offer(idx)
		if UpgradeManager.is_presenting():
			UpgradeManager.skip()
	_action_timer = UI_ACTION_DELAY


func _pick_upgrade_index(offers: Array) -> int:
	# 存活优先：减伤被动 / 已有武器升级 > 输出被动 > 新武器（教学期仍留槽）
	var best_i: int = -1
	var best_score: int = -1
	for i in offers.size():
		var offer: Dictionary = offers[i]
		if not _can_apply_offer(offer):
			continue
		var score: int = _offer_score(offer)
		if score > best_score:
			best_score = score
			best_i = i
	return best_i


func _can_apply_offer(offer: Dictionary) -> bool:
	var otype: String = str(offer.get("type", ""))
	# 满血永不占升级位；潮汐币始终可选（由评分压低无需求时）
	if otype == "heal":
		return (
			GameState.player_max_health > 0
			and GameState.player_health < GameState.player_max_health
		)
	if otype == "tidecoins":
		return true
	var id: String = str(offer.get("id", ""))
	if id == "":
		return false
	if otype == "weapon":
		if id in GameState.weapon_slots:
			return GameState.get_weapon_level(id) < GameState.max_weapon_level
		return _weapon_slots_free_for_new()
	if id in GameState.passive_slots:
		return GameState.get_passive_level(id) < GameState.max_passive_level
	return GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS


func _offer_score(offer: Dictionary) -> int:
	var otype: String = str(offer.get("type", ""))
	if otype == "heal":
		return _heal_offer_score()
	if otype == "tidecoins":
		return _tidecoins_offer_score()
	var id: String = str(offer.get("id", ""))
	# 进化路径优先于「生存期压低拾取/经验钥」；exp_sac 可能是信天翁钥被动
	var evo_boost: int = _evolution_build_boost(id, otype)
	if evo_boost > 0:
		return evo_boost
	if (_want_survival_bias() or _want_calamity_prep()) and id in ["pearl", "exp_sac"]:
		return 5
	if otype == "weapon":
		# 临近精英夜：已有武器升级仍优先，但新武器低于高分减伤被动
		if id in GameState.weapon_slots:
			return 88
		if _want_calamity_prep():
			return 22
		return 28 if _want_survival_bias() else 36
	return _survival_item_score(id)


## 残血才抬 heal；危血压过进化提权，轻伤远低于武器/减伤
func _heal_offer_score() -> int:
	if GameState.player_max_health <= 0:
		return 0
	var hp_ratio: float = float(GameState.player_health) / float(GameState.player_max_health)
	if hp_ratio >= 0.999:
		return 0
	# 危血：必须高于 evo boost（≤210），否则会边濒死边凑进化
	if hp_ratio < HEAL_CRITICAL_HP_RATIO:
		return HEAL_CRITICAL_SCORE
	if hp_ratio < 0.65:
		return 86
	if hp_ratio < 0.85:
		return 58 if (_want_survival_bias() or _want_calamity_prep()) else 42
	# 轻伤：仅天灾前略考虑，否则让位给 BD
	if _want_calamity_prep():
		return 36
	return 18


## 按钱袋与进化/天灾需求加权；不缺钱时远低于武器升级（原固定 70 会挤爆 BD）
func _tidecoins_offer_score() -> int:
	var coins: int = GameState.tidecoins
	var need: bool = _bot_wants_more_coins()
	if not need:
		if coins >= COINS_RICH:
			return 6
		if coins >= COINS_OK:
			return 14
		return 24
	if coins < COINS_LOW:
		return 76
	if coins < COINS_MID:
		return 52
	if coins < COINS_OK:
		return 36
	return 22


## 破产 / 凑进化钥 / 天灾前囤回血消耗品时才积极要潮汐币
func _bot_wants_more_coins() -> bool:
	var coins: int = GameState.tidecoins
	if coins < COINS_BROKE:
		return true
	if _want_calamity_prep() and coins < COINS_CALAMITY_WANT:
		return true
	if GameState.current_night + 1 == ARCHON_NIGHT and coins < COINS_ARCHON_WANT:
		return true
	for wid_v in GameState.weapon_slots:
		var wid: String = String(wid_v)
		if GameState.is_weapon_evolved(wid):
			continue
		var path: Dictionary = EvolutionSystem.evolution_path(wid)
		if path.is_empty():
			continue
		var pid: String = String(path.get("passive_id", ""))
		if pid == "":
			continue
		var wlv: int = GameState.get_weapon_level(wid)
		var need_key: bool = pid not in GameState.passive_slots
		var need_key_lv: bool = (
			pid in GameState.passive_slots
			and GameState.get_passive_level(pid) < GameState.max_passive_level
		)
		if wlv >= GameState.max_weapon_level - 1 and (need_key or need_key_lv) and coins < COINS_EVO_WANT:
			return true
	return false

## 教学期按「尚未拥有的 demo_weapons 数量」留空槽，保证夜2/3/4 展示能入槽
func _weapon_slots_free_for_new() -> bool:
	var used: int = GameState.weapon_slots.size()
	if used >= GameState.MAX_WEAPON_SLOTS:
		return false
	var reserve: int = _teaching_demo_reserve()
	return used < GameState.MAX_WEAPON_SLOTS - reserve


func _teaching_demo_reserve() -> int:
	if not (
		DifficultySystem.is_teaching_night(GameState.current_night)
		or DifficultySystem.is_teaching_night(GameState.current_night + 1)
	):
		return 0
	var need: int = 0
	for wid in ConfigLoader.get_teaching_demo_weapons():
		var id: String = String(wid)
		if id != "" and id not in GameState.weapon_slots:
			need += 1
	return need


func _tick_day_shop(world: World, delta: float) -> void:
	if _cutoff_restart_pending:
		_tick_max_night_cutoff(delta)
		return
	_action_timer -= delta
	if _action_timer > 0.0:
		return
	if world.shop_ui != null and world.shop_ui.visible:
		_try_shop_actions(world)
		print("[TestBot] 跳过抉择之昼 → 下一夜")
		if world.day_phase_ui != null:
			world.day_phase_ui.exit_day()
		world.shop_ui.close()
		world.day_night.skip_day_phase()
	_action_timer = SHOP_DWELL


func _try_shop_actions(world: World) -> void:
	if world.shop_manager == null:
		return
	# 槽满时为进化钥腾位 → 购买 → 融合 → 精炼
	_bot_free_slots_for_evolution_keys(world)
	_bot_buy_shop_items(world)
	_bot_fuse_ready_weapons()
	_bot_refine_ready_weapons()


## 商店有未持有的进化钥、被动槽满时：重铸非钥被动腾位，以便凑融合
func _bot_free_slots_for_evolution_keys(world: World) -> void:
	if GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS:
		return
	var needed: Dictionary = {}  # passive_id → true
	for wid in GameState.weapon_slots:
		if GameState.is_weapon_evolved(wid):
			continue
		var path: Dictionary = EvolutionSystem.evolution_path(wid)
		if path.is_empty():
			continue
		var pid: String = String(path.get("passive_id", ""))
		if pid == "" or pid in GameState.passive_slots:
			continue
		# 仅当武器已接近/满级，或货架上确实有该钥时才腾位
		var on_shelf: bool = false
		for item in world.shop_manager.get_current_items():
			if str(item.get("kind", "")) == "passive" and str(item.get("id", "")) == pid:
				on_shelf = true
				break
		if on_shelf or GameState.get_weapon_level(wid) >= GameState.max_weapon_level - 1:
			needed[pid] = true
	if needed.is_empty():
		return
	# 重铸「不是任何未进化武器钥」的被动；优先 pearl / 低价值
	var protected: Dictionary = {}
	for wid2 in GameState.weapon_slots:
		if GameState.is_weapon_evolved(wid2):
			continue
		var p2: Dictionary = EvolutionSystem.evolution_path(wid2)
		var k: String = String(p2.get("passive_id", ""))
		if k != "":
			protected[k] = true
	var victims: Array[String] = []
	for pid_owned in GameState.passive_slots:
		if protected.has(pid_owned):
			continue
		victims.append(pid_owned)
	# 低价值优先卸（冒泡，槽位 ≤6）
	for i in victims.size():
		for j in range(i + 1, victims.size()):
			if _survival_item_score(victims[j]) < _survival_item_score(victims[i]):
				var tmp: String = victims[i]
				victims[i] = victims[j]
				victims[j] = tmp
	var slots_needed: int = needed.size()
	for i in mini(slots_needed, victims.size()):
		var refund: int = GameState.reroll_passive(victims[i])
		if refund > 0:
			print("[TestBot] 为进化钥腾位，重铸被动 %s（退 %d）" % [victims[i], refund])


## 按存活/进化分买到没钱或没货（教学留槽仍由 _should_buy_shop_item 约束）
func _bot_buy_shop_items(world: World) -> void:
	var items: Array = world.shop_manager.get_current_items()
	var skipped: Dictionary = {}
	while true:
		var best: Dictionary = {}
		var best_score: int = -1
		for item in items:
			var key: String = _shop_item_key(item)
			if key != "" and skipped.has(key):
				continue
			if not _should_buy_shop_item(item):
				continue
			var cost: int = int(item.get("cost", 0))
			if cost > GameState.tidecoins:
				continue
			var score: int = _shop_item_score(item)
			if score > best_score:
				best_score = score
				best = item
		if best_score < 0:
			break
		if world.shop_manager.buy(best):
			print("[TestBot] 购买 %s" % best.get("name", "?"))
		else:
			var fail_key: String = _shop_item_key(best)
			if fail_key == "":
				break
			skipped[fail_key] = true


## 可融合则全部融合（需进化道具 + 武器满级 + 钥被动满级）
func _bot_fuse_ready_weapons() -> void:
	var guard: int = 0
	while guard < 8:
		var ready: Array[String] = EvolutionSystem.list_ready()
		if ready.is_empty():
			break
		var fused_any: bool = false
		for wid in ready:
			if EvolutionSystem.fuse(wid):
				print("[TestBot] 融合武器 %s → %s" % [wid, GameState.get_evolved_name(wid)])
				fused_any = true
		if not fused_any:
			break
		guard += 1


func _bot_refine_ready_weapons() -> void:
	for wid in RefineSystem.list_ready():
		if RefineSystem.refine(wid) > 0:
			print("[TestBot] 精炼武器 %s" % wid)
			_refine_clicked = true
			_record_accept("4.2.8", "pass", "refine=%s" % wid)


func _shop_item_key(item: Dictionary) -> String:
	var id: String = str(item.get("id", ""))
	if id == "":
		return ""
	return "%s:%s" % [str(item.get("kind", "")), id]


func _should_buy_shop_item(item: Dictionary) -> bool:
	var id: String = str(item.get("id", ""))
	if id == "":
		return false
	var kind: String = str(item.get("kind", ""))
	# 生存期不买纯拾取/经验被动；但进化钥（如信天翁→exp_sac）例外
	if _want_survival_bias() and id in ["pearl", "exp_sac"] and _evolution_build_boost(id, kind) <= 0:
		return false
	if kind == "weapon":
		if id in GameState.weapon_slots:
			return GameState.get_weapon_level(id) < GameState.max_weapon_level
		return _weapon_slots_free_for_new()
	if kind == "passive":
		if id in GameState.passive_slots:
			return GameState.get_passive_level(id) < GameState.max_passive_level
		return GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS
	# 消耗品 / 其他：买得起就买
	return true


func _shop_item_score(item: Dictionary) -> int:
	var id: String = str(item.get("id", ""))
	var kind: String = str(item.get("kind", ""))
	var evo_boost: int = _evolution_build_boost(id, kind)
	if evo_boost > 0:
		return evo_boost
	var owned: bool = id in GameState.weapon_slots or id in GameState.passive_slots
	var base: int = _survival_item_score(id)
	var calamity_prep: bool = _want_calamity_prep()
	# 仅真正消耗品回血：低血或进天灾前抬优先（storm_flask 是减 CD 被动，不走此分支）
	if kind == "consumable":
		var hp_ratio: float = 1.0
		if GameState.player_max_health > 0:
			hp_ratio = float(GameState.player_health) / float(GameState.player_max_health)
		# N14 进执政官前：几乎无条件囤回血（光晕内存活仍靠满血/减伤）
		if GameState.current_night + 1 == ARCHON_NIGHT:
			base = maxi(base, 175)
		elif hp_ratio < 0.95 or _want_survival_bias() or calamity_prep:
			base = maxi(base, 150 if calamity_prep else 130)
	if kind == "weapon" and owned:
		return 86 if not _want_survival_bias() else 70
	# 生存期 / 天灾前：未拥有新武器再降，把钱留给护身符/珊瑚屏障
	if kind == "weapon" and not owned and (_want_survival_bias() or calamity_prep):
		base = mini(base, 30 if calamity_prep else 36)
	# 已有减伤被动继续叠级
	if kind == "passive" and owned and id in ["amulet", "coral_barrier"]:
		var stack: int = 140 + (22 if _want_survival_bias() else 0)
		if calamity_prep:
			stack += 30
		return stack
	return base + (12 if owned else 0)


## 为已持有未进化武器凑满级 / 钥被动：高分驱动三选一与商店，便于抉择之昼融合
func _evolution_build_boost(id: String, kind: String) -> int:
	if id == "" or (kind != "weapon" and kind != "passive"):
		return 0
	var best: int = 0
	for wid in GameState.weapon_slots:
		if GameState.is_weapon_evolved(wid):
			continue
		var path: Dictionary = EvolutionSystem.evolution_path(wid)
		if path.is_empty():
			continue
		var pid: String = String(path.get("passive_id", ""))
		var wlv: int = GameState.get_weapon_level(wid)
		var wmax: int = GameState.max_weapon_level
		if kind == "weapon" and id == wid and wlv < wmax:
			best = maxi(best, 170)
		if kind == "passive" and id == pid:
			var plv: int = GameState.get_passive_level(pid)
			if plv >= GameState.max_passive_level:
				continue
			if wlv >= wmax:
				# 武器已满级：钥被动最高优先，尽快触发融合
				best = maxi(best, 210)
			elif wlv >= 5:
				best = maxi(best, 165)
			else:
				best = maxi(best, 135)
	return best



func _want_survival_bias() -> bool:
	return GameState.current_night >= SURVIVAL_BIAS_FROM_NIGHT


## 天灾夜前一昼（N9/14/19）：囤回血与减伤，少买新武器
func _want_calamity_prep() -> bool:
	return GameState.current_night + 1 in CALAMITY_NIGHTS


func _is_calamity_night() -> bool:
	return GameState.current_night in CALAMITY_NIGHTS


func _is_archon_night() -> bool:
	return GameState.current_night == ARCHON_NIGHT


func _lighthouse_aura_radius() -> float:
	var light: Dictionary = ConfigLoader.get_lighthouse_meta()
	return float(light.get("aura_radius", 140.0))


func _lighthouse_position(world: World) -> Vector2:
	# 圆心可能为 (0,0)；勿用 ZERO 作「未设置」哨兵（与 World 写入的真实坐标一致）
	if world.enemy_spawner == null:
		return Vector2.INF
	return world.enemy_spawner.lighthouse_position


func _survival_item_score(id: String) -> int:
	var bias: int = 22 if _want_survival_bias() else 0
	if _want_calamity_prep():
		bias += 18
	match id:
		"amulet", "coral_barrier":
			return 120 + bias
		"storm_flask":
			# 进化钥被动（减 CD）；天灾前略抬，但仍低于减伤叠级与真回血消耗品
			return 78 + bias + (12 if _want_calamity_prep() else 0)
		"lamp_core", "tide_bell":
			return 48 if _want_survival_bias() else 72
		"lamp_oil", "iron_chain", "humus", "abyss_eye", "tide_compass":
			return 40 if _want_survival_bias() else 64
		"pearl":
			# 拾取半径对深潜突袭无帮助；生存期刻意压分
			return 12 if _want_survival_bias() else 40
		"exp_sac":
			return 8
		_:
			return 50


func _tick_night_movement(world: World, delta: float) -> void:
	if _suite_name != "":
		_ensure_chest_hook(world)
		_enemy_sample_timer -= delta
		if _enemy_sample_timer <= 0.0:
			_enemy_sample_timer = ACCEPT_ENEMY_SAMPLE_INTERVAL
			_accept_sample_enemies(world)
	var player: Player = world.player as Player
	# 锁链改为减速后仍可走位；仅缺玩家时停手
	if player == null:
		_release_move_actions()
		return
	var pos: Vector2 = player.global_position
	var dir: Vector2 = _compute_move_direction(world, pos, delta)
	if dir.length_squared() > 0.01:
		_last_move_dir = dir.normalized()
	_apply_move_direction(dir)


func _compute_move_direction(world: World, pos: Vector2, delta: float) -> Vector2:
	_orbit_angle += delta * ORBIT_SPEED
	var kite: Vector2 = Vector2(cos(_orbit_angle), sin(_orbit_angle))
	if _panic_timer > 0.0:
		_panic_timer = maxf(0.0, _panic_timer - delta)
	# 挣扎窗口：无敌期内全力凑杀（见 _struggle_move_direction）
	if GameState.is_struggling():
		return _struggle_move_direction(world, pos, kite)

	var proj_flee: Vector2 = _projectile_flee_vector(world, pos)
	var flee: Vector2 = _enemy_flee_vector(world, pos) + proj_flee
	var hp_ratio: float = 1.0
	if GameState.player_max_health > 0:
		hp_ratio = float(GameState.player_health) / float(GameState.player_max_health)
	var calamity: bool = _is_calamity_night()
	var proj_len_sq: float = proj_flee.length_squared()

	# N15 执政官：必须待在灯塔光晕内，远距风筝会周期性吃潮汐波
	if _is_archon_night():
		return _archon_move_direction(world, pos, flee, kite, hp_ratio, delta)

	var nearest_contact: float = _nearest_enemy_distance(world, pos, PANIC_CONTACT_DIST + 40.0)
	var burrow_threat: bool = _has_burrow_threat(world, pos, BURROW_SCAN_RADIUS)
	# 贴脸、潜地或强弹幕：锁定逃离方向，禁止掉头/捡珠（深潜者脚下浮现后须立刻离开接触半径）
	if (
		nearest_contact <= PANIC_CONTACT_DIST
		or burrow_threat
		or proj_len_sq >= PROJ_PANIC_LEN_SQ
	):
		_arm_panic(flee, kite)

	if _panic_timer > 0.0:
		# 恐慌期仍允许顺逃逸方向捡回血箱（深潜磨血时救命）
		var hp_ratio_panic: float = 1.0
		if GameState.player_max_health > 0:
			hp_ratio_panic = float(GameState.player_health) / float(GameState.player_max_health)
		if hp_ratio_panic < DANGER_HP_RATIO:
			var panic_chest: Vector2 = _safe_chest_direction(world, pos)
			if panic_chest != Vector2.ZERO and panic_chest.dot(_panic_dir) >= -0.1:
				return panic_chest
		return _panic_flee_direction(world, pos, flee, kite)

	# Boss 优先于精英：天灾夜潮汐主宰是主死因
	var boss_pos: Vector2 = _nearest_boss_position(world, pos, BOSS_SCAN_RADIUS)
	var boss_near: bool = boss_pos != Vector2.INF
	var boss_dist: float = pos.distance_to(boss_pos) if boss_near else 9999.0
	var boss_min_dist: float = BOSS_MIN_DIST_CALAMITY if calamity else BOSS_MIN_DIST
	if boss_near and boss_dist < boss_min_dist:
		if hp_ratio < DANGER_HP_RATIO:
			var rescue_chest: Vector2 = _safe_chest_direction(world, pos)
			if rescue_chest != Vector2.ZERO and _chest_away_from_elite(rescue_chest, pos, boss_pos):
				return rescue_chest
		return _kite_away_from(boss_pos, pos, flee, kite, 7.5, 2.2)

	var elite_pos: Vector2 = _nearest_elite_position(world, pos, ELITE_SCAN_RADIUS)
	var elite_near: bool = elite_pos != Vector2.INF
	var elite_dist: float = pos.distance_to(elite_pos) if elite_near else 9999.0
	var elite_min_dist: float = _elite_keep_distance(world, elite_pos)
	# N5 开场精英刷在玩家上方约 200：立刻南向拉开，勿捡箱/珠
	if elite_near and elite_dist < elite_min_dist:
		if hp_ratio < DANGER_HP_RATIO:
			var rescue_chest2: Vector2 = _safe_chest_direction(world, pos)
			if rescue_chest2 != Vector2.ZERO and _chest_away_from_elite(rescue_chest2, pos, elite_pos):
				return rescue_chest2
		return _kite_away_from(elite_pos, pos, flee, kite, 6.0, 2.6)

	# 低血：优先安全宝箱（可能回血），再风筝
	if hp_ratio < DANGER_HP_RATIO:
		var low_hp_chest: Vector2 = _safe_chest_direction(world, pos)
		if low_hp_chest != Vector2.ZERO:
			return low_hp_chest

	# N4+ 有深潜者或贴身压力：放弃捡珠，切向风筝（保持移动吃掉突袭后的接触 CD）
	var diver_pressure: bool = GameState.current_night >= 4 and _has_burrow_enemy(world, pos, BURROW_SCAN_RADIUS)
	var proj_danger: bool = proj_len_sq >= PROJ_DANGER_LEN_SQ
	var danger: bool = (
		calamity
		or boss_near
		or flee.length_squared() > 0.08
		or hp_ratio < DANGER_HP_RATIO
		or elite_near
		or diver_pressure
		or proj_danger
	)
	if danger:
		var away: Vector2 = flee.normalized() if flee.length_squared() > 0.0001 else _last_move_dir
		if away.length_squared() < 0.0001:
			away = kite
		if boss_near:
			away = (away + (pos - boss_pos).normalized() * 3.2).normalized()
		elif elite_near:
			away = (away + (pos - elite_pos).normalized() * 2.4).normalized()
		# 弹幕主导时：侧移权重更高（对齐 _projectile_flee 的 side 分量）
		if proj_danger and proj_flee.length_squared() > 0.0001:
			away = (away * 0.55 + proj_flee.normalized() * 0.85).normalized()
		var tangent: Vector2 = Vector2(-away.y, away.x)
		if kite.dot(tangent) < 0.0:
			tangent = -tangent
		var away_w: float = 4.8 if hp_ratio > DANGER_HP_RATIO else 6.2
		if boss_near:
			away_w += 3.4
		elif elite_near:
			away_w += 2.2
		if GameState.current_night >= 4:
			away_w += 1.4
		if calamity:
			away_w += 1.8
			tangent *= 0.55
		if diver_pressure:
			away_w += 1.6
			# 深潜压力下少绕圈，优先直线拉开
			tangent *= 0.45
		if proj_danger:
			away_w += 2.4
			tangent *= 0.7
		var combined: Vector2 = away * away_w + tangent * 2.6 + kite * 0.1
		if combined.length_squared() < 0.01:
			return away
		return combined.normalized()

	# 安全时优先捡宝箱；天灾夜整晚不捡珠（保命优先于经验）
	var chest_dir: Vector2 = _safe_chest_direction(world, pos)
	if chest_dir != Vector2.ZERO:
		return chest_dir
	if not calamity and not boss_near:
		var gem_dir: Vector2 = _safe_gem_direction(world, pos)
		if gem_dir != Vector2.ZERO:
			return gem_dir
	return kite


## N15：贴灯塔光晕内环绕；出圈立刻回撤（潮汐波 exam_point）
func _archon_move_direction(
	world: World, pos: Vector2, flee: Vector2, kite: Vector2, hp_ratio: float, delta: float
) -> Vector2:
	_orbit_angle += delta * (ARCHON_ORBIT_SPEED - ORBIT_SPEED)
	var light: Vector2 = _lighthouse_position(world)
	if light == Vector2.INF:
		var boss_fb: Vector2 = _nearest_boss_position(world, pos, BOSS_SCAN_RADIUS)
		if boss_fb != Vector2.INF:
			return _kite_away_from(boss_fb, pos, flee, kite, 5.0, 2.0)
		return kite if kite.length_squared() > 0.0001 else Vector2.RIGHT

	var aura: float = _lighthouse_aura_radius()
	var stay_r: float = aura * ARCHON_AURA_STAY_RATIO
	var hard_r: float = aura * ARCHON_AURA_HARD_RATIO
	var to_light: Vector2 = light - pos
	var dist_light: float = to_light.length()
	var inward: Vector2 = to_light / dist_light if dist_light > 1.0 else Vector2.RIGHT

	# 硬出圈 / 接近出圈：最高优先级回撤（可略带侧移躲接触，但不允许净外向）
	if dist_light > stay_r:
		var back: Vector2 = inward
		if flee.length_squared() > 0.0001:
			var side: Vector2 = Vector2(-inward.y, inward.x)
			if flee.normalized().dot(side) < 0.0:
				side = -side
			var blend: Vector2 = inward * 4.2 + side * 1.1
			# 夹击杂兵 flee 若指向外圈则丢掉
			if flee.normalized().dot(inward) > -0.05:
				blend += flee.normalized() * 0.9
			back = blend.normalized()
		return back

	var boss_pos: Vector2 = _nearest_boss_position(world, pos, BOSS_SCAN_RADIUS)
	var nearest_contact: float = _nearest_enemy_distance(world, pos, PANIC_CONTACT_DIST + 30.0)
	if nearest_contact <= PANIC_CONTACT_DIST:
		# 恐慌仍锁向，但最终方向钳制在光晕内
		_arm_panic(flee, kite)
		var panic_dir: Vector2 = _panic_flee_direction(world, pos, flee, kite)
		return _clamp_dir_inside_aura(panic_dir, pos, light, hard_r)

	# 低血：光晕内专用寻箱（不走 CHEST_SAFE_BOSS=720）
	if hp_ratio < DANGER_HP_RATIO:
		var chest: Vector2 = _archon_chest_direction(world, pos, light, hard_r)
		if chest != Vector2.ZERO:
			return chest

	# 光晕内：环绕灯塔 + 软拉开 Boss（flee 已含弹幕，勿再叠 _projectile_flee）
	var radial: Vector2 = (pos - light).normalized() if dist_light > 8.0 else kite
	var tangent: Vector2 = Vector2(-radial.y, radial.x)
	var orbit_kite: Vector2 = Vector2(cos(_orbit_angle), sin(_orbit_angle))
	if orbit_kite.dot(tangent) < 0.0:
		tangent = -tangent

	var away_boss: Vector2 = Vector2.ZERO
	if boss_pos != Vector2.INF:
		var bd: float = pos.distance_to(boss_pos)
		if bd < ARCHON_BOSS_SOFT_DIST:
			away_boss = (pos - boss_pos).normalized()
		elif bd < ARCHON_BOSS_SOFT_DIST * 1.55:
			away_boss = (pos - boss_pos).normalized() * 0.55

	var prefer_r: float = aura * ARCHON_PREF_RING_RATIO
	var radial_fix: Vector2 = Vector2.ZERO
	if dist_light < prefer_r * 0.5:
		radial_fix = radial
	elif dist_light > prefer_r * 1.2:
		radial_fix = -radial

	var combined: Vector2 = (
		tangent * 3.2
		+ away_boss * 5.0
		+ flee * 2.15
		+ radial_fix * 2.4
		+ orbit_kite * 0.25
	)
	if combined.length_squared() < 0.01:
		combined = tangent
	return _clamp_dir_inside_aura(combined.normalized(), pos, light, hard_r)


## 执政官夜寻箱：须在 hard_r 内；只拒贴脸怪 / Boss 脚下（允许圈内 Boss 旁回血）
func _archon_chest_direction(world: World, pos: Vector2, light: Vector2, hard_r: float) -> Vector2:
	if world.pickup_system == null:
		return Vector2.ZERO
	var chest_out: Array[Vector2] = [Vector2.ZERO]
	if not world.pickup_system.try_nearest_chest_position(pos, chest_out, CHEST_SEEK_RANGE):
		return Vector2.ZERO
	var chest: Vector2 = chest_out[0]
	if light.distance_to(chest) > hard_r:
		return Vector2.ZERO
	if _nearest_enemy_distance(world, chest, ARCHON_CHEST_SAFE_ENEMY + 20.0) <= ARCHON_CHEST_SAFE_ENEMY:
		return Vector2.ZERO
	if _nearest_boss_position(world, chest, ARCHON_CHEST_SAFE_BOSS) != Vector2.INF:
		return Vector2.ZERO
	var to_chest: Vector2 = chest - pos
	if to_chest.length_squared() < 4.0:
		return Vector2.ZERO
	return to_chest.normalized()


## 禁止移动方向把玩家推出光晕硬边界
func _clamp_dir_inside_aura(dir: Vector2, pos: Vector2, light: Vector2, hard_r: float) -> Vector2:
	if dir.length_squared() < 0.0001:
		return (light - pos).normalized() if pos.distance_to(light) > 1.0 else Vector2.RIGHT
	var dist: float = pos.distance_to(light)
	if dist <= hard_r * 0.85:
		return dir.normalized()
	var outward: Vector2 = (pos - light).normalized() if dist > 1.0 else Vector2.RIGHT
	var outward_dot: float = dir.normalized().dot(outward)
	if outward_dot <= 0.05:
		return dir.normalized()
	var fixed: Vector2 = dir.normalized() - outward * (outward_dot + 0.35)
	if fixed.length_squared() < 0.0001:
		return -outward
	return fixed.normalized()


func _arm_panic(flee: Vector2, kite: Vector2) -> void:
	var dir: Vector2 = flee
	if dir.length_squared() < 0.0001:
		dir = _last_move_dir
	if dir.length_squared() < 0.0001:
		dir = kite
	# 恐慌中途不换向（避免来回撞回接触圈）
	if _panic_timer <= 0.0:
		_panic_dir = dir.normalized()
	_panic_timer = PANIC_STICK_SEC


func _panic_flee_direction(world: World, pos: Vector2, flee: Vector2, kite: Vector2) -> Vector2:
	var away: Vector2 = _panic_dir
	if flee.length_squared() > 0.0001 and flee.normalized().dot(_panic_dir) > 0.15:
		away = (away * 1.4 + flee.normalized()).normalized()
	elif flee.length_squared() > 0.0001 and _panic_timer < PANIC_STICK_SEC * 0.35:
		# 后半段允许轻微并入新 flee，仍禁止反向
		var blended: Vector2 = away * 2.0 + flee.normalized()
		if blended.dot(_panic_dir) > 0.0:
			away = blended.normalized()
	if away.length_squared() < 0.0001:
		away = kite if kite.length_squared() > 0.0001 else Vector2.RIGHT
	# 恐慌期仍躲弹，但权重低、且不反向
	var proj: Vector2 = _projectile_flee_vector(world, pos)
	if proj.length_squared() > 0.0001 and proj.normalized().dot(away) > -0.2:
		away = (away * 3.0 + proj.normalized()).normalized()
	return away.normalized()


func _has_burrow_threat(world: World, pos: Vector2, radius: float) -> bool:
	# 潜地突袭会传送到玩家附近：任一潜地中的深潜者都算威胁（全图）；贴脸未潜地也算
	for enemy in _iter_live_enemies(world, pos, radius, true):
		if enemy.behavior_type != "burrow_ambush":
			continue
		if enemy.is_burrowed():
			return true
		if pos.distance_to(enemy.global_position) <= PANIC_CONTACT_DIST * 1.5:
			return true
	return false


func _has_burrow_enemy(world: World, pos: Vector2, radius: float) -> bool:
	for enemy in _iter_live_enemies(world, pos, radius, false):
		if enemy.behavior_type == "burrow_ambush":
			return true
	return false


## 优先对象池；ignore_radius=true 时扫全活跃（潜地威胁跨距）；否则按 radius 过滤
func _iter_live_enemies(world: World, pos: Vector2, radius: float, ignore_radius: bool = false) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	var radius_sq: float = radius * radius
	if world.enemy_pool != null:
		for node in world.enemy_pool.get_active():
			var enemy: EnemyBase = node as EnemyBase
			if enemy == null or enemy.is_dead():
				continue
			if not ignore_radius and pos.distance_squared_to(enemy.global_position) > radius_sq:
				continue
			out.append(enemy)
		return out
	return _query_enemies(world, pos, radius)


## 挣扎：无敌窗内全力凑杀；优先安全软怪，没有则追最近可计杀目标（含靠近精英）
func _struggle_move_direction(world: World, pos: Vector2, kite: Vector2) -> Vector2:
	var soft: Vector2 = _nearest_struggle_target(world, pos, STRUGGLE_HUNT_RADIUS)
	if soft != Vector2.INF:
		return (soft - pos).normalized()
	# 放宽：任意非 floor / 非 boss 目标（含精英）—— 3s 内需 5 杀，保命靠无敌
	var any_kill: Vector2 = _nearest_struggle_any(world, pos, STRUGGLE_HUNT_RADIUS + 200.0)
	if any_kill != Vector2.INF:
		return (any_kill - pos).normalized()
	var flee: Vector2 = _enemy_flee_vector(world, pos)
	if flee.length_squared() > 0.0001:
		# 反向靠近怪群（flee 指向远离，挣扎时取反）
		return (-flee).normalized()
	return kite


func _elite_keep_distance(world: World, elite_pos: Vector2) -> float:
	var base: float = ELITE_MIN_DIST_N5 if GameState.current_night >= 5 else ELITE_MIN_DIST
	if elite_pos == Vector2.INF:
		return base
	# 仅精英（Boss 由 _nearest_boss_position / BOSS_MIN_DIST_* 处理）
	for enemy in _query_enemies(world, elite_pos, 40.0):
		if not enemy.is_elite or enemy.is_boss:
			continue
		if enemy.has_affix("chain"):
			return maxf(base, ELITE_MIN_DIST_CHAIN)
		if enemy.has_affix("thorns") and enemy.has_affix("swift"):
			return maxf(base, ELITE_MIN_DIST_N5 + 80.0)
	return base


func _chest_away_from_elite(chest_dir: Vector2, pos: Vector2, elite_pos: Vector2) -> bool:
	if elite_pos == Vector2.INF or chest_dir == Vector2.ZERO:
		return true
	var away: Vector2 = (pos - elite_pos).normalized()
	return chest_dir.dot(away) >= -0.15


func _kite_away_from(
	threat_pos: Vector2, pos: Vector2, flee: Vector2, kite: Vector2, away_w: float, tangent_w: float
) -> Vector2:
	var away: Vector2 = (pos - threat_pos).normalized()
	if flee.length_squared() > 0.0001:
		away = (away * 1.6 + flee.normalized()).normalized()
	var tangent: Vector2 = Vector2(-away.y, away.x)
	if kite.dot(tangent) < 0.0:
		tangent = -tangent
	var combined: Vector2 = away * away_w + tangent * tangent_w + flee * 0.8 + kite * 0.15
	if combined.length_squared() < 0.01:
		return away
	return combined.normalized()


func _safe_chest_direction(world: World, pos: Vector2) -> Vector2:
	if world.pickup_system == null:
		return Vector2.ZERO
	var chest_out: Array[Vector2] = [Vector2.ZERO]
	if not world.pickup_system.try_nearest_chest_position(pos, chest_out, CHEST_SEEK_RANGE):
		return Vector2.ZERO
	var chest: Vector2 = chest_out[0]
	if _nearest_enemy_distance(world, chest, CHEST_SAFE_ENEMY + 20.0) <= CHEST_SAFE_ENEMY:
		return Vector2.ZERO
	if _nearest_boss_position(world, chest, CHEST_SAFE_BOSS) != Vector2.INF:
		return Vector2.ZERO
	if _nearest_elite_position(world, chest, CHEST_SAFE_ELITE) != Vector2.INF:
		return Vector2.ZERO
	var to_chest: Vector2 = chest - pos
	if to_chest.length_squared() < 4.0:
		return Vector2.ZERO
	return to_chest.normalized()


func _safe_gem_direction(world: World, pos: Vector2) -> Vector2:
	if world.pickup_system == null:
		return Vector2.ZERO
	# 经验珠优先，其次潮币（同吸附半径；避免风筝只捡珠导致 CoinPool 堆满）
	var target: Vector2 = Vector2.ZERO
	var gem_out: Array[Vector2] = [Vector2.ZERO]
	if world.pickup_system.try_nearest_gem_position(pos, gem_out, GEM_SEEK_RANGE):
		target = gem_out[0]
	else:
		var coin_out: Array[Vector2] = [Vector2.ZERO]
		if not world.pickup_system.try_nearest_coin_position(pos, coin_out, GEM_SEEK_RANGE):
			return Vector2.ZERO
		target = coin_out[0]
	if _nearest_enemy_distance(world, target, GEM_SAFE_ENEMY + 24.0) <= GEM_SAFE_ENEMY:
		return Vector2.ZERO
	if _nearest_boss_position(world, target, CHEST_SAFE_BOSS) != Vector2.INF:
		return Vector2.ZERO
	if _nearest_elite_position(world, target, GEM_SAFE_ELITE) != Vector2.INF:
		return Vector2.ZERO
	var to_target: Vector2 = target - pos
	if to_target.length_squared() < 4.0:
		return Vector2.ZERO
	return to_target.normalized()


func _nearest_boss_position(world: World, pos: Vector2, radius: float) -> Vector2:
	# 走对象池扫 is_boss（通常 0~1 只），避免 BOSS_SCAN_RADIUS 大半径 SpatialHash 扫格
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	if world.enemy_pool != null:
		for node in world.enemy_pool.get_active():
			var enemy: EnemyBase = node as EnemyBase
			if enemy == null or enemy.is_dead() or not enemy.is_boss:
				continue
			var dist: float = pos.distance_to(enemy.global_position)
			if dist < best_dist:
				best_dist = dist
				best_pos = enemy.global_position
		return best_pos
	for enemy in _query_enemies(world, pos, radius):
		if not enemy.is_boss:
			continue
		var dist2: float = pos.distance_to(enemy.global_position)
		if dist2 < best_dist:
			best_dist = dist2
			best_pos = enemy.global_position
	return best_pos


func _nearest_elite_position(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for enemy in _query_enemies(world, pos, radius):
		# Boss 由 _nearest_boss_position 单独处理，避免精英距离套用到 Boss
		if not enemy.is_elite or enemy.is_boss:
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


## 挣扎击杀目标：排除 floor 补刷 / 荆棘怪；优先远离精英/Boss 的软怪
func _nearest_struggle_target(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	var elite_ref: Vector2 = _nearest_elite_position(world, pos, ELITE_SCAN_RADIUS)
	var boss_ref: Vector2 = _nearest_boss_position(world, pos, BOSS_SCAN_RADIUS)
	for enemy in _query_enemies(world, pos, radius):
		if enemy.is_floor_refill or enemy.is_elite or enemy.is_boss:
			continue
		if enemy.has_affix("thorns"):
			continue
		var epos: Vector2 = enemy.global_position
		if elite_ref != Vector2.INF and epos.distance_to(elite_ref) < STRUGGLE_SAFE_ELITE * 0.7:
			continue
		if boss_ref != Vector2.INF and epos.distance_to(boss_ref) < STRUGGLE_SAFE_ELITE * 0.85:
			continue
		if _nearest_thorns_distance(world, epos, STRUGGLE_SAFE_THORNS + 20.0) <= STRUGGLE_SAFE_THORNS:
			continue
		var dist: float = pos.distance_to(epos)
		if dist < best_dist:
			best_dist = dist
			best_pos = epos
	return best_pos


## 挣扎兜底目标：任意可计杀（非 floor）；含精英
func _nearest_struggle_any(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for enemy in _query_enemies(world, pos, radius):
		if enemy.is_floor_refill:
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


func _nearest_thorns_distance(world: World, pos: Vector2, radius: float) -> float:
	var best: float = radius + 1.0
	for enemy in _query_enemies(world, pos, radius):
		if not enemy.has_affix("thorns"):
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best:
			best = dist
	return best


func _nearest_enemy_distance(world: World, pos: Vector2, radius: float) -> float:
	var best: float = radius + 1.0
	for enemy in _query_enemies(world, pos, radius):
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best:
			best = dist
	return best


func _query_enemies(world: World, pos: Vector2, radius: float) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if world.spatial_hash_holder == null:
		return out
	var grid: SpatialHash = world.spatial_hash_holder.get_hash()
	if grid == null:
		return out
	for node in grid.query_radius(pos, radius):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		if pos.distance_to(enemy.global_position) > radius:
			continue
		out.append(enemy)
	return out


func _enemy_flee_vector(world: World, pos: Vector2) -> Vector2:
	var flee: Vector2 = Vector2.ZERO
	var danger_radius: float = FLEE_RADIUS
	if _is_archon_night():
		# 光晕仅 ~140：大半径 flee 会被两侧夹击推出安全区
		danger_radius = _aura_safe_flee_radius()
	elif _is_calamity_night():
		danger_radius = FLEE_RADIUS_CALAMITY
	elif GameState.current_night >= 5:
		danger_radius = FLEE_RADIUS_N5
	elif GameState.current_night >= 4:
		danger_radius = FLEE_RADIUS_N4
	for enemy in _query_enemies(world, pos, danger_radius):
		# 执政官夜：Boss 接触由光晕环绕软拉开，不叠 BOSS_FLEE_WEIGHT 远推
		if _is_archon_night() and enemy.is_boss:
			continue
		var offset: Vector2 = pos - enemy.global_position
		var dist: float = offset.length()
		# 脚下浮现 / 重叠：旧逻辑 dist≈0 直接 skip，导致贴脸后无逃离力
		var dir: Vector2
		if dist < 1.0:
			dir = _last_move_dir if _last_move_dir.length_squared() > 0.0001 else Vector2.RIGHT
			dist = 1.0
		else:
			dir = offset / dist
		var weight: float = 1.0 - (dist / danger_radius)
		weight = maxf(weight, 0.05)
		weight *= 1.0 + float(enemy.danger) * 0.28
		if enemy.is_boss:
			weight *= BOSS_FLEE_WEIGHT
		elif enemy.is_elite:
			weight *= ELITE_FLEE_WEIGHT
		if enemy.has_affix("thorns"):
			weight *= THORNS_FLEE_WEIGHT
		if enemy.has_affix("swift"):
			weight *= SWIFT_FLEE_WEIGHT
		if enemy.has_affix("chain"):
			weight *= CHAIN_FLEE_WEIGHT
		if enemy.behavior_type == "self_destruct":
			weight *= BOMB_FLEE_WEIGHT
			if dist <= 110.0:
				weight *= 1.6
		if enemy.behavior_type == "burrow_ambush":
			weight *= BURROW_FLEE_WEIGHT
			if enemy.is_burrowed():
				weight *= 1.8
			if dist <= PANIC_CONTACT_DIST:
				weight *= 2.5
		flee += dir * weight
	return flee


func _aura_safe_flee_radius() -> float:
	return _lighthouse_aura_radius() * 0.95


func _projectile_flee_vector(world: World, pos: Vector2) -> Vector2:
	if world.enemy_projectile_pool == null:
		return Vector2.ZERO
	var flee: Vector2 = Vector2.ZERO
	var look: float = PROJ_LOOK_CALAMITY if _is_calamity_night() else PROJ_LOOK
	for node in world.enemy_projectile_pool.get_active():
		var proj: EnemyProjectile = node as EnemyProjectile
		if proj == null or not proj.visible:
			continue
		var offset: Vector2 = pos - proj.global_position
		var dist: float = offset.length()
		if dist < 0.001 or dist > look:
			continue
		var travel: Vector2 = proj.get_travel_dir()
		if travel.dot(-offset) < 0.15:
			continue
		var side: Vector2 = Vector2(-travel.y, travel.x)
		if offset.dot(side) < 0.0:
			side = -side
		var urgency: float = 1.0 - (dist / look)
		# 弹幕是局内第一承伤源：提高侧移/后撤，近距额外加压
		var side_w: float = 1.55 if _is_calamity_night() else 1.25
		var back_w: float = 0.95 if _is_calamity_night() else 0.75
		if dist < 90.0:
			side_w *= 1.35
			back_w *= 1.25
		flee += (offset.normalized() * back_w + side.normalized() * side_w) * urgency
	return flee


func _apply_move_direction(dir: Vector2) -> void:
	_release_move_actions()
	if dir.length_squared() < 0.01:
		return
	# 更低阈值：对角线更容易打出，突袭后离开接触圈更快
	if dir.x < -0.18:
		Input.action_press("move_left")
	elif dir.x > 0.18:
		Input.action_press("move_right")
	if dir.y < -0.18:
		Input.action_press("move_up")
	elif dir.y > 0.18:
		Input.action_press("move_down")


func _release_move_actions() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


# ---------------------------------------------------------------------------
# 验收套件 / ACCEPT（对齐 docs/原型验证验收清单.md）
# ---------------------------------------------------------------------------

func _apply_suite_config() -> void:
	_suite_name = _BotSuite.resolve_suite_name()
	var defs: Dictionary = _BotSuite.suite_defaults(_suite_name) if _suite_name != "" else {}
	_character_mode = _BotSuite.resolve_character(String(defs.get("character", "watcher")))
	_difficulty_mode = _BotSuite.resolve_difficulty(String(defs.get("difficulty", "lighthouse")))
	_max_night = _BotSuite.resolve_max_night(int(defs.get("max_night", 0)))
	_max_runs = _BotSuite.resolve_max_runs(int(defs.get("max_runs", 0)))
	_unlock_all_chars = bool(defs.get("unlock_all", false))
	if _unlock_all_chars:
		MetaSystem.set_unlock_all_characters_override(true)
	var lh: String = _BotSuite.suite_lighthouse_if_unset(String(defs.get("lighthouse", "")))
	_forced_lighthouse_mode = lh
	_suite_checklist.clear()
	var raw_list: Variant = defs.get("checklist", [])
	if raw_list is Array:
		for item in raw_list:
			_suite_checklist.append(String(item))


func _record_accept(id: String, status: String, detail: String = "") -> void:
	# 无验收套件时不打 ACCEPT，避免自由 Debug 跑污染日志
	if _suite_name == "":
		return
	var emit_key: String = "%s|%s" % [status, detail]
	# 同 status+detail 不重打（fail 仍允许覆盖：key 不同才会到此）
	if status != "fail" and String(_accept_last_emit.get(id, "")) == emit_key:
		return
	_accept_last_emit[id] = emit_key
	_BotSuite.emit_accept(id, status, detail)
	match status:
		"pass":
			_accept_pass[id] = true
			_accept_fail.erase(id)
		"fail":
			# fail 可覆盖先前 pass（5.2 中途扫到 SCRIPT ERROR 须打回）
			_accept_pass.erase(id)
			_accept_fail[id] = true
		_:
			pass


## 汇总前按最终 script_err / ge8 重算 5.2（避免粘滞 pass）
func _reconcile_accept_5_2() -> void:
	if _runs_reached_n8 < 3:
		return
	if _script_error_count <= 0:
		_accept_pass["5.2"] = true
		_accept_fail.erase("5.2")
	else:
		_accept_pass.erase("5.2")
		_accept_fail["5.2"] = true


func _accept_on_night_start(night: int) -> void:
	_accept_soft_caps_once()
	_accept_affix_config_once()
	var world: World = _current_world()
	_ensure_chest_hook(world)
	var expected: float = _BotSuite.expected_night_duration(night)
	var actual: float = expected
	if world != null and world.day_night != null:
		actual = world.day_night.get_night_duration()
	var dur_key: int = int(round(expected))
	if not _duration_checked.has(dur_key):
		_duration_checked[dur_key] = true
		var dur_ok: bool = is_equal_approx(actual, expected)
		_record_accept(
			"1.1.2",
			"pass" if dur_ok else "fail",
			"n=%d expect=%.0f got=%.0f" % [night, expected, actual]
		)
	var event_id: String = EventSystem.get_active_event_id()
	if night == 15:
		var ok15: bool = event_id != "tidal_reversal"
		_record_accept("4.5.2", "pass" if ok15 else "fail", "event=%s" % event_id)
	var pincer: bool = false
	if world != null and world.enemy_spawner != null:
		pincer = world.enemy_spawner.is_pincer_mode()
	var expect_pincer: bool = (night == 15) or EventSystem.is_event_pincer()
	if expect_pincer or pincer:
		_record_accept(
			"4.5.3",
			"pass" if pincer == expect_pincer else "fail",
			"n=%d pincer=%s expect=%s event=%s" % [night, str(pincer), str(expect_pincer), event_id]
		)
	if not _move_speed_checked and world != null and world.player != null:
		_move_speed_checked = true
		var want: float = ConfigLoader.get_character_move_speed(MetaSystem.get_active_character())
		var got: float = world.player.base_move_speed
		_record_accept(
			"1.2.1",
			"pass" if is_equal_approx(want, got) else "fail",
			"base=%.2f expect=%.2f" % [got, want]
		)
	_accept_affix_night_rules(night, world)


func _accept_on_night_end(night: int) -> void:
	# 1.1.1：清单要求连续 ≥10 夜；3.3：可玩到第 8~10 夜（≥8 即过）
	if night >= 10:
		_record_accept("1.1.1", "pass", "cleared_n=%d" % night)
	if night >= 8:
		_record_accept("3.3", "pass", "cleared_n=%d" % night)
	_accept_emit_feature_progress()


func _finalize_run_outcome(is_win: bool) -> void:
	if _run_outcome_recorded:
		return
	_run_outcome_recorded = true
	_completed_runs += 1
	_poll_script_errors()
	var peak: int = maxi(_run_peak_night, GameState.current_night)
	if peak >= 8:
		_runs_reached_n8 += 1
		_record_accept("3.3", "pass", "peak_n=%d" % peak)
	if peak >= 10:
		_runs_reached_n10 += 1
		_record_accept("1.1.1", "pass", "peak_n=%d" % peak)
	if _runs_reached_n8 >= 3:
		if _script_error_count <= 0:
			_record_accept("5.2", "pass", "runs_ge8=%d script_err=0" % _runs_reached_n8)
		else:
			_record_accept(
				"5.2",
				"fail",
				"runs_ge8=%d script_err=%d" % [_runs_reached_n8, _script_error_count]
			)
	if not _refine_clicked and _suite_name in ["acceptance", "full", "meta"]:
		_record_accept("4.2.8", "skip", "no_refine_this_run")
	_accept_emit_feature_progress()
	_accept_finalize_feature_skips(peak)
	print(
		"[TestBot] 局次完成 #%d win=%s peak_night=%d suite=%s script_err=%d peak_enemies=%d affix_kinds=%d thorns_hits=%d chests=%d"
		% [
			_completed_runs,
			str(is_win),
			peak,
			_suite_name if _suite_name != "" else "-",
			_script_error_count,
			_peak_enemies,
			_seen_affix_ids.size(),
			_thorns_hits,
			_chest_kinds_seen.size(),
		]
	)
	if _should_quit_after_runs() and not _sweep_pending_quit:
		call_deferred("_quit_bot_suite", "max_runs")


## 会话级：软上限公式自检（对齐 GDD §6.9 / B2）
func _accept_soft_caps_once() -> void:
	if _soft_caps_checked:
		return
	_soft_caps_checked = true
	var caps_raw: Variant = ConfigLoader.get_passives_metadata().get("soft_caps", {})
	var caps: Dictionary = caps_raw if caps_raw is Dictionary else {}
	var as_raw: Variant = caps.get("attack_speed", {})
	var as_cfg: Dictionary = as_raw if as_raw is Dictionary else {}
	var thr_as: float = float(as_cfg.get("threshold", -1.0))
	var eff_as: float = float(as_cfg.get("efficiency", 0.5))
	var thr_ms: float = PassiveSystem.get_soft_cap_threshold("move_speed", -1.0)
	var thr_exp: float = PassiveSystem.get_soft_cap_threshold("exp", -1.0)
	var thr_ok: bool = thr_as > 0.0 and thr_ms > 0.0 and thr_exp > 0.0 and not caps.is_empty()
	var soft_as: float = PassiveSystem.apply_soft_cap(3.0, "attack_speed")
	var expect_as: float = thr_as + (3.0 - thr_as) * eff_as
	var formula_ok: bool = thr_ok and is_equal_approx(soft_as, expect_as)
	var below: float = PassiveSystem.apply_soft_cap(thr_as, "attack_speed")
	var below_ok: bool = is_equal_approx(below, thr_as)
	var dr: float = PassiveSystem.get_damage_reduction()
	var dr_raw: Variant = caps.get("damage_reduction", {})
	var dr_cfg: Dictionary = dr_raw if dr_raw is Dictionary else {}
	var dr_cap: float = float(dr_cfg.get("cap", 0.70))
	var dr_ok: bool = dr <= dr_cap + 0.0001
	var ok: bool = formula_ok and below_ok and dr_ok
	_record_accept(
		"4.3.12",
		"pass" if ok else "fail",
		"as_thr=%.2f soft3=%.2f dr=%.3f" % [thr_as, soft_as, dr]
	)


## 会话级：6 词缀表齐全 + 荆棘键存在（精确 ratio/cap 留给 w8 机检）
func _accept_affix_config_once() -> void:
	if _affix_cfg_checked:
		return
	_affix_cfg_checked = true
	var expected_ids: Array[String] = ["split", "teleport", "thorns", "swift", "regen", "chain"]
	var missing: Array[String] = []
	for id in expected_ids:
		if ConfigLoader.get_affix(id).is_empty():
			missing.append(id)
	var th: Dictionary = ConfigLoader.get_affix("thorns")
	var ratio: float = float(th.get("melee_reflect_ratio", -1.0))
	var cap: int = int(th.get("melee_reflect_cap", -1))
	var thorns_ok: bool = ratio > 0.0 and cap > 0
	_affix_cfg_ok = missing.is_empty() and thorns_ok
	if not _affix_cfg_ok:
		_record_accept(
			"2.4.2",
			"fail",
			"cfg_bad missing=%s ratio=%.2f cap=%d" % [
				"-".join(missing) if not missing.is_empty() else "-",
				ratio,
				cap,
			]
		)


## 夜开始：教学无全场词缀 / 天灾全场+1（fail 不被后续 pass 抹掉）
func _accept_affix_night_rules(night: int, world: World) -> void:
	if world == null or world.enemy_spawner == null:
		return
	var rules: Dictionary = ConfigLoader.get_affix_rules()
	var teaching: int = int(rules.get("teaching_nights_no_affix", 4))
	var bonus: Array[String] = world.enemy_spawner.get_night_bonus_affixes()
	if night <= teaching:
		_record_accept_keep_fail(
			"2.4.3",
			"pass" if bonus.is_empty() else "fail",
			"teach_n=%d bonus=%d" % [night, bonus.size()]
		)
		return
	var calamity_nights: Variant = rules.get("calamity_nights", [10, 15, 20])
	var is_calamity: bool = false
	if calamity_nights is Array:
		for v in calamity_nights:
			if int(v) == night:
				is_calamity = true
				break
	if is_calamity:
		var want: int = int(rules.get("calamity_bonus_affixes", 1))
		var ok: bool = bonus.size() == want
		_record_accept_keep_fail(
			"2.4.3",
			"pass" if ok else "fail",
			"calamity_n=%d bonus=%d expect=%d" % [night, bonus.size(), want]
		)


## 夜中采样：同屏峰值 + 场上词缀种类；精英夜校验 2~3 词缀
func _accept_sample_enemies(world: World) -> void:
	if _suite_name == "" or world == null or world.enemy_pool == null:
		return
	var active: Array = world.enemy_pool.get_active()
	_peak_enemies = maxi(_peak_enemies, active.size())
	var rules: Dictionary = ConfigLoader.get_affix_rules()
	var amin: int = int(rules.get("elite_affix_min", 2))
	var amax: int = int(rules.get("elite_affix_max", 3))
	for n in active:
		if not (n is EnemyBase):
			continue
		var enemy: EnemyBase = n as EnemyBase
		if enemy.is_dead():
			continue
		for aid in enemy.affix_ids:
			var sid: String = String(aid)
			if sid != "":
				_seen_affix_ids[sid] = true
		if enemy.is_elite and not _elite_affix_checked:
			_elite_affix_checked = true
			var n_aff: int = enemy.affix_ids.size()
			var ok_elite: bool = n_aff >= amin and n_aff <= amax
			_record_accept_keep_fail(
				"2.4.3",
				"pass" if ok_elite else "fail",
				"elite_affix=%d expect=%d..%d" % [n_aff, amin, amax]
			)


## pass 不覆盖既有 fail（词缀夜规等多探针项）；fail 仍可打回
func _record_accept_keep_fail(id: String, status: String, detail: String = "") -> void:
	if status == "pass" and _accept_fail.has(id):
		return
	_record_accept(id, status, detail)


func _on_player_damaged_accept(_amount: int) -> void:
	if _suite_name == "":
		return
	if GameState.get_last_hit_source() != "affix_thorns":
		return
	var hit: int = GameState.get_last_hit_amount()
	_thorns_hits += 1
	_thorns_hit_max = maxi(_thorns_hit_max, hit)
	var cap: int = int(ConfigLoader.get_affix("thorns").get("melee_reflect_cap", 10))
	# applied 已含减伤，仍不得高于 raw cap
	var ok: bool = hit <= cap
	_record_accept(
		"2.4.2",
		"pass" if ok else "fail",
		"thorns_hit=%d max=%d cap=%d" % [hit, _thorns_hit_max, cap]
	)


func _ensure_chest_hook(world: World) -> void:
	if _suite_name == "" or world == null or world.pickup_system == null:
		return
	if _chest_hooked_world == world:
		return
	_disconnect_chest_hook()
	if not world.pickup_system.chest_opened.is_connected(_on_chest_opened_accept):
		world.pickup_system.chest_opened.connect(_on_chest_opened_accept)
	_chest_hooked_world = world


func _disconnect_chest_hook() -> void:
	if _chest_hooked_world != null and is_instance_valid(_chest_hooked_world):
		var ps: PickupSystem = _chest_hooked_world.pickup_system
		if ps != null and ps.chest_opened.is_connected(_on_chest_opened_accept):
			ps.chest_opened.disconnect(_on_chest_opened_accept)
	_chest_hooked_world = null


func _on_chest_opened_accept(kind: String, amount: int, rarity_name: String) -> void:
	if _suite_name == "":
		return
	var k: String = kind if kind != "" else "unknown"
	_chest_kinds_seen[k] = int(_chest_kinds_seen.get(k, 0)) + 1
	if k not in ACCEPT_CHEST_KINDS:
		return
	_record_accept(
		"4.5.4",
		"pass",
		"kind=%s amount=%d rarity=%s" % [k, amount, rarity_name]
	)


## 同屏峰值门槛：max(底数, max_enemies/4)
func _enemy_peak_min() -> int:
	var cap: int = int(ConfigLoader.get_difficulty_config().get("max_enemies", 350))
	return maxi(ACCEPT_ENEMY_PEAK_FLOOR, int(cap / 4))


## 有证据即打 pass（可多次覆盖为更新 detail；不覆盖既有 fail；同 detail 由 _record_accept 去重）
func _accept_emit_feature_progress() -> void:
	if _seen_affix_ids.size() > 0 and not _accept_fail.has("2.4.2"):
		var ids: Array[String] = []
		for k in _seen_affix_ids.keys():
			ids.append(String(k))
		ids.sort()
		var detail: String = "seen=%s" % ",".join(ids)
		if _thorns_hits > 0:
			detail += "_thorns_max=%d" % _thorns_hit_max
		_record_accept("2.4.2", "pass", detail)
	var peak_min: int = _enemy_peak_min()
	if _peak_enemies >= peak_min and not _accept_fail.has("4.9.1"):
		var cap: int = int(ConfigLoader.get_difficulty_config().get("max_enemies", 350))
		_record_accept(
			"4.9.1",
			"pass",
			"peak=%d min=%d max_enemies=%d" % [_peak_enemies, peak_min, cap]
		)


## 局末：未触发项 skip（不覆盖已有 pass/fail）
func _accept_finalize_feature_skips(peak_night: int) -> void:
	if not _accept_pass.has("4.5.4") and not _accept_fail.has("4.5.4"):
		if _chest_kinds_seen.is_empty():
			_record_accept("4.5.4", "skip", "no_chest_opened")
		else:
			var kinds: Array[String] = []
			for k in _chest_kinds_seen.keys():
				kinds.append(String(k))
			kinds.sort()
			_record_accept("4.5.4", "skip", "no_known_kind=%s" % ",".join(kinds))
	var peak_min: int = _enemy_peak_min()
	if not _accept_pass.has("4.9.1") and not _accept_fail.has("4.9.1"):
		if peak_night >= 8:
			_record_accept(
				"4.9.1",
				"skip",
				"peak=%d_below_min=%d" % [_peak_enemies, peak_min]
			)
		else:
			_record_accept("4.9.1", "skip", "peak_night=%d" % peak_night)
	# 2.4.2：仅场上词缀 / 荆棘命中可 pass；配置自检 alone → skip（避免假绿）
	if not _accept_pass.has("2.4.2") and not _accept_fail.has("2.4.2"):
		if _affix_cfg_ok:
			_record_accept("2.4.2", "skip", "cfg_ok_no_field_sample")
		else:
			_record_accept("2.4.2", "skip", "no_affix_evidence")
	elif _thorns_hits <= 0 and _accept_pass.has("2.4.2"):
		_record_accept("2.4.2", "info", "thorns_hits=0")
	if not _accept_pass.has("2.4.3") and not _accept_fail.has("2.4.3"):
		_record_accept("2.4.3", "skip", "no_rule_sample")


func _tick_max_night_cutoff(delta: float) -> void:
	_action_timer -= delta
	if _action_timer > 0.0:
		return
	_cutoff_restart_pending = false
	_note_serial_run_finished()
	_finalize_run_outcome(false)
	# 截断夜次：1.1.1 需 ≥10；3.3 需 ≥8
	if _max_night >= 10:
		_record_accept("1.1.1", "pass", "cutoff_n=%d" % _max_night)
	if _max_night >= 8:
		_record_accept("3.3", "pass", "cutoff_n=%d" % _max_night)
	if _should_quit_after_runs():
		_quit_bot_suite("max_night_then_max_runs")
		return
	if _sweep_pending_quit:
		_quit_after_sweep_if_pending()
		return
	print("[TestBot] 夜上限 N%d 截断 → 重开" % _max_night)
	_begin_next_bot_run()


func _should_quit_after_runs() -> bool:
	return _max_runs > 0 and _completed_runs >= _max_runs


## 结算/截断共用：end_run → 选角（含 cycle）→ 灯塔 → reload
func _begin_next_bot_run() -> void:
	MetaSystem.end_run()
	_prepare_new_run_meta()
	var char_id: String = _pick_run_character()
	MetaSystem.set_active_character(char_id)
	_apply_lighthouse_for_new_run()
	_emit_run_start_accepts(char_id)
	print(
		"[TestBot] 下一局角色 %s 难度=%s"
		% [char_id, DifficultySystem.get_tier()]
	)
	if get_tree() != null:
		get_tree().paused = false
		get_tree().reload_current_scene()
	_action_timer = RESULT_RESTART_DELAY


func _emit_run_start_accepts(char_id: String) -> void:
	if char_id == "":
		return
	_record_accept("1.2.3", "pass", "char=%s" % char_id)
	var data: Dictionary = ConfigLoader.get_character(char_id)
	_record_accept("4.6.1", "pass" if not data.is_empty() else "fail", "char=%s" % char_id)
	var weapon: String = ConfigLoader.get_character_starting_weapon(char_id)
	var expect_weapon: String = String(data.get("starting_weapon", ""))
	var weapon_ok: bool = weapon != "" and weapon == expect_weapon
	_record_accept(
		"4.6.3",
		"pass" if weapon_ok else "fail",
		"char=%s weapon=%s" % [char_id, weapon]
	)
	var traits: Dictionary = data.get("traits", {})
	_record_accept(
		"4.6.5",
		"pass" if not traits.is_empty() else "fail",
		"char=%s trait_keys=%d" % [char_id, traits.size()]
	)


func _init_script_error_scan() -> void:
	_log_scan_path = OS.get_user_data_dir().path_join("logs").path_join("godot.log")
	_script_error_count = 0
	_log_scan_offset = 0
	if FileAccess.file_exists(_log_scan_path):
		var f: FileAccess = FileAccess.open(_log_scan_path, FileAccess.READ)
		if f != null:
			_log_scan_offset = f.get_length()
			f.close()


func _poll_script_errors() -> void:
	if _log_scan_path == "" or not FileAccess.file_exists(_log_scan_path):
		return
	var f: FileAccess = FileAccess.open(_log_scan_path, FileAccess.READ)
	if f == null:
		return
	var length: int = f.get_length()
	# 轮转/截断：重新锚定到当前 EOF，不重扫文件头（避免把历史 SCRIPT ERROR 算进本会话）
	if _log_scan_offset > length:
		_log_scan_offset = length
		f.close()
		return
	f.seek(_log_scan_offset)
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.contains("SCRIPT ERROR") or line.contains("Error at:"):
			_script_error_count += 1
	_log_scan_offset = f.get_position()
	f.close()


func _quit_bot_suite(reason: String) -> void:
	_poll_script_errors()
	print(
		"[TestBot] 套件结束 reason=%s completed_runs=%d wins=%d script_err=%d"
		% [reason, _completed_runs, _wins, _script_error_count]
	)
	_print_accept_summary()
	if get_tree() != null:
		get_tree().paused = false
		get_tree().quit()


func _print_accept_summary() -> void:
	if _summary_printed:
		return
	if _suite_name == "" and _accept_pass.is_empty() and _accept_fail.is_empty():
		return
	_summary_printed = true
	_poll_script_errors()
	var prev_pass_52: bool = _accept_pass.has("5.2")
	_reconcile_accept_5_2()
	# 仅在汇总时从 pass 打回 fail 才补打一行，避免噪音
	if prev_pass_52 and _accept_fail.has("5.2"):
		_BotSuite.emit_accept(
			"5.2",
			"fail",
			"reconcile runs_ge8=%d script_err=%d" % [_runs_reached_n8, _script_error_count]
		)
	var pass_ids: Array[String] = []
	for k in _accept_pass.keys():
		pass_ids.append(String(k))
	pass_ids.sort()
	var fail_ids: Array[String] = []
	for k2 in _accept_fail.keys():
		fail_ids.append(String(k2))
	fail_ids.sort()
	var skip_ids: Array[String] = []
	for cid in _suite_checklist:
		if not _accept_pass.has(cid) and not _accept_fail.has(cid):
			skip_ids.append(cid)
	print(
		"[TestBot] ACCEPT_SUMMARY suite=%s runs=%d wins=%d ge8=%d ge10=%d script_err=%d pass=%s fail=%s skip=%s"
		% [
			_suite_name if _suite_name != "" else "-",
			_completed_runs,
			_wins,
			_runs_reached_n8,
			_runs_reached_n10,
			_script_error_count,
			",".join(pass_ids) if not pass_ids.is_empty() else "-",
			",".join(fail_ids) if not fail_ids.is_empty() else "-",
			",".join(skip_ids) if not skip_ids.is_empty() else "-",
		]
	)
