# ============================================================================
# R1PerfBench — 阶段 A / R1：350 敌帧时 + 内存粗测（A1 / A4）
# 不替代人工 Profiler，但给出可复现的墙钟帧时与静态内存趋势。
#
# 负载边界（代理，非全战斗）：单种 small_goblin + AI/哈希；无武器弹道/粒子/HUD/World。
# A4 为同进程「刷满→测→清空」×3 的 MEMORY_STATIC 涨幅，非「连续 3 局打到第 8 夜」。
#
# 运行（勿加 --fixed-fps，否则墙钟被锁死无法估 fps）：
#   godot --path godot_project res://scenes/tests/r1_perf_bench.tscn
#   godot --headless --path godot_project res://scenes/tests/r1_perf_bench.tscn
#   python tools/run_perf_bench.py
#
# 机读行：
#   [PERF] key=value ...
# TestBot ACCEPT：N/A（Profiler 代理工具）
# ============================================================================
extends Node2D

const WARMUP_FRAMES: int = 30
const MEASURE_FRAMES: int = 180
const MEMORY_CYCLES: int = 3
## 目标帧预算（ms）；≤ 此值视为可撑 60fps
const BUDGET_MS: float = 16.67
## 内存粗测：末周期相对首周期允许的静态内存涨幅（字节）
const MEMORY_GROWTH_BUDGET: int = 32 * 1024 * 1024

var _passed: int = 0
var _failed: int = 0
## 仅在 _measure_loaded 窗口内写入（避免跨周期采样顶满丢帧）
var _sampling: bool = false
var _frame_samples_ms: Array[float] = []

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Player = $Player
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	print("============================================================")
	print("R1 性能压测：350 敌帧时 + 内存粗测")
	print("============================================================")
	# 解除刷新率锁，使墙钟帧时可反映真实负载（窗口模式）
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameState.start_new_run("watcher", 20260914)
	spatial_hash_holder.add_to_group("spatial_hash")
	player.add_to_group("player")
	spawner.add_to_group("enemy_spawner")
	spawner.setup(enemy_pool, player, pickup_system)
	await get_tree().process_frame

	var headless: bool = DisplayServer.get_name() == "headless"
	_emit_perf({
		"event": "meta",
		"godot": Engine.get_version_info().get("string", "?"),
		"display": DisplayServer.get_name(),
		"headless": headless,
		"max_enemies": spawner.max_enemies,
		"budget_ms": BUDGET_MS,
		"measure_frames": MEASURE_FRAMES,
		"memory_cycles": MEMORY_CYCLES,
		"load_note": "goblin_ai_hash_only_no_weapons_ui",
	})

	await _run_frames(WARMUP_FRAMES)
	var mem_baseline: int = _static_mem()
	_emit_perf({"event": "mem_baseline", "static_bytes": mem_baseline})

	var cycle_avgs: Array[float] = []
	var cycle_p95s: Array[float] = []
	var cycle_mems: Array[int] = []
	var fill_ok: bool = true

	for cycle in range(MEMORY_CYCLES):
		var filled: int = await _fill_enemies()
		if filled < spawner.max_enemies:
			fill_ok = false
			print("  [WARN] 周期%d 刷满失败 filled=%d cap=%d" % [cycle + 1, filled, spawner.max_enemies])
		var stats: Dictionary = await _measure_loaded()
		var mem_after: int = _static_mem()
		cycle_avgs.append(float(stats.get("wall_avg_ms", 0.0)))
		cycle_p95s.append(float(stats.get("p95_ms", 0.0)))
		cycle_mems.append(mem_after)
		_emit_perf({
			"event": "cycle",
			"cycle": cycle + 1,
			"filled": filled,
			"avg_ms": stats.get("avg_ms", 0.0),
			"p50_ms": stats.get("p50_ms", 0.0),
			"p95_ms": stats.get("p95_ms", 0.0),
			"max_ms": stats.get("max_ms", 0.0),
			"wall_avg_ms": stats.get("wall_avg_ms", 0.0),
			"wall_fps": stats.get("wall_fps", 0.0),
			"active": enemy_pool.active_count(),
			"static_bytes": mem_after,
		})
		_clear()
		await _run_frames(10)

	_assert(fill_ok, "三周期均可刷满 max_enemies")
	# A1 以关闭 vsync/max_fps 后的墙钟帧时为准；process p95 仅参考
	var worst_avg: float = _max_f(cycle_avgs)
	var worst_p95: float = _max_f(cycle_p95s)
	var a1_pass: bool = fill_ok and worst_avg <= BUDGET_MS
	_assert(a1_pass, "A1 代理：最差 wall_avg_ms=%.2f ≤ %.2f（process_p95=%.2f）" % [worst_avg, BUDGET_MS, worst_p95])

	var mem_first: int = cycle_mems[0] if not cycle_mems.is_empty() else mem_baseline
	var mem_last: int = cycle_mems[cycle_mems.size() - 1] if not cycle_mems.is_empty() else mem_baseline
	var mem_delta: int = mem_last - mem_first
	var a4_pass: bool = mem_delta <= MEMORY_GROWTH_BUDGET
	_assert(a4_pass, "A4 代理：周期内存涨幅=%d ≤ %d（非连续3局）" % [mem_delta, MEMORY_GROWTH_BUDGET])

	_emit_perf({
		"event": "summary",
		"a1_pass": a1_pass,
		"a4_pass": a4_pass,
		"fill_ok": fill_ok,
		"worst_avg_ms": worst_avg,
		"worst_p95_ms": worst_p95,
		"wall_fps_proxy": 1000.0 / maxf(worst_avg, 0.001),
		"mem_baseline": mem_baseline,
		"mem_first_cycle": mem_first,
		"mem_last_cycle": mem_last,
		"mem_delta": mem_delta,
		"note": "headless_skips_full_render" if headless else "includes_display_server",
	})

	print("------------------------------------------------------------")
	print("R1 压测通过=%d 失败=%d | A1=%s A4=%s | worst_wall=%.2fms wall_fps≈%.1f process_p95=%.2f" % [
		_passed, _failed,
		"PASS" if a1_pass else "FAIL",
		"PASS" if a4_pass else "FAIL",
		worst_avg,
		1000.0 / maxf(worst_avg, 0.001),
		worst_p95,
	])
	print("============================================================")
	await get_tree().process_frame
	# 崩溃=非零；帧时/内存/刷满未达预算也非零，便于 CI / 收口判断
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if not _sampling:
		return
	var proc_sec: float = float(Performance.get_monitor(Performance.TIME_PROCESS))
	if proc_sec > 0.0:
		_frame_samples_ms.append(proc_sec * 1000.0)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _run_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _clear() -> void:
	spawner.stop()
	spawner.clear_all()
	enemy_pool.release_all()


func _fill_enemies() -> int:
	_clear()
	await get_tree().process_frame
	var cap: int = spawner.max_enemies
	var def: Dictionary = ConfigLoader.get_enemy("small_goblin")
	var spawned: int = 0
	while spawned < cap and enemy_pool.available_count() > 0:
		var e: EnemyBase = enemy_pool.acquire() as EnemyBase
		if e == null:
			break
		e.configure(def, 10)
		# 保留 AI 移动，贴近同屏压力（勿置 0）
		e.spawn_at(
			Vector2(float(spawned % 25) * 48.0 - 600.0, float(spawned / 25) * 48.0 - 400.0),
			player
		)
		spawned += 1
	await get_tree().process_frame
	return spawned


func _measure_loaded() -> Dictionary:
	_frame_samples_ms.clear()
	_sampling = true
	var t0: int = Time.get_ticks_usec()
	await _run_frames(MEASURE_FRAMES)
	_sampling = false
	var wall_us: int = Time.get_ticks_usec() - t0
	var wall_ms: float = float(wall_us) / 1000.0
	var avg_wall: float = wall_ms / float(MEASURE_FRAMES)
	var wall_fps: float = 1000.0 / maxf(avg_wall, 0.001)

	var slice: Array[float] = _frame_samples_ms.duplicate()
	# 若 TIME_PROCESS 采样不足，退回墙钟（仅作 p50/p95 参考）
	if slice.size() < maxi(MEASURE_FRAMES / 2, 1):
		slice.clear()
		for _j in MEASURE_FRAMES:
			slice.append(avg_wall)

	slice.sort()
	var p50: float = _percentile(slice, 0.50)
	var p95: float = _percentile(slice, 0.95)
	var mx: float = slice[slice.size() - 1]
	var sum: float = 0.0
	for v in slice:
		sum += v
	var avg_proc: float = sum / float(slice.size())
	# A1 主指标为墙钟 wall_avg_ms；TIME_PROCESS 分位仅参考
	return {
		"avg_ms": avg_proc,
		"p50_ms": p50,
		"p95_ms": p95,
		"max_ms": mx,
		"wall_avg_ms": avg_wall,
		"wall_fps": wall_fps,
	}


func _static_mem() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))


func _percentile(sorted_vals: Array[float], p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = int(floor(float(sorted_vals.size() - 1) * p))
	idx = clampi(idx, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _max_f(vals: Array[float]) -> float:
	var m: float = 0.0
	for v in vals:
		if v > m:
			m = v
	return m


func _emit_perf(fields: Dictionary) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for k in fields.keys():
		var v: Variant = fields[k]
		var s: String
		match typeof(v):
			TYPE_BOOL:
				s = "true" if bool(v) else "false"
			TYPE_FLOAT:
				s = "%.4f" % float(v)
			TYPE_INT:
				s = str(int(v))
			_:
				s = str(v).replace(" ", "_")
		parts.append("%s=%s" % [str(k), s])
	print("[PERF] %s" % " ".join(parts))
