# ============================================================================
# W20IntegrationTest — 全流程集成验收机检（W20）
# 验收目标（机器可验代理）：
#   1) 配置完整性：ConfigLoader 加载、关键计数、角色初始武器/难度档位/天灾夜 Boss 齐备。
#   2) 完整玩法闭环：开局(角色+难度档位) → 多夜刷怪/升级/拾币 → 昼间事件/商店/休息
#      → 终局夜通关 → 局外星尘结算 + 首通落盘 → 重开状态干净。
#   3) 失败路径：致死 → 挣扎窗口耗尽 → 判负 → 落败保底星尘结算落盘。
#   4) i18n 运行时：zh/en 切换 + 缺失 key 回退。
#   5) 难度档位集成：守夜人(0.7x) 敌人血量倍率低于灯塔(1.0x)。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w20_integration_test.tscn
# 说明：首局完成率>=60% 与 350 敌 60fps 为人工试玩/Profiler 验收项，本机检仅覆盖可机器验证部分。
# ============================================================================
extends Node2D

var _passed: int = 0
var _failed: int = 0
var _shop: ShopManager = null


func _ready() -> void:
	print("============================================================")
	print("W20 全流程集成验收 机检")
	print("============================================================")
	# 隔离存档（避免跨进程/跨局污染），恢复默认难度与语言
	MetaSystem.reset_progress()
	DifficultySystem.reset_tier()
	LanguageSystem.set_language("zh")

	_assert(ConfigLoader.is_loaded, "ConfigLoader 已加载")

	_phase_config_integrity()
	_phase_full_win_run("watcher", "lighthouse", 20260824)
	_phase_full_win_run("watcher", "watcher", 20260824)
	_phase_defeat_run("watcher", 20260824)
	_phase_i18n_runtime()

	print("------------------------------------------------------------")
	print("W20 集成验收 通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	if _shop != null:
		_shop.free()
		_shop = null
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


# ----------------------------------------------------------------------------
# Phase 1: 配置完整性（数据驱动红线抽样校验）
# ----------------------------------------------------------------------------
func _phase_config_integrity() -> void:
	print("[assert] 配置完整性")
	_assert(not ConfigLoader.weapons.is_empty(), "weapons.json 已加载")
	_assert(not ConfigLoader.enemies.is_empty(), "enemies.json 已加载")
	_assert(not ConfigLoader.bosses.is_empty(), "bosses.json 已加载")
	_assert(not ConfigLoader.events.is_empty(), "events.json 已加载")
	_assert(not ConfigLoader.passives.is_empty(), "passives.json 已加载")
	_assert(ConfigLoader.get_all_weapon_ids().size() >= 8, "武器数 >= 8 (=%d)" % ConfigLoader.get_all_weapon_ids().size())
	_assert(ConfigLoader.get_all_enemy_ids().size() >= 9, "敌人数 >= 9 (=%d)" % ConfigLoader.get_all_enemy_ids().size())
	_assert(ConfigLoader.get_all_passive_ids().size() >= 12, "被动数 >= 12 (=%d)" % ConfigLoader.get_all_passive_ids().size())

	# 天灾夜 Boss 齐备（10/15/20）
	_assert(not ConfigLoader.get_boss_by_night(10).is_empty(), "夜10 天灾 Boss 存在")
	_assert(not ConfigLoader.get_boss_by_night(15).is_empty(), "夜15 天灾 Boss 存在")
	_assert(not ConfigLoader.get_boss_by_night(20).is_empty(), "夜20 天灾 Boss 存在")

	# 角色初始武器全部有效
	for cid in ConfigLoader.get_all_character_ids():
		var sw: String = ConfigLoader.get_character_starting_weapon(cid)
		_assert(not ConfigLoader.get_weapon(sw).is_empty(), "角色 %s 初始武器 %s 存在" % [cid, sw])

	# W18 难度配置：档位 + max_enemies(350) 数据驱动
	var diff: Dictionary = ConfigLoader.get_difficulty_config()
	_assert(diff.has("tiers"), "难度档位表存在")
	_assert(diff.get("tiers", {}).has("lighthouse"), "档位 lighthouse 存在")
	_assert(diff.get("tiers", {}).has("watcher"), "档位 watcher 存在")
	_assert(int(diff.get("max_enemies", 0)) == 350, "max_enemies=350 (=%d)" % int(diff.get("max_enemies", 0)))

	# 难度档位集成：守夜人(0.7x) 敌人血量倍率 < 灯塔(1.0x)
	DifficultySystem.set_tier("lighthouse")
	var hp_lh: float = DifficultySystem.enemy_hp_multiplier(10)
	DifficultySystem.set_tier("watcher")
	var hp_wt: float = DifficultySystem.enemy_hp_multiplier(10)
	_assert(hp_wt < hp_lh, "守夜人敌血倍率<灯塔 (watcher=%.2f < lighthouse=%.2f)" % [hp_wt, hp_lh])
	DifficultySystem.reset_tier()


# ----------------------------------------------------------------------------
# Phase 2/3: 完整通关闭环（含升级/事件/商店/休息/结算/重开）
# ----------------------------------------------------------------------------
func _phase_full_win_run(char_id: String, tier: String, seed: int) -> void:
	print("[assert] 完整通关闭环 char=%s tier=%s" % [char_id, tier])
	DifficultySystem.set_tier(tier)
	MetaSystem.set_active_character(char_id)
	MetaSystem.begin_run()              # 须在 start_new_run 前（与 World 一致）
	if _shop == null:
		_shop = ShopManager.new()
	GameState.start_new_run(char_id, seed)

	_assert(GameState.player_health == GameState.player_max_health, "开局满血")
	_assert(GameState.weapon_slots.size() >= 1, "开局至少 1 把武器")
	_assert(GameState.current_night == 0, "开局夜次=0")

	var prev_level: int = 1
	for night in range(1, 21):
		GameState.enter_night(night)
		var hp_mult: float = DifficultySystem.enemy_hp_multiplier(night)
		var dmg_mult: float = DifficultySystem.enemy_damage_multiplier(night)
		_assert(hp_mult > 0.0 and dmg_mult > 0.0, "夜%d 难度倍率>0" % night)
		if DifficultySystem.is_teaching_night(night):
			_assert(hp_mult < DifficultySystem.enemy_hp_multiplier(5), "教学夜%d 敌血倍率低于常规夜" % night)

		# 模拟战斗：击杀推进升级 + 拾币（register_enemy_kill 驱动挣扎复活计数）
		var to_kill: int = 8 + night
		for i in range(to_kill):
			GameState.register_enemy_kill()
			GameState.add_exp(5)
			GameState.add_tidecoins(2)
		# 受击但保持存活（不触发挣扎/判负）
		GameState.damage_player(5, "enemy_contact")
		if GameState.player_health < GameState.player_max_health * 0.5:
			GameState.heal_player_to_full()

		# 状态不变量
		_assert(GameState.player_health > 0, "夜%d 存活(HP>0)" % night)
		_assert(GameState.player_health <= GameState.player_max_health, "夜%d 血量不超上限" % night)
		_assert(GameState.player_level >= prev_level, "夜%d 等级单调不减" % night)
		_assert(GameState.tidecoins >= 0, "夜%d 潮币非负" % night)
		prev_level = GameState.player_level

		# 夜尽 → 抉择之昼
		GameState.end_night()
		var upcoming: int = night + 1
		if upcoming <= 20:
			EventSystem.pick_for_night(upcoming)
			EventSystem.begin_night()       # arm 下一夜战斗修正
		MetaSystem.record_night_cleared(night)
		RestSystem.try_apply_rest_for_night(night)
		RestSystem.try_apply_night_regen()
		_shop_try_buy()

	_assert(GameState.is_final_night(), "到达终局夜 20")
	_assert(GameState.player_health > 0, "通关前存活")

	# 通关结算（与 World._on_game_win 对齐）
	GameState.arm_game_win()
	GameState.trigger_game_win()
	_assert(GameState.is_over, "通关置 is_over")
	MetaSystem.end_run()
	MetaSystem.record_night_cleared(20)
	MetaSystem.record_run_started(char_id)
	var earned: int = MetaSystem.settle_stardust(20, true, GameState.stardust)
	_assert(earned > 0, "通关结算星尘>0 (=%d)" % earned)
	_assert(SaveSystem.get_save_meta().get("first_clear") == true, "首通标记已落盘")
	_assert(int(SaveSystem.get_save_meta().get("stardust", 0)) >= earned, "星尘已累加落盘")

	# 重开：状态干净
	GameState.start_new_run(char_id, seed)
	_assert(GameState.player_health == GameState.player_max_health, "重开满血")
	_assert(GameState.current_night == 0, "重开夜次归零")
	_assert(GameState.tidecoins == 0, "重开潮币归零")
	_assert(GameState.player_level == 1, "重开等级=1")
	DifficultySystem.reset_tier()


# ----------------------------------------------------------------------------
# Phase 4: 失败路径（致死 → 挣扎窗口耗尽 → 判负 → 落败保底）
# ----------------------------------------------------------------------------
func _phase_defeat_run(char_id: String, seed: int) -> void:
	print("[assert] 失败路径（落败保底结算）")
	MetaSystem.reset_progress()         # 干净存档，首通=false，可验证保底
	DifficultySystem.reset_tier()
	MetaSystem.set_active_character(char_id)
	MetaSystem.begin_run()
	GameState.start_new_run(char_id, seed)

	# 活过前几夜（推进进度统计）
	for night in [1, 2, 3, 4, 5]:
		GameState.enter_night(night)
		GameState.register_enemy_kill()
		GameState.end_night()
		MetaSystem.record_night_cleared(night)

	# 第 6 夜致命伤（超出首夜保护 4 夜）：进入挣扎或判负
	GameState.enter_night(6)
	GameState.player_health = 1
	GameState.damage_player(999, "boss_tide_archon")
	if GameState.is_player_down():
		# 挣扎免死窗口中：耗尽窗口 → 判负
		GameState.advance_timers_for_test(10.0)
	_assert(GameState.is_over, "落败判负 is_over")

	MetaSystem.end_run()
	MetaSystem.record_run_started(char_id)
	var before_stardust: int = int(SaveSystem.get_save_meta().get("stardust", 0))
	var earned: int = MetaSystem.settle_stardust(6, false, GameState.stardust)
	_assert(earned >= 0, "落败结算星尘>=0 (=%d)" % earned)
	_assert(int(SaveSystem.get_save_meta().get("stardust", 0)) >= before_stardust + earned, "落败星尘落盘")


# ----------------------------------------------------------------------------
# Phase 5: i18n 运行时（zh/en 切换 + 缺失 key 回退）
# ----------------------------------------------------------------------------
func _phase_i18n_runtime() -> void:
	print("[assert] i18n 运行时双语")
	LanguageSystem.set_language("zh")
	_assert(LanguageSystem.localize("ui.game_over") == "游戏结束", "zh ui.game_over")
	_assert(LanguageSystem.localize("ui.victory") == "通关", "zh ui.victory")
	LanguageSystem.set_language("en")
	_assert(LanguageSystem.localize("ui.game_over") == "Game Over", "en ui.game_over")
	_assert(LanguageSystem.localize("ui.victory") == "Victory", "en ui.victory")
	_assert(LanguageSystem.localize("difficulty.tier.lighthouse") != "", "难度档位 key 有值(en)")
	_assert(LanguageSystem.localize("difficulty.tier.watcher") != "", "难度档位 key 有值(en)")
	# 缺失 key 回退自身
	_assert(LanguageSystem.localize("no.such.key.x") == "no.such.key.x", "缺失 key 回退自身")
	LanguageSystem.set_language("zh")


# ----------------------------------------------------------------------------
# 商店冒烟：开商店 + 购买一件（潮币充足时），不因槽满/余额不足崩溃
# ----------------------------------------------------------------------------
func _shop_try_buy() -> void:
	if _shop == null:
		return
	_shop.open_shop()
	var items: Array = _shop.get_current_items()
	_assert(items.size() >= 4, "商店在售 >= 4 件 (=%d)" % items.size())
	for it in items:
		if GameState.tidecoins >= int(it.get("cost", 0)):
			_shop.buy(it)   # 槽满/重复被动会退款返回 false，均属正常，不崩溃
			break
	_shop.close_shop()
