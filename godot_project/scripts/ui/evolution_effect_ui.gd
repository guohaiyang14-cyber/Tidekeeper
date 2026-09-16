# ============================================================================
# EvolutionEffectUI — 潮汐共鸣全屏反馈（W10 + A7）
# 职责：订阅 EvolutionSystem.resonance_requested，播放约 1.5s 金色全屏闪 + 进化名
# 红线：仅表现层；时长来自信号参数（config）；不改 GameState
# ============================================================================
class_name EvolutionEffectUI
extends CanvasLayer

const _UI := preload("res://scripts/ui/ui_chrome.gd")

var _overlay: ColorRect
var _panel: Panel
var _title: Label
var _subtitle: Label
var _tween: Tween
var _weapon_id: String = ""
var _last_duration: float = 0.0
var _playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80

	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(1.0, 0.85, 0.35, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_panel = _UI.make_panel(_UI.accent_panel_style(
		Color(0.10, 0.08, 0.04, 0.92),
		Color(0.95, 0.82, 0.40, 0.90)
	))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(520.0, 140.0)
	_panel.size = Vector2(520.0, 140.0)
	_panel.position = Vector2(_UI.VIEW_W * 0.5 - 260.0, _UI.VIEW_H * 0.5 - 70.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_right = -16.0
	box.offset_top = 20.0
	box.offset_bottom = -20.0
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", _UI.FONT_BODY)
	_subtitle.add_theme_color_override("font_color", Color(0.92, 0.88, 0.70))
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_subtitle)

	_refresh_labels()
	visible = false
	if not EvolutionSystem.resonance_requested.is_connected(_on_resonance):
		EvolutionSystem.resonance_requested.connect(_on_resonance)
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)


func _exit_tree() -> void:
	if EvolutionSystem.resonance_requested.is_connected(_on_resonance):
		EvolutionSystem.resonance_requested.disconnect(_on_resonance)
	if LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.disconnect(_on_language_changed)


func _on_resonance(duration: float, weapon_id: String = "") -> void:
	play(duration, weapon_id)


func _on_language_changed(_lang: String) -> void:
	if _playing:
		_refresh_labels()


func _refresh_labels() -> void:
	if _title != null:
		_title.text = LanguageSystem.localize("ui.evo.resonance")
	if _subtitle != null:
		_subtitle.text = _evolved_display_name(_weapon_id)


func _evolved_display_name(weapon_id: String) -> String:
	if weapon_id == "":
		return ""
	var evo_key: String = "weapon.%s.evolved_name" % weapon_id
	var text: String = LanguageSystem.localize(evo_key)
	if text != evo_key:
		return text
	var path: Dictionary = EvolutionSystem.evolution_path(weapon_id)
	return String(path.get("evolved_name", weapon_id))


func is_playing() -> bool:
	return _playing


func get_last_duration() -> float:
	return _last_duration


func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_subtitle_text() -> String:
	return _subtitle.text if _subtitle != null else ""


func play(duration: float = 1.5, weapon_id: String = "") -> void:
	if duration <= 0.0:
		duration = 1.5
	_weapon_id = weapon_id
	_last_duration = duration
	_refresh_labels()
	_playing = true
	visible = true
	if _tween != null:
		_tween.kill()
	_overlay.color.a = 0.0
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_overlay, "color:a", 0.45, duration * 0.2)
	_tween.parallel().tween_property(_panel, "modulate:a", 1.0, duration * 0.2)
	_tween.tween_property(_overlay, "color:a", 0.0, duration * 0.8)
	_tween.parallel().tween_property(_panel, "modulate:a", 0.0, duration * 0.8)
	_tween.tween_callback(_on_play_finished)


func _on_play_finished() -> void:
	_playing = false
	visible = false
