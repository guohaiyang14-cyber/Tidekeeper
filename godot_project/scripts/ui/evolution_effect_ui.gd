# ============================================================================
# EvolutionEffectUI — 潮汐共鸣全屏反馈（W10）
# 职责：订阅 EvolutionSystem.resonance_requested，播放约 1.5s 金色全屏闪
# 红线：仅表现层；时长来自信号参数（config）；不改 GameState
# ============================================================================
class_name EvolutionEffectUI
extends CanvasLayer

var _overlay: ColorRect
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 80
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(1.0, 0.85, 0.35, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_label = Label.new()
	_label.text = "潮汐共鸣"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 48)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 0.0))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false
	if not EvolutionSystem.resonance_requested.is_connected(_on_resonance):
		EvolutionSystem.resonance_requested.connect(_on_resonance)


func _on_resonance(duration: float) -> void:
	play(duration)


func play(duration: float = 1.5) -> void:
	if duration <= 0.0:
		duration = 1.5
	visible = true
	if _tween != null:
		_tween.kill()
	_overlay.color.a = 0.0
	_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_overlay, "color:a", 0.45, duration * 0.2)
	_tween.parallel().tween_property(_label, "modulate:a", 1.0, duration * 0.2)
	_tween.tween_property(_overlay, "color:a", 0.0, duration * 0.8)
	_tween.parallel().tween_property(_label, "modulate:a", 0.0, duration * 0.8)
	_tween.tween_callback(func() -> void: visible = false)
