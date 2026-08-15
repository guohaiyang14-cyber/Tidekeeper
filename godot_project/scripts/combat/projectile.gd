# ============================================================================
# Projectile — 武器弹道（W5，鱼叉枪等定向弹幕使用）
# 职责：沿方向飞行；用 SpatialHash 查命中敌人造成伤害；穿透耗尽回收进池
# 红线：运行时禁止 instantiate（走 projectile_pool）；不走 Physics2D；随机走 RNG
# 注册：通过 "spatial_hash" group 查找 SpatialHashHolder
# ============================================================================
class_name Projectile
extends Node2D

# 显式预加载 EnemyBase，确保 headless 下 class_name 注册（命中检测类型依赖）
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

@export var speed: float = 420.0
@export var hit_radius: float = 14.0

## 弹道最大存活时间（秒）：即使未命中/未出界也强制回收，防止对象池被持续发射的弹道占满
## （鱼叉枪每发 5+ 弹道，稀疏/速杀场景下未命中弹道会飞到 5000 单位边界才回收，
##   约 12s 寿命 → 32 容量池几秒内耗尽 → 武器停火 → 玩家无敌防御被秒杀）
const MAX_LIFE: float = 2.0

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 0
var _pierce: int = 0
var _hash: SpatialHash
var _hit_set: Dictionary = {}  # 已命中敌人，去重
var _active: bool = false
var _life: float = 0.0


func _on_acquire() -> void:
	_active = true
	_life = 0.0
	_hit_set.clear()
	_ensure_hash()


func _on_release() -> void:
	_active = false


func _ensure_hash() -> void:
	if _hash != null:
		return
	var holders: Array = get_tree().get_nodes_in_group("spatial_hash")
	if not holders.is_empty():
		var holder: SpatialHashHolder = holders[0] as SpatialHashHolder
		if holder != null:
			_hash = holder.get_hash()


## 发射配置（由武器调用）
func launch(pos: Vector2, dir: Vector2, damage: int, pierce: int) -> void:
	global_position = pos
	_direction = dir.normalized()
	_damage = damage
	_pierce = pierce
	_life = MAX_LIFE
	if is_inside_tree():
		visible = true


func _process(delta: float) -> void:
	if not _active:
		return
	_life -= delta
	if _life <= 0.0:
		_recycle()
		return
	global_position += _direction * speed * delta
	# 命中检测（所在格 + 邻格，SKILL §2.4）
	if _hash != null:
		var candidates: Array = _hash.query_radius(global_position, hit_radius)
		for node in candidates:
			if node is EnemyBase and not _hit_set.has(node):
				_hit_set[node] = true
				(node as EnemyBase).take_damage(_damage)
				_pierce -= 1
				if _pierce < 0:
					_recycle()
					return
	# 越界回收（防止极端情况泄漏）
	if abs(global_position.x) > 5000.0 or abs(global_position.y) > 5000.0:
		_recycle()


func _recycle() -> void:
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)
