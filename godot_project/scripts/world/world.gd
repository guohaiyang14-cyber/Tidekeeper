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
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var projectile_pool: ObjectPool = $ProjectilePool
@onready var particle_pool: ObjectPool = $ParticlePool
@onready var pickup_pool: ObjectPool = $PickupPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var hud: Control = $UI/HUD
@onready var debug_label: Label = $UI/HUD/DebugLabel


func _ready() -> void:
	print("[World] 初始化中...")
	# 验证配置加载
	_verify_config()
	# 开局：重置局内状态后再进昼夜循环
	var character_id: String = "watcher"
	if player is Player:
		character_id = (player as Player).character_id
	GameState.start_new_run(character_id)
	# 启动昼夜状态机
	day_night.start_run()
	# 连接信号
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.night_tick.connect(_on_night_tick)
	GameState.game_over.connect(_on_game_over)
	GameState.game_win.connect(_on_game_win)
	print("[World] 就绪 — 第 %d 夜开始 (pools=%d/%d/%d/%d gems=%d hash_cell=%.0f)" % [
		day_night.get_current_night(),
		enemy_pool.pool_size if enemy_pool else 0,
		projectile_pool.pool_size if projectile_pool else 0,
		particle_pool.pool_size if particle_pool else 0,
		pickup_pool.pool_size if pickup_pool else 0,
		pickup_system.active_gem_count() if pickup_system else 0,
		spatial_hash_holder.get_hash().get_cell_size() if spatial_hash_holder else 0.0,
	])


func _process(_delta: float) -> void:
	# 调试信息（W2 临时，W11 移到正式 HUD）
	if debug_label:
		debug_label.text = "夜: %d / 20  |  阶段: %s  |  剩余: %.1fs  |  等级: %d  |  HP: %d/%d  |  经验: %d  |  珠: %d" % [
			day_night.get_current_night(),
			_phase_label(day_night.get_phase()),
			day_night.get_night_remaining(),
			GameState.player_level,
			GameState.player_health,
			GameState.player_max_health,
			GameState.player_exp,
			pickup_system.active_gem_count() if pickup_system else 0,
		]


## 验证配置加载（启动自检）
func _verify_config() -> void:
	assert(ConfigLoader.is_loaded, "[World] ConfigLoader 未加载完成")
	assert(not ConfigLoader.weapons.is_empty(), "[World] weapons.json 未加载")
	assert(not ConfigLoader.enemies.is_empty(), "[World] enemies.json 未加载")
	assert(not ConfigLoader.bosses.is_empty(), "[World] bosses.json 未加载")
	assert(not ConfigLoader.events.is_empty(), "[World] events.json 未加载")
	assert(ExpTable.get_max_level() == 30, "[World] 经验表未加载或 max_level != 30")
	print("[World] 配置自检通过 [OK]")


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
	# 抉择之昼按 skip 键进入下一夜
	if event.is_action_pressed("skip") and day_night.get_phase() == DayNightStateMachine.Phase.DAY:
		day_night.skip_day_phase()
	# W2 调试：按 interact(E) 在玩家周围生成经验珠（随机品质）
	if event.is_action_pressed("interact") and pickup_system and player:
		# 围绕玩家生成 6 颗，展示不同品质颜色
		var count: int = 6
		var base_angle: float = RNG.randf_range(0.0, TAU)
		for i in count:
			var angle: float = base_angle + (TAU / count) * i
			var spawn_dist: float = 50.0 + RNG.randf_range(-5.0, 5.0)
			var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_dist
			var gem: ExpGem = pickup_system.spawn_exp_gem(pos, 5)
			if gem:
				print("[World] 生成 %s 经验珠 (%d exp) @ %s" % [
					ExpGem.QUALITY_NAMES[gem.get_quality()], gem.exp_value, pos,
				])


## 阶段标签（调试用）
func _phase_label(phase: DayNightStateMachine.Phase) -> String:
	match phase:
		DayNightStateMachine.Phase.INIT: return "初始"
		DayNightStateMachine.Phase.NIGHT: return "夜晚"
		DayNightStateMachine.Phase.DAY: return "昼"
		DayNightStateMachine.Phase.TRANSITION: return "切换"
	return "?"
