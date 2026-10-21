# ============================================================================
# AudioManager — 音频管理（autoload 单例）
# 职责：BGM 播放/淡入淡出 + SFX 声音池（并发上限 / 冷却 / 音高抖动）
# 数据源：config/audio.json（总线音量、sfx/bgm 表、相位 BGM 映射）
# 总线：godot_project/default_bus_layout.tres（Master / Music / SFX / UI）
# 资源加载：优先 ResourceLoader（导出包内只有 .godot/imported/*.sample，原始 .wav 不随包）；
#           干净检出 / 无导入缓存时回退 AudioStreamWAV.load_from_file()（绕过 .import 直接解码）
# 红线：数值只读 config（SKILL.md §4.2）；headless 默认静默（skip_headless，保持机检确定性）
# 注意：音高抖动使用本地 RNG 实例，绝不消耗游戏 RNG（避免破坏局内确定性）
# ============================================================================
extends Node

const _MASTER_BUS: String = "Master"
const _DEFAULT_DIR: String = "res://assets/audio/"
const _SILENT_DB: float = -60.0

var _cfg: Dictionary = {}
var _enabled: bool = false
var _forced_enabled: bool = false
var _activated: bool = false
var _audio_dir: String = _DEFAULT_DIR

## id -> {file, bus, volume_db, cooldown_sec, max_concurrent, pitch_jitter}
var _sfx_defs: Dictionary = {}
## id -> AudioStreamWAV
var _sfx_streams: Dictionary = {}
## id -> {file, bus, volume_db, loop}
var _bgm_defs: Dictionary = {}
var _bgm_streams: Dictionary = {}

## id -> 剩余冷却（秒）
var _cooldown: Dictionary = {}
## 冷却到期暂存（每帧复用，避免 _process 内分配）
var _cooldown_expired: Array[String] = []
## id -> 已解析总线名（播放热路径不再查 config / AudioServer）
var _sfx_bus: Dictionary = {}
var _bgm_bus: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _bgm_player: AudioStreamPlayer = null
var _bgm_id: String = ""
var _bgm_target_db: float = _SILENT_DB
var _bgm_fade_db_per_sec: float = 0.0
var _world_bound: bool = false
var _world: World = null
var _signals_connected: bool = false

## 机检可断言统计（不依赖真实混音，headless dummy 驱动下同样有效）
var play_count: int = 0
var bgm_change_count: int = 0
var last_sfx_id: String = ""
var last_bgm_id: String = ""
var dropped_count: int = 0

## 独立 RNG（禁止使用游戏 RNG，否则破坏局内确定性）
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 0x7EA51DE
	_reload_config()
	if not _passes_gate():
		print("[AudioManager] 已静默（headless / enabled=false；音频机检用 set_enabled_for_test 强制开启）")
		return
	_activate()


func _process(delta: float) -> void:
	if not _enabled:
		return
	# SFX 冷却衰减（复用成员数组，避免每帧 keys() 新建 Array）
	if not _cooldown.is_empty():
		_cooldown_expired.clear()
		for k in _cooldown:
			var left: float = float(_cooldown[k]) - delta
			if left <= 0.0:
				_cooldown_expired.append(k)
			else:
				_cooldown[k] = left
		for k in _cooldown_expired:
			_cooldown.erase(k)
	_tick_bgm_fade(delta)


# ============================================================================
# 公共接口
# ============================================================================

## 播放音效（id 见 config/audio.json sfx 表）
func play_sfx(sfx_id: String, pitch_scale: float = 1.0) -> void:
	if not _enabled or sfx_id == "":
		return
	var def: Dictionary = _sfx_defs.get(sfx_id, {})
	if def.is_empty():
		return
	if float(_cooldown.get(sfx_id, 0.0)) > 0.0:
		dropped_count += 1
		return
	var stream: AudioStreamWAV = _sfx_streams.get(sfx_id, null) as AudioStreamWAV
	if stream == null:
		return
	if _count_playing(sfx_id) >= int(def.get("max_concurrent", 3)):
		dropped_count += 1
		return
	var voice: AudioStreamPlayer = _pick_voice(sfx_id)
	if voice == null:
		dropped_count += 1
		return
	_cooldown[sfx_id] = maxf(0.0, float(def.get("cooldown_sec", 0.0)))
	voice.stream = stream
	voice.bus = String(_sfx_bus.get(sfx_id, _MASTER_BUS))
	voice.volume_db = float(def.get("volume_db", 0.0))
	var jitter: float = float(def.get("pitch_jitter", 0.0))
	var pitch: float = pitch_scale
	if jitter > 0.0:
		pitch += _rng.randf_range(-jitter, jitter)
	voice.pitch_scale = clampf(pitch, 0.1, 4.0)
	voice.set_meta("sfx_id", sfx_id)
	voice.play()
	play_count += 1
	last_sfx_id = sfx_id


## 切换 BGM（同 id 正在播放则忽略；fade_sec<0 用 config 默认）
func play_bgm(bgm_id: String, fade_sec: float = -1.0) -> void:
	if not _enabled or bgm_id == "" or _bgm_player == null:
		return
	if bgm_id == _bgm_id and _bgm_player.playing and _bgm_target_db > _SILENT_DB + 1.0:
		return
	var def: Dictionary = _bgm_defs.get(bgm_id, {})
	if def.is_empty():
		return
	var stream: AudioStreamWAV = _bgm_streams.get(bgm_id, null) as AudioStreamWAV
	if stream == null:
		return
	_bgm_id = bgm_id
	_bgm_player.stream = stream
	_bgm_player.bus = String(_bgm_bus.get(bgm_id, _MASTER_BUS))
	_bgm_player.volume_db = _SILENT_DB
	_bgm_player.play()
	var target: float = float(def.get("volume_db", -10.0))
	var dur: float = fade_sec if fade_sec >= 0.0 else float(_cfg.get("bgm_fade_sec", 1.2))
	_bgm_target_db = target
	_bgm_fade_db_per_sec = maxf(1.0, absf(target - _SILENT_DB) / maxf(0.05, dur))
	bgm_change_count += 1
	last_bgm_id = bgm_id


## 淡出并停止 BGM
func stop_bgm(fade_sec: float = -1.0) -> void:
	if _bgm_player == null:
		return
	_bgm_id = ""
	_bgm_target_db = _SILENT_DB
	var dur: float = fade_sec if fade_sec >= 0.0 else float(_cfg.get("bgm_fade_sec", 1.2))
	_bgm_fade_db_per_sec = maxf(1.0, absf(_bgm_player.volume_db - _SILENT_DB) / maxf(0.05, dur))


## 按当前游戏相位选 BGM（白天 / 夜晚 / Boss 夜 / 菜单）
func phase_bgm_id() -> String:
	var map: Dictionary = _cfg.get("bgm_by_phase", {})
	if GameState.is_over:
		return String(map.get("menu", "menu"))
	if GameState.is_day_phase:
		return String(map.get("day", "day"))
	var night: int = GameState.current_night
	if bool(_cfg.get("boss_bgm_on_boss_nights", true)) and not ConfigLoader.get_boss_by_night(night).is_empty():
		return String(map.get("boss", "boss"))
	return String(map.get("night", "night"))


## 按当前相位切 BGM（供 world / 结算调用）
func sync_bgm_to_phase() -> void:
	play_bgm(phase_bgm_id())


func is_enabled() -> bool:
	return _enabled


func get_current_bgm() -> String:
	return _bgm_id


func get_sfx_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _sfx_defs.keys():
		out.append(String(k))
	return out


func get_bgm_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _bgm_defs.keys():
		out.append(String(k))
	return out


## 设置总线音量（dB）；返回是否成功
func set_bus_volume_db(bus_name: String, volume_db: float) -> bool:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return false
	AudioServer.set_bus_volume_db(idx, volume_db)
	return true


func get_bus_volume_db(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)


## 机检专用：强制开启/关闭（headless 下 skip_headless 会默认静默）
func set_enabled_for_test(on: bool) -> void:
	_forced_enabled = on
	if on:
		_enabled = true
		_activate()
	else:
		_enabled = false
		if _bgm_player != null:
			_bgm_player.stop()


## 机检专用：把 SFX 冷却全部清零，便于连续断言
func clear_cooldowns_for_test() -> void:
	_cooldown.clear()


# ============================================================================
# 初始化
# ============================================================================

func _reload_config() -> void:
	_cfg = ConfigLoader.get_audio_config()
	if _cfg.is_empty():
		_cfg = {}
	_sfx_defs = _normalize_table(_cfg.get("sfx", {}))
	_bgm_defs = _normalize_table(_cfg.get("bgm", {}))
	var dir: String = String(_cfg.get("audio_dir", _DEFAULT_DIR))
	if dir != "" and not dir.ends_with("/"):
		dir += "/"
	_audio_dir = dir if dir != "" else _DEFAULT_DIR


## 表项只接受 Dictionary（防配置写错导致崩溃）
func _normalize_table(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for k in (raw as Dictionary).keys():
		var v: Variant = (raw as Dictionary)[k]
		if v is Dictionary:
			out[String(k)] = v
	return out


## headless / 总开关门控（保持 29 个机检场景零音频开销）
func _passes_gate() -> bool:
	if _forced_enabled:
		return true
	# 配置缺失（audio.json 未加载）时整体静默，不建声道、不接管 UI
	if _cfg.is_empty():
		return false
	if not bool(_cfg.get("enabled", true)):
		return false
	if bool(_cfg.get("skip_headless", true)) and DisplayServer.get_name() == "headless":
		return false
	return true


## 建总线音量 → 建声音池 → 载流 → 接信号（幂等）
func _activate() -> void:
	_enabled = true
	_apply_bus_volumes()
	_build_players()
	_load_streams()
	if not _signals_connected:
		_connect_signals()
		_signals_connected = true
	if not _activated:
		_activated = true
		print("[AudioManager] 就绪 | sfx=%d bgm=%d voices=%d" % [
			_sfx_streams.size(), _bgm_streams.size(), _voices.size()
		])
	# 主场景在 autoload 之后才就绪，延后一次做首帧 BGM 同步
	call_deferred("_on_scene_changed")


func _apply_bus_volumes() -> void:
	var buses: Variant = _cfg.get("buses", {})
	if not (buses is Dictionary):
		return
	for key in (buses as Dictionary).keys():
		var item: Variant = (buses as Dictionary)[key]
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary
		var bus_name: String = String(d.get("name", ""))
		if bus_name == "" or AudioServer.get_bus_index(bus_name) < 0:
			push_warning("[AudioManager] 总线缺失: %s（检查 default_bus_layout.tres）" % bus_name)
			continue
		set_bus_volume_db(bus_name, float(d.get("volume_db", 0.0)))


func _build_players() -> void:
	if not _voices.is_empty():
		return
	var count: int = maxi(1, int(_cfg.get("sfx_voice_count", 16)))
	for i in count:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "SFXVoice%d" % i
		p.bus = _resolve_bus("sfx", "sfx")
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_voices.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = _resolve_bus("music", "music")
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_player.volume_db = _SILENT_DB
	add_child(_bgm_player)


func _load_streams() -> void:
	_sfx_bus.clear()
	for id in _sfx_defs.keys():
		var def: Dictionary = _sfx_defs[id]
		_sfx_bus[String(id)] = _resolve_bus(String(def.get("bus", "sfx")), "sfx")
		var s: AudioStreamWAV = _load_wav(String(def.get("file", "")), false)
		if s != null:
			_sfx_streams[String(id)] = s
	_bgm_bus.clear()
	for id in _bgm_defs.keys():
		var def2: Dictionary = _bgm_defs[id]
		_bgm_bus[String(id)] = _resolve_bus(String(def2.get("bus", "music")), "music")
		var s2: AudioStreamWAV = _load_wav(String(def2.get("file", "")), bool(def2.get("loop", true)))
		if s2 != null:
			_bgm_streams[String(id)] = s2


## 加载 WAV：优先走导入资源（导出包内只有 .godot/imported/*.sample，原始 .wav 不随包），
## 干净检出 / 无导入缓存时回退直接解码源文件（AudioStreamWAV.load_from_file 绕过 .import）
func _load_wav(filename: String, loop: bool) -> AudioStreamWAV:
	if filename == "":
		return null
	var path: String = filename if filename.begins_with("res://") or filename.begins_with("user://") else _audio_dir + filename
	var s: AudioStreamWAV = null
	if ResourceLoader.exists(path):
		s = ResourceLoader.load(path) as AudioStreamWAV
	if s == null:
		if not FileAccess.file_exists(path):
			push_warning("[AudioManager] 音频文件缺失: %s" % path)
			return null
		s = AudioStreamWAV.load_from_file(path)
	if s == null:
		push_warning("[AudioManager] WAV 解码失败: %s" % path)
		return null
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(round(s.get_length() * float(s.mix_rate)))
	return s


## 总线解析：允许写逻辑键（music/sfx/ui，取自 config.buses）或直接写总线名；
## 未知总线回退 Master 并告警（避免静音且便于定位配置错误）
func _resolve_bus(raw: String, fallback_key: String) -> String:
	# 配置写坏（如 buses 写成数组）时退化为空表，不能因类型不符在热路径抛错
	var buses_raw: Variant = _cfg.get("buses", {})
	var buses: Dictionary = buses_raw if buses_raw is Dictionary else {}
	var bus_name: String = raw
	var logical: Variant = buses.get(raw, null)
	if logical is Dictionary:
		bus_name = String((logical as Dictionary).get("name", raw))
	if bus_name == "":
		var fb: Variant = buses.get(fallback_key, null)
		if fb is Dictionary:
			bus_name = String((fb as Dictionary).get("name", ""))
	if bus_name == "" or AudioServer.get_bus_index(bus_name) < 0:
		push_warning("[AudioManager] 未知总线 '%s'（回退 Master）" % raw)
		return _MASTER_BUS
	return bus_name


# ============================================================================
# 声音池
# ============================================================================

func _count_playing(sfx_id: String) -> int:
	var n: int = 0
	for v in _voices:
		if v.playing and String(v.get_meta("sfx_id", "")) == sfx_id:
			n += 1
	return n


## 优先空闲声道；全忙时只允许同 id 自我抢断（复用本音效在播音色，按声道顺序取第一个），
## 不打断其它音效；无同 id 在播则返回 null（play_sfx 按丢弃计 dropped_count）
func _pick_voice(sfx_id: String) -> AudioStreamPlayer:
	for v in _voices:
		if not v.playing:
			return v
	for v2 in _voices:
		if String(v2.get_meta("sfx_id", "")) == sfx_id:
			return v2
	return null


func _tick_bgm_fade(delta: float) -> void:
	if _bgm_player == null:
		return
	if is_equal_approx(_bgm_player.volume_db, _bgm_target_db):
		return
	_bgm_player.volume_db = move_toward(
		_bgm_player.volume_db, _bgm_target_db, _bgm_fade_db_per_sec * delta
	)
	if _bgm_target_db <= _SILENT_DB + 0.5 and _bgm_player.volume_db <= _SILENT_DB + 0.5:
		_bgm_player.stop()


# ============================================================================
# 信号接线
# ============================================================================

func _connect_signals() -> void:
	GameState.run_started.connect(_on_run_started)
	GameState.night_started.connect(_on_night_started)
	GameState.day_started.connect(_on_day_started)
	GameState.game_over.connect(_on_game_over)
	GameState.game_win.connect(_on_game_win)
	GameState.level_up.connect(_on_level_up)
	GameState.player_damaged.connect(_on_player_damaged)
	GameState.player_down.connect(_on_player_down)
	if get_tree() != null:
		get_tree().scene_changed.connect(_on_scene_changed)
		# UI 点击音：全局接管（含商店/三选一/灯塔树等运行时动态生成的按钮）
		get_tree().node_added.connect(_on_node_added)
		_wire_ui_buttons(get_tree().root)


func _on_scene_changed() -> void:
	if not is_instance_valid(_world):
		_world = null
		_world_bound = false
	_try_bind_world()
	# 回到选角 / 其他场景 → 菜单 BGM；进 World 由相位决定
	var world: World = _current_world()
	if world == null:
		play_bgm(String(_cfg.get("default_bgm", "menu")))
	else:
		sync_bgm_to_phase()


## 由 World._ready() 显式调用：不依赖 scene_changed + current_scene 的时序，
## 也让「把 World 挂成测试场景子节点」的机检能覆盖到 pickup/shop 接线
func bind_world(world: World) -> void:
	if not _enabled or world == null:
		return
	_world = world
	_world_bound = false
	_try_bind_world()


func _try_bind_world() -> void:
	var world: World = _world if is_instance_valid(_world) else _current_world()
	if world == null:
		return
	if _world != world:
		_world = world
		_world_bound = false
	if _world_bound:
		return
	if world.pickup_system != null:
		if not world.pickup_system.exp_collected.is_connected(_on_exp_collected):
			world.pickup_system.exp_collected.connect(_on_exp_collected)
		if not world.pickup_system.chest_opened.is_connected(_on_chest_opened):
			world.pickup_system.chest_opened.connect(_on_chest_opened)
	if world.shop_manager != null:
		if not world.shop_manager.purchase_made.is_connected(_on_purchase_made):
			world.shop_manager.purchase_made.connect(_on_purchase_made)
	_world_bound = true


func _on_run_started(_character: String, _seed_value: int) -> void:
	sync_bgm_to_phase()


func _on_night_started(_night: int) -> void:
	sync_bgm_to_phase()


func _on_day_started() -> void:
	sync_bgm_to_phase()


func _on_level_up(_new_level: int) -> void:
	play_sfx("level_up")


func _on_player_damaged(amount: int) -> void:
	if amount > 0:
		play_sfx("hurt")


func _on_player_down(_kind: String) -> void:
	play_sfx("hurt")


func _on_game_over(_reason: String) -> void:
	play_sfx("game_over")
	stop_bgm()


func _on_game_win() -> void:
	play_sfx("victory")
	stop_bgm()


func _on_exp_collected(_amount: int) -> void:
	play_sfx("pickup")


func _on_chest_opened(_kind: String, _amount: int, _rarity_name: String) -> void:
	play_sfx("chest")


func _on_purchase_made(_item: Dictionary) -> void:
	play_sfx("coin")


# ============================================================================
# UI 点击音（全局接管，无需在每个按钮处写一行）
# ============================================================================

## 运行时新增节点：若是按钮则挂点击音（覆盖动态生成的商店/三选一卡片）
func _on_node_added(node: Node) -> void:
	if not _enabled:
		return
	if node is BaseButton:
		_connect_button(node as BaseButton)


## 递归扫描已存在的按钮（进场景 / 测试强制开启时补齐）
func _wire_ui_buttons(root: Node) -> void:
	if root == null:
		return
	if root is BaseButton:
		_connect_button(root as BaseButton)
	for child in root.get_children():
		_wire_ui_buttons(child)


func _connect_button(btn: BaseButton) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(_on_any_ui_pressed):
		btn.pressed.connect(_on_any_ui_pressed)


func _on_any_ui_pressed() -> void:
	play_sfx("ui_click")


func _current_world() -> World:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene as World
