# ============================================================================
# W13ShopTest — 商店完善 + 经济闭环（逻辑 + 机检）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w13_shop_test.tscn
# 覆盖：购买扣实付价 / 槽满退款不扣币 / 重铸退 80% / 未持有退 0 /
#       休息夜判定 / 灯塔回血 / 经济闭环无刷币
# ============================================================================
extends Node

const _SHOP = preload("res://scripts/core/shop_manager.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	RNG.set_seed(20261313)
	print("============================================================")
	print("W13 商店完善 + 经济闭环（逻辑 + 机检）")
	print("============================================================")
	_test_buy_deducts()
	_test_slot_full_no_deduct()
	_test_reroll_passive()
	_test_reroll_weapon()
	_test_reroll_last_weapon_blocked()
	_test_reroll_clears_refine()
	_test_reroll_not_held()
	_test_buy_emits_loadout()
	_test_rest_night()
	_test_rest_heal()
	_test_rest_try_apply()
	_test_economy_no_exploit()
	print("------------------------------------------------------------")
	print("W13 机检通过=%d 失败=%d" % [_passed, _failed])
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
	GameState.start_new_run("watcher", 20261313)


## 某商品实际支付价（与 ConfigLoader.get_shop_paid_cost 一致）
func _paid(kind: String) -> int:
	return ConfigLoader.get_shop_paid_cost(kind)


func _refund(kind: String) -> int:
	return roundi(float(_paid(kind)) * ConfigLoader.get_shop_refund_ratio(kind))


func _test_buy_deducts() -> void:
	print("[购买扣费]")
	_reset_run()
	GameState.add_tidecoins(1000)
	var shop: ShopManager = _SHOP.new()
	shop.open_shop()
	var items: Array = shop.get_current_items()
	var item: Dictionary = {}
	for it in items:
		if it["kind"] == "passive":
			item = it
			break
	_assert(not item.is_empty(), "商店含被动项")
	if item.is_empty():
		shop.free()
		return
	var paid: int = _paid("passive")
	var before: int = GameState.tidecoins
	var ok: bool = shop.buy(item)
	_assert(ok, "购买被动成功")
	_assert(GameState.tidecoins == before - paid, "潮币扣实付折扣价 %d" % paid)
	_assert(GameState.get_passive_level(item["id"]) >= 1, "被动已入槽")
	shop.free()


func _test_slot_full_no_deduct() -> void:
	print("[槽满退款]")
	_reset_run()
	GameState.add_tidecoins(1000)
	for pid in ["pearl", "amulet", "tide_bell", "lamp_core", "tide_compass", "lamp_oil"]:
		GameState.add_passive(pid)
	_assert(GameState.passive_slot_usage() == 6, "被动槽满 6")
	var shop: ShopManager = _SHOP.new()
	var before: int = GameState.tidecoins
	var ok: bool = shop.buy({"id": "iron_chain", "kind": "passive", "cost": _paid("passive")})
	_assert(not ok, "槽满购买失败")
	_assert(GameState.tidecoins == before, "槽满不扣币（退款）")
	shop.free()


func _test_reroll_passive() -> void:
	print("[重铸回收-被动]")
	_reset_run()
	GameState.add_tidecoins(1000)
	GameState.add_passive("humus")
	var exp_refund: int = _refund("passive")
	var before: int = GameState.tidecoins
	var got: int = GameState.reroll_passive("humus")
	_assert(got == exp_refund, "重铸退 config 比例 = %d" % exp_refund)
	_assert(GameState.tidecoins == before + exp_refund, "潮币增加退款额")
	_assert(GameState.get_passive_level("humus") == 0, "被动已卸下返还槽")


func _test_reroll_weapon() -> void:
	print("[重铸回收-武器]")
	_reset_run()
	GameState.add_tidecoins(1000)
	# start_new_run 已有起步枪；再入一把以便允许重铸
	GameState.add_weapon("holy_fire")
	var exp_refund: int = _refund("weapon")
	var before: int = GameState.tidecoins
	var got: int = GameState.reroll_weapon("holy_fire")
	_assert(got == exp_refund, "武器重铸退 config 比例 = %d" % exp_refund)
	_assert(GameState.tidecoins == before + exp_refund, "潮币增加退款额")
	_assert(GameState.get_weapon_level("holy_fire") == 0, "武器已卸下返还槽")
	_assert(GameState.weapon_slots.size() >= 1, "重铸后仍保留至少 1 把")


func _test_reroll_last_weapon_blocked() -> void:
	print("[重铸-末把武器拒绝]")
	_reset_run()
	GameState.add_tidecoins(1000)
	_assert(GameState.weapon_slots.size() == 1, "开局仅起步枪")
	var before: int = GameState.tidecoins
	var got: int = GameState.reroll_weapon(GameState.weapon_slots[0])
	_assert(got == 0, "末把武器重铸返回 0")
	_assert(GameState.tidecoins == before, "末把不退款")
	_assert(GameState.weapon_slots.size() == 1, "末把仍在槽")


func _test_reroll_clears_refine() -> void:
	print("[重铸清除精炼阶]")
	_reset_run()
	GameState.add_weapon("holy_fire")
	GameState.set_refine_tier("holy_fire", 2)
	_assert(GameState.get_refine_tier("holy_fire") == 2, "重铸前精炼阶 2")
	GameState.reroll_weapon("holy_fire")
	_assert(GameState.get_refine_tier("holy_fire") == 0, "重铸后精炼阶清零")
	GameState.add_weapon("holy_fire")
	_assert(GameState.get_refine_tier("holy_fire") == 0, "再购同武器无残留精炼")


func _test_reroll_not_held() -> void:
	print("[重铸-未持有]")
	_reset_run()
	GameState.add_tidecoins(1000)
	var before: int = GameState.tidecoins
	var got: int = GameState.reroll_passive("nonexistent_xyz")
	_assert(got == 0, "未持有退 0")
	_assert(GameState.tidecoins == before, "未持有不退款")


func _test_buy_emits_loadout() -> void:
	print("[购买发射 loadout_changed]")
	_reset_run()
	GameState.add_tidecoins(1000)
	var emitted: Array[bool] = [false]
	var on_loadout := func() -> void:
		emitted[0] = true
	GameState.loadout_changed.connect(on_loadout)
	var shop: ShopManager = _SHOP.new()
	var paid: int = _paid("weapon")
	var ok: bool = shop.buy({"id": "holy_fire", "kind": "weapon", "cost": paid})
	_assert(ok, "购买武器成功")
	_assert(emitted[0], "购买后发射 loadout_changed（供 World 同步）")
	GameState.loadout_changed.disconnect(on_loadout)
	shop.free()


func _test_rest_night() -> void:
	print("[休息夜判定]")
	_assert(RestSystem.is_rest_night(5), "第 5 夜为休息夜")
	_assert(RestSystem.is_rest_night(10), "第 10 夜为休息夜")
	_assert(not RestSystem.is_rest_night(4), "第 4 夜非休息夜")
	_assert(not RestSystem.is_rest_night(0), "第 0 夜非休息夜")


func _test_rest_heal() -> void:
	print("[灯塔回血]")
	_reset_run()
	GameState.player_health = 40
	var healed: int = RestSystem.apply_rest()
	_assert(GameState.player_health == GameState.player_max_health, "回血至上限")
	_assert(healed == GameState.player_max_health - 40, "回复量正确")
	var healed2: int = RestSystem.apply_rest()
	_assert(healed2 == 0, "已满再休回复 0")


func _test_rest_try_apply() -> void:
	print("[休息夜进昼接线]")
	_reset_run()
	GameState.player_health = 50
	var skipped: int = RestSystem.try_apply_rest_for_night(4)
	_assert(skipped == 0, "非休息夜 try_apply=0")
	_assert(GameState.player_health == 50, "非休息夜不回血")
	var healed: int = RestSystem.try_apply_rest_for_night(5)
	_assert(healed == GameState.player_max_health - 50, "休息夜 try_apply 回血")
	_assert(GameState.player_health == GameState.player_max_health, "休息夜生命满")


func _test_economy_no_exploit() -> void:
	print("[经济闭环无刷币]")
	_reset_run()
	var paid: int = _paid("passive")
	var refund: int = _refund("passive")
	_assert(refund < paid, "退款(%d) < 原价(%d)，无无限刷币" % [refund, paid])
	# 完整闭环：给币 → 买(扣 paid) → 重铸(退 refund)，净变化 = -paid + refund（净减少，无刷币）
	GameState.add_tidecoins(1000)
	var shop: ShopManager = _SHOP.new()
	var before: int = GameState.tidecoins
	shop.buy({"id": "exp_sac", "kind": "passive", "cost": paid})
	_assert(GameState.tidecoins == before - paid, "购买扣 paid")
	GameState.reroll_passive("exp_sac")
	_assert(GameState.tidecoins == before - paid + refund, "买+重铸净 = -paid + refund（净减少）")
	shop.free()
