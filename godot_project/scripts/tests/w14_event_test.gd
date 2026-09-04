# ============================================================================
# W14EventTest — 事件卡 + 潮汐夹击（逻辑 + 机检）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w14_event_test.tscn
# 覆盖：7 事件可触发且效果正确 / 第 15 夜排除潮汐反转 / 潮汐反转→两侧夹击 /
#       迷途航船赠武器+锁槽 / 满槽升级已持有 / 鱼群回游进化道具受软上限+精英波 /
#       星尘雨结算 / 月食·暴风雨·灯塔共鸣倍率 / 经验·攻速·移速·掉落接线 / reset 清空
# ============================================================================
extends Node

const _PLAYER = preload("res://scripts/player/player.gd")
const _WEAPON_HARPOON = preload("res://scripts/combat/weapon_harpoon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	RNG.set_seed(20261414)
	print("============================================================")
	print("W14 事件卡 + 潮汐夹击（逻辑 + 机检）")
	print("============================================================")
	_test_all_seven_triggerable()
	_test_effects_correct()
	_test_night15_excludes_tidal_reversal()
	_test_pick_night15_no_tidal()
	_test_tidal_reversal_pincer()
	_test_storm()
	_test_eclipse()
	_test_lighthouse_resonance()
	_test_stardust_rain()
	_test_lost_ship()
	_test_lost_ship_full_slots()
	_test_fish_migration()
	_test_stardust_bonus_flow()
	_test_exp_mult_integration()
	_test_attack_speed_wiring()
	_test_move_speed_wiring()
	_test_drop_scaling()
	_test_combat_mods_deferred_until_begin_night()
	_test_reset_clears()
	await _test_vision_overlay()
	print("------------------------------------------------------------")
	print("W14 机检通过=%d 失败=%d" % [_passed, _failed])
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
	GameState.start_new_run("watcher", 20261414)
	EventSystem.reset()


## 7 张卡均可触发（apply_event 后 active 且名称正确）
func _test_all_seven_triggerable() -> void:
	print("[7 事件可触发]")
	var ids: Array = ConfigLoader.events.get("events", {}).keys()
	_assert(ids.size() == 7, "事件池共 7 张（%d）" % ids.size())
	for id in ids:
		EventSystem.reset()
		EventSystem.apply_event(id)
		var cfg_name: String = ConfigLoader.get_event(id).get("name", "")
		_assert(EventSystem.has_active_event(), "事件 %s 已激活" % id)
		_assert(EventSystem.get_active_event_name() == cfg_name, "事件 %s 名称=%s" % [id, cfg_name])


## 各事件 effects 解析为正确倍率/标记
func _test_effects_correct() -> void:
	print("[效果解析]")
	EventSystem.reset(); EventSystem.apply_event("storm")
	_assert(EventSystem.get_enemy_speed_mult() == 1.30, "暴风雨 敌移速×1.30")
	_assert(EventSystem.get_night_drop_mult() == 1.50, "暴风雨 掉落×1.50")
	EventSystem.reset(); EventSystem.apply_event("eclipse")
	_assert(EventSystem.get_vision_mult() == 0.70, "月食 视野×0.70")
	_assert(EventSystem.get_exp_mult() == 2.0, "月食 经验×2.0")
	EventSystem.reset(); EventSystem.apply_event("lighthouse_resonance")
	_assert(EventSystem.get_attack_speed_mult() == 1.40, "灯塔共鸣 攻速×1.40")
	_assert(EventSystem.get_move_speed_mult() == 0.80, "灯塔共鸣 移速×0.80")
	EventSystem.reset(); EventSystem.apply_event("stardust_rain")
	_assert(EventSystem.get_tidecoin_mult() == 1.80, "星尘雨 潮币×1.80")
	_assert(EventSystem.has_stardust_bonus(), "星尘雨 结束+星尘标记")


## 第 15 夜事件池排除潮汐反转（避免与天灾潮汐夹击叠乘）
func _test_night15_excludes_tidal_reversal() -> void:
	print("[第15夜排除潮汐反转]")
	var pool: Array = ConfigLoader.get_events_for_night(15)
	var has_tidal: bool = false
	for ev in pool:
		if String(ev.get("id", "")) == "tidal_reversal":
			has_tidal = true
	_assert(not has_tidal, "第15夜事件池不含 tidal_reversal")
	_assert(pool.size() == 6, "第15夜事件池剩 6 张（%d）" % pool.size())


## 第 15 夜多次抽取均不返回潮汐反转（确定性 RNG）
func _test_pick_night15_no_tidal() -> void:
	print("[第15夜抽取采样]")
	RNG.set_seed(20261414)
	var bad: int = 0
	var nonempty: int = 0
	for _i in 200:
		var id: String = EventSystem.pick_for_night(15)
		if id == "":
			continue
		nonempty += 1
		if id == "tidal_reversal":
			bad += 1
	_assert(nonempty == 200, "200 次抽取均有事件（%d）" % nonempty)
	_assert(bad == 0, "200 次抽取均非潮汐反转（命中=%d）" % bad)
	# 其余夜次（非15）潮汐反转可正常出现
	RNG.set_seed(20261414)
	var seen_tidal: bool = false
	for _i in 300:
		if EventSystem.pick_for_night(7) == "tidal_reversal":
			seen_tidal = true
	_assert(seen_tidal, "非15夜（如第7夜）可抽到潮汐反转")


## 潮汐反转 → 两侧夹击标记 + 宝箱翻倍；reset 后清除
func _test_tidal_reversal_pincer() -> void:
	print("[潮汐反转→夹击]")
	EventSystem.reset(); EventSystem.apply_event("tidal_reversal")
	_assert(EventSystem.is_event_pincer(), "潮汐反转 is_event_pincer=true")
	_assert(EventSystem.get_chest_mult() == 2.0, "潮汐反转 宝箱×2.0")
	EventSystem.reset()
	_assert(not EventSystem.is_event_pincer(), "reset 后 is_event_pincer=false")
	_assert(EventSystem.get_chest_mult() == 1.0, "reset 后 宝箱×1.0")


func _test_storm() -> void:
	print("[暴风雨]")
	EventSystem.reset(); EventSystem.apply_event("storm")
	_assert(EventSystem.get_enemy_speed_mult() == 1.30, "敌移速×1.30")
	_assert(EventSystem.get_night_drop_mult() == 1.50, "掉落×1.50")


func _test_eclipse() -> void:
	print("[月食]")
	EventSystem.reset(); EventSystem.apply_event("eclipse")
	_assert(EventSystem.get_exp_mult() == 2.0, "经验×2.0")
	_assert(EventSystem.get_vision_mult() == 0.70, "视野×0.70")


func _test_lighthouse_resonance() -> void:
	print("[灯塔共鸣]")
	EventSystem.reset(); EventSystem.apply_event("lighthouse_resonance")
	_assert(EventSystem.get_attack_speed_mult() == 1.40, "攻速×1.40")
	_assert(EventSystem.get_move_speed_mult() == 0.80, "移速×0.80")


func _test_stardust_rain() -> void:
	print("[星尘雨]")
	EventSystem.reset(); EventSystem.apply_event("stardust_rain")
	_assert(EventSystem.get_tidecoin_mult() == 1.80, "潮币×1.80")
	_assert(EventSystem.has_stardust_bonus(), "结束+星尘标记=true")


## 迷途航船：免费赠 1 武器并锁定该槽 3 夜；锁定期间重铸返回 0；夜数递减后解锁
func _test_lost_ship() -> void:
	print("[迷途航船·赠武器+锁槽]")
	_reset_run()
	var before: int = GameState.weapon_slots.size()
	var before_slots: Array = GameState.weapon_slots.duplicate()
	EventSystem.reset(); EventSystem.apply_event("lost_ship")
	var after: int = GameState.weapon_slots.size()
	_assert(after >= before, "赠武器后槽数不减（%d→%d）" % [before, after])
	# 找出被锁定的武器（新入槽者）
	var locked_id: String = ""
	var before_set: Dictionary = {}
	for w in before_slots:
		before_set[w] = true
	# lost_ship 优先加未持有武器；若加成功则锁定，否则升级已持有（仍锁定其一）
	if after > before:
		for w in GameState.weapon_slots:
			if not before_set.has(w):
				locked_id = w
				break
	else:
		# 满槽情况：锁定随机一把已持有（此处开局仅 1 把，不会满槽）
		locked_id = GameState.weapon_slots[0] if not GameState.weapon_slots.is_empty() else ""
	_assert(locked_id != "", "定位被锁武器")
	_assert(GameState.is_weapon_locked(locked_id), "锁定期间 is_weapon_locked=true")
	var refund: int = GameState.reroll_weapon(locked_id)
	_assert(refund == 0, "锁定期间重铸返回 0")
	# 模拟 3 夜结束（end_night 递减锁定）
	GameState.end_night()
	GameState.end_night()
	GameState.end_night()
	_assert(not GameState.is_weapon_locked(locked_id), "3 夜后锁解除")
	var refund2: int = GameState.reroll_weapon(locked_id)
	_assert(refund2 > 0, "解锁后重铸可退币（%d）" % refund2)


## 满槽：升级随机已持有并锁定；槽数不变；发射 loadout_changed
func _test_lost_ship_full_slots() -> void:
	print("[迷途航船·满槽升级]")
	_reset_run()
	var ids: Array[String] = ["harpoon", "holy_fire", "anchor_hammer", "spore"]
	GameState.weapon_slots = ids.duplicate()
	GameState.weapon_levels.clear()
	for wid in ids:
		GameState.weapon_levels[wid] = 1
	var saw_loadout: Array[bool] = [false]
	var cb: Callable = func() -> void:
		saw_loadout[0] = true
	GameState.loadout_changed.connect(cb)
	EventSystem.apply_event("lost_ship")
	GameState.loadout_changed.disconnect(cb)
	_assert(GameState.weapon_slots.size() == 4, "满槽后槽数仍为 4")
	var upgraded: String = ""
	for wid in GameState.weapon_slots:
		if GameState.get_weapon_level(wid) == 2:
			upgraded = wid
			break
	_assert(upgraded != "", "满槽时升级一把已持有")
	_assert(GameState.is_weapon_locked(upgraded), "升级的武器被锁定")
	_assert(saw_loadout[0], "赠枪/升级发射 loadout_changed")
	_assert(GameState.reroll_weapon(upgraded) == 0, "锁定期间重铸返回 0")


## 鱼群回游：立即掉进化道具（受 ≤2 软上限）；并标记本夜精英波
func _test_fish_migration() -> void:
	print("[鱼群回游·进化道具+精英波]")
	_reset_run()
	EventSystem.reset(); EventSystem.apply_event("fish_migration")
	_assert(GameState.evolution_items == 1, "空持有时掉 1 进化道具（%d）" % GameState.evolution_items)
	_assert(EventSystem.has_elite_wave(), "本夜精英波标记=true")
	_assert(EventSystem.get_elite_wave_count() == 3, "精英波数量来自 config（%d）" % EventSystem.get_elite_wave_count())
	# 软上限：已持有 2 时不再掉
	GameState.evolution_items = 2
	EventSystem.reset(); EventSystem.apply_event("fish_migration")
	_assert(GameState.evolution_items == 2, "已达软上限 2 时不再掉（%d）" % GameState.evolution_items)


## 星尘雨结算：World 在进昼对上夜事件 add_stardust(1)
func _test_stardust_bonus_flow() -> void:
	print("[星尘雨·结算]")
	_reset_run()
	EventSystem.reset(); EventSystem.apply_event("stardust_rain")
	_assert(EventSystem.has_stardust_bonus(), "星尘雨标记=true")
	_assert(EventSystem.get_stardust_bonus_amount() == 1, "星尘数量来自 config=1")
	var before: int = GameState.stardust
	GameState.add_stardust(EventSystem.get_stardust_bonus_amount())
	_assert(GameState.stardust == before + 1, "结算 +1 星尘")


## 经验倍率接线：月食下 add_exp 实际翻倍（被动倍率默认 1.0）
## 注：用 exp_gained 信号比对实际获得量，避免升级扣经验干扰
func _test_exp_mult_integration() -> void:
	print("[经验倍率接线]")
	_reset_run()
	EventSystem.reset(); EventSystem.apply_event("eclipse")
	var gained_box: Array = [0]
	var on_gained := func(gained: int, _total: int) -> void:
		gained_box[0] = gained
	GameState.exp_gained.connect(on_gained)
	GameState.add_exp(100)
	_assert(gained_box[0] == 200, "月食下 100 经验→200（×2）")
	EventSystem.reset()
	GameState.add_exp(100)
	_assert(gained_box[0] == 100, "无事件 100 经验→100")
	if GameState.exp_gained.is_connected(on_gained):
		GameState.exp_gained.disconnect(on_gained)


## 灯塔共鸣攻速接线：WeaponBase.get_attack_rate 乘 EventSystem 攻速
func _test_attack_speed_wiring() -> void:
	print("[攻速接线]")
	_reset_run()
	var data: Dictionary = ConfigLoader.get_weapon("harpoon")
	var w: WeaponBase = _WEAPON_HARPOON.new()
	w.configure(data, 1)
	var r0: float = w.get_attack_rate()
	EventSystem.apply_event("lighthouse_resonance")
	_assert(abs(w.get_attack_rate() - r0 * 1.40) < 0.001, "灯塔共鸣攻速 ×1.40")
	EventSystem.reset()
	_assert(abs(w.get_attack_rate() - r0) < 0.001, "reset 后攻速恢复")
	w.free()


## 灯塔共鸣移速接线：Player.get_current_speed 乘 EventSystem 移速
func _test_move_speed_wiring() -> void:
	print("[移速接线]")
	_reset_run()
	var p: Player = _PLAYER.new()
	var s0: float = p.get_current_speed()
	EventSystem.apply_event("lighthouse_resonance")
	_assert(abs(p.get_current_speed() - s0 * 0.80) < 0.001, "灯塔共鸣移速 ×0.80")
	EventSystem.reset()
	_assert(abs(p.get_current_speed() - s0) < 0.001, "reset 后移速恢复")
	p.free()


## 掉落缩放：暴风雨经验/潮币 ×1.50；星尘雨仅潮币 ×1.80；重铸退款路径不经 scale_coin
func _test_drop_scaling() -> void:
	print("[掉落缩放]")
	EventSystem.reset(); EventSystem.apply_event("storm")
	_assert(EventSystem.scale_drop_amount(10) == 15, "暴风雨 经验珠基础 10→15")
	_assert(EventSystem.scale_coin_amount(10) == 15, "暴风雨 潮币 10→15")
	EventSystem.reset(); EventSystem.apply_event("stardust_rain")
	_assert(EventSystem.scale_drop_amount(10) == 10, "星尘雨 经验珠不受潮币倍率")
	_assert(EventSystem.scale_coin_amount(10) == 18, "星尘雨 潮币 10→18")
	EventSystem.reset()
	_assert(EventSystem.scale_drop_amount(10) == 10, "无事件掉落原值")
	_assert(EventSystem.scale_coin_amount(10) == 10, "无事件潮币原值")


## 昼 arm 不加载战斗倍率；begin_night 后才生效（商店阶段不受灯塔共鸣移速等影响）
func _test_combat_mods_deferred_until_begin_night() -> void:
	print("[昼抽卡延期战斗倍率]")
	_reset_run()
	EventSystem.reset()
	EventSystem.arm_event("lighthouse_resonance")
	_assert(EventSystem.get_active_event_id() == "lighthouse_resonance", "arm 后事件 id 已锁定")
	_assert(EventSystem.get_attack_speed_mult() == 1.0, "昼阶段攻速仍为 1.0")
	_assert(EventSystem.get_move_speed_mult() == 1.0, "昼阶段移速仍为 1.0")
	EventSystem.begin_night()
	_assert(EventSystem.get_attack_speed_mult() == 1.40, "begin_night 后攻速 ×1.40")
	_assert(EventSystem.get_move_speed_mult() == 0.80, "begin_night 后移速 ×0.80")
	EventSystem.reset()
	EventSystem.arm_event("stardust_rain")
	_assert(EventSystem.has_stardust_bonus(), "星尘标记在昼 arm 即生效")
	_assert(EventSystem.get_stardust_bonus_amount() == 1, "星尘数量来自 config")
	_assert(EventSystem.get_tidecoin_mult() == 1.0, "潮币倍率仍待 begin_night")
	EventSystem.begin_night()
	_assert(EventSystem.get_tidecoin_mult() == 1.80, "begin_night 后潮币 ×1.80")


## 敌人移速接线：已由 enemy_base._effective_speed 乘 EventSystem.get_enemy_speed_mult() 实现，
## 该倍率值已在 _test_effects_correct / _test_storm 中通过 EventSystem getter 覆盖；
## 真实实例化的移速放大在 w8/w9 场景回归（含完整依赖）中验证，headless 单测场景因
## BossBrain/AffixSystem class_name 依赖未注册而无法独立编译 enemy_base，故此处不实例化。


func _test_reset_clears() -> void:
	print("[reset 清空]")
	EventSystem.reset()
	_assert(not EventSystem.has_active_event(), "reset 后无激活事件")
	_assert(EventSystem.get_enemy_speed_mult() == 1.0, "reset 敌移速=1.0")
	_assert(EventSystem.get_exp_mult() == 1.0, "reset 经验=1.0")
	_assert(EventSystem.get_tidecoin_mult() == 1.0, "reset 潮币=1.0")
	_assert(not EventSystem.is_event_pincer(), "reset 夹击=false")
	_assert(not EventSystem.has_stardust_bonus(), "reset 星尘标记=false")
	_assert(EventSystem.get_stardust_bonus_amount() == 0, "reset 星尘数量=0")
	_assert(not EventSystem.has_elite_wave(), "reset 精英波=false")
	_assert(EventSystem.get_elite_wave_count() == 0, "reset 精英波数量=0")
	_assert(EventSystem.get_attack_speed_mult() == 1.0, "reset 攻速=1.0")
	_assert(EventSystem.get_move_speed_mult() == 1.0, "reset 移速=1.0")


## 视野遮罩消费 EventSystem.get_vision_mult（月食缩小半径）
func _test_vision_overlay() -> void:
	print("[视野遮罩]")
	const _VO = preload("res://scripts/core/vision_overlay.gd")
	var base: float = ConfigLoader.get_base_vision_radius()
	_assert(base > 0.0, "基准视野半径已从 config 加载")
	var eclipse_mult: float = float(
		ConfigLoader.get_event("eclipse").get("effects", {}).get("vision_radius_mult", 1.0)
	)
	_assert(eclipse_mult < 0.999, "月食 config 含视野惩罚")
	var vo: VisionOverlay = _VO.new() as VisionOverlay
	add_child(vo)
	await get_tree().process_frame
	EventSystem.reset()
	EventSystem.apply_event("storm")
	vo.refresh_from_event()
	_assert(not vo.is_vision_restricted(), "无视野惩罚时遮罩关闭")
	_assert(abs(vo.get_vision_radius() - base) < 0.01, "暴风雨视野=基准")
	EventSystem.reset()
	EventSystem.apply_event("eclipse")
	vo.refresh_from_event()
	_assert(vo.is_vision_restricted(), "月食激活遮罩")
	_assert(abs(EventSystem.get_vision_mult() - eclipse_mult) < 0.01, "EventSystem 视野倍率=config")
	_assert(abs(vo.get_vision_radius() - base * eclipse_mult) < 0.01, "月食半径=base×config")
	EventSystem.reset()
	vo.refresh_from_event()
	_assert(not vo.is_vision_restricted(), "reset 后遮罩关闭")
	# 进昼等价：clear_overlay 须清 _active
	EventSystem.apply_event("eclipse")
	vo.refresh_from_event()
	_assert(vo.is_vision_restricted(), "月食再次激活")
	vo.clear_overlay()
	_assert(not vo.is_vision_restricted(), "clear_overlay 后未激活")
	_assert(vo.visible == false, "clear_overlay 后不可见")
	vo.queue_free()
