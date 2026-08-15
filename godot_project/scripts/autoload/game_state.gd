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

# 武器槽 / 被动槽（SKILL.md §5.2：上限 4 武器 / 6 被动）
var weapon_slots: Array[String] = []
var passive_slots: Array[String] = []
# 武器等级：id → 等级（1~max_weapon_level），重复获得已持有武器则升级（W5）
var weapon_levels: Dictionary[String, int] = {}
var max_weapon_level: int = 7
const MAX_WEAPON_SLOTS: int = 4
const MAX_PASSIVE_SLOTS: int = 6

# 精炼约束（SKILL.md §5.4：MVP 上限 2 II，无 III）
var refine_ii_count: int = 0
const MAX_REFINE_II: int = 2
const MAX_REFINE_III: int = 0  # MVP 不做 III

# 局内种子（确定性回放）
var run_seed: int = 0

# 局是否已结束（游戏结束/通关后防止重复触发）
var is_over: bool = false


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
	# 开局授予数据驱动的默认武器（避免 0 武器无法攻击的死亡螺旋，§4.2）
	var sw: String = ConfigLoader.get_starting_weapon()
	if sw != "":
		add_weapon(sw)
	# 武器等级上限来自 config（避免硬编码，§6.3）
	var cfg_max_lv: int = ConfigLoader.get_max_weapon_level()
	if cfg_max_lv > 0:
		max_weapon_level = cfg_max_lv
	refine_ii_count = 0

	# 重置结束标记（新局可再次触发结束）
	is_over = false

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
	night_ended.emit(current_night)
	day_started.emit()
	print("[GameState] 第 %d 夜结束 → 抉择之昼" % current_night)


## 增加经验（自动处理升级；E(level) = 本级升下一级所需）
func add_exp(amount: int) -> void:
	player_exp += amount
	exp_gained.emit(amount, player_exp)
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
		var lv: int = weapon_levels.get(weapon_id, 1)
		if lv >= max_weapon_level:
			return false  # 已满级，无法再升级
		weapon_levels[weapon_id] = lv + 1
		return true
	if weapon_slots.size() >= MAX_WEAPON_SLOTS:
		return false
	weapon_slots.append(weapon_id)
	weapon_levels[weapon_id] = 1
	return true


## 获取武器当前等级（未持有返回 0）
func get_weapon_level(weapon_id: String) -> int:
	return weapon_levels.get(weapon_id, 0)


## 添加被动到槽位（返回是否成功）
func add_passive(passive_id: String) -> bool:
	if passive_slots.size() >= MAX_PASSIVE_SLOTS:
		return false
	if passive_id in passive_slots:
		return false
	passive_slots.append(passive_id)
	return true


## 玩家受伤（敌人接触/弹幕/自爆调用）；归零触发游戏结束
func damage_player(amount: int) -> void:
	if amount <= 0:
		return
	player_health -= amount
	player_damaged.emit(amount)
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
	game_over.emit(reason)
	print("[GameState] 游戏结束: %s (已存活 %d 夜)" % [reason, current_night])


## 判定通关（第 20 夜 Boss 击败）
func trigger_game_win() -> void:
	if is_over:
		return
	is_over = true
	game_win.emit()
	print("[GameState] 通关！20 夜全部完成")


## 是否最后一夜
func is_final_night() -> bool:
	return current_night >= 20
