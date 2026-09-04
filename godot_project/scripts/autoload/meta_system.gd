# ============================================================================
# MetaSystem — 局外进度（autoload 单例，W15-W16）
# 职责：角色解锁、灯塔升级树购买、角色&灯塔修正倍率聚合、星尘结算、首通标记
# 数据源：config/characters.json · config/lighthouse_tree.json · config/meta.json
# 持久化：SaveSystem（_save_data.meta，版本化迁移，见 save_system.gd）
# 红线：数值只读 config；本单例不持有战斗状态（战斗状态在 GameState）
# 修正倍率由 weapon_base / player / PassiveSystem / GameState 在运行时读取
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 MetaSystem 访问

## 待开始角色（角色选择 UI 设置；运行时作为当前角色来源）
var pending_character: String = "watcher"

## 局内激活标记：角色/灯塔特性倍率仅在正式开局后生效。
## 单元机检（w1/w12 等）不会调用 begin_run，故读到纯基线（倍率 1.0 / 加成 0），
## 避免未开局时误食默认守望者 +5% 特性、或被跨进程持久化存档污染（W15-W16 回归修复）
var _run_active: bool = false
## 灯塔效果累加缓存（购买 / begin_run / 重置时失效）
var _lh_effects_cache: Dictionary = {}
var _lh_effects_dirty: bool = true
## Debug/TestBot 会话覆盖：非 null 时 is_node_purchased / 效果聚合读此表，不落盘
var _lighthouse_override: Variant = null


## 标记一局正式开始（World._ready 调用）：此后角色/灯塔特性倍率才生效
func begin_run() -> void:
	_run_active = true
	_lh_effects_dirty = true


## 标记一局结束（World 结算时调用）：特性倍率归零，结算/非战斗阶段不应用局外修正
func end_run() -> void:
	_run_active = false
	_lh_effects_dirty = true


## 当前是否处于一局中（调试/断言用）
func is_run_active() -> bool:
	return _run_active


func _ready() -> void:
	# 触发 SaveSystem 确保 meta 已初始化
	var _m: Dictionary = SaveSystem.get_save_meta()
	print("[MetaSystem] 就绪 | 角色=%s 星尘=%d 首通=%s" % [
		get_active_character(), int(_m.get("stardust", 0)), bool(_m.get("first_clear", false)),
	])


## 当前生效角色：pending 若已解锁，否则回退默认守望者
func get_active_character() -> String:
	var c: String = pending_character if is_character_unlocked(pending_character) else "watcher"
	return c


## 设置待开始角色（角色选择 UI 调用）
func set_active_character(id: String) -> void:
	pending_character = id


# ============================================================================
# 角色解锁
# ============================================================================

## 角色是否已解锁（解锁条件：always / 累计 runs 局 / 通关 night 夜）
func is_character_unlocked(id: String) -> bool:
	var data: Dictionary = ConfigLoader.get_character(id)
	if data.is_empty():
		return false
	var unlock: Dictionary = data.get("unlock", {})
	match String(unlock.get("type", "always")):
		"always":
			return true
		"runs":
			return int(SaveSystem.get_save_meta().get("total_runs", 0)) >= int(unlock.get("count", 9999))
		"night":
			return int(SaveSystem.get_save_meta().get("max_night_cleared", 0)) >= int(unlock.get("night", 9999))
		_:
			return true


## 已解锁角色 id 列表
func get_unlocked_characters() -> Array[String]:
	var out: Array[String] = []
	for id in ConfigLoader.get_all_character_ids():
		if is_character_unlocked(String(id)):
			out.append(String(id))
	return out


## 未解锁角色的解锁提示（已解锁返回空串）
func get_character_unlock_hint(id: String) -> String:
	if is_character_unlocked(id):
		return ""
	var data: Dictionary = ConfigLoader.get_character(id)
	var unlock: Dictionary = data.get("unlock", {})
	match String(unlock.get("type", "")):
		"runs":
			return LanguageSystem.localizef("ui.unlock.runs", [
				int(unlock.get("count", 0)), int(SaveSystem.get_save_meta().get("total_runs", 0)),
			])
		"night":
			return LanguageSystem.localizef("ui.unlock.night", [
				int(unlock.get("night", 0)), int(SaveSystem.get_save_meta().get("max_night_cleared", 0)),
			])
		_:
			return ""


# ============================================================================
# 统计记录（由 World 在开局/清夜/通关时调用）
# ============================================================================

## 记录一局开始（累计 runs +1）
func record_run_started(character: String) -> void:
	var meta: Dictionary = SaveSystem.get_save_meta()
	meta["total_runs"] = int(meta.get("total_runs", 0)) + 1
	SaveSystem.set_save_meta(meta)


## 记录某夜清空（取历史最高）
func record_night_cleared(night: int) -> void:
	var meta: Dictionary = SaveSystem.get_save_meta()
	meta["max_night_cleared"] = maxi(int(meta.get("max_night_cleared", 0)), night)
	SaveSystem.set_save_meta(meta)


## 记录首次完整通关（置 first_clear）
func record_first_clear() -> void:
	var meta: Dictionary = SaveSystem.get_save_meta()
	meta["first_clear"] = true
	SaveSystem.set_save_meta(meta)


# ============================================================================
# 灯塔升级树
# ============================================================================

## 当前生效的已购灯塔表快照（会话覆盖优先；返回副本，调用方可安全改）
func get_lighthouse_purchased() -> Dictionary:
	return _lighthouse_purchased_ref().duplicate()


## 只读引用（内部查询用，避免 is_node_purchased 每次 duplicate）
func _lighthouse_purchased_ref() -> Dictionary:
	if _lighthouse_override is Dictionary:
		return _lighthouse_override as Dictionary
	var raw: Variant = SaveSystem.get_save_meta().get("lighthouse", {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


## Debug/TestBot：会话覆盖灯塔点亮状态（不写存档；传空 Dictionary 表示零升级）
func set_lighthouse_override(purchased: Dictionary) -> void:
	_lighthouse_override = purchased.duplicate()
	_lh_effects_dirty = true


## 清除会话覆盖，恢复读存档
func clear_lighthouse_override() -> void:
	_lighthouse_override = null
	_lh_effects_dirty = true


## 是否正在使用会话覆盖
func has_lighthouse_override() -> bool:
	return _lighthouse_override is Dictionary


## 节点是否已点亮
func is_node_purchased(node_id: String) -> bool:
	return bool(_lighthouse_purchased_ref().get(node_id, false))


## 节点当前是否可购买（未点亮 + 前置已点亮 + 星尘充足）
func can_purchase_node(node_id: String) -> bool:
	if is_node_purchased(node_id):
		return false
	# 会话覆盖期间禁止改存档节点，避免与 Debug 覆盖互相污染
	if has_lighthouse_override():
		return false
	var node: Dictionary = ConfigLoader.get_lighthouse_node(node_id)
	if node.is_empty():
		return false
	var req: Variant = node.get("requires", null)
	if req != null and not is_node_purchased(String(req)):
		return false
	return get_stardust() >= int(node.get("cost", 9999))


## 购买节点（成功扣星尘并落盘，返回是否成功）
func purchase_node(node_id: String) -> bool:
	if not can_purchase_node(node_id):
		return false
	var node: Dictionary = ConfigLoader.get_lighthouse_node(node_id)
	var meta: Dictionary = SaveSystem.get_save_meta()
	meta["stardust"] = int(meta.get("stardust", 0)) - int(node.get("cost", 0))
	var lh: Dictionary = meta.get("lighthouse", {})
	if not (lh is Dictionary):
		lh = {}
	lh[node_id] = true
	meta["lighthouse"] = lh
	SaveSystem.set_save_meta(meta)
	_lh_effects_dirty = true
	print("[MetaSystem] 点亮灯塔节点 %s（剩余星尘 %d）" % [node_id, int(meta["stardust"])])
	return true


## 当前星尘余额
func get_stardust() -> int:
	return int(SaveSystem.get_save_meta().get("stardust", 0))


# ============================================================================
# 修正倍率聚合（当前角色特性 + 已购灯塔节点效果，战运行时读取）
# ============================================================================

## 当前角色特性表
func _character_traits() -> Dictionary:
	return ConfigLoader.get_character(get_active_character()).get("traits", {})


## 已购灯塔节点效果累加表
func _lighthouse_effects() -> Dictionary:
	if not _lh_effects_dirty:
		return _lh_effects_cache
	var out: Dictionary = {}
	var lh: Dictionary = _lighthouse_purchased_ref()
	for node_id in lh.keys():
		if not bool(lh[node_id]):
			continue
		var node: Dictionary = ConfigLoader.get_lighthouse_node(String(node_id))
		if node.is_empty():
			continue
		for k in (node.get("effects", {}) as Dictionary).keys():
			out[k] = float(out.get(k, 0.0)) + float((node["effects"] as Dictionary)[k])
	_lh_effects_cache = out
	_lh_effects_dirty = false
	return _lh_effects_cache


## 累加某修正 key 的总百分比（角色 + 灯塔）。
## 未开局（_run_active=false）时返回 0，保证单元机检读到纯基线，且不读取被跨进程污染的存档
func _sum_pct(key: String) -> float:
	if not _run_active:
		return 0.0
	var v: float = float(_character_traits().get(key, 0.0))
	v += float(_lighthouse_effects().get(key, 0.0))
	return v


func get_damage_mult() -> float:
	return 1.0 + _sum_pct("damage_pct") / 100.0


func get_attack_speed_mult() -> float:
	return 1.0 + _sum_pct("attack_speed_pct") / 100.0


func get_area_mult() -> float:
	return 1.0 + _sum_pct("area_pct") / 100.0


func get_move_speed_mult() -> float:
	return 1.0 + _sum_pct("move_speed_pct") / 100.0


func get_exp_mult() -> float:
	return 1.0 + _sum_pct("exp_pct") / 100.0


func get_damage_reduction_pct() -> float:
	return _sum_pct("damage_reduction_pct")


func get_crit_chance_pct() -> float:
	return _sum_pct("crit_chance_pct")


## 额外弹道数（取整；弹道+1 → 1）
func get_extra_projectiles() -> int:
	return int(round(_sum_pct("projectile_bonus")))


## 灯塔附加最大生命（取整，叠加到角色基础生命）
func get_max_health_bonus() -> int:
	return int(round(_sum_pct("max_health")))


## 灯塔每休息夜额外回血（取整）
func get_regen_per_night() -> int:
	return int(round(_sum_pct("regen_per_night")))


# ============================================================================
# 星尘结算（基础 × 进度 × 难度 × 首胜）
# ============================================================================

## 局终结算星尘。nights_survived = 本局到达的夜次（1~20）；is_win = 是否通关 20 夜
## extra_stardust = 本局事件星尘（星尘雨等，叠在公式与失败保底之后）
## 返回本次获得星尘；并累加到 meta.stardust 落盘；首通额外 ×first_clear_mult（仅首次）
## W17 失败保底：落败时本次获得不低于 floor_pct ×（满通应得），保证最低挫败补偿
func settle_stardust(nights_survived: int, is_win: bool, extra_stardust: int = 0) -> int:
	var cfg: Dictionary = ConfigLoader.get_meta_config().get("stardust", {})
	var base: float = float(cfg.get("base", 60))
	var difficulty: float = float(cfg.get("difficulty", 1.0))
	var progress: float = clampf(float(nights_survived) / 20.0, 0.0, 1.0)
	var meta: Dictionary = SaveSystem.get_save_meta()
	var first_mult: float = 1.0
	if is_win and not bool(meta.get("first_clear", false)):
		first_mult = float(cfg.get("first_clear_mult", 1.5))
	var earned: int = roundi(base * progress * difficulty * first_mult)
	if earned < 0:
		earned = 0
	# W17 失败保底：落败时不低于 floor_pct × 满通应得（须 fallback.enabled）
	if not is_win:
		var floor_cfg: Dictionary = ConfigLoader.get_frustration_config().get("fallback", {})
		if bool(floor_cfg.get("enabled", false)):
			var floor_pct: float = float(floor_cfg.get("floor_pct", 0.0))
			if floor_pct > 0.0:
				var full_clear: float = base * difficulty * first_mult  # 满通应得（落败首通倍率恒 1）
				var floor_earned: int = roundi(full_clear * floor_pct)
				if floor_earned > earned:
					earned = floor_earned
	# 本局事件星尘（星尘雨等）在保底之后叠加，避免被公式吃掉
	earned += maxi(0, extra_stardust)
	meta["stardust"] = int(meta.get("stardust", 0)) + earned
	if is_win:
		meta["first_clear"] = true
	SaveSystem.set_save_meta(meta)
	print("[MetaSystem] 结算星尘 +%d（累计 %d）" % [earned, int(meta["stardust"])])
	return earned


## 清空全部局外进度（测试 / 调试用）
func reset_progress() -> void:
	SaveSystem.reset_save_meta()
	pending_character = "watcher"
	_lighthouse_override = null
	_lh_effects_dirty = true
