# ============================================================================
# W10EvolutionTest — 8 进化路径融合 + 掉落配额机检
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w10_evolution_test.tscn
# ============================================================================
extends Node

const _WEAPON_HARPOON = preload("res://scripts/combat/weapon_harpoon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W10 进化路径 / 掉落 / 共鸣 机检")
	print("============================================================")
	_test_config_paths()
	_test_fuse_all_eight()
	_test_slot_return_and_item_consume()
	_test_soft_cap()
	_test_elite_and_boss_drops()
	_test_evolved_damage_mult()
	print("------------------------------------------------------------")
	print("W10 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _reset_run() -> void:
	GameState.start_new_run("watcher", 20261010)
	EvolutionSystem.on_night_start(1)


func _max_weapon(wid: String) -> void:
	if wid not in GameState.weapon_slots:
		GameState.add_weapon(wid)
	while GameState.get_weapon_level(wid) < GameState.max_weapon_level:
		if not GameState.add_weapon(wid):
			break


func _max_passive(pid: String) -> void:
	if pid not in GameState.passive_slots:
		GameState.add_passive(pid)
	while GameState.get_passive_level(pid) < GameState.max_passive_level:
		if not GameState.add_passive(pid):
			break


func _test_config_paths() -> void:
	print("[配置]")
	var ids: Array = ConfigLoader.get_all_evolution_weapon_ids()
	_assert(ids.size() == 8, "evolutions.paths = 8")
	_assert(ConfigLoader.get_all_passive_ids().size() == 12, "passives = 12（4 通用 + 8 钥）")
	for wid in ids:
		var path: Dictionary = ConfigLoader.get_evolution_path(String(wid))
		var pid: String = String(path.get("passive_id", ""))
		var w: Dictionary = ConfigLoader.get_weapon(String(wid))
		var evo: Dictionary = w.get("evolution", {})
		_assert(pid != "" and not ConfigLoader.get_passive(pid).is_empty(), "%s 钥被动存在" % wid)
		_assert(String(evo.get("required_passive_id", "")) == pid, "%s weapons.required_passive_id 对齐" % wid)


func _test_fuse_all_eight() -> void:
	print("[8 路径融合]")
	_reset_run()
	# 腾出槽：清默认鱼叉后再逐条测；每条独立开局
	for wid_v in ConfigLoader.get_all_evolution_weapon_ids():
		var wid: String = String(wid_v)
		_reset_run()
		GameState.weapon_slots.clear()
		GameState.weapon_levels.clear()
		GameState.evolved_weapons.clear()
		var path: Dictionary = EvolutionSystem.get_path(wid)
		var pid: String = String(path.get("passive_id", ""))
		_max_weapon(wid)
		_max_passive(pid)
		GameState.evolution_items = 1
		_assert(EvolutionSystem.can_fuse(wid), "%s 可融合" % wid)
		var ok: bool = EvolutionSystem.fuse(wid)
		_assert(ok, "%s fuse 成功" % wid)
		_assert(GameState.is_weapon_evolved(wid), "%s 已标记进化" % wid)
		_assert(GameState.get_evolved_name(wid) == String(path.get("evolved_name", "")), "%s 进化名" % wid)
		_assert(pid not in GameState.passive_slots, "%s 被动槽已返还" % wid)
		_assert(GameState.evolution_items == 0, "%s 耗 1 道具" % wid)


func _test_slot_return_and_item_consume() -> void:
	print("[槽位/道具]")
	_reset_run()
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	_max_weapon("holy_fire")
	_max_passive("lamp_oil")
	GameState.evolution_items = 0
	_assert(not EvolutionSystem.can_fuse("holy_fire"), "无道具不可融合")
	GameState.evolution_items = 1
	var before_slots: int = GameState.passive_slots.size()
	EvolutionSystem.fuse("holy_fire")
	_assert(GameState.passive_slots.size() == before_slots - 1, "融合返还被动槽")


func _test_soft_cap() -> void:
	print("[软上限]")
	_reset_run()
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	_max_weapon("harpoon")
	var soft: int = int(ConfigLoader.get_evolution_rules().get("soft_cap_unused_items", 2))
	GameState.evolution_items = soft
	var got: int = EvolutionSystem.grant_items(3, true, true)
	_assert(got == 0, "达软上限不再发放（宝箱/事件路径）")
	GameState.evolution_items = 0
	got = EvolutionSystem.grant_items(5, true, true)
	_assert(got == soft, "发放受软上限截断 (= %d)" % soft)
	# Boss / 第5夜保底精英无视软上限
	GameState.evolution_items = soft
	var b: int = EvolutionSystem.try_boss_drop(10)
	_assert(b == 1, "Boss 必掉无视软上限")
	_assert(GameState.evolution_items == soft + 1, "Boss 掉落后可超过软上限")
	EvolutionSystem.on_night_start(5)
	GameState.evolution_items = soft
	var e: int = EvolutionSystem.try_elite_drop(5, true)
	_assert(e == 1, "第5夜保底精英无视软上限")


func _test_elite_and_boss_drops() -> void:
	print("[掉落]")
	_reset_run()
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	# 无可进化项
	var n0: int = EvolutionSystem.try_elite_drop(5, true)
	_assert(n0 == 0, "无可进化项时精英不掉")
	_max_weapon("harpoon")
	EvolutionSystem.on_night_start(5)
	var n1: int = EvolutionSystem.try_elite_drop(5, true)
	_assert(n1 == 1, "第5夜命名精英掉 1")
	var n2: int = EvolutionSystem.try_elite_drop(5, true)
	_assert(n2 == 0, "当夜精英池上限 1")
	EvolutionSystem.on_night_start(10)
	GameState.evolution_items = 0
	var b10: int = EvolutionSystem.try_boss_drop(10)
	_assert(b10 == 1, "第10夜 Boss 掉 1")
	EvolutionSystem.on_night_start(15)
	GameState.evolution_items = 0
	var b15: int = EvolutionSystem.try_boss_drop(15)
	_assert(b15 == 2, "第15夜 Boss 掉 2")


func _test_evolved_damage_mult() -> void:
	print("[传说伤害倍率]")
	_reset_run()
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	_max_weapon("harpoon")
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var w: WeaponBase = WeaponHarpoon.new()
	w.configure(data, GameState.max_weapon_level)
	var base_dmg: int = w.get_leveled_damage()
	GameState.mark_weapon_evolved("harpoon", "深渊鱼叉")
	var evo_dmg: int = w.get_leveled_damage()
	_assert(evo_dmg > base_dmg, "进化后伤害提升 (%d → %d)" % [base_dmg, evo_dmg])
	w.free()
