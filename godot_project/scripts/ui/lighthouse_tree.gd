# ============================================================================
# LighthouseTree — 灯塔升级树界面（Control，W16）
# 职责：展示 3 分支 × 5 层灯塔节点；消耗星尘点亮（前置链 + 星尘门控）；返回/开始
# 数据流：仅通过 MetaSystem / ConfigLoader，不直接改战斗状态
# ============================================================================
extends Control

const VIEW_W: float = 1280.0
const MAIN_SCENE := "res://scenes/main.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"

var _stardust_label: Label
var _node_buttons: Dictionary = {}  # node_id -> Button


func _ready() -> void:
	_build()
	print("[LighthouseTree] 就绪")


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.11, 0.96)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var title := Label.new()
	title.text = "灯塔升级树"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 24.0
	title.offset_bottom = 70.0
	title.add_theme_font_size_override("font_size", 38)
	add_child(title)

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
		var bname: String = "%s — %s" % [branch.get("name", branch_id), branch.get("desc", "")]
		var bl := Label.new()
		bl.text = bname
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		bl.offset_top = y
		bl.offset_bottom = y + 30.0
		bl.add_theme_font_size_override("font_size", 20)
		bl.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
		add_child(bl)
		y += 36.0

		# 该分支节点按 tier 排序排成一行
		var nodes: Array = (branch.get("nodes", {}) as Dictionary).values()
		nodes.sort_custom(func(a, b): return int(a.get("tier", 0)) < int(b.get("tier", 0)))
		var n: int = nodes.size()
		var bw := 200.0
		var gap := 24.0
		var total_w := bw * float(n) + gap * float(maxi(n - 1, 0))
		var start_x := (VIEW_W - total_w) / 2.0
		for i in n:
			var node: Dictionary = nodes[i]
			var btn := Button.new()
			btn.size = Vector2(bw, 90.0)
			btn.position = Vector2(start_x + float(i) * (bw + gap), y)
			btn.add_theme_font_size_override("font_size", 16)
			btn.text = _node_summary(node)
			btn.pressed.connect(_on_node_pressed.bind(String(node.get("id", ""))))
			add_child(btn)
			_node_buttons[String(node.get("id", ""))] = btn
		y += 110.0

	var back_btn := Button.new()
	back_btn.text = "返回角色选择"
	back_btn.size = Vector2(240.0, 52.0)
	back_btn.position = Vector2(VIEW_W / 2.0 - 360.0, y + 20.0)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)

	var start_btn := Button.new()
	start_btn.text = "开始游戏"
	start_btn.size = Vector2(240.0, 52.0)
	start_btn.position = Vector2(VIEW_W / 2.0 + 120.0, y + 20.0)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	_refresh()


## 节点摘要（描述 + 效果）
func _node_summary(node: Dictionary) -> String:
	var eff: Dictionary = node.get("effects", {})
	var parts: Array[String] = []
	var label_map: Dictionary = {
		"damage_pct": "伤害", "attack_speed_pct": "攻速", "area_pct": "范围",
		"move_speed_pct": "移速", "exp_pct": "经验", "crit_chance_pct": "暴击",
		"damage_reduction_pct": "减伤", "projectile_bonus": "弹道",
		"max_health": "生命", "regen_per_night": "休息回血",
	}
	for k in eff.keys():
		var v: float = float(eff[k])
		var sign: String = "+" if v >= 0 else ""
		var suffix: String = "%" if not (k == "projectile_bonus" or k == "max_health" or k == "regen_per_night") else ""
		parts.append("%s%s%d%s" % [label_map.get(k, k), sign, int(v), suffix])
	return "Lv%d %s\n%s 星尘" % [int(node.get("tier", 0)), "·".join(parts), int(node.get("cost", 0))]


## 刷新星尘与所有节点按钮状态
func _refresh() -> void:
	_stardust_label.text = "星尘：%d" % MetaSystem.get_stardust()
	for node_id in _node_buttons.keys():
		var btn: Button = _node_buttons[node_id]
		var node: Dictionary = ConfigLoader.get_lighthouse_node(node_id)
		if MetaSystem.is_node_purchased(node_id):
			btn.text = "✔ 已点亮"
			btn.disabled = true
		elif MetaSystem.can_purchase_node(node_id):
			btn.text = _node_summary(node)
			btn.disabled = false
		else:
			var req: Variant = node.get("requires", null)
			if req != null and not MetaSystem.is_node_purchased(String(req)):
				btn.text = "需先点亮前置"
			else:
				btn.text = "星尘不足"
			btn.disabled = true


func _on_node_pressed(node_id: String) -> void:
	if MetaSystem.purchase_node(node_id):
		_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SCENE)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
