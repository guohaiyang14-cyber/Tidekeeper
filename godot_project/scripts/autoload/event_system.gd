# ============================================================================
# EventSystem — 事件卡系统（W14 逻辑 + 机检）
# 职责：抉择之昼从事件池随机抽 1 张事件卡（数据驱动，见 config/events.json §5.6），
#       昼阶段只落 identity + 即时效果；战斗倍率在进夜 begin_night 再加载。
# 红线：单一真源 = ConfigLoader.get_event(s)（运行时只读 config）；随机走 RNG（确定性回放）。
# 命名约定（设计文档 §5.5）：
#   - 「潮汐反转」= 事件卡（两侧夹击 + 宝箱翻倍），第 15 夜被 get_events_for_night 排除，避免与天灾「潮汐夹击」叠乘。
#   - 「潮汐夹击」= 第 15 夜天灾规则（仅两侧夹击），由 EnemySpawner._is_pincer_night 实现；本系统仅负责事件版两侧夹击。
# 生命周期：昼 World.pick_for_night(N+1) → arm（即时效果）；夜 World.begin_night → 战斗倍率；
#           下昼前结算星尘雨，再 pick 下一张（reset 旧事件）。
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 EventSystem 访问

# ---- 当前生效事件 ----
var _active_id: String = ""
var _active_name: String = ""

# ---- 数值倍率（无事件 / 昼未 begin_night 时全为 1.0） ----
var _enemy_speed_mult: float = 1.0
var _night_drop_mult: float = 1.0
var _vision_mult: float = 1.0
var _exp_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _move_speed_mult: float = 1.0
var _tidecoin_mult: float = 1.0
var _chest_mult: float = 1.0

# ---- 形态/状态类 ----
## 事件版两侧夹击（潮汐反转）：非 15 夜也强制 EnemySpawner 两侧刷怪
var _event_pincer: bool = false
## 鱼群回游：本夜开局刷一波精英（spawner 在 start_night 消费）
var _elite_wave_pending: bool = false
var _elite_wave_count: int = 0
## 星尘雨：本夜结束额外星尘（World 进昼结算；数量来自 config）
var _stardust_bonus: bool = false
var _stardust_bonus_amount: int = 0


func _ready() -> void:
	reset()
	print("[EventSystem] 就绪")


## 清空所有事件态（新局 / 抽下一张前）
func reset() -> void:
	_active_id = ""
	_active_name = ""
	_clear_combat_modifiers()
	_elite_wave_pending = false
	_elite_wave_count = 0
	_stardust_bonus = false
	_stardust_bonus_amount = 0


func _clear_combat_modifiers() -> void:
	_enemy_speed_mult = 1.0
	_night_drop_mult = 1.0
	_vision_mult = 1.0
	_exp_mult = 1.0
	_attack_speed_mult = 1.0
	_move_speed_mult = 1.0
	_tidecoin_mult = 1.0
	_chest_mult = 1.0
	_event_pincer = false


## 为「下一个夜」抽取 1 张事件卡：只写 identity + 即时效果（战斗倍率待 begin_night）
## 返回事件 id；池为空返回 ""
func pick_for_night(upcoming_night: int) -> String:
	reset()
	var pool: Array = ConfigLoader.get_events_for_night(upcoming_night)
	if pool.is_empty():
		return ""
	var idx: int = RNG.randi_range(0, pool.size() - 1)
	var ev: Dictionary = pool[idx]
	var id: String = String(ev.get("id", ""))
	arm_event(id)
	return id


## 昼阶段锁定事件：identity + 即时效果；不加载战斗倍率（避免商店阶段吃到灯塔共鸣移速等）
func arm_event(event_id: String) -> void:
	var ev: Dictionary = ConfigLoader.get_event(event_id)
	if ev.is_empty():
		return
	_active_id = event_id
	_active_name = String(ev.get("name", event_id))
	_apply_instant_effects(ev.get("effects", {}))


## 进夜：按已 arm 的事件加载战斗倍率（夹击 / 移速 / 掉落 / 攻速等）
func begin_night() -> void:
	if _active_id == "":
		return
	var ev: Dictionary = ConfigLoader.get_event(_active_id)
	if ev.is_empty():
		return
	_apply_combat_modifiers(ev.get("effects", {}))


## 应用指定事件卡的全部 effects（战斗 + 即时；供单测 / 调试，等价于 arm + begin_night）
func apply_event(event_id: String) -> void:
	var ev: Dictionary = ConfigLoader.get_event(event_id)
	if ev.is_empty():
		return
	_active_id = event_id
	_active_name = String(ev.get("name", event_id))
	var fx: Dictionary = ev.get("effects", {})
	_apply_combat_modifiers(fx)
	_apply_instant_effects(fx)


func _apply_combat_modifiers(fx: Dictionary) -> void:
	_enemy_speed_mult = float(fx.get("enemy_move_speed_mult", 1.0))
	_night_drop_mult = float(fx.get("night_drop_mult", 1.0))
	_vision_mult = float(fx.get("vision_radius_mult", 1.0))
	_exp_mult = float(fx.get("exp_gain_mult", 1.0))
	_attack_speed_mult = float(fx.get("attack_speed_mult", 1.0))
	_move_speed_mult = float(fx.get("move_speed_mult", 1.0))
	_tidecoin_mult = float(fx.get("tidecoin_mult", 1.0))
	_chest_mult = float(fx.get("chest_drop_mult", 1.0))
	_event_pincer = (String(fx.get("spawn_pattern", "")) == "two_sided_flank")


func _apply_instant_effects(fx: Dictionary) -> void:
	if bool(fx.get("grant_random_epic_weapon", false)):
		_grant_random_weapon(int(fx.get("weapon_slot_lock_nights", 0)))
	if bool(fx.get("spawn_elite_wave", false)):
		_elite_wave_pending = true
		_elite_wave_count = int(fx.get("elite_wave_count", 0))
	if int(fx.get("drop_evolution_item", 0)) > 0:
		_grant_evolution_items(int(fx.get("drop_evolution_item", 0)))
	if bool(fx.get("end_of_night_stardust_bonus", false)):
		_stardust_bonus = true
		_stardust_bonus_amount = maxi(0, int(fx.get("stardust_bonus_amount", 1)))


## 迷途航船：免费 1 件随机武器（优先未持有；满槽则升级随机已持有），并锁定该槽 N 夜
func _grant_random_weapon(lock_nights: int) -> void:
	var all_ids: Array = ConfigLoader.get_all_weapon_ids()
	if all_ids.is_empty():
		return
	var id: String = ""
	if GameState.weapon_slots.size() < GameState.MAX_WEAPON_SLOTS:
		var fresh: Array[String] = []
		for w in all_ids:
			var wid: String = String(w)
			if wid not in GameState.weapon_slots:
				fresh.append(wid)
		if not fresh.is_empty():
			id = fresh[RNG.randi_range(0, fresh.size() - 1)]
		else:
			id = String(all_ids[RNG.randi_range(0, all_ids.size() - 1)])
	else:
		var upgradable: Array[String] = []
		for wid in GameState.weapon_slots:
			if GameState.get_weapon_level(wid) < GameState.max_weapon_level:
				upgradable.append(wid)
		if upgradable.is_empty():
			return
		id = upgradable[RNG.randi_range(0, upgradable.size() - 1)]
	if id == "":
		return
	var added: bool = GameState.add_weapon(id)
	if not added:
		return
	if lock_nights > 0:
		GameState.lock_weapon(id, lock_nights)


## 鱼群回游：掉落进化道具；走 EvolutionSystem 软上限（§5.4），事件不要求已有可进化项
func _grant_evolution_items(n: int) -> void:
	EvolutionSystem.grant_items(n, false, true)


# ============================================================================
# 公开查询（夜战系统消费）
# ============================================================================
func get_active_event_id() -> String:
	return _active_id


func get_active_event_name() -> String:
	return _active_name


func has_active_event() -> bool:
	return _active_id != ""


func get_enemy_speed_mult() -> float:
	return _enemy_speed_mult


func get_night_drop_mult() -> float:
	return _night_drop_mult


func get_vision_mult() -> float:
	return _vision_mult


func get_exp_mult() -> float:
	return _exp_mult


func get_attack_speed_mult() -> float:
	return _attack_speed_mult


func get_move_speed_mult() -> float:
	return _move_speed_mult


func get_tidecoin_mult() -> float:
	return _tidecoin_mult


func get_chest_mult() -> float:
	return _chest_mult


## 经验珠基础量 × 本夜掉落倍率（暴风雨）；品质倍率仍由 PickupSystem 另乘
func scale_drop_amount(base: int) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * _night_drop_mult))


## 潮币掉落 × 本夜掉落倍率 × 潮币倍率（星尘雨）；不经 add_tidecoins，避免重铸退款被加成
func scale_coin_amount(base: int) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * _night_drop_mult * _tidecoin_mult))


## 事件版两侧夹击（潮汐反转）；与第 15 夜天灾夹击相互独立（spawner OR 组合）
func is_event_pincer() -> bool:
	return _event_pincer


func has_elite_wave() -> bool:
	return _elite_wave_pending


func get_elite_wave_count() -> int:
	return _elite_wave_count


func consume_elite_wave() -> void:
	_elite_wave_pending = false
	_elite_wave_count = 0


func has_stardust_bonus() -> bool:
	return _stardust_bonus


func get_stardust_bonus_amount() -> int:
	return _stardust_bonus_amount
