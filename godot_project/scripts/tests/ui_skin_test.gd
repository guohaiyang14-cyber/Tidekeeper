# ============================================================================
# UiSkinTest — 卡通像素风 UI 皮肤机检
# 验收：22 贴图可加载且尺寸符合 BLOCK 倍率；九宫格边距不超贴图半宽；
#       styles 与磁盘文件一一对应；Theme 含 Button/Panel/ProgressBar 条目且
#       全为 StyleBoxTexture；进度条中段平铺、面板拉伸；缓存不串味；
#       apply_to 能跨 CanvasLayer / Node2D 截断段挂上主题（P1 回归）；
#       关闭开关时全部回退 StyleBoxFlat；HUD 实机接线（血条/经验条异色）。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/ui_skin_test.tscn
# ============================================================================
extends Node2D

const _SKIN := preload("res://scripts/ui/pixel_skin.gd")
const HUD_SCRIPT = preload("res://scripts/core/hud.gd")
const WEAPON_MANAGER = preload("res://scripts/combat/weapon_manager.gd")
const SPATIAL_HASH = preload("res://scripts/core/spatial_hash.gd")
const PROJECTILE_POOL = preload("res://scripts/core/projectile_pool.gd")

## 逻辑像素 × BLOCK(3)：与 tools/generate_ui_pixel_assets.py 的 BLOCK 对应
const _BLOCK: int = 3
## 各贴图的逻辑边长（见生成脚本）
const _EXPECT_LOGICAL: Dictionary = {
	"panel_dark.png": 24,
	"panel_accent.png": 24,
	"panel_death.png": 24,
	"panel_gold.png": 24,
	"chip.png": 12,
	"slot_frame.png": 16,
	"btn_normal.png": 16,
	"btn_hover.png": 16,
	"btn_pressed.png": 16,
	"btn_disabled.png": 16,
	"btn_lit.png": 16,
	"bar_bg.png": 8,
	"bar_hp.png": 8,
	"bar_exp.png": 8,
	"bar_boss.png": 8,
	"icon_heart.png": 16,
	"icon_coin.png": 16,
	"icon_star.png": 16,
	"icon_skull.png": 16,
	"icon_chest.png": 16,
	"icon_sword.png": 16,
	"cursor_arrow.png": 16,
}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("UI 皮肤（卡通像素风）机检")
	print("============================================================")
	_SKIN.reset_cache_for_test()
	UiChrome.reset_cache_for_test()

	print("[assert] 配置完整性")
	_test_config()

	print("[assert] 贴图可加载 + 尺寸")
	_test_textures()

	print("[assert] 九宫格边距合法")
	_test_nine_patch()

	print("[assert] styles ↔ 磁盘文件一致")
	_test_styles_mapping()

	print("[assert] Theme 条目")
	_test_theme()

	print("[assert] 样式属性（平铺/拉伸/边距/缓存）")
	_test_style_props()

	print("[assert] apply_to 跨 CanvasLayer 生效")
	_test_apply_to()

	print("[assert] UiChrome 接入")
	_test_ui_chrome()

	print("[assert] apply_button_state（按钮三态）")
	_test_button_state()

	print("[assert] HUD 实机接线")
	_test_hud()

	print("[assert] 关闭开关回退扁平样式")
	_test_disabled_fallback()

	print("[assert] 静态缓存释放（退出时不泄漏贴图）")
	_test_release_cache()

	print("------------------------------------------------------------")
	print("UI 皮肤机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
func _test_config() -> void:
	var cfg: Dictionary = _SKIN.config()
	_assert(not cfg.is_empty(), "config/ui_skin.json 已加载")
	_assert(_SKIN.is_enabled(), "皮肤开关 enabled=true")
	_assert(String(cfg.get("asset_dir", "")) == "res://assets/ui/pixel/", "asset_dir 指向像素资源目录")
	var styles: Variant = cfg.get("styles", {})
	_assert(styles is Dictionary and (styles as Dictionary).size() == 15, "styles 共 15 条")
	var patches: Variant = cfg.get("nine_patch", {})
	_assert(patches is Dictionary and (patches as Dictionary).size() == 5, "nine_patch 共 5 个键")
	for key in ["panel", "button", "chip", "slot", "bar"]:
		_assert((patches as Dictionary).has(key), "nine_patch 含 %s" % key)


# ---------------------------------------------------------------------------
# 贴图
# ---------------------------------------------------------------------------
func _test_textures() -> void:
	for filename in _EXPECT_LOGICAL.keys():
		var tex: Texture2D = _SKIN.texture(String(filename))
		_assert(tex != null, "贴图可加载: %s" % filename)
		if tex == null:
			continue
		var logical: int = int(_EXPECT_LOGICAL[filename])
		var want: int = logical * _BLOCK
		var size: Vector2 = tex.get_size()
		_assert(
			int(size.x) == want and int(size.y) == want,
			"尺寸 %s = %d×%d（逻辑 %d × BLOCK %d）" % [filename, want, want, logical, _BLOCK]
		)
	# 缓存命中：同一 filename 两次返回同一实例
	_assert(_SKIN.texture("panel_dark.png") == _SKIN.texture("panel_dark.png"), "贴图缓存命中同实例")
	# 不存在的文件安全返回 null
	_assert(_SKIN.texture("no_such_file.png") == null, "缺失贴图返回 null 不崩")
	_assert(_SKIN.texture("") == null, "空文件名返回 null")


# ---------------------------------------------------------------------------
# 九宫格
# ---------------------------------------------------------------------------
func _test_nine_patch() -> void:
	var cfg: Dictionary = _SKIN.config()
	var patches: Dictionary = cfg.get("nine_patch", {}) as Dictionary
	for style_id in ["panel_dark", "panel_accent", "panel_death", "chip", "slot", "btn_normal", "bar_bg"]:
		var sb: StyleBoxTexture = _SKIN.stylebox(String(style_id))
		_assert(sb != null, "stylebox 可构建: %s" % style_id)
		if sb == null:
			continue
		var tex_size: Vector2 = sb.texture.get_size()
		var half_w: float = tex_size.x * 0.5
		var half_h: float = tex_size.y * 0.5
		# 九宫格四边边距之和必须小于贴图边长，否则中段被挤成负宽
		_assert(
			sb.texture_margin_left + sb.texture_margin_right < tex_size.x,
			"%s 横向边距 %.0f+%.0f < 贴图宽 %.0f" % [
				style_id, sb.texture_margin_left, sb.texture_margin_right, tex_size.x
			]
		)
		_assert(
			sb.texture_margin_top + sb.texture_margin_bottom < tex_size.y,
			"%s 纵向边距 %.0f+%.0f < 贴图高 %.0f" % [
				style_id, sb.texture_margin_top, sb.texture_margin_bottom, tex_size.y
			]
		)
		_assert(
			sb.texture_margin_left <= half_w and sb.texture_margin_top <= half_h,
			"%s 边距不超贴图半宽（边角不被挤压）" % style_id
		)
	# 边距值来自 config，非硬编码
	var panel_margin: int = int(patches.get("panel", 0))
	_assert(int(_SKIN.stylebox("panel_dark").texture_margin_left) == panel_margin, "面板边距取自 nine_patch.panel")
	var bar_margin: int = int(patches.get("bar", 0))
	_assert(int(_SKIN.stylebox("bar_hp").texture_margin_top) == bar_margin, "进度条边距取自 nine_patch.bar")


# ---------------------------------------------------------------------------
# styles ↔ 磁盘
# ---------------------------------------------------------------------------
func _test_styles_mapping() -> void:
	var cfg: Dictionary = _SKIN.config()
	var styles: Dictionary = cfg.get("styles", {}) as Dictionary
	var dir: String = String(cfg.get("asset_dir", ""))
	for style_id in styles.keys():
		var def: Dictionary = styles[style_id] as Dictionary
		var filename: String = String(def.get("texture", ""))
		_assert(filename != "", "样式 %s 声明了 texture" % style_id)
		_assert(FileAccess.file_exists(dir + filename), "样式 %s 的贴图文件存在: %s" % [style_id, filename])
		_assert(String(def.get("patch", "")) != "", "样式 %s 声明了九宫格 patch 键" % style_id)
		_assert((cfg.get("nine_patch", {}) as Dictionary).has(String(def.get("patch", ""))), "样式 %s 的 patch 键在 nine_patch 中" % style_id)
	# 反向：目录里每个 PNG 要么被 styles 引用，要么是图标（icon_/cursor_）
	var referenced: Dictionary = {}
	for style_id in styles.keys():
		referenced[String((styles[style_id] as Dictionary).get("texture", ""))] = true
	var icons: int = 0
	for filename in _EXPECT_LOGICAL.keys():
		if String(filename).begins_with("icon_") or String(filename).begins_with("cursor_"):
			icons += 1
			continue
		_assert(referenced.has(String(filename)), "贴图 %s 已被 styles 引用（无孤儿资源）" % filename)
	_assert(icons == 7, "图标类资源共 7 个（6 icon + 1 cursor）")


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
func _test_theme() -> void:
	var theme: Theme = _SKIN.get_theme()
	_assert(theme != null, "Theme 已构建")
	if theme == null:
		return
	for slot in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBox = theme.get_stylebox(String(slot), "Button")
		_assert(sb is StyleBoxTexture, "Theme Button.%s 是九宫格贴图" % slot)
	for type_name in ["Panel", "PanelContainer"]:
		var sb: StyleBox = theme.get_stylebox("panel", String(type_name))
		_assert(sb is StyleBoxTexture, "Theme %s.panel 是九宫格贴图" % type_name)
	for slot in ["background", "fill"]:
		var sb: StyleBox = theme.get_stylebox(String(slot), "ProgressBar")
		_assert(sb is StyleBoxTexture, "Theme ProgressBar.%s 是九宫格贴图" % slot)
	# 进度条背景与填充必须是两张不同贴图（否则看不出血量）
	var bg: StyleBoxTexture = theme.get_stylebox("background", "ProgressBar") as StyleBoxTexture
	var fill: StyleBoxTexture = theme.get_stylebox("fill", "ProgressBar") as StyleBoxTexture
	_assert(bg != null and fill != null and bg.texture != fill.texture, "进度条背景/填充贴图不同")
	# 字色
	_assert(theme.get_color("font_color", "Button") == Color("#F4F0FF"), "Button 字色 #F4F0FF")
	_assert(theme.get_color("font_hover_color", "Button") == Color("#FFE08A"), "Button 悬停字色 #FFE08A")
	_assert(theme.get_color("font_color", "Label") == Color("#EDE8FF"), "Label 字色 #EDE8FF")
	# 二次取用返回同一 Theme（缓存）
	_assert(_SKIN.get_theme() == theme, "Theme 缓存复用同实例")


# ---------------------------------------------------------------------------
# 样式属性
# ---------------------------------------------------------------------------
func _test_style_props() -> void:
	# 进度条中段平铺（保像素块感），面板/按钮拉伸
	for style_id in ["bar_bg", "bar_hp", "bar_exp", "bar_boss"]:
		var sb: StyleBoxTexture = _SKIN.stylebox(String(style_id))
		_assert(sb != null and sb.axis_stretch_horizontal == TextureRect.STRETCH_TILE, "%s 横向平铺" % style_id)
	for style_id in ["panel_dark", "btn_normal", "chip", "slot"]:
		var sb: StyleBoxTexture = _SKIN.stylebox(String(style_id))
		_assert(sb != null and sb.axis_stretch_horizontal == TextureRect.STRETCH_SCALE, "%s 横向拉伸" % style_id)
	# content_margin 来自 config
	var panel_sb: StyleBoxTexture = _SKIN.stylebox("panel_dark")
	_assert(panel_sb != null and is_equal_approx(panel_sb.content_margin_left, 12.0), "panel_dark content_margin=12")
	# 缓存：两次同 id 同实例
	_assert(_SKIN.stylebox("panel_dark") == _SKIN.stylebox("panel_dark"), "stylebox 缓存命中同实例")
	# stylebox_with_margin：不同 margin 得到不同实例，且不污染基样式
	var a: StyleBoxTexture = _SKIN.stylebox_with_margin("panel_dark", 12.0)
	var b: StyleBoxTexture = _SKIN.stylebox_with_margin("panel_dark", 20.0)
	_assert(a != null and b != null and a != b, "不同 content_margin 得到不同实例")
	_assert(is_equal_approx(a.content_margin_left, 12.0) and is_equal_approx(b.content_margin_left, 20.0), "content_margin 各自独立")
	_assert(is_equal_approx(_SKIN.stylebox("panel_dark").content_margin_left, 12.0), "基样式 content_margin 未被 duplicate 污染")
	# 未知 style id 安全返回 null
	_assert(_SKIN.stylebox("no_such_style") == null, "未知 style id 返回 null")


# ---------------------------------------------------------------------------
# apply_to（P1 回归：CanvasLayer / Node2D 会截断 Theme 继承）
# ---------------------------------------------------------------------------
func _test_apply_to() -> void:
	# 复刻实机父链：Node2D → CanvasLayer → Control(HUD) → ProgressBar
	var stage: Node2D = Node2D.new()
	add_child(stage)
	var layer: CanvasLayer = CanvasLayer.new()
	stage.add_child(layer)
	var hud: Control = Control.new()
	layer.add_child(hud)
	var bar: ProgressBar = ProgressBar.new()
	hud.add_child(bar)
	# 未挂皮肤：走引擎默认主题 → StyleBoxFlat
	_assert(bar.get_theme_stylebox("background") is StyleBoxFlat, "未 apply 时进度条用默认扁平样式")
	# 挂皮肤
	_SKIN.apply_to(stage)
	_assert(hud.theme != null, "apply_to 给 CanvasLayer 下的 Control 挂上了主题")
	_assert(bar.get_theme_stylebox("background") is StyleBoxTexture, "跨 CanvasLayer 后进度条吃到像素皮肤")
	_assert(bar.get_theme_stylebox("fill") is StyleBoxTexture, "跨 CanvasLayer 后进度条填充吃到像素皮肤")
	# 主题挂在 Control 而非 Node2D（Node2D 无 theme 属性，挂上去也传不下去）
	_assert(bar.get_theme_stylebox("background") is StyleBoxTexture, "进度条经 Control 祖先继承到主题")
	# 幂等：重复 apply 不重复设
	var theme_ref: Theme = hud.theme
	_SKIN.apply_to(stage)
	_assert(hud.theme == theme_ref, "重复 apply_to 幂等")
	# 多段继承链：子树里另有 CanvasLayer 时也能覆盖
	var layer2: CanvasLayer = CanvasLayer.new()
	stage.add_child(layer2)
	var overlay: Control = Control.new()
	layer2.add_child(overlay)
	_SKIN.apply_to(stage)
	_assert(overlay.theme != null, "子树里另起的 CanvasLayer 段也被覆盖")
	# 直接对一个 Control 调用也能生效
	var solo: Control = Control.new()
	add_child(solo)
	_SKIN.apply_to(solo)
	_assert(solo.theme != null, "对 Control 直接 apply_to 生效")
	stage.queue_free()
	solo.queue_free()


# ---------------------------------------------------------------------------
# UiChrome
# ---------------------------------------------------------------------------
func _test_ui_chrome() -> void:
	UiChrome.reset_cache_for_test()
	var panel: StyleBox = UiChrome.panel_style()
	_assert(panel is StyleBoxTexture, "UiChrome.panel_style 走像素皮肤")
	var accent: StyleBox = UiChrome.accent_panel_style()
	_assert(accent is StyleBoxTexture, "UiChrome.accent_panel_style 走像素皮肤")
	var death: StyleBox = UiChrome.death_panel_style()
	_assert(death is StyleBoxTexture, "UiChrome.death_panel_style 走像素皮肤")
	var gold: StyleBox = UiChrome.gold_panel_style()
	_assert(gold is StyleBoxTexture, "UiChrome.gold_panel_style 走像素皮肤")
	# 三张面板贴图必须互不相同，否则「常规 / 事件卡 / 死因 / 共鸣」语义混同
	_assert(
		panel != accent and accent != death and panel != death and gold != accent and gold != death,
		"常规/强调/死因/共鸣 四类面板贴图互不相同"
	)
	var chip: StyleBox = UiChrome.chip_style()
	_assert(chip is StyleBoxTexture, "UiChrome.chip_style 走像素皮肤")
	_assert(UiChrome.chip_style() == chip, "chip_style 缓存复用同实例")
	_assert(UiChrome.pixel_style("no_such_style", 8.0) == null, "pixel_style 未知 id 返回 null")
	# 按钮三态：灯塔树 lit / available / locked 必须用三张不同贴图（否则语义混淆）
	var lit: StyleBoxTexture = _SKIN.stylebox("btn_lit")
	var normal: StyleBoxTexture = _SKIN.stylebox("btn_normal")
	var dis: StyleBoxTexture = _SKIN.stylebox("btn_disabled")
	_assert(lit != null and normal != null and dis != null, "按钮三态贴图均可构建")
	_assert(
		lit != null and normal != null and dis != null
		and lit.texture != normal.texture and lit.texture != dis.texture and normal.texture != dis.texture,
		"按钮三态（已点亮/可购买/未解锁）贴图互不相同"
	)


# ---------------------------------------------------------------------------
# apply_button_state（灯塔树三态：贴图 + 该态专属字色）
# ---------------------------------------------------------------------------
func _test_button_state() -> void:
	# 先建好按钮再挂主题：apply_to 只遍历当时已存在的子节点
	var btn := Button.new()
	var btn2 := Button.new()
	var btn3 := Button.new()
	add_child(btn)
	add_child(btn2)
	add_child(btn3)
	_SKIN.apply_to(self)
	# 已点亮：绿色贴图 + 浅绿字（若只换贴图不换字色，会变成亮贴图配灰紫禁用字，比可购买态更难读）
	_assert(_SKIN.apply_button_state(btn, "btn_lit"), "apply_button_state(btn_lit) 返回 true")
	_assert(btn.get_theme_stylebox("normal") is StyleBoxTexture, "lit 态 normal 为贴图")
	_assert(btn.get_theme_stylebox("disabled") is StyleBoxTexture, "lit 态 disabled 为贴图")
	var lit_color: Color = btn.get_theme_color("font_disabled_color")
	_assert(lit_color == Color("#B4E8C4"), "lit 态 font_disabled_color 取自 config（#B4E8C4）")
	# 换成可购买态：贴图变，且该样式未定义 font_* 时不残留上一态的 override
	_assert(_SKIN.apply_button_state(btn2, "btn_normal"), "apply_button_state(btn_normal) 返回 true")
	_assert(btn2.get_theme_stylebox("normal") is StyleBoxTexture, "available 态 normal 为贴图")
	var theme_disabled: Color = _SKIN.get_theme().get_color("font_disabled_color", "Button")
	_assert(btn2.get_theme_color("font_disabled_color") == theme_disabled, "available 态不覆盖字色（沿用主题禁用色）")
	# 未知 style id 安全失败，不改动按钮
	_assert(not _SKIN.apply_button_state(btn3, "no_such_style"), "apply_button_state 未知 id 返回 false")
	_assert(btn3.get_theme_stylebox("normal") is StyleBoxTexture, "未知 id 时按钮样式未被改动（仍取主题默认）")
	_assert(not _SKIN.apply_button_state(null, "btn_lit"), "apply_button_state(null) 返回 false 不崩")
	btn.queue_free()
	btn2.queue_free()
	btn3.queue_free()


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _test_hud() -> void:
	GameState.start_new_run("watcher", 20260824)
	DifficultySystem.reset_tier()
	GameState.add_weapon("harpoon")
	var wm: WeaponManager = WEAPON_MANAGER.new()
	add_child(wm)
	var player_stub: Node2D = Node2D.new()
	add_child(player_stub)
	var hash_stub: SpatialHash = SPATIAL_HASH.new()
	var pool_stub: ProjectilePool = PROJECTILE_POOL.new()
	add_child(pool_stub)
	wm.setup(player_stub, hash_stub, pool_stub)
	wm.sync_from_game_state()
	var hud: Control = HUD_SCRIPT.new()
	add_child(hud)
	# 复刻实机接线：world.gd 在 _ready 里对自身调 apply_to，
	# 本测试根是 Node2D，HUD 作为其 Control 子节点即可吃到主题
	_SKIN.apply_to(self)
	hud.init(wm)
	hud.refresh()
	_assert(hud._hp_bar != null and hud._exp_bar != null, "HUD 进度条已创建")
	# 血条走主题默认 fill（bar_hp）
	var hp_fill: StyleBox = hud._hp_bar.get_theme_stylebox("fill")
	_assert(hp_fill is StyleBoxTexture, "HUD 血条填充为像素贴图")
	# 经验条显式 override 成 bar_exp（否则跟血条同红）
	var exp_fill: StyleBox = hud._exp_bar.get_theme_stylebox("fill")
	_assert(exp_fill is StyleBoxTexture, "HUD 经验条填充为像素贴图")
	var want_exp: StyleBoxTexture = _SKIN.stylebox("bar_exp")
	_assert(exp_fill == want_exp, "HUD 经验条用 bar_exp 贴图（与血条异色）")
	_assert(hp_fill != exp_fill, "HUD 血条/经验条填充不同")
	# 武器槽：截图反馈返工后无背景面板，仅图标+文字
	_assert(hud._weapon_box.get_child_count() >= 1, "HUD 武器槽存在")
	_assert(not (hud._weapon_box.get_child(0) is PanelContainer), "HUD 武器槽无背景面板")
	# 挣扎横幅（非模态，战斗中仍显示）：皮肤开启时用 panel_death 贴图
	_assert(hud._struggle_banner != null, "HUD 挣扎横幅已创建")
	var banner_sb: StyleBox = hud._struggle_banner.get_theme_stylebox("panel")
	_assert(banner_sb is StyleBoxTexture, "HUD 挣扎横幅为像素贴图")
	_assert(banner_sb == _SKIN.stylebox_with_margin("panel_death", 14.0), "挣扎横幅用 panel_death 样式")
	hud.queue_free()
	wm.queue_free()
	player_stub.queue_free()
	pool_stub.queue_free()
	# SpatialHash 是 RefCounted，随引用释放，无需 queue_free


# ---------------------------------------------------------------------------
# 关闭开关
# ---------------------------------------------------------------------------
func _test_disabled_fallback() -> void:
	var cfg: Dictionary = _SKIN.config()
	cfg["enabled"] = false
	_SKIN.reset_cache_for_test()
	UiChrome.reset_cache_for_test()
	_assert(not _SKIN.is_enabled(), "enabled=false 后 is_enabled() 为 false")
	_assert(_SKIN.stylebox("panel_dark") == null, "关闭后 stylebox() 返回 null")
	_assert(_SKIN.get_theme() == null, "关闭后不构建 Theme")
	var panel: StyleBox = UiChrome.panel_style()
	_assert(panel is StyleBoxFlat, "关闭后 UiChrome.panel_style 回退 StyleBoxFlat")
	var chip: StyleBox = UiChrome.chip_style()
	_assert(chip is StyleBoxFlat, "关闭后 UiChrome.chip_style 回退 StyleBoxFlat")
	var death: StyleBox = UiChrome.death_panel_style()
	_assert(death is StyleBoxFlat, "关闭后 death_panel_style 回退 StyleBoxFlat")
	var gold: StyleBox = UiChrome.gold_panel_style()
	_assert(gold is StyleBoxFlat, "关闭后 gold_panel_style 回退 StyleBoxFlat")
	# 关闭后挣扎横幅必须回到它原本的配色（0.80 alpha + 亮红边框），
	# 而不是套用结算页的 death_panel（0.92 + 粉红）——「关掉开关 = 回到原样」
	var banner: StyleBox = _SKIN.stylebox_with_margin("panel_death", 14.0)
	_assert(banner == null, "关闭后挣扎横幅取不到像素样式（调用方走就地扁平分支）")
	# apply_to 在关闭时不动主题
	var stage: Control = Control.new()
	add_child(stage)
	_SKIN.apply_to(stage)
	_assert(stage.theme == null, "关闭时 apply_to 不改动主题")
	stage.queue_free()
	# 恢复开关，确认可重新启用（配置热改场景）
	cfg["enabled"] = true
	_SKIN.reset_cache_for_test()
	UiChrome.reset_cache_for_test()
	_assert(_SKIN.is_enabled(), "恢复 enabled=true")
	_assert(_SKIN.stylebox("panel_dark") != null, "恢复后样式可重建")
	_assert(UiChrome.panel_style() is StyleBoxTexture, "恢复后 UiChrome 重新走像素皮肤")


## 静态缓存必须能被显式释放 —— 静态变量比引擎的纹理/RID 清理晚一步卸载，
## 不释放的话每个已加载的像素贴图都会在退出日志里报 "Texture ... leaked"
## （实测 world 路径漏 5 个、character_select 漏 7 个）。释放后还要能自愈重建。
func _test_release_cache() -> void:
	var cfg: Dictionary = _SKIN.config()
	cfg["enabled"] = true
	_SKIN.reset_cache_for_test()
	UiChrome.reset_cache_for_test()
	var theme_before: Theme = _SKIN.get_theme()
	_assert(theme_before != null, "释放前 Theme 已构建")
	var chip_before: StyleBox = _SKIN.stylebox("chip")
	_assert(chip_before is StyleBoxTexture, "释放前 chip 样式已缓存")
	# 释放（注意：get_theme() 本身会按需重建，不能拿它断言 null，
	#        要用「重建出的实例与释放前不同」来证明缓存确已清空）
	_SKIN.release_cache()
	var theme_after: Theme = _SKIN.get_theme()
	_assert(theme_after != null, "释放后 get_theme 能自愈重建")
	_assert(theme_after != theme_before, "重建得到新 Theme 实例（缓存确已清空）")
	var chip_after: StyleBox = _SKIN.stylebox("chip")
	_assert(chip_after is StyleBoxTexture, "释放后 stylebox 能自愈重建")
	_assert(chip_after != chip_before, "释放后样式为新实例（缓存确已清空）")
	# UiChrome.chip_style 的像素分支不再二次缓存 —— 否则贴图会被它单独握死
	var chip: StyleBox = UiChrome.chip_style()
	_assert(chip is StyleBoxTexture, "chip_style 释放后仍返回像素样式")
	_assert(UiChrome.chip_style() == chip, "chip_style 重复调用返回同一实例（由 PixelSkin 缓存）")
	# 幂等：连续释放不崩，之后仍能重建
	_SKIN.release_cache()
	_SKIN.release_cache()
	_assert(_SKIN.get_theme() != null, "release_cache 幂等（连续两次后仍可重建）")
	_SKIN.reset_cache_for_test()
	UiChrome.reset_cache_for_test()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
