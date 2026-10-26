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
var _title: Label

## 2026-10-26 用户反馈「提示信息应该跟所选的语言相同」：本界面原为硬编码中文，
## 现全部走 i18n；config 里的分类/系别是中文取值，用稳定 key 映射（字面量 key 供校验器扫描）
const _CAT_KEYS := {
	"通用被动": "ui.upgrade.cat_generic",
	"进化钥被动": "ui.upgrade.cat_evolution_key",
	# 2026-10-26 code-review 补：溢出奖励（潮币/血包）的 category 也是中文原值
	"溢出奖励": "ui.upgrade.cat_overflow",
}
const _SERIES_KEYS := {
	"夜风": "ui.upgrade.series_nightwind",
	"潮汐": "ui.upgrade.series_tide",
	"灯塔": "ui.upgrade.series_lighthouse",
	"礁石": "ui.upgrade.series_reef",
}
## 武器卡的 meta 取自 weapons.json 的 attack_type（中文原值）——
## 2026-10-26 检查发现：不映射时英文界面会显示「[Weapon] 定向弹幕」这种中文残留
const _ATTACK_KEYS := {
	"定向弹幕": "ui.upgrade.attack_projectile",
	"范围型": "ui.upgrade.attack_area",
	"爆发近战": "ui.upgrade.attack_melee",
	"召唤型": "ui.upgrade.attack_summon",
	"环绕型": "ui.upgrade.attack_orbit",
}


func _ready() -> void:
	_build_ui()
	UpgradeManager.upgrade_offered.connect(_show)
	UpgradeManager.upgrade_resolved.connect(_on_resolved)
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	visible = false
	print("[UpgradeUI] 就绪")


## 语言切换：刷新静态文案；若正在展示三选一则整屏重绘
func _on_language_changed(_lang: String) -> void:
	_refresh_static_texts()
	if visible:
		for i in _offers.size():
			_populate_card(i, _offers[i])


func _refresh_static_texts() -> void:
	if _title != null:
		_title.text = LanguageSystem.localize("ui.upgrade.title")
	if _hint != null:
		_hint.text = LanguageSystem.localize("ui.upgrade.hint")
		_hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	if _skip_button != null:
		_skip_button.text = LanguageSystem.localize("ui.upgrade.skip")
	if _reroll_button != null:
		_reroll_button.text = LanguageSystem.localize("ui.upgrade.reroll_free")


## config 中文取值 → i18n；无映射时原样返回（未知取值不至于显示成 key）
func _localize_mapped(map: Dictionary, raw: String) -> String:
	if raw == "":
		return raw
	var key: String = String(map.get(raw, ""))
	if key == "":
		return raw
	var text: String = LanguageSystem.localize(key)
	return text if text != key else raw


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
	if can_free_reroll:
		_reroll_button.text = LanguageSystem.localize("ui.upgrade.reroll_free")
	else:
		_reroll_button.text = LanguageSystem.localizef("ui.upgrade.reroll_cost", [cost])
	_hint.text = LanguageSystem.localize("ui.upgrade.hint")
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
	_hint.text = LanguageSystem.localizef("ui.upgrade.no_coins", [UpgradeManager.get_reroll_cost()])
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
	_title = title
	title.text = LanguageSystem.localize("ui.upgrade.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40.0
	title.offset_bottom = 84.0
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	_hint = Label.new()
	_hint.text = LanguageSystem.localize("ui.upgrade.hint")
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
	_reroll_button.text = LanguageSystem.localize("ui.upgrade.reroll_free")
	_reroll_button.size = Vector2(200.0, 48.0)
	_reroll_button.position = Vector2(VIEW_W / 2.0 - 220.0, btn_y)
	_reroll_button.pressed.connect(_do_reroll)
	add_child(_reroll_button)

	_skip_button = Button.new()
	_skip_button.text = LanguageSystem.localize("ui.upgrade.skip")
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
	var otype: String = str(offer.get("type", ""))
	var kind: String = LanguageSystem.localize("ui.upgrade.kind_weapon")
	match otype:
		"passive":
			kind = LanguageSystem.localize("ui.upgrade.kind_passive")
		"tidecoins":
			kind = LanguageSystem.localize("ui.upgrade.kind_tidecoins")
		"heal":
			kind = LanguageSystem.localize("ui.upgrade.kind_heal")
	var raw_meta: String = ""
	if otype == "passive":
		# 被动：series（夜风/潮汐/灯塔/礁石）；无 series 时退回分类（通用被动/进化钥被动）
		var s_raw: String = str(offer.get("series", ""))
		if s_raw != "":
			raw_meta = _localize_mapped(_SERIES_KEYS, s_raw)
		else:
			raw_meta = _localize_mapped(_CAT_KEYS, str(offer.get("category", "")))
	elif otype == "weapon":
		# 2026-10-26 补：UpgradeManager 给武器填的 category 实际是 weapons.json attack_type
		# （定向弹幕/范围型/爆发近战/召唤型/环绕型，中文原值）——不映射就会在英文界面残留中文
		raw_meta = _localize_mapped(_ATTACK_KEYS, str(offer.get("category", "")))
	else:
		raw_meta = _localize_mapped(_CAT_KEYS, str(offer.get("category", "")))
	# 名称按 id 走 config 名 i18n（config 里是中文名）
	var oid: String = str(offer.get("id", ""))
	var raw_name: String = str(offer.get("name", "?"))
	var display_name: String = raw_name
	if oid != "":
		if otype == "weapon":
			display_name = LanguageSystem.localize_config_name("weapon", oid, raw_name)
			_card_desc[i].text = LanguageSystem.localize_config_desc(
				"weapon", oid, str(offer.get("description", "")))
		elif otype == "passive":
			display_name = LanguageSystem.localize_config_name("passive", oid, raw_name)
			_card_desc[i].text = LanguageSystem.localize_config_desc(
				"passive", oid, str(offer.get("description", "")))
		else:
			# 溢出奖励（潮币 / 血包）：id/name/description 全来自 config/upgrade.json 中文原值，
			# 不映射的话英文界面会整卡中文（2026-10-26 code-review 实测发现）
			display_name = LanguageSystem.localize_config_name("upgrade_offer", oid, raw_name)
			_card_desc[i].text = LanguageSystem.localize_config_desc(
				"upgrade_offer", oid, str(offer.get("description", "")))
	else:
		_card_desc[i].text = str(offer.get("description", ""))
	_card_name[i].text = "%d. %s" % [i + 1, display_name]
	# 潮币/治疗类 offer 没有 category/series → raw_meta 为空，别渲染成 "[Coins] " 带尾随空格
	if raw_meta != "":
		_card_meta[i].text = "[%s] %s" % [kind, raw_meta]
	else:
		_card_meta[i].text = "[%s]" % kind
