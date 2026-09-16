# ============================================================================
# ShopUI — 商店界面（W4 雏形 + W10 进化 + W11 精炼 + W13 重铸 + A6 排版）
# 职责：订阅 ShopManager；融合/精炼/重铸按钮调用 Evolution / Refine / GameState.reroll_*
# 红线：潮币/槽位经 GameState / ShopManager；重铸后 loadout_changed → World 同步武器实例
# A6：右侧面板 + Scroll 商品区 + 钉底跳过/收工；kind/文案走 i18n；开店 grab_focus 跳过
# ============================================================================
class_name ShopUI
extends Control

const _UI := preload("res://scripts/ui/ui_chrome.gd")

var _shop_manager: ShopManager

## 玩家请求跳过昼（继续下一夜）；World 监听后关店并进夜
signal skip_requested()
## 抉择之昼「点亮信号」提前收工；World 监听后按进度结算（非通关）
signal retire_requested()
## 融合成功后通知 World 同步武器实例
signal evolution_fused(weapon_id: String)

## 滚动区内动态行（商品 / 融合 / 精炼 / 重铸）
var _vbox: VBoxContainer
var _coin_label: Label
var _skip_btn: Button
var _retire_btn: Button
var _retire_confirm: ConfirmationDialog
var _evo_label: Label
var _refine_label: Label
var _reroll_label: Label
var _fuse_btns: Array[Button] = []
var _refine_btns: Array[Button] = []
var _reroll_btns: Array[Button] = []
var _panel: Panel
var _layout_built: bool = false


func _ready() -> void:
	visible = false
	_build_layout()
	_connect_manager()
	_build_retire_confirm()
	if not LanguageSystem.language_changed.is_connected(_on_language_changed):
		LanguageSystem.language_changed.connect(_on_language_changed)
	if not GameState.evolution_items_changed.is_connected(_on_evo_items_changed):
		GameState.evolution_items_changed.connect(_on_evo_items_changed)
	if not GameState.refine_essence_changed.is_connected(_on_refine_essence_changed):
		GameState.refine_essence_changed.connect(_on_refine_essence_changed)


func _build_layout() -> void:
	if _layout_built:
		return
	_layout_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 兼容旧场景 / 机检预挂的 VBox+CoinLabel：抽出潮币标签后释放
	var legacy_coin: Label = null
	var legacy := get_node_or_null("VBox")
	if legacy != null:
		var c: Node = legacy.get_node_or_null("CoinLabel")
		if c is Label:
			legacy_coin = c as Label
			legacy.remove_child(legacy_coin)
		remove_child(legacy)
		legacy.queue_free()

	_panel = _UI.make_panel()
	_panel.name = "ShopPanel"
	_panel.position = Vector2(_UI.VIEW_W - 460.0, 72.0)
	_panel.size = Vector2(440.0, _UI.VIEW_H - 100.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = _UI.MARGIN
	outer.offset_right = -_UI.MARGIN
	outer.offset_top = _UI.MARGIN
	outer.offset_bottom = -_UI.MARGIN
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	if legacy_coin != null:
		_coin_label = legacy_coin
	else:
		_coin_label = Label.new()
	_coin_label.name = "CoinLabel"
	_coin_label.add_theme_font_size_override("font_size", 20)
	_coin_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	outer.add_child(_coin_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ScrollContainer 子节点默认按最小宽度布局；显式给足面板内容宽，避免长文案按钮偏窄
	_vbox.custom_minimum_size = Vector2(_panel.size.x - _UI.MARGIN * 2.0, 0.0)
	_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_vbox)

	_evo_label = Label.new()
	_evo_label.add_theme_font_size_override("font_size", _UI.FONT_BODY)
	_evo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_evo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_refine_label = Label.new()
	_refine_label.add_theme_font_size_override("font_size", _UI.FONT_BODY)
	_refine_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	_refine_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_reroll_label = Label.new()
	_reroll_label.add_theme_font_size_override("font_size", _UI.FONT_BODY)
	_reroll_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.7))
	_reroll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	outer.add_child(footer)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipButton"
	_UI.style_button(_skip_btn)
	_skip_btn.text = LanguageSystem.localize("ui.shop.skip")
	_skip_btn.pressed.connect(func(): skip_requested.emit())
	footer.add_child(_skip_btn)

	_retire_btn = Button.new()
	_retire_btn.name = "RetireButton"
	_UI.style_button(_retire_btn)
	_retire_btn.text = LanguageSystem.localize("ui.shop.retire")
	_retire_btn.pressed.connect(_on_retire_pressed)
	footer.add_child(_retire_btn)

	_refresh_coins()


func _build_retire_confirm() -> void:
	_retire_confirm = ConfirmationDialog.new()
	_retire_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_retire_confirm.confirmed.connect(_on_retire_confirmed)
	add_child(_retire_confirm)
	_refresh_retire_confirm_text()


func _refresh_retire_confirm_text() -> void:
	if _retire_confirm == null:
		return
	_retire_confirm.title = LanguageSystem.localize("ui.shop.retire_confirm_title")
	_retire_confirm.dialog_text = LanguageSystem.localize("ui.shop.retire_confirm_body")
	_retire_confirm.ok_button_text = LanguageSystem.localize("ui.shop.retire_confirm_ok")
	_retire_confirm.cancel_button_text = LanguageSystem.localize("ui.shop.retire_confirm_cancel")


func _on_retire_pressed() -> void:
	if _retire_confirm == null:
		_on_retire_confirmed()
		return
	_refresh_retire_confirm_text()
	_retire_confirm.popup_centered()


func _on_retire_confirmed() -> void:
	retire_requested.emit()


## 机检：跳过确认框直接发出 retire_requested（等同玩家点确认）
func emit_retire_confirmed_for_test() -> void:
	_on_retire_confirmed()


func _on_language_changed(_lang: String) -> void:
	if _skip_btn != null:
		_skip_btn.text = LanguageSystem.localize("ui.shop.skip")
	if _retire_btn != null:
		_retire_btn.text = LanguageSystem.localize("ui.shop.retire")
	_refresh_retire_confirm_text()
	_refresh_coins()
	if visible:
		_refresh_fusion()


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
	if _skip_btn != null:
		_skip_btn.grab_focus()


## 开店后 Skip 是否持焦（验收 1.1.5 / TestBot）
func has_skip_focus() -> bool:
	return _skip_btn != null and _skip_btn.has_focus()


func _on_purchase_made(_item: Dictionary) -> void:
	_refresh_coins()
	_refresh_fusion()


func _on_purchase_failed(_reason: String) -> void:
	_refresh_coins()


func _render(items: Array) -> void:
	_clear_dynamic_rows()
	for item in items:
		var btn: Button = Button.new()
		_UI.style_button(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text = _item_row_text(item)
		btn.pressed.connect(_on_item_pressed.bind(item))
		_vbox.add_child(btn)
	_place_tail_controls()


func _item_row_text(item: Dictionary) -> String:
	var kind: String = String(item.get("kind", ""))
	var kind_key: String = (
		"ui.shop.kind_weapon" if kind == "weapon" else "ui.shop.kind_passive"
	)
	var item_id: String = String(item.get("id", ""))
	var fallback: String = String(item.get("name", item_id if item_id != "" else "?"))
	var display: String = fallback
	if kind == "weapon" and item_id != "":
		display = LanguageSystem.localize_config_name("weapon", item_id, fallback)
	elif kind == "passive" and item_id != "":
		display = LanguageSystem.localize_config_name("passive", item_id, fallback)
	return LanguageSystem.localizef("ui.shop.item_row", [
		display,
		LanguageSystem.localize(kind_key),
		int(item.get("cost", 0)),
	])


## 仅清空尾部按钮引用；实际释放由树上 remove_child + queue_free 单次完成
func _discard_tail_button_refs() -> void:
	_fuse_btns.clear()
	_refine_btns.clear()
	_reroll_btns.clear()


func _clear_dynamic_rows() -> void:
	_discard_tail_button_refs()
	_detach_section_labels()
	if _vbox == null:
		return
	var stale: Array[Node] = _vbox.get_children()
	for child in stale:
		_vbox.remove_child(child)
		child.queue_free()


func _detach_section_labels() -> void:
	for lab in [_evo_label, _refine_label, _reroll_label]:
		if lab != null and lab.get_parent() != null:
			lab.get_parent().remove_child(lab)


func _place_tail_controls() -> void:
	_refresh_fusion()


func _refresh_fusion() -> void:
	if not visible or _vbox == null:
		return
	_detach_section_labels()
	_discard_tail_button_refs()
	# 保留商品行；仅拆掉带 shop_tail 的尾部控件（单次释放，避免双重 queue_free）
	var stale: Array[Node] = []
	for child in _vbox.get_children():
		if child.has_meta("shop_tail"):
			stale.append(child)
	for child in stale:
		_vbox.remove_child(child)
		child.queue_free()

	_refresh_fusion_buttons_only()
	_refresh_refine_buttons_only()
	_refresh_reroll_buttons_only()
	if _evo_label != null:
		_evo_label.set_meta("shop_tail", true)
		_vbox.add_child(_evo_label)
	if _refine_label != null:
		_refine_label.set_meta("shop_tail", true)
		_vbox.add_child(_refine_label)
	if _reroll_label != null:
		_reroll_label.set_meta("shop_tail", true)
		_vbox.add_child(_reroll_label)


func _refresh_fusion_buttons_only() -> void:
	if _evo_label != null:
		_evo_label.text = LanguageSystem.localizef("ui.shop.evo_items", [GameState.evolution_items])
	var ready: Array[String] = EvolutionSystem.list_ready()
	for wid in ready:
		var path: Dictionary = EvolutionSystem.evolution_path(wid)
		var btn: Button = Button.new()
		_UI.style_button(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("shop_tail", true)
		var evo_key: String = "weapon.%s.evolved_name" % wid
		var evo_name: String = LanguageSystem.localize(evo_key)
		if evo_name == evo_key:
			evo_name = String(path.get("evolved_name", "?"))
		btn.text = LanguageSystem.localizef("ui.shop.fuse", [
			GameState.get_weapon_display_name(wid),
			evo_name,
		])
		btn.pressed.connect(_on_fuse_pressed.bind(wid))
		_vbox.add_child(btn)
		_fuse_btns.append(btn)


func _refresh_refine_buttons_only() -> void:
	if _refine_label != null:
		_refine_label.text = LanguageSystem.localizef("ui.shop.refine_essence", [
			GameState.refine_essence, GameState.MAX_REFINE_II,
		])
	var ready: Array[String] = RefineSystem.list_ready()
	for wid in ready:
		var path: Dictionary = RefineSystem.refine_path(wid)
		var target: int = RefineSystem.next_refine_tier(wid)
		var cost: int = int(RefineSystem.get_rules().get("tier_%d_cost" % target, 1 if target == 1 else 2))
		var step_mult: float = ConfigLoader.get_refine_multiplier(wid, target) / ConfigLoader.get_refine_multiplier(wid, target - 1)
		var cum_mult: float = ConfigLoader.get_refine_multiplier(wid, target)
		var btn: Button = Button.new()
		_UI.style_button(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("shop_tail", true)
		btn.text = LanguageSystem.localizef("ui.shop.refine", [
			target,
			GameState.get_weapon_display_name(wid),
			_refine_path_display_name(wid, path),
			step_mult,
			cum_mult,
			cost,
		])
		btn.pressed.connect(_on_refine_pressed.bind(wid))
		_vbox.add_child(btn)
		_refine_btns.append(btn)


func _refine_path_display_name(weapon_id: String, path: Dictionary) -> String:
	var key: String = "refine.%s.name" % weapon_id
	var text: String = LanguageSystem.localize(key)
	if text != key:
		return text
	return String(path.get("name", weapon_id))


func _refresh_reroll_buttons_only() -> void:
	var ratio_pct: int = int(round(ConfigLoader.get_shop_refund_ratio("weapon") * 100.0))
	if _reroll_label != null:
		_reroll_label.text = LanguageSystem.localizef("ui.shop.reroll_header", [ratio_pct])
	var can_reroll_weapon: bool = GameState.weapon_slots.size() > 1
	for wid in GameState.weapon_slots:
		var paid: int = ConfigLoader.get_shop_paid_cost("weapon")
		var refund: int = roundi(float(paid) * ConfigLoader.get_shop_refund_ratio("weapon"))
		var btn: Button = Button.new()
		_UI.style_button(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.set_meta("shop_tail", true)
		var wlabel: String = GameState.get_weapon_display_name(wid)
		if GameState.is_weapon_locked(wid):
			btn.text = LanguageSystem.localizef("ui.shop.reroll_weapon_locked", [wlabel])
			btn.disabled = true
		elif can_reroll_weapon:
			btn.text = LanguageSystem.localizef("ui.shop.reroll_weapon", [wlabel, refund])
			btn.pressed.connect(_on_reroll_weapon_pressed.bind(wid))
		else:
			btn.text = LanguageSystem.localizef("ui.shop.reroll_weapon_keep", [wlabel])
			btn.disabled = true
		_vbox.add_child(btn)
		_reroll_btns.append(btn)
	for pid in GameState.passive_slots:
		var paid_p: int = ConfigLoader.get_shop_paid_cost("passive")
		var refund_p: int = roundi(float(paid_p) * ConfigLoader.get_shop_refund_ratio("passive"))
		var btn_p: Button = Button.new()
		_UI.style_button(btn_p)
		btn_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn_p.set_meta("shop_tail", true)
		var pdata: Dictionary = ConfigLoader.get_passive(pid)
		var pname: String = LanguageSystem.localize_config_name(
			"passive", pid, String(pdata.get("name", pid))
		)
		btn_p.text = LanguageSystem.localizef("ui.shop.reroll_passive", [
			pname, refund_p,
		])
		btn_p.pressed.connect(_on_reroll_passive_pressed.bind(pid))
		_vbox.add_child(btn_p)
		_reroll_btns.append(btn_p)


func _on_fuse_pressed(weapon_id: String) -> void:
	if EvolutionSystem.fuse(weapon_id):
		evolution_fused.emit(weapon_id)
		_refresh_fusion()


func _on_refine_pressed(weapon_id: String) -> void:
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
		_evo_label.text = LanguageSystem.localizef("ui.shop.evo_items", [GameState.evolution_items])
	if visible:
		_refresh_fusion()


func _on_refine_essence_changed(_total: int) -> void:
	if _refine_label != null:
		_refine_label.text = LanguageSystem.localizef("ui.shop.refine_essence", [
			GameState.refine_essence, GameState.MAX_REFINE_II,
		])
	if visible:
		_refresh_fusion()


func _refresh_coins() -> void:
	if _coin_label != null:
		_coin_label.text = LanguageSystem.localizef("ui.shop.coins", [GameState.tidecoins])


func close() -> void:
	visible = false
