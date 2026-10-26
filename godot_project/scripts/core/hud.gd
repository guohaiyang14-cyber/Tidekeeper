# ============================================================================
# HUD — 战斗抬头显示（W18 UI 完善 + 截图反馈返工）
# 职责：实时展示 血条 / 经验条 / 等级 / 夜数（仅第N夜） / 难度档位 /
#       Boss 提示 / 武器槽 / 被动槽 / 潮币（信息区上边缘）。
# 设计：与 result_ui.gd 一致的程序化构建（不手绘 .tscn 节点）；
#       每帧 refresh() 拉取 GameState / WeaponManager / DifficultySystem 状态；
#       武器槽 / 被动槽仅在 loadout_changed 时重建，避免每帧 churn。
# 红线：本节点只读展示，不直接改 GameState 数值；数值变更走各 autoload。
# 坐标基准：设计分辨率 1280×720（Godot 视口缩放保证不同分辨率对齐）。
# 布局铁律（2026-10-21/22 截图反馈返工）：
#   - 左上信息区**无背景面板**（进度条/图标自带像素底；夜数与潮币数字用深色描边保可读）；
#   - 潮币贴信息区上边缘（与 HP 条同行、进度条右侧 x=340），不得再回夜数行；
#   - HP / 经验文案必须做成各自进度条的**子节点 + 全矩形锚点**（Godot 4.7 默认主题
#     Label 最小高 23、ProgressBar 最小高 27，手工 position/size 会被最小尺寸顶掉 → 错位）；
#   - 武器行 y=VIEW_H-64 / 被动行 y=VIEW_H-34，两行不得重叠；
#   - 武器/被动槽仅图标+文字，不绘制背景面板。
# ============================================================================
extends Control

const _SKIN := preload("res://scripts/ui/pixel_skin.gd")
const _SPRITE_LIB := preload("res://scripts/core/sprite_lib.gd")

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0

var _weapon_mgr: WeaponManager = null

var _hp_bar: ProgressBar
var _hp_label: Label
var _exp_bar: ProgressBar
var _exp_label: Label
var _night_label: Label
var _diff_label: Label
var _boss_label: Label
var _weapon_box: HBoxContainer
var _passive_box: HBoxContainer
var _coin_icon: TextureRect
var _coin_label: Label
var _struggle_banner: Panel
var _struggle_title: Label
var _struggle_body: Label
var _toast_label: Label
var _toast_left: float = 0.0
## 召唤型武器图标（呼吸动画；_rebuild_slots 维护）
var _summon_icons: Array[TextureRect] = []
var _skin_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	if not GameState.loadout_changed.is_connected(_on_loadout_changed):
		GameState.loadout_changed.connect(_on_loadout_changed)
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	refresh()


func init(wm: WeaponManager) -> void:
	_weapon_mgr = wm
	refresh()
	_on_loadout_changed()  # 初始构建武器/被动槽（loadout_changed 可能已在 HUD 创建前触发）


## 宝箱开启提示（World 连接 PickupSystem.chest_opened）
func notify_chest(kind: String, amount: int, rarity_name: String) -> void:
	if _toast_label == null:
		return
	if kind == "none" or amount <= 0:
		_toast_label.text = LanguageSystem.localizef("ui.hud.chest_toast_struggle", [rarity_name])
	else:
		_toast_label.text = LanguageSystem.localizef("ui.hud.chest_toast", [
			rarity_name, _chest_kind_text(kind), amount,
		])
	_toast_label.visible = true
	_toast_left = 2.2


## 宝箱奖励类型文案（跟随语言；字面量 key 供校验器扫描，未知类型原样返回）
func _chest_kind_text(kind: String) -> String:
	match kind:
		"tidecoins":
			return LanguageSystem.localize("ui.chest.kind_tidecoins")
		"heal":
			return LanguageSystem.localize("ui.chest.kind_heal")
		"evolution":
			return LanguageSystem.localize("ui.chest.kind_evolution")
		"refine_essence":
			return LanguageSystem.localize("ui.chest.kind_refine_essence")
		"weapon":
			return LanguageSystem.localize("ui.chest.kind_weapon")
		"passive":
			return LanguageSystem.localize("ui.chest.kind_passive")
		"none":
			return LanguageSystem.localize("ui.chest.kind_none")
	return kind


func _process(delta: float) -> void:
	# 召唤型武器图标呼吸（提示场上有活的召唤物在动作）
	if not _summon_icons.is_empty():
		_skin_time += delta
		var s: float = 1.0 + 0.09 * sin(_skin_time * 4.2)
		for ic in _summon_icons:
			if is_instance_valid(ic):
				ic.scale = Vector2(s, s)
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	if _toast_left <= 0.0 and _toast_label != null:
		_toast_label.visible = false


# ---------------------------------------------------------------------------
# 构建静态元素
# ---------------------------------------------------------------------------
func _build() -> void:
	# 左上信息区（血条 + 经验条 + 夜数 + 潮币；截图反馈：不要背景面板）
	# 条高 ≥24：Godot 4.7 默认主题 Label 最小高 23（字号 override 不缩小最小高），
	# 手工 size 会被最小尺寸顶掉 → 文案改为进度条子节点 + 全矩形锚点，随条自动对齐。
	var top := Control.new()
	top.position = Vector2(12.0, 12.0)
	top.size = Vector2(440.0, 92.0)
	add_child(top)

	_hp_bar = ProgressBar.new()
	_hp_bar.size = Vector2(300.0, 26.0)
	_hp_bar.position = Vector2(12.0, 6.0)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hp_bar)
	# HP 文案：血条子节点 + 全矩形锚点（左右各缩进 8）+ 垂直居中（修复截图「条上文本错位」）
	_hp_label = Label.new()
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.offset_left = 8.0
	_hp_label.offset_right = -8.0
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_child(_hp_label)

	_exp_bar = ProgressBar.new()
	_exp_bar.size = Vector2(300.0, 24.0)
	_exp_bar.position = Vector2(12.0, 35.0)
	_exp_bar.show_percentage = false
	_exp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 像素皮肤下经验条换蓝色填充（主题里 ProgressBar 默认填血条红）
	var exp_fill: StyleBox = _SKIN.stylebox("bar_exp")
	if exp_fill != null:
		_exp_bar.add_theme_stylebox_override("fill", exp_fill)
	top.add_child(_exp_bar)
	# 经验文案：经验条子节点 + 全矩形锚点（同上修复错位）
	_exp_label = Label.new()
	_exp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exp_label.offset_left = 8.0
	_exp_label.offset_right = -8.0
	_exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_exp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_label.add_theme_font_size_override("font_size", 12)
	_exp_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_exp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exp_bar.add_child(_exp_label)

	# 潮币计数（金币图标 + 数字）：贴信息区上边缘、两条进度条右侧
	# （截图反馈 3：不再需要背景面板，金币上移至顶行与 HP 条对齐）
	_coin_icon = TextureRect.new()
	_coin_icon.position = Vector2(340.0, 8.0)
	_coin_icon.size = Vector2(20.0, 20.0)
	_coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_icon.texture = _SKIN.texture("icon_coin.png")
	top.add_child(_coin_icon)
	_coin_label = Label.new()
	_coin_label.position = Vector2(364.0, 8.0)
	_coin_label.size = Vector2(72.0, 20.0)
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_label.add_theme_font_size_override("font_size", 14)
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	# 无背景面板（截图反馈）→ 深色描边保证在杂乱地图上的可读性
	_coin_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_coin_label.add_theme_constant_override("outline_size", 4)
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_coin_label)

	# 夜数：只显示「第N夜」（截图反馈：不显示 /20 与教学夜后缀）
	_night_label = Label.new()
	_night_label.position = Vector2(12.0, 62.0)
	_night_label.size = Vector2(416.0, 22.0)
	_night_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_night_label.add_theme_font_size_override("font_size", 15)
	_night_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	# 无背景面板（截图反馈）→ 同上深色描边
	_night_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_night_label.add_theme_constant_override("outline_size", 4)
	top.add_child(_night_label)

	# 右上：难度档位 + Boss 提示
	_diff_label = Label.new()
	_diff_label.position = Vector2(VIEW_W - 360.0, 12.0)
	_diff_label.size = Vector2(348.0, 24.0)
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_diff_label.add_theme_font_size_override("font_size", 16)
	_diff_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_diff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_diff_label)

	_boss_label = Label.new()
	_boss_label.position = Vector2(VIEW_W - 360.0, 40.0)
	_boss_label.size = Vector2(348.0, 24.0)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_label.add_theme_font_size_override("font_size", 16)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_label)

	# 左下：武器槽 + 被动槽（截图反馈 2：两行原先相互重叠、图文过挤、贴屏幕底边
	#       → 行距拉开、底部留 34px 边距、槽位不绘制背景面板仅图标+文字+描边）
	_weapon_box = HBoxContainer.new()
	_weapon_box.position = Vector2(12.0, VIEW_H - 64.0)
	_weapon_box.add_theme_constant_override("separation", 10)
	add_child(_weapon_box)
	_passive_box = HBoxContainer.new()
	_passive_box.position = Vector2(12.0, VIEW_H - 34.0)
	_passive_box.add_theme_constant_override("separation", 10)
	add_child(_passive_box)

	# 挣扎模式提示横幅（W17 挫败感控制：0 血免死窗口显式提示，避免被误判为卡死）
	var sb := Panel.new()
	sb.name = "StruggleBanner"
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.position = Vector2(VIEW_W * 0.5 - 230.0, VIEW_H * 0.40)
	sb.size = Vector2(460.0, 92.0)
	sb.visible = false
	# 挣扎横幅：皮肤启用时用像素 panel_death；关闭时保留原有就地扁平样式
	# （不能直接调 death_panel_style() 的回退分支——那是结算页配色，
	#   挣扎横幅原本更透更红，直接换会让「关掉皮肤」也变色）
	var sb_style: StyleBox = _SKIN.stylebox_with_margin("panel_death", 14.0)
	if sb_style == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.06, 0.02, 0.04, 0.80)
		flat.border_color = Color(1.0, 0.35, 0.30, 0.95)
		flat.set_corner_radius_all(10)
		flat.set_border_width_all(2)
		sb_style = flat
	sb.add_theme_stylebox_override("panel", sb_style)
	var sb_v := VBoxContainer.new()
	sb_v.position = Vector2(14.0, 12.0)
	sb_v.size = Vector2(432.0, 68.0)
	sb_v.add_theme_constant_override("separation", 8)
	var sb_title := Label.new()
	sb_title.name = "Title"
	sb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb_title.add_theme_font_size_override("font_size", 26)
	sb_title.add_theme_color_override("font_color", Color(1.0, 0.38, 0.32))
	var sb_body := Label.new()
	sb_body.name = "Body"
	sb_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb_body.add_theme_font_size_override("font_size", 15)
	sb_body.add_theme_color_override("font_color", Color(1.0, 0.90, 0.84))
	sb_v.add_child(sb_title)
	sb_v.add_child(sb_body)
	sb.add_child(sb_v)
	add_child(sb)
	_struggle_banner = sb
	_struggle_title = sb_title
	_struggle_body = sb_body

	# 宝箱拾取轻提示（屏幕上方居中）
	var toast := Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.position = Vector2(340.0, 96.0)
	toast.size = Vector2(600.0, 28.0)
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	add_child(toast)
	_toast_label = toast


# ---------------------------------------------------------------------------
# 每帧刷新（world._process 调用；游戏结束/通关时 world 显式再调一次）
# ---------------------------------------------------------------------------
func refresh() -> void:
	if _hp_bar == null:
		return
	var hp: int = GameState.player_health
	var maxhp: int = GameState.player_max_health
	_hp_bar.max_value = maxi(1, maxhp)
	_hp_bar.value = clampi(hp, 0, maxhp)
	_hp_label.text = LanguageSystem.localizef("ui.hud.hp", [hp, maxhp])

	var lvl: int = GameState.player_level
	var need: int = ExpTable.get_exp(lvl)
	_exp_bar.max_value = maxi(1, need)
	_exp_bar.value = clampi(GameState.player_exp, 0, need)
	_exp_label.text = LanguageSystem.localizef("ui.hud.exp", [lvl, GameState.player_exp, need])

	var night: int = GameState.current_night
	# 夜数只显示「第N夜」：不显示 /20、不挂教学夜后缀（截图反馈；
	# 教学夜机制本身保留在 DifficultySystem.is_teaching_night，由难度系统测试覆盖）
	_night_label.text = LanguageSystem.localizef("ui.hud.night", [night])

	# 潮币计数（金币图标旁的数字）
	if _coin_label != null:
		_coin_label.text = str(GameState.tidecoins)

	_diff_label.text = LanguageSystem.localize("ui.difficulty") + DifficultySystem.get_tier_label()

	if DifficultySystem.boss_prompt_enabled() and _is_boss_night(night):
		_boss_label.text = LanguageSystem.localize("ui.boss_warn")
	else:
		_boss_label.text = ""

	# 挣扎模式提示：0 血免死窗口中显式提示（解释「延迟结算」非卡死）
	if GameState.is_player_down():
		if _struggle_banner != null:
			if not _struggle_banner.visible:
				_struggle_banner.visible = true
			_struggle_title.text = LanguageSystem.localize("ui.struggle.title")
			var got: int = GameState.get_struggle_kills()
			var need_kills: int = GameState.get_struggle_kills_needed()
			var remain: float = GameState.get_struggle_remaining()
			_struggle_body.text = LanguageSystem.localizef("ui.struggle.body", [got, need_kills, remain])
	else:
		if _struggle_banner != null and _struggle_banner.visible:
			_struggle_banner.visible = false


func _on_loadout_changed() -> void:
	# 先于重建同步实例，避免 signal 连接顺序导致 HUD 读到 stale WeaponManager
	if _weapon_mgr != null:
		_weapon_mgr.sync_from_game_state()
	# 呼吸动画列表跨两行重建维护：必须在外层清一次（_rebuild_slots 内不清，
	# 否则被动行重建会把武器行收集的召唤图标清掉）
	_summon_icons.clear()
	_rebuild_slots(_weapon_box, _weapon_slots())
	_rebuild_slots(_passive_box, _passive_slots())


func _on_language_changed(_lang: String) -> void:
	refresh()
	_on_loadout_changed()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _is_boss_night(night: int) -> bool:
	var cal: Dictionary = ConfigLoader.get_boss_calamity()
	var nights: Variant = cal.get("calamity_nights", [10, 15, 20])
	if nights is Array:
		for v in nights:
			if int(v) == night:
				return true
	return false


func _weapon_slots() -> Array[Dictionary]:
	# 武器槽：每项 = {icon, text, series(进化系), summon(召唤型呼吸动画), series_color}
	var out: Array[Dictionary] = []
	if _weapon_mgr != null:
		for w in _weapon_mgr.get_weapons():
			var wid: String = w.weapon_id
			var wname: String = GameState.get_weapon_display_name(wid)
			var wdata: Dictionary = ConfigLoader.get_weapon(wid)
			var series: String = ""
			var evo: Variant = wdata.get("evolution", null)
			if evo is Dictionary:
				series = String((evo as Dictionary).get("passive_series", ""))
			out.append({
				"icon": _SPRITE_LIB.weapon(wid),
				"text": "%s Lv%d" % [wname, w.level],
				"series": series,
				"summon": wdata.get("summon", null) is Dictionary,
				"series_color": _series_color(series),
			})
	return out


func _passive_slots() -> Array[Dictionary]:
	# 被动槽：每项 = {icon, text, series, series_color}（series 来自 passives.json）
	var out: Array[Dictionary] = []
	for pid in ConfigLoader.get_all_passive_ids():
		var lv: int = GameState.get_passive_level(pid)
		if lv > 0:
			var d: Dictionary = ConfigLoader.get_passive(pid)
			var pname: String = LanguageSystem.localize_config_name(
				"passive", pid, String(d.get("name", pid)))
			var series: String = String(d.get("series", ""))
			out.append({
				"icon": _SPRITE_LIB.passive(pid),
				"text": "%s Lv%d" % [pname, lv],
				"series": series,
				"series_color": _series_color(series),
			})
	return out


## 进化系配色（config/ui_skin.json series_colors；未配置返回白）
func _series_color(series: String) -> Color:
	if series == "":
		return Color(1, 1, 1)
	var colors: Dictionary = ConfigLoader.get_ui_skin_config().get("series_colors", {})
	var hex: String = String(colors.get(series, ""))
	if hex == "":
		return Color(1, 1, 1)
	var s: String = hex.strip_edges()
	if not s.begins_with("#"):
		s = "#" + s
	return Color.from_string(s, Color(1, 1, 1))


## 重建一排槽位（图标 + series 色标 + 文字）；items 每项 = {icon, text, series_color, summon}
## 截图反馈：武器/道具槽不显示背景面板（原 PanelContainer 芯片外框移除）；
## 2026-10-22：进化系色条（ui_skin.json series_colors）+ 召唤型武器图标呼吸动画
func _rebuild_slots(box: HBoxContainer, items: Array[Dictionary]) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for it in items:
		var entry: Dictionary = it
		var series_col: Color = entry.get("series_color", Color(1, 1, 1)) as Color
		var icon: Texture2D = entry.get("icon", null) as Texture2D
		if icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = icon
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# 固定 22px 图标盒：EXPAND_IGNORE_SIZE 防止贴图原尺寸（>22）把盒子撑大
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.custom_minimum_size = Vector2(22.0, 22.0)
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_rect.pivot_offset = Vector2(11.0, 11.0)
			box.add_child(icon_rect)
			# series 色条：图标底部 3px（标识进化系；白=无系）
			if series_col != Color(1, 1, 1):
				var strip := ColorRect.new()
				strip.color = series_col
				strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				strip.custom_minimum_size = Vector2(22.0, 3.0)
				strip.size = Vector2(22.0, 3.0)
				strip.position = Vector2(0.0, 19.0)
				icon_rect.add_child(strip)
			# 召唤型武器：呼吸缩放（提示场上有活的召唤物）
			if bool(entry.get("summon", false)):
				_summon_icons.append(icon_rect)
		var lbl := Label.new()
		lbl.text = String(entry.get("text", ""))
		lbl.add_theme_font_size_override("font_size", 13)
		# 文字色向 series 色提亮（保持可读性的同时贴合系色）
		var txt_col: Color = series_col.lerp(Color(0.95, 0.97, 1.0), 0.35)
		lbl.add_theme_color_override("font_color", txt_col)
		# 无背景面板（截图反馈）→ 用深色描边保证文字在杂乱地面上的可读性
		lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		box.add_child(lbl)
