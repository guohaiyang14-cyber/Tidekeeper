# ============================================================================
# LighthouseTree — 灯塔升级树界面（Control，W16 + A6 i18n/排版）
# ============================================================================
extends Control

const _UI := preload("res://scripts/ui/ui_chrome.gd")
const VIEW_W: float = 1280.0
const MAIN_SCENE := "res://scenes/main.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"

var _title_label: Label
var _stardust_label: Label
var _back_btn: Button
var _start_btn: Button
var _branch_labels: Array[Label] = []
var _node_buttons: Dictionary = {}  # node_id -> Button
var _node_data_cache: Dictionary = {}  # node_id -> Dictionary


func _ready() -> void:
	_build()
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	print("[LighthouseTree] 就绪")


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.11, 0.96)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top = 24.0
	_title_label.offset_bottom = 70.0
	_title_label.add_theme_font_size_override("font_size", 38)
	add_child(_title_label)

	_stardust_label = Label.new()
	_stardust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stardust_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stardust_label.offset_top = 76.0
	_stardust_label.offset_bottom = 106.0
	_stardust_label.add_theme_font_size_override("font_size", 22)
	_stardust_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(_stardust_label)

	var branches: Dictionary = ConfigLoader.get_lighthouse_branches()
	var y := 130.0
	for branch_id in branches.keys():
		var branch: Dictionary = branches[branch_id]
		var bl := Label.new()
		bl.set_meta("branch_id", String(branch_id))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		bl.offset_top = y
		bl.offset_bottom = y + 30.0
		bl.add_theme_font_size_override("font_size", 20)
		bl.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
		add_child(bl)
		_branch_labels.append(bl)
		y += 36.0

		var nodes: Array = (branch.get("nodes", {}) as Dictionary).values()
		nodes.sort_custom(func(a, b): return int(a.get("tier", 0)) < int(b.get("tier", 0)))
		var n: int = nodes.size()
		var bw := 210.0
		var gap := 18.0
		var total_w := bw * float(n) + gap * float(maxi(n - 1, 0))
		var start_x := (VIEW_W - total_w) / 2.0
		for i in n:
			var node: Dictionary = nodes[i]
			var nid: String = String(node.get("id", ""))
			_node_data_cache[nid] = node
			var btn := Button.new()
			_UI.style_button(btn)
			btn.size = Vector2(bw, 100.0)
			btn.custom_minimum_size = Vector2(bw, 100.0)
			btn.position = Vector2(start_x + float(i) * (bw + gap), y)
			btn.add_theme_font_size_override("font_size", 14)
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.pressed.connect(_on_node_pressed.bind(nid))
			add_child(btn)
			_node_buttons[nid] = btn
		y += 118.0

	_back_btn = Button.new()
	_UI.style_button(_back_btn)
	_back_btn.size = Vector2(240.0, 52.0)
	_back_btn.position = Vector2(VIEW_W / 2.0 - 360.0, y + 20.0)
	_back_btn.add_theme_font_size_override("font_size", 22)
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	_start_btn = Button.new()
	_UI.style_button(_start_btn)
	_start_btn.size = Vector2(240.0, 52.0)
	_start_btn.position = Vector2(VIEW_W / 2.0 + 120.0, y + 20.0)
	_start_btn.add_theme_font_size_override("font_size", 22)
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_refresh_localized_static()
	_refresh()
	if _start_btn != null:
		_start_btn.grab_focus()


func _on_language_changed(_lang: String) -> void:
	_refresh_localized_static()
	_refresh()


func _refresh_localized_static() -> void:
	if _title_label != null:
		_title_label.text = LanguageSystem.localize("ui.lh.title")
	if _back_btn != null:
		_back_btn.text = LanguageSystem.localize("ui.lh.back")
	if _start_btn != null:
		_start_btn.text = LanguageSystem.localize("ui.lh.start")
	for bl in _branch_labels:
		var bid: String = String(bl.get_meta("branch_id", ""))
		var branch: Dictionary = ConfigLoader.get_lighthouse_branches().get(bid, {})
		var name_key: String = "ui.lh.branch.%s.name" % bid
		var desc_key: String = "ui.lh.branch.%s.desc" % bid
		var bname: String = LanguageSystem.localize(name_key)
		var bdesc: String = LanguageSystem.localize(desc_key)
		if bname == name_key:
			bname = String(branch.get("name", bid))
		if bdesc == desc_key:
			bdesc = String(branch.get("desc", ""))
		bl.text = "%s — %s" % [bname, bdesc]


func _effect_parts(eff: Dictionary) -> String:
	var parts: Array[String] = []
	for k in eff.keys():
		var v: float = float(eff[k])
		var sign: String = "+" if v >= 0 else ""
		var suffix: String = "%" if not (k == "projectile_bonus" or k == "max_health" or k == "regen_per_night") else ""
		var trait_key: String = "ui.trait.%s" % String(k)
		var label: String = LanguageSystem.localize(trait_key)
		if label == trait_key:
			label = String(k)
		parts.append("%s%s%d%s" % [label, sign, int(v), suffix])
	return "·".join(parts)


func _node_summary(node: Dictionary) -> String:
	var effects: String = _effect_parts(node.get("effects", {}))
	var line1: String = LanguageSystem.localizef("ui.lh.node_effects", [
		int(node.get("tier", 0)), effects,
	])
	var line2: String = LanguageSystem.localizef("ui.lh.node_cost", [int(node.get("cost", 0))])
	return "%s\n%s" % [line1, line2]


func _apply_btn_chrome(btn: Button, state: String) -> void:
	var style := StyleBoxFlat.new()
	match state:
		"lit":
			style.bg_color = Color(0.12, 0.22, 0.16, 0.95)
			style.border_color = Color(0.45, 0.90, 0.60, 0.95)
		"available":
			style.bg_color = Color(0.08, 0.12, 0.22, 0.95)
			style.border_color = Color(0.55, 0.75, 1.0, 0.95)
		_:
			style.bg_color = Color(0.08, 0.08, 0.10, 0.90)
			style.border_color = Color(0.35, 0.35, 0.40, 0.80)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("disabled", style)


func _refresh() -> void:
	_stardust_label.text = LanguageSystem.localizef("ui.lh.stardust", [MetaSystem.get_stardust()])
	for node_id in _node_buttons.keys():
		var btn: Button = _node_buttons[node_id]
		var node: Dictionary = _node_data_cache.get(node_id, ConfigLoader.get_lighthouse_node(node_id))
		if MetaSystem.is_node_purchased(node_id):
			btn.text = LanguageSystem.localize("ui.lh.lit")
			btn.disabled = true
			_apply_btn_chrome(btn, "lit")
		elif MetaSystem.can_purchase_node(node_id):
			btn.text = _node_summary(node)
			btn.disabled = false
			_apply_btn_chrome(btn, "available")
		else:
			var req: Variant = node.get("requires", null)
			if req != null and not MetaSystem.is_node_purchased(String(req)):
				btn.text = LanguageSystem.localize("ui.lh.need_prereq")
			else:
				btn.text = LanguageSystem.localize("ui.lh.not_enough")
			btn.disabled = true
			_apply_btn_chrome(btn, "locked")


func _on_node_pressed(node_id: String) -> void:
	if MetaSystem.purchase_node(node_id):
		_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SCENE)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
