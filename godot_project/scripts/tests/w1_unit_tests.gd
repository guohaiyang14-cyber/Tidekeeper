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
	_assert(not TestBot.is_active(), "headless 下 TestBot 关闭")
	_test_spatial_hash()
	await _test_object_pool()
	_test_rng_deterministic()
	_test_exp_table()
	_test_game_state_leveling()
	await _test_starting_weapon_and_game_over()
	_test_teaching_demo_weapons()
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


## 教学夜武器展示：按 difficulty.json teaching.demo_weapons 顺序在夜2/3/4 授予尚未拥有的武器；
## 夜1（非展示）/ 夜5（非教学）/ 已拥有 → 不授予（幂等）。
func _test_teaching_demo_weapons() -> void:
	print("[教学夜武器展示]")
	var demo: Array = ConfigLoader.get_teaching_demo_weapons()
	if demo.is_empty():
		print("  [SKIP] teaching.demo_weapons 为空")
		return
	GameState.start_new_run("watcher", 20260824)
	_assert(GameState.weapon_slots.size() == 1, "开局仅 1 把武器")
	_assert(GameState.grant_teaching_demo_weapon(1) == "", "夜1 不授予展示武器")
	for n in range(2, 5):
		var idx: int = n - 2
		var expect: String = String(demo[idx]) if idx < demo.size() else ""
		var wid: String = GameState.grant_teaching_demo_weapon(n)
		_assert(wid == expect, "夜%d 授予展示武器 %s (期望 %s)" % [n, wid, expect])
		if wid != "":
			_assert(not ConfigLoader.get_weapon(wid).is_empty(), "授予的 %s 是有效武器" % wid)
			_assert(GameState.weapon_slots.has(wid), "授予后入槽: %s" % wid)
	_assert(GameState.grant_teaching_demo_weapon(5) == "", "夜5(非教学) 不授予")
	var before: int = GameState.weapon_slots.size()
	_assert(GameState.grant_teaching_demo_weapon(2) == "", "已拥有的夜2 不再授予（幂等）")
	_assert(GameState.weapon_slots.size() == before, "幂等：槽数不变")
	# 铁匠开局锚锤：夜4 顺位为 anchor_hammer 已持有 → 不重复授予
	GameState.start_new_run("blacksmith", 20260825)
	_assert(GameState.weapon_slots.has("anchor_hammer"), "铁匠开局锚锤")
	_assert(GameState.grant_teaching_demo_weapon(2) == "holy_fire", "铁匠夜2 圣火")
	_assert(GameState.grant_teaching_demo_weapon(3) == "storm_cloud", "铁匠夜3 雷暴云")
	_assert(GameState.grant_teaching_demo_weapon(4) == "", "铁匠夜4 顺位锚锤已持有且无新武器")
	# 星象师开局雷暴云：夜3 顺位已持有 → 向前扫描授予 anchor_hammer
	GameState.start_new_run("stargazer", 20260826)
	_assert(GameState.weapon_slots.has("storm_cloud"), "星象师开局雷暴云")
	_assert(GameState.grant_teaching_demo_weapon(2) == "holy_fire", "星象师夜2 圣火")
	_assert(GameState.grant_teaching_demo_weapon(3) == "anchor_hammer", "星象师夜3 回补锚锤")
	_assert(GameState.grant_teaching_demo_weapon(4) == "", "星象师夜4 演示武器已齐")
	# 武器槽满时不再授予
	GameState.start_new_run("watcher", 20260827)
	GameState.add_weapon("holy_fire")
	GameState.add_weapon("storm_cloud")
	GameState.add_weapon("anchor_hammer")
	_assert(GameState.weapon_slots.size() == GameState.MAX_WEAPON_SLOTS, "武器槽满")
	_assert(GameState.grant_teaching_demo_weapon(2) == "", "槽满时不授予演示武器")
	GameState.start_new_run("watcher", 20260824)  # 还原


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
	# 普通局重开须重抽种子；合法种子 ∈ [0, 2^32)，可用日志 seed 回放
	GameState.start_new_run("watcher")
	var seed_a: int = GameState.run_seed
	GameState.start_new_run("watcher")
	var seed_b: int = GameState.run_seed
	_assert(seed_a != seed_b, "连续无参 start_new_run 种子不同 (%d vs %d)" % [seed_a, seed_b])
	_assert(seed_a >= 0 and seed_a <= RNG.SEED_MASK_32, "seed_a 为 32 位非负")
	_assert(seed_b >= 0 and seed_b <= RNG.SEED_MASK_32, "seed_b 为 32 位非负")
	_assert(seed_a != RNG.SEED_UNSET and seed_b != RNG.SEED_UNSET, "局种子 ≠ SEED_UNSET")
	GameState.start_new_run("watcher", seed_a)
	_assert(GameState.run_seed == seed_a, "显式种子可回放")
	_assert(RNG.get_seed() == seed_a, "显式种子写入 RNG")
	# 高位/负输入经 normalize 后仍可回放（不再被 <0 误判为重抽）
	var raw_neg: int = -3390847677302330907
	var norm: int = RNG.normalize_seed(raw_neg)
	_assert(norm >= 0 and norm <= RNG.SEED_MASK_32, "负输入 normalize 后非负")
	GameState.start_new_run("watcher", raw_neg)
	_assert(GameState.run_seed == norm, "负输入开局写入规范种子")
	_assert(RNG.get_seed() == norm, "负输入写入 RNG 规范种子")


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
