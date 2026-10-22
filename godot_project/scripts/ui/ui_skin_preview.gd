# ============================================================================
# UiSkinPreview — 卡通像素风 UI 资源预览（开发用场景，不参与机检）
# 用途：一屏看完 九宫格面板 / 按钮四态 / 进度条 / 槽位芯片 / 点阵图标
# 用法：编辑器打开 scenes/ui_skin_preview.tscn，或
#       godot --path godot_project res://scenes/ui_skin_preview.tscn
# 截图：追加用户参数 -- --shot → 渲染若干帧后存 user://ui_preview.png 并退出
# ============================================================================
extends Control

const _UI := preload("res://scripts/ui/ui_chrome.gd")
const _SKIN := preload("res://scripts/ui/pixel_skin.gd")

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0
const MAIN_SCENE := preload("res://scenes/main.tscn")
const CHAR_SCENE := preload("res://scenes/character_select.tscn")
const LH_SCENE := preload("res://scenes/lighthouse_tree.tscn")
const ICON_NAMES: Array[String] = [
	"icon_heart.png", "icon_coin.png", "icon_star.png",
	"icon_skull.png", "icon_chest.png", "icon_sword.png", "cursor_arrow.png",
]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# --noskin：临时关闭皮肤（只改内存配置，不落盘），用于 A/B 对照排查
	#           「某个视觉问题是皮肤引入的，还是本来就有的」
	if "--noskin" in args:
		ConfigLoader.ui_skin["enabled"] = false
		_SKIN.reset_cache_for_test()
		UiChrome.reset_cache_for_test()
	# --world  ：实例化真实对局，核对 HUD
	# --char   ：选角首屏，核对角色卡面板 / 按钮
	# --upgrade：局内三选一（UpgradeUI）
	# --day    ：抉择之昼（DayPhaseUI 事件卡 + ShopUI 商店）
	# --result ：结算页（ResultUI，含死因 / 挣扎面板）
	if "--world" in args or "--char" in args or "--lh" in args:
		var scene: PackedScene = CHAR_SCENE
		if "--world" in args:
			scene = MAIN_SCENE
		elif "--lh" in args:
			scene = LH_SCENE
		var ui: Node = scene.instantiate()
		add_child(ui)
		_SKIN.apply_to(self)
		# --lit：把灯塔树第一个节点伪造成「已点亮」态，用于核对 lit 贴图与字色
		#        （不真的 purchase，避免污染 user://savegame.json 真实存档）
		if "--lh" in args and "--lit" in args:
			for i in 4:
				await get_tree().process_frame
			var first: Button = null
			for key in ui._node_buttons.keys():
				first = ui._node_buttons[key] as Button
				break
			if first != null:
				first.text = "已点亮"
				first.disabled = true
				ui._apply_btn_chrome(first, "lit")
		if "--shot" in args:
			_capture.call_deferred()
		return
	if "--upgrade" in args or "--day" in args or "--result" in args or "--evo" in args:
		_enter_world_sub_ui(args)
		return
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()
	_SKIN.apply_to(self)
	if "--shot" in args:
		_capture.call_deferred()


## 实例化真实对局并强制弹出某个子 UI，用于核对局内各界面是否都吃到皮肤。
## 这些 UI 全部是 main.tscn 里 $UI 的静态子节点，world.gd 的 apply_to 应一次覆盖；
## 本模式就是用来实证「覆盖到了」而不是只靠推理。
func _enter_world_sub_ui(args: PackedStringArray) -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	_SKIN.apply_to(self)
	var world: Node = main
	# 等 World._ready 及其子 UI 全部就绪
	for i in 6:
		await get_tree().process_frame
	if "--upgrade" in args:
		# 直接抬经验触发升级 → UpgradeManager 发 upgrade_offered → UpgradeUI 弹出
		GameState.add_exp(9999)
	elif "--day" in args:
		# 抉择之昼：DayPhaseUI 框架 + 事件卡 + 商店
		world.day_phase_ui.enter_day(3, EventSystem.get_active_event_display_name())
		world.shop_manager.open_shop()
	elif "--result" in args:
		# 结算页：死因可视化 + 挣扎/死亡面板
		world.result_ui.show_game_over("enemy_projectile", 12, 9, 240, 60)
	elif "--evo" in args:
		# 进化共鸣（金色面板，与事件卡的青色区分）
		world.get_node("UI/EvolutionEffectUI").play(9.0, "harpoon")
	# --focus：给第一个按钮抓焦点，用于验证主题 focus 贴图不会糊住整块卡片
	#         （三选一的「整卡透明按钮」flat=true + 全屏锚点，最容易被 focus 贴图盖满）
	if "--focus" in args:
		for i in 3:
			await get_tree().process_frame
		var btns: Array[Node] = world.find_children("*", "Button", true, false)
		if btns.size() > 0:
			(btns[0] as Button).grab_focus()
	for i in 10:
		await get_tree().process_frame
	if "--shot" in args:
		_capture.call_deferred()


func _section(text: String, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(40.0, y)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.62, 0.58, 0.82))
	add_child(l)


func _build() -> void:
	var title := Label.new()
	title.text = "卡通像素风 UI 皮肤"
	title.position = Vector2(40.0, 20.0)
	title.add_theme_font_size_override("font_size", _UI.FONT_TITLE)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	add_child(title)

	var sub := Label.new()
	sub.text = "assets/ui/pixel/ · config/ui_skin.json · 九宫格 StyleBoxTexture"
	sub.position = Vector2(40.0, 62.0)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.6, 0.56, 0.78))
	add_child(sub)

	# --- 按钮四态 ---------------------------------------------------------
	_section("按钮（normal / hover / pressed / disabled + 主题默认态）", 96.0)
	var states: Array = [
		["btn_normal", "常态"],
		["btn_hover", "悬停"],
		["btn_pressed", "按下"],
		["btn_disabled", "禁用"],
	]
	var x: float = 40.0
	for item in states:
		var btn := Button.new()
		btn.text = String(item[1])
		btn.position = Vector2(x, 120.0)
		btn.size = Vector2(190.0, 52.0)
		var sb: StyleBox = _SKIN.stylebox(String(item[0]))
		if sb != null:
			for slot in ["normal", "hover", "pressed", "disabled", "focus"]:
				btn.add_theme_stylebox_override(slot, sb)
		add_child(btn)
		x += 205.0
	var themed := Button.new()
	themed.text = "主题默认（继承）"
	themed.position = Vector2(x, 120.0)
	themed.size = Vector2(190.0, 52.0)
	add_child(themed)

	# --- 面板 -------------------------------------------------------------
	_section("面板（panel_dark / panel_accent / panel_death）", 190.0)
	_add_panel("panel_dark", "常规面板", Vector2(40.0, 214.0), Color(0.85, 0.82, 1.0))
	_add_panel("panel_accent", "事件卡（强调）", Vector2(420.0, 214.0), Color(0.75, 1.0, 0.92))
	_add_panel("panel_death", "死因 / 挣扎", Vector2(800.0, 214.0), Color(1.0, 0.82, 0.85))

	# --- 进度条 -----------------------------------------------------------
	_section("进度条（血条 / 经验条 / Boss 条，中段平铺）", 356.0)
	_add_bar("bar_hp", 1.0, Vector2(40.0, 380.0), Vector2(400.0, 28.0))
	_add_bar("bar_hp", 0.55, Vector2(470.0, 380.0), Vector2(400.0, 28.0))
	_add_bar("bar_exp", 0.72, Vector2(40.0, 420.0), Vector2(400.0, 22.0))
	_add_bar("bar_boss", 0.38, Vector2(470.0, 420.0), Vector2(400.0, 22.0))

	# --- 槽位 / 芯片 ------------------------------------------------------
	_section("槽位芯片（HUD 武器 / 被动）", 470.0)
	var chip_style: StyleBox = _UI.chip_style()
	var slot_style: StyleBox = _SKIN.stylebox("slot")
	var cx: float = 40.0
	for label_text in ["锚锤 Lv3", "圣火 Lv2", "雷云 Lv1"]:
		var chip := PanelContainer.new()
		chip.position = Vector2(cx, 494.0)
		if chip_style != null:
			chip.add_theme_stylebox_override("panel", chip_style)
		var l := Label.new()
		l.text = label_text
		l.add_theme_font_size_override("font_size", 14)
		chip.add_child(l)
		add_child(chip)
		cx += 150.0
	for i in 2:
		var slot := PanelContainer.new()
		slot.position = Vector2(520.0 + float(i) * 56.0, 494.0)
		slot.custom_minimum_size = Vector2(48.0, 48.0)
		if slot_style != null:
			slot.add_theme_stylebox_override("panel", slot_style)
		add_child(slot)

	# --- 图标 -------------------------------------------------------------
	_section("点阵图标（16×16 逻辑，×3 放大）", 566.0)
	var ix: float = 40.0
	for name in ICON_NAMES:
		var tex: Texture2D = _SKIN.texture(name)
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.position = Vector2(ix, 590.0)
		tr.size = Vector2(48.0, 48.0)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(tr)
		ix += 62.0

	var foot := Label.new()
	foot.text = "占位素材由 tools/generate_ui_pixel_assets.py 程序化生成，可整批替换为美术资源"
	foot.position = Vector2(40.0, 668.0)
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", Color(0.5, 0.47, 0.66))
	add_child(foot)


func _add_panel(style_id: String, text: String, pos: Vector2, color: Color) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = Vector2(360.0, 120.0)
	var sb: StyleBox = _SKIN.stylebox(style_id)
	if sb != null:
		p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(24.0, 20.0)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	var l2 := Label.new()
	l2.text = "九宫格四角保护，中段拉伸不变形"
	l2.position = pos + Vector2(24.0, 58.0)
	l2.add_theme_font_size_override("font_size", 14)
	l2.add_theme_color_override("font_color", Color(0.72, 0.70, 0.88))
	add_child(l2)


func _add_bar(style_id: String, value: float, pos: Vector2, size: Vector2) -> void:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = size
	bar.value = value * 100.0
	bar.show_percentage = false
	var fill: StyleBox = _SKIN.stylebox(style_id)
	if fill != null:
		bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)


func _capture() -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://ui_preview.png"
	for flag in ["world", "char", "lh", "upgrade", "day", "result", "evo"]:
		if ("--" + flag) in OS.get_cmdline_user_args():
			path = "user://ui_preview_%s.png" % flag
			break
	if "--noskin" in OS.get_cmdline_user_args():
		path = path.replace(".png", "_noskin.png")
	if "--focus" in OS.get_cmdline_user_args():
		path = path.replace(".png", "_focus.png")
	if "--lit" in OS.get_cmdline_user_args():
		path = path.replace(".png", "_lit.png")
	var err: int = img.save_png(path)
	print("[UiSkinPreview] 截图 %s err=%d size=%s" % [path, err, str(img.get_size())])
	get_tree().quit(0 if err == OK else 1)
