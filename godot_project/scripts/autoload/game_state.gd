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
## 新局已初始化（CombatLog / 调试订阅）
signal run_started(character: String, seed_value: int)
## W17 挫败感控制：玩家复活（kind = "first_night" | "struggle"）
signal player_revived(kind: String)
## W17 挫败感控制：玩家倒地进入挣扎（HP 归零但未判负，免死窗口中）。
## kind = "struggle"。供 HUD/音效订阅，做「倒地」视觉与音效反馈（与 player_revived/game_over 构成完整反馈生命周期）
signal player_down(kind: String)

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

# ============================================================================
# W17 挫败感控制：运行时态（数据驱动 config/frustration.json）
# ============================================================================
## 首夜保护已用复活次数（每局上限 max_revives）
var _first_night_revives: int = 0
## 挣扎模式是否激活（免死窗口中）
var _struggle_active: bool = false
## 挣扎模式免死窗口剩余秒数
var _struggle_timer: float = 0.0
## 本次挣扎窗口内累计击杀
var _struggle_kills: int = 0
## 挣扎模式已用复活次数（每夜上限 max_revives；进夜清零，对齐 GDD「每夜 1 次」）
var _struggle_revives: int = 0
## 当前无敌剩余秒数（复活后短暂无敌 / 挣扎免死窗口内）
var _invuln_remaining: float = 0.0
## 伤害来源累计：source_id(String) -> 累计伤害(int)（W17 死因可视化）
var _damage_taken: Dictionary = {}
## 最后一击来源与伤害量
var _last_hit_source: String = ""
var _last_hit_amount: int = 0


func _ready() -> void:
	print("[GameState] 就绪（尚未开始新局）")


## 每帧推进挫败感计时器（免死窗口 / 复活无敌倒计时）
func _process(delta: float) -> void:
	_advance_timers(delta)


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

	# 角色基础属性（对齐 §9.4 角色表，数据驱动 config/characters.json；叠加灯塔最大生命）
	player_max_health = ConfigLoader.get_character_max_health(character) + MetaSystem.get_max_health_bonus()
	player_health = player_max_health

	weapon_slots.clear()
	passive_slots.clear()
	weapon_levels.clear()
	passive_levels.clear()
	evolved_weapons.clear()
	evolution_items = 0
	refine_tiers.clear()
	# 开局授予数据驱动的角色默认武器（避免 0 武器无法攻击的死亡螺旋，§4.2）
	var sw: String = ConfigLoader.get_character_starting_weapon(character)
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
	# 重置 W17 挫败感控制计数（每局 fresh）
	_reset_frustration_state()

	# 种子：仅 SEED_UNSET(-1) 表示重抽；合法种子 [0, 2^32)，显式传入可回放
	if seed_value == RNG.SEED_UNSET:
		run_seed = RNG.randomize_seed()
	else:
		run_seed = RNG.normalize_seed(seed_value)
		RNG.set_seed(run_seed)

	print("[GameState] 新局开始: character=%s seed=%d max_hp=%d" % [character, run_seed, player_max_health])
	run_started.emit(character, run_seed)


## 进入第 N 夜
func enter_night(night: int) -> void:
	current_night = night
	is_day_phase = false
	# GDD §8.4：挣扎「每夜 1 次」——按 config max_revives_scope 清零本夜已用次数
	var st: Dictionary = ConfigLoader.get_frustration_config().get("struggle", {})
	if String(st.get("max_revives_scope", "per_night")) == "per_night":
		_struggle_revives = 0
	night_started.emit(night)
	print("[GameState] 进入第 %d 夜" % night)


## 夜晚结束进入抉择之昼
func end_night() -> void:
	is_day_phase = true
	# 本夜结束：递减迷途航船武器锁定（锁定随夜数解除，§5.6）
	tick_weapon_lock()
	night_ended.emit(current_night)
	# 夜尽清场后无法再击杀：挣扎窗口不得带入抉择之昼/商店。终局夜（20）走通关，不在此判负。
	if _struggle_active and current_night < 20:
		_fail_unresolved_struggle()
		return
	day_started.emit()
	print("[GameState] 第 %d 夜结束 → 抉择之昼" % current_night)


## 增加经验（自动处理升级；E(level) = 本级升下一级所需）
## 应用被动通用经验桶（W12）+ 事件经验倍率（W14）：实际获得 = amount × 被动倍率 × 事件倍率
func add_exp(amount: int) -> void:
	var gained: int = int(round(float(amount) * PassiveSystem.get_exp_mult() * EventSystem.get_exp_mult() * MetaSystem.get_exp_mult()))
	player_exp += gained
	exp_gained.emit(gained, player_exp)
	# 人物无等级硬顶：E(n) 表内查表、表外同公式外推
	while true:
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
		loadout_changed.emit()
		return true
	if weapon_slots.size() >= MAX_WEAPON_SLOTS:
		return false
	weapon_slots.append(weapon_id)
	weapon_levels[weapon_id] = 1
	loadout_changed.emit()
	return true


## 教学夜武器展示：第 night 夜（教学期内）按 difficulty.json teaching.demo_weapons 顺序
## 授予一把「尚未拥有」的武器，让玩家直观看到不同武器的效果。
## 当夜顺位武器已持有（如铁匠开局锚锤）时，向后扫描 demo 列表，再回补更早顺位。
## 非教学夜 / 无可授予 / 槽满 → 返回 ""（不授予；槽满静默跳过）。
## 仅真实对局 World 在进夜时调用；headless 单测直接调用本函数。
func grant_teaching_demo_weapon(night: int) -> String:
	if not DifficultySystem.is_teaching_night(night):
		return ""
	var demo: Array = ConfigLoader.get_teaching_demo_weapons()
	if demo.is_empty():
		return ""
	var start_idx: int = night - 2  # 第2夜→[0]，第3夜→[1]，第4夜→[2]
	if start_idx < 0:
		return ""
	var wid: String = _pick_teaching_demo_weapon(demo, start_idx)
	if wid == "":
		return ""
	# 槽满是可预期路径（玩家/机器人已自选满 4 槽），静默跳过；勿 push_warning 刷屏
	if weapon_slots.size() >= MAX_WEAPON_SLOTS:
		print("[GameState] 教学夜展示武器跳过（槽满）: %s (夜%d)" % [wid, night])
		return ""
	if add_weapon(wid):
		print("[GameState] 教学夜展示武器: %s (夜%d)" % [wid, night])
		return wid
	return ""


## 从 demo 列表选取首个未持有武器：先 [start_idx..)，再 [0, start_idx)（跳过角色开局重复）
func _pick_teaching_demo_weapon(demo: Array, start_idx: int) -> String:
	for i in range(start_idx, demo.size()):
		var wid: String = String(demo[i])
		if wid != "" and wid not in weapon_slots:
			return wid
	for i in range(0, start_idx):
		var wid: String = String(demo[i])
		if wid != "" and wid not in weapon_slots:
			return wid
	return ""


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
		loadout_changed.emit()
		return true
	if passive_slots.size() >= MAX_PASSIVE_SLOTS:
		return false
	passive_slots.append(passive_id)
	passive_levels[passive_id] = 1
	loadout_changed.emit()
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
	if _struggle_active:
		return 0  # 挣扎免死窗口中治疗中不生效，唯有击杀 K 敌可复活（P3）
	var before: int = player_health
	player_health = player_max_health
	var healed: int = player_health - before
	if healed > 0:
		player_health_changed.emit(player_health)
	return healed


## 回复指定生命（不超过上限）；返回实际回复量
func heal_player(amount: int) -> int:
	if amount <= 0:
		return 0
	if _struggle_active:
		return 0  # 挣扎免死窗口中治疗中不生效，唯有击杀 K 敌可复活（P3）
	var before: int = player_health
	player_health = mini(player_max_health, player_health + amount)
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


## HUD / 商店显示名：已进化用进化名，否则基础名（走 i18n）
func get_weapon_display_name(weapon_id: String) -> String:
	var base: Dictionary = ConfigLoader.get_weapon(weapon_id)
	var base_name: String = String(base.get("name", weapon_id))
	if is_weapon_evolved(weapon_id):
		var evo_fallback: String = get_evolved_name(weapon_id)
		if evo_fallback == "":
			var evo_cfg: Dictionary = base.get("evolution", {})
			evo_fallback = String(evo_cfg.get("name", base_name))
		var evo_key: String = "weapon.%s.evolved_name" % weapon_id
		var evo_text: String = LanguageSystem.localize(evo_key)
		return evo_text if evo_text != evo_key else evo_fallback
	return LanguageSystem.localize_config_name("weapon", weapon_id, base_name)


## 标记武器已进化（占原槽；被动槽由 EvolutionSystem 返还）
func mark_weapon_evolved(weapon_id: String, evolved_name: String) -> void:
	if weapon_id not in weapon_slots:
		return
	evolved_weapons[weapon_id] = evolved_name
	loadout_changed.emit()


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


## 玩家受伤（敌人接触/弹幕/自爆/荆棘调用）；归零触发游戏结束
## 应用被动通用减伤桶（W12）：实际伤害 = amount × (1 - 减伤)
## source_id：伤害来源标识（W17 死因可视化用，如 "enemy_contact" / "boss_tide_archon" / ""）
func damage_player(amount: int, source_id: String = "") -> void:
	if is_over or amount <= 0:
		return
	if _invuln_remaining > 0.0:
		return  # 免死/复活后短暂无敌期内忽略伤害
	# 减伤只走 PassiveSystem 桶（已含灯塔/角色减伤）；禁止再减一次 MetaSystem
	var applied: int = int(round(float(amount) * (1.0 - PassiveSystem.get_damage_reduction())))
	# 伤害来源追踪（W17 死因可视化）
	_record_damage(source_id, applied)
	player_health -= applied
	player_damaged.emit(applied)
	if player_health > 0:
		return
	player_health = 0
	# 致命伤：先尝试挫败感控制的复活保护，否则判负
	if _try_revive_on_lethal():
		return
	trigger_game_over("hp_zero")


## 记录一次伤害来源与量（W17 死因可视化）
func _record_damage(source_id: String, applied: int) -> void:
	var key: String = source_id if source_id != "" else "unknown"
	_damage_taken[key] = int(_damage_taken.get(key, 0)) + applied
	_last_hit_source = key
	_last_hit_amount = applied


## 致命伤时尝试复活保护（首夜保护 / 挣扎模式）。返回 true 表示已复活（不判负）
## 仅在正式开局（MetaSystem.begin_run）后生效，与角色/灯塔特性同门控，避免单元机检误食复活
func _try_revive_on_lethal() -> bool:
	if not MetaSystem.is_run_active():
		return false
	var cfg: Dictionary = ConfigLoader.get_frustration_config()
	# 1) 首夜保护：前 protect_nights 夜，最多 max_revives 次满血复活
	var fn: Dictionary = cfg.get("first_night", {})
	if bool(fn.get("enabled", false)) and _first_night_revives < int(fn.get("max_revives", 0)):
		var protect_nights: int = int(fn.get("protect_nights", 4))
		if current_night <= protect_nights:
			_first_night_revives += 1
			revive_to_full()
			_invuln_remaining = float(fn.get("revive_invuln_sec", 1.5))  # 复活后短暂无敌，避免同帧再死
			player_revived.emit("first_night")
			print("[GameState] 首夜保护复活（第 %d 次，剩余无敌 %.1fs）" % [_first_night_revives, _invuln_remaining])
			return true
	# 2) 挣扎模式：进入免死窗口（invuln_sec 秒），期间击杀 kills_to_revive 敌则满血复活
	var st: Dictionary = cfg.get("struggle", {})
	if bool(st.get("enabled", false)) and not _struggle_active and _struggle_revives < int(st.get("max_revives", 0)):
		_struggle_active = true
		_struggle_timer = float(st.get("invuln_sec", 3.0))
		_struggle_kills = 0
		_invuln_remaining = _struggle_timer
		player_down.emit("struggle")  # 倒地进入挣扎：供视觉/音效反馈
		print("[GameState] 进入挣扎模式（免死 %.1fs，需击杀 %d 敌）" % [_struggle_timer, int(st.get("kills_to_revive", 5))])
		return true
	return false


## 满血复活（不重置局内进度，仅回血至上限）
func revive_to_full() -> void:
	player_health = player_max_health
	player_health_changed.emit(player_health)


## 击杀登记（enemy_base._die 的 enemy_died 信号回调调用）：挣扎模式累计击杀，达标则复活
func register_enemy_kill() -> void:
	if not _struggle_active:
		return
	var st: Dictionary = ConfigLoader.get_frustration_config().get("struggle", {})
	_struggle_kills += 1
	var need: int = int(st.get("kills_to_revive", 5))
	if _struggle_kills >= need:
		_struggle_active = false
		_struggle_revives += 1
		revive_to_full()
		_invuln_remaining = float(st.get("revive_invuln_sec", 2.0))  # 复活后短暂无敌
		player_revived.emit("struggle")
		print("[GameState] 挣扎模式复活（窗口内击杀 %d 敌达标）" % _struggle_kills)


## 当前是否处于无敌（免死窗口 / 复活后）
func is_invulnerable() -> bool:
	return _invuln_remaining > 0.0


## 当前是否处于挣扎模式（免死窗口中）
func is_struggling() -> bool:
	return _struggle_active


## 是否「倒地但未死」（HP<=0 且未结束，即挣扎免死窗口中）。
## HUD/结算应以 is_over 为「已死亡」真值，以 is_player_down() 表示「挣扎中（可复活）」，
## 避免 player_health==0 的挣扎期被误判为已死亡（P2-#2）
func is_player_down() -> bool:
	return player_health <= 0 and not is_over


## 挣扎免死窗口剩余秒数（未挣扎返回 0.0）。供 HUD 显示「挣扎倒计时」
func get_struggle_remaining() -> float:
	return _struggle_timer if _struggle_active else 0.0


## 挣扎窗口内已击杀敌数（未挣扎返回 0）。供 HUD 显示「击杀进度」
func get_struggle_kills() -> int:
	return _struggle_kills if _struggle_active else 0


## 挣扎复活所需总击杀数（取 config，未配置回退 5）。供 HUD 显示「击杀进度」
func get_struggle_kills_needed() -> int:
	var st: Dictionary = ConfigLoader.get_frustration_config().get("struggle", {})
	return int(st.get("kills_to_revive", 5))


## 最近一次实际扣血来源（CombatLog 受击行；避免每次 get_death_analysis）
func get_last_hit_source() -> String:
	return _last_hit_source


## 最近一次实际扣血量
func get_last_hit_amount() -> int:
	return _last_hit_amount


## 死亡原因分析（W17 死因可视化）：最后一击来源 + 伤害来源 TopN
func get_death_analysis() -> Dictionary:
	var cfg: Dictionary = ConfigLoader.get_frustration_config().get("death_analysis", {})
	var top_n: int = int(cfg.get("top_sources", 3))
	var ranked: Array = []
	for src in _damage_taken.keys():
		ranked.append({"source": String(src), "damage": int(_damage_taken[src])})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["damage"] > b["damage"])
	var top: Array = ranked.slice(0, mini(top_n, ranked.size()))
	var total: int = 0
	for v in _damage_taken.values():
		total += int(v)
	return {
		"last_hit_source": _last_hit_source,
		"last_hit_amount": _last_hit_amount,
		"top_sources": top,
		"total_damage": total,
	}


## 机检：推进挫败感计时器（公开包装，避免测试直接调私有 _advance_timers）
func advance_timers_for_test(delta: float) -> void:
	_advance_timers(delta)


## 推进挫败感计时器（免死窗口 / 复活无敌）。_process 自动调用；机检走 advance_timers_for_test
func _advance_timers(delta: float) -> void:
	if _invuln_remaining > 0.0:
		_invuln_remaining = maxf(0.0, _invuln_remaining - delta)
	if _struggle_active:
		_struggle_timer -= delta
		if _struggle_timer <= 0.0:
			_fail_unresolved_struggle()


## 挣扎未达标结束（窗口耗尽 / 夜尽清场）：关窗口并判负
func _fail_unresolved_struggle() -> void:
	if not _struggle_active:
		return
	_struggle_active = false
	_struggle_timer = 0.0
	_invuln_remaining = 0.0
	player_health = 0
	trigger_game_over("hp_zero")


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
	_log_damage_composition()


## Debug/TestBot 可解析：整局累计伤害组成（含复活前后；数值为减伤后 applied）
## 编辑器二进制 / debug 导出落盘；release 导出模板跳过（正式包降噪）
func _log_damage_composition() -> void:
	if not OS.is_debug_build() and not OS.has_feature("editor"):
		return
	var a: Dictionary = get_death_analysis()
	var ranked: Array = []
	for src in _damage_taken.keys():
		ranked.append({"source": String(src), "damage": int(_damage_taken[src])})
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["damage"] > y["damage"])
	var parts: PackedStringArray = PackedStringArray()
	for entry in ranked:
		parts.append("%s=%d" % [String(entry["source"]), int(entry["damage"])])
	var body: String = " ".join(parts) if not parts.is_empty() else "(none)"
	print(
		"[GameState] 伤害组成: total=%d last=%s amt=%d | %s"
		% [int(a.get("total_damage", 0)), String(a.get("last_hit_source", "")), int(a.get("last_hit_amount", 0)), body]
	)


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
	# 清空挣扎/无敌瞬时态（防止跨局残留）
	_struggle_active = false
	_struggle_timer = 0.0
	_invuln_remaining = 0.0


## 重置 W17 挫败感控制全部运行时态（每局开始调用）
## 死因统计口径（P2-#3）：_damage_taken 每局 start_new_run 重置（无跨局泄漏）；
## 整局累计（含复活前后）不分段，get_death_analysis 反映「最终致命全貌」。
func _reset_frustration_state() -> void:
	_first_night_revives = 0
	_struggle_active = false
	_struggle_timer = 0.0
	_struggle_kills = 0
	_struggle_revives = 0
	_invuln_remaining = 0.0
	_damage_taken.clear()
	_last_hit_source = ""
	_last_hit_amount = 0
