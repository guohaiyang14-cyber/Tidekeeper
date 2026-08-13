# ============================================================================
# PrototypeAcceptanceTest — 原型验收自动核对（W1–W4 清单可机检项）
# 运行：godot --headless --path godot_project res://scenes/tests/prototype_acceptance_test.tscn
# 退出码：0=全部机检通过，1=有失败
# 范围：仅核对"无需人工手玩"的项；帧率/手感/可玩到8-10夜标注需人工验收
# ============================================================================
extends Node

var _passed: int = 0
var _failed: int = 0
var _manual: int = 0


func _ready() -> void:
	print("============================================================")
	print("Prototype Acceptance Test (原型验收·机检项)")
	print("============================================================")
	_test_day_night_loop()
	_test_night_duration_constants()
	_test_night_ends_to_day()
	_test_day_no_countdown()
	_test_three_choice_trigger()
	_test_three_choice_categories()
	_test_free_reroll()
	_test_slot_caps()
	print("------------------------------------------------------------")
	print("机检通过=%d 失败=%d | 需人工验收项(本脚本不计)=%d" % [_passed, _failed, _manual])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String, is_manual: bool = false) -> void:
	if is_manual:
		_manual += 1
		print("  [人工] %s" % label)
		return
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


# ---------------------------------------------------------------------------
# 1.1.1 昼夜空循环 ≥10 夜不中断
# ---------------------------------------------------------------------------
func _test_day_night_loop() -> void:
	print("[1.1.1 昼夜空循环 ≥10 夜]")
	GameState.start_new_run("watcher", 20260813)
	var dn: DayNightStateMachine = DayNightStateMachine.new()
	add_child(dn)
	dn.start_run()
	var survived: bool = true
	for n in 10:
		# 驱动本夜计时走完（触发无条件进昼）
		dn._process(dn.get_night_duration() + 1.0)
		if dn.get_phase() != DayNightStateMachine.Phase.DAY:
			survived = false
			break
		# 抉择之昼跳过 → 进入下一夜
		dn.skip_day_phase()
		if dn.get_phase() != DayNightStateMachine.Phase.NIGHT:
			survived = false
			break
	_assert(survived and dn.get_current_night() >= 10, "连续空循环 ≥10 夜（当前第 %d 夜）不中断" % dn.get_current_night())
	dn.queue_free()


# ---------------------------------------------------------------------------
# 1.1.2 夜晚时长常量（常规45/精英60/天灾90/终局120）
# ---------------------------------------------------------------------------
func _test_night_duration_constants() -> void:
	print("[1.1.2 夜晚时长常量]")
	var dn: DayNightStateMachine = DayNightStateMachine.new()
	add_child(dn)
	_assert(dn._get_night_duration(1) == 45.0, "常规夜(第1夜)=45s")
	_assert(dn._get_night_duration(5) == 60.0, "精英夜(第5夜)=60s")
	_assert(dn._get_night_duration(10) == 90.0, "天灾夜(第10夜)=90s")
	_assert(dn._get_night_duration(20) == 120.0, "终局夜(第20夜)=120s")
	dn.queue_free()


# ---------------------------------------------------------------------------
# 1.1.3 夜晚结束无条件进昼（敌人未清完也切换）
# ---------------------------------------------------------------------------
func _test_night_ends_to_day() -> void:
	print("[1.1.3 夜末无条件进昼]")
	GameState.start_new_run("watcher", 20260813)
	var dn: DayNightStateMachine = DayNightStateMachine.new()
	add_child(dn)
	dn.start_run()
	dn._process(dn.get_night_duration() + 1.0)
	_assert(dn.get_phase() == DayNightStateMachine.Phase.DAY, "夜晚计时归零 → 进入抉择之昼")
	dn.queue_free()


# ---------------------------------------------------------------------------
# 1.1.4 抉择之昼无强制倒计时（停留不自动切换）
# ---------------------------------------------------------------------------
func _test_day_no_countdown() -> void:
	print("[1.1.4 昼无强制倒计时]")
	GameState.start_new_run("watcher", 20260813)
	var dn: DayNightStateMachine = DayNightStateMachine.new()
	add_child(dn)
	dn.start_run()
	dn._process(dn.get_night_duration() + 1.0)  # 进昼
	var phase_after_skip_wait: int = 0
	for i in 100:  # 模拟约 100 帧停留
		dn._process(1.0)
		if dn.get_phase() != DayNightStateMachine.Phase.DAY:
			phase_after_skip_wait = dn.get_phase()
			break
	_assert(dn.get_phase() == DayNightStateMachine.Phase.DAY, "抉择之昼停留不自动切换（无强制倒计时）")
	dn.queue_free()


# ---------------------------------------------------------------------------
# 1.3.1 升级触发三选一
# ---------------------------------------------------------------------------
func _test_three_choice_trigger() -> void:
	print("[1.3.1 升级触发三选一]")
	GameState.start_new_run("watcher", 20260813)
	UpgradeManager.reset()
	GameState.add_exp(22)  # 跨 1 级
	_assert(UpgradeManager.is_presenting(), "经验足够后弹出三选一")
	UpgradeManager.skip()
	if get_tree().paused:
		get_tree().paused = false


# ---------------------------------------------------------------------------
# 1.3.2 武器/被动分类展示
# ---------------------------------------------------------------------------
func _test_three_choice_categories() -> void:
	print("[1.3.2 武器/被动分类]")
	GameState.start_new_run("watcher", 20260813)
	UpgradeManager.reset()
	GameState.add_exp(22)
	var offers: Array = UpgradeManager.get_current_offers()
	var has_weapon: bool = false
	var has_passive: bool = false
	var all_typed: bool = true
	for o in offers:
		var t: String = o.get("type", "")
		if t == "weapon":
			has_weapon = true
		elif t == "passive":
			has_passive = true
		else:
			all_typed = false
	_assert(all_typed, "选项 type 均为 weapon/passive")
	_assert(has_weapon or has_passive, "至少含武器或被动分类")
	UpgradeManager.skip()
	if get_tree().paused:
		get_tree().paused = false


# ---------------------------------------------------------------------------
# 1.3.3 免费重铸（每级 1 次）
# ---------------------------------------------------------------------------
func _test_free_reroll() -> void:
	print("[1.3.3 免费重铸 1 次/级]")
	GameState.start_new_run("watcher", 20260813)
	UpgradeManager.reset()
	GameState.add_exp(22)
	var coins_before: int = GameState.tidecoins
	var ok: bool = UpgradeManager.reroll()
	_assert(ok, "首次重铸成功")
	_assert(GameState.tidecoins == coins_before, "免费重铸不花费潮币")
	UpgradeManager.skip()
	if get_tree().paused:
		get_tree().paused = false


# ---------------------------------------------------------------------------
# 1.3.4 锁槽（4 武器 / 6 被动上限）
# ---------------------------------------------------------------------------
func _test_slot_caps() -> void:
	print("[1.3.4 锁槽上限 4 武器 / 6 被动]")
	_assert(GameState.MAX_WEAPON_SLOTS == 4, "武器槽上限 = 4")
	_assert(GameState.MAX_PASSIVE_SLOTS == 6, "被动槽上限 = 6")
	# 武器槽满后 add_weapon 失败
	GameState.start_new_run("watcher", 20260813)
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	var extra: bool = GameState.add_weapon("anchor_chain")
	_assert(not extra, "武器槽满(4)后 add_weapon 返回 false")
	# 被动槽满后失败
	GameState.passive_slots = ["pearl", "amulet", "tide_bell", "lamp_core", "p1", "p2"]
	var extra_p: bool = GameState.add_passive("p3")
	_assert(not extra_p, "被动槽满(6)后 add_passive 返回 false")
