# ============================================================================
# EnemyProjectile — 敌方弹幕（W2-W3）
# 职责：敌人远程攻击的弹道；朝玩家飞行，命中玩家（proximity）造成伤害后回收
# 红线：运行时禁止 instantiate（走 enemy_projectile_pool）；不走 Physics2D
# 命中：玩家不在 SpatialHash，改用距离判定（玩家加入 "player" group 供查询）
# ============================================================================
class_name EnemyProjectile
extends Node2D

@export var speed: float = 260.0
@export var hit_radius: float = 14.0

## 最大存活时间（秒）：未命中也强制回收。否则远程群在 260 速飞到 5000 边界约 19s，
## 同屏数十只水母浮游即可把 200 池打满（机器人日志：EnemyProjectilePool 池耗尽×数十）。
const MAX_LIFE: float = 3.5

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 0
var _active: bool = false
var _player: Node2D
var _life: float = 0.0


func _on_acquire() -> void:
	_active = true
	_life = 0.0
	visible = true


func _on_release() -> void:
	_active = false
	visible = false


## 发射配置（由 EnemyBase 调用）：pos 起点、dir 方向、damage 伤害
func launch(pos: Vector2, dir: Vector2, damage: int) -> void:
	global_position = pos
	_direction = dir.normalized()
	_damage = damage
	_life = MAX_LIFE


func _process(delta: float) -> void:
	if not _active:
		return
	_life -= delta
	if _life <= 0.0:
		_recycle()
		return
	global_position += _direction * speed * delta
	if _player == null:
		_player = _find_player()
	if _player != null and global_position.distance_to(_player.global_position) <= hit_radius:
		GameState.damage_player(_damage, "enemy_projectile")
		_recycle()
		return
	# 越界回收
	if abs(global_position.x) > 5000.0 or abs(global_position.y) > 5000.0:
		_recycle()


func _find_player() -> Node2D:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if not arr.is_empty():
		return arr[0] as Node2D
	return null


func _recycle() -> void:
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)
