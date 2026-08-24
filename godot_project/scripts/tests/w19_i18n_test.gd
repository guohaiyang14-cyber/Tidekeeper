# ============================================================================
# W19I18nTest — 双语切换机检
# 验收：默认中文；set_language 切英文后 localize/localizef 返回英文；偏好持久化；
#       缺失 key 安全回退；HUD/ResultUI/角色卡切语言；配置实体名 i18n。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w19_i18n_test.tscn
# ============================================================================
extends Node2D

const HUD_SCRIPT = preload("res://scripts/core/hud.gd")
const RESULT_UI = preload("res://scripts/core/result_ui.gd")
const WEAPON_MANAGER = preload("res://scripts/combat/weapon_manager.gd")
const SPATIAL_HASH = preload("res://scripts/core/spatial_hash.gd")
const PROJECTILE_POOL = preload("res://scripts/core/projectile_pool.gd")
const CHARACTER_SELECT = preload("res://scripts/ui/character_select.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W19 i18n 双语切换 机检")
	print("============================================================")
	LanguageSystem.set_language("zh")

	print("[assert] 默认/中文")
	_assert(LanguageSystem.localize("ui.difficulty") == "难度：", "zh 难度前缀")
	_assert(LanguageSystem.localize("ui.game_over") == "游戏结束", "zh 游戏结束")
	_assert(LanguageSystem.localize("ui.victory") == "通关", "zh 通关")
	_assert(LanguageSystem.localize("ui.restart") == "再来一局 (Enter)", "zh 重开按钮")
	_assert(LanguageSystem.localizef("ui.hud.hp", [80, 100]) == "HP 80 / 100", "zh localizef hp")

	print("[assert] 切换英文")
	LanguageSystem.set_language("en")
	_assert(LanguageSystem.get_language() == "en", "当前语言=en")
	_assert(LanguageSystem.localize("ui.difficulty") == "Difficulty: ", "en 难度前缀")
	_assert(LanguageSystem.localize("ui.game_over") == "Game Over", "en 游戏结束")
	_assert(LanguageSystem.localize("ui.victory") == "Victory", "en 通关")
	_assert(LanguageSystem.localize("ui.boss_warn") == "⚠ Boss appears this night", "en Boss 提示")
	_assert(LanguageSystem.localizef("ui.hud.exp", [2, 10, 50]) == "Lv 2  XP 10 / 50", "en localizef exp")
	_assert(SaveSystem.get_settings().get("language") == "en", "语言偏好已持久化")

	print("[assert] 配置实体名")
	_assert(LanguageSystem.localize_config_name("weapon", "harpoon", "鱼叉枪") == "Harpoon", "en weapon.harpoon")
	_assert(LanguageSystem.localize_config_name("enemy", "small_goblin", "小水鬼") == "Tide Imp", "en enemy.small_goblin")
	_assert(LanguageSystem.localize_config_desc("character", "watcher", "守望者") == "Balanced watcher. +5% all stats. Starts with Harpoon. Beginner-friendly.", "en character.watcher.desc")

	print("[assert] HUD 切语言")
	_test_hud_language()

	print("[assert] ResultUI 切语言")
	_test_result_ui_language()

	print("[assert] 角色选择卡切语言")
	_test_character_select_language()

	print("[assert] 缺失 key 回退")
	_assert(LanguageSystem.localize("no.such.key") == "no.such.key", "缺失 key 回退自身")

	print("[assert] 切回中文")
	LanguageSystem.set_language("zh")
	_assert(LanguageSystem.localize("ui.difficulty") == "难度：", "切回中文正确")

	print("------------------------------------------------------------")
	print("W19 i18n 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


func _test_hud_language() -> void:
	GameState.start_new_run("watcher", 20260824)
	DifficultySystem.reset_tier()
	GameState.add_weapon("harpoon")
	var wm: WeaponManager = WEAPON_MANAGER.new()
	add_child(wm)
	var player_stub: Node2D = Node2D.new()
	add_child(player_stub)
	var hash_stub: SpatialHash = SPATIAL_HASH.new()
	var pool_stub: ProjectilePool = PROJECTILE_POOL.new()
	add_child(pool_stub)
	wm.setup(player_stub, hash_stub, pool_stub)
	wm.sync_from_game_state()
	var hud: Control = HUD_SCRIPT.new()
	add_child(hud)
	hud.init(wm)
	LanguageSystem.set_language("en")
	hud.refresh()
	hud._on_loadout_changed()
	_assert(hud._exp_label.text.contains("XP"), "HUD en 经验文案")
	_assert(hud._weapon_box.get_child_count() >= 1, "HUD 武器槽存在")
	var chip: PanelContainer = hud._weapon_box.get_child(0) as PanelContainer
	var wlbl: Label = chip.get_child(0) as Label
	_assert(wlbl != null and wlbl.text.contains("Harpoon"), "HUD en 武器名 Harpoon")


func _test_result_ui_language() -> void:
	var ui: ResultUI = RESULT_UI.new()
	add_child(ui)
	DifficultySystem.reset_tier()
	ui.show_game_over("hp_zero", 6, 3, 100, 50)
	LanguageSystem.set_language("en")
	_assert(ui._stats.text.contains("Survived"), "ResultUI en stats")
	_assert(ui._reason.text.contains("Cause"), "ResultUI en reason")
	_assert(ui._stardust.text.contains("Stardust"), "ResultUI en stardust")


func _test_character_select_language() -> void:
	MetaSystem.reset_progress()
	var cs: Control = CHARACTER_SELECT.new()
	add_child(cs)
	await get_tree().process_frame
	LanguageSystem.set_language("en")
	await get_tree().process_frame
	var card: Dictionary = cs._char_cards[0]
	var trait_l: Label = card.get("trait_l") as Label
	_assert(trait_l != null and trait_l.text.contains("Damage"), "角色卡 en 特性 Damage")
	var name_l: Label = card.get("name_l") as Label
	_assert(name_l != null and name_l.text == "Watcher", "角色卡 en 名称 Watcher")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
