# ============================================================================
# UpgradeLogicTests — 升级三选一逻辑最小单测
# 运行：godot --headless --path godot_project res://scenes/tests/upgrade_logic_test.tscn
# 退出码：0=全部通过，1=有失败
# ============================================================================
extends Node

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("Upgrade Logic Tests")
	print("============================================================")
	_test_offers_count_and_types()
	_test_apply_adds_to_slots()
	_test_reroll_cost()
	_test_weapon_slots_full_only_passives()
	_test_skip_no_change()
	_test_weapon_pity_force()
	_test_reroll_does_not_double_pity()
	_test_empty_pool_auto_skip()
	_test_force_resume_closes_ui_signal()
	_test_series_pity_mult()
	_test_series_seen_blocks_mult_on_reroll()
	_test_reroll_empty_pool_auto_skip()
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
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


func _fresh_run() -> void:
	UpgradeManager.reset()
	GameState.start_new_run("watcher", 20260813)
	get_tree().paused = false


# 升级到触发一次三选一，返回当前 offers（已暂停）
func _level_up_once() -> Array:
	# 加足够经验跨越 1 级（E(1)=22）
	GameState.add_exp(22)
	return UpgradeManager.get_current_offers()


func _test_offers_count_and_types() -> void:
	print("[offers count & types]")
	_fresh_run()
	RNG.set_seed(1)
	var offers: Array = _level_up_once()
	_assert(UpgradeManager.is_presenting(), "level up 触发三选一（暂停）")
	_assert(offers.size() == 3, "恰好 3 个选项")
	var all_valid: bool = true
	for o in offers:
		var t: String = o.get("type", "")
		if t != "weapon" and t != "passive":
			all_valid = false
		if o.get("id", "") == "":
			all_valid = false
	_assert(all_valid, "选项 type 为 weapon/passive 且含 id")
	# 恢复
	UpgradeManager.skip()
	_assert(not UpgradeManager.is_presenting(), "skip 后结束三选一")
	_assert(not get_tree().paused, "skip 后恢复树")


func _test_apply_adds_to_slots() -> void:
	print("[apply adds to slots]")
	_fresh_run()
	# 清空开局授予的默认武器/被动，隔离「应用新项 → 入槽」语义
	# （start_new_run 会授予数据驱动默认武器，否则首次三选一可能选到已持有武器走升级分支，槽数不 +1）
	GameState.weapon_slots.clear()
	GameState.passive_slots.clear()
	GameState.weapon_levels.clear()
	GameState.passive_levels.clear()
	var offers: Array = _level_up_once()
	# 选第一个武器（若有），否则任一
	var idx: int = 0
	for i in offers.size():
		if offers[i].get("type") == "weapon":
			idx = i
			break
	var before_w: int = GameState.weapon_slots.size()
	var before_p: int = GameState.passive_slots.size()
	UpgradeManager.apply_offer(idx)
	if offers[idx].get("type") == "weapon":
		_assert(GameState.weapon_slots.size() == before_w + 1, "apply 武器 → 武器槽 +1")
	else:
		_assert(GameState.passive_slots.size() == before_p + 1, "apply 被动 → 被动槽 +1")
	_assert(not UpgradeManager.is_presenting(), "apply 后结束（单级）")


func _test_reroll_cost() -> void:
	print("[reroll cost]")
	_fresh_run()
	_level_up_once()
	# 首次免费重铸：潮币不变、仍 3 项
	var coins_before: int = GameState.tidecoins
	var ok_free: bool = UpgradeManager.reroll()
	_assert(ok_free, "免费重铸成功")
	_assert(GameState.tidecoins == coins_before, "免费重铸不花潮币")
	_assert(UpgradeManager.get_current_offers().size() == 3, "重铸后仍 3 项")
	# 第二次重铸需 10 潮币：潮币不足应失败
	GameState.tidecoins = 0
	var ok_paid: bool = UpgradeManager.reroll()
	_assert(not ok_paid, "潮币不足时付费重铸失败")
	# 给足潮币后成功并扣费
	GameState.tidecoins = 50
	var ok_paid2: bool = UpgradeManager.reroll()
	_assert(ok_paid2, "潮币充足时付费重铸成功")
	_assert(GameState.tidecoins == 40, "付费重铸扣除 10 潮币")
	UpgradeManager.skip()


func _test_weapon_slots_full_only_passives() -> void:
	print("[weapon slots full -> only passives or owned upgrades]")
	_fresh_run()
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	GameState.passive_slots = []
	var offers: Array = _level_up_once()
	# 武器槽已满（4/4）：已持有武器仍可升级（W5 武器升级路径），但不得出现「新武器」
	# （新武器无槽位，§6.2）——这是真实不变量；原断言「只出被动」过严。
	var only_passives_or_owned_upgrades: bool = true
	for o in offers:
		if o.get("type") == "weapon" and o.get("id", "") not in GameState.weapon_slots:
			only_passives_or_owned_upgrades = false
	_assert(only_passives_or_owned_upgrades, "武器槽满时只出被动或已持有武器升级（不出新武器）")
	UpgradeManager.skip()


func _test_skip_no_change() -> void:
	print("[skip keeps slots]")
	_fresh_run()
	var offers: Array = _level_up_once()
	var before_w: int = GameState.weapon_slots.size()
	var before_p: int = GameState.passive_slots.size()
	UpgradeManager.skip()
	_assert(GameState.weapon_slots.size() == before_w, "skip 不改变武器槽")
	_assert(GameState.passive_slots.size() == before_p, "skip 不改变被动槽")
	_assert(not UpgradeManager.is_presenting(), "skip 后结束")


func _test_weapon_pity_force() -> void:
	print("[weapon pity force]")
	_fresh_run()
	GameState.weapon_slots = []
	GameState.passive_slots = []
	# 模拟连续 2 次未出武器（白盒：直接置保底计数）
	UpgradeManager._no_weapon_streak = 2
	var pool: Array = UpgradeManager._build_candidate_pool()
	var built: Array = UpgradeManager._build_offers()
	var has_weapon: bool = false
	for o in built:
		if o.get("type") == "weapon":
			has_weapon = true
	_assert(not pool.is_empty(), "候选池非空")
	_assert(has_weapon, "连续 2 次无武器 → 第 3 次必出武器")


func _test_reroll_does_not_double_pity() -> void:
	print("[reroll does not double pity]")
	_fresh_run()
	# 4 把武器全部满级 → 候选池剔除武器（含升级），仅剩被动，
	# 从而稳定复现「本轮只展示被动」前提（否则已持有武器升级也会清零 miss）
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	for wid in GameState.weapon_slots:
		GameState.weapon_levels[wid] = GameState.max_weapon_level
	GameState.passive_slots = []
	_level_up_once()
	_assert(UpgradeManager._no_weapon_streak == 1, "仅被动展示 → 武器 miss=1")
	var ok: bool = UpgradeManager.reroll()
	_assert(ok, "免费重铸成功")
	_assert(UpgradeManager._no_weapon_streak == 1, "同一次重铸不把 miss 累加到 2")
	UpgradeManager.skip()


func _test_empty_pool_auto_skip() -> void:
	print("[empty pool auto skip]")
	_fresh_run()
	# 槽满且全部满级 → 无升级候选（含 W10「已持有升级」路径）
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	for wid in GameState.weapon_slots:
		GameState.weapon_levels[wid] = GameState.max_weapon_level
	GameState.passive_slots = [
		"pearl", "amulet", "tide_bell", "lamp_core", "tide_compass", "lamp_oil",
	]
	for pid in GameState.passive_slots:
		GameState.passive_levels[pid] = GameState.max_passive_level
	GameState.add_exp(22)
	_assert(not UpgradeManager.is_presenting(), "候选池空 → 不停留在三选一")
	_assert(not get_tree().paused, "候选池空 → 不保持暂停")


func _test_force_resume_closes_ui_signal() -> void:
	print("[force resume emits resolved]")
	_fresh_run()
	_level_up_once()
	var closed: Array = [false]
	var cb := func(_offer: Dictionary, _is_skip: bool) -> void:
		closed[0] = true
	UpgradeManager.upgrade_resolved.connect(cb)
	GameState.trigger_game_over("test")
	_assert(closed[0], "game_over 时发出 upgrade_resolved")
	_assert(not UpgradeManager.is_presenting(), "game_over 后结束三选一")
	# is_over 时 UpgradeManager 不解暂停（结束态暂停权归 World/ResultUI）
	_assert(get_tree().paused, "is_over 时 UpgradeManager 保持暂停（不解暂停）")
	_assert(GameState.is_over, "trigger_game_over 置 is_over")
	get_tree().paused = false  # 单测无 World，自行清暂停以免污染后续用例
	if UpgradeManager.upgrade_resolved.is_connected(cb):
		UpgradeManager.upgrade_resolved.disconnect(cb)


func _test_series_pity_mult() -> void:
	print("[series pity mult]")
	_fresh_run()
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	GameState.passive_slots = []
	UpgradeManager._series_miss_streak["潮汐"] = 3
	UpgradeManager._choosing = false
	var pool: Array = UpgradeManager._build_candidate_pool()
	var tide_weight: int = 0
	var base_passive: int = int(ConfigLoader.get_upgrade_config().get("weight_passive", 8))
	var mult: int = int(ConfigLoader.get_upgrade_config().get("series_pity_mult", 3))
	for c in pool:
		if c.get("series") == "潮汐":
			tide_weight = int(c.get("weight", 0))
			break
	_assert(tide_weight == base_passive * mult, "连续 3 次无某系 → 该系权重 ×3")


func _test_series_seen_blocks_mult_on_reroll() -> void:
	print("[series seen blocks mult on reroll]")
	_fresh_run()
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	GameState.passive_slots = []
	UpgradeManager._series_miss_streak["潮汐"] = 3
	UpgradeManager._pending_choices = 1
	UpgradeManager._present_next()
	# 模拟本轮已展示过潮汐（不论实际抽到什么）
	UpgradeManager._series_seen_this_choice["潮汐"] = true
	UpgradeManager._note_offers_and_recompute_pity([
		{"type": "passive", "series": "潮汐", "id": "tide_bell"},
	])
	_assert(int(UpgradeManager._series_miss_streak.get("潮汐", -1)) == 0, "出现潮汐后 miss 清零")
	var pool: Array = UpgradeManager._build_candidate_pool()
	var tide_weight: int = -1
	var base_passive: int = int(ConfigLoader.get_upgrade_config().get("weight_passive", 8))
	for c in pool:
		if c.get("series") == "潮汐":
			tide_weight = int(c.get("weight", 0))
			break
	_assert(tide_weight == base_passive, "本轮已出现该系后重铸构建不再 ×3")
	UpgradeManager.skip()


func _test_reroll_empty_pool_auto_skip() -> void:
	print("[reroll empty pool auto skip]")
	_fresh_run()
	GameState.weapon_slots = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	for wid in GameState.weapon_slots:
		GameState.weapon_levels[wid] = GameState.max_weapon_level
	GameState.passive_slots = []
	GameState.passive_levels.clear()
	_level_up_once()
	_assert(UpgradeManager.is_presenting(), "先进入三选一")
	# 中途塞满被动且满级，使重铸候选为空
	GameState.passive_slots = [
		"pearl", "amulet", "tide_bell", "lamp_core", "tide_compass", "lamp_oil",
	]
	for pid in GameState.passive_slots:
		GameState.passive_levels[pid] = GameState.max_passive_level
	UpgradeManager._reroll_offers()
	_assert(not UpgradeManager.is_presenting(), "重铸空池 → 自动结束")
	_assert(not get_tree().paused, "重铸空池 → 恢复树")
