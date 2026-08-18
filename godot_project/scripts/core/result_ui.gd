# ============================================================================
# ResultUI — 结算/死因界面（W10 雏形）
# 职责：游戏结束/通关时显示结算页（标题 + 死因 + 存活统计 + 重启按钮），
#       让玩家清楚死亡原因并能快速重开。
# 设计：技术选型.md —— ResultUI = 结算/死因；
#       游戏设计文档 §挫败感控制：死亡原因可视化（结算页说明死因与建议）。
# 红线：本节点只做结算页展示与重启交互，不直接改 GameState 数值；
#       重启走 get_tree().reload_current_scene() —— 重新走 world._ready →
#       start_new_run + UpgradeManager.reset（自动 paused=false） + day_night.start_run 全套初始化。
# 架构：CanvasLayer 子 Control；process_mode=ALWAYS 保证暂停期可交互；
#       背景 mouse_filter=IGNORE 不拦截按钮点击。
# ============================================================================
extends Control

class_name ResultUI

const VIEW_W: float = 1280.0

var _title: Label
var _reason: Label
var _stats: Label
var _stardust: Label
var _restart_btn: Button
var _meta_btn: Button
var _hint: Label
## W17 死因可视化：最后一击 + 伤害来源 Top3
var _death_cause: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	visible = false
	print("[ResultUI] 就绪")


func _build_frame() -> void:
	# 半透明更深色背景，明确"结算"模式
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 120.0
	_title.offset_bottom = 200.0
	_title.add_theme_font_size_override("font_size", 56)
	add_child(_title)

	_reason = Label.new()
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_reason.offset_top = 210.0
	_reason.offset_bottom = 260.0
	_reason.add_theme_font_size_override("font_size", 24)
	_reason.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	add_child(_reason)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stats.offset_top = 290.0
	_stats.offset_bottom = 360.0
	_stats.add_theme_font_size_override("font_size", 22)
	_stats.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	add_child(_stats)

	_stardust = Label.new()
	_stardust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stardust.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stardust.offset_top = 368.0
	_stardust.offset_bottom = 400.0
	_stardust.add_theme_font_size_override("font_size", 22)
	_stardust.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(_stardust)

	# W17 死因可视化：最后一击 + 伤害来源 Top3（位于星尘与按钮之间）
	_death_cause = Label.new()
	_death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_cause.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_death_cause.offset_top = 408.0
	_death_cause.offset_bottom = 454.0
	_death_cause.add_theme_font_size_override("font_size", 16)
	_death_cause.add_theme_color_override("font_color", Color(0.92, 0.78, 0.82))
	add_child(_death_cause)

	_restart_btn = Button.new()
	_restart_btn.text = "再来一局 (Enter)"
	_restart_btn.size = Vector2(280.0, 56.0)
	_restart_btn.position = Vector2(VIEW_W / 2.0 - 140.0, 502.0)
	_restart_btn.add_theme_font_size_override("font_size", 22)
	_restart_btn.pressed.connect(_on_restart_pressed)
	add_child(_restart_btn)

	_meta_btn = Button.new()
	_meta_btn.text = "角色 / 灯塔"
	_meta_btn.size = Vector2(280.0, 48.0)
	_meta_btn.position = Vector2(VIEW_W / 2.0 - 140.0, 564.0)
	_meta_btn.add_theme_font_size_override("font_size", 20)
	_meta_btn.pressed.connect(_on_meta_pressed)
	add_child(_meta_btn)

	_hint = Label.new()
	_hint.text = "按 Enter 或点击按钮重开 · 可进入角色选择 / 灯塔升级（W15-W16）"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -50.0
	_hint.offset_bottom = -20.0
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("restart"):
		_on_restart_pressed()
		get_viewport().set_input_as_handled()


## 显示游戏结束（§挫败感控制：死亡原因可视化）
func show_game_over(reason: String, night: int, level: int, tidecoins: int, stardust_earned: int = 0) -> void:
	_title.text = "游戏结束"
	_title.remove_theme_color_override("font_color")
	_title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_reason.text = _reason_label(reason)
	_stats.text = "存活至第 %d 夜 · 等级 %d · 潮币 %d" % [night, level, tidecoins]
	_stardust.text = "本局星尘 +%d（累计 %d）" % [stardust_earned, MetaSystem.get_stardust()]
	_death_cause.text = _death_cause_text()
	_show()


## 显示通关
func show_victory(night: int, level: int, tidecoins: int, stardust_earned: int = 0) -> void:
	_title.text = "通关"
	_title.remove_theme_color_override("font_color")
	_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	_reason.text = "击败吞噬之星，第 20 夜结束"
	_stats.text = "通关 · 第 %d 夜 · 等级 %d · 潮币 %d" % [night, level, tidecoins]
	_stardust.text = "本局星尘 +%d（累计 %d）" % [stardust_earned, MetaSystem.get_stardust()]
	_death_cause.text = ""
	_show()


func _show() -> void:
	visible = true
	if _restart_btn != null:
		_restart_btn.grab_focus()


func _on_restart_pressed() -> void:
	# 重置暂停状态，避免 reload 后新场景继承暂停（UpgradeManager.reset 也会兜底）
	if get_tree() != null:
		get_tree().paused = false
	get_tree().reload_current_scene()


## 进入角色选择 / 灯塔升级界面（W15-W16）
func _on_meta_pressed() -> void:
	if get_tree() != null:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")


## 死因文案映射
func _reason_label(reason: String) -> String:
	match reason:
		"hp_zero": return "死因：血量归零"
		"timeout": return "死因：超时"
		"death": return "死因：生命值耗尽"
		_: return "死因：%s" % reason


## W17 死因可视化文案：最后一击来源 + 伤害来源 Top3（来自 GameState.get_death_analysis）
func _death_cause_text() -> String:
	var a: Dictionary = GameState.get_death_analysis()
	var lines: Array[String] = []
	var last: String = String(a.get("last_hit_source", ""))
	var last_amt: int = int(a.get("last_hit_amount", 0))
	lines.append("最后一击：%s（%d）" % [_source_label(last if last != "" else "unknown"), last_amt])
	var top: Array = a.get("top_sources", [])
	if top.is_empty():
		lines.append("伤害来源：无记录")
	else:
		var parts: Array[String] = []
		for i in top.size():
			var s: Dictionary = top[i]
			parts.append("%d. %s %d" % [i + 1, _source_label(String(s.get("source", "?"))), int(s.get("damage", 0))])
		lines.append("伤害来源 Top%d：%s" % [top.size(), "  ".join(parts)])
	return "\n".join(lines)


## 伤害来源友好名（已知战斗来源映射；敌人 id 直出）
func _source_label(src: String) -> String:
	match src:
		"enemy_contact": return "敌人接触"
		"enemy_projectile": return "敌方弹幕"
		"affix_thorns": return "荆棘反伤"
		"boss_tide_archon": return "天灾潮汐"
		"unknown": return "未知"
		_: return src
