# ============================================================================
# ShopManager — 商店逻辑（W4 雏形）
# 职责：每夜开商店时从 config 生成 ≥4 件可购项（武器 + 被动，折扣 20%）；
#       处理购买：扣潮币（GameState.spend_tidecoins）→ add_weapon / add_passive；
#       槽满 / 潮币不足则失败（并退款）。UI 仅消费本逻辑（ShopUI 订阅信号）。
# 红线：数值来自 config（weapons/passives metadata.shop），禁止硬编码；随机走 RNG
# 架构：World 子节点；setup 注入 ShopUI（可选），_ready 自动解析父节点 ShopUI
# ============================================================================
class_name ShopManager
extends Node

signal shop_opened(items: Array)
signal purchase_made(item: Dictionary)
signal purchase_failed(reason: String)
## 已售出/已达上限后刷新在售列表（只重绘，不抢焦点）
## 2026-10-23 code-review：参数类型化为 Array[Dictionary]（与 _items 一致；shop_opened 保持
## 无类型 Array——UI 侧 _on_shop_opened 传入的就是未类型化数组，双向都会破坏）
signal shop_items_changed(items: Array[Dictionary])

## 当前在售列表（每项：{id, name, kind, cost}）
var _items: Array[Dictionary] = []

## 本次开店已购买件数（2026-10-23 用户反馈「成长太快」：加每次开店购买上限）
var _purchases_this_visit: int = 0

var _shop_ui: ShopUI


func _ready() -> void:
	if _shop_ui == null:
		var parent: Node = get_parent()
		if parent != null:
			_shop_ui = parent.get_node_or_null("UI/ShopUI") as ShopUI
	_connect_ui()


## 注入 ShopUI（World 调用）
func setup(ui: ShopUI) -> void:
	_shop_ui = ui
	_connect_ui()


func _connect_ui() -> void:
	if _shop_ui == null:
		return
	if not shop_opened.is_connected(_shop_ui._on_shop_opened):
		shop_opened.connect(_shop_ui._on_shop_opened)
	if not purchase_made.is_connected(_shop_ui._on_purchase_made):
		purchase_made.connect(_shop_ui._on_purchase_made)
	if not purchase_failed.is_connected(_shop_ui._on_purchase_failed):
		purchase_failed.connect(_shop_ui._on_purchase_failed)
	if _shop_ui.has_method("_on_shop_items_changed") and not shop_items_changed.is_connected(_shop_ui._on_shop_items_changed):
		shop_items_changed.connect(_shop_ui._on_shop_items_changed)


## 开商店：构建在售列表并发信号
func open_shop() -> void:
	_purchases_this_visit = 0
	_items = _build_items()
	print("[ShopManager] 开商店：%d 件在售（本次上限 %d 件）" % [_items.size(), get_max_purchases()])
	shop_opened.emit(_items)


## 关闭商店（清列表）
func close_shop() -> void:
	_items = []
	_purchases_this_visit = 0


## 本次开店已购买件数（机检/UI 用）
func get_purchases_this_visit() -> int:
	return _purchases_this_visit


## 本次开店购买上限（upgrade.json shop.max_purchases_per_visit）
func get_max_purchases() -> int:
	return ConfigLoader.get_shop_max_purchases()


## 当前在售列表（UI / 测试用）
func get_current_items() -> Array[Dictionary]:
	return _items


## 购买一件；成功返回 true
func buy(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var cap: int = get_max_purchases()
	if cap > 0 and _purchases_this_visit >= cap:
		purchase_failed.emit("visit_limit")
		return false
	var id: String = item.get("id", "")
	if id == "":
		return false
	# 过期句柄防护（2026-10-23 code-review P1）：按 id 在「当前在售列表」中查找。
	# 调用方可能持有已售出项的缓存引用或自构字典——整体相等性判断会漏判/误伤；
	# id 在在售列表中唯一，售出即 erase → 旧句柄/不在售的 id 自然被拒（sold_out）
	var live: Dictionary
	for it in _items:
		if String(it.get("id", "")) == id:
			live = it
			break
	if live.is_empty():
		purchase_failed.emit("sold_out")
		return false
	# 成交价/类型以在售列表为准（防调用方篡改 cost；与 config 单价一致）
	var cost: int = int(live.get("cost", 0))
	var kind: String = String(live.get("kind", ""))
	if not GameState.spend_tidecoins(cost):
		purchase_failed.emit("insufficient_funds")
		return false
	var ok: bool
	if kind == "weapon":
		ok = GameState.add_weapon(id)
	else:
		ok = GameState.add_passive(id)
	if not ok:
		# 槽满 / 已满级 → 退款，不扣币
		GameState.add_tidecoins(cost)
		purchase_failed.emit("slot_full")
		return false
	_purchases_this_visit += 1
	# 售出即下架（一件商品一次开店只卖一次），并刷新在售列表
	_items.erase(live)
	shop_items_changed.emit(_items)
	purchase_made.emit(live)
	# add_weapon / add_passive 成功时已 emit loadout_changed
	return true


# ============================================================================
# 内部
# ============================================================================

## 构建在售列表：全部武器 + 全部被动，分别洗牌后保底各 ≥1 件，交替补齐至 6 件（≥4）
func _build_items() -> Array[Dictionary]:
	var weapons: Array[Dictionary] = []
	for wid in ConfigLoader.get_all_weapon_ids():
		var w: Dictionary = ConfigLoader.get_weapon(wid)
		if w.is_empty():
			continue
		weapons.append({
			"id": wid,
			"name": w.get("name", wid),
			"kind": "weapon",
			"cost": _weapon_cost(),
		})
	var passives: Array[Dictionary] = []
	for pid in ConfigLoader.get_all_passive_ids():
		var p: Dictionary = ConfigLoader.get_passive(pid)
		if p.is_empty():
			continue
		passives.append({
			"id": pid,
			"name": p.get("name", pid),
			"kind": "passive",
			"cost": _passive_cost(),
		})
	_shuffle(weapons)
	_shuffle(passives)
	var items: Array[Dictionary] = []
	var iw: int = 0
	var ip: int = 0
	# 保底：武器/被动至少各 1 件（§3.2 商店须可买到武器与被动），顺带改善商店 UX
	if not weapons.is_empty():
		items.append(weapons[iw]); iw += 1
	if not passives.is_empty():
		items.append(passives[ip]); ip += 1
	# 交替补齐至 6 件，保持武器/被动比例均衡
	var want: int = mini(6, weapons.size() + passives.size())
	while items.size() < want and (iw < weapons.size() or ip < passives.size()):
		if iw < weapons.size() and (ip >= passives.size() or items.size() % 2 == 0):
			items.append(weapons[iw]); iw += 1
		elif ip < passives.size():
			items.append(passives[ip]); ip += 1
		else:
			break
	return items


## 确定性 Fisher–Yates 洗牌（RNG）
func _shuffle(arr: Array[Dictionary]) -> void:
	var n: int = arr.size()
	for i in range(n - 1, 0, -1):
		var j: int = RNG.randi_range(0, i)
		var tmp: Dictionary = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 武器单价（config 折扣后）
func _weapon_cost() -> int:
	return ConfigLoader.get_shop_paid_cost("weapon")


## 被动单价（config 折扣后）
func _passive_cost() -> int:
	return ConfigLoader.get_shop_paid_cost("passive")
