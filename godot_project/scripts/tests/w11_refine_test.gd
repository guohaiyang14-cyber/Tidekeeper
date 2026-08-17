# ============================================================================
# W11RefineTest — 精炼系统 I/II 机检
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w11_refine_test.tscn
# 覆盖：8 路径、倍率累积、须进化、夜次门控、II≤2、不可逆、伤害、Boss/精英掉落、精华上限、tier clamp
# ============================================================================
extends Node

const _WEAPON_HARPOON = preload("res://scripts/combat/weapon_harpoon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# 固定种子，保证精英 30% 概率采样的可复现性
	RNG.set_seed(20261111)
	print("============================================================")
	print("W11 精炼系统 I/II 机检")
	print("============================================================")
	_test_config_paths()
	_test_multiplier_cumulative()
	_test_require_evolved()
	_test_night_gating_and_cost()
	_test_ii_cap()
	_test_irreversible()
	_test_tier_clamp()
	_test_damage_applies()
	_test_boss_drops()
	_test_elite_drops()
	_test_essence_cap()
	print("------------------------------------------------------------")
	print("W11 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _reset_run() -> void:
	GameState.start_new_run("watcher", 20261010)
	RefineSystem.on_night_start(1)


func _own_weapon(wid: String) -> void:
	if wid not in GameState.weapon_slots:
		GameState.add_weapon(wid)


func _mark_evolved(wid: String) -> void:
	_own_weapon(wid)
	GameState.mark_weapon_evolved(wid, "测试传说·%s" % wid)


func _test_config_paths() -> void:
	print("[配置]")
	var ids: Array = ConfigLoader.get_all_refine_weapon_ids()
	_assert(ids.size() == 8, "refine.paths = 8（MVP #1~#8）")
	_assert(bool(ConfigLoader.get_refine_rules().get("require_evolved", false)), "require_evolved=true（§6.6）")
	for wid_v in ids:
		var wid: String = String(wid_v)
		var path: Dictionary = ConfigLoader.get_refine_path(wid)
		_assert(not path.is_empty(), "%s 精炼路径存在" % wid)
		_assert(path.has("tier_I") and path.has("tier_II"), "%s 含 I/II 两阶" % wid)
		_assert(float(path["tier_I"].get("dps_mult", 0)) > 1.0, "%s I 倍率>1" % wid)
		_assert(float(path["tier_II"].get("dps_mult", 0)) > 1.0, "%s II 倍率>1" % wid)
		# 路径武器必须真实存在
		_assert(not ConfigLoader.get_weapon(wid).is_empty(), "%s 武器存在" % wid)


func _test_multiplier_cumulative() -> void:
	print("[倍率累积]")
	var i: float = ConfigLoader.get_refine_multiplier("harpoon", 1)
	var full: float = ConfigLoader.get_refine_multiplier("harpoon", 2)
	var expect: float = float(ConfigLoader.get_refine_path("harpoon")["tier_I"]["dps_mult"]) * float(ConfigLoader.get_refine_path("harpoon")["tier_II"]["dps_mult"])
	_assert(abs(i - float(ConfigLoader.get_refine_path("harpoon")["tier_I"]["dps_mult"])) < 0.001, "T1 倍率= tier_I")
	_assert(abs(full - expect) < 0.001, "T2 倍率= tier_I × tier_II（累积）")
	_assert(ConfigLoader.get_refine_multiplier("harpoon", 0) == 1.0, "T0 倍率=1")


func _test_require_evolved() -> void:
	print("[须已进化]")
	_reset_run()
	_own_weapon("harpoon")
	GameState.current_night = 15
	GameState.refine_essence = 9
	_assert(not GameState.is_weapon_evolved("harpoon"), "前置：未进化")
	_assert(RefineSystem.next_refine_tier("harpoon") == 0, "未进化不可精炼")
	_mark_evolved("harpoon")
	_assert(RefineSystem.can_refine("harpoon"), "进化后可精炼")


func _test_night_gating_and_cost() -> void:
	print("[夜次门控 / 精华消耗]")
	_reset_run()
	_mark_evolved("harpoon")
	# 第 1 夜：未开放 + 无精华 → 不可精炼
	GameState.current_night = 1
	GameState.refine_essence = 0
	_assert(RefineSystem.next_refine_tier("harpoon") == 0, "第1夜未开放，不可精炼")
	# 第 10 夜 + 1 精华 → 可精炼 I
	GameState.current_night = 10
	GameState.refine_essence = 1
	_assert(RefineSystem.can_refine("harpoon"), "第10夜+1精华 可精炼 I")
	_assert(RefineSystem.refine("harpoon") == 1, "精炼 → T1")
	_assert(GameState.refine_essence == 0, "精炼 I 消耗 1 精华")
	_assert(GameState.get_refine_tier("harpoon") == 1, "武器记为 T1")
	# T1 后第 10 夜：II 未开放（需第15夜）
	GameState.refine_essence = 2
	_assert(RefineSystem.next_refine_tier("harpoon") == 0, "第10夜 T1 后不可精炼 II（需第15夜）")
	# 第 15 夜 + 2 精华 → 可精炼 II
	GameState.current_night = 15
	GameState.refine_essence = 2
	_assert(RefineSystem.can_refine("harpoon"), "第15夜+2精华 可精炼 II")
	_assert(RefineSystem.refine("harpoon") == 2, "精炼 → T2")
	_assert(GameState.refine_essence == 0, "精炼 II 消耗 2 精华")
	_assert(GameState.refine_ii_count == 1, "II 计数 +1")


func _test_ii_cap() -> void:
	print("[II 全局上限 ≤2]")
	_reset_run()
	GameState.current_night = 15
	GameState.refine_essence = 9
	for wid in ["harpoon", "holy_fire", "anchor_hammer"]:
		_mark_evolved(wid)
	# 两把升到 II
	_assert(RefineSystem.refine("harpoon") == 1, "harpoon → I")
	_assert(RefineSystem.refine("harpoon") == 2, "harpoon → II")
	_assert(RefineSystem.refine("holy_fire") == 1, "holy_fire → I")
	_assert(RefineSystem.refine("holy_fire") == 2, "holy_fire → II")
	_assert(GameState.refine_ii_count == 2, "II 计数=2（达上限）")
	# 第三把升到 I 后，无法再升 II
	_assert(RefineSystem.refine("anchor_hammer") == 1, "anchor_hammer → I")
	_assert(RefineSystem.next_refine_tier("anchor_hammer") == 0, "达 II 上限，第三把不可精炼到 II")
	_assert(RefineSystem.refine("anchor_hammer") == 0, "精炼到 II 被上限拦截")
	# 已 II 的武器不可再精炼（封顶）
	_assert(RefineSystem.next_refine_tier("harpoon") == 0, "已 II 武器封顶")


func _test_irreversible() -> void:
	print("[不可撤销 / 封顶]")
	_reset_run()
	_mark_evolved("harpoon")
	GameState.current_night = 15
	GameState.refine_essence = 3
	RefineSystem.refine("harpoon")  # → I
	GameState.set_refine_tier("harpoon", 2)
	# 系统侧只能升不能降：已 II 的 next 必为 0（无更高阶）
	_assert(RefineSystem.next_refine_tier("harpoon") == 0, "已 II 无法再精炼（无 III，MVP）")


func _test_tier_clamp() -> void:
	print("[set_refine_tier 钳制]")
	_reset_run()
	_own_weapon("harpoon")
	GameState.set_refine_tier("harpoon", 99)
	_assert(GameState.get_refine_tier("harpoon") == 2, "tier>2 钳制为 2")
	_assert(GameState.refine_ii_count == 1, "钳制到 II 时计数 +1")
	GameState.set_refine_tier("harpoon", -3)
	_assert(GameState.get_refine_tier("harpoon") == 0, "tier<0 钳制为 0")
	_assert(GameState.refine_ii_count == 0, "离开 II 时计数 -1")


func _test_damage_applies() -> void:
	print("[伤害倍率生效]")
	_reset_run()
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	_own_weapon("harpoon")
	while GameState.get_weapon_level("harpoon") < GameState.max_weapon_level:
		if not GameState.add_weapon("harpoon"):
			break
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var w: WeaponBase = WeaponHarpoon.new()
	w.configure(data, GameState.max_weapon_level)
	var base: int = w.get_leveled_damage()
	GameState.set_refine_tier("harpoon", 1)
	var t1: int = w.get_leveled_damage()
	GameState.set_refine_tier("harpoon", 2)
	var t2: int = w.get_leveled_damage()
	var m1: float = ConfigLoader.get_refine_multiplier("harpoon", 1)
	var m2: float = ConfigLoader.get_refine_multiplier("harpoon", 2)
	_assert(t1 > base, "精炼 I 后伤害提升 (%d → %d)" % [base, t1])
	_assert(t2 > t1, "精炼 II 后伤害再提升 (%d → %d)" % [t1, t2])
	_assert(abs(t1 - round(float(base) * m1)) <= 1, "T1 伤害 ≈ base × tier_I 倍率")
	_assert(abs(t2 - round(float(base) * m2)) <= 1, "T2 伤害 ≈ base × tier_I×II 倍率")
	w.free()


func _test_boss_drops() -> void:
	print("[Boss 淬炼精华掉落]")
	_reset_run()
	RefineSystem.on_night_start(10)
	GameState.refine_essence = 0
	_assert(RefineSystem.try_boss_drop(10) == 1, "第10夜 Boss 掉 1")
	RefineSystem.on_night_start(15)
	GameState.refine_essence = 0
	_assert(RefineSystem.try_boss_drop(15) == 2, "第15夜 Boss 掉 2")
	RefineSystem.on_night_start(20)
	GameState.refine_essence = 0
	_assert(RefineSystem.try_boss_drop(20) == 3, "第20夜 Boss 掉 3")
	# 非 Boss 夜不掉
	RefineSystem.on_night_start(11)
	GameState.refine_essence = 0
	_assert(RefineSystem.try_boss_drop(11) == 0, "第11夜无 Boss 掉落")


func _test_elite_drops() -> void:
	print("[精英淬炼精华掉落]")
	_reset_run()
	# 夜次门控：第 12 夜前不掉
	RefineSystem.on_night_start(10)
	GameState.refine_essence = 0
	_assert(RefineSystem.try_elite_drop(10) == 0, "第<12夜精英不掉")
	# 第 12 夜起：30% 概率 + 当夜上限 1（多次采样必中至少一次且不超过 1）
	RefineSystem.on_night_start(12)
	GameState.refine_essence = 0
	var granted: int = 0
	for i in 300:
		granted += RefineSystem.try_elite_drop(12)
	_assert(granted >= 1, "第12夜精英有概率掉落（300 次采样）")
	_assert(granted <= 1, "精英当夜上限 1")
	_assert(GameState.refine_essence == granted, "掉落实发数 = 精华增量")


func _test_essence_cap() -> void:
	print("[精华安全上限]")
	_reset_run()
	var cap: int = int(RefineSystem.get_rules().get("essence_cap", 9))
	GameState.refine_essence = cap - 1
	var got: int = RefineSystem.grant_essence(5)
	_assert(got == 1, "超过 essence_cap 被截断（room=1）")
	_assert(GameState.refine_essence == cap, "精华不超过上限 %d" % cap)
