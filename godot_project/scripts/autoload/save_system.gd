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

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://savegame.json"

# 存档数据结构（对齐 README §1.5）
var _save_data: Dictionary = {
	"version": SAVE_VERSION,
	"saves": []
}


func _ready() -> void:
	load_save()
	print("[SaveSystem] 就绪（W1 骨架，完整实现在 W16）")


## 加载存档
func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveSystem] 无存档，使用默认数据")
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveSystem] 无法读取存档")
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[SaveSystem] 存档 JSON 解析失败")
		return false
	_save_data = parsed as Dictionary
	# 版本迁移（W16 实现）
	var file_version: int = int(_save_data.get("version", 1))
	if file_version < SAVE_VERSION:
		_migrate(file_version)
	print("[SaveSystem] 存档已加载: %d 个存档位" % _save_data.get("saves", []).size())
	return true


## 保存存档
func save_save() -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] 无法写入存档: %s" % SAVE_PATH)
		return false
	_save_data["version"] = SAVE_VERSION
	file.store_string(JSON.stringify(_save_data, "  "))
	file.close()
	return true


## 版本迁移（W16 实现）
func _migrate(from_version: int) -> void:
	print("[SaveSystem] 存档迁移: v%d → v%d（W16 实现完整迁移逻辑）" % [from_version, SAVE_VERSION])


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
