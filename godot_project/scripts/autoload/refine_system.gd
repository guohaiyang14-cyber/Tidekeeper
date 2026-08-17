# ============================================================================
# RefineSystem — 精炼系统（W11，autoload）
# 职责：判定可精炼阶（夜次门控 + 淬炼精华 + II 上限）、执行精炼（耗精华）、Boss/精英淬炼精华掉落
# 红线：路径与规则只读 config/refine_paths.json；随机走 RNG；禁止运行时 instantiate
# 设计：§6.6 精炼 — 进化后开放；I 第10夜 / II 第15夜；消耗 I×1 II×2；全局最多 2 把 II；不可撤销；MVP 只加伤害（dps_mult）
# ============================================================================
extends Node

signal refined(weapon_id: String, tier: int, path_name: String)

var _elite_drops_this_night: int = 0


func _ready() -> void:
	print("[RefineSystem] 就绪")


## 新局 / 新夜：重置当夜精英掉落计数
func on_night_start(_night: int) -> void:
	_elite_drops_this_night = 0


func refine_path(weapon_id: String) -> Dictionary:
	return ConfigLoader.get_refine_path(weapon_id)


func get_rules() -> Dictionary:
	return ConfigLoader.get_refine_rules()


## 某武器当前可精炼到的「下一阶」（0=不可；1=可 I；2=可 II）
## 约束：已持有、已进化、路径存在、未达 II、夜次开放、II 全局上限、淬炼精华足够
func next_refine_tier(weapon_id: String) -> int:
	if weapon_id not in GameState.weapon_slots:
		return 0
	var path: Dictionary = refine_path(weapon_id)
	if path.is_empty():
		return 0
	var cur: int = GameState.get_refine_tier(weapon_id)
	if cur >= 2:
		return 0
	var target: int = cur + 1
	var rules: Dictionary = get_rules()
	# 夜次开放门控
	var unlock_night: int = int(rules.get("tier_%d_unlock_night" % target, 10 if target == 1 else 15))
	if GameState.current_night < unlock_night:
		return 0
	# II 全局上限（设计 §6.6：一局最多 2 把 II）
	if target == 2 and GameState.refine_ii_count >= GameState.MAX_REFINE_II:
		return 0
	# 须已进化（§6.6「进化后的终局养成层」；可由 config.require_evolved 关闭）
	if bool(rules.get("require_evolved", true)) and not GameState.is_weapon_evolved(weapon_id):
		return 0
	# 淬炼精华消耗
	var cost: int = int(rules.get("tier_%d_cost" % target, 1 if target == 1 else 2))
	if GameState.refine_essence < cost:
		return 0
	return target


func can_refine(weapon_id: String) -> bool:
	return next_refine_tier(weapon_id) > 0


## 当前可精炼的武器 id 列表（抉择之昼置顶）
func list_ready() -> Array[String]:
	var out: Array[String] = []
	for wid in ConfigLoader.get_all_refine_weapon_ids():
		if can_refine(String(wid)):
			out.append(String(wid))
	return out


## 执行精炼到下一阶；成功返回目标阶（1/2），失败返回 0
func refine(weapon_id: String) -> int:
	var target: int = next_refine_tier(weapon_id)
	if target <= 0:
		return 0
	var cost: int = int(get_rules().get("tier_%d_cost" % target, 1 if target == 1 else 2))
	if not GameState.consume_refine_essence(cost):
		return 0
	GameState.set_refine_tier(weapon_id, target)
	var path: Dictionary = refine_path(weapon_id)
	refined.emit(weapon_id, target, String(path.get("name", weapon_id)))
	print("[RefineSystem] 精炼成功：%s → T%d（II 计数 %d/%d）" % [weapon_id, target, GameState.refine_ii_count, GameState.MAX_REFINE_II])
	return target


## 发放淬炼精华（含安全上限 essence_cap）；返回实发数
func grant_essence(amount: int) -> int:
	if amount <= 0:
		return 0
	var cap: int = int(get_rules().get("essence_cap", 9))
	var room: int = cap - GameState.refine_essence
	if room <= 0:
		return 0
	var give: int = mini(amount, room)
	GameState.add_refine_essence(give)
	return give


## Boss 击杀掉落淬炼精华（第 10/15/20 夜，amount 见 config.boss_drop_count）
func try_boss_drop(night: int) -> int:
	var table: Dictionary = get_rules().get("boss_drop_count", {})
	var amount: int = int(table.get(str(night), table.get(night, 0)))
	if amount <= 0:
		return 0
	return grant_essence(amount)


## 精英击杀掉落淬炼精华（第 12 夜起 30% 概率 ×1，当夜上限 elite_per_night_cap）
func try_elite_drop(night: int) -> int:
	var rules: Dictionary = get_rules()
	var min_night: int = int(rules.get("elite_min_night", 12))
	if night < min_night:
		return 0
	var cap: int = int(rules.get("elite_per_night_cap", 1))
	if _elite_drops_this_night >= cap:
		return 0
	var chance: float = float(rules.get("elite_drop_chance", 0.3))
	if not RNG.chance(chance):
		return 0
	var n: int = grant_essence(1)
	if n > 0:
		_elite_drops_this_night += n
	return n
