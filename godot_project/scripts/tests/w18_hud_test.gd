# ============================================================================
# W18HudTest — HUD 抬头显示机检
# 验收：血条/经验条/夜数/难度档位/教学夜徽标/Boss 提示/武器槽/被动槽 均正确填充；
#       难度档位可切换并在 HUD 上反映。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w18_hud_test.tscn
# ============================================================================
extends Node2D

const HUD_SCRIPT = preload("res://scripts/core/hud.gd")
const WEAPON_MANAGER = preload("res://scripts/combat/weapon_manager.gd")
const SPATIAL_HASH = preload("res://scripts/core/spatial_hash.gd")
const PROJECTILE_POOL = preload("res://scripts/core/projectile_pool.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W18 HUD 抬头显示 机检")
	print("============================================================")
	GameState.start_new_run("watcher", 20260818)
	DifficultySystem.reset_tier()
	GameState.add_weapon("harpoon")
	GameState.add_passive("pearl")

	# 构建武器管理器（HUD 武器槽依赖其实例列表）
	var wm: WeaponManager = WEAPON_MANAGER.new()
	add_child(wm)
	var player_stub: Node2D = Node2D.new()
	add_child(player_stub)
	var hash_stub: SpatialHash = SPATIAL_HASH.new()
	var pool_stub: ProjectilePool = PROJECTILE_POOL.new()
	add_child(pool_stub)
	wm.setup(player_stub, hash_stub, pool_stub)
	wm.sync_from_game_state()

	# 构建 HUD（程序化节点；勿 set_script 后调自定义方法）
	var hud: Control = HUD_SCRIPT.new()
	add_child(hud)
	hud.init(wm)
	hud.refresh()

	print("[assert] 基础填充")
	_assert(hud._hp_label.text.contains("HP"), "血条文案 (HP)")
	_assert(hud._exp_label.text.contains("Lv"), "经验条文案 (Lv)")
	_assert(hud._night_label.text.contains("第") and hud._night_label.text.contains("夜"), "夜数文案")
	_assert(hud._diff_label.text.contains("灯塔"), "难度档位默认=灯塔守望")
	_assert(hud._weapon_box.get_child_count() >= 1, "武器槽 >= 1 (实际 %d)" % hud._weapon_box.get_child_count())
	_assert(hud._passive_box.get_child_count() >= 1, "被动槽 >= 1 (实际 %d)" % hud._passive_box.get_child_count())

	print("[assert] 教学夜徽标（夜 1）")
	GameState.current_night = 1
	hud.refresh()
	_assert(hud._night_label.text.contains("教学夜"), "教学夜徽标 (夜1)")

	print("[assert] 难度切换（守夜人）")
	DifficultySystem.set_tier("watcher")
	hud.refresh()
	_assert(hud._diff_label.text.contains("守夜人"), "难度切换=守夜人")

	print("[assert] Boss 提示（天灾夜 10）")
	GameState.current_night = 10
	hud.refresh()
	_assert(hud._boss_label.text.contains("Boss"), "Boss 提示 (夜10)")

	print("[assert] 教学演示武器 loadout_changed → HUD 武器槽")
	var chips_before: int = hud._weapon_box.get_child_count()
	var granted: String = GameState.grant_teaching_demo_weapon(2)
	_assert(granted == "holy_fire", "授予演示武器 holy_fire")
	_assert(hud._weapon_box.get_child_count() > chips_before,
		"HUD 武器槽随 loadout_changed 增加 (%d→%d)" % [chips_before, hud._weapon_box.get_child_count()])

	DifficultySystem.reset_tier()
	print("------------------------------------------------------------")
	print("W18 HUD 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
