# ============================================================================
# HUD — 战斗抬头显示（W18 UI 完善）
# 职责：实时展示 血条 / 经验条 / 等级 / 夜数 / 难度档位 / 教学夜徽标 /
#       Boss 提示 / 武器槽 / 被动槽。
# 设计：与 result_ui.gd 一致的程序化构建（不手绘 .tscn 节点）；
#       每帧 refresh() 拉取 GameState / WeaponManager / DifficultySystem 状态；
#       武器槽 / 被动槽仅在 loadout_changed 时重建，避免每帧 churn。
# 红线：本节点只读展示，不直接改 GameState 数值；数值变更走各 autoload。
# 坐标基准：设计分辨率 1280×720（Godot 视口缩放保证不同分辨率对齐）。
# ============================================================================
extends Control

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0

var _weapon_mgr: WeaponManager = null

var _hp_bar: ProgressBar
var _hp_label: Label
var _exp_bar: ProgressBar
var _exp_label: Label
var _night_label: Label
var _diff_label: Label
var _boss_label: Label
var _weapon_box: HBoxContainer
var _passive_box: HBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	if not GameState.loadout_changed.is_connected(_on_loadout_changed):
		GameState.loadout_changed.connect(_on_loadout_changed)
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	refresh()


func init(wm: WeaponManager) -> void:
	_weapon_mgr = wm
	refresh()
	_on_loadout_changed()  # 初始构建武器/被动槽（loadout_changed 可能已在 HUD 创建前触发）


# ---------------------------------------------------------------------------
# 构建静态元素
# ---------------------------------------------------------------------------
func _build() -> void:
	# 左上信息面板（血条 + 经验条 + 夜数）
	var top := Control.new()
	top.position = Vector2(12.0, 12.0)
	top.size = Vector2(420.0, 72.0)
	add_child(top)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(panel)

	_hp_bar = ProgressBar.new()
	_hp_bar.size = Vector2(396.0, 22.0)
	_hp_bar.position = Vector2(12.0, 8.0)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.position = Vector2(16.0, 10.0)
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	top.add_child(_hp_label)

	_exp_bar = ProgressBar.new()
	_exp_bar.size = Vector2(396.0, 14.0)
	_exp_bar.position = Vector2(12.0, 36.0)
	_exp_bar.show_percentage = false
	_exp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_exp_bar)
	_exp_label = Label.new()
	_exp_label.position = Vector2(16.0, 35.0)
	_exp_label.add_theme_font_size_override("font_size", 12)
	_exp_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	top.add_child(_exp_label)

	_night_label = Label.new()
	_night_label.position = Vector2(12.0, 54.0)
	_night_label.add_theme_font_size_override("font_size", 15)
	_night_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	top.add_child(_night_label)

	# 右上：难度档位 + Boss 提示
	_diff_label = Label.new()
	_diff_label.position = Vector2(VIEW_W - 360.0, 12.0)
	_diff_label.size = Vector2(348.0, 24.0)
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_diff_label.add_theme_font_size_override("font_size", 16)
	_diff_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_diff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_diff_label)

	_boss_label = Label.new()
	_boss_label.position = Vector2(VIEW_W - 360.0, 40.0)
	_boss_label.size = Vector2(348.0, 24.0)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_label.add_theme_font_size_override("font_size", 16)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_label)

	# 左下：武器槽 + 被动槽
	_weapon_box = HBoxContainer.new()
	_weapon_box.position = Vector2(12.0, VIEW_H - 72.0)
	_weapon_box.add_theme_constant_override("separation", 6)
	add_child(_weapon_box)
	_passive_box = HBoxContainer.new()
	_passive_box.position = Vector2(12.0, VIEW_H - 40.0)
	_passive_box.add_theme_constant_override("separation", 6)
	add_child(_passive_box)


# ---------------------------------------------------------------------------
# 每帧刷新（world._process 调用；游戏结束/通关时 world 显式再调一次）
# ---------------------------------------------------------------------------
func refresh() -> void:
	if _hp_bar == null:
		return
	var hp: int = GameState.player_health
	var maxhp: int = GameState.player_max_health
	_hp_bar.max_value = maxi(1, maxhp)
	_hp_bar.value = clampi(hp, 0, maxhp)
	_hp_label.text = LanguageSystem.localizef("ui.hud.hp", [hp, maxhp])

	var lvl: int = GameState.player_level
	var need: int = ExpTable.get_exp(lvl)
	_exp_bar.max_value = maxi(1, need)
	_exp_bar.value = clampi(GameState.player_exp, 0, need)
	_exp_label.text = LanguageSystem.localizef("ui.hud.exp", [lvl, GameState.player_exp, need])

	var night: int = GameState.current_night
	var teach: String = LanguageSystem.localize("ui.teaching") if DifficultySystem.is_teaching_night(night) else ""
	_night_label.text = LanguageSystem.localizef("ui.hud.night", [night, teach])

	_diff_label.text = LanguageSystem.localize("ui.difficulty") + DifficultySystem.get_tier_label()

	if DifficultySystem.boss_prompt_enabled() and _is_boss_night(night):
		_boss_label.text = LanguageSystem.localize("ui.boss_warn")
	else:
		_boss_label.text = ""


func _on_loadout_changed() -> void:
	# 先于重建同步实例，避免 signal 连接顺序导致 HUD 读到 stale WeaponManager
	if _weapon_mgr != null:
		_weapon_mgr.sync_from_game_state()
	_rebuild_slots(_weapon_box, _weapon_list())
	_rebuild_slots(_passive_box, _passive_list())


func _on_language_changed(_lang: String) -> void:
	refresh()
	_on_loadout_changed()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _is_boss_night(night: int) -> bool:
	var cal: Dictionary = ConfigLoader.get_boss_calamity()
	var nights: Variant = cal.get("calamity_nights", [10, 15, 20])
	if nights is Array:
		for v in nights:
			if int(v) == night:
				return true
	return false


func _weapon_list() -> Array[String]:
	var out: Array[String] = []
	if _weapon_mgr != null:
		for w in _weapon_mgr.get_weapons():
			var d: Dictionary = ConfigLoader.get_weapon(w.weapon_id)
			var wname: String = LanguageSystem.localize_config_name(
				"weapon", w.weapon_id, String(d.get("name", w.weapon_id)))
			out.append("%s Lv%d" % [wname, w.level])
	return out


func _passive_list() -> Array[String]:
	var out: Array[String] = []
	for pid in ConfigLoader.get_all_passive_ids():
		var lv: int = GameState.get_passive_level(pid)
		if lv > 0:
			var d: Dictionary = ConfigLoader.get_passive(pid)
			var pname: String = LanguageSystem.localize_config_name(
				"passive", pid, String(d.get("name", pid)))
			out.append("%s Lv%d" % [pname, lv])
	return out


func _rebuild_slots(box: HBoxContainer, items: Array[String]) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for it in items:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl := Label.new()
		lbl.text = it
		lbl.add_theme_font_size_override("font_size", 13)
		chip.add_child(lbl)
		box.add_child(chip)
