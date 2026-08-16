# ============================================================================
# World — 游戏世界根节点（W1 骨架）
# 职责：持有场景树结构（Player/Spawner/Pool/SpatialHash/UI），驱动昼夜状态机
# 架构：README §1.2 Main → World（含全部运行时子节点）
# W1 范围：仅搭建结构 + 验证配置加载 + 启动昼夜空循环
# ============================================================================
extends Node2D
class_name World

# 显式预加载 EnemyBase，确保 headless 下 class_name 注册（刷怪类型依赖）
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")
const _AFFIX_SYSTEM = preload("res://scripts/combat/affix_system.gd")
# 显式预加载 UI 脚本，确保 headless 下 class_name 可用（新脚本可能尚未写入 global_script_class_cache）
const _DAY_PHASE_UI = preload("res://scripts/core/day_phase_ui.gd")
const _RESULT_UI = preload("res://scripts/core/result_ui.gd")

# 子节点引用
@onready var player: Node2D = $Player
@onready var day_night: DayNightStateMachine = $DayNightStateMachine
@onready var enemy_pool: ObjectPool = $EnemyPool
@onready var projectile_pool: ObjectPool = $ProjectilePool
@onready var particle_pool: ObjectPool = $ParticlePool
@onready var pickup_pool: ObjectPool = $PickupPool
@onready var pickup_system: PickupSystem = $PickupSystem
@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var enemy_projectile_pool: ObjectPool = $EnemyProjectilePool
@onready var coin_pool: ObjectPool = $CoinPool
@onready var shop_manager: ShopManager = $ShopManager
@onready var shop_ui: ShopUI = $UI/ShopUI
@onready var day_phase_ui: DayPhaseUI = $UI/DayPhaseUI
@onready var result_ui: ResultUI = $UI/ResultUI
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
	# 开局授予默认武器后，同步生成武器实例并触发自动开火（§4.2）
	weapon_manager.sync_from_game_state()
	UpgradeManager.reset()
	# 空间哈希加入 group，供敌人/武器/弹道通过 group 查找（避免硬编码路径）
	spatial_hash_holder.add_to_group("spatial_hash")
	# 武器管理器接线（玩家位置 / 哈希 / 弹道池）
	weapon_manager.setup(player, spatial_hash_holder.get_hash(), projectile_pool)
	# 刷怪器接线（EnemyPool / 玩家 / 拾取系统）
	enemy_spawner.setup(enemy_pool, player, pickup_system)
	# 商店接线（ShopManager ↔ ShopUI 双向）
	shop_manager.setup(shop_ui)
	shop_ui.setup(shop_manager)
	shop_ui.skip_requested.connect(_on_shop_skip)
	# 注册 group（供 EnemyProjectile 查玩家 / EnemyBase 查弹道池；tscn 的 groups 属性在 headless 不生效，统一在此注册）
	player.add_to_group("player")
	enemy_spawner.add_to_group("enemy_spawner")
	enemy_projectile_pool.add_to_group("enemy_projectile_pool")
	# 先连接信号，再启动昼夜状态机（否则首夜 phase_changed 发射时监听器尚未挂载，导致首夜不刷怪）
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.night_tick.connect(_on_night_tick)
	GameState.game_over.connect(_on_game_over)
	GameState.game_win.connect(_on_game_win)
	# 升级结算后同步武器实例（获得/升级武器）
	UpgradeManager.upgrade_resolved.connect(_on_upgrade_resolved)
	# 启动昼夜状态机（首夜 phase_changed 将触发刷怪）
	day_night.start_run()
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
	_update_debug_label()


## 刷新调试 HUD（玩家血量/等级/经验等）。游戏结束/通关时树被暂停、_process 停跑，
## 故在 _on_game_over/_on_game_win 中显式再调一次，避免 HUD 冻结在致死前最后一帧。
func _update_debug_label() -> void:
	if debug_label == null:
		return
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
	assert(not ConfigLoader.passives.is_empty(), "[World] passives.json 未加载")
	assert(not ConfigLoader.pickups.is_empty(), "[World] pickups.json 未加载")
	assert(ConfigLoader.get_upgrade_config().has("reroll_cost"), "[World] upgrade.json 未加载")
	assert(ExpTable.get_max_level() == 30, "[World] 经验表未加载或 max_level != 30")
	print("[World] 配置自检通过 [OK]")


# ============================================================================
# 信号回调
# ============================================================================

func _on_phase_changed(phase: DayNightStateMachine.Phase) -> void:
	match phase:
		DayNightStateMachine.Phase.NIGHT:
			print("[World] → 夜晚阶段 (第 %d 夜)" % day_night.get_current_night())
			enemy_spawner.start_night(day_night.get_current_night())
		DayNightStateMachine.Phase.DAY:
			print("[World] → 抉择之昼（按 skip 跳过；开商店）")
			# 进昼清场（敌人 + 敌方弹道 + 掉落），保证商店阶段安全
			_clear_night_entities()
			# 显示白昼选择页面框架（技术选型.md：DayPhaseUI = 抉择之昼）
			day_phase_ui.enter_day(day_night.get_current_night())
			shop_manager.open_shop()
		DayNightStateMachine.Phase.TRANSITION:
			pass  # 过渡帧，无需处理


func _on_night_tick(remaining: float) -> void:
	pass  # HUD 更新由 _process 处理


func _on_game_over(reason: String) -> void:
	print("[World] 游戏结束: %s" % reason)
	_clear_night_entities()
	day_phase_ui.exit_day()
	# 冻结昼夜循环，阻止夜晚计时器继续滚动进入抉择之昼（§5.1）
	day_night.stop()
	# 显示结算/死因界面（§挫败感控制：死亡原因可视化）并暂停整棵树（防止玩家在结算页继续移动/交互）
	result_ui.show_game_over(reason, day_night.get_current_night(), GameState.player_level, GameState.tidecoins)
	get_tree().paused = true
	_update_debug_label()  # 树已暂停、_process 停跑，强制刷新 HUD 以显示真实 HP（致死时 player_health 已置 0）


func _on_game_win() -> void:
	print("[World] 通关！")
	_clear_night_entities()
	day_phase_ui.exit_day()
	day_night.stop()
	# 显示通关结算界面并暂停整棵树
	result_ui.show_victory(day_night.get_current_night(), GameState.player_level, GameState.tidecoins)
	get_tree().paused = true
	_update_debug_label()


## 玩家在商店点「继续下一夜」→ 关店并进下一夜（与 Q 键等效）
func _on_shop_skip() -> void:
	day_phase_ui.exit_day()
	shop_ui.close()
	day_night.skip_day_phase()


## 停止刷怪并回收敌人 / 敌方弹道 / 拾取物
func _clear_night_entities() -> void:
	enemy_spawner.stop()
	enemy_spawner.clear_all()
	if enemy_projectile_pool != null:
		enemy_projectile_pool.release_all()
	pickup_system.clear_all()


## 升级结算后同步武器实例（获得/升级武器）
func _on_upgrade_resolved(_offer: Dictionary, _is_skip: bool) -> void:
	weapon_manager.sync_from_game_state()


func _unhandled_input(event: InputEvent) -> void:
	# 抉择之昼按 skip 键进入下一夜
	if event.is_action_pressed("skip") and day_night.get_phase() == DayNightStateMachine.Phase.DAY:
		day_phase_ui.exit_day()
		shop_ui.close()
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
