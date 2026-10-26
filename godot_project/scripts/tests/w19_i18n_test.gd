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
	_assert(LanguageSystem.localizef("ui.struggle.body", [1, 5, 2.5])
		== "挣扎求生中 · 击杀 1/5 敌可复活 · 2.5 秒后结算", "zh localizef %.1f 挣扎")

	print("[assert] 切换英文")
	LanguageSystem.set_language("en")
	_assert(LanguageSystem.get_language() == "en", "当前语言=en")
	_assert(LanguageSystem.localize("ui.difficulty") == "Difficulty: ", "en 难度前缀")
	_assert(LanguageSystem.localize("ui.game_over") == "Game Over", "en 游戏结束")
	_assert(LanguageSystem.localize("ui.victory") == "Victory", "en 通关")
	_assert(LanguageSystem.localize("ui.boss_warn") == "⚠ Boss appears this night", "en Boss 提示")
	_assert(LanguageSystem.localizef("ui.hud.exp", [2, 10, 50]) == "Lv 2  XP 10 / 50", "en localizef exp")
	_assert(LanguageSystem.localizef("ui.struggle.body", [1, 5, 2.5])
		== "Struggling · kill 1/5 to revive · settle in 2.5s", "en localizef %.1f 挣扎")
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
	await _test_character_select_language()

	print("[assert] A7 事件/精炼/共鸣文案")
	_test_a7_display_names()

	print("[assert] 升级三选一切语言（2026-10-26 硬编码中文改 i18n）")
	_test_upgrade_ui_language()

	print("[assert] 宝箱提示切语言（稀有度 + 奖励类型）")
	_test_chest_toast_language()

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
	# 截图反馈返工后槽位无背景面板：HBoxContainer 直接子节点 = [TextureRect, Label]
	var wlbl: Label = null
	for c in hud._weapon_box.get_children():
		if c is Label:
			wlbl = c as Label
			break
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
	LanguageSystem.set_language("zh")
	await get_tree().process_frame
	var lang_btn: Button = cs._lang_btn as Button
	_assert(lang_btn != null, "语言切换钮存在")
	_assert(lang_btn.text == LanguageSystem.localize("ui.lang.en"), "zh 时按钮显示 English")
	LanguageSystem.set_language("en")
	await get_tree().process_frame
	_assert(lang_btn.text == LanguageSystem.localize("ui.lang.zh"), "en 时按钮显示 中文")
	var card: Dictionary = cs._char_cards[0]
	var trait_l: Label = card.get("trait_l") as Label
	_assert(trait_l != null and trait_l.text.contains("Damage"), "角色卡 en 特性 Damage")
	var name_l: Label = card.get("name_l") as Label
	_assert(name_l != null and name_l.text == "Watcher", "角色卡 en 名称 Watcher")
	cs.queue_free()


func _test_a7_display_names() -> void:
	EventSystem.reset()
	EventSystem.arm_event("storm", 2)
	LanguageSystem.set_language("zh")
	_assert(EventSystem.get_active_event_name() == "暴风雨", "事件 config 名仍为中文")
	_assert(EventSystem.get_active_event_display_name() == "暴风雨", "事件 UI zh")
	LanguageSystem.set_language("en")
	_assert(EventSystem.get_active_event_display_name() == "Storm", "事件 UI en")
	_assert(LanguageSystem.localize("refine.harpoon.name") == "Path of the Deep", "精炼路径 en")
	_assert(LanguageSystem.localize("ui.evo.resonance") == "Tide Resonance", "共鸣标题 en")
	LanguageSystem.set_language("zh")
	_assert(LanguageSystem.localize("refine.harpoon.name") == "深溯之径", "精炼路径 zh")


## 升级三选一：2026-10-26 用户反馈「提示信息应该跟所选的语言相同」——
## 本界面原为硬编码中文，改全量 i18n 后必须验证「切 en 无中文残留」。
## 覆盖：标题 / 提示 / 跳过按钮 / 重铸按钮 / 卡片类型标签 / 系列与分类映射 / 名称 / 描述
func _test_upgrade_ui_language() -> void:
	const UPGRADE_UI = preload("res://scripts/ui/upgrade_ui.gd")
	var ui: Control = UPGRADE_UI.new()
	add_child(ui)
	# 三张卡：武器 / 被动 / 潮币。字段严格对齐 UpgradeManager 的真实 offer 结构：
	#   武器 meta ← category（实际是 weapons.json attack_type，中文原值）
	#   被动 meta ← series（夜风/潮汐/灯塔/礁石）
	var offers: Array = [
		{"type": "weapon", "id": "harpoon", "name": "鱼叉枪", "category": "定向弹幕",
			"description": "穿透鱼叉"},
		{"type": "passive", "id": "pearl", "name": "夜明珠", "series": "潮汐",
			"category": "通用被动", "description": "视野 +1"},
		{"type": "tidecoins", "id": "tidecoins", "name": "潮币补给", "category": "溢出奖励",
			"amount": 20, "description": "获得 20 潮币"},
	]
	LanguageSystem.set_language("en")
	ui.call("_show", offers, true)
	_assert(ui.get("_title").text == "Level Up! Choose an upgrade", "升级标题 en")
	_assert(ui.get("_hint").text.contains("skip anytime"), "升级提示 en")
	_assert(ui.get("_skip_button").text.contains("Skip"), "跳过按钮 en")
	_assert(ui.get("_reroll_button").text == "Reroll (free)", "重铸按钮 en（免费态）")
	var metas: Array = ui.get("_card_meta")
	var names: Array = ui.get("_card_name")
	_assert(metas.size() >= 3 and names.size() >= 3, "三张卡片已渲染（%d 张）" % metas.size())
	if metas.size() >= 3:
		_assert(metas[0].text == "[Weapon] Projectile", "武器卡类型+攻击型 en（%s）" % metas[0].text)
		_assert(metas[1].text == "[Passive] Tide", "被动卡类型+系列 en（%s）" % metas[1].text)
		_assert(metas[2].text == "[Coins] Overflow reward", "潮币卡类型+分类 en（%s）" % metas[2].text)
		_assert(names[0].text.contains("Harpoon"), "武器名 en（%s）" % names[0].text)
		_assert(not _has_cjk(names[1].text), "被动名 en 无中文（%s）" % names[1].text)
		_assert(names[2].text.contains("Coin Cache"), "溢出奖励名 en（%s）" % names[2].text)
	# 中文残留检查：en 态下所有可见文案不含 CJK
	# 2026-10-26 code-review 补：原先只扫 name/meta，漏了 _card_desc——而卡片描述正是
	# 「按 id 走 localize_config_desc」那条路径，漏扫等于该路径没有回归网。
	var descs: Array = ui.get("_card_desc")
	_assert(descs.size() >= 3, "三张卡片描述已渲染（%d 张）" % descs.size())
	var cjk_hits: Array[String] = []
	for n in [ui.get("_title"), ui.get("_hint"), ui.get("_skip_button"), ui.get("_reroll_button")]:
		var t: String = _ctrl_text(n)
		if _has_cjk(t):
			cjk_hits.append(t)
	for arr in [metas, names, descs]:
		for n in arr:
			var t2: String = _ctrl_text(n)
			if _has_cjk(t2):
				cjk_hits.append(t2)
	_assert(cjk_hits.is_empty(), "升级界面 en 态无中文残留（%s）" % str(cjk_hits))
	# 描述确实被本地化过（不能是空串或残留中文冒充通过）
	if descs.size() >= 3:
		var d0: String = _ctrl_text(descs[0])
		var d1: String = _ctrl_text(descs[1])
		var d2: String = _ctrl_text(descs[2])
		_assert(d0 != "" and d1 != "" and d2 != "", "卡片描述非空（%s / %s / %s）" % [d0, d1, d2])
		_assert(d0 != "穿透鱼叉", "武器卡描述走 i18n 而非原中文（%s）" % d0)
		_assert(d2 == "Gain 20 coins", "溢出奖励描述走 i18n（%s）" % d2)
	# 切回中文：同一批控件即时刷新（LanguageSystem.language_changed → _refresh_static_texts）
	LanguageSystem.set_language("zh")
	_assert(ui.get("_title").text == "升级！选择一项强化", "切回中文标题即时生效")
	_assert(ui.get("_skip_button").text.contains("跳过"), "切回中文跳过按钮")
	ui.queue_free()


## 宝箱提示：稀有度 + 奖励类型都要跟随语言（HUD.notify_chest → _chest_kind_text）
func _test_chest_toast_language() -> void:
	GameState.start_new_run("watcher", 20261026)
	DifficultySystem.reset_tier()
	var hud: Control = HUD_SCRIPT.new()
	add_child(hud)
	hud.init(null)
	LanguageSystem.set_language("en")
	hud.notify_chest("tidecoins", 35, LanguageSystem.localize("ui.chest.rarity_1"))
	var toast: Label = hud.get("_toast_label")
	_assert(toast != null, "宝箱提示 Label 存在")
	if toast != null:
		_assert(toast.text.contains("Fine"), "宝箱稀有度 en（%s）" % toast.text)
		_assert(toast.text.contains("Coins"), "宝箱奖励类型 en（%s）" % toast.text)
		_assert(not _has_cjk(toast.text), "宝箱提示 en 态无中文残留（%s）" % toast.text)
	# 六类奖励都有英文标签（对齐 pickups.json 奖励池）
	var kinds_en: Array[String] = ["tidecoins", "heal", "evolution", "refine_essence", "weapon", "passive"]
	var missing: Array[String] = []
	for k in kinds_en:
		var t: String = String(hud.call("_chest_kind_text", k))
		if t == k or _has_cjk(t):
			missing.append("%s→%s" % [k, t])
	_assert(missing.is_empty(), "6 类宝箱奖励均有英文标签（%s）" % str(missing))
	LanguageSystem.set_language("zh")
	_assert(String(hud.call("_chest_kind_text", "tidecoins")) == "潮币", "宝箱奖励类型切回中文")
	_assert(String(hud.call("_chest_kind_text", "unknown_kind")) == "unknown_kind",
		"未知 kind 原样返回（不崩、不吞）")
	hud.queue_free()


## 是否含中日韩统一表意文字（用来查「en 态残留中文」）
## 取控件文案：Label 与 Button 都覆盖。
## 2026-10-26 修：原来统一写 (n as Label).text，_skip_button/_reroll_button 实为 Button，
## as Label 得到 null → 取 .text 触发 SCRIPT ERROR（断言仍全绿，属真实运行错误）。
func _ctrl_text(n: Object) -> String:
	if n == null:
		return ""
	if n is Label:
		return (n as Label).text
	if n is Button:
		return (n as Button).text
	return ""


func _has_cjk(s: String) -> bool:
	for c in s:
		var u: int = c.unicode_at(0)
		if u >= 0x4E00 and u <= 0x9FFF:
			return true
	return false


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
