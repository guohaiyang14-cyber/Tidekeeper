# ============================================================================
# UpgradeUI — 升级三选一界面（Control，挂在 UI 下）
# 职责：展示 3 张卡片（名称/类型/描述）、重铸与跳过按钮、快捷键、软提示
# 交互：choose_1/2/3 选择；reroll(R) 重铸；skip(Q) 跳过
# 注意：本节点 process_mode=ALWAYS，三选一暂停期间仍可响应输入
# 数据流：仅通过 UpgradeManager 信号 / 方法，不直接改 GameState
# ============================================================================
extends Control

const VIEW_W: float = 1280.0

var _offers: Array = []
var _card_name: Array[Label] = []
var _card_meta: Array[Label] = []
var _card_desc: Array[Label] = []
var _card_buttons: Array[Button] = []
var _reroll_button: Button
var _skip_button: Button
var _hint: Label


func _ready() -> void:
	_build_ui()
	UpgradeManager.upgrade_offered.connect(_show)
	UpgradeManager.upgrade_resolved.connect(_on_resolved)
	visible = false
	print("[UpgradeUI] 就绪")


# ============================================================================
# 输入（暂停期间由 process_mode=ALWAYS 保证分发）
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("choose_1"):
		_choose(0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("choose_2"):
		_choose(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("choose_3"):
		_choose(2)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reroll"):
		_do_reroll()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skip"):
		_do_skip()
		get_viewport().set_input_as_handled()


# ============================================================================
# 信号回调
# ============================================================================

func _show(offers: Array, can_free_reroll: bool) -> void:
	_offers = offers
	for i in _card_buttons.size():
		if i < offers.size():
			_populate_card(i, offers[i])
			_card_buttons[i].visible = true
		else:
			_card_buttons[i].visible = false
	var cost: int = UpgradeManager.get_reroll_cost()
	_reroll_button.text = "重铸 (免费)" if can_free_reroll else "重铸 (%d 潮币)" % cost
	_hint.text = "建议用时 20 秒 · 可随时跳过 (Q) · 快捷键 1/2/3 选择，R 重铸"
	_hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	visible = true
	print("[UpgradeUI] 展示三选一 (共 %d 项)" % offers.size())


func _on_resolved(_offer: Dictionary, _is_skip: bool) -> void:
	visible = false


# ============================================================================
# 操作
# ============================================================================

func _choose(index: int) -> void:
	if not visible or index >= _offers.size():
		return
	UpgradeManager.apply_offer(index)


func _do_reroll() -> void:
	if not visible:
		return
	if UpgradeManager.reroll():
		return
	_hint.text = "潮币不足，无法重铸（需要 %d）" % UpgradeManager.get_reroll_cost()
	_hint.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))


func _do_skip() -> void:
	if not visible:
		return
	UpgradeManager.skip()


# ============================================================================
# UI 构建（代码生成，无美术占位）
# ============================================================================

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 背景遮罩（拦截点击，避免点到背后）
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.09, 0.62)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var title := Label.new()
	title.text = "升级！选择一项强化"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40.0
	title.offset_bottom = 84.0
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	_hint = Label.new()
	_hint.text = "建议用时 20 秒 · 可随时跳过 (Q) · 快捷键 1/2/3 选择，R 重铸"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 90.0
	_hint.offset_bottom = 116.0
	_hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	add_child(_hint)

	var card_count: int = UpgradeManager.get_max_offers()
	var card_w := 360.0
	var card_h := 300.0
	var gap := 30.0
	var total_w := card_w * float(card_count) + gap * float(maxi(card_count - 1, 0))
	var start_x := (VIEW_W - total_w) / 2.0
	var card_y := 160.0
	for i in card_count:
		var card := _make_card(i)
		card.position = Vector2(start_x + float(i) * (card_w + gap), card_y)
		card.size = Vector2(card_w, card_h)
		add_child(card)

	var btn_y := card_y + card_h + 30.0
	_reroll_button = Button.new()
	_reroll_button.text = "重铸 (免费)"
	_reroll_button.size = Vector2(200.0, 48.0)
	_reroll_button.position = Vector2(VIEW_W / 2.0 - 220.0, btn_y)
	_reroll_button.pressed.connect(_do_reroll)
	add_child(_reroll_button)

	_skip_button = Button.new()
	_skip_button.text = "跳过 (Q)"
	_skip_button.size = Vector2(200.0, 48.0)
	_skip_button.position = Vector2(VIEW_W / 2.0 + 20.0, btn_y)
	_skip_button.pressed.connect(_do_skip)
	add_child(_skip_button)


func _make_card(index: int) -> Panel:
	var panel := Panel.new()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16.0
	vbox.offset_right = -16.0
	vbox.offset_top = 16.0
	vbox.offset_bottom = -16.0

	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	var meta_l := Label.new()
	meta_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	var desc_l := Label.new()
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	vbox.add_child(name_l)
	vbox.add_child(meta_l)
	vbox.add_child(desc_l)
	panel.add_child(vbox)

	# 全卡透明按钮（捕获点击）
	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_choose.bind(index))
	panel.add_child(btn)

	_card_name.append(name_l)
	_card_meta.append(meta_l)
	_card_desc.append(desc_l)
	_card_buttons.append(btn)
	return panel


func _populate_card(i: int, offer: Dictionary) -> void:
	var kind: String = "武器" if offer.get("type") == "weapon" else "被动"
	var meta: String = offer.get("series", "") if offer.get("type") == "passive" else offer.get("category", "")
	_card_name[i].text = "%d. %s" % [i + 1, offer.get("name", "?")]
	_card_meta[i].text = "[%s] %s" % [kind, meta]
	_card_desc[i].text = offer.get("description", "")
