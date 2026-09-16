# ============================================================================
# UiChrome — A6 轻量 UI 样式（静态工具，非 autoload）
# 职责：统一 Panel StyleBoxFlat / 边距 / 字号 / 按钮最小高度，供程序化 UI 复用。
# ============================================================================
class_name UiChrome
extends RefCounted

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0
const MARGIN: float = 12.0
const BTN_MIN_H: float = 40.0
const FONT_TITLE: int = 36
const FONT_BODY: int = 16
const FONT_CAPTION: int = 14
const PANEL_RADIUS: int = 10


## 标准半透明面板样式
static func panel_style(
	bg: Color = Color(0.04, 0.06, 0.12, 0.92),
	border: Color = Color(0.45, 0.55, 0.75, 0.85),
	radius: int = PANEL_RADIUS,
	content_margin: float = MARGIN
) -> StyleBoxFlat:
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


## 强调色面板（事件卡 / 死因）
static func accent_panel_style(
	bg: Color = Color(0.06, 0.08, 0.14, 0.94),
	border: Color = Color(0.55, 0.85, 0.75, 0.9)
) -> StyleBoxFlat:
	return panel_style(bg, border)


## 死因面板（偏暖）
static func death_panel_style() -> StyleBoxFlat:
	return panel_style(
		Color(0.10, 0.04, 0.06, 0.92),
		Color(0.85, 0.45, 0.50, 0.9),
		PANEL_RADIUS,
		14.0
	)


## 创建带样式的 Panel
static func make_panel(style: StyleBoxFlat = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style if style != null else panel_style())
	return p


## 统一按钮最小高度
static func style_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(0.0, BTN_MIN_H)


## 槽位芯片样式（HUD）；缓存单例，勿在业务侧就地改颜色
static var _chip_style_cached: StyleBoxFlat = null


static func chip_style() -> StyleBoxFlat:
	if _chip_style_cached == null:
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
