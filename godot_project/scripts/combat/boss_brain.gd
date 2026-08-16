# ============================================================================
# BossBrain — Boss 行为基类（W9）
# 职责：挂在 EnemyBase 上，按 bosses.json 驱动阶段技；不走 Physics2D；召唤走对象池
# 工厂用 load() 创建子类，避免基类 preload 子类造成循环依赖
# ============================================================================
class_name BossBrain
extends RefCounted

const _PATH_JELLY := "res://scripts/combat/boss_jelly_queen.gd"
const _PATH_ARCHON := "res://scripts/combat/boss_tide_archon.gd"
const _PATH_STAR := "res://scripts/combat/boss_devouring_star.gd"

var host: EnemyBase
var data: Dictionary = {}
var phase: int = 0


static func create(behavior_type: String) -> BossBrain:
	var path: String = ""
	match behavior_type:
		"boss_jelly_queen":
			path = _PATH_JELLY
		"boss_tide_archon":
			path = _PATH_ARCHON
		"boss_devouring_star":
			path = _PATH_STAR
		_:
			return BossBrain.new()
	var script: Script = load(path) as Script
	if script == null:
		push_error("[BossBrain] 无法加载脚本: %s" % path)
		return BossBrain.new()
	var inst: Object = script.new()
	if inst is BossBrain:
		return inst as BossBrain
	push_error("[BossBrain] 脚本未继承 BossBrain: %s" % path)
	return BossBrain.new()


func setup(enemy: EnemyBase, boss_data: Dictionary) -> void:
	host = enemy
	data = boss_data
	phase = 0
	_on_setup()


func _on_setup() -> void:
	pass


func tick(delta: float, player_pos: Vector2, do_move: bool) -> void:
	if host == null or host.is_dead():
		return
	_tick(delta, player_pos, do_move)


func _tick(_delta: float, _player_pos: Vector2, _do_move: bool) -> void:
	pass


## 受伤前修正（护盾等）；默认原样
func modify_incoming_damage(amount: int) -> int:
	return amount


## 血量变化后回调（阶段切换）
func on_health_changed() -> void:
	pass


func get_float(key: String, default_value: float) -> float:
	return float(data.get(key, default_value))


func get_int(key: String, default_value: int) -> int:
	return int(data.get(key, default_value))


func get_string(key: String, default_value: String) -> String:
	return String(data.get(key, default_value))
