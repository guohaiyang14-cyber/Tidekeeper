# ============================================================================
# EvolutionSystem — 进化融合与道具掉落（W10，autoload）
# 职责：判定可融合路径、执行融合（耗道具 + 返还被动槽）、精英/Boss 掉落配额
# 红线：路径与掉落只读 config/evolutions.json；随机走 RNG；禁止运行时 instantiate
# ============================================================================
extends Node

signal evolved(weapon_id: String, evolved_name: String)
signal item_gained(amount: int, total: int)
signal resonance_requested(duration: float)

var _elite_drops_this_night: int = 0


func _ready() -> void:
	print("[EvolutionSystem] 就绪")


## 新局 / 新夜：重置当夜精英掉落计数
func on_night_start(_night: int) -> void:
	_elite_drops_this_night = 0


func evolution_path(weapon_id: String) -> Dictionary:
	return ConfigLoader.get_evolution_path(weapon_id)


## 持有尚未进化、且配置了进化路径的武器 → 仍有「可进化项」
func has_evolvable_owned() -> bool:
	for wid in GameState.weapon_slots:
		if GameState.is_weapon_evolved(wid):
			continue
		if not evolution_path(wid).is_empty():
			return true
	return false


func can_fuse(weapon_id: String) -> bool:
	var path: Dictionary = evolution_path(weapon_id)
	if path.is_empty():
		return false
	if GameState.is_weapon_evolved(weapon_id):
		return false
	if weapon_id not in GameState.weapon_slots:
		return false
	var rules: Dictionary = ConfigLoader.get_evolution_rules()
	var wmax: int = int(rules.get("weapon_max_level", GameState.max_weapon_level))
	var pmax: int = int(rules.get("passive_max_level", GameState.max_passive_level))
	if GameState.get_weapon_level(weapon_id) < wmax:
		return false
	var pid: String = String(path.get("passive_id", ""))
	if pid == "" or GameState.get_passive_level(pid) < pmax:
		return false
	if GameState.evolution_items <= 0:
		return false
	return true


## 当前可融合的武器 id 列表（抉择之昼置顶）
func list_ready() -> Array[String]:
	var out: Array[String] = []
	for wid in ConfigLoader.get_all_evolution_weapon_ids():
		if can_fuse(String(wid)):
			out.append(String(wid))
	return out


## 执行融合：耗 1 道具，移除进化钥被动（返还槽），标记传说
func fuse(weapon_id: String) -> bool:
	if not can_fuse(weapon_id):
		return false
	var path: Dictionary = evolution_path(weapon_id)
	var pid: String = String(path.get("passive_id", ""))
	var evo_name: String = String(path.get("evolved_name", "传说武器"))
	if not GameState.consume_evolution_item():
		return false
	GameState.remove_passive(pid)
	GameState.mark_weapon_evolved(weapon_id, evo_name)
	var dur: float = float(ConfigLoader.get_evolution_rules().get("resonance_duration", 1.5))
	resonance_requested.emit(dur)
	evolved.emit(weapon_id, evo_name)
	print("[EvolutionSystem] 融合成功：%s → %s" % [weapon_id, evo_name])
	return true


## 尝试发放进化道具。
## respect_evolvable：需持有可进化武器；respect_soft_cap：宝箱/事件受未使用道具软上限（Boss/保底精英无视）。
func grant_items(amount: int, respect_evolvable: bool = true, respect_soft_cap: bool = true) -> int:
	if amount <= 0:
		return 0
	var rules: Dictionary = ConfigLoader.get_evolution_rules()
	if respect_evolvable and bool(rules.get("require_evolvable_for_drop", true)):
		if not has_evolvable_owned():
			return 0
	var give: int = amount
	if respect_soft_cap:
		var soft: int = int(rules.get("soft_cap_unused_items", 2))
		var room: int = soft - GameState.evolution_items
		if room <= 0:
			return 0
		give = mini(amount, room)
	GameState.add_evolution_items(give)
	item_gained.emit(give, GameState.evolution_items)
	return give


## 精英击杀掉落（当夜精英池合计最多 1；第 5 夜命名精英必掉且无视软上限）
func try_elite_drop(night: int, is_named_elite: bool) -> int:
	var drops: Dictionary = ConfigLoader.get_evolution_drops()
	var cap: int = int(drops.get("elite_per_night_cap", 1))
	if _elite_drops_this_night >= cap:
		return 0
	var guaranteed: bool = false
	var nights: Variant = drops.get("elite_night_guaranteed", [5])
	if nights is Array:
		for v in nights:
			if int(v) == night and is_named_elite:
				guaranteed = true
				break
	if not guaranteed and not is_named_elite:
		# 非命名精英：本周仅保证命名/精英夜路径；其余精英暂不掉（避免与词缀小怪混淆）
		return 0
	if not guaranteed and not has_evolvable_owned():
		return 0
	# 保底精英无视软上限（§5.4 软上限约束宝箱/事件）；仍要求可进化项
	var n: int = grant_items(1, true, not guaranteed)
	if n > 0:
		_elite_drops_this_night += n
	return n


## Boss 击杀掉落（不计入精英上限、无视软上限；第 15/20 夜额外数量见 config）
func try_boss_drop(night: int) -> int:
	var drops: Dictionary = ConfigLoader.get_evolution_drops()
	var table: Dictionary = drops.get("boss_drop_count", {})
	var amount: int = int(table.get(str(night), table.get(night, 1)))
	return grant_items(amount, true, false)
