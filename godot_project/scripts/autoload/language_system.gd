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
	var header: PackedStringArray = f.get_line().split(",")
	# header: [key, zh, en, ...]；仅取第 2、3 列（zh/en）
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		var parts: PackedStringArray = line.split(",")
		if parts.size() < 3:
			continue
		var key: String = parts[0]
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
