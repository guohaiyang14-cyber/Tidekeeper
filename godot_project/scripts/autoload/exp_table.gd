# ============================================================================
# ExpTable — 经验表查询单例（autoload）
# 职责：从 config/exp_table.json 加载经验表，提供按等级查询
# 红线：经验表必须由 tools/generate_exp_table.py 生成（SKILL.md §4.3）
#       禁止手动修改 config/exp_table.json 任意一行
# 数据源：config/exp_table.json（30 级，n≥30 取 E(30)）
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 ExpTable 访问

var _levels: Dictionary = {}
var _max_level: int = 30


func _ready() -> void:
	_load_table()


## 从 config/exp_table.json 加载经验表
func _load_table() -> void:
	var path: String = ConfigLoader.config_dir + "exp_table.json"
	if not FileAccess.file_exists(path):
		push_error("[ExpTable] 经验表缺失: %s — 请先运行 python tools/generate_exp_table.py" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[ExpTable] 无法打开经验表: %s" % path)
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[ExpTable] 经验表 JSON 解析失败")
		return
	var data: Dictionary = parsed as Dictionary
	_levels = data.get("levels", {})
	_max_level = int(data.get("metadata", {}).get("max_level", 30))
	print("[ExpTable] 经验表加载完成: %d 级 (max_level=%d)" % [_levels.size(), _max_level])


## 查询升到 level 级所需经验（n≥30 取 E(30)）
func get_exp(level: int) -> int:
	if level <= 1:
		return 0
	var clamped: int = mini(level, _max_level)
	var entry: Dictionary = _levels.get(str(clamped), {})
	return int(entry.get("exp_required", 0))


## 查询升到 level 级的累计经验
func get_cumulative_exp(level: int) -> int:
	var clamped: int = mini(level, _max_level)
	var entry: Dictionary = _levels.get(str(clamped), {})
	return int(entry.get("cumulative_exp", 0))


## 根据当前累计经验反查等级
func get_level_from_exp(cumulative_exp: int) -> int:
	var level: int = 1
	for i in range(1, _max_level + 1):
		if get_cumulative_exp(i) <= cumulative_exp:
			level = i
		else:
			break
	return level


## 最大等级上限
func get_max_level() -> int:
	return _max_level
