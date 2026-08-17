# ============================================================================
# ShopUI — 商店界面（W4 雏形 + W10 进化 + W11 精炼 + W13 重铸回收）
# 职责：订阅 ShopManager；融合/精炼/重铸按钮调用 Evolution / Refine / GameState.reroll_*
# 红线：潮币/槽位经 GameState / ShopManager；重铸后 loadout_changed → World 同步武器实例
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
var _refine_label: Label
var _reroll_label: Label
var _fuse_btns: Array[Button] = []
var _refine_btns: Array[Button] = []
var _reroll_btns: Array[Button] = []


func _ready() -> void:
	visible = false
	_connect_manager()
	_evo_label = Label.new()
	_evo_label.add_theme_font_size_override("font_size", 16)
	_evo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_vbox.add_child(_evo_label)
	_refine_label = Label.new()
	_refine_label.add_theme_font_size_override("font_size", 16)
	_refine_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	_vbox.add_child(_refine_label)
	_reroll_label = Label.new()
	_reroll_label.add_theme_font_size_override("font_size", 16)
	_reroll_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.7))
	_vbox.add_child(_reroll_label)
	_skip_btn = Button.new()
	_skip_btn.text = "继续下一夜 (Q)"
	_skip_btn.pressed.connect(func(): skip_requested.emit())
	_vbox.add_child(_skip_btn)
	if not GameState.evolution_items_changed.is_connected(_on_evo_items_changed):
		GameState.evolution_items_changed.connect(_on_evo_items_changed)
	if not GameState.refine_essence_changed.is_connected(_on_refine_essence_changed):
		GameState.refine_essence_changed.connect(_on_refine_essence_changed)


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
	for b in _refine_btns:
		if is_instance_valid(b):
			b.queue_free()
	_refine_btns.clear()
	for b in _reroll_btns:
		if is_instance_valid(b):
			b.queue_free()
	_reroll_btns.clear()
	if _skip_btn != null and _skip_btn.get_parent() == _vbox:
		_vbox.remove_child(_skip_btn)
	if _evo_label != null and _evo_label.get_parent() == _vbox:
		_vbox.remove_child(_evo_label)
	if _refine_label != null and _refine_label.get_parent() == _vbox:
		_vbox.remove_child(_refine_label)
	if _reroll_label != null and _reroll_label.get_parent() == _vbox:
		_vbox.remove_child(_reroll_label)
	for child in _vbox.get_children():
		if child != _coin_label:
			child.queue_free()


func _place_tail_controls() -> void:
	_refresh_fusion()


func _refresh_fusion() -> void:
	if not visible:
		return
	# 重建尾部：摘尾部控件 → 清旧钮 → 重挂（融合 + 精炼 + 重铸 + 标签 + 跳过）
	if _skip_btn != null and _skip_btn.get_parent() == _vbox:
		_vbox.remove_child(_skip_btn)
	if _evo_label != null and _evo_label.get_parent() == _vbox:
		_vbox.remove_child(_evo_label)
	if _refine_label != null and _refine_label.get_parent() == _vbox:
		_vbox.remove_child(_refine_label)
	if _reroll_label != null and _reroll_label.get_parent() == _vbox:
		_vbox.remove_child(_reroll_label)
	for b in _fuse_btns:
		if is_instance_valid(b):
			b.queue_free()
	_fuse_btns.clear()
	for b in _refine_btns:
		if is_instance_valid(b):
			b.queue_free()
	_refine_btns.clear()
	for b in _reroll_btns:
		if is_instance_valid(b):
			b.queue_free()
	_reroll_btns.clear()
	_refresh_fusion_buttons_only()
	_refresh_refine_buttons_only()
	_refresh_reroll_buttons_only()
	if _evo_label != null:
		_vbox.add_child(_evo_label)
	if _refine_label != null:
		_vbox.add_child(_refine_label)
	if _reroll_label != null:
		_vbox.add_child(_reroll_label)
	if _skip_btn != null:
		_vbox.add_child(_skip_btn)


func _refresh_fusion_buttons_only() -> void:
	if _evo_label != null:
		_evo_label.text = "进化道具：%d" % GameState.evolution_items
	var ready: Array[String] = EvolutionSystem.list_ready()
	for wid in ready:
		var path: Dictionary = EvolutionSystem.evolution_path(wid)
		var btn: Button = Button.new()
		btn.text = "融合 · %s → %s" % [
			ConfigLoader.get_weapon(wid).get("name", wid),
			path.get("evolved_name", "?"),
		]
		btn.pressed.connect(_on_fuse_pressed.bind(wid))
		_vbox.add_child(btn)
		_fuse_btns.append(btn)


func _refresh_refine_buttons_only() -> void:
	if _refine_label != null:
		_refine_label.text = "淬炼精华：%d（II 上限 %d）" % [GameState.refine_essence, GameState.MAX_REFINE_II]
	var ready: Array[String] = RefineSystem.list_ready()
	for wid in ready:
		var path: Dictionary = RefineSystem.refine_path(wid)
		var target: int = RefineSystem.next_refine_tier(wid)
		var cost: int = int(RefineSystem.get_rules().get("tier_%d_cost" % target, 1 if target == 1 else 2))
		# MVP 只应用 dps_mult；按钮展示本阶倍率与相对未精炼的累积倍率，避免行为 desc 误导
		var step_mult: float = ConfigLoader.get_refine_multiplier(wid, target) / ConfigLoader.get_refine_multiplier(wid, target - 1)
		var cum_mult: float = ConfigLoader.get_refine_multiplier(wid, target)
		var btn: Button = Button.new()
		btn.text = "精炼 T%d · %s → %s（本阶×%.2f / 累积×%.2f，精华 %d）" % [
			target,
			ConfigLoader.get_weapon(wid).get("name", wid),
			path.get("name", "?"),
			step_mult,
			cum_mult,
			cost,
		]
		btn.pressed.connect(_on_refine_pressed.bind(wid))
		_vbox.add_child(btn)
		_refine_btns.append(btn)


func _refresh_reroll_buttons_only() -> void:
	var ratio_pct: int = int(round(ConfigLoader.get_shop_refund_ratio("weapon") * 100.0))
	if _reroll_label != null:
		_reroll_label.text = "重铸回收（退 %d%% 实付潮币；至少保留 1 把武器）" % ratio_pct
	var can_reroll_weapon: bool = GameState.weapon_slots.size() > 1
	for wid in GameState.weapon_slots:
		var paid: int = ConfigLoader.get_shop_paid_cost("weapon")
		var refund: int = roundi(float(paid) * ConfigLoader.get_shop_refund_ratio("weapon"))
		var btn: Button = Button.new()
		if can_reroll_weapon:
			btn.text = "重铸 · 武器 %s（退 %d）" % [ConfigLoader.get_weapon(wid).get("name", wid), refund]
			btn.pressed.connect(_on_reroll_weapon_pressed.bind(wid))
		else:
			btn.text = "重铸 · 武器 %s（需保留末把）" % ConfigLoader.get_weapon(wid).get("name", wid)
			btn.disabled = true
		_vbox.add_child(btn)
		_reroll_btns.append(btn)
	for pid in GameState.passive_slots:
		var paid_p: int = ConfigLoader.get_shop_paid_cost("passive")
		var refund_p: int = roundi(float(paid_p) * ConfigLoader.get_shop_refund_ratio("passive"))
		var btn_p: Button = Button.new()
		btn_p.text = "重铸 · 被动 %s（退 %d）" % [ConfigLoader.get_passive(pid).get("name", pid), refund_p]
		btn_p.pressed.connect(_on_reroll_passive_pressed.bind(pid))
		_vbox.add_child(btn_p)
		_reroll_btns.append(btn_p)


func _on_fuse_pressed(weapon_id: String) -> void:
	if EvolutionSystem.fuse(weapon_id):
		evolution_fused.emit(weapon_id)
		_refresh_fusion()


func _on_refine_pressed(weapon_id: String) -> void:
	# 伤害实时读 GameState.refine_tiers，无需通知 World 重建实例
	if RefineSystem.refine(weapon_id) > 0:
		_refresh_fusion()


func _on_reroll_weapon_pressed(weapon_id: String) -> void:
	if GameState.reroll_weapon(weapon_id) > 0:
		_refresh_coins()
		_refresh_fusion()


func _on_reroll_passive_pressed(passive_id: String) -> void:
	if GameState.reroll_passive(passive_id) > 0:
		_refresh_coins()
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


func _on_refine_essence_changed(_total: int) -> void:
	if _refine_label != null:
		_refine_label.text = "淬炼精华：%d（II 上限 %d）" % [GameState.refine_essence, GameState.MAX_REFINE_II]
	if visible:
		_refresh_fusion()


func _refresh_coins() -> void:
	if _coin_label != null:
		_coin_label.text = "潮币：%d" % GameState.tidecoins


## 关闭商店界面（由 World 在跳过昼时调用）
func close() -> void:
	visible = false
