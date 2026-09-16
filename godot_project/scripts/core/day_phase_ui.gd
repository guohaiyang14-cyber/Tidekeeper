# ============================================================================
# DayPhaseUI — 抉择之昼视觉框架（W4 + A6 事件卡）
# 职责：夜晚结束进入「昼」时显示暗色背景 + 标题 + 夜数副标题 + 事件卡 + 操作提示。
# 红线：只负责昼阶段视觉；商店由 ShopUI 承载；不直接改 GameState。
# ============================================================================
class_name DayPhaseUI
extends Control

const _UI := preload("res://scripts/ui/ui_chrome.gd")

var _title: Label
var _subtitle: Label
var _event_panel: Panel
var _event_title: Label
var _event_label: Label
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	visible = false
	print("[DayPhaseUI] 就绪")


func _build_frame() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.12, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 28.0
	_title.offset_bottom = 80.0
	_title.add_theme_font_size_override("font_size", _UI.FONT_TITLE)
	_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 86.0
	_subtitle.offset_bottom = 118.0
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	add_child(_subtitle)

	_event_panel = _UI.make_panel(_UI.accent_panel_style())
	_event_panel.name = "EventCard"
	_event_panel.position = Vector2(_UI.VIEW_W * 0.5 - 280.0, 128.0)
	_event_panel.size = Vector2(560.0, 72.0)
	_event_panel.visible = false
	_event_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_event_panel)

	var ev_box := VBoxContainer.new()
	ev_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ev_box.offset_left = 16.0
	ev_box.offset_right = -16.0
	ev_box.offset_top = 8.0
	ev_box.offset_bottom = -8.0
	ev_box.add_theme_constant_override("separation", 2)
	_event_panel.add_child(ev_box)

	_event_title = Label.new()
	_event_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_title.add_theme_font_size_override("font_size", 14)
	_event_title.add_theme_color_override("font_color", Color(0.70, 0.90, 0.82))
	ev_box.add_child(_event_title)

	_event_label = Label.new()
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 22)
	_event_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.92))
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev_box.add_child(_event_label)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -42.0
	_hint.offset_bottom = -12.0
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.92))
	add_child(_hint)
	_refresh_localized_static()


func _refresh_localized_static() -> void:
	if _title != null:
		_title.text = LanguageSystem.localize("ui.day.title")
	if _hint != null:
		_hint.text = LanguageSystem.localize("ui.day.hint")
	if _event_title != null:
		_event_title.text = LanguageSystem.localize("ui.day.event_title")


func _on_language_changed(_lang: String) -> void:
	_refresh_localized_static()


## 进入昼：显示框架并更新夜数副标题（休息夜提示灯塔回血；有事件卡则展示事件名）
func enter_day(night: int, event_name: String = "") -> void:
	if _subtitle != null:
		if RestSystem.is_rest_night(night):
			_subtitle.text = LanguageSystem.localizef("ui.day.subtitle_rest", [night])
		else:
			_subtitle.text = LanguageSystem.localizef("ui.day.subtitle", [night])
	if _event_panel != null and _event_label != null:
		if event_name != "":
			_event_label.text = event_name
			_event_panel.visible = true
		else:
			_event_panel.visible = false
	visible = true


func exit_day() -> void:
	visible = false
