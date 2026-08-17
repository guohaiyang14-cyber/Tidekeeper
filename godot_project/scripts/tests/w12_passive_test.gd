# ============================================================================
# W12PassiveTest — 被动系统（通用效果桶）机检
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w12_passive_test.tscn
# 覆盖：12 被动配置（4 通用+8 钥，含 effect 桶）、PassiveSystem 聚合倍率、
#       伤害/攻速/拾取半径/减伤/经验 乘区生效、暴击/范围/CD 消费侧、
#       被动槽上限6+等级5+移除返还
# ============================================================================
extends Node

const _PLAYER = preload("res://scripts/player/player.gd")
const _WEAPON_HARPOON = preload("res://scripts/combat/weapon_harpoon.gd")

var _passed: int = 0
var _failed: int = 0
var _last_exp: int = 0


func _ready() -> void:
	RNG.set_seed(20261212)
	if not GameState.exp_gained.is_connected(_on_exp):
		GameState.exp_gained.connect(_on_exp)
	print("============================================================")
	print("W12 被动系统（通用效果桶）机检")
	print("============================================================")
	_test_config()
	_test_aggregate()
	_test_damage_applies()
	_test_attack_speed()
	_test_pickup_radius()
	_test_damage_reduction()
	_test_exp_mult()
	_test_area_crit_cd()
	_test_slot_cap()
	_test_level_cap()
	_test_remove_frees()
	print("------------------------------------------------------------")
	print("W12 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _on_exp(amount: int, _total: int) -> void:
	_last_exp = amount


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _reset_run() -> void:
	GameState.start_new_run("watcher", 20261212)


func _own_to_level(pid: String, lvl: int) -> void:
	GameState.add_passive(pid)
	while GameState.get_passive_level(pid) < lvl:
		if not GameState.add_passive(pid):
			break


# ---------------------------------------------------------------------------
func _test_config() -> void:
	print("[配置]")
	var ids: Array = ConfigLoader.get_all_passive_ids()
	_assert(ids.size() == 12, "被动共 12（4 通用 + 8 钥）")
	var gen: int = 0
	var key: int = 0
	for pid_v in ids:
		var pid: String = String(pid_v)
		var p: Dictionary = ConfigLoader.get_passive(pid)
		_assert(not p.is_empty(), "%s 被动存在" % pid)
		var eff: Dictionary = p.get("effect", {})
		_assert(not eff.is_empty(), "%s 含 effect 桶" % pid)
		if str(p.get("category")) == "通用被动":
			gen += 1
		elif str(p.get("category")) == "进化钥被动":
			key += 1
	_assert(gen == 4, "通用被动 = 4")
	_assert(key == 8, "进化钥被动 = 8")


func _test_aggregate() -> void:
	print("[PassiveSystem 聚合倍率]")
	_reset_run()
	GameState.add_passive("pearl")
	_assert(abs(PassiveSystem.get_pickup_radius_mult() - 1.15) < 0.001, "pearl L1 拾取倍率 1.15")
	_own_to_level("pearl", 5)
	_assert(abs(PassiveSystem.get_pickup_radius_mult() - 1.75) < 0.001, "pearl L5 拾取倍率 1.75")
	_reset_run()
	_own_to_level("lamp_core", 3)
	_assert(abs(PassiveSystem.get_damage_mult() - 1.24) < 0.001, "lamp_core L3 伤害倍率 1.24")
	# 叠加：lamp_core L3 + humus L3（伤害 6%×3=18%）
	_own_to_level("humus", 3)
	_assert(abs(PassiveSystem.get_damage_mult() - 1.42) < 0.001, "lamp_core L3 + humus L3 伤害倍率 1.42")
	_reset_run()
	_own_to_level("amulet", 5)
	_assert(abs(PassiveSystem.get_damage_reduction() - 0.30) < 0.001, "amulet L5 减伤 0.30")


func _test_damage_applies() -> void:
	print("[伤害乘区生效]")
	_reset_run()
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var w: WeaponBase = _WEAPON_HARPOON.new()
	w.configure(data, GameState.max_weapon_level)
	var base: int = w.get_leveled_damage()
	_own_to_level("lamp_core", 3)
	var with: int = w.get_leveled_damage()
	_assert(with > base, "被动伤害桶使伤害提升 (%d → %d)" % [base, with])
	_assert(abs(with - round(float(base) * 1.24)) <= 1, "伤害 ≈ base × 1.24 (L3)")
	w.free()


func _test_attack_speed() -> void:
	print("[攻速乘区生效]")
	_reset_run()
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var base_rate: float = float(data.get("attack_rate", 1.0))
	var w: WeaponBase = _WEAPON_HARPOON.new()
	w.configure(data, 1)
	var r0: float = w.get_attack_rate()
	_assert(abs(r0 - base_rate) < 0.001, "无被动攻速=基础")
	_own_to_level("tide_bell", 3)
	var r1: float = w.get_attack_rate()
	_assert(abs(r1 - base_rate * 1.24) < 0.001, "攻速 ≈ 基础 × 1.24 (L3 tide_bell)")
	w.free()


func _test_pickup_radius() -> void:
	print("[拾取半径乘区生效]")
	_reset_run()
	var p: Player = _PLAYER.new()
	var base_r: float = p.base_pickup_radius
	var r0: float = p.get_pickup_radius()
	_assert(abs(r0 - base_r) < 0.001, "无被动拾取半径=基础")
	_own_to_level("pearl", 5)
	var r1: float = p.get_pickup_radius()
	_assert(abs(r1 - base_r * 1.75) < 0.001, "拾取半径 ≈ 基础 × 1.75 (L5 pearl)")
	p.free()


func _test_damage_reduction() -> void:
	print("[减伤乘区生效]")
	_reset_run()
	GameState.is_over = false
	GameState.player_health = 100
	_own_to_level("amulet", 5)
	GameState.damage_player(10)
	_assert(GameState.player_health == 93, "减伤30%：100 - 10×0.7 = 93")
	# 无被动对照
	_reset_run()
	GameState.is_over = false
	GameState.player_health = 100
	GameState.damage_player(10)
	_assert(GameState.player_health == 90, "无减伤：100 - 10 = 90")


func _test_exp_mult() -> void:
	print("[经验乘区生效]")
	_reset_run()
	_last_exp = -1
	GameState.player_exp = 0
	_own_to_level("exp_sac", 5)
	GameState.add_exp(100)
	_assert(_last_exp == 150, "经验桶 L5：100 × 1.5 = 150")
	_reset_run()
	_last_exp = -1
	GameState.add_exp(100)
	_assert(_last_exp == 100, "无被动经验 = 基础 100")


func _test_area_crit_cd() -> void:
	print("[暴击/范围/冷却桶消费侧]")
	_reset_run()
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var w: WeaponBase = _WEAPON_HARPOON.new()
	w.configure(data, 1)
	_own_to_level("iron_chain", 5)
	_assert(abs(PassiveSystem.get_area_mult() - 1.4) < 0.001, "iron_chain L5 范围倍率 1.4")
	_assert(abs(w.scale_area_radius(100.0) - 140.0) < 0.001, "scale_area_radius 消费 area 桶")
	_reset_run()
	w.configure(data, 1)
	_own_to_level("storm_flask", 5)
	var base_rate: float = float(data.get("attack_rate", 1.0))
	var expect_iv: float = (1.0 / base_rate) * (1.0 - 0.4)
	_assert(abs(PassiveSystem.get_cd_reduction() - 0.4) < 0.001, "storm_flask L5 CD 减免 0.4")
	_assert(abs(w.get_attack_interval() - expect_iv) < 0.001, "攻击间隔应用 CD 桶")
	_reset_run()
	w.configure(data, 1)
	_own_to_level("abyss_eye", 5)
	_assert(abs(PassiveSystem.get_crit_chance() - 0.4) < 0.001, "abyss_eye L5 暴击率 0.4")
	var base_dmg: int = w.get_leveled_damage()
	var crit_mult: float = ConfigLoader.get_crit_damage_mult()
	var crit_expect: int = int(round(float(base_dmg) * crit_mult))
	var saw_crit: bool = false
	var saw_normal: bool = false
	RNG.set_seed(20261212)
	for _i in 80:
		var rolled: int = w.roll_hit_damage()
		if rolled == crit_expect:
			saw_crit = true
		elif rolled == base_dmg:
			saw_normal = true
	_assert(saw_crit and saw_normal, "roll_hit_damage 同时出现普通与暴击命中")
	# 连续两次掷骰可不同 → 每命中独立（非齐射共用一次）
	RNG.set_seed(20261212)
	var a: int = PassiveSystem.apply_crit_to_damage(base_dmg)
	var b: int = PassiveSystem.apply_crit_to_damage(base_dmg)
	var varied: bool = false
	for _j in 40:
		a = PassiveSystem.apply_crit_to_damage(base_dmg)
		b = PassiveSystem.apply_crit_to_damage(base_dmg)
		if a != b:
			varied = true
			break
	_assert(varied, "连续命中暴击独立（相邻掷骰可不同）")
	w.free()


func _test_slot_cap() -> void:
	print("[被动槽上限 6]")
	_reset_run()
	var ids: Array[String] = ["pearl", "amulet", "tide_bell", "lamp_core", "tide_compass", "lamp_oil"]
	for pid in ids:
		GameState.add_passive(pid)
	_assert(GameState.passive_slot_usage() == 6, "6 被动占满槽")
	_assert(not GameState.can_add_passive(), "槽满 can_add_passive=false")
	_assert(GameState.add_passive("humus") == false, "第 7 个被动被拒（槽满）")


func _test_level_cap() -> void:
	print("[被动等级上限 5]")
	_reset_run()
	GameState.add_passive("pearl")
	var guard: int = 0
	while GameState.add_passive("pearl"):
		guard += 1
		if guard > 20:
			break
	_assert(GameState.get_passive_level("pearl") == 5, "被动满级 5 封顶")
	_assert(GameState.add_passive("pearl") == false, "满级后再加返回 false")


func _test_remove_frees() -> void:
	print("[移除返还槽位]")
	_reset_run()
	var ids: Array[String] = ["pearl", "amulet", "tide_bell", "lamp_core", "tide_compass", "lamp_oil"]
	for pid in ids:
		GameState.add_passive(pid)
	GameState.remove_passive("pearl")
	_assert(GameState.passive_slot_usage() == 5, "移除后剩 5 槽")
	_assert(GameState.can_add_passive(), "移除后槽有空位")
	_assert(GameState.add_passive("humus") == true, "移除后可再入槽")
