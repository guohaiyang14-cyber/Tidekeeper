# ============================================================================
# ConfigLoader — 配置表加载器（autoload 单例）
# 职责：启动时加载 config/*.json 到内存，运行时只读
# 红线：禁止硬编码数值（SKILL.md §4.2），所有数据从此单例读取
# 数据源：仓库根目录 config/（在 godot_project/ 上一级）
# ============================================================================
extends Node

# 注：autoload 单例不应声明 class_name（Godot 4.x 会冲突）
# 全局通过 autoload 名 ConfigLoader 访问

# 配置目录相对 res:// 的路径（godot_project/ 上一级）
const _CONFIG_RELATIVE_PATH := "../config/"

# 加载完成的配置数据（运行时只读）
var weapons: Dictionary = {}
var enemies: Dictionary = {}
var bosses: Dictionary = {}
var events: Dictionary = {}
var affixes: Dictionary = {}
var passives: Dictionary = {}
var pickups: Dictionary = {}
var upgrade: Dictionary = {}
var evolutions: Dictionary = {}
var refine: Dictionary = {}
# W15-W16 局外进度配置
var characters: Dictionary = {}
var lighthouse: Dictionary = {}
var meta_cfg: Dictionary = {}
# 灯塔节点扁平表（branch.nodes 展开，便于按 id 查询）
var _lighthouse_nodes: Dictionary = {}
# W17 挫败感控制配置
var frustration: Dictionary = {}
# W18 难度系统配置（档位 / 教学宽容）
var difficulty: Dictionary = {}

# 配置目录绝对路径
var config_dir: String = ""

# 加载状态
var is_loaded: bool = false


func _ready() -> void:
	_resolve_config_dir()
	_load_all()


## 解析 config 目录绝对路径（兼容编辑器运行与导出运行）
func _resolve_config_dir() -> void:
	var res_abs: String = ProjectSettings.globalize_path("res://")
	config_dir = res_abs + _CONFIG_RELATIVE_PATH
	# 规范化路径分隔符（Windows 兼容）
	config_dir = config_dir.replace("\\", "/")


## 加载全部配置文件
func _load_all() -> void:
	weapons = _load_json("weapons.json", true)
	enemies = _load_json("enemies.json", true)
	bosses = _load_json("bosses.json", true)
	events = _load_json("events.json", true)
	passives = _load_json("passives.json", true)
	pickups = _load_json("pickups.json", true)
	upgrade = _load_json("upgrade.json", true)
	evolutions = _load_json("evolutions.json", true)
	refine = _load_json("refine_paths.json", true)
	# W15-W16 局外进度配置（角色 / 灯塔树 / 星尘结算参数）
	characters = _load_json("characters.json", true)
	lighthouse = _load_json("lighthouse_tree.json", true)
	meta_cfg = _load_json("meta.json", true)
	_flatten_lighthouse_nodes()
	# W17 挫败感控制配置（首夜保护 / 挣扎模式 / 失败保底 / 死因可视化）
	frustration = _load_json("frustration.json", true)
	# W18 难度系统配置（档位 守夜人0.7× / 灯塔1.0× + 教学宽容 1~4 夜减半）
	difficulty = _load_json("difficulty.json", true)

	# enemies.json 内嵌 affixes 子表
	if enemies.has("affixes"):
		affixes = enemies["affixes"]

	# 校验计数（对齐设计文档红线）
	_validate_counts()

	is_loaded = true
	print("[ConfigLoader] 配置加载完成: weapons=%d enemies=%d bosses=%d events=%d affixes=%d passives=%d evolutions=%d pickups=%s upgrade=%s" % [
		weapons.get("weapons", {}).size(),
		enemies.get("enemies", {}).size(),
		bosses.get("bosses", {}).size(),
		events.get("events", {}).size(),
		get_all_affix_ids().size(),
		passives.get("passives", {}).size(),
		evolutions.get("paths", {}).size(),
		"ok" if pickups.has("exp_gem") else "missing",
		"ok" if upgrade.has("reroll_cost") else "missing",
	])


## 加载单个 JSON 文件（返回 Dictionary）
func _load_json(filename: String, required: bool) -> Dictionary:
	var path: String = config_dir + filename
	if not FileAccess.file_exists(path):
		if required:
			push_error("[ConfigLoader] 配置文件缺失: %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[ConfigLoader] 无法打开: %s (error=%d)" % [path, FileAccess.get_open_error()])
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[ConfigLoader] JSON 解析失败: %s" % path)
		return {}
	return parsed as Dictionary


## 校验配置计数对齐设计文档 MVP 范围
func _validate_counts() -> void:
	var checks: Array = [
		["weapons", "weapons", 8],
		["enemies", "enemies", 9],
		["bosses", "bosses", 3],
		["events", "events", 7],
		["passives", "passives", 12],
	]
	var evo_paths: int = evolutions.get("paths", {}).size()
	if evo_paths != 8:
		push_warning("[ConfigLoader] evolutions.paths 计数 %d != 预期 8（MVP 红线）" % evo_paths)
	var refine_paths: int = refine.get("paths", {}).size()
	if refine_paths != 8:
		push_warning("[ConfigLoader] refine.paths 计数 %d != 预期 8（MVP 红线）" % refine_paths)
	for check in checks:
		var table_key: String = check[0]
		var data_key: String = check[1]
		var expected: int = check[2]
		var table: Dictionary = get(table_key)
		var actual: int = table.get(data_key, {}).size()
		if actual != expected:
			push_warning("[ConfigLoader] %s.%s 计数 %d != 预期 %d（MVP 红线）" % [table_key, data_key, actual, expected])


# ============================================================================
# 公共查询接口（运行时只读）
# ============================================================================

## 获取武器数据（按 id）
func get_weapon(weapon_id: String) -> Dictionary:
	return weapons.get("weapons", {}).get(weapon_id, {})

## 武器等级上限（来自 weapons.json metadata.max_weapon_level，§6.3）
func get_max_weapon_level() -> int:
	return int(weapons.get("metadata", {}).get("max_weapon_level", 7))

## 获取全部武器 id 列表
func get_all_weapon_ids() -> Array:
	return weapons.get("weapons", {}).keys()

## 获取敌人数据（按 id）
func get_enemy(enemy_id: String) -> Dictionary:
	return enemies.get("enemies", {}).get(enemy_id, {})

## 敌人难度系数（来自 enemies.json metadata.difficulty）
func get_enemy_difficulty() -> Dictionary:
	return enemies.get("metadata", {}).get("difficulty", {})

## 敌人刷怪参数（来自 enemies.json metadata.spawn）
func get_enemy_spawn() -> Dictionary:
	return enemies.get("metadata", {}).get("spawn", {})


## 敌人战斗通用参数（来自 enemies.json metadata.combat）
func get_enemy_combat() -> Dictionary:
	return enemies.get("metadata", {}).get("combat", {})


## 敌人精英夜参数（来自 enemies.json metadata.elite）
func get_enemy_elite() -> Dictionary:
	return enemies.get("metadata", {}).get("elite", {})


## 武器商店参数（来自 weapons.json metadata.shop）
func get_weapon_shop_meta() -> Dictionary:
	return weapons.get("metadata", {}).get("shop", {})


## 开局默认武器（来自 weapons.json metadata.starting_weapon，数据驱动避免硬编码 §4.2）
func get_starting_weapon() -> String:
	return weapons.get("metadata", {}).get("starting_weapon", "")


## 武器每级伤害加成系数（来自 weapons.json metadata.damage_per_level，§6.3）
func get_damage_per_level() -> float:
	return float(weapons.get("metadata", {}).get("damage_per_level", 0.15))


## 被动商店参数（来自 passives.json metadata.shop）
func get_passive_shop_meta() -> Dictionary:
	return passives.get("metadata", {}).get("shop", {})


## 商店折扣后实付价（购买与重铸退款共用，单一真源）
func discounted_shop_price(base: int, discount: float) -> int:
	return maxi(1, roundi(float(base) * (1.0 - discount)))


## 某类商品实付价（weapon / passive；全局统一定价，不按 id）
func get_shop_paid_cost(kind: String) -> int:
	var meta: Dictionary = get_weapon_shop_meta() if kind == "weapon" else get_passive_shop_meta()
	var default_cost: int = 30 if kind == "weapon" else 20
	return discounted_shop_price(int(meta.get("cost", default_cost)), float(meta.get("discount", 0.2)))


## 重铸回收比例（metadata.shop.refund_ratio，默认 0.8）
func get_shop_refund_ratio(kind: String) -> float:
	var meta: Dictionary = get_weapon_shop_meta() if kind == "weapon" else get_passive_shop_meta()
	return float(meta.get("refund_ratio", 0.8))


## 休息夜间隔（upgrade.json rest_interval_nights，每 N 夜一次灯塔大回血）
func get_rest_interval_nights() -> int:
	return int(get_upgrade_config().get("rest_interval_nights", 5))


## 获取全部敌人 id 列表
func get_all_enemy_ids() -> Array:
	return enemies.get("enemies", {}).keys()

## 获取 Boss 数据（按 id）
func get_boss(boss_id: String) -> Dictionary:
	return bosses.get("bosses", {}).get(boss_id, {})


## 天灾夹击规则（bosses.json metadata.calamity）
func get_boss_calamity() -> Dictionary:
	return bosses.get("metadata", {}).get("calamity", {})


## 灯塔光晕参数（bosses.json metadata.lighthouse）
func get_lighthouse_meta() -> Dictionary:
	return bosses.get("metadata", {}).get("lighthouse", {})


## 按夜次获取 Boss（第 10/15/20 夜）
func get_boss_by_night(night: int) -> Dictionary:
	for boss in bosses.get("bosses", {}).values():
		if boss.get("night") == night:
			return boss
	return {}

## 获取事件数据（按 id）
func get_event(event_id: String) -> Dictionary:
	return events.get("events", {}).get(event_id, {})

## 获取第 N 夜可用事件池（排除 excluded_nights 命中的事件）
## 注意：JSON 数值解析为 float，需 int 比较（否则 15 in [15.0] 判定为 false，导致第 15 夜排除失效）
func get_events_for_night(night: int) -> Array:
	var result: Array = []
	for event in events.get("events", {}).values():
		var excluded: Array = event.get("excluded_nights", [])
		var skip: bool = false
		for v in excluded:
			if int(v) == night:
				skip = true
				break
		if skip:
			continue
		result.append(event)
	return result

## 获取词缀数据（按 id）
func get_affix(affix_id: String) -> Dictionary:
	return affixes.get(affix_id, {})


## 全部词缀 id（排除 _meta）
func get_all_affix_ids() -> Array[String]:
	var out: Array[String] = []
	for k in affixes.keys():
		var id: String = String(k)
		if id == "_meta":
			continue
		out.append(id)
	return out


## 词缀施加规则（精英 2~3 / 天灾全场 +1 / 教学夜无词缀）
func get_affix_rules() -> Dictionary:
	return enemies.get("metadata", {}).get("affix_rules", {})

## 获取难度公式元数据（§8.2）
func get_difficulty_formula() -> Dictionary:
	return enemies.get("metadata", {}).get("difficulty_formula", {})

## 获取 W18 难度系统配置（档位 / 教学宽容）
func get_difficulty_config() -> Dictionary:
	return difficulty

## 获取经验珠拾取参数（W2）
func get_exp_gem_config() -> Dictionary:
	return pickups.get("exp_gem", {})

## 获取被动数据（按 id）
func get_passive(passive_id: String) -> Dictionary:
	return passives.get("passives", {}).get(passive_id, {})

## 获取全部被动 id 列表
func get_all_passive_ids() -> Array:
	return passives.get("passives", {}).keys()

## 获取被动系名列表（去重，来自 passives.json）
func get_all_passive_series() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for p in passives.get("passives", {}).values():
		var series: String = str(p.get("series", ""))
		if series == "" or seen.has(series):
			continue
		seen[series] = true
		result.append(series)
	return result

## 三选一数值配置（§6.2）
func get_upgrade_config() -> Dictionary:
	return upgrade


## 进化总表
func get_evolutions() -> Dictionary:
	return evolutions


func get_evolution_rules() -> Dictionary:
	return evolutions.get("rules", {})


func get_evolution_drops() -> Dictionary:
	return evolutions.get("drops", {})


func get_evolution_path(weapon_id: String) -> Dictionary:
	return evolutions.get("paths", {}).get(weapon_id, {})


func get_all_evolution_weapon_ids() -> Array:
	return evolutions.get("paths", {}).keys()


## 精炼总表
func get_refine() -> Dictionary:
	return refine


func get_refine_rules() -> Dictionary:
	return refine.get("rules", {})


func get_refine_path(weapon_id: String) -> Dictionary:
	return refine.get("paths", {}).get(weapon_id, {})


func get_all_refine_weapon_ids() -> Array:
	return refine.get("paths", {}).keys()


## 精炼累积伤害倍率：tier>=1 乘 tier_I.dps_mult；tier>=2 再乘 tier_II.dps_mult（与设计 §6.6 乘区分离一致）
func get_refine_multiplier(weapon_id: String, tier: int) -> float:
	var path: Dictionary = get_refine_path(weapon_id)
	if path.is_empty() or tier <= 0:
		return 1.0
	var m: float = 1.0
	if tier >= 1 and path.has("tier_I"):
		m *= float(path["tier_I"].get("dps_mult", 1.0))
	if tier >= 2 and path.has("tier_II"):
		m *= float(path["tier_II"].get("dps_mult", 1.0))
	return m


## 被动等级上限
func get_max_passive_level() -> int:
	var from_evo: int = int(get_evolution_rules().get("passive_max_level", 0))
	if from_evo > 0:
		return from_evo
	return int(passives.get("metadata", {}).get("max_passive_level", 5))


## 暴击伤害倍率（passives.json metadata.crit_damage_mult，对齐 GDD ×1.8）
func get_crit_damage_mult() -> float:
	return float(passives.get("metadata", {}).get("crit_damage_mult", 1.8))


# ============================================================================
# W15-W16 局外进度配置查询接口
# ============================================================================

## 将 lighthouse_tree.json 的 branches.*.nodes 展开为 id → 节点 的扁平表
func _flatten_lighthouse_nodes() -> void:
	_lighthouse_nodes = {}
	for branch in lighthouse.get("branches", {}).values():
		for node_id in (branch as Dictionary).get("nodes", {}).keys():
			_lighthouse_nodes[node_id] = (branch as Dictionary)["nodes"][node_id]


## 全部角色 id（排除 _meta/metadata）
func get_all_character_ids() -> Array[String]:
	var out: Array[String] = []
	for k in characters.get("characters", {}).keys():
		out.append(String(k))
	return out


## 角色数据（按 id）
func get_character(id: String) -> Dictionary:
	return characters.get("characters", {}).get(id, {})


## 角色开局武器（按 id；缺省回退全局 starting_weapon）
func get_character_starting_weapon(id: String) -> String:
	var c: Dictionary = get_character(id)
	if not c.is_empty() and c.has("starting_weapon"):
		return String(c["starting_weapon"])
	return get_starting_weapon()


## 角色最大生命（按 id；缺省 100）
func get_character_max_health(id: String) -> int:
	return int(get_character(id).get("max_health", 100))


## 角色基础移速（按 id；缺省 4.2，对齐 GDD §9.4）
func get_character_move_speed(id: String) -> float:
	return float(get_character(id).get("move_speed", 4.2))


## 全部灯塔节点（扁平）
func get_all_lighthouse_nodes() -> Dictionary:
	return _lighthouse_nodes


## 灯塔节点（按 id）
func get_lighthouse_node(node_id: String) -> Dictionary:
	return _lighthouse_nodes.get(node_id, {})


## 灯塔全部分支（branch_id → {name, desc, nodes}）
func get_lighthouse_branches() -> Dictionary:
	return lighthouse.get("branches", {})


## 星尘结算参数（meta.json stardust）
func get_meta_config() -> Dictionary:
	return meta_cfg


## 挫败感控制参数（frustration.json；W17 首夜保护 / 挣扎模式 / 失败保底 / 死因可视化）
func get_frustration_config() -> Dictionary:
	return frustration
