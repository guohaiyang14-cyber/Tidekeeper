# ============================================================================
# EnemyBase — 最小敌人（W5 占位，供武器索敌 / 受伤 / 死亡）
# 职责：冲撞行为朝玩家移动；受伤 → 死亡 → 回收对象池；注册自定义 SpatialHash
# 红线：不走 Physics2D（SKILL.md §2.4）；随机走 RNG；不分帧外分配
# 注册：通过 "spatial_hash" group 查找 SpatialHashHolder（World 注入）
# 死亡：emit enemy_died → 调父池 release（触发 _on_release 从 hash 移除）
# ============================================================================
class_name EnemyBase
extends Node2D

signal enemy_died(enemy: EnemyBase)

@export var max_health: int = 30
@export var move_speed: float = 60.0
@export var contact_damage: int = 8
@export var update_group: int = 2  # 分帧：1=每帧, 2=每2帧, 4=每4帧

var health: int = 0
var target: Node2D
var _hash: SpatialHash
var _dead: bool = false


## 池 acquire 时调用（ObjectPool 约定）：仅重置状态，不注册哈希
func _on_acquire() -> void:
	_dead = false
	health = max_health
	_ensure_hash()


## 池 release 时调用（ObjectPool 约定）：从哈希移除
func _on_release() -> void:
	if _hash != null:
		_hash.remove(self, global_position)


func _ensure_hash() -> void:
	if _hash != null:
		return
	var holders: Array = get_tree().get_nodes_in_group("spatial_hash")
	if not holders.is_empty():
		var holder: SpatialHashHolder = holders[0] as SpatialHashHolder
		if holder != null:
			_hash = holder.get_hash()


## 刷怪生成：设位置与目标，并注册到空间哈希（由 World 调用）
func spawn_at(pos: Vector2, tgt: Node2D) -> void:
	global_position = pos
	target = tgt
	if _hash != null:
		_hash.insert(self)


func _process(delta: float) -> void:
	if _dead:
		return
	if Engine.get_process_frames() % update_group != 0:
		return
	if target == null:
		return
	var old_pos: Vector2 = global_position
	var direction: Vector2 = (target.global_position - global_position).normalized()
	global_position += direction * move_speed * delta
	if _hash != null:
		_hash.update(self, old_pos)


## 受伤（返回是否致死）
func take_damage(amount: int) -> bool:
	if _dead:
		return false
	health -= amount
	if health <= 0:
		_die()
		return true
	return false


func _die() -> void:
	if _dead:
		return
	_dead = true
	enemy_died.emit(self)
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)
