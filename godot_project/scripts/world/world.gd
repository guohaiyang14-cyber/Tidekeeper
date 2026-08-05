# ============================================================================
# World — 游戏世界根节点（W1 骨架）
# 职责：持有场景树结构（Player/Spawner/Pool/SpatialHash/UI），驱动昼夜状态机
# 架构：README §1.2 Main → World（含全部运行时子节点）
# W1 范围：仅搭建结构 + 验证配置加载 + 启动昼夜空循环
# ============================================================================
extends Node2D
class_name World

# 子节点引用
@onready var player: Node2D = $Player
@onready var day_night: DayNightStateMachine = $DayNightStateMachine
@onready var hud: Control = $UI/HUD
@onready var debug_label: Label = $UI/HUD/DebugLabel


func _ready() -> void:
	print("[World] 初始化中...")
	# 验证配置加载
	_verify_config()
	# 启动昼夜状态机
	day_night.start_run()
	# 连接信号
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.night_tick.connect(_on_night_tick)
	GameState.game_over.connect(_on_game_over)
	GameState.game_win.connect(_on_game_win)
	print("[World] 就绪 — 第 %d 夜开始" % day_night.get_current_night())


func _process(_delta: float) -> void:
	# 调试信息（W1 临时，W2+ 移到 HUD）
	if debug_label:
		debug_label.text = "夜: %d / 20  |  阶段: %s  |  剩余: %.1fs  |  等级: %d  |  HP: %d/%d" % [
			day_night.get_current_night(),
			_phase_label(day_night.get_phase()),
			day_night.get_night_remaining(),
			GameState.player_level,
			GameState.player_health,
			GameState.player_max_health,
		]


## 验证配置加载（启动自检）
func _verify_config() -> void:
	assert(ConfigLoader.is_loaded, "[World] ConfigLoader 未加载完成")
	assert(not ConfigLoader.weapons.is_empty(), "[World] weapons.json 未加载")
	assert(not ConfigLoader.enemies.is_empty(), "[World] enemies.json 未加载")
	assert(not ConfigLoader.bosses.is_empty(), "[World] bosses.json 未加载")
	assert(not ConfigLoader.events.is_empty(), "[World] events.json 未加载")
	assert(ExpTable.get_max_level() == 30, "[World] 经验表未加载或 max_level != 30")
	print("[World] 配置自检通过 ✓")


# ============================================================================
# 信号回调
# ============================================================================

func _on_phase_changed(phase: DayNightStateMachine.Phase) -> void:
	match phase:
		DayNightStateMachine.Phase.NIGHT:
			print("[World] → 夜晚阶段")
		DayNightStateMachine.Phase.DAY:
			print("[World] → 抉择之昼（按 skip 跳过）")
		DayNightStateMachine.Phase.TRANSITION:
			pass  # 过渡帧，无需处理


func _on_night_tick(remaining: float) -> void:
	pass  # HUD 更新由 _process 处理


func _on_game_over(reason: String) -> void:
	print("[World] 游戏结束: %s" % reason)


func _on_game_win() -> void:
	print("[World] 通关！")


func _unhandled_input(event: InputEvent) -> void:
	# 抉择之昼按 skip 键进入下一夜（W1 空循环用）
	if event.is_action_pressed("skip") and day_night.get_phase() == DayNightStateMachine.Phase.DAY:
		day_night.skip_day_phase()


## 阶段标签（调试用）
func _phase_label(phase: DayNightStateMachine.Phase) -> String:
	match phase:
		DayNightStateMachine.Phase.INIT: return "初始"
		DayNightStateMachine.Phase.NIGHT: return "夜晚"
		DayNightStateMachine.Phase.DAY: return "昼"
		DayNightStateMachine.Phase.TRANSITION: return "切换"
	return "?"
