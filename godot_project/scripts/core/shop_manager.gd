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

## 当前在售列表（每项：{id, name, kind, cost}）
var _items: Array[Dictionary] = []

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


## 开商店：构建在售列表并发信号
func open_shop() -> void:
	_items = _build_items()
	print("[ShopManager] 开商店：%d 件在售" % _items.size())
	shop_opened.emit(_items)


## 关闭商店（清列表）
func close_shop() -> void:
	_items = []


## 当前在售列表（UI / 测试用）
func get_current_items() -> Array[Dictionary]:
	return _items


## 购买一件；成功返回 true
func buy(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var cost: int = int(item.get("cost", 0))
	var kind: String = item.get("kind", "")
	var id: String = item.get("id", "")
	if id == "":
		return false
	if not GameState.spend_tidecoins(cost):
		purchase_failed.emit("insufficient_funds")
		return false
	var ok: bool
	if kind == "weapon":
		ok = GameState.add_weapon(id)
	else:
		ok = GameState.add_passive(id)
	if not ok:
		# 槽满 / 重复被动 → 退款，不扣币
		GameState.add_tidecoins(cost)
		purchase_failed.emit("slot_full")
		return false
	purchase_made.emit(item)
	return true


# ============================================================================
# 内部
# ============================================================================

## 构建在售列表：全部武器 + 全部被动，RNG 洗牌后取前 6 件（≥4）
func _build_items() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for wid in ConfigLoader.get_all_weapon_ids():
		var w: Dictionary = ConfigLoader.get_weapon(wid)
		if w.is_empty():
			continue
		candidates.append({
			"id": wid,
			"name": w.get("name", wid),
			"kind": "weapon",
			"cost": _weapon_cost(),
		})
	for pid in ConfigLoader.get_all_passive_ids():
		var p: Dictionary = ConfigLoader.get_passive(pid)
		if p.is_empty():
			continue
		candidates.append({
			"id": pid,
			"name": p.get("name", pid),
			"kind": "passive",
			"cost": _passive_cost(),
		})
	_shuffle(candidates)
	var take: int = mini(6, candidates.size())
	return candidates.slice(0, take)


## 确定性洗牌（RNG）
func _shuffle(arr: Array[Dictionary]) -> void:
	var n: int = arr.size()
	for i in n:
		var j: int = RNG.randi_range(0, n - 1)
		var tmp: Dictionary = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 武器单价（config 折扣后）
func _weapon_cost() -> int:
	var meta: Dictionary = ConfigLoader.get_weapon_shop_meta()
	return _discounted(int(meta.get("cost", 30)), float(meta.get("discount", 0.2)))


## 被动单价（config 折扣后）
func _passive_cost() -> int:
	var meta: Dictionary = ConfigLoader.get_passive_shop_meta()
	return _discounted(int(meta.get("cost", 20)), float(meta.get("discount", 0.2)))


func _discounted(base: int, discount: float) -> int:
	return maxi(1, roundi(float(base) * (1.0 - discount)))
