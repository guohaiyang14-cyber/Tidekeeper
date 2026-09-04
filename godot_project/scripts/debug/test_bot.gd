# ============================================================================
# TestBot — Debug 模式自动试玩机器人
# 职责：debug.bat（--debug）启动时模拟玩家：选角开局、夜间走位拾取、
#       三选一/商店/结算自动推进，便于无人值守冒烟试玩。
# 红线：仅 debug 启动且非 headless/单测场景；不修改 GameState 数值逻辑。
# 倍速：启用时 Engine.time_scale ∈ [2,10]（默认 4；--bot-speed=N / [ ] 调节）
# ============================================================================
extends Node

const MAIN_SCENE: String = "res://scenes/main.tscn"
const CHAR_SELECT_SCENE: String = "res://scenes/character_select.tscn"

const UI_ACTION_DELAY: float = 0.55
const CHAR_SELECT_DELAY: float = 0.9
const RESULT_RESTART_DELAY: float = 1.1
const SHOP_DWELL: float = 1.8

## 机器人试玩墙钟加速（非玩法数值；仅 Debug Bot）
const BOT_SPEED_MIN: float = 2.0
const BOT_SPEED_MAX: float = 10.0
const BOT_SPEED_DEFAULT: float = 4.0

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
const THORNS_FLEE_WEIGHT: float = 3.8
const SWIFT_FLEE_WEIGHT: float = 2.4
const CHAIN_FLEE_WEIGHT: float = 2.8
const BURROW_FLEE_WEIGHT: float = 4.0
## 贴脸/突袭后锁定逃跑方向，避免轨道掉头又撞回去
const PANIC_STICK_SEC: float = 1.15
const PANIC_CONTACT_DIST: float = 52.0
const BURROW_SCAN_RADIUS: float = 720.0
const PROJ_LOOK: float = 180.0
const PROJ_LOOK_CALAMITY: float = 300.0
## 对齐 config/enemies.json → metadata.affix_rules.calamity_nights（Bot 不读表，改夜次须同步）
const CALAMITY_NIGHTS: Array[int] = [10, 15, 20]
## 第 15 夜执政官（潮汐波光晕机制；与 bosses.json tide_archon.night 对齐）
const ARCHON_NIGHT: int = 15
## 第 3 夜昼起囤减伤（N4 深潜者 / N5 精英前）
const SURVIVAL_BIAS_FROM_NIGHT: int = 3

const _BotCombatStats = preload("res://scripts/debug/bot_combat_stats.gd")

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


func _ready() -> void:
	_enabled = _compute_enabled()
	if _enabled:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_combat_stats = _BotCombatStats.new()
		# 注册后 EnemyBase 命中路径只判静态引用，避免每击 get_node
		EnemyBase.set_combat_telemetry(self)
		_speed_scale = _resolve_initial_speed()
		_apply_speed_scale()
		print(
			"[TestBot] 已启用 — 自动模拟玩家 ×%.0f（[ / ] 调速 2~10；关闭：TIDEKEEPER_NO_TEST_BOT=1 或 --no-test-bot）"
			% _speed_scale
		)
		get_tree().scene_changed.connect(_on_scene_changed)
		GameState.night_started.connect(_on_night_started)
		GameState.night_ended.connect(_on_night_ended)
		GameState.game_over.connect(_on_game_over_stats)
		GameState.game_win.connect(_on_game_win_stats)
		_reset_scene_timers()
	else:
		EnemyBase.set_combat_telemetry(null)
		process_mode = Node.PROCESS_MODE_DISABLED


func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	EnemyBase.set_combat_telemetry(null)


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
	if night == ARCHON_NIGHT:
		print(
			"[TestBot] N%d 执政官策略：贴灯塔光晕内环绕（aura=%.0f）"
			% [night, _lighthouse_aura_radius()]
		)
	if _combat_stats == null:
		return
	_combat_stats.begin_night(night, _current_world())


func _on_night_ended(night: int) -> void:
	if _combat_stats == null:
		return
	_combat_stats.end_night(night, _current_world())


func _on_game_over_stats(_reason: String) -> void:
	if _combat_stats == null:
		return
	_combat_stats.flush_open_night(_current_world())


func _on_game_win_stats() -> void:
	if _combat_stats == null:
		return
	_combat_stats.flush_open_night(_current_world())


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
	var char_id: String = _pick_unlocked_character()
	MetaSystem.set_active_character(char_id)
	print("[TestBot] 选择角色 %s 并开始游戏" % char_id)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _pick_unlocked_character() -> String:
	var fallback: String = MetaSystem.get_active_character()
	if MetaSystem.is_character_unlocked(fallback):
		return fallback
	for id in ConfigLoader.get_all_character_ids():
		var cid: String = String(id)
		if MetaSystem.is_character_unlocked(cid):
			return cid
	return fallback


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
	print("[TestBot] 结算页 → 重开")
	if get_tree() != null:
		get_tree().paused = false
		get_tree().reload_current_scene()
	_action_timer = RESULT_RESTART_DELAY


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


func _offer_score(offer: Dictionary) -> int:
	var id: String = str(offer.get("id", ""))
	if (_want_survival_bias() or _want_calamity_prep()) and id in ["pearl", "exp_sac"]:
		return 5
	if offer.get("type") == "weapon":
		# 临近精英夜：已有武器升级仍优先，但新武器低于高分减伤被动
		if id in GameState.weapon_slots:
			return 88
		if _want_calamity_prep():
			return 22
		return 28 if _want_survival_bias() else 36
	return _survival_item_score(id)


func _can_apply_offer(offer: Dictionary) -> bool:
	var id: String = str(offer.get("id", ""))
	if id == "":
		return false
	if offer.get("type") == "weapon":
		if id in GameState.weapon_slots:
			return GameState.get_weapon_level(id) < GameState.max_weapon_level
		return _weapon_slots_free_for_new()
	if id in GameState.passive_slots:
		return GameState.get_passive_level(id) < GameState.max_passive_level
	return GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS


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
	for wid in EvolutionSystem.list_ready():
		if EvolutionSystem.fuse(wid):
			print("[TestBot] 融合武器 %s" % wid)
	for wid in RefineSystem.list_ready():
		if RefineSystem.refine(wid) > 0:
			print("[TestBot] 精炼武器 %s" % wid)
	# 按存活分买到没钱或没货（教学留槽仍由 _should_buy_shop_item 约束）。
	# buy 失败（槽满等）跳过该件，继续试下一候选，避免整段购买提前退出。
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
	# 生存期不买纯拾取/经验被动（对深潜突袭零帮助，占槽占钱）
	if _want_survival_bias() and id in ["pearl", "exp_sac"]:
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

	var flee: Vector2 = _enemy_flee_vector(world, pos) + _projectile_flee_vector(world, pos)
	var hp_ratio: float = 1.0
	if GameState.player_max_health > 0:
		hp_ratio = float(GameState.player_health) / float(GameState.player_max_health)
	var calamity: bool = _is_calamity_night()

	# N15 执政官：必须待在灯塔光晕内，远距风筝会周期性吃潮汐波
	if _is_archon_night():
		return _archon_move_direction(world, pos, flee, kite, hp_ratio, delta)

	var nearest_contact: float = _nearest_enemy_distance(world, pos, PANIC_CONTACT_DIST + 40.0)
	var burrow_threat: bool = _has_burrow_threat(world, pos, BURROW_SCAN_RADIUS)
	# 贴脸或潜地威胁：锁定逃离方向，禁止掉头/捡珠（深潜者脚下浮现后须立刻离开接触半径）
	if nearest_contact <= PANIC_CONTACT_DIST or burrow_threat:
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
	var danger: bool = (
		calamity
		or boss_near
		or flee.length_squared() > 0.08
		or hp_ratio < DANGER_HP_RATIO
		or elite_near
		or diver_pressure
	)
	if danger:
		var away: Vector2 = flee.normalized() if flee.length_squared() > 0.0001 else _last_move_dir
		if away.length_squared() < 0.0001:
			away = kite
		if boss_near:
			away = (away + (pos - boss_pos).normalized() * 3.2).normalized()
		elif elite_near:
			away = (away + (pos - elite_pos).normalized() * 2.4).normalized()
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
		+ flee * 1.35
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
			weight *= 2.1
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
		# 天灾弹幕是主伤源之一：略提高侧移权重
		var side_w: float = 1.15 if _is_calamity_night() else 0.9
		var back_w: float = 0.7 if _is_calamity_night() else 0.55
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
