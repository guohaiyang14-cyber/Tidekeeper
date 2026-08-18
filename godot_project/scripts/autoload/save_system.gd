# ============================================================================
# SaveSystem — 存档系统（autoload 单例）
# 职责：JSON 存档（Steam 云同步）— 解锁、灯塔等级、星尘、设置
# 数据源：README §1.5 存档格式
# MVP 范围：本地存档（W16 实现）；云同步为封测
# 注意：本文件为 W1 骨架，完整实现在 W16
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 SaveSystem 访问

const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://savegame.json"
const TEST_SAVE_PATH: String = "user://savegame_test.json"

# 当前读写路径（机检切到 TEST_SAVE_PATH，避免清空/写坏试玩档）
var _save_path: String = SAVE_PATH

# 存档数据结构（对齐 README §1.5 + W16 局外进度）
var _save_data: Dictionary = {
	"version": SAVE_VERSION,
	"saves": [],
	"meta": _default_meta()
}


## 局外进度默认结构（解锁 / 灯塔等级 / 星尘 / 统计 / 首通）
func _default_meta() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"total_runs": 0,
		"max_night_cleared": 0,
		"stardust": 0,
		"first_clear": false,
		"unlocks": [],
		"lighthouse": {}
	}


func _ready() -> void:
	if _is_test_scene():
		isolate_for_tests()
	else:
		load_save()
	print("[SaveSystem] 就绪（v%d，path=%s）" % [SAVE_VERSION, _save_path])


## 机检：改写独立路径并丢弃内存中的试玩档（不写 production）
func isolate_for_tests() -> void:
	_save_path = TEST_SAVE_PATH
	_save_data = {
		"version": SAVE_VERSION,
		"saves": [],
		"meta": _default_meta()
	}
	print("[SaveSystem] 已隔离到测试存档 %s" % _save_path)


## 当前命令行是否在跑 scenes/tests 机检
func _is_test_scene() -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("res://scenes/tests/"):
			return true
	return false


## 加载存档
func load_save() -> bool:
	if not FileAccess.file_exists(_save_path):
		print("[SaveSystem] 无存档，使用默认数据")
		return false
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		push_error("[SaveSystem] 无法读取存档")
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[SaveSystem] 存档 JSON 解析失败，已改名备份")
		_quarantine_corrupt_save()
		_save_data = {
			"version": SAVE_VERSION,
			"saves": [],
			"meta": _default_meta()
		}
		return false
	_save_data = parsed as Dictionary
	# 版本迁移（W16 实现）
	var file_version: int = int(_save_data.get("version", 1))
	if file_version < SAVE_VERSION:
		_migrate(file_version)
	# 兼容旧档：确保 meta 字段存在
	_ensure_meta()
	print("[SaveSystem] 存档已加载: %d 个存档位 | 星尘 %d" % [
		_save_data.get("saves", []).size(), get_save_meta().get("stardust", 0),
	])
	return true


## 损坏存档改名为 .bak，避免下次启动仍读半截文件
func _quarantine_corrupt_save() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	var src: String = _save_path.get_file()
	var bak: String = src + ".bak"
	if not dir.file_exists(src):
		return
	if dir.file_exists(bak):
		dir.remove(bak)
	dir.rename(src, bak)


## 保存存档（先写 .tmp 再替换，避免并行/中断留下半截 JSON）
func save_save() -> bool:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("[SaveSystem] 无法打开 user://")
		return false
	var dest_name: String = _save_path.get_file()
	var tmp_name: String = dest_name + ".tmp"
	var tmp_path: String = "user://" + tmp_name
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] 无法写入存档: %s" % tmp_path)
		return false
	_save_data["version"] = SAVE_VERSION
	file.store_string(JSON.stringify(_save_data, "  "))
	file.close()
	if dir.file_exists(dest_name):
		dir.remove(dest_name)
	var err: Error = dir.rename(tmp_name, dest_name)
	if err != OK:
		push_error("[SaveSystem] 无法替换存档: %s error=%d" % [dest_name, err])
		return false
	return true


## 版本迁移（W16：v1 → v2 增加 meta 局外进度字段）
func _migrate(from_version: int) -> void:
	print("[SaveSystem] 存档迁移: v%d → v%d" % [from_version, SAVE_VERSION])
	# v1 存档无 meta 字段，_ensure_meta 会补齐默认结构
	_ensure_meta()
	_save_data["version"] = SAVE_VERSION


## 确保 meta 字段存在（旧档兼容）
func _ensure_meta() -> void:
	if not _save_data.has("meta") or not (_save_data["meta"] is Dictionary):
		_save_data["meta"] = _default_meta()
		return
	# 补齐缺失子键，避免旧档缺字段报错
	var m: Dictionary = _save_data["meta"]
	for key in _default_meta().keys():
		if not m.has(key):
			m[key] = _default_meta()[key]


## 获取局外进度（返回实时引用，调用方修改后需 set_save_meta 落盘）
## 注：方法名避开 Object.get_meta 内置（Godot 保留）
func get_save_meta() -> Dictionary:
	_ensure_meta()
	return _save_data["meta"]


## 写入并持久化局外进度
func set_save_meta(m: Dictionary) -> void:
	_save_data["meta"] = m
	save_save()


## 重置局外进度（测试 / 调试用）
func reset_save_meta() -> void:
	_save_data["meta"] = _default_meta()
	save_save()


## 获取所有存档位
func get_saves() -> Array:
	return _save_data.get("saves", [])


## 获取指定存档
func get_save(index: int) -> Dictionary:
	var saves: Array = _save_data.get("saves", [])
	if index < 0 or index >= saves.size():
		return {}
	return saves[index]


## 添加/更新存档
func upsert_save(save_entry: Dictionary) -> void:
	var saves: Array = _save_data.get("saves", [])
	# 简化：按 character 匹配替换（W16 完善）
	var found: bool = false
	for i in saves.size():
		if saves[i].get("character") == save_entry.get("character"):
			saves[i] = save_entry
			found = true
			break
	if not found:
		saves.append(save_entry)
	_save_data["saves"] = saves
	save_save()


## 获取设置
func get_settings() -> Dictionary:
	return _save_data.get("settings", {"language": "zh", "volume": 0.8})


## 更新设置
func set_settings(settings: Dictionary) -> void:
	_save_data["settings"] = settings
	save_save()
