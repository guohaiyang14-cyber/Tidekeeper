# ============================================================================
# W18DifficultyTest — W18 难度系统 逻辑机检（headless）
# 验收项（数据驱动 config/difficulty.json）：
#   W18-1 配置加载（档位 守夜人0.7× / 灯塔1.0× + 教学宽容 齐全）
#   W18-2 默认档位 = 灯塔（1.0× 血量/伤害/数量）
#   W18-3 切换档位 = 守夜人（0.7× 血量/伤害 / 0.8× 数量）
#   W18-4 教学夜（1~4 夜减半；夜5 起不减半；档位×教学叠加）
#   W18-5 enemy_base.configure 实际施加倍率（灯塔/守夜人/教学夜 三种口径）
#   W18-6 Boss 登场提示（教学宽容开启）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w18_difficulty_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

var _passed: int = 0
var _failed: int = 0
var _fail_msgs: Array[String] = []


func _ready() -> void:
	if not ConfigLoader.is_loaded:
		push_error("[W18DifficultyTest] ConfigLoader 未加载")
		get_tree().quit(1)
		return
	print("============================================================")
	print("W18 难度系统 机检")
	print("============================================================")
	_test_config_loaded()
	_test_default_tier()
	_test_watcher_tier()
	_test_teaching_night()
	_test_configure_scaling()
	_test_boss_prompt()
	_test_tier_persistence()
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("失败项: " + ", ".join(_fail_msgs))
	print("============================================================")
	# 收尾：恢复默认档位，避免跨进程污染（每场景独立进程，防御性）
	DifficultySystem.reset_tier()
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		_fail_msgs.append(label)
		print("  [FAIL] %s" % label)


# ============================================================================
# W18-1 配置加载
# ============================================================================
func _test_config_loaded() -> void:
	var cfg: Dictionary = ConfigLoader.get_difficulty_config()
	_assert(not cfg.is_empty(), "difficulty.json 已加载")
	var tiers: Dictionary = cfg.get("tiers", {})
	_assert(tiers.has("lighthouse"), "含 灯塔 档位")
	_assert(tiers.has("watcher"), "含 守夜人 档位")
	_assert(cfg.get("default_tier", "") == "lighthouse", "默认档位=灯塔")
	_assert(cfg.has("teaching"), "含 教学宽容 配置")


# ============================================================================
# W18-2 默认档位
# ============================================================================
func _test_default_tier() -> void:
	_assert(DifficultySystem.get_tier() == "lighthouse", "当前档位=灯塔")
	_assert(abs(DifficultySystem.enemy_hp_multiplier(10) - 1.0) < 1e-6, "灯塔 血量倍率=1.0@夜10")
	_assert(abs(DifficultySystem.enemy_damage_multiplier(10) - 1.0) < 1e-6, "灯塔 伤害倍率=1.0@夜10")
	_assert(abs(DifficultySystem.enemy_count_multiplier() - 1.0) < 1e-6, "灯塔 数量倍率=1.0")


# ============================================================================
# W18-3 切换档位 = 守夜人
# ============================================================================
func _test_watcher_tier() -> void:
	DifficultySystem.set_tier("watcher")
	_assert(DifficultySystem.get_tier() == "watcher", "切换=守夜人")
	_assert(abs(DifficultySystem.enemy_hp_multiplier(10) - 0.7) < 1e-6, "守夜人 血量倍率=0.7@夜10")
	_assert(abs(DifficultySystem.enemy_damage_multiplier(10) - 0.7) < 1e-6, "守夜人 伤害倍率=0.7@夜10")
	_assert(abs(DifficultySystem.enemy_count_multiplier() - 0.8) < 1e-6, "守夜人 数量倍率=0.8")
	# 无效档位应被忽略
	DifficultySystem.set_tier("nonexistent")
	_assert(DifficultySystem.get_tier() == "watcher", "无效档位被忽略，保持守夜人")
	DifficultySystem.reset_tier()


# ============================================================================
# W18-4 教学夜（1~4 夜减半）
# ============================================================================
func _test_teaching_night() -> void:
	_assert(DifficultySystem.is_teaching_night(4), "夜4=教学夜")
	_assert(not DifficultySystem.is_teaching_night(5), "夜5=非教学夜")
	# 灯塔 + 教学夜 2 → 0.6
	_assert(abs(DifficultySystem.enemy_hp_multiplier(2) - 0.6) < 1e-6, "灯塔 教学夜 血量倍率=0.6")
	_assert(abs(DifficultySystem.enemy_damage_multiplier(2) - 0.6) < 1e-6, "灯塔 教学夜 伤害倍率=0.6")
	# 守夜人 + 教学夜 2 → 0.7 × 0.6 = 0.42
	DifficultySystem.set_tier("watcher")
	_assert(abs(DifficultySystem.enemy_hp_multiplier(2) - 0.42) < 1e-6, "守夜人 教学夜 血量倍率=0.42")
	_assert(abs(DifficultySystem.enemy_damage_multiplier(2) - 0.42) < 1e-6, "守夜人 教学夜 伤害倍率=0.42")
	DifficultySystem.reset_tier()


# ============================================================================
# W18-5 enemy_base.configure 实际施加倍率
# ============================================================================
func _test_configure_scaling() -> void:
	var def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	_assert(not def.is_empty(), "存在 small_goblin 配置")
	var base_hp: float = float(def.get("base_health", 30))
	var dcfg: Dictionary = ConfigLoader.get_enemy_difficulty()
	var region_coeff: float = float(dcfg.get("region_coeff", 1.0))
	var hp_per_night: float = float(dcfg.get("health_per_night", 0.10))
	var hp_per_5: float = float(dcfg.get("health_per_5nights", 0.15))

	# 灯塔 夜10（非教学）：base × region × 1.0 × (1 + hp_per_night*10) × (1 + hp_per_5*2)
	var e_l: EnemyBase = EnemyBase.new()
	e_l.configure(def, 10)
	var expect_l: int = int(roundi(base_hp * region_coeff * 1.0 * (1.0 + hp_per_night * 10.0) * (1.0 + hp_per_5 * floor(10.0 / 5.0))))
	_assert(e_l.max_health == expect_l, "灯塔 夜10 血量=%d (期望 %d)" % [e_l.max_health, expect_l])
	e_l.free()

	# 守夜人 夜10：× 0.7
	DifficultySystem.set_tier("watcher")
	var e_w: EnemyBase = EnemyBase.new()
	e_w.configure(def, 10)
	var expect_w: int = int(roundi(base_hp * region_coeff * 0.7 * (1.0 + hp_per_night * 10.0) * (1.0 + hp_per_5 * floor(10.0 / 5.0))))
	_assert(e_w.max_health == expect_w, "守夜人 夜10 血量=%d (期望 %d)" % [e_w.max_health, expect_w])
	e_w.free()

	# 守夜人 教学夜2：× 0.7 × 0.6
	var e_t: EnemyBase = EnemyBase.new()
	e_t.configure(def, 2)
	var expect_t: int = int(roundi(base_hp * region_coeff * 0.7 * 0.6 * (1.0 + hp_per_night * 2.0) * (1.0 + hp_per_5 * floor(2.0 / 5.0))))
	_assert(e_t.max_health == expect_t, "守夜人 教学夜2 血量=%d (期望 %d)" % [e_t.max_health, expect_t])
	e_t.free()
	DifficultySystem.reset_tier()


# ============================================================================
# W18-6 Boss 登场提示
# ============================================================================
func _test_boss_prompt() -> void:
	_assert(DifficultySystem.boss_prompt_enabled(), "Boss 提示开启（教学宽容）")


# ============================================================================
# W18-7 档位持久化（SaveSystem.settings.difficulty_tier）
# ============================================================================
func _test_tier_persistence() -> void:
	DifficultySystem.set_tier("watcher", true)
	_assert(SaveSystem.get_settings().get("difficulty_tier") == "watcher", "档位持久化=watcher")
	DifficultySystem.set_tier("lighthouse", true)
	_assert(SaveSystem.get_settings().get("difficulty_tier") == "lighthouse", "档位持久化=灯塔")
