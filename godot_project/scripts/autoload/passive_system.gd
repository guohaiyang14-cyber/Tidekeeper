# ============================================================================
# PassiveSystem — 被动效果聚合（W12，autoload）
# 职责：从 GameState.passive_levels 聚合 8 类通用数值桶（每被动 effect 字段，per-level 百分比）
# 设计：§6.4 被动与槽位；MVP 用「通用效果桶」，钥被动深机制（燃烧/反弹/持续伤）映射为桶数值
# 调用方：weapon_base（伤害/攻速/范围/暴击/CD）、projectile（命中暴击）、
#         player（拾取半径）、GameState（减伤/经验）
# 红线：被动数据只读 config/passives.json；不持有状态（状态在 GameState）；禁止运行时 instantiate
# ============================================================================
extends Node

## 8 类通用数值桶（per-level 百分比，由 PassiveSystem 累加后转倍率/概率）
const _BUCKETS: Array[String] = [
	"damage_pct",
	"attack_speed_pct",
	"pickup_radius_pct",
	"damage_reduction_pct",
	"exp_pct",
	"crit_chance_pct",
	"area_pct",
	"cd_reduction_pct",
]

## 软上限配置缓存（从 passives.json metadata.soft_caps 加载）
var _soft_caps: Dictionary = {}


func _ready() -> void:
	_load_soft_caps()
	print("[PassiveSystem] 就绪")


## 加载软上限配置（GDD §6.9）
func _load_soft_caps() -> void:
	var meta: Dictionary = ConfigLoader.get_passives_metadata()
	_soft_caps = meta.get("soft_caps", {})
	if _soft_caps.is_empty():
		# apply_soft_cap 无 key 时不限制；减伤仍走 get_damage_reduction 内置 cap/coeff 默认
		push_warning("[PassiveSystem] passives.json 无 soft_caps：乘率类不衰减，减伤用内置公式默认")


## 软上限：超过 threshold 后额外收益按 efficiency（默认 50%）计入（GDD §6.9：软衰减，非硬截断）
## e.g., apply_soft_cap(3.0, "attack_speed") → 2.5 + (3.0 - 2.5) × 0.5 = 2.75
## 公开方法：player.gd 移速软上限也调用此方法
func apply_soft_cap(value: float, key: String) -> float:
	var cfg: Dictionary = _soft_caps.get(key, {})
	if cfg.is_empty():
		return value  # 无配置 = 不限制
	var threshold: float = float(cfg.get("threshold", 999.0))
	var efficiency: float = float(cfg.get("efficiency", 0.5))
	if value <= threshold:
		return value
	return threshold + (value - threshold) * efficiency


## 软上限阈值（读 soft_caps[key].threshold；缺省 default）
func get_soft_cap_threshold(key: String, default: float = 999.0) -> float:
	var cfg: Dictionary = _soft_caps.get(key, {})
	if cfg.is_empty():
		return default
	return float(cfg.get("threshold", default))


## 累加某桶的总百分比（已乘等级）：sum(effect[bucket] * level)
## 仅统计 config 中真实存在的被动；无效 id（测试占位）effect 为空，贡献 0
func _total_pct(bucket: String) -> float:
	assert(bucket in _BUCKETS, "未知被动桶: %s" % bucket)
	var total: float = 0.0
	for wid in GameState.passive_levels.keys():
		var sid: String = String(wid)
		var data: Dictionary = ConfigLoader.get_passive(sid)
		if data.is_empty():
			continue
		var eff: Dictionary = data.get("effect", {})
		if eff.has(bucket):
			total += float(eff[bucket]) * float(GameState.get_passive_level(sid))
	return total


# ---- 乘率类（1 + pct/100；同乘区含角色&灯塔后软上限；事件倍率在消费侧另乘）----

func get_damage_mult() -> float:
	return 1.0 + _total_pct("damage_pct") / 100.0


func get_attack_speed_mult() -> float:
	## GDD §6.9：被动 + 角色&灯塔同乘区加算后再软衰减（阈值 2.5）
	var raw: float = 1.0 + _total_pct("attack_speed_pct") / 100.0 + (MetaSystem.get_attack_speed_mult() - 1.0)
	return apply_soft_cap(raw, "attack_speed")


func get_pickup_radius_mult() -> float:
	return 1.0 + _total_pct("pickup_radius_pct") / 100.0


func get_exp_mult() -> float:
	## GDD §6.9：+200% 软上限；含角色&灯塔经验
	var raw: float = 1.0 + _total_pct("exp_pct") / 100.0 + (MetaSystem.get_exp_mult() - 1.0)
	return apply_soft_cap(raw, "exp")


func get_area_mult() -> float:
	## GDD §6.9：+120% 软上限；含角色&灯塔范围
	var raw: float = 1.0 + _total_pct("area_pct") / 100.0 + (MetaSystem.get_area_mult() - 1.0)
	return apply_soft_cap(raw, "area")


# ---- 概率/比例类（减伤公式封顶；暴击软衰减+硬顶 1.0；CD 仍硬钳）----

func get_damage_reduction() -> float:
	## GDD §6.9：有效减伤率 = min(cap, 1 - 1/(1 + coeff × 点数))
	## 点数 = 被动 damage_reduction_pct + 角色&灯塔减伤（W15-W16，守望者贡献 0）
	var cfg: Dictionary = _soft_caps.get("damage_reduction", {})
	var cap: float = float(cfg.get("cap", 0.70))
	var coeff: float = float(cfg.get("coeff", 0.02))
	var points: float = _total_pct("damage_reduction_pct") + MetaSystem.get_damage_reduction_pct()
	var reduction: float = 1.0 - 1.0 / (1.0 + coeff * points)
	return minf(reduction, cap)


func get_crit_chance() -> float:
	## GDD §6.9：暴击率软上限 60%，超过后每 1% 面板仅给 0.5% 实际；硬顶 ≤1.0
	## 叠加角色&灯塔暴击（W15-W16，守望者贡献 0）
	var raw: float = _total_pct("crit_chance_pct") / 100.0 + MetaSystem.get_crit_chance_pct() / 100.0
	return minf(apply_soft_cap(raw, "crit_chance"), 1.0)

func get_cd_reduction() -> float:
	return clampf(_total_pct("cd_reduction_pct") / 100.0, 0.0, 0.8)


## 对单次命中伤害掷暴击（每目标/每弹道命中各自调用；chance=0 不耗 RNG）
func apply_crit_to_damage(base_damage: int) -> int:
	var chance: float = get_crit_chance()
	if chance <= 0.0:
		return base_damage
	if RNG.randf() < chance:
		return int(round(float(base_damage) * ConfigLoader.get_crit_damage_mult()))
	return base_damage
