# ============================================================================
# ShopUI — 商店界面（W4 雏形 + W10 进化融合入口）
# 职责：订阅 ShopManager 信号，渲染在售列表；融合按钮调用 EvolutionSystem.fuse
# 红线：仅消费 ShopManager / EvolutionSystem，不自行改潮币/槽位
# ============================================================================
class_name ShopUI
extends Control

var _shop_manager: ShopManager

## 玩家请求跳过昼（继续下一夜）；World 监听后关店并进夜
signal skip_requested()
## 融合成功后通知 World 同步武器实例
signal evolution_fused(weapon_id: String)

@onready var _vbox: VBoxContainer = $VBox
@onready var _coin_label: Label = $VBox/CoinLabel
var _skip_btn: Button
var _evo_label: Label
var _fuse_btns: Array[Button] = []


func _ready() -> void:
	visible = false
	_connect_manager()
	_evo_label = Label.new()
	_evo_label.add_theme_font_size_override("font_size", 16)
	_evo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_vbox.add_child(_evo_label)
	_skip_btn = Button.new()
	_skip_btn.text = "继续下一夜 (Q)"
	_skip_btn.pressed.connect(func(): skip_requested.emit())
	_vbox.add_child(_skip_btn)
	if not GameState.evolution_items_changed.is_connected(_on_evo_items_changed):
		GameState.evolution_items_changed.connect(_on_evo_items_changed)


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


func _on_shop_opened(items: Array) -> void:
	visible = true
	_render(items)
	_refresh_coins()
	_refresh_fusion()


func _on_purchase_made(_item: Dictionary) -> void:
	_refresh_coins()
	_refresh_fusion()


func _on_purchase_failed(_reason: String) -> void:
	_refresh_coins()


func _render(items: Array) -> void:
	_clear_dynamic_rows()
	for item in items:
		var btn: Button = Button.new()
		var kind_label: String = "武器" if item.get("kind") == "weapon" else "被动"
		btn.text = "%s · %s  (潮币 %d)" % [item.get("name", "?"), kind_label, int(item.get("cost", 0))]
		btn.pressed.connect(_on_item_pressed.bind(item))
		_vbox.add_child(btn)
	_place_tail_controls()


func _clear_dynamic_rows() -> void:
	for b in _fuse_btns:
		if is_instance_valid(b):
			b.queue_free()
	_fuse_btns.clear()
	if _skip_btn != null and _skip_btn.get_parent() == _vbox:
		_vbox.remove_child(_skip_btn)
	if _evo_label != null and _evo_label.get_parent() == _vbox:
		_vbox.remove_child(_evo_label)
	for child in _vbox.get_children():
		if child != _coin_label:
			child.queue_free()


func _place_tail_controls() -> void:
	_refresh_fusion_buttons_only()
	if _evo_label != null:
		_vbox.add_child(_evo_label)
	if _skip_btn != null:
		_vbox.add_child(_skip_btn)


func _refresh_fusion() -> void:
	if not visible:
		return
	# 重建融合钮：摘尾部 → 清旧融合钮 → 重挂
	if _skip_btn != null and _skip_btn.get_parent() == _vbox:
		_vbox.remove_child(_skip_btn)
	if _evo_label != null and _evo_label.get_parent() == _vbox:
		_vbox.remove_child(_evo_label)
	for b in _fuse_btns:
		if is_instance_valid(b):
			b.queue_free()
	_fuse_btns.clear()
	_refresh_fusion_buttons_only()
	if _evo_label != null:
		_vbox.add_child(_evo_label)
	if _skip_btn != null:
		_vbox.add_child(_skip_btn)


func _refresh_fusion_buttons_only() -> void:
	if _evo_label != null:
		_evo_label.text = "进化道具：%d" % GameState.evolution_items
	var ready: Array[String] = EvolutionSystem.list_ready()
	for wid in ready:
		var path: Dictionary = EvolutionSystem.get_path(wid)
		var btn: Button = Button.new()
		btn.text = "融合 · %s → %s" % [
			ConfigLoader.get_weapon(wid).get("name", wid),
			path.get("evolved_name", "?"),
		]
		btn.pressed.connect(_on_fuse_pressed.bind(wid))
		_vbox.add_child(btn)
		_fuse_btns.append(btn)


func _on_fuse_pressed(weapon_id: String) -> void:
	if EvolutionSystem.fuse(weapon_id):
		evolution_fused.emit(weapon_id)
		_refresh_fusion()


func _on_item_pressed(item: Dictionary) -> void:
	if _shop_manager != null:
		_shop_manager.buy(item)


func _on_tidecoins_changed(_total: int) -> void:
	_refresh_coins()


func _on_evo_items_changed(_total: int) -> void:
	if _evo_label != null:
		_evo_label.text = "进化道具：%d" % GameState.evolution_items
	if visible:
		_refresh_fusion()


func _refresh_coins() -> void:
	if _coin_label != null:
		_coin_label.text = "潮币：%d" % GameState.tidecoins


## 关闭商店界面（由 World 在跳过昼时调用）
func close() -> void:
	visible = false
