# ============================================================================
# DayPhaseUI — 抉择之昼（白昼选择页面）视觉框架（W4 雏形）
# 职责：夜晚结束进入「昼」时显示明确的昼阶段框架（暗色背景 + 标题 + 夜数副标题
#        + 操作提示），让玩家清晰感知「已进入白昼选择页面」。
# 设计：技术选型.md —— DayPhaseUI = 抉择之昼（三选一/商店/事件）。
# 红线：本节点只负责昼阶段的视觉框架与提示；商店内容由 ShopUI（兄弟节点，
#       在场景树中位于本节点之后，渲染在上层）承载，不直接改 GameState/槽位。
# 说明：背景 mouse_filter=IGNORE，避免拦截上层 ShopUI 按钮点击与玩家移动输入。
# ============================================================================
class_name DayPhaseUI
extends Control

var _subtitle: Label
var _event_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	visible = false
	print("[DayPhaseUI] 就绪")


func _build_frame() -> void:
	# 半透明暗色背景，明确「进入昼」的模式切换
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.12, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var title := Label.new()
	title.text = "抉择之昼"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 28.0
	title.offset_bottom = 80.0
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	add_child(title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 86.0
	_subtitle.offset_bottom = 118.0
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	add_child(_subtitle)

	# 事件卡提示（W14：抉择之昼抽到的事件卡，无事件时隐藏）
	_event_label = Label.new()
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_event_label.offset_top = 126.0
	_event_label.offset_bottom = 156.0
	_event_label.add_theme_font_size_override("font_size", 22)
	_event_label.add_theme_color_override("font_color", Color(0.65, 0.95, 0.85))
	_event_label.visible = false
	add_child(_event_label)

	var hint := Label.new()
	hint.text = "右侧商店可购买强化 · 可融合时点「融合」· 按 Q 或点「继续下一夜」进入下一夜"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -42.0
	hint.offset_bottom = -12.0
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.92))
	add_child(hint)


## 进入昼：显示框架并更新夜数副标题（休息夜提示灯塔回血；有事件卡则展示事件名）
func enter_day(night: int, event_name: String = "") -> void:
	if _subtitle != null:
		if RestSystem.is_rest_night(night):
			_subtitle.text = "第 %d 夜结束 · 灯塔休息回血" % night
		else:
			_subtitle.text = "第 %d 夜结束" % night
	if _event_label != null:
		if event_name != "":
			_event_label.text = "事件：%s" % event_name
			_event_label.visible = true
		else:
			_event_label.visible = false
	visible = true


## 离开昼（跳过 / 游戏结束 / 通关）
func exit_day() -> void:
	visible = false
