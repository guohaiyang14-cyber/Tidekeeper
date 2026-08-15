# ============================================================================
# UpgradeManager — 升级三选一管理器（autoload 单例）
# 职责：监听 GameState.level_up，构建 3 选项（武器/被动），按权重抽取；
#       武器保底（连续 2 次无武器 → 第 3 次必出）+ 被动系保底（连续 3 次无某系 → ×3）；
#       每级免费重铸 1 次（之后按 config 潮币）；apply / skip / reroll。
# 设计口径：主文档 §6.2 + 实现疑点清单 Q14
#   - 一次三选一计一次；重铸不另计 miss
#   - 本轮已出现的被动系立即清零权重加成（重铸不再 ×3）
# 红线：候选与权重来自 config/（ConfigLoader），禁止硬编码；用确定性 RNG（整数权重）
# 暂停：弹出三选一时暂停整棵树（get_tree().paused），选择/跳过后恢复
# 延后：已持有武器升级/进化候选 → W5（GameState 武器等级就位后）
# 注意：本文件只维护逻辑与数据；UI 表现由 UpgradeUI 负责
# ============================================================================
extends Node

signal upgrade_offered(offers: Array, can_free_reroll: bool)
signal upgrade_resolved(offer: Dictionary, is_skip: bool)

# 运行时状态
var _pending_choices: int = 0
var _current_offers: Array[Dictionary] = []
var _choosing: bool = false
var _no_weapon_streak: int = 0
var _series_miss_streak: Dictionary = {}
var _free_reroll_available: bool = false
# 进入本次三选一时的保底快照（miss 相对此基线只 +0/+1；权重看基线 + 本轮已出现集合）
var _pity_baseline_weapon: int = 0
var _pity_baseline_series: Dictionary = {}
var _weapon_seen_this_choice: bool = false
var _series_seen_this_choice: Dictionary = {}


func _ready() -> void:
	GameState.level_up.connect(_on_level_up)
	GameState.game_over.connect(_force_resume)
	GameState.game_win.connect(_force_resume)
	print("[UpgradeManager] 就绪")


## 新局开始时重置全部状态（World 在 start_new_run 后调用）
func reset() -> void:
	var was_choosing: bool = _choosing
	_pending_choices = 0
	_choosing = false
	_no_weapon_streak = 0
	_series_miss_streak.clear()
	_free_reroll_available = false
	_current_offers = []
	_pity_baseline_weapon = 0
	_pity_baseline_series.clear()
	_weapon_seen_this_choice = false
	_series_seen_this_choice.clear()
	if get_tree() != null:
		get_tree().paused = false
	if was_choosing:
		upgrade_resolved.emit({}, true)


# ============================================================================
# 公开查询 / 操作（UI 调用）
# ============================================================================

func is_presenting() -> bool:
	return _choosing


func pending_count() -> int:
	return _pending_choices


func get_current_offers() -> Array[Dictionary]:
	return _current_offers.duplicate()


func get_reroll_cost() -> int:
	return int(ConfigLoader.get_upgrade_config().get("reroll_cost", 10))


func get_max_offers() -> int:
	return int(ConfigLoader.get_upgrade_config().get("max_offers", 3))


## 选择一个选项（index 0-based）；应用失败则保持三选一打开
func apply_offer(index: int) -> void:
	if not _choosing or index < 0 or index >= _current_offers.size():
		return
	var offer: Dictionary = _current_offers[index]
	var applied: bool = false
	if offer.get("type") == "weapon":
		applied = GameState.add_weapon(str(offer["id"]))
	else:
		applied = GameState.add_passive(str(offer["id"]))
	print("[UpgradeManager] 选择: %s (%s) applied=%s" % [offer.get("name"), offer.get("type"), applied])
	if not applied:
		return
	_resolve(offer, false)


func skip() -> void:
	if not _choosing:
		return
	print("[UpgradeManager] 跳过三选一")
	_resolve({}, true)


## 重铸。免费 1 次/级；之后按 config 扣潮币。
func reroll() -> bool:
	if not _choosing:
		return false
	var cost: int = get_reroll_cost()
	if _free_reroll_available:
		_free_reroll_available = false
		_reroll_offers()
		print("[UpgradeManager] 免费重铸")
		return true
	if GameState.tidecoins >= cost:
		GameState.tidecoins -= cost
		_reroll_offers()
		print("[UpgradeManager] 重铸 (花费 %d 潮币)" % cost)
		return true
	print("[UpgradeManager] 重铸失败：潮币不足")
	return false


# ============================================================================
# 内部逻辑
# ============================================================================

func _on_level_up(_new_level: int) -> void:
	_pending_choices += 1
	if not _choosing:
		_present_next()


func _present_next() -> void:
	if _pending_choices <= 0:
		return
	_pending_choices -= 1
	_choosing = true
	_free_reroll_available = true
	_weapon_seen_this_choice = false
	_series_seen_this_choice.clear()
	_capture_pity_baseline()
	_current_offers = _build_offers()
	_note_offers_and_recompute_pity(_current_offers)
	if _current_offers.is_empty():
		print("[UpgradeManager] 候选池为空，自动跳过")
		_resolve({}, true)
		return
	get_tree().paused = true
	upgrade_offered.emit(_current_offers, _free_reroll_available)


func _reroll_offers() -> void:
	_current_offers = _build_offers()
	_note_offers_and_recompute_pity(_current_offers)
	if _current_offers.is_empty():
		print("[UpgradeManager] 重铸后候选池为空，自动跳过")
		_resolve({}, true)
		return
	upgrade_offered.emit(_current_offers, false)


func _resolve(offer: Dictionary, is_skip: bool) -> void:
	_choosing = false
	upgrade_resolved.emit(offer, is_skip)
	if _pending_choices > 0:
		_present_next()
	else:
		if get_tree() != null:
			get_tree().paused = false
		print("[UpgradeManager] 三选一结束，恢复")


func _force_resume(_payload: Variant = null) -> void:
	var was_choosing: bool = _choosing
	_choosing = false
	_pending_choices = 0
	_current_offers = []
	_weapon_seen_this_choice = false
	_series_seen_this_choice.clear()
	# 局已结束时不解暂停：结束态暂停权归 World/ResultUI，避免与连接顺序竞态
	# （本 autoload 先于 World 订阅 game_over，若此处 unpause 再被 World pause 依赖顺序脆弱）
	if get_tree() != null and not GameState.is_over:
		get_tree().paused = false
	if was_choosing:
		upgrade_resolved.emit({}, true)


func _capture_pity_baseline() -> void:
	_pity_baseline_weapon = _no_weapon_streak
	_pity_baseline_series = _series_miss_streak.duplicate()


## 合并本轮已展示集合，并相对基线重算 miss（同一次三选一只计一次）
func _note_offers_and_recompute_pity(offered: Array) -> void:
	for o in offered:
		if o.get("type") == "weapon":
			_weapon_seen_this_choice = true
		var s: String = str(o.get("series", ""))
		if s != "":
			_series_seen_this_choice[s] = true
	_no_weapon_streak = 0 if _weapon_seen_this_choice else _pity_baseline_weapon + 1
	for series in ConfigLoader.get_all_passive_series():
		if _series_seen_this_choice.has(series):
			_series_miss_streak[series] = 0
		else:
			_series_miss_streak[series] = int(_pity_baseline_series.get(series, 0)) + 1


## 构建当前候选池（来自 config，过滤已拥有 / 槽位已满）
## 注：不含已持有武器升级 —— 延后 W5
func _build_candidate_pool() -> Array[Dictionary]:
	var cfg: Dictionary = ConfigLoader.get_upgrade_config()
	var weight_weapon: int = int(cfg.get("weight_weapon", 10))
	var weight_passive: int = int(cfg.get("weight_passive", 8))
	var pool: Array[Dictionary] = []
	if GameState.weapon_slots.size() < GameState.MAX_WEAPON_SLOTS:
		for wid in ConfigLoader.get_all_weapon_ids():
			if wid not in GameState.weapon_slots:
				var w: Dictionary = ConfigLoader.get_weapon(wid)
				pool.append({
					"id": wid,
					"type": "weapon",
					"name": w.get("name", wid),
					"category": w.get("attack_type", ""),
					"series": "",
					"description": w.get("level_1_trait", ""),
					"weight": weight_weapon,
				})
	if GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS:
		for pid in ConfigLoader.get_all_passive_ids():
			if pid not in GameState.passive_slots:
				var p: Dictionary = ConfigLoader.get_passive(pid)
				var series: String = str(p.get("series", ""))
				pool.append({
					"id": pid,
					"type": "passive",
					"name": p.get("name", pid),
					"category": p.get("category", "通用被动"),
					"series": series,
					"description": p.get("description", ""),
					"weight": weight_passive * _series_weight_mult(series),
				})
	return pool


func _build_offers() -> Array[Dictionary]:
	var cfg: Dictionary = ConfigLoader.get_upgrade_config()
	var max_offers: int = int(cfg.get("max_offers", 3))
	var weapon_pity_threshold: int = int(cfg.get("weapon_pity_threshold", 2))
	var pool: Array[Dictionary] = _build_candidate_pool()
	if pool.is_empty():
		return []
	var offers: Array[Dictionary] = []
	# 武器保底看「进入本轮时」的 streak，避免同轮展示中间态干扰
	var streak_for_force: int = _pity_baseline_weapon if _choosing else _no_weapon_streak
	var force_weapon: bool = (streak_for_force >= weapon_pity_threshold) and _has_type(pool, "weapon")
	if force_weapon:
		var w: Dictionary = _pick_one(pool, "weapon")
		if not w.is_empty():
			offers.append(w)
			pool.erase(w)
	while offers.size() < max_offers and not pool.is_empty():
		var pick: Dictionary = _weighted_pick(pool)
		if pick.is_empty():
			break
		offers.append(pick)
		pool.erase(pick)
	return offers


## 系权重：本轮已出现过的系强制 ×1（Q14 出现后立即清零）；否则看进入本轮时的 miss
func _series_weight_mult(series: String) -> int:
	if series == "":
		return 1
	if _series_seen_this_choice.has(series):
		return 1
	var cfg: Dictionary = ConfigLoader.get_upgrade_config()
	var threshold: int = int(cfg.get("series_pity_threshold", 3))
	var mult: int = int(cfg.get("series_pity_mult", 3))
	var streak: int = int(_series_miss_streak.get(series, 0))
	if _choosing:
		streak = int(_pity_baseline_series.get(series, 0))
	if streak >= threshold:
		return mult
	return 1


func _has_type(pool: Array, type: String) -> bool:
	for c in pool:
		if c.get("type") == type:
			return true
	return false


func _pick_one(pool: Array, type: String) -> Dictionary:
	var candidates: Array = []
	for c in pool:
		if c.get("type") == type:
			candidates.append(c)
	if candidates.is_empty():
		return {}
	var picked: Variant = RNG.pick(candidates)
	if picked == null or not picked is Dictionary:
		return {}
	return picked as Dictionary


## 整数权重抽样（SKILL §5.5；无放回由调用方 erase 保证）
func _weighted_pick(pool: Array) -> Dictionary:
	var total: int = 0
	for c in pool:
		total += int(c.get("weight", 1))
	if total <= 0:
		var fallback: Variant = RNG.pick(pool)
		return fallback as Dictionary if fallback is Dictionary else {}
	var roll: int = RNG.randi_range(1, total)
	var cumulative: int = 0
	for c in pool:
		cumulative += int(c.get("weight", 1))
		if roll <= cumulative:
			return c as Dictionary
	return pool[pool.size() - 1] as Dictionary
