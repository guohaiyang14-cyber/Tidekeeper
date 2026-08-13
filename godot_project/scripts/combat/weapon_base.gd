# ============================================================================
# WeaponBase — 武器基类（W5）
# 职责：持有武器配置与等级；tick 计时到 attack_rate 自动 fire；伤害按等级缩放
# 红线：数值来自 config/（ConfigLoader）；随机走 RNG；运行时禁止 instantiate
# 索敌：get_target（返回 EnemyBase 或 null）、get_owner_pos（返回玩家位置）由 WeaponManager 注入
# fire(target) 为虚函数，具体武器子类实现差异化行为
# ============================================================================
class_name WeaponBase
extends Node

# 显式预加载 EnemyBase，确保 headless 下 class_name 注册（fire 参数类型依赖）
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

var weapon_id: String = ""
var weapon_data: Dictionary = {}
var level: int = 1
var attack_timer: float = 0.0

## 注入：索敌（返回最近 EnemyBase 或 null）/ 玩家位置
var get_target: Callable = Callable()
var get_owner_pos: Callable = Callable()

## 伤害/级系数（原型占位，W12 随被动系统统一校准，§6.3）
const DAMAGE_PER_LEVEL: float = 0.15


func configure(data: Dictionary, lv: int) -> void:
	weapon_data = data
	weapon_id = data.get("id", "")
	level = lv
	attack_timer = 0.0


func get_attack_rate() -> float:
	return float(weapon_data.get("attack_rate", 1.0))


func get_base_damage() -> int:
	return int(weapon_data.get("base_damage", 0))


## 等级缩放伤害（§6.3：每级 +15%）
func get_leveled_damage() -> int:
	return int(round(float(get_base_damage()) * (1.0 + DAMAGE_PER_LEVEL * float(level - 1))))


## 每帧推进计时；到点自动开火（无目标不发射、不累积）
func tick(delta: float) -> void:
	if get_target.is_null() or get_owner_pos.is_null():
		return
	var rate: float = get_attack_rate()
	if rate <= 0.0:
		return
	var target: EnemyBase = get_target.call()
	if target == null:
		return
	attack_timer += delta
	var interval: float = 1.0 / rate
	while attack_timer >= interval:
		attack_timer -= interval
		fire(target)


## 开火（子类实现；target 为当前索敌到的敌人）
func fire(_target: EnemyBase) -> void:
	pass
