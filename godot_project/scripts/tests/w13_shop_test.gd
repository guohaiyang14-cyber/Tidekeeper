# ============================================================================
# W13ShopTest — 商店完善 + 经济闭环（逻辑 + 机检）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w13_shop_test.tscn
# 覆盖：购买扣实付价 / 槽满退款不扣币 / 重铸退 80% / 未持有退 0 /
#       休息夜判定 / 灯塔回血 / 经济闭环无刷币 /
#       商店 UI 置灰（潮币不足/达上限时商品行渲染即禁用）
# ============================================================================
extends Node

const _SHOP = preload("res://scripts/core/shop_manager.gd")
const _SHOP_UI = preload("res://scripts/core/shop_ui.gd")
const _UI = preload("res://scripts/ui/ui_chrome.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	RNG.set_seed(20261313)
	print("============================================================")
	print("W13 商店完善 + 经济闭环（逻辑 + 机检）")
	print("============================================================")
	_test_buy_deducts()
	_test_slot_full_no_deduct()
	_test_visit_limit_and_sold_out()
	_test_stale_item_rejected()
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
	await _test_shop_ui_disabled_rows()
	await _test_shop_panel_layout()
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
	var shop: ShopManager = _SHOP.new()
	shop.open_shop()
	# 2026-10-23：buy() 按 id 命中在售列表（自构任意 id 不再被接受），
	# 故先选一件「未持有」的在售被动当目标，再用其余被动把槽填满 → 必走槽满退款
	var target: Dictionary = {}
	for it in shop.get_current_items():
		if it.get("kind") == "passive" and not GameState.passive_slots.has(it.get("id", "")):
			target = it
			break
	_assert(not target.is_empty(), "商店有未持有的在售被动")
	if target.is_empty():
		shop.free()
		return
	for pid in ConfigLoader.get_all_passive_ids():
		if GameState.passive_slot_usage() >= 6:
			break
		if pid != target.get("id", "") and not GameState.passive_slots.has(pid):
			GameState.add_passive(pid)
	_assert(GameState.passive_slot_usage() == 6, "被动槽满 6")
	var before: int = GameState.tidecoins
	var ok: bool = shop.buy(target)
	_assert(not ok, "槽满购买失败")
	_assert(GameState.tidecoins == before, "槽满不扣币（退款）")
	shop.free()


## 2026-10-23 用户反馈「成长太快」→ 售出即下架 + 每次开店购买上限
func _test_visit_limit_and_sold_out() -> void:
	print("[售出下架 + 开店购买上限]")
	_reset_run()
	GameState.add_tidecoins(5000)
	var shop: ShopManager = _SHOP.new()
	shop.open_shop()
	var cap: int = ConfigLoader.get_shop_max_purchases()
	_assert(cap > 0, "开店购买上限 >0（%d）" % cap)
	var items: Array = shop.get_current_items()
	var n0: int = items.size()
	_assert(n0 > 0, "开商店有在售项（%d）" % n0)
	if n0 == 0:
		shop.free()
		return
	var first: Dictionary = items[0]
	var bought: bool = shop.buy(first)
	_assert(bought, "首件购买成功")
	_assert(not shop.get_current_items().has(first), "售出项已下架（不可回购）")
	_assert(shop.get_current_items().size() == n0 - 1, "在售数 -1（%d→%d）" % [n0, shop.get_current_items().size()])
	# 买到上限后再买必须失败
	var guard: int = 0
	while shop.get_purchases_this_visit() < cap and guard < 20:
		guard += 1
		var cur: Array = shop.get_current_items()
		if cur.is_empty():
			break
		shop.buy(cur[0])
	_assert(shop.get_purchases_this_visit() == cap, "本次开店买满上限（%d）" % shop.get_purchases_this_visit())
	var before: int = GameState.tidecoins
	var extra: Dictionary = {}
	var rest: Array = shop.get_current_items()
	if not rest.is_empty():
		extra = rest[0]
	if not extra.is_empty():
		_assert(not shop.buy(extra), "超过上限购买失败")
		_assert(GameState.tidecoins == before, "超限不扣币")
	# 重新开店后计数归零
	shop.open_shop()
	_assert(shop.get_purchases_this_visit() == 0, "重新开店计数归零")
	shop.free()


## 过期句柄拒绝：已售出商品的缓存引用再次 buy() 必须失败（2026-10-23 code-review P1：
## buy() 原先不校验在售，TestBot 循环开头缓存的 items 列表可在售出后重复购买，绕过「售出即下架」）
func _test_stale_item_rejected() -> void:
	print("[过期句柄拒绝]")
	_reset_run()
	GameState.add_tidecoins(5000)
	var shop: ShopManager = _SHOP.new()
	shop.open_shop()
	var items: Array = shop.get_current_items()
	if items.is_empty():
		shop.free()
		return
	var stale: Dictionary = items[0]
	_assert(shop.buy(stale), "首件购买成功（建立过期句柄）")
	var coins_after_first: int = GameState.tidecoins
	_assert(not shop.buy(stale), "已售出商品的过期句柄再次购买被拒绝")
	_assert(GameState.tidecoins == coins_after_first, "拒绝时不扣币")
	_assert(shop.get_purchases_this_visit() == 1, "拒绝时不计入本次购买数")
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
	shop.open_shop()
	# 2026-10-23：购买在售列表中的真实武器（buy() 按 id 命中在售）
	var w_item: Dictionary = {}
	for it in shop.get_current_items():
		if it.get("kind") == "weapon":
			w_item = it
			break
	_assert(not w_item.is_empty(), "商店含在售武器")
	var ok: bool = false
	if not w_item.is_empty():
		ok = shop.buy(w_item)
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
	shop.open_shop()
	# 2026-10-23：购买在售列表中的真实被动（buy() 按 id 命中在售）
	var item: Dictionary = {}
	for it in shop.get_current_items():
		if it.get("kind") == "passive":
			item = it
			break
	var pid: String = String(item.get("id", ""))
	_assert(pid != "", "商店含在售被动")
	var before: int = GameState.tidecoins
	shop.buy(item)
	_assert(GameState.tidecoins == before - paid, "购买扣 paid")
	GameState.reroll_passive(pid)
	_assert(GameState.tidecoins == before - paid + refund, "买+重铸净 = -paid + refund（净减少）")
	shop.free()


# ---- 商店 UI 置灰（2026-10-23 用户反馈「限制购买的应该在购买之后不能再交互了，而不是点击没有反应」）----
# 商品行在渲染时就地判定禁用原因并 disabled=true：潮币不足/达每次开店上限/槽满/已满级
func _test_shop_ui_disabled_rows() -> void:
	print("[商店 UI 置灰]")
	_reset_run()
	var shop: ShopManager = _SHOP.new()
	add_child(shop)
	var ui: ShopUI = _SHOP_UI.new()
	add_child(ui)
	await get_tree().process_frame
	ui.setup(shop)   # UI→Manager（潮币信号 / 上限查询）
	shop.setup(ui)   # Manager→UI（shop_opened / shop_items_changed 等）
	# ① 潮币不足：全部行置灰（点击前即可读，而非点击无反应）
	GameState.tidecoins = 0
	GameState.tidecoins_changed.emit(0)
	shop.open_shop()
	await get_tree().process_frame
	var rows: Array[Button] = _item_row_buttons(ui)
	_assert(rows.size() > 0, "商品行已渲染（%d 行）" % rows.size())
	var all_blocked: bool = true
	for btn in rows:
		if not btn.disabled:
			all_blocked = false
	_assert(all_blocked, "潮币不足时全部商品行置灰")
	# ② 给足潮币：恢复可点（_on_tidecoins_changed 重绘）
	GameState.add_tidecoins(1000)
	await get_tree().process_frame
	rows = _item_row_buttons(ui)
	var any_enabled: bool = false
	for btn in rows:
		if not btn.disabled:
			any_enabled = true
	_assert(any_enabled, "潮币足够时商品行恢复可点")
	# ③ 买到达每次开店上限：剩余行全部置灰（shop_items_changed 逐次重绘）
	var cap: int = shop.get_max_purchases()
	var bought: int = 0
	for it in shop.get_current_items().duplicate():
		if bought >= cap:
			break
		if shop.buy(it):
			bought += 1
	_assert(bought == cap, "已买到本次开店上限（%d 件）" % bought)
	await get_tree().process_frame
	rows = _item_row_buttons(ui)
	var remaining_all_disabled: bool = true
	for btn in rows:
		if not btn.disabled:
			remaining_all_disabled = false
	_assert(remaining_all_disabled, "达购买上限后剩余商品行全部置灰")
	# 清理（入树节点：queue_free + 一帧，避免退出段错误）
	ui.queue_free()
	shop.queue_free()
	await get_tree().process_frame


## 商品行按钮（VBox 下不带 shop_tail 标记的 Button；尾部融合/精炼/重铸控件除外）
func _item_row_buttons(ui: ShopUI) -> Array[Button]:
	var rows: Array[Button] = []
	var vbox: Variant = ui.get("_vbox")
	if vbox == null:
		return rows
	for child in (vbox as VBoxContainer).get_children():
		if child is Button and not child.has_meta("shop_tail"):
			rows.append(child as Button)
	return rows


## 商店面板铺满整屏（2026-10-26 用户反馈「这个列表太窄了，可以铺满页面」）
## 机检口径：面板宽 ≥ 视口宽 - 2×MARGIN，高 ≥ 视口高 - 120（顶部 HUD 让位），
## 且商品 VBox 的内容宽与面板内宽一致（否则行仍会缩成窄条）
func _test_shop_panel_layout() -> void:
	print("[商店面板铺满]")
	_reset_run()
	var shop: ShopManager = _SHOP.new()
	add_child(shop)
	var ui: ShopUI = _SHOP_UI.new()
	add_child(ui)
	await get_tree().process_frame
	ui.setup(shop)
	shop.setup(ui)
	shop.open_shop()
	await get_tree().process_frame
	var panel: Panel = ui.find_child("ShopPanel", false, false) as Panel
	_assert(panel != null, "商店面板节点存在（ShopPanel）")
	if panel == null:
		ui.queue_free()
		shop.queue_free()
		await get_tree().process_frame
		return
	var want_w: float = _UI.VIEW_W - _UI.MARGIN * 2.0
	_assert(absf(panel.size.x - want_w) < 1.0,
		"面板宽铺满（%.0f ≈ 视口 %.0f - 2×%.0f）" % [panel.size.x, _UI.VIEW_W, _UI.MARGIN])
	_assert(panel.size.y >= _UI.VIEW_H - 120.0,
		"面板高占满（%.0f ≥ %.0f）" % [panel.size.y, _UI.VIEW_H - 120.0])
	_assert(panel.size.x / _UI.VIEW_W >= 0.95,
		"面板占视口宽 ≥95%%（实际 %.1f%%）" % (panel.size.x / _UI.VIEW_W * 100.0))
	_assert(absf(panel.position.x - _UI.MARGIN) < 0.01 and panel.position.y <= 60.01,
		"面板左边距 = %.0f、顶部让位 HUD（y=%.0f）" % [panel.position.x, panel.position.y])
	var vbox: VBoxContainer = ui.get("_vbox") as VBoxContainer
	_assert(vbox != null, "商品 VBox 存在")
	if vbox != null:
		_assert(vbox.custom_minimum_size.x >= want_w - _UI.MARGIN * 2.0 - 1.0,
			"商品行内容宽 ≥ 面板内宽（%.0f ≥ %.0f）" % [vbox.custom_minimum_size.x, want_w - _UI.MARGIN * 2.0])
	var rows: Array[Button] = _item_row_buttons(ui)
	_assert(rows.size() > 0, "商品行已渲染（%d 行）" % rows.size())
	if not rows.is_empty():
		var wide: bool = rows[0].size.x >= want_w - _UI.MARGIN * 4.0
		_assert(wide, "商品行铺满（首行宽 %.0f ≥ %.0f）" % [rows[0].size.x, want_w - _UI.MARGIN * 4.0])
	ui.queue_free()
	shop.queue_free()
	await get_tree().process_frame
