# ============================================================================
# DifficultySystem — W18 难度档位 + 教学宽容（autoload 单例）
# 职责：
#   - 持有当前难度档位（守夜人 0.7× / 灯塔 1.0×），开局前可选，运行时只读
#   - 暴露敌人 血量/伤害/数量 倍率 = 档位倍率 × 教学宽容倍率（按夜数）
#   - 教学夜（默认 1~4 夜）敌人数值减半 + Boss 提示开关
# 红线：数值全部来自 config/difficulty.json，运行时禁止硬编码（SKILL.md §4.2）
# 架构：与 ConfigLoader/GameState 同为 autoload 单例；不引用 enemy_base（避免环依赖）
# ============================================================================
extends Node

# 当前选中档位（lighthouse / watcher）
var _selected_tier: String = "lighthouse"
var _default_tier: String = "lighthouse"
var _tiers: Dictionary = {}
var _teaching: Dictionary = {}


func _ready() -> void:
	_load_from_config()
	_load_tier_from_settings()


func _load_from_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_difficulty_config()
	_tiers = cfg.get("tiers", {})
	_teaching = cfg.get("teaching", {})
	_default_tier = String(cfg.get("default_tier", "lighthouse"))
	if not _tiers.has(_default_tier):
		_default_tier = "lighthouse"
	_selected_tier = _default_tier


## 设置当前难度档位（忽略无效 id，保持现状并告警）；persist 写入 SaveSystem.settings
func set_tier(id: String, persist: bool = false) -> void:
	if _tiers.has(id):
		_selected_tier = id
		if persist:
			_save_tier_to_settings()
	else:
		push_warning("[DifficultySystem] 未知档位 %s，保持 %s" % [id, _selected_tier])


## 当前档位 id
func get_tier() -> String:
	return _selected_tier


## 当前档位显示名（优先 i18n，回退 config label）
func get_tier_label() -> String:
	var key: String = "difficulty.tier.%s" % _selected_tier
	var localized: String = LanguageSystem.localize(key)
	if localized != key:
		return localized
	var t: Dictionary = _tiers.get(_selected_tier, {})
	return String(t.get("label", _selected_tier))


## 恢复默认档位（诊断/重开前调用，避免跨局污染）
func reset_tier() -> void:
	_selected_tier = _default_tier


## 敌人血量倍率 = 档位 × 教学（夜 ≤ teaching.nights 减半）
func enemy_hp_multiplier(night: int) -> float:
	var tier: Dictionary = _tiers.get(_selected_tier, {})
	var m: float = float(tier.get("enemy_hp_mult", 1.0))
	return m * _teaching_hp_mult(night)


## 敌人伤害倍率 = 档位 × 教学
func enemy_damage_multiplier(night: int) -> float:
	var tier: Dictionary = _tiers.get(_selected_tier, {})
	var m: float = float(tier.get("enemy_dmg_mult", 1.0))
	return m * _teaching_dmg_mult(night)


## 刷怪数量倍率（守夜人 0.8×；灯塔 1.0×）
func enemy_count_multiplier() -> float:
	var tier: Dictionary = _tiers.get(_selected_tier, {})
	return float(tier.get("enemy_count_mult", 1.0))


## 是否教学夜（默认 1~4 夜）
func is_teaching_night(night: int) -> bool:
	return night <= int(_teaching.get("nights", 0))


## Boss 登场提示是否开启（教学夜 / 首次遭遇引导）
func boss_prompt_enabled() -> bool:
	return bool(_teaching.get("boss_prompt", false))


func _teaching_hp_mult(night: int) -> float:
	if is_teaching_night(night):
		return float(_teaching.get("enemy_hp_mult", 1.0))
	return 1.0


func _teaching_dmg_mult(night: int) -> float:
	if is_teaching_night(night):
		return float(_teaching.get("enemy_dmg_mult", 1.0))
	return 1.0


func _load_tier_from_settings() -> void:
	var saved: String = String(SaveSystem.get_settings().get("difficulty_tier", ""))
	if saved != "" and _tiers.has(saved):
		_selected_tier = saved
	else:
		_selected_tier = _default_tier


func _save_tier_to_settings() -> void:
	var settings: Dictionary = SaveSystem.get_settings()
	settings["difficulty_tier"] = _selected_tier
	SaveSystem.set_settings(settings)
