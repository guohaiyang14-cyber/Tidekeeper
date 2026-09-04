# ============================================================================
# TestBot — Debug 模式自动试玩机器人
# 职责：debug.bat（--debug）启动时模拟玩家：选角开局、夜间走位拾取、
#       三选一/商店/结算自动推进，便于无人值守冒烟试玩。
# 红线：仅 debug 启动且非 headless/单测场景；不修改 GameState 数值逻辑。
# ============================================================================
extends Node

const MAIN_SCENE: String = "res://scenes/main.tscn"
const CHAR_SELECT_SCENE: String = "res://scenes/character_select.tscn"

const UI_ACTION_DELAY: float = 0.55
const CHAR_SELECT_DELAY: float = 0.9
const RESULT_RESTART_DELAY: float = 1.1
const SHOP_DWELL: float = 1.8

# 夜间走位（仅 Debug 机器人；非玩法数值表）
# 日志主因：contact:deep_diver（潜地后脚下浮现）；贴脸时 dist≈0 旧 flee 直接 skip，再停捡珠会连吃接触伤。
const ORBIT_SPEED: float = 1.85
const STRUGGLE_HUNT_RADIUS: float = 520.0
const STRUGGLE_SAFE_ELITE: float = 420.0
const STRUGGLE_SAFE_THORNS: float = 140.0
const ELITE_SCAN_RADIUS: float = 1000.0
const ELITE_MIN_DIST_N5: float = 520.0
const ELITE_MIN_DIST: float = 300.0
## 锁链精英：被打会减速，需拉得更开（夜结束靠计时，不强制击杀精英）
const ELITE_MIN_DIST_CHAIN: float = 620.0
## N4 起深潜者登场：扩大逃离半径（不必等到 N5）
const FLEE_RADIUS_N4: float = 400.0
const FLEE_RADIUS_N5: float = 480.0
const FLEE_RADIUS: float = 260.0
const DANGER_HP_RATIO: float = 0.85
const CHEST_SEEK_RANGE: float = 420.0
const CHEST_SAFE_ENEMY: float = 110.0
const CHEST_SAFE_ELITE: float = 420.0
const GEM_SEEK_RANGE: float = 360.0
const GEM_SAFE_ENEMY: float = 80.0
const GEM_SAFE_ELITE: float = 360.0
const ELITE_FLEE_WEIGHT: float = 5.5
const THORNS_FLEE_WEIGHT: float = 3.2
const SWIFT_FLEE_WEIGHT: float = 2.4
const CHAIN_FLEE_WEIGHT: float = 2.8
const BURROW_FLEE_WEIGHT: float = 4.0
## 贴脸/突袭后锁定逃跑方向，避免轨道掉头又撞回去
const PANIC_STICK_SEC: float = 0.85
const PANIC_CONTACT_DIST: float = 48.0
const BURROW_SCAN_RADIUS: float = 720.0
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


func _ready() -> void:
	_enabled = _compute_enabled()
	if _enabled:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_combat_stats = _BotCombatStats.new()
		# 注册后 EnemyBase 命中路径只判静态引用，避免每击 get_node
		EnemyBase.set_combat_telemetry(self)
		print("[TestBot] 已启用 — 自动模拟玩家（关闭：环境变量 TIDEKEEPER_NO_TEST_BOT=1 或 --no-test-bot）")
		get_tree().scene_changed.connect(_on_scene_changed)
		GameState.night_started.connect(_on_night_started)
		GameState.night_ended.connect(_on_night_ended)
		GameState.game_over.connect(_on_game_over_stats)
		GameState.game_win.connect(_on_game_win_stats)
		_reset_scene_timers()
	else:
		EnemyBase.set_combat_telemetry(null)
		process_mode = Node.PROCESS_MODE_DISABLED


func is_active() -> bool:
	return _enabled


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


func _on_night_started(night: int) -> void:
	_panic_timer = 0.0
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
	if _want_survival_bias() and id in ["pearl", "exp_sac"]:
		return 5
	if offer.get("type") == "weapon":
		# 临近精英夜：已有武器升级仍优先，但新武器低于高分减伤被动
		if id in GameState.weapon_slots:
			return 88
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
	# 消耗品回血：低血或进 N4/N5 前抬到最高优先（休息回血在过完 N5 之后才结算）
	if kind == "consumable" or id in ["storm_flask"]:
		var hp_ratio: float = 1.0
		if GameState.player_max_health > 0:
			hp_ratio = float(GameState.player_health) / float(GameState.player_max_health)
		if hp_ratio < 0.92 or _want_survival_bias():
			base = maxi(base, 130)
	if kind == "weapon" and owned:
		return 86 if not _want_survival_bias() else 70
	# 生存期：未拥有新武器再降，把钱留给护身符/珊瑚屏障
	if kind == "weapon" and not owned and _want_survival_bias():
		base = mini(base, 36)
	# 已有减伤被动继续叠级
	if kind == "passive" and owned and id in ["amulet", "coral_barrier"]:
		return 140 + (22 if _want_survival_bias() else 0)
	return base + (12 if owned else 0)


func _want_survival_bias() -> bool:
	return GameState.current_night >= SURVIVAL_BIAS_FROM_NIGHT


func _survival_item_score(id: String) -> int:
	var bias: int = 22 if _want_survival_bias() else 0
	match id:
		"amulet", "coral_barrier":
			return 120 + bias
		"storm_flask":
			# 进化钥 + 常作回血消耗品入口；生存期仍高于纯输出
			return 78 + bias
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

	var elite_pos: Vector2 = _nearest_elite_position(world, pos, ELITE_SCAN_RADIUS)
	var elite_near: bool = elite_pos != Vector2.INF
	var elite_dist: float = pos.distance_to(elite_pos) if elite_near else 9999.0
	var elite_min_dist: float = _elite_keep_distance(world, elite_pos)
	# N5 开场精英刷在玩家上方约 200：立刻南向拉开，勿捡箱/珠
	if elite_near and elite_dist < elite_min_dist:
		if hp_ratio < DANGER_HP_RATIO:
			var rescue_chest: Vector2 = _safe_chest_direction(world, pos)
			if rescue_chest != Vector2.ZERO and _chest_away_from_elite(rescue_chest, pos, elite_pos):
				return rescue_chest
		return _kite_away_from(elite_pos, pos, flee, kite, 6.0, 2.6)

	# 低血：优先安全宝箱（可能回血），再风筝
	if hp_ratio < DANGER_HP_RATIO:
		var low_hp_chest: Vector2 = _safe_chest_direction(world, pos)
		if low_hp_chest != Vector2.ZERO:
			return low_hp_chest

	# N4+ 有深潜者或贴身压力：放弃捡珠，切向风筝（保持移动吃掉突袭后的接触 CD）
	var diver_pressure: bool = GameState.current_night >= 4 and _has_burrow_enemy(world, pos, BURROW_SCAN_RADIUS)
	var danger: bool = (
		flee.length_squared() > 0.08
		or hp_ratio < DANGER_HP_RATIO
		or elite_near
		or diver_pressure
	)
	if danger:
		var away: Vector2 = flee.normalized() if flee.length_squared() > 0.0001 else _last_move_dir
		if away.length_squared() < 0.0001:
			away = kite
		if elite_near:
			away = (away + (pos - elite_pos).normalized() * 2.4).normalized()
		var tangent: Vector2 = Vector2(-away.y, away.x)
		if kite.dot(tangent) < 0.0:
			tangent = -tangent
		var away_w: float = 4.8 if hp_ratio > DANGER_HP_RATIO else 6.2
		if elite_near:
			away_w += 2.2
		if GameState.current_night >= 4:
			away_w += 1.4
		if diver_pressure:
			away_w += 1.6
			# 深潜压力下少绕圈，优先直线拉开
			tangent *= 0.45
		var combined: Vector2 = away * away_w + tangent * 2.6 + kite * 0.1
		if combined.length_squared() < 0.01:
			return away
		return combined.normalized()

	# 安全时优先捡宝箱（主动触碰），再捡经验珠
	var chest_dir: Vector2 = _safe_chest_direction(world, pos)
	if chest_dir != Vector2.ZERO:
		return chest_dir
	var gem_dir: Vector2 = _safe_gem_direction(world, pos)
	if gem_dir != Vector2.ZERO:
		return gem_dir
	return kite


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
	for enemy in _query_enemies(world, elite_pos, 40.0):
		if not (enemy.is_elite or enemy.is_boss):
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
	if _nearest_elite_position(world, chest, CHEST_SAFE_ELITE) != Vector2.INF:
		return Vector2.ZERO
	var to_chest: Vector2 = chest - pos
	if to_chest.length_squared() < 4.0:
		return Vector2.ZERO
	return to_chest.normalized()


func _safe_gem_direction(world: World, pos: Vector2) -> Vector2:
	if world.pickup_system == null:
		return Vector2.ZERO
	var gem_out: Array[Vector2] = [Vector2.ZERO]
	if not world.pickup_system.try_nearest_gem_position(pos, gem_out, GEM_SEEK_RANGE):
		return Vector2.ZERO
	var gem: Vector2 = gem_out[0]
	if _nearest_enemy_distance(world, gem, GEM_SAFE_ENEMY + 24.0) <= GEM_SAFE_ENEMY:
		return Vector2.ZERO
	if _nearest_elite_position(world, gem, GEM_SAFE_ELITE) != Vector2.INF:
		return Vector2.ZERO
	var to_gem: Vector2 = gem - pos
	if to_gem.length_squared() < 4.0:
		return Vector2.ZERO
	return to_gem.normalized()


func _nearest_elite_position(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for enemy in _query_enemies(world, pos, radius):
		if not enemy.is_elite and not enemy.is_boss:
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


## 挣扎击杀目标：排除 floor 补刷 / 荆棘怪；优先远离精英的软怪
func _nearest_struggle_target(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	var elite_ref: Vector2 = _nearest_elite_position(world, pos, ELITE_SCAN_RADIUS)
	for enemy in _query_enemies(world, pos, radius):
		if enemy.is_floor_refill or enemy.is_elite or enemy.is_boss:
			continue
		if enemy.has_affix("thorns"):
			continue
		var epos: Vector2 = enemy.global_position
		if elite_ref != Vector2.INF and epos.distance_to(elite_ref) < STRUGGLE_SAFE_ELITE * 0.7:
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
	if GameState.current_night >= 5:
		danger_radius = FLEE_RADIUS_N5
	elif GameState.current_night >= 4:
		danger_radius = FLEE_RADIUS_N4
	for enemy in _query_enemies(world, pos, danger_radius):
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
		if enemy.is_elite or enemy.is_boss:
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


func _projectile_flee_vector(world: World, pos: Vector2) -> Vector2:
	if world.enemy_projectile_pool == null:
		return Vector2.ZERO
	var flee: Vector2 = Vector2.ZERO
	var look: float = 160.0
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
		flee += (offset.normalized() * 0.55 + side.normalized() * 0.9) * urgency
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
