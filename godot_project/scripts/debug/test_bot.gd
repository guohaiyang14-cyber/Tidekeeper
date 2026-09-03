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
const ORBIT_SPEED: float = 1.85
const STRUGGLE_HUNT_RADIUS: float = 640.0
const STRUGGLE_PACK_RADIUS: float = 520.0
const ELITE_SCAN_RADIUS: float = 900.0
const ELITE_MIN_DIST_N5: float = 360.0
const ELITE_MIN_DIST: float = 280.0
const FLEE_RADIUS_N5: float = 320.0
const FLEE_RADIUS: float = 240.0
const DANGER_HP_RATIO: float = 0.72
const CHEST_SEEK_RANGE: float = 420.0
const CHEST_SAFE_ENEMY: float = 100.0
const CHEST_SAFE_ELITE: float = 320.0
const GEM_SEEK_RANGE: float = 380.0
const GEM_SAFE_ENEMY: float = 72.0
const GEM_SAFE_ELITE: float = 280.0
const ELITE_FLEE_WEIGHT: float = 4.2
const THORNS_FLEE_WEIGHT: float = 2.2
const SWIFT_FLEE_WEIGHT: float = 1.5

var _enabled: bool = false
var _action_timer: float = 0.0
var _char_select_started: bool = false
var _orbit_angle: float = 0.0


func _ready() -> void:
	_enabled = _compute_enabled()
	if _enabled:
		process_mode = Node.PROCESS_MODE_ALWAYS
		print("[TestBot] 已启用 — 自动模拟玩家（关闭：环境变量 TIDEKEEPER_NO_TEST_BOT=1 或 --no-test-bot）")
		get_tree().scene_changed.connect(_on_scene_changed)
		_reset_scene_timers()
	else:
		process_mode = Node.PROCESS_MODE_DISABLED


func is_active() -> bool:
	return _enabled


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
	if offer.get("type") == "weapon":
		if id in GameState.weapon_slots:
			return 88
		return 36
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
	var owned: bool = id in GameState.weapon_slots or id in GameState.passive_slots
	var base: int = _survival_item_score(id)
	if str(item.get("kind", "")) == "weapon" and owned:
		return 86
	return base + (12 if owned else 0)


func _survival_item_score(id: String) -> int:
	match id:
		"amulet", "coral_barrier":
			return 100
		"lamp_core", "tide_bell", "storm_flask":
			return 72
		"lamp_oil", "iron_chain", "humus", "abyss_eye", "tide_compass":
			return 64
		"pearl":
			return 40
		"exp_sac":
			return 18
		_:
			return 50


func _tick_night_movement(world: World, delta: float) -> void:
	var player: Player = world.player as Player
	if player == null or player.is_bound():
		_release_move_actions()
		return
	var pos: Vector2 = player.global_position
	var dir: Vector2 = _compute_move_direction(world, pos, delta)
	_apply_move_direction(dir)


func _compute_move_direction(world: World, pos: Vector2, delta: float) -> Vector2:
	# 挣扎窗口：优先打附近「非 floor 补刷、非精英」的小怪凑 5 杀（floor 补刷不计入挣扎进度）
	if GameState.is_struggling():
		var soft: Vector2 = _nearest_struggle_target(world, pos, STRUGGLE_HUNT_RADIUS)
		if soft != Vector2.INF:
			return (soft - pos).normalized()
		var pack: Vector2 = _enemy_pack_centroid(world, pos, STRUGGLE_PACK_RADIUS)
		if pack != Vector2.INF:
			return (pack - pos).normalized()
		var hunt: Vector2 = _nearest_enemy_position(world, pos, STRUGGLE_HUNT_RADIUS)
		if hunt != Vector2.INF:
			return (hunt - pos).normalized()
		return Vector2.ZERO

	_orbit_angle += delta * ORBIT_SPEED
	var kite: Vector2 = Vector2(cos(_orbit_angle), sin(_orbit_angle))
	var flee: Vector2 = _enemy_flee_vector(world, pos) + _projectile_flee_vector(world, pos)
	var hp_ratio: float = 1.0
	if GameState.player_max_health > 0:
		hp_ratio = float(GameState.player_health) / float(GameState.player_max_health)

	var elite_pos: Vector2 = _nearest_elite_position(world, pos, ELITE_SCAN_RADIUS)
	var elite_near: bool = elite_pos != Vector2.INF
	var elite_dist: float = pos.distance_to(elite_pos) if elite_near else 9999.0
	# 精英夜：强制拉开；荆棘+迅捷贴脸几乎必死
	var elite_min_dist: float = ELITE_MIN_DIST_N5 if GameState.current_night >= 5 else ELITE_MIN_DIST
	if elite_near and elite_dist < elite_min_dist:
		# 低血仍可去「远离精英」的安全宝箱（回血箱）
		if hp_ratio < DANGER_HP_RATIO:
			var rescue_chest: Vector2 = _safe_chest_direction(world, pos)
			if rescue_chest != Vector2.ZERO:
				return rescue_chest
		var away_e: Vector2 = (pos - elite_pos).normalized()
		var tangent_e: Vector2 = Vector2(-away_e.y, away_e.x)
		if kite.dot(tangent_e) < 0.0:
			tangent_e = -tangent_e
		return (away_e * 4.6 + tangent_e * 2.2 + flee * 1.0).normalized()

	# 低血：优先安全宝箱（可能回血），再风筝
	if hp_ratio < DANGER_HP_RATIO:
		var low_hp_chest: Vector2 = _safe_chest_direction(world, pos)
		if low_hp_chest != Vector2.ZERO:
			return low_hp_chest

	# 贴身/中低血/精英在场：放弃捡珠，切向风筝
	var danger: bool = flee.length_squared() > 0.08 or hp_ratio < DANGER_HP_RATIO or elite_near
	if danger:
		var away: Vector2 = flee.normalized() if flee.length_squared() > 0.0001 else kite
		if elite_near:
			away = (away + (pos - elite_pos).normalized() * 1.8).normalized()
		var tangent: Vector2 = Vector2(-away.y, away.x)
		if kite.dot(tangent) < 0.0:
			tangent = -tangent
		var away_w: float = 4.0 if hp_ratio > DANGER_HP_RATIO else 5.4
		if elite_near:
			away_w += 1.6
		var combined: Vector2 = away * away_w + tangent * 2.4 + kite * 0.2
		if combined.length_squared() < 0.01:
			return kite
		return combined.normalized()

	# 安全时优先捡宝箱（主动触碰），再捡经验珠
	var chest_dir: Vector2 = _safe_chest_direction(world, pos)
	if chest_dir != Vector2.ZERO:
		return chest_dir
	var gem_dir: Vector2 = _safe_gem_direction(world, pos)
	if gem_dir != Vector2.ZERO:
		return gem_dir
	return kite


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


## 挣扎击杀目标：排除 floor 补刷（不计进度）与精英（贴脸易白给）
func _nearest_struggle_target(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for enemy in _query_enemies(world, pos, radius):
		if enemy.is_floor_refill or enemy.is_elite or enemy.is_boss:
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


func _nearest_enemy_position(world: World, pos: Vector2, radius: float) -> Vector2:
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for enemy in _query_enemies(world, pos, radius):
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


func _nearest_enemy_distance(world: World, pos: Vector2, radius: float) -> float:
	var best: float = radius + 1.0
	for enemy in _query_enemies(world, pos, radius):
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best:
			best = dist
	return best


func _enemy_pack_centroid(world: World, pos: Vector2, radius: float) -> Vector2:
	var acc: Vector2 = Vector2.ZERO
	var n: int = 0
	for enemy in _query_enemies(world, pos, radius):
		acc += enemy.global_position
		n += 1
	if n <= 0:
		return Vector2.INF
	return acc / float(n)


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
	var danger_radius: float = FLEE_RADIUS_N5 if GameState.current_night >= 5 else FLEE_RADIUS
	for enemy in _query_enemies(world, pos, danger_radius):
		var offset: Vector2 = pos - enemy.global_position
		var dist: float = offset.length()
		if dist < 0.001:
			continue
		var weight: float = 1.0 - (dist / danger_radius)
		weight *= 1.0 + float(enemy.danger) * 0.28
		if enemy.is_elite or enemy.is_boss:
			weight *= ELITE_FLEE_WEIGHT
		if enemy.has_affix("thorns"):
			weight *= THORNS_FLEE_WEIGHT
		if enemy.has_affix("swift"):
			weight *= SWIFT_FLEE_WEIGHT
		if enemy.behavior_type == "self_destruct":
			weight *= 2.1
		if enemy.behavior_type == "burrow_ambush":
			weight *= 1.7
		flee += offset.normalized() * weight
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
	if dir.x < -0.25:
		Input.action_press("move_left")
	elif dir.x > 0.25:
		Input.action_press("move_right")
	if dir.y < -0.25:
		Input.action_press("move_up")
	elif dir.y > 0.25:
		Input.action_press("move_down")


func _release_move_actions() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)
