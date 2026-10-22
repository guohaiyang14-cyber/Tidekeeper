# ============================================================================
# W18HudTest — HUD 抬头显示机检
# 验收：血条/经验条/夜数（仅第N夜）/难度档位/Boss 提示/武器槽/被动槽 均正确填充；
#       难度档位可切换并在 HUD 上反映。
# 布局铁律（2026-10-21 截图反馈返工）：潮币在经验条之后；条上文案与条同矩形垂直居中；
#       武器/被动两行不重叠且无背景面板。
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
	_assert(hud._diff_label.text.contains("守夜人"), "难度档位默认=守夜人（首局友好）")
	_assert(hud._weapon_box.get_child_count() >= 1, "武器槽 >= 1 (实际 %d)" % hud._weapon_box.get_child_count())
	_assert(hud._passive_box.get_child_count() >= 1, "被动槽 >= 1 (实际 %d)" % hud._passive_box.get_child_count())

	print("[assert] 布局铁律（截图反馈返工）")
	# 潮币在经验条之后（右侧同一行），不得回夜数行与调试信息重叠
	_assert(hud._coin_icon.position.x >= hud._exp_bar.position.x + hud._exp_bar.size.x,
		"潮币图标在经验条之后 (x=%.0f, 经验条右缘=%.0f)" % [
			hud._coin_icon.position.x, hud._exp_bar.position.x + hud._exp_bar.size.x])
	_assert(hud._coin_icon.position.y < hud._night_label.position.y,
		"潮币与夜数不同行 (y=%.0f vs 夜数 y=%.0f)" % [hud._coin_icon.position.y, hud._night_label.position.y])
	# 条上文案与条同矩形（不错位）：label 覆盖 bar 且垂直居中
	# 条上文案：进度条子节点 + 全矩形锚点（Godot 4.7 默认主题 Label 最小高 23，
	# 手工 position/size 会被最小尺寸顶掉 → 错位；子节点锚点方案不受条高变化影响）
	_assert(hud._hp_label.get_parent() == hud._hp_bar
		and hud._exp_label.get_parent() == hud._exp_bar,
		"条上文案为进度条子节点（全矩形锚点随条对齐）")
	_assert(hud._hp_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER
		and hud._exp_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		"条上文案垂直居中")
	_assert(absf(hud._hp_label.size.y - hud._hp_bar.size.y) < 0.01
		and absf(hud._exp_label.size.y - hud._exp_bar.size.y) < 0.01,
		"文案高度与条一致（锚点全矩形，不被最小高度顶掉）")
	_assert(hud._hp_bar.size.y >= 24.0 and hud._exp_bar.size.y >= 24.0,
		"条高 ≥24（容纳默认主题 Label 最小高 23）")
	_assert(hud._exp_bar.position.y + hud._exp_bar.size.y <= hud._night_label.position.y,
		"经验条不与夜数行重叠 (条底=%.0f, 夜数 y=%.0f)" % [
			hud._exp_bar.position.y + hud._exp_bar.size.y, hud._night_label.position.y])
	# 武器/被动两行不重叠
	var weapon_row_bottom: float = hud._weapon_box.position.y + 24.0
	_assert(weapon_row_bottom <= hud._passive_box.position.y,
		"武器行/被动行不重叠 (%.0f <= %.0f)" % [weapon_row_bottom, hud._passive_box.position.y])
	# 槽位无背景面板
	_assert(not (hud._weapon_box.get_child(0) is PanelContainer), "武器槽无背景面板")
	_assert(not (hud._passive_box.get_child(0) is PanelContainer), "被动槽无背景面板")
	# 左上信息区无背景面板（截图反馈 3）；潮币贴上边缘；无背景下浮动文字有描边
	var top_box: Control = hud.get_child(0) as Control
	_assert(top_box != null and not (top_box.get_child(0) is Panel),
		"左上信息区无背景面板（截图反馈）")
	_assert(hud._coin_icon.position.y <= hud._hp_bar.position.y + 4.0,
		"潮币贴上边缘（与 HP 条同顶行 y=%.0f）" % hud._coin_icon.position.y)
	_assert(hud._night_label.get_theme_constant("outline_size") >= 4
		and hud._coin_label.get_theme_constant("outline_size") >= 4,
		"无背景下夜数/潮币文字有深色描边保可读")

	print("[assert] 夜数仅显示第N夜（教学夜徽标移除）")
	GameState.current_night = 1
	hud.refresh()
	_assert(DifficultySystem.is_teaching_night(1), "教学夜机制仍在（难度系统口径，夜1）")
	_assert(not hud._night_label.text.contains("/ 20"), "夜数不显示 /20（截图反馈）")
	_assert(not hud._night_label.text.contains("教学夜"), "教学夜徽标已从 HUD 夜数移除（截图反馈）")
	_assert(hud._night_label.text.contains("第") and hud._night_label.text.contains("夜"), "夜数文案")

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

	print("[assert] 挣扎模式提示横幅（致命伤进入免死窗口）")
	# 夜 10 已过首夜保护；begin_run 后门控才允许挣扎（避免机检误食复活）
	MetaSystem.begin_run()
	GameState.current_night = 10
	GameState.player_health = GameState.player_max_health
	GameState.damage_player(100000, "enemy_contact")
	hud.refresh()
	_assert(GameState.is_struggling(), "致命伤进入挣扎窗口")
	_assert(hud._struggle_banner.visible, "挣扎横幅可见")
	_assert(hud._struggle_title.text != "", "挣扎标题非空")
	var need_kills: int = GameState.get_struggle_kills_needed()
	_assert(not hud._struggle_body.text.contains("%"), "挣扎正文已格式化（无 %% 占位符）")
	_assert(hud._struggle_body.text.contains("0/%d" % need_kills), "挣扎正文含击杀进度 0/%d" % need_kills)
	_assert(hud._struggle_body.text.contains("复活") or hud._struggle_body.text.contains("revive"),
		"挣扎正文含复活提示")
	GameState.revive_to_full()
	GameState.clear_over_state()
	MetaSystem.end_run()
	hud.refresh()
	_assert(not hud._struggle_banner.visible, "回血后横幅隐藏")

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
