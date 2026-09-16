# ============================================================================
# ResultUI — 结算/死因界面（W10 + W17 + A6 死因面板）
# ============================================================================
extends Control

class_name ResultUI

const _UI := preload("res://scripts/ui/ui_chrome.gd")
const VIEW_W: float = 1280.0

var _title: Label
var _reason: Label
var _stats: Label
var _stardust: Label
var _restart_btn: Button
var _meta_btn: Button
var _hint: Label
var _death_panel: Panel
var _death_title: Label
var _death_cause: Label
var _showing_victory: bool = false
var _last_game_over_reason: String = ""
var _last_night: int = 0
var _last_level: int = 0
var _last_tidecoins: int = 0
var _last_stardust_earned: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	visible = false
	print("[ResultUI] 就绪")


func _build_frame() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 72.0
	_title.offset_bottom = 140.0
	_title.add_theme_font_size_override("font_size", 52)
	add_child(_title)

	_reason = Label.new()
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_reason.offset_top = 148.0
	_reason.offset_bottom = 188.0
	_reason.add_theme_font_size_override("font_size", 22)
	_reason.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	add_child(_reason)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stats.offset_top = 200.0
	_stats.offset_bottom = 250.0
	_stats.add_theme_font_size_override("font_size", 20)
	_stats.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	add_child(_stats)

	_stardust = Label.new()
	_stardust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stardust.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stardust.offset_top = 258.0
	_stardust.offset_bottom = 290.0
	_stardust.add_theme_font_size_override("font_size", 20)
	_stardust.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(_stardust)

	_death_panel = _UI.make_panel(_UI.death_panel_style())
	_death_panel.name = "DeathPanel"
	_death_panel.position = Vector2(VIEW_W * 0.5 - 320.0, 304.0)
	_death_panel.size = Vector2(640.0, 120.0)
	_death_panel.visible = false
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_panel)

	var death_box := VBoxContainer.new()
	death_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_box.offset_left = 12.0
	death_box.offset_right = -12.0
	death_box.offset_top = 8.0
	death_box.offset_bottom = -8.0
	death_box.add_theme_constant_override("separation", 4)
	_death_panel.add_child(death_box)

	_death_title = Label.new()
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title.add_theme_font_size_override("font_size", 15)
	_death_title.add_theme_color_override("font_color", Color(1.0, 0.70, 0.72))
	death_box.add_child(_death_title)

	_death_cause = Label.new()
	_death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death_cause.add_theme_font_size_override("font_size", 15)
	_death_cause.add_theme_color_override("font_color", Color(0.95, 0.82, 0.85))
	_death_cause.size_flags_vertical = Control.SIZE_EXPAND_FILL
	death_box.add_child(_death_cause)

	_restart_btn = Button.new()
	_UI.style_button(_restart_btn)
	_restart_btn.text = LanguageSystem.localize("ui.restart")
	_restart_btn.size = Vector2(280.0, 56.0)
	_restart_btn.position = Vector2(VIEW_W / 2.0 - 140.0, 448.0)
	_restart_btn.add_theme_font_size_override("font_size", 22)
	_restart_btn.pressed.connect(_on_restart_pressed)
	add_child(_restart_btn)

	_meta_btn = Button.new()
	_UI.style_button(_meta_btn)
	_meta_btn.text = LanguageSystem.localize("ui.meta")
	_meta_btn.size = Vector2(280.0, 48.0)
	_meta_btn.position = Vector2(VIEW_W / 2.0 - 140.0, 514.0)
	_meta_btn.add_theme_font_size_override("font_size", 20)
	_meta_btn.pressed.connect(_on_meta_pressed)
	add_child(_meta_btn)

	_hint = Label.new()
	_hint.text = LanguageSystem.localize("ui.hint")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -50.0
	_hint.offset_bottom = -20.0
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	add_child(_hint)
	_refresh_localized_static()


func _refresh_localized_static() -> void:
	if _restart_btn == null:
		return
	_restart_btn.text = LanguageSystem.localize("ui.restart")
	_meta_btn.text = LanguageSystem.localize("ui.meta")
	_hint.text = LanguageSystem.localize("ui.hint")
	if _death_title != null:
		_death_title.text = LanguageSystem.localize("ui.death.panel_title")


func _on_language_changed(_lang: String) -> void:
	_refresh_localized_static()
	if not visible:
		return
	if _showing_victory:
		_apply_victory_text()
	else:
		_apply_game_over_text()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("restart"):
		_on_restart_pressed()
		get_viewport().set_input_as_handled()


func show_game_over(reason: String, night: int, level: int, tidecoins: int, stardust_earned: int = 0) -> void:
	_showing_victory = false
	_last_game_over_reason = reason
	_last_night = night
	_last_level = level
	_last_tidecoins = tidecoins
	_last_stardust_earned = stardust_earned
	_apply_game_over_text()
	_show()


func show_victory(night: int, level: int, tidecoins: int, stardust_earned: int = 0) -> void:
	_showing_victory = true
	_last_night = night
	_last_level = level
	_last_tidecoins = tidecoins
	_last_stardust_earned = stardust_earned
	_apply_victory_text()
	_show()


func _apply_game_over_text() -> void:
	var is_retire: bool = _last_game_over_reason == "early_retire"
	if is_retire:
		_title.text = LanguageSystem.localize("ui.early_retire")
		_title.remove_theme_color_override("font_color")
		_title.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	else:
		_title.text = LanguageSystem.localize("ui.game_over")
		_title.remove_theme_color_override("font_color")
		_title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_reason.text = _reason_label(_last_game_over_reason)
	_stats.text = LanguageSystem.localizef("ui.result.stats_defeat", [
		_last_night, _last_level, _last_tidecoins, DifficultySystem.get_tier_label(),
	])
	_stardust.text = LanguageSystem.localizef("ui.result.stardust", [
		_last_stardust_earned, MetaSystem.get_stardust(),
	])
	if is_retire:
		_death_cause.text = ""
		if _death_panel != null:
			_death_panel.visible = false
	else:
		_death_cause.text = _death_cause_text()
		if _death_panel != null:
			_death_panel.visible = true


func _apply_victory_text() -> void:
	_title.text = LanguageSystem.localize("ui.victory")
	_title.remove_theme_color_override("font_color")
	_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	_reason.text = LanguageSystem.localize("ui.result.victory_reason")
	_stats.text = LanguageSystem.localizef("ui.result.stats_victory", [
		_last_night, _last_level, _last_tidecoins, DifficultySystem.get_tier_label(),
	])
	_stardust.text = LanguageSystem.localizef("ui.result.stardust", [
		_last_stardust_earned, MetaSystem.get_stardust(),
	])
	_death_cause.text = ""
	if _death_panel != null:
		_death_panel.visible = false


func _show() -> void:
	visible = true
	if _restart_btn != null:
		_restart_btn.grab_focus()


func _on_restart_pressed() -> void:
	if get_tree() != null:
		get_tree().paused = false
	get_tree().reload_current_scene()


func _on_meta_pressed() -> void:
	if get_tree() != null:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _reason_label(reason: String) -> String:
	match reason:
		"hp_zero": return LanguageSystem.localize("ui.death.reason.hp_zero")
		"timeout": return LanguageSystem.localize("ui.death.reason.timeout")
		"death": return LanguageSystem.localize("ui.death.reason.death")
		"early_retire": return LanguageSystem.localize("ui.death.reason.early_retire")
		_: return LanguageSystem.localizef("ui.death.reason.other", [reason])


func _death_cause_text() -> String:
	var a: Dictionary = GameState.get_death_analysis()
	var lines: Array[String] = []
	var last: String = String(a.get("last_hit_source", ""))
	var last_amt: int = int(a.get("last_hit_amount", 0))
	lines.append(LanguageSystem.localizef("ui.death.last_hit", [
		_source_label(last if last != "" else "unknown"), last_amt,
	]))
	var top: Array = a.get("top_sources", [])
	if top.is_empty():
		lines.append(LanguageSystem.localize("ui.death.no_record"))
	else:
		var parts: Array[String] = []
		for i in top.size():
			var s: Dictionary = top[i]
			parts.append(LanguageSystem.localizef("ui.death.top_entry", [
				i + 1, _source_label(String(s.get("source", "?"))), int(s.get("damage", 0)),
			]))
		lines.append(LanguageSystem.localizef("ui.death.top_sources", [top.size(), "  ".join(parts)]))
	return "\n".join(lines)


func _source_label(src: String) -> String:
	if src.begins_with("contact:"):
		return LanguageSystem.localizef("ui.source.contact", [_entity_name(src.substr(8))])
	if src.begins_with("explode:"):
		return LanguageSystem.localizef("ui.source.explode", [_entity_name(src.substr(8))])
	match src:
		"enemy_contact": return LanguageSystem.localize("ui.source.enemy_contact")
		"enemy_projectile": return LanguageSystem.localize("ui.source.enemy_projectile")
		"affix_thorns": return LanguageSystem.localize("ui.source.affix_thorns")
		"boss_tide_archon": return LanguageSystem.localize("ui.source.boss_tide_archon")
		"unknown": return LanguageSystem.localize("ui.source.unknown")
		_: return src


func _entity_name(id: String) -> String:
	if id == "":
		return LanguageSystem.localize("ui.source.unknown")
	var enemy: Dictionary = ConfigLoader.get_enemy(id)
	if not enemy.is_empty():
		return LanguageSystem.localize_config_name("enemy", id, String(enemy.get("name", id)))
	var boss: Dictionary = ConfigLoader.get_boss(id)
	if not boss.is_empty():
		return LanguageSystem.localize_config_name("boss", id, String(boss.get("name", id)))
	return id
