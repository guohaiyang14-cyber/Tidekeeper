# ============================================================================
# UiChrome — A6 轻量 UI 样式（静态工具，非 autoload）
# 职责：统一 Panel StyleBox / 边距 / 字号 / 按钮最小高度，供程序化 UI 复用。
# 皮肤：config/ui_skin.json 的 enabled=true 时，面板/芯片改用卡通像素风九宫格
#       贴图（PixelSkin），否则回退原 StyleBoxFlat 扁平样式。
# ============================================================================
class_name UiChrome
extends RefCounted

const _SKIN := preload("res://scripts/ui/pixel_skin.gd")

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0
const MARGIN: float = 12.0
const BTN_MIN_H: float = 40.0
const FONT_TITLE: int = 36
const FONT_BODY: int = 16
const FONT_CAPTION: int = 14
const PANEL_RADIUS: int = 10


## 像素皮肤下取九宫格样式；未启用或资源缺失返回 null（调用方回退扁平样式）
static func pixel_style(style_id: String, content_margin: float) -> StyleBox:
	if not _SKIN.is_enabled():
		return null
	return _SKIN.stylebox_with_margin(style_id, content_margin)


## 标准半透明面板样式
static func panel_style(
	bg: Color = Color(0.04, 0.06, 0.12, 0.92),
	border: Color = Color(0.45, 0.55, 0.75, 0.85),
	radius: int = PANEL_RADIUS,
	content_margin: float = MARGIN
) -> StyleBox:
	var px := pixel_style("panel_dark", content_margin)
	if px != null:
		return px
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.set_border_width_all(2)
	s.content_margin_left = content_margin
	s.content_margin_right = content_margin
	s.content_margin_top = content_margin
	s.content_margin_bottom = content_margin
	return s


## 强调色面板（事件卡）
static func accent_panel_style(
	bg: Color = Color(0.06, 0.08, 0.14, 0.94),
	border: Color = Color(0.55, 0.85, 0.75, 0.9)
) -> StyleBox:
	var px := pixel_style("panel_accent", MARGIN)
	if px != null:
		return px
	return panel_style(bg, border)


## 死因 / 挣扎横幅面板（偏暖）
static func death_panel_style() -> StyleBox:
	var px := pixel_style("panel_death", 14.0)
	if px != null:
		return px
	return panel_style(
		Color(0.10, 0.04, 0.06, 0.92),
		Color(0.85, 0.45, 0.50, 0.9),
		PANEL_RADIUS,
		14.0
	)


## 进化共鸣面板（金色；与事件卡的青色区分——共鸣是稀有庆祝感）
static func gold_panel_style() -> StyleBox:
	var px := pixel_style("panel_gold", MARGIN)
	if px != null:
		return px
	return panel_style(
		Color(0.10, 0.08, 0.04, 0.92),
		Color(0.95, 0.82, 0.40, 0.90)
	)


## 创建带样式的 Panel
static func make_panel(style: StyleBox = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style if style != null else panel_style())
	return p


## 统一按钮最小高度
static func style_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(0.0, BTN_MIN_H)


## 槽位芯片样式（HUD）。此处只缓存**扁平回退**样式：
## 像素分支交给 PixelSkin._style_cache 统一持有 —— 双份静态缓存会让贴图
## 在退出时无法释放（静态变量比引擎的纹理清理晚一步，会报 leaked）。
static var _chip_style_cached: StyleBox = null


static func chip_style() -> StyleBox:
	var px := pixel_style("chip", 6.0)
	if px != null:
		return px
	if _chip_style_cached != null:
		return _chip_style_cached
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.16, 0.85)
	s.border_color = Color(0.50, 0.65, 0.90, 0.75)
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	_chip_style_cached = s
	return _chip_style_cached


## 机检用：清空样式缓存（切换皮肤开关后需重建）
static func reset_cache_for_test() -> void:
	_chip_style_cached = null
