# ============================================================================
# W1UnitTests — 对象池 / 空间哈希 / RNG / 经验表最小单测
# 运行：godot --headless --path godot_project res://scenes/tests/w1_unit_tests.tscn
# 退出码：0=全部通过，1=有失败
# ============================================================================
extends Node

const STUB_SCENE := preload("res://scenes/poolable_stub.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W1 Unit Tests")
	print("============================================================")
	# 清空局外进度（防御性）：保证 max_health=100 断言不依赖被其他机检污染的存档
	MetaSystem.reset_progress()
	_test_spatial_hash()
	await _test_object_pool()
	_test_rng_deterministic()
	_test_exp_table()
	_test_game_state_leveling()
	await _test_starting_weapon_and_game_over()
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	print("============================================================")
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _test_spatial_hash() -> void:
	print("[SpatialHash]")
	var hash := SpatialHash.new(80.0)
	var a := Node2D.new()
	var b := Node2D.new()
	add_child(a)
	add_child(b)
	a.global_position = Vector2(10, 10)
	b.global_position = Vector2(200, 200)
	hash.insert(a)
	hash.insert(b)
	_assert(hash.total_nodes() == 2, "insert two nodes")
	_assert(hash.query_cell(Vector2(10, 10)).has(a), "query_cell finds a")
	_assert(not hash.query_cell(Vector2(10, 10)).has(b), "query_cell excludes far b")
	var near: Array = hash.query_radius(Vector2(10, 10), 0.0)
	_assert(near.has(a), "query_radius center+neighbors includes a")
	hash.update(a, Vector2(10, 10))
	a.global_position = Vector2(240, 240)
	hash.update(a, Vector2(10, 10))
	_assert(hash.query_cell(Vector2(240, 240)).has(a), "update moves cell")
	hash.remove(b, Vector2(200, 200))
	_assert(hash.total_nodes() == 1, "remove leaves one")
	hash.clear()
	_assert(hash.total_nodes() == 0 and hash.cell_count() == 0, "clear empties")
	a.queue_free()
	b.queue_free()


func _test_object_pool() -> void:
	print("[ObjectPool]")
	var pool := ObjectPool.new()
	pool.name = "TestPool"
	pool.scene = STUB_SCENE
	pool.pool_size = 4
	add_child(pool)
	# _ready 已预分配
	await get_tree().process_frame
	_assert(pool.available_count() == 4, "preallocate 4")
	_assert(pool.active_count() == 0, "none active initially")
	var n1: Node = pool.acquire()
	var n2: Node = pool.acquire()
	_assert(n1 != null and n2 != null and n1 != n2, "acquire distinct nodes")
	_assert(pool.active_count() == 2 and pool.available_count() == 2, "active/available after acquire")
	_assert(n1 is CanvasItem and (n1 as CanvasItem).visible, "acquired visible")
	pool.release(n1)
	_assert(pool.active_count() == 1 and pool.available_count() == 3, "release returns to pool")
	_assert(not (n1 as CanvasItem).visible, "released hidden")
	pool.release_all()
	_assert(pool.active_count() == 0 and pool.available_count() == 4, "release_all")
	# 耗尽
	var grabbed: Array[Node] = []
	for i in 4:
		grabbed.append(pool.acquire())
	var overflow: Node = pool.acquire()
	_assert(overflow == null, "exhausted returns null")
	for n in grabbed:
		pool.release(n)
	pool.queue_free()


func _test_rng_deterministic() -> void:
	print("[RNG]")
	RNG.set_seed(42)
	var seq_a: Array = [RNG.randi_range(0, 1000), RNG.randf(), RNG.pick([10, 20, 30, 40])]
	RNG.set_seed(42)
	var seq_b: Array = [RNG.randi_range(0, 1000), RNG.randf(), RNG.pick([10, 20, 30, 40])]
	_assert(seq_a == seq_b, "same seed same sequence")
	RNG.set_seed(99)
	var first_99: int = RNG.randi_range(0, 1000)
	_assert(first_99 != seq_a[0], "different seed diverges")
	RNG.set_seed(7)
	var picks: Array = RNG.pick_n([1, 2, 3, 4, 5], 3)
	_assert(picks.size() == 3, "pick_n size")
	var shuffled: Array = RNG.shuffle([1, 2, 3])
	_assert(shuffled.size() == 3, "shuffle size")


func _test_exp_table() -> void:
	print("[ExpTable]")
	_assert(ExpTable.get_max_level() == 30, "max_level 30")
	_assert(ExpTable.get_exp(1) == 22, "E(1)=22")
	_assert(ExpTable.get_exp(10) == 83, "E(10)=83")
	_assert(ExpTable.get_exp(20) == 216, "E(20)=216")
	_assert(ExpTable.get_exp(30) == 0, "E(30) next=0 (capped)")
	_assert(ExpTable.get_exp_to_reach(1) == 0, "reach Lv1 costs 0")
	_assert(ExpTable.get_exp_to_reach(2) == 22, "reach Lv2 costs 22")
	_assert(ExpTable.get_exp_to_reach(3) == 49, "reach Lv3 costs 49")
	_assert(ExpTable.get_level_from_exp(0) == 1, "0 exp -> Lv1")
	_assert(ExpTable.get_level_from_exp(21) == 1, "21 exp -> Lv1")
	_assert(ExpTable.get_level_from_exp(22) == 2, "22 exp -> Lv2")
	_assert(ExpTable.get_level_from_exp(49) == 3, "49 exp -> Lv3")


func _test_game_state_leveling() -> void:
	print("[GameState.add_exp]")
	GameState.start_new_run("watcher", 12345)
	_assert(GameState.player_level == 1 and GameState.player_exp == 0, "fresh run Lv1")
	_assert(GameState.player_max_health == 100, "watcher HP 100")
	_assert(GameState.run_seed == 12345, "seed applied")
	GameState.add_exp(21)
	_assert(GameState.player_level == 1 and GameState.player_exp == 21, "21 < E(1)")
	GameState.add_exp(1)
	_assert(GameState.player_level == 2 and GameState.player_exp == 0, "22 -> Lv2")
	GameState.add_exp(27)
	_assert(GameState.player_level == 3 and GameState.player_exp == 0, "E(2)=27 -> Lv3")


## 开局默认武器授予 + 游戏结束只触发一次 + 昼夜循环冻结（修复 §4.2 / 用户反馈）
func _test_starting_weapon_and_game_over() -> void:
	print("[StartWeapon + GameOver]")
	# 1) 开局应授予数据驱动默认武器，避免 0 武器无法攻击的死亡螺旋
	GameState.start_new_run("watcher", 777)
	_assert(ConfigLoader.get_starting_weapon() == "harpoon", "config starting_weapon = harpoon")
	_assert(GameState.weapon_slots.has("harpoon"), "start_new_run grants starting weapon")
	_assert(GameState.get_weapon_level("harpoon") == 1, "starting weapon level = 1")
	# 2) 游戏结束只触发一次（is_over 守卫，防止敌人逐帧重复触发）
	# 计数用引用类型（Array），避免 GDScript lambda 对 int 的按值捕获
	var tally: Array[int] = [0]
	var cb := func(_r: String): tally[0] += 1
	GameState.game_over.connect(cb)
	GameState.trigger_game_over("hp_zero")
	GameState.trigger_game_over("hp_zero")  # 重复触发
	GameState.damage_player(999)            # 再次撞击归零
	await get_tree().process_frame
	GameState.game_over.disconnect(cb)
	_assert(tally[0] == 1, "game_over emitted exactly once")
	# 3) 昼夜循环停止后冻结（phase=INIT，_process 不再推进夜晚计时器 / 不会滚入 DAY）
	var dn := DayNightStateMachine.new()
	add_child(dn)
	dn.start_run()
	await get_tree().process_frame
	_assert(dn.get_phase() == DayNightStateMachine.Phase.NIGHT, "start_run -> NIGHT")
	dn.stop()
	await get_tree().process_frame
	_assert(dn.get_phase() == DayNightStateMachine.Phase.INIT, "stop freezes to INIT")
	dn.queue_free()
