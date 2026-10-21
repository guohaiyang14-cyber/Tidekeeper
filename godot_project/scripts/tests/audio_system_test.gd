# ============================================================================
# AudioSystemTest — 音频系统机检（post-W20 新增）
# 验收：config/audio.json 数据驱动完整；总线布局 Music/SFX/UI 存在且音量对齐；
#       16 个占位音频可解码（AudioStreamWAV.load_from_file 绕过 .import）；
#       SFX 冷却 / 并发 / 未知 id 安全；BGM 切换去重 + 无缝循环参数；
#       相位→BGM 映射（day / night / boss / menu）；GameState 信号接线；
#       UI 点击音全局接管；headless 默认静默（skip_headless 门控）。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/audio_system_test.tscn
# ============================================================================
extends Node2D

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CLEANUP := preload("res://scripts/tests/test_cleanup.gd")

const SFX_IDS: Array[String] = [
	"shoot", "hit", "enemy_die", "pickup", "coin", "level_up",
	"hurt", "chest", "ui_click", "boss_roar", "game_over", "victory",
]
const BGM_IDS: Array[String] = ["menu", "day", "night", "boss"]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("音频系统 机检")
	print("============================================================")

	print("[assert] headless 默认静默")
	_assert(not AudioManager.is_enabled(), "headless 下默认不启用（skip_headless）")

	print("[assert] 配置表完整性")
	var cfg: Dictionary = ConfigLoader.get_audio_config()
	_assert(not cfg.is_empty(), "config/audio.json 已加载")
	_assert(cfg.get("sfx", {}).size() == SFX_IDS.size(), "sfx 表 %d 项" % SFX_IDS.size())
	_assert(cfg.get("bgm", {}).size() == BGM_IDS.size(), "bgm 表 %d 项" % BGM_IDS.size())
	_assert(cfg.get("buses", {}).size() == 3, "总线配置 3 条（music/sfx/ui）")
	_assert(int(cfg.get("sfx_voice_count", 0)) > 0, "声音池声道数 > 0")

	print("[assert] 音频文件齐全（数据驱动 → 文件存在）")
	var audio_dir: String = String(cfg.get("audio_dir", "res://assets/audio/"))
	for id in SFX_IDS:
		var f: String = String(cfg.get("sfx", {}).get(id, {}).get("file", ""))
		_assert(f != "" and FileAccess.file_exists(audio_dir + f), "sfx %s → %s" % [id, f])
	for id in BGM_IDS:
		var f2: String = String(cfg.get("bgm", {}).get(id, {}).get("file", ""))
		_assert(f2 != "" and FileAccess.file_exists(audio_dir + f2), "bgm %s → %s" % [id, f2])

	print("[assert] 总线布局")
	for bus_name in ["Master", "Music", "SFX", "UI"]:
		_assert(AudioServer.get_bus_index(bus_name) >= 0, "总线存在: %s" % bus_name)
	_assert(is_equal_approx(
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
		float(cfg.get("buses", {}).get("music", {}).get("volume_db", 0.0))
	), "Music 总线音量 = config")

	print("[assert] 强制开启（机检专用门控）")
	AudioManager.set_enabled_for_test(true)
	_assert(AudioManager.is_enabled(), "set_enabled_for_test(true) 生效")
	_assert(AudioManager.get_sfx_ids().size() == SFX_IDS.size(), "12 个 SFX 流全部加载")
	_assert(AudioManager.get_bgm_ids().size() == BGM_IDS.size(), "4 个 BGM 流全部加载")

	print("[assert] 总线解析（逻辑键 / 直写名 / 未知回退）")
	_assert(AudioManager._resolve_bus("sfx", "sfx") == "SFX", "逻辑键 sfx → SFX")
	_assert(AudioManager._resolve_bus("Music", "music") == "Music", "直写总线名兼容")
	_assert(AudioManager._resolve_bus("", "ui") == "UI", "空值回退 fallback 键 ui")
	_assert(AudioManager._resolve_bus("no_such_bus", "sfx") == "Master", "未知总线回退 Master")

	print("[assert] 加载路径（导入资源优先 / 源文件兜底）")
	var probe: AudioStreamWAV = AudioManager._sfx_streams.get("shoot", null) as AudioStreamWAV
	var probe_path: String = probe.resource_path if probe != null else "<null>"
	print("  [info] shoot resource_path=%s（非空=走 ResourceLoader，导出包内可用）" % probe_path)
	_assert(probe != null and (probe_path != "" or probe.data.size() > 0), "sfx 流可用（导入资源或源文件解码）")

	print("[assert] BGM 无缝循环参数")
	for id in BGM_IDS:
		var s: AudioStreamWAV = AudioManager._bgm_streams.get(id, null) as AudioStreamWAV
		_assert(s != null, "bgm 流存在: %s" % id)
		if s == null:
			continue
		_assert(s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "bgm %s loop_mode=FORWARD" % id)
		_assert(s.loop_end == int(round(s.get_length() * float(s.mix_rate))), "bgm %s loop_end=整段" % id)
		# 采样率/位深不硬编码（占位素材为 22050Hz 单声道，正式素材可任意），只验证可解码
		_assert(s.mix_rate > 0 and s.data.size() > 0, "bgm %s 流可解码" % id)

	print("[assert] SFX 播放 / 冷却 / 未知 id")
	AudioManager.clear_cooldowns_for_test()
	var n0: int = AudioManager.play_count
	AudioManager.play_sfx("shoot")
	_assert(AudioManager.play_count == n0 + 1, "play_sfx(shoot) 计数 +1")
	_assert(AudioManager.last_sfx_id == "shoot", "last_sfx_id=shoot")
	var n1: int = AudioManager.play_count
	AudioManager.play_sfx("shoot")
	_assert(AudioManager.play_count == n1, "冷却期内重复播放被节流")
	AudioManager.clear_cooldowns_for_test()
	AudioManager.play_sfx("shoot")
	_assert(AudioManager.play_count == n1 + 1, "冷却清零后可再播")
	var n2: int = AudioManager.play_count
	AudioManager.play_sfx("no_such_sfx")
	AudioManager.play_sfx("")
	_assert(AudioManager.play_count == n2, "未知/空 id 不播放且不崩")

	print("[assert] SFX 并发上限（max_concurrent=1 的 level_up）")
	AudioManager.clear_cooldowns_for_test()
	var n3: int = AudioManager.play_count
	AudioManager.play_sfx("level_up")
	AudioManager.play_sfx("level_up")
	AudioManager.play_sfx("level_up")
	var played: int = AudioManager.play_count - n3
	print("  [info] level_up 连续 3 次实际播放 %d 次（max_concurrent=%d）" % [
		played, int(cfg.get("sfx", {}).get("level_up", {}).get("max_concurrent", 1))
	])
	_assert(played <= 1, "并发上限生效（≤1）")

	print("[assert] BGM 切换去重")
	AudioManager.play_bgm("night")
	_assert(AudioManager.last_bgm_id == "night", "play_bgm(night)")
	var c1: int = AudioManager.bgm_change_count
	AudioManager.play_bgm("night")
	_assert(AudioManager.bgm_change_count == c1, "同 id 重复切歌被忽略")
	AudioManager.play_bgm("boss")
	_assert(AudioManager.bgm_change_count == c1 + 1, "切到 boss 生效")
	AudioManager.play_bgm("no_such_bgm")
	_assert(AudioManager.bgm_change_count == c1 + 1, "未知 bgm id 不生效")

	print("[assert] 相位 → BGM 映射")
	GameState.start_new_run("watcher", 20260824)
	GameState.enter_night(1)
	_assert(AudioManager.phase_bgm_id() == "night", "开局（夜 1）→ night")
	GameState.enter_night(10)
	_assert(AudioManager.phase_bgm_id() == "boss", "第 10 夜（Boss 夜）→ boss")
	GameState.end_night()
	_assert(AudioManager.phase_bgm_id() == "day", "白天 → day")

	print("[assert] GameState 信号接线")
	AudioManager.clear_cooldowns_for_test()
	GameState.level_up.emit(2)
	_assert(AudioManager.last_sfx_id == "level_up", "level_up → level_up 音效")
	AudioManager.clear_cooldowns_for_test()
	GameState.player_damaged.emit(7)
	_assert(AudioManager.last_sfx_id == "hurt", "player_damaged → hurt 音效")
	AudioManager.clear_cooldowns_for_test()
	GameState.game_over.emit("test")
	_assert(AudioManager.last_sfx_id == "game_over", "game_over → game_over 音效")
	_assert(GameState.level_up.is_connected(Callable(AudioManager, "_on_level_up")), "level_up 已接线")
	_assert(GameState.night_started.is_connected(Callable(AudioManager, "_on_night_started")), "night_started 已接线")
	_assert(GameState.day_started.is_connected(Callable(AudioManager, "_on_day_started")), "day_started 已接线")
	_assert(GameState.game_win.is_connected(Callable(AudioManager, "_on_game_win")), "game_win 已接线")

	print("[assert] UI 点击音全局接管")
	AudioManager.clear_cooldowns_for_test()
	var btn: Button = Button.new()
	btn.text = "probe"
	add_child(btn)
	await get_tree().process_frame
	_assert(btn.pressed.is_connected(Callable(AudioManager, "_on_any_ui_pressed")), "运行时按钮自动接线")
	btn.pressed.emit()
	_assert(AudioManager.last_sfx_id == "ui_click", "按钮 pressed → ui_click 音效")
	btn.queue_free()

	print("[assert] TestBot ACCEPT 4.11.1 探针（pass / skip / fail / 增量口径 四支）")
	TestBot._suite_name = "acceptance"
	AudioManager.set_enabled_for_test(true)
	_reset_accept_state("4.11.1")
	TestBot._accept_audio_probe()
	_assert(TestBot._accept_pass.has("4.11.1"), "启用且 play_count>0 → pass")
	AudioManager.set_enabled_for_test(false)
	_reset_accept_state("4.11.1")
	TestBot._accept_audio_probe()
	_assert(not TestBot._accept_pass.has("4.11.1") and not TestBot._accept_fail.has("4.11.1"),
		"音频关闭（headless）→ skip，不假绿")
	AudioManager.set_enabled_for_test(true)
	var saved_play_count: int = AudioManager.play_count
	AudioManager.play_count = 0
	_reset_accept_state("4.11.1")
	TestBot._accept_audio_probe()
	_assert(TestBot._accept_fail.has("4.11.1"), "启用却零播放 → fail")
	AudioManager.play_count = saved_play_count
	# 增量口径：开局基线 = 当前累计，本局零新增 → fail（覆盖多局连跑首局后失真场景）
	TestBot._run_audio_play_baseline = AudioManager.play_count
	_reset_accept_state("4.11.1")
	TestBot._accept_audio_probe()
	_assert(TestBot._accept_fail.has("4.11.1"), "基线>0 且本局零新增 → fail（增量口径）")
	TestBot._run_audio_play_baseline = -1
	TestBot._suite_name = ""
	AudioManager.clear_cooldowns_for_test()

	print("[assert] World 绑定（拾取 / 商店信号）")
	# 必须在音频已开启后实例化，World._ready() 才会 bind_world
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: World = main as World
	_assert(world != null, "main.tscn 实例化为 World")
	if world != null:
		_assert(world.pickup_system.exp_collected.is_connected(Callable(AudioManager, "_on_exp_collected")),
			"exp_collected 已接线")
		_assert(world.pickup_system.chest_opened.is_connected(Callable(AudioManager, "_on_chest_opened")),
			"chest_opened 已接线")
		_assert(world.shop_manager.purchase_made.is_connected(Callable(AudioManager, "_on_purchase_made")),
			"purchase_made 已接线")
		AudioManager.clear_cooldowns_for_test()
		world.pickup_system.exp_collected.emit(5)
		_assert(AudioManager.last_sfx_id == "pickup", "exp_collected → pickup 音效")
		AudioManager.clear_cooldowns_for_test()
		world.pickup_system.chest_opened.emit("tidecoins", 10, "普通")
		_assert(AudioManager.last_sfx_id == "chest", "chest_opened → chest 音效")
		AudioManager.clear_cooldowns_for_test()
		world.shop_manager.purchase_made.emit({})
		_assert(AudioManager.last_sfx_id == "coin", "purchase_made → coin 音效")
	CLEANUP.free_node(main)
	await get_tree().process_frame

	print("[assert] 关闭后静默")
	AudioManager.set_enabled_for_test(false)
	_assert(not AudioManager.is_enabled(), "set_enabled_for_test(false) 生效")
	var n4: int = AudioManager.play_count
	AudioManager.play_sfx("shoot")
	AudioManager.clear_cooldowns_for_test()
	AudioManager.play_sfx("shoot")
	_assert(AudioManager.play_count == n4, "关闭后不再播放")

	print("------------------------------------------------------------")
	print("音频系统机检 通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


## 清空某 ACCEPT id 的累计态（探针三支验证用）
func _reset_accept_state(id: String) -> void:
	TestBot._accept_pass.erase(id)
	TestBot._accept_fail.erase(id)
	TestBot._accept_last_emit.erase(id)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
