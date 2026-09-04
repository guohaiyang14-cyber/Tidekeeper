# ============================================================================
# ExpTable — 经验表查询单例（autoload）
# 职责：从 config/exp_table.json 加载经验表，提供按等级查询
# 红线：经验表必须由 tools/generate_exp_table.py 生成（SKILL.md §4.3）
#       禁止手动修改 config/exp_table.json 任意一行
# 数据源：config/exp_table.json（预生成 1..table_max）
# 口径（GDD §6.2）：人物无等级硬顶；n ≥ table_max 时 E(n)=E(table_max)
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 ExpTable 访问

var _levels: Dictionary = {}
## 预生成表覆盖的最高等级；亦为 E(n) 曲线封顶点（非人物硬顶）
var _table_max_level: int = 30


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
	_table_max_level = int(data.get("metadata", {}).get("max_level", 30))
	print("[ExpTable] 经验表加载完成: 表内 %d 级 (table_max=%d；n≥该级 E 封顶，人物无硬顶)" % [
		_levels.size(), _table_max_level,
	])


## 查询在 level 级升到下一级所需经验 E(level)（§6.2 / §9.2）
## 玩家从 1 级开始：首次升级需 E(1)=22；n ≥ table_max 时返回 E(table_max)（可继续升级）
func get_exp(level: int) -> int:
	if level < 1:
		return 0
	var lookup: int = mini(level, _table_max_level)
	var entry: Dictionary = _levels.get(str(lookup), {})
	return int(entry.get("exp_required", 0))


## 累计：sum(E(1)..E(level))；表外按 E(table_max) 线性外推
func get_cumulative_exp(level: int) -> int:
	if level < 1:
		return 0
	if level <= _table_max_level:
		var entry: Dictionary = _levels.get(str(level), {})
		return int(entry.get("cumulative_exp", 0))
	var top: Dictionary = _levels.get(str(_table_max_level), {})
	var base_cum: int = int(top.get("cumulative_exp", 0))
	var plateau: int = get_exp(_table_max_level)
	return base_cum + plateau * (level - _table_max_level)


## 从 1 级 0 经验升到 target_level 所需总经验
func get_exp_to_reach(target_level: int) -> int:
	if target_level <= 1:
		return 0
	return get_cumulative_exp(target_level - 1)


## 根据累计获得经验反查当前等级（1 级起，无硬顶）
func get_level_from_exp(total_exp: int) -> int:
	var level: int = 1
	var spent: int = 0
	var guard: int = 0
	while guard < 100000:
		var need: int = get_exp(level)
		if need <= 0:
			break
		if spent + need <= total_exp:
			spent += need
			level += 1
			guard += 1
		else:
			break
	return level


## 曲线封顶点（= 预生成表顶）。人物可升超过此级，但 E(n) 不再升高。
## 兼容旧名；新代码请优先 get_table_max_level() / get_plateau_level()。
func get_max_level() -> int:
	return _table_max_level


## 预生成表最高等级（同 get_plateau_level）
func get_table_max_level() -> int:
	return _table_max_level


## E(n) 封顶点：n ≥ 此值时 E(n)=E(此值)；人物等级无硬顶
func get_plateau_level() -> int:
	return _table_max_level


## 人物是否有等级硬顶（当前设计：否）
func has_player_level_cap() -> bool:
	return false
