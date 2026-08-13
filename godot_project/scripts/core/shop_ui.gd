# ============================================================================
# ShopUI — 商店界面（W4 雏形）
# 职责：订阅 ShopManager 信号，渲染在售列表（名称 + 价格）与潮币余额；
#       点击购买 → ShopManager.buy(item)；购买结果反馈。
# 红线：仅消费 ShopManager 逻辑，不自行改潮币/槽位
# 架构：UI 子节点（Control）；setup 注入 ShopManager
# ============================================================================
class_name ShopUI
extends Control

var _shop_manager: ShopManager

@onready var _vbox: VBoxContainer = $VBox
@onready var _coin_label: Label = $VBox/CoinLabel


func _ready() -> void:
	visible = false
	# ShopManager 由 World 在 _ready 中通过 setup() 注入（正式路径）。
	# 不在此做脆弱的双跳节点回溯（get_parent().get_parent()），避免场景树结构调整即断裂。
	_connect_manager()


## 注入 ShopManager（由 World 调用）
func setup(sm: ShopManager) -> void:
	_shop_manager = sm
	_connect_manager()


func _connect_manager() -> void:
	if _shop_manager == null:
		return
	if not GameState.tidecoins_changed.is_connected(_on_tidecoins_changed):
		GameState.tidecoins_changed.connect(_on_tidecoins_changed)
	_refresh_coins()


# ---- ShopManager 信号回调 ----

func _on_shop_opened(items: Array) -> void:
	visible = true
	_render(items)
	_refresh_coins()


func _on_purchase_made(_item: Dictionary) -> void:
	_refresh_coins()


func _on_purchase_failed(_reason: String) -> void:
	_refresh_coins()


# ---- 渲染 ----

func _render(items: Array) -> void:
	# 清空旧按钮（保留 CoinLabel）
	for child in _vbox.get_children():
		if child != _coin_label:
			child.queue_free()
	for item in items:
		var btn: Button = Button.new()
		var kind_label: String = "武器" if item.get("kind") == "weapon" else "被动"
		btn.text = "%s · %s  (潮币 %d)" % [item.get("name", "?"), kind_label, int(item.get("cost", 0))]
		btn.pressed.connect(_on_item_pressed.bind(item))
		_vbox.add_child(btn)


func _on_item_pressed(item: Dictionary) -> void:
	if _shop_manager != null:
		_shop_manager.buy(item)


func _on_tidecoins_changed(_total: int) -> void:
	_refresh_coins()


func _refresh_coins() -> void:
	if _coin_label != null:
		_coin_label.text = "潮币：%d" % GameState.tidecoins


## 关闭商店界面（由 World 在跳过昼时调用）
func close() -> void:
	visible = false
