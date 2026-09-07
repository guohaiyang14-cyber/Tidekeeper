# ============================================================================
# ObjectPool — 对象池基类（W1 agent 生成初稿）
# 职责：预分配节点实例，运行时 acquire/release，禁止运行时 instantiate
# 红线：运行时禁止 instantiate（SKILL.md §2.3），必须走对象池
# 用法：子类继承本类，设置 scene_class，调用 _init_pool() 预分配
#       pool.acquire() 取节点，pool.release(node) 还节点
# ============================================================================
class_name ObjectPool
extends Node

## 池中节点的场景（子类设置）
@export var scene: PackedScene

## 预分配数量
@export var pool_size: int = 100

## 池是否已初始化
var _initialized: bool = false

## 耗尽报错限流（毫秒）；风暴清场时每帧数百次 push_error 会拖死控制台
const EXHAUST_WARN_INTERVAL_MSEC: int = 3000

# 内部数据
var _pool: Array[Node] = []
var _active: Array[Node] = []
var _exhaust_warn_msec: int = -EXHAUST_WARN_INTERVAL_MSEC
var _exhaust_suppressed: int = 0


func _ready() -> void:
	if not _initialized:
		_init_pool()


## 初始化对象池：预分配 pool_size 个实例
func _init_pool() -> void:
	if scene == null:
		push_warning("[%s] 未设置 scene，跳过预分配" % name)
		return
	for i in pool_size:
		var node: Node = scene.instantiate()
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		add_child(node)
		_pool.append(node)
	_initialized = true
	print("[%s] 对象池初始化: %d 个实例" % [name, _pool.size()])


## 从池中获取一个节点（激活）
func acquire() -> Node:
	var node: Node = _find_inactive()
	if node == null:
		_warn_exhausted()
		return null
	_pool.erase(node)
	_active.append(node)
	if node is CanvasItem:
		(node as CanvasItem).visible = true
	node.process_mode = Node.PROCESS_MODE_INHERIT
	# 子类可重写 _on_acquire 做状态重置
	if node.has_method("_on_acquire"):
		node._on_acquire()
	return node


## 限流耗尽告警：首条立即打，之后合并抑制次数
func _warn_exhausted() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _exhaust_warn_msec < EXHAUST_WARN_INTERVAL_MSEC:
		_exhaust_suppressed += 1
		return
	var suppressed: int = _exhaust_suppressed
	_exhaust_suppressed = 0
	_exhaust_warn_msec = now_msec
	if suppressed > 0:
		push_error(
			"[%s] 池耗尽！active=%d/%d（其间抑制 %d 次）— 请增大 pool_size / 硬顶或检查 release"
			% [name, _active.size(), pool_size, suppressed]
		)
	else:
		push_error(
			"[%s] 池耗尽！active=%d/%d — 请增大 pool_size / 硬顶或检查 release 逻辑"
			% [name, _active.size(), pool_size]
		)


## 将节点归还池中（失活）；幂等——已归还 / 从未取出时直接返回（debug 仍告警便于抓泄漏）
func release(node: Node) -> void:
	if node == null:
		return
	if not _active.has(node):
		if OS.is_debug_build():
			push_warning("[%s] 释放了不在 active 列表中的节点" % name)
		return
	_active.erase(node)
	_pool.append(node)
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	# 子类可重写 _on_release 做状态清理
	if node.has_method("_on_release"):
		node._on_release()


## 查找池中第一个失活节点
func _find_inactive() -> Node:
	if _pool.is_empty():
		return null
	return _pool[0]


## 当前活跃节点数
func active_count() -> int:
	return _active.size()


## 当前活跃节点列表（测试 / 调试用；返回副本避免外部修改内部数组）
func get_active() -> Array[Node]:
	return _active.duplicate()


## 可用节点数
func available_count() -> int:
	return _pool.size()


## 释放所有活跃节点（场景切换/重置时调用）
func release_all() -> void:
	var snapshot: Array = _active.duplicate()
	for node in snapshot:
		release(node)


## 扩容（仅在极端情况下使用，正常应预分配足够）
func expand(extra: int) -> void:
	if scene == null:
		return
	for i in extra:
		var node: Node = scene.instantiate()
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		add_child(node)
		_pool.append(node)
	pool_size += extra
	print("[%s] 对象池扩容 +%d (当前总容量 %d)" % [name, extra, pool_size])


## difficulty.max_enemies（拾取池软扩容硬顶用）
func difficulty_max_enemies() -> int:
	return int(ConfigLoader.get_difficulty_config().get("max_enemies", 350))


## 拾取类软扩容硬顶：max(max_enemies×mult, floor)；不随 pool_size 抬升以免无上限
func pickup_soft_hard_cap(mult: int, floor_cap: int) -> int:
	return maxi(difficulty_max_enemies() * mult, floor_cap)


## 向 hard_cap 软扩容一块；已触顶返回 false（随后 acquire 走限流告警）
func soft_expand_toward(hard_cap: int, chunk: int) -> bool:
	if pool_size >= hard_cap or chunk <= 0:
		return false
	expand(mini(chunk, hard_cap - pool_size))
	return true
