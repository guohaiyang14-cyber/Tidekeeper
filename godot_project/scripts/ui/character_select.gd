# ============================================================================
# CharacterSelect — 角色选择界面（Control，W15）
# 职责：列出 3 名角色，展示特性与解锁条件；已解锁可进入游戏，未解锁置灰并提示
# 数据流：仅通过 MetaSystem / ConfigLoader，不直接改战斗状态
# 入口：结算页「角色 / 灯塔」按钮，或游戏内 change_scene_to_file
# ============================================================================
extends Control

const VIEW_W: float = 1280.0
const MAIN_SCENE := "res://scenes/main.tscn"
const LIGHTHOUSE_SCENE := "res://scenes/lighthouse_tree.tscn"

var _stardust_label: Label
var _difficulty_label: Label
var _title_label: Label
var _lighthouse_btn: Button
var _start_btn: Button
var _tier_buttons: Dictionary = {}  # tier_id -> Button
var _tier_group: ButtonGroup
var _char_cards: Array[Dictionary] = []  # {id, btn, name_l, desc_l, trait_l}


func _ready() -> void:
	_build()
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	print("[CharacterSelect] 就绪")


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.11, 0.96)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var title := Label.new()
	_title_label = title
	title.text = LanguageSystem.localize("ui.char_select.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30.0
	title.offset_bottom = 80.0
	title.add_theme_font_size_override("font_size", 40)
	add_child(title)

	_stardust_label = Label.new()
	_stardust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stardust_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stardust_label.offset_top = 86.0
	_stardust_label.offset_bottom = 116.0
	_stardust_label.add_theme_font_size_override("font_size", 20)
	_stardust_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(_stardust_label)

	_build_difficulty_row()

	var ids: Array[String] = ConfigLoader.get_all_character_ids()
	var card_w := 360.0
	var card_h := 300.0
	var gap := 30.0
	var total_w := card_w * float(ids.size()) + gap * float(maxi(ids.size() - 1, 0))
	var start_x := (VIEW_W - total_w) / 2.0
	var card_y := 190.0
	for i in ids.size():
		var panel := _make_card(String(ids[i]))
		panel.position = Vector2(start_x + float(i) * (card_w + gap), card_y)
		panel.size = Vector2(card_w, card_h)
		add_child(panel)

	var btn_y := card_y + card_h + 40.0
	var lighthouse_btn := Button.new()
	_lighthouse_btn = lighthouse_btn
	lighthouse_btn.text = LanguageSystem.localize("ui.char_select.lighthouse")
	lighthouse_btn.size = Vector2(240.0, 52.0)
	lighthouse_btn.position = Vector2(VIEW_W / 2.0 - 360.0, btn_y)
	lighthouse_btn.add_theme_font_size_override("font_size", 22)
	lighthouse_btn.pressed.connect(_on_lighthouse_pressed)
	add_child(lighthouse_btn)

	var start_btn := Button.new()
	_start_btn = start_btn
	start_btn.text = LanguageSystem.localize("ui.char_select.start")
	start_btn.size = Vector2(240.0, 52.0)
	start_btn.position = Vector2(VIEW_W / 2.0 + 120.0, btn_y)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(_on_start_default_pressed)
	add_child(start_btn)

	_refresh_stardust()
	_refresh_tier_buttons()


func _build_difficulty_row() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 118.0
	row.offset_bottom = 158.0
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_tier_group = ButtonGroup.new()

	_difficulty_label = Label.new()
	_difficulty_label.text = LanguageSystem.localize("ui.difficulty_select")
	_difficulty_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_difficulty_label)

	var tiers: Dictionary = ConfigLoader.get_difficulty_config().get("tiers", {})
	for tier_id in tiers.keys():
		var btn := Button.new()
		btn.text = LanguageSystem.localize("difficulty.tier.%s" % tier_id)
		btn.custom_minimum_size = Vector2(160.0, 36.0)
		btn.toggle_mode = true
		btn.button_group = _tier_group
		btn.button_pressed = tier_id == DifficultySystem.get_tier()
		btn.pressed.connect(_on_tier_pressed.bind(String(tier_id)))
		row.add_child(btn)
		_tier_buttons[String(tier_id)] = btn


func _refresh_tier_buttons() -> void:
	var active: String = DifficultySystem.get_tier()
	for tier_id in _tier_buttons.keys():
		var btn: Button = _tier_buttons[tier_id] as Button
		btn.button_pressed = tier_id == active
		btn.text = LanguageSystem.localize("difficulty.tier.%s" % tier_id)


func _on_tier_pressed(tier_id: String) -> void:
	DifficultySystem.set_tier(tier_id, true)
	_refresh_tier_buttons()


func _on_language_changed(_lang: String) -> void:
	if _title_label != null:
		_title_label.text = LanguageSystem.localize("ui.char_select.title")
	if _lighthouse_btn != null:
		_lighthouse_btn.text = LanguageSystem.localize("ui.char_select.lighthouse")
	if _start_btn != null:
		_start_btn.text = LanguageSystem.localize("ui.char_select.start")
	if _difficulty_label != null:
		_difficulty_label.text = LanguageSystem.localize("ui.difficulty_select")
	_refresh_stardust()
	_refresh_tier_buttons()
	_refresh_card_content()


func _make_card(id: String) -> Panel:
	var data: Dictionary = ConfigLoader.get_character(id)
	var panel := Panel.new()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16.0
	vbox.offset_right = -16.0
	vbox.offset_top = 16.0
	vbox.offset_bottom = -16.0

	var name_l := Label.new()
	name_l.text = _character_name(id, data)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 26)
	var desc_l := Label.new()
	desc_l.text = _character_desc(id, data)
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.add_theme_font_size_override("font_size", 15)
	var trait_l := Label.new()
	trait_l.text = _traits_text(data.get("traits", {}))
	trait_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trait_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_l.add_theme_font_size_override("font_size", 15)
	trait_l.add_theme_color_override("font_color", Color(0.7, 0.95, 0.8))

	vbox.add_child(name_l)
	vbox.add_child(desc_l)
	vbox.add_child(trait_l)
	panel.add_child(vbox)

	var unlocked: bool = MetaSystem.is_character_unlocked(id)
	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	btn.offset_left = 16.0
	btn.offset_right = -16.0
	btn.offset_top = -56.0
	btn.offset_bottom = -12.0
	if unlocked:
		btn.text = LanguageSystem.localize("ui.char_select.pick")
		btn.pressed.connect(_on_start_pressed.bind(id))
	else:
		btn.text = MetaSystem.get_character_unlock_hint(id)
		btn.disabled = true
	_char_cards.append({"id": id, "btn": btn, "name_l": name_l, "desc_l": desc_l, "trait_l": trait_l})
	panel.add_child(btn)
	return panel


func _character_name(id: String, data: Dictionary) -> String:
	return LanguageSystem.localize_config_name("character", id, String(data.get("name", id)))


func _character_desc(id: String, data: Dictionary) -> String:
	return LanguageSystem.localize_config_desc("character", id, String(data.get("description", "")))


func _refresh_card_content() -> void:
	for entry in _char_cards:
		var id: String = String(entry.get("id", ""))
		var btn: Button = entry.get("btn") as Button
		var name_l: Label = entry.get("name_l") as Label
		var desc_l: Label = entry.get("desc_l") as Label
		var trait_l: Label = entry.get("trait_l") as Label
		var data: Dictionary = ConfigLoader.get_character(id)
		if name_l != null:
			name_l.text = _character_name(id, data)
		if desc_l != null:
			desc_l.text = _character_desc(id, data)
		if trait_l != null:
			trait_l.text = _traits_text(data.get("traits", {}))
		if btn == null:
			continue
		if MetaSystem.is_character_unlocked(id):
			btn.text = LanguageSystem.localize("ui.char_select.pick")
		else:
			btn.text = MetaSystem.get_character_unlock_hint(id)


## 特性字典 → 简短描述（i18n 键 ui.trait.*）
func _traits_text(traits: Dictionary) -> String:
	if traits.is_empty():
		return LanguageSystem.localize("ui.char_select.no_traits")
	var parts: Array[String] = []
	for k in traits.keys():
		var v: float = float(traits[k])
		var sign: String = "+" if v >= 0 else ""
		var suffix: String = "%" if not (k == "projectile_bonus" or k == "max_health" or k == "regen_per_night") else ""
		var trait_key: String = "ui.trait.%s" % String(k)
		var label: String = LanguageSystem.localize(trait_key)
		if label == trait_key:
			label = String(k)
		parts.append("%s %s%d%s" % [label, sign, int(v), suffix])
	return " · ".join(parts)


func _refresh_stardust() -> void:
	_stardust_label.text = LanguageSystem.localizef("ui.char_select.stardust", [MetaSystem.get_stardust()])


func _on_start_default_pressed() -> void:
	_on_start_pressed(MetaSystem.get_active_character())


func _on_start_pressed(id: String) -> void:
	MetaSystem.set_active_character(id)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_lighthouse_pressed() -> void:
	get_tree().change_scene_to_file(LIGHTHOUSE_SCENE)
