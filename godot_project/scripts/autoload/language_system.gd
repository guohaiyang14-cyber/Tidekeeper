# ============================================================================
# LanguageSystem — 双语切换（W19 i18n）
# 职责：加载 config/i18n.csv 翻译表，提供 localize(key) 取当前语言文案；
#       set_language 切换并持久化到 SaveSystem.settings.language。
# 设计：翻译表数据驱动（config/i18n.csv），新增语种只需扩表；
#       缺失 key 回退 zh，仍缺则回退 key 本身（不崩）。
# 红线：本单例只做翻译与语言偏好存储，不在此硬编码任何 UI 文案。
# ============================================================================
extends Node

signal language_changed(lang: String)

var _table: Dictionary = {}  # { lang: { key: text } }
var _lang: String = "zh"


func _ready() -> void:
	_load_csv()
	var settings: Dictionary = SaveSystem.get_settings()
	_lang = String(settings.get("language", "zh"))


func _csv_path() -> String:
	return ConfigLoader.config_dir + "i18n.csv"


func _load_csv() -> void:
	var path: String = _csv_path()
	if not FileAccess.file_exists(path):
		push_warning("[LanguageSystem] 缺失翻译表 %s" % path)
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[LanguageSystem] 无法打开 %s" % path)
		return
	var first_line: bool = true
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		if first_line:
			line = _strip_bom(line)
			first_line = false
			continue  # 跳过 header: key,zh,en
		var parts: PackedStringArray = _parse_csv_row(line)
		if parts.size() < 3:
			continue
		var key: String = parts[0].strip_edges()
		if key == "":
			continue
		if not _table.has("zh"):
			_table["zh"] = {}
		if not _table.has("en"):
			_table["en"] = {}
		_table["zh"][key] = parts[1]
		_table["en"][key] = parts[2]
	f.close()
	print("[LanguageSystem] 翻译表加载 %d 条" % _table.get("zh", {}).size())


## 取 key 在当前语言下的文案；lang 可临时指定（勿命名为 tr，与 Object.tr 冲突）
func localize(key: String, lang: String = "") -> String:
	var l: String = lang if lang != "" else _lang
	if _table.has(l) and _table[l].has(key):
		return _table[l][key]
	if _table.has("zh") and _table["zh"].has(key):
		return _table["zh"][key]
	return key


## 配置实体显示名（weapon/enemy/boss/passive/character.{id}.name）；缺 key 回退 fallback
func localize_config_name(category: String, id: String, fallback: String) -> String:
	var key: String = "%s.%s.name" % [category, id]
	var text: String = localize(key)
	return text if text != key else fallback


## 配置实体描述（character.{id}.desc）；缺 key 回退 fallback
func localize_config_desc(category: String, id: String, fallback: String) -> String:
	var key: String = "%s.%s.desc" % [category, id]
	var text: String = localize(key)
	return text if text != key else fallback


## 格式化文案：先 localize 再 % 占位符（args 为 Array）；占位符数量不匹配时告警并回退 fmt
func localizef(key: String, args: Array = [], lang: String = "") -> String:
	var fmt: String = localize(key, lang)
	if args.is_empty():
		return fmt
	var need: int = _format_arg_count(fmt)
	if need != args.size():
		push_warning("[LanguageSystem] localizef(%s) placeholders=%d args=%d" % [key, need, args.size()])
		return fmt
	return fmt % args


func get_language() -> String:
	return _lang


func set_language(l: String) -> void:
	if l != "zh" and l != "en":
		return
	if l == _lang:
		return
	_lang = l
	var settings: Dictionary = SaveSystem.get_settings()
	settings["language"] = l
	SaveSystem.set_settings(settings)
	language_changed.emit(l)


func _strip_bom(line: String) -> String:
	if line.length() > 0 and line[0] == "\ufeff":
		return line.substr(1)
	return line


## 解析 CSV 行（支持引号包裹字段与 "" 转义）
func _parse_csv_row(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var field: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if in_quotes:
			if c == '"':
				if i + 1 < line.length() and line[i + 1] == '"':
					field += '"'
					i += 2
					continue
				in_quotes = false
			else:
				field += c
		elif c == '"':
			in_quotes = true
		elif c == ',':
			out.append(field)
			field = ""
		else:
			field += c
		i += 1
	out.append(field)
	return out


## 统计 fmt 中 printf 占位符数量（忽略 %%；支持 %d / %.1f / %02d 等宽度精度）
func _format_arg_count(fmt: String) -> int:
	var count: int = 0
	var i: int = 0
	var n: int = fmt.length()
	while i < n:
		if fmt[i] != "%":
			i += 1
			continue
		if i + 1 >= n:
			break
		if fmt[i + 1] == "%":
			i += 2
			continue
		i += 1
		while i < n and fmt[i] in ["-", "+", " ", "#", "0"]:
			i += 1
		while i < n and fmt[i] >= "0" and fmt[i] <= "9":
			i += 1
		if i < n and fmt[i] == ".":
			i += 1
			while i < n and fmt[i] >= "0" and fmt[i] <= "9":
				i += 1
		if i < n and fmt[i] in ["d", "s", "f", "x", "X", "o"]:
			count += 1
			i += 1
	return count
