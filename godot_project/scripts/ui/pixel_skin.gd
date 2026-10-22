# ============================================================================
# PixelSkin — 卡通像素风 UI 皮肤（静态工具，非 autoload）
# 职责：按 config/ui_skin.json 构建 Theme（九宫格 StyleBoxTexture + 字色），
#       挂到根 Window 上，让全部 Control 自动继承，无需逐个改按钮。
# 数据源：config/ui_skin.json（边距 / 贴图 / 主题映射）；贴图 assets/ui/pixel/
# 资源加载：ResourceLoader 优先（导出包内只有导入产物），干净检出回退
#           Image.load_from_file()（绕过 .import 直接读 PNG）
# 红线：本文件只读配置，不写任何数值；关闭开关（enabled=false）即回到原扁平样式
# ============================================================================
extends RefCounted

const _DEFAULT_DIR: String = "res://assets/ui/pixel/"
const _STRETCH_STRETCH: int = 0
const _STRETCH_TILE: int = 1

static var _theme: Theme = null
static var _tex_cache: Dictionary = {}
static var _style_cache: Dictionary = {}


func _init() -> void:
	return  # 静态工具类，禁止实例化（调用静态方法即可）


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
static func config() -> Dictionary:
	return ConfigLoader.get_ui_skin_config()


static func is_enabled() -> bool:
	var cfg: Dictionary = config()
	if cfg.is_empty():
		return false
	return bool(cfg.get("enabled", false))


# ---------------------------------------------------------------------------
# 应用
# ---------------------------------------------------------------------------
## 给子树里「最上层的 Control」挂主题，其下全部子控件自动继承。
## 注意：不能挂到根 Window —— 本工程 UI 挂在 $UI(CanvasLayer) → HUD，
## 而 CanvasLayer / Node2D 会**截断**主题继承链，Window 上的主题到不了局内 UI。
## 实测父链：ProgressBar → HUD(Control) → UI(CanvasLayer) → Main(Node2D) → root(Window)
static func apply_to(node: Node) -> void:
	if node == null or not is_enabled():
		return
	var theme := get_theme()
	if theme == null:
		return
	if node is Control and not (node.get_parent() is Control):
		var self_ctrl := node as Control
		if self_ctrl.theme != theme:
			self_ctrl.theme = theme
	_walk_apply(node, theme)


static func _walk_apply(node: Node, theme: Theme) -> void:
	for child in node.get_children():
		if child is Control and not (child.get_parent() is Control):
			var ctrl := child as Control
			if ctrl.theme != theme:
				ctrl.theme = theme
		# 递归：子树里可能还有 CanvasLayer（如 EvolutionEffectUI）另起一段继承链
		_walk_apply(child, theme)


static func build_theme() -> Theme:
	var cfg: Dictionary = config()
	var t := Theme.new()
	var mapping: Dictionary = cfg.get("theme", {}) if cfg.get("theme") is Dictionary else {}
	for type_name in mapping.keys():
		var slots: Variant = mapping[type_name]
		if not (slots is Dictionary):
			continue
		for slot_name in (slots as Dictionary).keys():
			var sb: StyleBoxTexture = stylebox(String((slots as Dictionary)[slot_name]))
			if sb != null:
				t.set_stylebox(String(slot_name), String(type_name), sb)
	# 字色（可选；缺省沿用项目原有 add_theme_color_override）
	var colors: Variant = cfg.get("font_colors", {})
	if colors is Dictionary:
		for type_name in (colors as Dictionary).keys():
			var entries: Variant = (colors as Dictionary)[type_name]
			if not (entries is Dictionary):
				continue
			for slot_name in (entries as Dictionary).keys():
				t.set_color(
					String(slot_name), String(type_name), _parse_color(String((entries as Dictionary)[slot_name]))
				)
	return t


static func get_theme() -> Theme:
	if _theme == null and is_enabled():
		_theme = build_theme()
	return _theme


# ---------------------------------------------------------------------------
# 样式
# ---------------------------------------------------------------------------
## 按 config 的 styles 表构建九宫格样式（带缓存）
## 注意：必须在这里检查开关 —— hud.gd / lighthouse_tree.gd 会直接调用本方法，
##       若只靠 UiChrome.pixel_style() 把关，关闭皮肤后这些控件仍会拿到像素贴图。
static func stylebox(style_id: String) -> StyleBoxTexture:
	if not is_enabled():
		return null
	if _style_cache.has(style_id):
		return _style_cache[style_id] as StyleBoxTexture
	var cfg: Dictionary = config()
	var defs: Variant = cfg.get("styles", {})
	if not (defs is Dictionary):
		return null
	var d: Variant = (defs as Dictionary).get(style_id, null)
	if not (d is Dictionary):
		return null
	var def: Dictionary = d as Dictionary
	var tex: Texture2D = texture(String(def.get("texture", "")))
	if tex == null:
		push_warning("[PixelSkin] 贴图缺失，样式跳过: %s" % style_id)
		return null
	var patches: Variant = cfg.get("nine_patch", {})
	var patch_key: String = String(def.get("patch", "panel"))
	var margin: int = 0
	if patches is Dictionary:
		margin = int((patches as Dictionary).get(patch_key, 0))
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(margin)
	sb.texture_margin_top = float(margin)
	sb.texture_margin_right = float(margin)
	sb.texture_margin_bottom = float(margin)
	# 进度条中段平铺（保留像素块感）；面板/按钮默认拉伸
	var stretch: int = _STRETCH_TILE if String(def.get("stretch", "stretch")) == "tile" else _STRETCH_STRETCH
	sb.axis_stretch_horizontal = stretch
	sb.axis_stretch_vertical = _STRETCH_STRETCH
	var cm: float = float(def.get("content_margin", 0.0))
	if cm > 0.0:
		sb.content_margin_left = cm
		sb.content_margin_right = cm
		sb.content_margin_top = cm
		sb.content_margin_bottom = cm
	_style_cache[style_id] = sb
	return sb


## 同一贴图 + 不同内容边距（UiChrome 的面板各自带内边距）
static func stylebox_with_margin(style_id: String, content_margin: float) -> StyleBoxTexture:
	var key: String = "%s@%.1f" % [style_id, content_margin]
	if _style_cache.has(key):
		return _style_cache[key] as StyleBoxTexture
	var base: StyleBoxTexture = stylebox(style_id)
	if base == null:
		return null
	var sb: StyleBoxTexture = base.duplicate() as StyleBoxTexture
	sb.content_margin_left = content_margin
	sb.content_margin_right = content_margin
	sb.content_margin_top = content_margin
	sb.content_margin_bottom = content_margin
	_style_cache[key] = sb
	return sb


## 给按钮套一个「状态样式」：贴图 + 该状态专属字色（字色也来自 config，不硬编码）。
## 用途：灯塔树已点亮/可购买/未解锁三态。已点亮按钮 disabled=true，
## 文字取的是 font_disabled_color —— 若只换贴图不换字色，会变成「亮贴图 + 灰紫字」，
## 比可购买态更难读，语义倒挂。故把字色一并放进 styles 定义里。
static func apply_button_state(btn: Button, style_id: String) -> bool:
	if btn == null:
		return false
	var sb: StyleBoxTexture = stylebox(style_id)
	if sb == null:
		return false
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	var cfg: Dictionary = config()
	var defs: Variant = cfg.get("styles", {})
	if defs is Dictionary:
		var d: Variant = (defs as Dictionary).get(style_id, null)
		if d is Dictionary:
			var def: Dictionary = d as Dictionary
			for slot in def.keys():
				var slot_name: String = String(slot)
				if not slot_name.begins_with("font_"):
					continue
				btn.add_theme_color_override(slot_name, _parse_color(String(def[slot])))
	return true


# ---------------------------------------------------------------------------
# 贴图
# ---------------------------------------------------------------------------
## 双路径加载：ResourceLoader（导出包可用）→ Image.load_from_file（干净检出兜底）
static func texture(filename: String) -> Texture2D:
	if filename == "":
		return null
	if _tex_cache.has(filename):
		return _tex_cache[filename] as Texture2D
	var cfg: Dictionary = config()
	var dir: String = String(cfg.get("asset_dir", _DEFAULT_DIR))
	if dir != "" and not dir.ends_with("/"):
		dir += "/"
	var path: String = filename if filename.begins_with("res://") else dir + filename
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	if tex == null:
		# Image.load_from_file 是静态方法，失败返回 null（不是实例方法返回 Error）
		var img: Image = Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("[PixelSkin] 贴图加载失败: %s" % path)
		return null
	_tex_cache[filename] = tex
	return tex


## 释放静态缓存。
## 必须由顶层场景在 _exit_tree() 调用：静态变量要等脚本卸载才释放，
## 而引擎的纹理/RID 清理发生在退出流程更早的阶段 —— 不清的话每个已加载
## 的像素贴图都会在退出日志里报 "Texture ... leaked"（实测 7 个）。
## 清空后若仍在使用，apply_to() 会自动重建（get_theme() 里 _theme == null 分支）。
static func release_cache() -> void:
	_theme = null
	_tex_cache.clear()
	_style_cache.clear()


## 机检用：清空缓存（模拟首次加载 / 配置变更后重建）
static func reset_cache_for_test() -> void:
	release_cache()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
static func _parse_color(text: String) -> Color:
	if text == "" or not Color.html_is_valid(text):
		return Color.WHITE
	return Color.html(text)
