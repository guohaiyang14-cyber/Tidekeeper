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
	# 优先级：升级已有武器 > 被动 > 新武器（教学期留槽给 demo_weapons）
	var best_weapon_up: int = -1
	var best_passive: int = -1
	var best_new_weapon: int = -1
	for i in offers.size():
		var offer: Dictionary = offers[i]
		if not _can_apply_offer(offer):
			continue
		var id: String = str(offer.get("id", ""))
		if offer.get("type") == "weapon":
			if id in GameState.weapon_slots:
				if best_weapon_up < 0:
					best_weapon_up = i
			elif best_new_weapon < 0:
				best_new_weapon = i
		elif best_passive < 0:
			best_passive = i
	if best_weapon_up >= 0:
		return best_weapon_up
	if best_passive >= 0:
		return best_passive
	return best_new_weapon


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
	# 先买已有武器/被动升级，再考虑新物品（同样遵守教学留槽）
	var items: Array = world.shop_manager.get_current_items()
	for prefer_owned in [true, false]:
		for item in items:
			var id: String = str(item.get("id", ""))
			var owned: bool = id in GameState.weapon_slots or id in GameState.passive_slots
			if prefer_owned != owned:
				continue
			if not _should_buy_shop_item(item):
				continue
			var cost: int = int(item.get("cost", 0))
			if cost > GameState.tidecoins:
				continue
			if world.shop_manager.buy(item):
				print("[TestBot] 购买 %s" % item.get("name", "?"))


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


func _tick_night_movement(world: World, delta: float) -> void:
	var player: Player = world.player as Player
	if player == null or player.is_bound():
		_release_move_actions()
		return
	var pos: Vector2 = player.global_position
	var dir: Vector2 = _compute_move_direction(world, pos, delta)
	_apply_move_direction(dir)


func _compute_move_direction(world: World, pos: Vector2, delta: float) -> Vector2:
	# 挣扎窗口必须贴脸击杀，否则 3s/5 杀必挂（机器人日志：夜5 反复 struggle 失败）
	if GameState.is_struggling():
		var hunt: Vector2 = _nearest_enemy_position(world, pos, 420.0)
		if hunt != Vector2.INF:
			return (hunt - pos).normalized()
		return Vector2.ZERO

	var target: Vector2 = Vector2.ZERO
	var has_target: bool = false
	if world.pickup_system != null:
		var gem_out: Array[Vector2] = [Vector2.ZERO]
		if world.pickup_system.try_nearest_gem_position(pos, gem_out):
			target = gem_out[0]
			has_target = true
	if not has_target:
		_orbit_angle += delta * 0.85
		var orbit_center: Vector2 = Vector2(640.0, 360.0)
		target = orbit_center + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * 140.0
	var flee: Vector2 = _enemy_flee_vector(world, pos)
	var to_target: Vector2 = (target - pos).normalized()
	var combined: Vector2 = to_target * 1.15 + flee * 2.4
	if combined.length_squared() < 0.01:
		return Vector2.ZERO
	return combined.normalized()


func _nearest_enemy_position(world: World, pos: Vector2, radius: float) -> Vector2:
	if world.spatial_hash_holder == null:
		return Vector2.INF
	var grid: SpatialHash = world.spatial_hash_holder.get_hash()
	if grid == null:
		return Vector2.INF
	var best_dist: float = radius
	var best_pos: Vector2 = Vector2.INF
	for node in grid.query_radius(pos, radius):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		var dist: float = pos.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = enemy.global_position
	return best_pos


func _enemy_flee_vector(world: World, pos: Vector2) -> Vector2:
	if world.spatial_hash_holder == null:
		return Vector2.ZERO
	var grid: SpatialHash = world.spatial_hash_holder.get_hash()
	if grid == null:
		return Vector2.ZERO
	var flee: Vector2 = Vector2.ZERO
	var danger_radius: float = 110.0
	for node in grid.query_radius(pos, danger_radius):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		var offset: Vector2 = pos - enemy.global_position
		var dist: float = offset.length()
		if dist < 0.001 or dist > danger_radius:
			continue
		var weight: float = 1.0 - (dist / danger_radius)
		flee += offset.normalized() * weight
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
