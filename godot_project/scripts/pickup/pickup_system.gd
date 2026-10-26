# ============================================================================
# PickupSystem — 拾取系统（W2 + 潮币 W4 + 宝箱 MVP）
# 职责：管理经验珠的生成、吸附检测、飞行、收集；潮币吸附；夜场宝箱触碰开启
# 数据源：config/pickups.json + Player.get_pickup_radius()
# 红线：走对象池（PickupPool / CoinPool / ChestPool）；不用 Physics2D，纯距离判定
# 架构：World 子节点，持有各池引用 + Player 引用
# ============================================================================
class_name PickupSystem
extends Node2D

# headless / 首次加载时保证 class_name 已注册
const _CHEST_SCRIPT = preload("res://scripts/pickup/chest.gd")
const _CHEST_POOL_SCRIPT = preload("res://scripts/core/chest_pool.gd")

## 无相机时假想可视半幅（机检 / headless；约 1080p 一半）
const _FALLBACK_VIEW_HALF: Vector2 = Vector2(960.0, 540.0)

## 经验珠收集信号（UI 可连接显示经验变化）
signal exp_collected(amount: int)

## 宝箱开启信号（kind / amount / rarity_name）
signal chest_opened(kind: String, amount: int, rarity_name: String)

## 对象池引用（主场景同级 `$`；缺失时 null，测试可用 bind() 注入）
@onready var _pool: ObjectPool = (
	$"../PickupPool" as ObjectPool if has_node("../PickupPool") else null
)

## 潮币池引用（W4 商店闭环）
@onready var _coin_pool: ObjectPool = (
	$"../CoinPool" as ObjectPool if has_node("../CoinPool") else null
)

## 宝箱池引用（夜场宝箱 MVP）
@onready var _chest_pool: ObjectPool = (
	$"../ChestPool" as ObjectPool if has_node("../ChestPool") else null
)

## 玩家引用（主场景同级 `$`；测试可用 bind()）
@onready var _player: Player = (
	$"../Player" as Player if has_node("../Player") else null
)

## 活跃经验珠列表（用于每帧更新）
var _active_gems: Array[ExpGem] = []

## 活跃潮币列表（用于每帧更新）
var _active_coins: Array[Coin] = []

## 活跃宝箱列表（主动触碰，不吸附）
var _active_chests: Array[Chest] = []

## 自 config/pickups.json 加载的运行时参数
var _collect_radius: float = 16.0
var _attract_speed: float = 560.0
## 半径内最大吸附时长（秒）；与 attract_speed 取 max，避免慢于玩家移速跟跑
var _attract_snap_time: float = 0.1
var _scatter_range: float = 12.0
## 连续不在显示区内超过此时长则回收（不入账）；经验珠与潮币共用
var _offscreen_despawn_sec: float = 5.0
## 池压（相对 hard_cap）：全图强制吸附阈值；屏外加速阈值（须更低，否则与全图吸互斥）
var _pressure_attract_ratio: float = 0.75
var _pressure_offscreen_ratio: float = 0.5
var _pressure_offscreen_sec: float = 2.0
## 触顶生成失败时强制入账最远掉落的批量（腾槽，防静默丢经验/币）
var _pressure_relief_batch: int = 48
## 腾槽日志限流（毫秒）
const _RELIEF_LOG_INTERVAL_MSEC: int = 5000
var _relief_log_msec: int = -_RELIEF_LOG_INTERVAL_MSEC
var _quality_weights: Array[float] = [65.0, 25.0, 8.0, 2.0]
var _quality_exp_mult: Array[float] = [1.0, 2.0, 5.0, 10.0]

## 宝箱参数（pickups.json.chest）
var _chest_touch_radius: float = 28.0
var _chest_ring_min: float = 180.0
var _chest_ring_max: float = 220.0
var _chest_per_night_min: int = 0
var _chest_per_night_max: int = 2
var _chest_rarity_weights: Array[float] = [50.0, 30.0, 15.0, 5.0]
var _chest_rarity_names: Array[String] = ["普通", "精良", "稀有", "史诗"]
var _chest_rewards: Array = []

## 宝箱刷新模式（2026-10-26 用户反馈「宝箱应该是动态刷新的，不应该是开局就刷新到任务附近」）
## timed = 夜间过程中按间隔动态刷（默认）；night_start = 旧行为（进夜一次性刷在灯塔外环）
var _chest_spawn_mode: String = "timed"
var _chest_first_delay: float = 12.0
var _chest_interval: float = 22.0
var _chest_max_active: int = 2
var _chest_min_dist: float = 320.0
var _chest_max_dist: float = 760.0
## 排期拟合（2026-10-26 code-review 修）：事件把宝箱预算翻倍后，固定 22s 间隔在 45s 夜里
## 只够刷 2 只（12s / 34s），第 3、4 只排到夜后 → 倍率形同无效。改为按夜长拟合有效间隔。
## schedule_tail_sec = 末尾留量（最后一只要在夜结束前这么久落地，留出被看见/够得着的时间）
var _chest_schedule_tail: float = 3.0
## 本夜实际生效的刷新间隔（≤ _chest_interval；预算翻倍时自动压缩）
var _chest_interval_eff: float = 22.0
## 间隔下限：避免极端预算下退化成一帧连刷
const MIN_CHEST_INTERVAL: float = 0.5
## 夜长来源（config/night.json）——用 preload 而非 class_name，干净环境无编辑器导入也能解析
const _DNSM = preload("res://scripts/core/day_night_state_machine.gd")
## 本夜剩余可刷数量 / 下次刷新倒计时 / 是否处于动态刷新窗口
var _chest_budget: int = 0
var _chest_timer: float = 0.0
var _chest_night_active: bool = false

## 测试注入：覆盖相机可见区（enabled=false 时改用相机/假想区）
var _test_view_rect: Rect2 = Rect2()
var _has_test_view: bool = false


func _ready() -> void:
	_load_config()
	# 触达 preload，确保 headless 首次加载已注册 class_name
	assert(_CHEST_SCRIPT != null and _CHEST_POOL_SCRIPT != null)
	print("[PickupSystem] 就绪 (pool=%s player=%s chest_pool=%s)" % [
		String(_pool.name) if _pool else "null",
		String(_player.name) if _player else "null",
		String(_chest_pool.name) if _chest_pool else "null",
	])


## 测试 / 手动注入引用（绕过场景路径）
func bind(pool: ObjectPool, player: Player) -> void:
	_pool = pool
	_player = player


## 注入潮币池（测试用）
func bind_coin_pool(pool: ObjectPool) -> void:
	_coin_pool = pool


## 注入宝箱池（测试用）
func bind_chest_pool(pool: ObjectPool) -> void:
	_chest_pool = pool


## 测试：覆盖显示区判定；enabled=false 清除
func set_test_view_rect(rect: Rect2, enabled: bool = true) -> void:
	_test_view_rect = rect
	_has_test_view = enabled


func _process(delta: float) -> void:
	if _player == null:
		return
	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = _player.get_pickup_radius()
	# 本帧只算一次显示区，避免每个掉落重复查相机
	var view_rect: Rect2 = _compute_display_rect()

	if not _active_gems.is_empty():
		_process_gems(delta, player_pos, pickup_radius, view_rect)
	if not _active_coins.is_empty():
		_process_coins(delta, player_pos, pickup_radius, view_rect)
	if not _active_chests.is_empty():
		_process_chests(player_pos)
	_process_chest_spawn(delta, player_pos)


func _process_gems(delta: float, player_pos: Vector2, pickup_radius: float, view_rect: Rect2) -> void:
	var force_attract: bool = _should_force_attract(_pool, _active_gems.size())
	var offscreen_sec: float = _effective_offscreen_sec(_pool, _active_gems.size())
	# 倒序遍历以便安全删除已收集的珠子
	var i: int = _active_gems.size() - 1
	while i >= 0:
		var gem: ExpGem = _active_gems[i]
		if not is_instance_valid(gem):
			_active_gems.remove_at(i)
			i -= 1
			continue

		var dist: float = gem.global_position.distance_to(player_pos)

		if gem.is_attracted():
			# 已吸附：飞向玩家 + 检查收集；吸附中不计屏外超时
			gem.clear_offscreen_time()
			gem.update_attract(player_pos, delta)
			var new_dist: float = gem.global_position.distance_to(player_pos)
			if new_dist <= _collect_radius:
				_collect(gem, i)
		elif dist <= pickup_radius or force_attract:
			# 进入拾取半径，或硬顶附近/空闲耗尽时全图强制吸附
			gem.clear_offscreen_time()
			if dist <= _collect_radius:
				_collect(gem, i)
			else:
				gem.start_attract(player_pos, _attract_speed, _attract_snap_time)
				gem.update_attract(player_pos, delta)
				if gem.global_position.distance_to(player_pos) <= _collect_radius:
					_collect(gem, i)
		elif gem.tick_offscreen(delta, view_rect.has_point(gem.global_position), offscreen_sec):
			_despawn_gem(gem, i)
		i -= 1


# ============================================================================
# 公共接口
# ============================================================================

## 生成经验珠（敌人死亡时调用；品质随机决定经验倍率）
func spawn_exp_gem(pos: Vector2, base_exp: int) -> ExpGem:
	var quality: ExpGem.Quality = _roll_quality()
	var final_exp: int = maxi(1, roundi(float(base_exp) * _quality_exp_mult[quality]))
	return _spawn_gem(pos, final_exp, quality)


## 批量生成：对整次掉落只滚一次品质，再拆成多颗（总经验 = total_exp × 倍率）
func spawn_exp_gems(pos: Vector2, total_exp: int, gem_count: int = 3) -> void:
	if total_exp <= 0 or gem_count <= 0:
		return
	var quality: ExpGem.Quality = _roll_quality()
	var final_total: int = maxi(1, roundi(float(total_exp) * _quality_exp_mult[quality]))
	var per_gem: int = int(final_total / float(gem_count))
	var remainder: int = final_total % gem_count
	for i in gem_count:
		var value: int = per_gem + (1 if i < remainder else 0)
		if value <= 0:
			continue
		var offset: Vector2 = Vector2(
			RNG.randf_range(-_scatter_range, _scatter_range),
			RNG.randf_range(-_scatter_range, _scatter_range)
		)
		_spawn_gem(pos + offset, value, quality)


## 生成潮币（敌人死亡时调用；amount 为掉落实 value）
func spawn_coin(pos: Vector2, amount: int) -> Coin:
	if _coin_pool == null or amount <= 0:
		return null
	var coin: Coin = _coin_pool.acquire() as Coin
	if coin == null:
		_force_collect_farthest_coins(_pressure_relief_batch)
		coin = _coin_pool.acquire() as Coin
	if coin == null:
		return null
	coin.global_position = pos
	coin.value = amount
	_active_coins.append(coin)
	return coin


## 潮币每帧更新（吸引 + 收集 → 入账）
func _process_coins(delta: float, player_pos: Vector2, pickup_radius: float, view_rect: Rect2) -> void:
	var force_attract: bool = _should_force_attract(_coin_pool, _active_coins.size())
	var offscreen_sec: float = _effective_offscreen_sec(_coin_pool, _active_coins.size())
	var i: int = _active_coins.size() - 1
	while i >= 0:
		var coin: Coin = _active_coins[i]
		if not is_instance_valid(coin):
			_active_coins.remove_at(i)
			i -= 1
			continue
		var dist: float = coin.global_position.distance_to(player_pos)
		if coin.is_attracted():
			coin.clear_offscreen_time()
			coin.update_attract(player_pos, delta)
			if coin.global_position.distance_to(player_pos) <= _collect_radius:
				_collect_coin(coin, i)
		elif dist <= pickup_radius or force_attract:
			coin.clear_offscreen_time()
			if dist <= _collect_radius:
				_collect_coin(coin, i)
			else:
				coin.start_attract(player_pos, _attract_speed, _attract_snap_time)
				coin.update_attract(player_pos, delta)
				if coin.global_position.distance_to(player_pos) <= _collect_radius:
					_collect_coin(coin, i)
		elif coin.tick_offscreen(delta, view_rect.has_point(coin.global_position), offscreen_sec):
			_despawn_coin(coin, i)
		i -= 1


## 收集潮币（入账 + 回收）
func _collect_coin(coin: Coin, index: int) -> void:
	GameState.add_tidecoins(coin.value)
	AudioManager.play_sfx("coin")
	_active_coins.remove_at(index)
	_coin_pool.release(coin)


## 屏外超时丢弃潮币（不入账）
func _despawn_coin(coin: Coin, index: int) -> void:
	_active_coins.remove_at(index)
	if _coin_pool != null:
		_coin_pool.release(coin)


## 当前活跃潮币数（调试用）
func active_coin_count() -> int:
	return _active_coins.size()


## 清除所有活跃经验珠 / 潮币 / 宝箱（场景重置 / 新局 / 进昼）
func clear_all() -> void:
	if _pool != null:
		for gem in _active_gems:
			if is_instance_valid(gem):
				_pool.release(gem)
	_active_gems.clear()
	if _coin_pool != null:
		for coin in _active_coins:
			if is_instance_valid(coin):
				_coin_pool.release(coin)
	_active_coins.clear()
	_clear_chests()


## 当前活跃宝箱数（调试 / TestBot）
func active_chest_count() -> int:
	return _active_chests.size()


## 查找最近宝箱；找到时写入 out_pos[0] 并返回 true
func try_nearest_chest_position(from: Vector2, out_pos: Array[Vector2], max_range: float = 2400.0) -> bool:
	var best_dist: float = max_range
	var best_pos: Vector2 = Vector2.ZERO
	var found: bool = false
	for chest in _active_chests:
		if not is_instance_valid(chest):
			continue
		var dist: float = from.distance_to(chest.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = chest.global_position
			found = true
	if not found:
		return false
	if out_pos.is_empty():
		out_pos.append(best_pos)
	else:
		out_pos[0] = best_pos
	return true


## 进夜入口：按 spawn.mode 决定「进夜一次性刷」还是「夜间动态刷」
## timed 模式只布防不立刻刷——箱子在夜里陆续出现在玩家周边远处，不再开局堆在灯塔附近
## night_seconds：本夜时长（World 传 day_night 的表值）。<=0 时自行按当前夜次查表，
##   保证只被测试或旧调用方单参调用时也能算对排期。
func begin_night_chests(lighthouse_pos: Vector2, night_seconds: float = 0.0) -> void:
	if _chest_spawn_mode == "night_start":
		spawn_night_chests(lighthouse_pos)
		return
	_clear_chests()
	var base_count: int = RNG.randi_range(_chest_per_night_min, _chest_per_night_max)
	var total: int = maxi(0, int(round(float(base_count) * EventSystem.get_chest_mult())))
	_chest_budget = total
	_chest_timer = _chest_first_delay
	_chest_night_active = total > 0
	# 排期拟合：让 total 只箱全部落在本夜内（事件翻倍预算不再被夜长吃掉）
	var night_len: float = night_seconds
	if night_len <= 0.0:
		night_len = _DNSM.duration_for_night(maxi(1, GameState.current_night))
	_chest_interval_eff = fit_chest_interval(
		total, _chest_first_delay, _chest_interval, night_len, _chest_schedule_tail)
	if total > 0:
		print("[PickupSystem] 宝箱动态刷新布防：本夜 %d 只（夜长 %.0fs / 首刷 %.1fs / 间隔 %.1fs / 场上上限 %d）" % [
			total, night_len, _chest_first_delay, _chest_interval_eff, _chest_max_active,
		])


## 把 total 只箱塞进 night_len 秒所需的间隔（纯函数，便于机检）
## 规则：间隔只压缩不放大——默认节奏够用时原样返回，保证常规夜的手感不变。
static func fit_chest_interval(total: int, first_delay: float, interval: float,
		night_len: float, tail: float) -> float:
	if total <= 1 or night_len <= 0.0:
		return interval
	var span: float = maxf(0.0, night_len - first_delay - tail)
	var fit: float = span / float(total - 1)
	return clampf(minf(interval, fit), MIN_CHEST_INTERVAL, interval)


## 本夜实际生效的刷新间隔（调试 / 机检）
func chest_spawn_interval_eff() -> float:
	return _chest_interval_eff


## 本夜首刷延迟（调试 / 机检）
func chest_first_delay() -> float:
	return _chest_first_delay


## 动态刷新：到点且场上未达上限时，在玩家外围 [min,max] 距离随机落箱
func _process_chest_spawn(delta: float, player_pos: Vector2) -> void:
	if not _chest_night_active or _chest_budget <= 0:
		return
	if _active_chests.size() >= _chest_max_active:
		return
	_chest_timer -= delta
	if _chest_timer > 0.0:
		return
	var pos: Vector2 = _roll_chest_spawn_pos(player_pos)
	var chest: Chest = _spawn_chest(pos)
	if chest == null:
		# 池不可用时下次再试，不消耗预算
		_chest_timer = _chest_interval_eff
		return
	_chest_budget -= 1
	_chest_timer = _chest_interval_eff
	print("[PickupSystem] 动态刷新宝箱 rarity=%s @ (%.0f, %.0f) 距玩家 %.0fpx（本夜剩 %d）" % [
		_rarity_display(int(chest.rarity)), pos.x, pos.y,
		player_pos.distance_to(pos), _chest_budget,
	])


## 落箱点：随机方位 + 玩家外围距离带（避免贴脸刷出，也不至于远到找不到）
func _roll_chest_spawn_pos(player_pos: Vector2) -> Vector2:
	var angle: float = RNG.randf_range(0.0, TAU)
	var dist: float = RNG.randf_range(_chest_min_dist, maxf(_chest_min_dist, _chest_max_dist))
	return player_pos + Vector2(cos(angle), sin(angle)) * dist


## 本夜动态刷新剩余数量（调试 / 机检）
func chest_budget_left() -> int:
	return _chest_budget


## 本夜一次性刷宝箱（旧行为；night_start 模式与机检用）
## 数量 = [min,max] × EventSystem.get_chest_mult，至少 0
## 每次调用先清掉场上残留箱，避免同夜重复刷叠箱。
func spawn_night_chests(lighthouse_pos: Vector2) -> int:
	if _chest_pool == null:
		push_warning("[PickupSystem] ChestPool 未就绪，跳过宝箱刷新")
		return 0
	_clear_chests()
	var base_count: int = RNG.randi_range(_chest_per_night_min, _chest_per_night_max)
	var count: int = int(round(float(base_count) * EventSystem.get_chest_mult()))
	count = maxi(0, count)
	var spawned: int = 0
	for _i in count:
		var angle: float = RNG.randf_range(0.0, TAU)
		var radius: float = RNG.randf_range(_chest_ring_min, _chest_ring_max)
		var pos: Vector2 = lighthouse_pos + Vector2(cos(angle), sin(angle)) * radius
		var chest: Chest = _spawn_chest(pos)
		if chest != null:
			spawned += 1
			print("[PickupSystem] 刷新宝箱 rarity=%s @ (%.0f, %.0f)" % [
				_chest_rarity_names[clampi(int(chest.rarity), 0, _chest_rarity_names.size() - 1)],
				pos.x, pos.y,
			])
	if spawned > 0:
		print("[PickupSystem] 本夜宝箱 ×%d（基数=%d ×倍率=%.1f）" % [
			spawned, base_count, EventSystem.get_chest_mult(),
		])
	return spawned


## 测试 / 调试：在指定位置刷一只固定稀有度宝箱（不清场、不滚数量、不消耗稀有度 RNG）
func spawn_chest_at(pos: Vector2, rarity: Chest.Rarity) -> Chest:
	if _chest_pool == null:
		return null
	var chest: Chest = _chest_pool.acquire() as Chest
	if chest == null:
		return null
	chest.global_position = pos
	chest.set_rarity(rarity)
	_active_chests.append(chest)
	return chest


func _clear_chests() -> void:
	if _chest_pool != null:
		for chest in _active_chests:
			if is_instance_valid(chest):
				_chest_pool.release(chest)
	_active_chests.clear()
	# 清场即停表：进昼/新局/重开时不再继续动态刷新
	_chest_night_active = false
	_chest_budget = 0
	_chest_timer = 0.0
	_chest_interval_eff = _chest_interval


func _spawn_chest(pos: Vector2) -> Chest:
	if _chest_pool == null:
		return null
	var chest: Chest = _chest_pool.acquire() as Chest
	if chest == null:
		return null
	var rarity: Chest.Rarity = _roll_chest_rarity()
	chest.global_position = pos
	chest.set_rarity(rarity)
	_active_chests.append(chest)
	return chest


func _process_chests(player_pos: Vector2) -> void:
	var i: int = _active_chests.size() - 1
	while i >= 0:
		var chest: Chest = _active_chests[i]
		if not is_instance_valid(chest):
			_active_chests.remove_at(i)
			i -= 1
			continue
		if player_pos.distance_to(chest.global_position) <= _chest_touch_radius:
			_open_chest(chest, i)
		i -= 1


func _open_chest(chest: Chest, index: int) -> void:
	var rarity: int = clampi(int(chest.rarity), 0, maxi(0, _chest_rarity_names.size() - 1))
	# 2026-10-26 用户反馈「提示信息应该跟所选的语言相同」：稀有度名随语言本地化，
	# config rarity_names 仅作兜底（未翻译时仍显示中文而非 key）
	var rarity_name: String = _rarity_display(rarity)
	var reward: Dictionary = {}
	if rarity < _chest_rewards.size() and _chest_rewards[rarity] is Dictionary:
		reward = _chest_rewards[rarity]
	# alternatives 支持：同一稀有度多个奖励随机选一（GDD §9.3「1 件随机稀有度物品」）
	if reward.has("alternatives") and reward["alternatives"] is Array:
		var alts: Array = reward["alternatives"]
		if alts.size() > 0:
			var picked: Variant = alts[RNG.randi_range(0, alts.size() - 1)]
			if picked is Dictionary:
				reward = picked as Dictionary
			else:
				push_warning("[PickupSystem] alternatives 项非 Dictionary，回退潮币")
				reward = {"kind": "tidecoins", "amount": 15}
	var kind: String = str(reward.get("kind", "tidecoins"))
	var amount: int = int(reward.get("amount", 10))
	var granted_kind: String = kind
	var granted_amount: int = amount
	# 挣扎倒地窗口：开箱不发奖（避免 heal 失败转潮币刷经济）；箱子仍回收
	if GameState.is_struggling():
		granted_kind = "none"
		granted_amount = 0
		print("[PickupSystem] 拾取宝箱 → 挣扎中跳过奖励（%s）" % rarity_name)
		chest_opened.emit(granted_kind, granted_amount, rarity_name)
		_active_chests.remove_at(index)
		if _chest_pool != null:
			_chest_pool.release(chest)
		return
	match kind:
		"heal":
			granted_amount = GameState.heal_player(amount)
			if granted_amount <= 0:
				# 仅满血等「治疗无效」回退潮币；挣扎已在上方拦截
				granted_kind = "tidecoins"
				granted_amount = maxi(8, amount >> 1)
				GameState.add_tidecoins(granted_amount)
		"evolution":
			var got: int = EvolutionSystem.grant_items(amount, true, true)
			if got > 0:
				granted_amount = got
			else:
				granted_kind = "tidecoins"
				granted_amount = int(reward.get("fallback_tidecoins", 40))
				GameState.add_tidecoins(granted_amount)
		"refine_essence":
			var got_refine: int = RefineSystem.grant_essence(amount)
			if got_refine > 0:
				granted_amount = got_refine
			else:
				granted_kind = "tidecoins"
				granted_amount = int(reward.get("fallback_tidecoins", 40))
				GameState.add_tidecoins(granted_amount)
		"weapon":
			# 2026-10-26 用户反馈「宝箱道具应该包括所有」：新增武器奖励（未持有优先，其次已持有升级）
			var got_w: String = _grant_random_weapon()
			if got_w != "":
				granted_kind = "weapon"
				granted_amount = 1
			else:
				granted_kind = "tidecoins"
				granted_amount = int(reward.get("fallback_tidecoins", 60))
				GameState.add_tidecoins(granted_amount)
		"passive":
			var got_p: String = _grant_random_passive()
			if got_p != "":
				granted_kind = "passive"
				granted_amount = 1
			else:
				granted_kind = "tidecoins"
				granted_amount = int(reward.get("fallback_tidecoins", 50))
				GameState.add_tidecoins(granted_amount)
		_:
			granted_kind = "tidecoins"
			GameState.add_tidecoins(amount)
			granted_amount = amount
	print("[PickupSystem] 拾取宝箱 → %s ×%d（%s）" % [granted_kind, granted_amount, rarity_name])
	chest_opened.emit(granted_kind, granted_amount, rarity_name)
	_active_chests.remove_at(index)
	if _chest_pool != null:
		_chest_pool.release(chest)
	else:
		push_warning("[PickupSystem] 开箱后 ChestPool 缺失，无法回收实例")


## 当前活跃经验珠数（调试 / 性能监控用）
func active_gem_count() -> int:
	return _active_gems.size()


## 当前活跃珠经验总和（测试 / 调试用）
func active_exp_total() -> int:
	var total: int = 0
	for gem in _active_gems:
		if is_instance_valid(gem):
			total += gem.exp_value
	return total


## 距 from 最近的经验珠世界坐标；无珠或均超出 max_range 时返回 Vector2.ZERO。
## 注意：原点也可能有珠，故「无珠」请用 try_nearest_gem_position，勿把 ZERO 当失败哨兵。
func find_nearest_gem_position(from: Vector2, max_range: float = 2400.0) -> Vector2:
	var out_pos: Array[Vector2] = [Vector2.ZERO]
	if try_nearest_gem_position(from, out_pos, max_range):
		return out_pos[0]
	return Vector2.ZERO


## 查找最近经验珠；找到时写入 out_pos[0] 并返回 true（可区分「原点有珠」与「无珠」）。
func try_nearest_gem_position(from: Vector2, out_pos: Array[Vector2], max_range: float = 2400.0) -> bool:
	var best_dist: float = max_range
	var best_pos: Vector2 = Vector2.ZERO
	var found: bool = false
	for gem in _active_gems:
		if not is_instance_valid(gem):
			continue
		var dist: float = from.distance_to(gem.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = gem.global_position
			found = true
	if not found:
		return false
	if out_pos.is_empty():
		out_pos.append(best_pos)
	else:
		out_pos[0] = best_pos
	return true


# ============================================================================
# 内部方法
# ============================================================================

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_exp_gem_config()
	if cfg.is_empty():
		push_warning("[PickupSystem] pickups.json.exp_gem 缺失，使用内置回退值")
	else:
		_collect_radius = float(cfg.get("collect_radius", _collect_radius))
		_attract_speed = float(cfg.get("attract_speed", _attract_speed))
		_attract_snap_time = maxf(0.05, float(cfg.get("attract_snap_time", _attract_snap_time)))
		_scatter_range = float(cfg.get("scatter_range", _scatter_range))
		_offscreen_despawn_sec = maxf(0.1, float(cfg.get("offscreen_despawn_sec", _offscreen_despawn_sec)))
		_pressure_attract_ratio = clampf(float(cfg.get("pool_pressure_attract_ratio", _pressure_attract_ratio)), 0.1, 1.0)
		_pressure_offscreen_ratio = clampf(float(cfg.get("pool_pressure_offscreen_ratio", _pressure_offscreen_ratio)), 0.1, 1.0)
		# 屏外加速阈值须低于全图吸，否则缩短超时永远走不到
		if _pressure_offscreen_ratio >= _pressure_attract_ratio:
			_pressure_offscreen_ratio = maxf(0.1, _pressure_attract_ratio * 0.67)
		_pressure_offscreen_sec = maxf(0.1, float(cfg.get("pool_pressure_offscreen_sec", _pressure_offscreen_sec)))
		_pressure_relief_batch = maxi(1, int(cfg.get("pool_pressure_relief_batch", _pressure_relief_batch)))
		_quality_weights = _to_float_array(cfg.get("quality_weights", _quality_weights), _quality_weights)
		_quality_exp_mult = _to_float_array(cfg.get("quality_exp_mult", _quality_exp_mult), _quality_exp_mult)
		# 品质数组长度必须与 Quality 枚举（4）一致，否则 _roll_quality 索引越界
		if _quality_weights.size() != 4 or _quality_exp_mult.size() != 4:
			push_warning("[PickupSystem] quality_weights/exp_mult 长度应为 4，回退默认值")
			_quality_weights = [65.0, 25.0, 8.0, 2.0]
			_quality_exp_mult = [1.0, 2.0, 5.0, 10.0]
	_load_chest_config()


## 与 pickups.json.chest.rewards 对齐的内置默认表（缺表/长度错误时回退）
func _default_chest_rewards() -> Array:
	return [
		{"kind": "tidecoins", "amount": 15},
		{"alternatives": [
			{"kind": "tidecoins", "amount": 35},
			{"kind": "heal", "amount": 20}
		]},
		{"alternatives": [
			{"kind": "tidecoins", "amount": 60},
			{"kind": "heal", "amount": 35},
			{"kind": "evolution", "amount": 1, "fallback_tidecoins": 55}
		]},
		{"alternatives": [
			{"kind": "evolution", "amount": 1, "fallback_tidecoins": 80},
			{"kind": "refine_essence", "amount": 2, "fallback_tidecoins": 70},
			{"kind": "heal", "amount": 50}
		]},
	]


## 测试用：临时覆盖 4 档稀有度奖励表
func set_chest_rewards_for_test(rewards: Array) -> void:
	if rewards.size() != 4:
		push_warning("[PickupSystem] set_chest_rewards_for_test 长度应为 4，忽略")
		return
	_chest_rewards = rewards


## 测试用：从 config 重载宝箱表（撤销 set_chest_rewards_for_test）
func reload_chest_config_for_test() -> void:
	_load_chest_config()


## 测试用：立即按触碰半径开箱（不经 _process，避免其它系统污染 RNG）
func force_open_chests_at_for_test(player_pos: Vector2) -> void:
	_process_chests(player_pos)


func _load_chest_config() -> void:
	var cfg: Dictionary = ConfigLoader.get_chest_config()
	if cfg.is_empty():
		push_warning("[PickupSystem] pickups.json.chest 缺失，使用内置回退值")
		_chest_rewards = _default_chest_rewards()
		return
	_chest_touch_radius = float(cfg.get("touch_radius", _chest_touch_radius))
	_chest_ring_min = float(cfg.get("ring_radius_min", _chest_ring_min))
	_chest_ring_max = float(cfg.get("ring_radius_max", _chest_ring_max))
	_chest_per_night_min = int(cfg.get("per_night_min", _chest_per_night_min))
	_chest_per_night_max = int(cfg.get("per_night_max", _chest_per_night_max))
	# 动态刷新参数（spawn 段）；缺省沿用 timed + 内置节奏
	var spawn: Variant = cfg.get("spawn", {})
	if spawn is Dictionary:
		var sp: Dictionary = spawn as Dictionary
		_chest_spawn_mode = String(sp.get("mode", _chest_spawn_mode))
		_chest_first_delay = float(sp.get("first_delay_sec", _chest_first_delay))
		_chest_interval = float(sp.get("interval_sec", _chest_interval))
		_chest_max_active = maxi(1, int(sp.get("max_active", _chest_max_active)))
		_chest_min_dist = float(sp.get("min_distance_from_player", _chest_min_dist))
		_chest_max_dist = float(sp.get("max_distance_from_player", _chest_max_dist))
		_chest_schedule_tail = maxf(0.0, float(sp.get("schedule_tail_sec", _chest_schedule_tail)))
	if _chest_spawn_mode != "timed" and _chest_spawn_mode != "night_start":
		push_warning("[PickupSystem] chest.spawn.mode=%s 非法，回落 timed" % _chest_spawn_mode)
		_chest_spawn_mode = "timed"
	if _chest_max_dist < _chest_min_dist:
		_chest_max_dist = _chest_min_dist
	if _chest_interval < 1.0:
		_chest_interval = 1.0
	# 未进夜时有效间隔跟表值一致；进夜后由 begin_night_chests 按夜长拟合
	_chest_interval_eff = _chest_interval
	_chest_rarity_weights = _to_float_array(cfg.get("rarity_weights", _chest_rarity_weights), _chest_rarity_weights)
	_chest_rewards = cfg.get("rewards", _chest_rewards)
	if not (_chest_rewards is Array):
		_chest_rewards = []
	if _chest_rewards.size() != 4:
		push_warning("[PickupSystem] chest.rewards 长度应为 4，回退默认奖励表")
		_chest_rewards = _default_chest_rewards()
	var names_raw: Variant = cfg.get("rarity_names", _chest_rarity_names)
	if names_raw is Array:
		_chest_rarity_names.clear()
		for n in names_raw as Array:
			_chest_rarity_names.append(str(n))
	if _chest_rarity_names.size() != 4:
		_chest_rarity_names = ["普通", "精良", "稀有", "史诗"]
	if _chest_rarity_weights.size() != 4:
		push_warning("[PickupSystem] chest.rarity_weights 长度应为 4，回退默认值")
		_chest_rarity_weights = [50.0, 30.0, 15.0, 5.0]
	if _chest_ring_max < _chest_ring_min:
		_chest_ring_max = _chest_ring_min
	if _chest_per_night_max < _chest_per_night_min:
		_chest_per_night_max = _chest_per_night_min


## 宝箱发武器：未持有的优先（需有空槽），其次已持有未满级的升级；都不可用时返回 ""
func _grant_random_weapon() -> String:
	var fresh: Array[String] = []
	var upgradable: Array[String] = []
	var has_free_slot: bool = GameState.weapon_slots.size() < GameState.MAX_WEAPON_SLOTS
	for raw in ConfigLoader.get_all_weapon_ids():
		var wid: String = String(raw)
		if wid == "":
			continue
		if wid in GameState.weapon_slots:
			if GameState.get_weapon_level(wid) < GameState.max_weapon_level:
				upgradable.append(wid)
		elif has_free_slot:
			fresh.append(wid)
	var pool: Array[String] = []
	pool.append_array(fresh)
	pool.append_array(upgradable)
	if pool.is_empty():
		return ""
	var pick: String = pool[RNG.randi_range(0, pool.size() - 1)]
	return pick if GameState.add_weapon(pick) else ""


## 宝箱发被动：同武器口径（未持有优先，其次升级）
func _grant_random_passive() -> String:
	var fresh: Array[String] = []
	var upgradable: Array[String] = []
	var has_free_slot: bool = GameState.passive_slots.size() < GameState.MAX_PASSIVE_SLOTS
	for raw in ConfigLoader.get_all_passive_ids():
		var pid: String = String(raw)
		if pid == "":
			continue
		if pid in GameState.passive_slots:
			if GameState.get_passive_level(pid) < GameState.max_passive_level:
				upgradable.append(pid)
		elif has_free_slot:
			fresh.append(pid)
	var pool: Array[String] = []
	pool.append_array(fresh)
	pool.append_array(upgradable)
	if pool.is_empty():
		return ""
	var pick: String = pool[RNG.randi_range(0, pool.size() - 1)]
	return pick if GameState.add_passive(pick) else ""


## 稀有度显示名（跟随当前语言；config rarity_names 为中文兜底，未翻译时不会露出 key）
func _rarity_display(rarity: int) -> String:
	var idx: int = clampi(rarity, 0, maxi(0, _chest_rarity_names.size() - 1))
	var fallback: String = _chest_rarity_names[idx] if idx < _chest_rarity_names.size() else ""
	match idx:
		0:
			return _loc_or("ui.chest.rarity_0", fallback)
		1:
			return _loc_or("ui.chest.rarity_1", fallback)
		2:
			return _loc_or("ui.chest.rarity_2", fallback)
		3:
			return _loc_or("ui.chest.rarity_3", fallback)
	return fallback


## 本地化取值；缺 key 时回退 fallback（不把 key 直接显示给玩家）
func _loc_or(key: String, fallback: String) -> String:
	var text: String = LanguageSystem.localize(key)
	return text if text != key else fallback


func _roll_chest_rarity() -> Chest.Rarity:
	var total: float = 0.0
	for w in _chest_rarity_weights:
		total += w
	if total <= 0.0:
		return Chest.Rarity.COMMON
	var roll: float = RNG.randf_range(0.0, total)
	var cumulative: float = 0.0
	for i in _chest_rarity_weights.size():
		cumulative += _chest_rarity_weights[i]
		if roll <= cumulative:
			return i as Chest.Rarity
	return Chest.Rarity.COMMON


func _to_float_array(raw: Variant, fallback: Array[float]) -> Array[float]:
	if raw is Array:
		var out: Array[float] = []
		for v in raw as Array:
			out.append(float(v))
		if not out.is_empty():
			return out
	return fallback


func _spawn_gem(pos: Vector2, exp_value: int, quality: ExpGem.Quality) -> ExpGem:
	if _pool == null:
		push_error("[PickupSystem] PickupPool 未就绪")
		return null
	var gem: ExpGem = _pool.acquire() as ExpGem
	if gem == null:
		_force_collect_farthest_gems(_pressure_relief_batch)
		gem = _pool.acquire() as ExpGem
	if gem == null:
		return null
	gem.global_position = pos
	gem.exp_value = exp_value
	gem.set_quality(quality)
	_active_gems.append(gem)
	return gem


## 活跃数相对硬顶的占用比（不用预分配 pool_size，避免 700×0.75 过早全图吸）
func _pool_occupancy(pool: ObjectPool, active: int) -> float:
	if pool == null:
		return 0.0
	var cap: int = maxi(pool.pickup_hard_cap(), 1)
	return float(active) / float(cap)


## 全图强制吸附：仅硬顶已满且空闲耗尽，或活跃占用达 attract_ratio
## （预分配抽干仍可 soft_expand，不得真空）
func _should_force_attract(pool: ObjectPool, active: int) -> bool:
	if pool == null:
		return false
	if _pool_occupancy(pool, active) >= _pressure_attract_ratio:
		return true
	var hard: int = pool.pickup_hard_cap()
	return pool.pool_size >= hard and pool.available_count() <= 0


## 近硬顶但未全图吸时缩短屏外超时，加速腾槽（不入账）
func _effective_offscreen_sec(pool: ObjectPool, active: int) -> float:
	if pool != null and _pool_occupancy(pool, active) >= _pressure_offscreen_ratio:
		return minf(_offscreen_despawn_sec, _pressure_offscreen_sec)
	return _offscreen_despawn_sec


## 触顶时强制入账最远经验珠，腾出对象池槽位
func _force_collect_farthest_gems(count: int) -> int:
	if count <= 0 or _active_gems.is_empty() or _pool == null:
		return 0
	var origin: Vector2 = _player.global_position if _player != null else Vector2.ZERO
	var freed: int = 0
	while freed < count and not _active_gems.is_empty():
		var best_i: int = 0
		var best_d: float = -1.0
		for i in _active_gems.size():
			var d: float = _active_gems[i].global_position.distance_squared_to(origin)
			if d > best_d:
				best_d = d
				best_i = i
		_collect(_active_gems[best_i], best_i)
		freed += 1
	_log_pressure_relief("gem", freed, _active_gems.size())
	return freed


## 触顶时强制入账最远潮币，腾出对象池槽位
func _force_collect_farthest_coins(count: int) -> int:
	if count <= 0 or _active_coins.is_empty() or _coin_pool == null:
		return 0
	var origin: Vector2 = _player.global_position if _player != null else Vector2.ZERO
	var freed: int = 0
	while freed < count and not _active_coins.is_empty():
		var best_i: int = 0
		var best_d: float = -1.0
		for i in _active_coins.size():
			var d: float = _active_coins[i].global_position.distance_squared_to(origin)
			if d > best_d:
				best_d = d
				best_i = i
		_collect_coin(_active_coins[best_i], best_i)
		freed += 1
	_log_pressure_relief("coin", freed, _active_coins.size())
	return freed


## 腾槽入账限流日志（工程兜底，非常规收益）
func _log_pressure_relief(kind: String, freed: int, active_left: int) -> void:
	if freed <= 0:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _relief_log_msec < _RELIEF_LOG_INTERVAL_MSEC:
		return
	_relief_log_msec = now_msec
	print("[PickupSystem] 池压腾槽入账 kind=%s freed=%d active_left=%d（硬顶兜底）" % [kind, freed, active_left])


## 随机滚动品质（确定性 RNG，权重见 pickups.json）
func _roll_quality() -> ExpGem.Quality:
	var roll: float = RNG.randf_range(0.0, 100.0)
	var cumulative: float = 0.0
	for i in _quality_weights.size():
		cumulative += _quality_weights[i]
		if roll <= cumulative:
			return i as ExpGem.Quality
	return ExpGem.Quality.COMMON


## 收集经验珠
func _collect(gem: ExpGem, index: int) -> void:
	var value: int = gem.exp_value
	GameState.add_exp(value)
	exp_collected.emit(value)
	_active_gems.remove_at(index)
	_pool.release(gem)


## 屏外超时丢弃经验珠（不入账）
func _despawn_gem(gem: ExpGem, index: int) -> void:
	_active_gems.remove_at(index)
	if _pool != null:
		_pool.release(gem)


## 本帧显示区（测试注入 / 相机 / 无相机假想区）
func _compute_display_rect() -> Rect2:
	if _has_test_view:
		return _test_view_rect
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var view_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
		var center: Vector2 = cam.get_screen_center_position()
		return Rect2(center - view_size * 0.5, view_size)
	# headless / 无相机：以玩家为中心假想可视区
	if _player == null:
		return Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
	return Rect2(
		_player.global_position - _FALLBACK_VIEW_HALF,
		_FALLBACK_VIEW_HALF * 2.0
	)


## 查找最近潮币；找到时写入 out_pos[0] 并返回 true。
func try_nearest_coin_position(from: Vector2, out_pos: Array[Vector2], max_range: float = 2400.0) -> bool:
	var best_dist: float = max_range
	var best_pos: Vector2 = Vector2.ZERO
	var found: bool = false
	for coin in _active_coins:
		if not is_instance_valid(coin):
			continue
		var dist: float = from.distance_to(coin.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = coin.global_position
			found = true
	if not found:
		return false
	if out_pos.is_empty():
		out_pos.append(best_pos)
	else:
		out_pos[0] = best_pos
	return true
