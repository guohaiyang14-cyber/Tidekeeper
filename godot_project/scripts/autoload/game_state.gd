# ============================================================================
# GameState — 单局运行时状态（autoload 单例）
# 职责：持有当前局的游戏状态，局开始时初始化、局结束时清理
# 架构位置：README §1.2 Main → GameState (autoload)
# 注意：存档数据由 SaveSystem 管理，本单例只管局内运行时状态
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 GameState 访问

# 信号
signal night_started(night: int)
signal night_ended(night: int)
signal day_started()
signal game_over(reason: String)
signal game_win()
signal exp_gained(amount: int, total_exp: int)
signal level_up(new_level: int)
signal tidecoins_changed(new_total: int)
signal player_damaged(amount: int)
signal evolution_items_changed(new_total: int)
signal refine_essence_changed(new_total: int)
signal player_health_changed(new_health: int)
signal loadout_changed()

# 局内状态
var current_night: int = 0
var is_day_phase: bool = true
var current_character: String = "watcher"

# 玩家运行时属性
var player_level: int = 1
var player_exp: int = 0
var player_health: int = 100
var player_max_health: int = 100
var tidecoins: int = 0
var stardust: int = 0
var refine_essence: int = 0
## 未使用的进化道具数量（§6.5）
var evolution_items: int = 0

# 武器槽 / 被动槽（SKILL.md §5.2：上限 4 武器 / 6 被动）
var weapon_slots: Array[String] = []
var passive_slots: Array[String] = []
# 武器等级：id → 等级（1~max_weapon_level），重复获得已持有武器则升级（W5）
var weapon_levels: Dictionary[String, int] = {}
# 被动等级：id → 等级（1~max_passive_level）
var passive_levels: Dictionary[String, int] = {}
## 已进化武器 id → 进化显示名
var evolved_weapons: Dictionary[String, String] = {}
## 精炼等级：weapon_id → 0/1/2（0=未精炼；W11 精炼系统）
var refine_tiers: Dictionary[String, int] = {}
var max_weapon_level: int = 7
var max_passive_level: int = 5
const MAX_WEAPON_SLOTS: int = 4
const MAX_PASSIVE_SLOTS: int = 6

# 精炼约束（SKILL.md §5.4：MVP 上限 2 II，无 III）
var refine_ii_count: int = 0
const MAX_REFINE_II: int = 2
const MAX_REFINE_III: int = 0  # MVP 不做 III

# 武器槽锁定（迷途航船事件：锁定 N 夜禁止重铸，§5.6）
var _locked_weapon: String = ""
var _lock_nights: int = 0

# 局内种子（确定性回放）
var run_seed: int = 0

# 局是否已结束（游戏结束/通关后防止重复触发）
var is_over: bool = false
## arm_game_win() 已置 is_over，但 game_win 信号尚未发出（防死亡栈内清场）
var _game_win_armed: bool = false


func _ready() -> void:
	print("[GameState] 就绪（尚未开始新局）")


## 开始新局（初始化所有局内状态）
func start_new_run(character: String = "watcher", seed_value: int = -1) -> void:
	current_night = 0
	is_day_phase = true
	current_character = character

	player_level = 1
	player_exp = 0
	tidecoins = 0
	stardust = 0
	refine_essence = 0
	refine_essence_changed.emit(refine_essence)

	# 角色基础属性（对齐 §9.4 角色表）
	match character:
		"watcher":
			player_max_health = 100
		"blacksmith":
			player_max_health = 120
		"stargazer":
			player_max_health = 85
		_:
			player_max_health = 100
	player_health = player_max_health

	weapon_slots.clear()
	passive_slots.clear()
	weapon_levels.clear()
	passive_levels.clear()
	evolved_weapons.clear()
	evolution_items = 0
	refine_tiers.clear()
	# 开局授予数据驱动的默认武器（避免 0 武器无法攻击的死亡螺旋，§4.2）
	var sw: String = ConfigLoader.get_starting_weapon()
	if sw != "":
		add_weapon(sw)
	# 武器等级上限来自 config（避免硬编码，§6.3）
	var cfg_max_lv: int = ConfigLoader.get_max_weapon_level()
	if cfg_max_lv > 0:
		max_weapon_level = cfg_max_lv
	var cfg_pas_lv: int = ConfigLoader.get_max_passive_level()
	if cfg_pas_lv > 0:
		max_passive_level = cfg_pas_lv
	refine_ii_count = 0

	# 重置武器槽锁定与事件态（新局不受上局事件影响）
	_locked_weapon = ""
	_lock_nights = 0
	EventSystem.reset()

	# 重置结束标记（新局可再次触发结束）
	clear_over_state()

	# 种子
	if seed_value < 0:
		run_seed = RNG.get_seed()
	else:
		run_seed = seed_value
		RNG.set_seed(seed_value)

	print("[GameState] 新局开始: character=%s seed=%d max_hp=%d" % [character, run_seed, player_max_health])


## 进入第 N 夜
func enter_night(night: int) -> void:
	current_night = night
	is_day_phase = false
	night_started.emit(night)
	print("[GameState] 进入第 %d 夜" % night)


## 夜晚结束进入抉择之昼
func end_night() -> void:
	is_day_phase = true
	# 本夜结束：递减迷途航船武器锁定（锁定随夜数解除，§5.6）
	tick_weapon_lock()
	night_ended.emit(current_night)
	day_started.emit()
	print("[GameState] 第 %d 夜结束 → 抉择之昼" % current_night)


## 增加经验（自动处理升级；E(level) = 本级升下一级所需）
## 应用被动通用经验桶（W12）+ 事件经验倍率（W14）：实际获得 = amount × 被动倍率 × 事件倍率
func add_exp(amount: int) -> void:
	var gained: int = int(round(float(amount) * PassiveSystem.get_exp_mult() * EventSystem.get_exp_mult()))
	player_exp += gained
	exp_gained.emit(gained, player_exp)
	while player_level < ExpTable.get_max_level():
		var need: int = ExpTable.get_exp(player_level)
		if need <= 0:
			break
		if player_exp >= need:
			player_exp -= need
			player_level += 1
			level_up.emit(player_level)
			print("[GameState] 升级！Lv%d (剩余经验 %d)" % [player_level, player_exp])
		else:
			break


## 添加或升级武器（返回是否成功）
## 未持有 → 入槽并置等级 1；已持有 → 等级 +1（上限 max_weapon_level），满级返回 false
func add_weapon(weapon_id: String) -> bool:
	if weapon_id in weapon_slots:
		var lv: int = get_weapon_level(weapon_id)
		if lv >= max_weapon_level:
			return false  # 已满级，无法再升级
		weapon_levels[weapon_id] = lv + 1
		return true
	if weapon_slots.size() >= MAX_WEAPON_SLOTS:
		return false
	weapon_slots.append(weapon_id)
	weapon_levels[weapon_id] = 1
	return true


## 获取武器当前等级（未持有返回 0；在槽但缺 levels 条目视为 1）
func get_weapon_level(weapon_id: String) -> int:
	if weapon_id not in weapon_slots:
		return 0
	return int(weapon_levels.get(weapon_id, 1))


## 移除武器并返还槽位（重铸回收时调用；同步清除进化标记与精炼阶）
func remove_weapon(weapon_id: String) -> bool:
	if weapon_id not in weapon_slots:
		return false
	weapon_slots.erase(weapon_id)
	weapon_levels.erase(weapon_id)
	evolved_weapons.erase(weapon_id)
	refine_tiers.erase(weapon_id)
	return true


## 添加或升级被动（返回是否成功）
## 未持有 → 入槽并置等级 1；已持有 → 等级 +1（上限 max_passive_level），满级返回 false
func add_passive(passive_id: String) -> bool:
	if passive_id in passive_slots:
		var lv: int = get_passive_level(passive_id)
		if lv >= max_passive_level:
			return false
		passive_levels[passive_id] = lv + 1
		return true
	if passive_slots.size() >= MAX_PASSIVE_SLOTS:
		return false
	passive_slots.append(passive_id)
	passive_levels[passive_id] = 1
	return true


## 获取被动当前等级（未持有返回 0；在槽但缺 levels 条目视为 1）
func get_passive_level(passive_id: String) -> int:
	if passive_id not in passive_slots:
		return 0
	return int(passive_levels.get(passive_id, 1))


## 移除被动并返还槽位（进化融合时调用）
func remove_passive(passive_id: String) -> bool:
	if passive_id not in passive_slots:
		return false
	passive_slots.erase(passive_id)
	passive_levels.erase(passive_id)
	return true


## 重铸回收：卸下被动并退还 config 比例的实付潮币（W13；MVP 不随等级浮动）
## 返回退还金额；未持有返回 0
func reroll_passive(passive_id: String) -> int:
	if passive_id not in passive_slots:
		return 0
	var paid: int = ConfigLoader.get_shop_paid_cost("passive")
	var refund: int = roundi(float(paid) * ConfigLoader.get_shop_refund_ratio("passive"))
	remove_passive(passive_id)
	add_tidecoins(refund)
	loadout_changed.emit()
	return refund


## 重铸回收：卸下武器并退还 config 比例的实付潮币（W13；同步清进化/精炼）
## 至少保留 1 把武器（禁止清空槽导致夜晚无输出）；末把返回 0
## 迷途航船锁定的武器在锁定期内禁止重铸（返回 0，§5.6）
func reroll_weapon(weapon_id: String) -> int:
	if weapon_id not in weapon_slots:
		return 0
	if weapon_slots.size() <= 1:
		return 0
	if is_weapon_locked(weapon_id):
		return 0
	var paid: int = ConfigLoader.get_shop_paid_cost("weapon")
	var refund: int = roundi(float(paid) * ConfigLoader.get_shop_refund_ratio("weapon"))
	remove_weapon(weapon_id)
	add_tidecoins(refund)
	loadout_changed.emit()
	return refund


## 灯塔回血至上限（RestSystem 调用）；返回实际回复量
func heal_player_to_full() -> int:
	var before: int = player_health
	player_health = player_max_health
	var healed: int = player_health - before
	if healed > 0:
		player_health_changed.emit(player_health)
	return healed


## 锁定某武器槽 N 夜（迷途航船事件；禁止期间重铸，§5.6）
func lock_weapon(weapon_id: String, nights: int) -> void:
	if nights <= 0:
		return
	_locked_weapon = weapon_id
	_lock_nights = nights


## 该武器当前是否处于锁定（禁止重铸）
func is_weapon_locked(weapon_id: String) -> bool:
	return weapon_id == _locked_weapon and _lock_nights > 0


## 每夜结束递减锁定计数（锁定随夜数自然解除；end_night 调用，§5.6）
func tick_weapon_lock() -> void:
	if _lock_nights > 0:
		_lock_nights -= 1
		if _lock_nights <= 0:
			_locked_weapon = ""


## 增加星尘（局外货币；事件「星尘雨」结算时调用，§5.6）
func add_stardust(amount: int) -> void:
	if amount <= 0:
		return
	stardust += amount


## 被动槽已用数量（被动槽管理，W12）
func passive_slot_usage() -> int:
	return passive_slots.size()


## 是否还能新增被动（被动槽管理，W12）
func can_add_passive() -> bool:
	return passive_slots.size() < MAX_PASSIVE_SLOTS


func is_weapon_evolved(weapon_id: String) -> bool:
	return evolved_weapons.has(weapon_id)


func get_evolved_name(weapon_id: String) -> String:
	return evolved_weapons.get(weapon_id, "")


## 标记武器已进化（占原槽；被动槽由 EvolutionSystem 返还）
func mark_weapon_evolved(weapon_id: String, evolved_name: String) -> void:
	if weapon_id not in weapon_slots:
		return
	evolved_weapons[weapon_id] = evolved_name


func add_evolution_items(amount: int) -> void:
	if amount <= 0:
		return
	evolution_items += amount
	evolution_items_changed.emit(evolution_items)


func consume_evolution_item() -> bool:
	if evolution_items <= 0:
		return false
	evolution_items -= 1
	evolution_items_changed.emit(evolution_items)
	return true


## 获取武器当前精炼等级（未持有返回 0）
func get_refine_tier(weapon_id: String) -> int:
	return int(refine_tiers.get(weapon_id, 0))


## 设置武器精炼等级（钳制到 0/1/2；由 RefineSystem 调用，门控在系统侧）
## 同时维护 refine_ii_count（达到/离开 II 阶的武器数），使「全局最多 2 把 II」上限与等级强绑定。
func set_refine_tier(weapon_id: String, tier: int) -> void:
	var old: int = int(refine_tiers.get(weapon_id, 0))
	var clamped: int = clampi(tier, 0, 2)
	refine_tiers[weapon_id] = clamped
	if old < 2 and clamped >= 2:
		refine_ii_count += 1
	elif old >= 2 and clamped < 2:
		refine_ii_count -= 1


## 武器是否已精炼（任意阶）
func is_weapon_refined(weapon_id: String) -> bool:
	return get_refine_tier(weapon_id) > 0


func add_refine_essence(amount: int) -> void:
	if amount <= 0:
		return
	refine_essence += amount
	refine_essence_changed.emit(refine_essence)


func consume_refine_essence(amount: int) -> bool:
	if amount <= 0:
		return true
	if refine_essence < amount:
		return false
	refine_essence -= amount
	refine_essence_changed.emit(refine_essence)
	return true


## 玩家受伤（敌人接触/弹幕/自爆调用）；归零触发游戏结束
## 应用被动通用减伤桶（W12）：实际伤害 = amount × (1 - 减伤)
func damage_player(amount: int) -> void:
	if is_over or amount <= 0:
		return
	var applied: int = int(round(float(amount) * (1.0 - PassiveSystem.get_damage_reduction())))
	player_health -= applied
	player_damaged.emit(applied)
	if player_health <= 0:
		player_health = 0
		trigger_game_over("hp_zero")
		return


## 增加潮币（击杀掉落拾取时调用）
func add_tidecoins(amount: int) -> void:
	if amount <= 0:
		return
	tidecoins += amount
	tidecoins_changed.emit(tidecoins)


## 花费潮币（商店购买时调用）；余额不足返回 false 且不扣减
func spend_tidecoins(amount: int) -> bool:
	if amount <= 0 or tidecoins < amount:
		return false
	tidecoins -= amount
	tidecoins_changed.emit(tidecoins)
	return true


## 判定游戏结束
func trigger_game_over(reason: String = "death") -> void:
	if is_over:
		return  # 已结束，防止敌人接触逐帧重复触发
	is_over = true
	_game_win_armed = false
	game_over.emit(reason)
	print("[GameState] 游戏结束: %s (已存活 %d 夜)" % [reason, current_night])


## 立刻锁通关（不发信号）：终局 Boss 死亡回调里调用，防止同帧接触抢先判负
func arm_game_win() -> void:
	if is_over:
		return
	is_over = true
	_game_win_armed = true


## 判定通关（第 20 夜 Boss 击败 / 夜尽）；若已 arm 则只补发信号
func trigger_game_win() -> void:
	if is_over and not _game_win_armed:
		return
	is_over = true
	_game_win_armed = false
	game_win.emit()
	print("[GameState] 通关！20 夜全部完成")


## 是否最后一夜
func is_final_night() -> bool:
	return current_night >= 20


## 清除结束态（新局 / 机检复位）
func clear_over_state() -> void:
	is_over = false
	_game_win_armed = false
