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


func _ready() -> void:
	print("[PassiveSystem] 就绪")


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


# ---- 乘率类（1 + pct/100）----

func get_damage_mult() -> float:
	return 1.0 + _total_pct("damage_pct") / 100.0


func get_attack_speed_mult() -> float:
	return 1.0 + _total_pct("attack_speed_pct") / 100.0


func get_pickup_radius_mult() -> float:
	return 1.0 + _total_pct("pickup_radius_pct") / 100.0


func get_exp_mult() -> float:
	## 钳制 ≤1.5（与验收清单 4.3.7 口径一致；当前仅 exp_sac 提供 exp_pct，10%×5=1.5 封顶）
	return clampf(1.0 + _total_pct("exp_pct") / 100.0, 1.0, 1.5)


func get_area_mult() -> float:
	## MVP 无范围软上限（GDD +120%）；现桶源仅 iron_chain，满级 +40%
	return 1.0 + _total_pct("area_pct") / 100.0


# ---- 概率/比例类（clamp 到安全上限）----

func get_damage_reduction() -> float:
	## MVP：线性百分比累加钳制 ≤0.9（≠ GDD §6.9 公式减伤与 0.70 封顶）
	## 叠加角色&灯塔减伤（W15-W16，守望者贡献 0）
	return clampf(_total_pct("damage_reduction_pct") / 100.0 + MetaSystem.get_damage_reduction_pct() / 100.0, 0.0, 0.9)


func get_crit_chance() -> float:
	## MVP：硬钳 ≤1.0（≠ GDD 暴击软上限 60% + 衰减；现仅 abyss_eye 满级 40%）
	## 叠加角色&灯塔暴击（W15-W16，守望者贡献 0）
	return clampf(_total_pct("crit_chance_pct") / 100.0 + MetaSystem.get_crit_chance_pct() / 100.0, 0.0, 1.0)


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
