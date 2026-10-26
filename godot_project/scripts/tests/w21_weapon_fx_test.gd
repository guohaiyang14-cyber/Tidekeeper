# ============================================================================
# W21WeaponFxTest — 武器视觉/动作机检（2026-10-22 召唤物与弹道可视化）
# 验收项：
#   V1 配置完备：每把武器有 attack_fx.kind；弹幕武器有 projectile_visual；
#      召唤武器有 summon 块且召唤精灵在盘上；series 配色覆盖全部武器/被动
#   V2 弹道视觉：harpoon→dart、jellyfish_cannon→orb（形状/颜色按 config 解析）
#   V3 攻击动作特效：七种 kind 均可播放并自动归还（bolt 带 height 参数）
#   V4 召唤物实体：spore 编队数量=base_targets；水母环绕巡航；信天翁俯冲状态机
#      ORBIT→DIVING→RETURN→ORBIT；叮刺动作触发
#   V5 锚链持久环绕视觉：跟随玩家 + tick 脉冲衰减
#   V6 HUD 槽位：series 色条/系色文字/召唤型图标进入呼吸列表
# 红线：仅走对象池；不 instantiate；断言不依赖真实渲染输出
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w21_weapon_fx_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node2D

const _WEAPON_MANAGER = preload("res://scripts/combat/weapon_manager.gd")
const _SPATIAL_HASH_HOLDER = preload("res://scripts/core/spatial_hash_holder.gd")
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")
const _SUMMON = preload("res://scripts/combat/summon_entity.gd")
const _ORBIT_VIS = preload("res://scripts/combat/orbit_chain_visual.gd")
const _HUD = preload("res://scripts/core/hud.gd")
const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")

const _KNOWN_FX_KINDS: Array[String] = ["ring", "bolt", "slam", "muzzle", "sting", "dive", "burst", "orbit", "deflect"]

@onready var spatial_hash_holder: SpatialHashHolder = $SpatialHashHolder
@onready var player: Node2D = $Player
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var projectile_pool: ProjectilePool = $ProjectilePool
@onready var particle_pool: ObjectPool = $ParticlePool
@onready var enemy_pool: EnemyPool = $EnemyPool

var _pass_count: int = 0
var _fail_count: int = 0
var _fail_msgs: Array[String] = []


func _ready() -> void:
	if not ConfigLoader.is_loaded:
		push_error("[W21WeaponFxTest] ConfigLoader 未加载，无法运行")
		get_tree().quit(1)
		return
	spatial_hash_holder.add_to_group("spatial_hash")
	weapon_manager.setup(player, spatial_hash_holder.get_hash(), projectile_pool, particle_pool)
	await _run_all()
	_finish()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		_fail_msgs.append(label)
		print("[FAIL] %s" % label)


func _simulate(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _setup_weapon(id: String) -> void:
	GameState.start_new_run("watcher")
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	enemy_pool.release_all()
	projectile_pool.release_all()
	particle_pool.release_all()
	spatial_hash_holder.get_hash().clear()
	GameState.add_weapon(id)
	weapon_manager.sync_from_game_state()


func _weapon_of(id: String) -> WeaponBase:
	for w in weapon_manager.get_weapons():
		if w.weapon_id == id:
			return w
	return null


func _finish() -> void:
	print("============================================================")
	print("W21 武器视觉/动作 机检完成: PASS=%d FAIL=%d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		for m in _fail_msgs:
			print("  [FAIL] %s" % m)
	print("============================================================")
	get_tree().quit(1 if _fail_count > 0 else 0)


func _run_all() -> void:
	await _test_config_completeness()
	await _test_projectile_visuals()
	await _test_fx_kinds()
	await _test_summon_entities()
	await _test_orbit_chain_visual()
	await _test_hud_series_ui()


# ---- V1 配置完备性 ----------------------------------------------------------
func _test_config_completeness() -> void:
	print("[assert] V1 配置完备性")
	var weapon_ids: Array = ConfigLoader.get_all_weapon_ids()
	_assert(weapon_ids.size() == 8, "武器共 8 把 (实际 %d)" % weapon_ids.size())
	var series_colors: Dictionary = (ConfigLoader.get_ui_skin_config().get("series_colors", {}) as Dictionary)
	for wid in weapon_ids:
		var d: Dictionary = ConfigLoader.get_weapon(String(wid))
		var fx: Variant = d.get("attack_fx", null)
		_assert(fx is Dictionary and String((fx as Dictionary).get("kind", "")) != "",
			"%s 有 attack_fx.kind" % wid)
		if fx is Dictionary:
			_assert(_KNOWN_FX_KINDS.has(String((fx as Dictionary).get("kind", ""))),
				"%s attack_fx.kind 已知 (%s)" % [wid, (fx as Dictionary).get("kind", "")])
		# 弹幕武器必须有弹道视觉
		var beh: Dictionary = d.get("behavior", {}) as Dictionary
		var btype: String = String(d.get("behavior_type", ""))
		if btype == "directional_pierce" or btype == "ring_barrage":
			var pv: Variant = d.get("projectile_visual", null)
			_assert(pv is Dictionary, "%s 有 projectile_visual" % wid)
			if pv is Dictionary:
				var shape: String = String((pv as Dictionary).get("shape", ""))
				_assert(shape == "dart" or shape == "orb", "%s 弹道形状 dart/orb (%s)" % [wid, shape])
				_assert(String((pv as Dictionary).get("color", "")) != "", "%s 弹道有颜色" % wid)
		# 召唤武器必须有 summon 块且精灵在盘上
		if btype.begins_with("summon_"):
			var sm: Variant = d.get("summon", null)
			_assert(sm is Dictionary, "%s 有 summon 块" % wid)
			if sm is Dictionary:
				var sprite_id: String = String((sm as Dictionary).get("sprite", ""))
				_assert(_SPRITE_LIB.has_sprite("summons", sprite_id),
					"%s 召唤精灵存在 (summons/%s.png)" % [wid, sprite_id])
				var mode: String = String((sm as Dictionary).get("mode", ""))
				_assert(mode == "orbit_sting" or mode == "dive", "%s 召唤模式已知 (%s)" % [wid, mode])
		# 进化系配色覆盖
		var evo: Variant = d.get("evolution", null)
		if evo is Dictionary:
			var series: String = String((evo as Dictionary).get("passive_series", ""))
			if series != "":
				_assert(series_colors.has(series), "武器 %s 系「%s」有配色" % [wid, series])
	# 被动系配色覆盖
	for pid in ConfigLoader.get_all_passive_ids():
		var pd: Dictionary = ConfigLoader.get_passive(pid)
		var ps: String = String(pd.get("series", ""))
		if ps != "":
			_assert(series_colors.has(ps), "被动 %s 系「%s」有配色" % [pid, ps])


# ---- V2 弹道视觉 ------------------------------------------------------------
func _test_projectile_visuals() -> void:
	print("[assert] V2 弹道视觉（per-weapon）")
	# 确定性部分：直接 launch 校验视觉配置解析（不受开火时序影响）
	for wid in ["harpoon", "jellyfish_cannon"]:
		var pv: Dictionary = ConfigLoader.get_weapon(wid).get("projectile_visual", {}) as Dictionary
		var probe: Projectile = projectile_pool.acquire() as Projectile
		_assert(probe != null, "%s 弹道可从池获取" % wid)
		if probe != null:
			probe.launch(player.global_position, Vector2.RIGHT, 5, 1, 1.0, 0.0, wid)
			var want_shape: String = String(pv.get("shape", ""))
			_assert(probe._vis_shape == want_shape,
				"%s 弹道形状=%s (实际 %s)" % [wid, want_shape, probe._vis_shape])
			var hex: String = String(pv.get("color", ""))
			var want: Color = Color.from_string("#" + hex, Color.MAGENTA)
			_assert(probe._vis_color.is_equal_approx(want), "%s 弹道颜色=#%s" % [wid, hex])
			_assert(absf(probe.rotation - Vector2.RIGHT.angle()) < 0.01, "%s 弹道朝向飞行方向" % wid)
			projectile_pool.release(probe)
	# 集成部分：真实开火逐帧捕获（敌距 500px，避免贴脸被瞬间回收）
	for wid in ["harpoon", "jellyfish_cannon"]:
		_setup_weapon(wid)
		var e: EnemyBase = enemy_pool.acquire() as EnemyBase
		e.spawn_at(player.global_position + Vector2(500, 0), player)
		var found: Projectile = null
		for _i in 150:
			await get_tree().process_frame
			for p in projectile_pool.get_active():
				found = p as Projectile
				break
			if found != null:
				break
		_assert(found != null, "%s 发射了弹道" % wid)
		if found != null:
			var want_shape2: String = String((ConfigLoader.get_weapon(wid).get("projectile_visual", {}) as Dictionary).get("shape", ""))
			_assert(found._vis_shape == want_shape2,
				"%s 实弹形状=%s (实际 %s)" % [wid, want_shape2, found._vis_shape])
		if e != null and enemy_pool.get_active().find(e) != -1:
			enemy_pool.release(e)


# ---- V3 攻击动作特效连播 -----------------------------------------------------
func _test_fx_kinds() -> void:
	print("[assert] V3 攻击动作特效（八 kind，含 deflect 近战清弹火花）")
	particle_pool.release_all()  # 清场，确保 active 里只有本次特效
	for kind in ["ring", "bolt", "slam", "muzzle", "sting", "dive", "burst", "deflect"]:
		var before: int = particle_pool.active_count()
		weapon_manager.spawn_area_effect(player.global_position, 60.0, Color(0.5, 0.8, 1.0),
			kind, Vector2.RIGHT, {"height": 200.0})
		_assert(particle_pool.active_count() == before + 1, "特效 %s acquire +1" % kind)
		await get_tree().process_frame
		# 按 kind 匹配查找（池中可能还有上一个尚未归池的特效）
		var fx: Node = null
		for a in particle_pool.get_active():
			if a.get("_kind") == kind:
				fx = a
				break
		if fx != null:
			_assert(fx.get("_kind") == kind, "特效 kind=%s 生效" % kind)
		var lifetime: float = ConfigLoader.get_area_effect_lifetime()
		var wait: int = int(ceil(lifetime * 60.0)) + 12
		var released: bool = false
		for _i in wait:
			await get_tree().process_frame
			if particle_pool.active_count() == before:
				released = true
				break
		_assert(released, "特效 %s 播完归还池" % kind)


# ---- V4 召唤物实体 -----------------------------------------------------------
func _test_summon_entities() -> void:
	print("[assert] V4 召唤物实体")
	# 水母：编队数量 + 环绕巡航
	_setup_weapon("spore")
	var e1: EnemyBase = enemy_pool.acquire() as EnemyBase
	e1.spawn_at(player.global_position + Vector2(40, 20), player)
	await _simulate(90)
	var spore: WeaponSpore = _weapon_of("spore") as WeaponSpore
	_assert(spore != null, "spore 武器实例存在")
	if spore != null:
		var want: int = spore.get_behavior_int("base_targets", 3)
		_assert(spore._summons.size() == want,
			"水母编队数量=base_targets (%d, 实际 %d)" % [want, spore._summons.size()])
		if spore._summons.size() > 0:
			var s0: SummonEntity = spore._summons[0]
			var p_before: Vector2 = s0.position
			await _simulate(30)
			var moved: float = s0.position.distance_to(p_before)
			_assert(moved > 1.0, "水母环绕巡航中 (30 帧移动 %.1f)" % moved)
			# 环绕半径合理（相对玩家）
			var dist: float = s0.global_position.distance_to(player.global_position)
			var orbit_r: float = float((spore.weapon_data.get("summon", {}) as Dictionary).get("orbit_radius", 70.0))
			_assert(dist > orbit_r * 0.4 and dist < orbit_r * 1.8,
				"水母环绕半径合理 (d=%.0f, r=%.0f)" % [dist, orbit_r])
			# 叮刺动作触发
			s0.sting_at(player.global_position + Vector2(200, 0))
			_assert(s0._lunge_t >= 0.0, "水母叮刺动作触发")
	# 信天翁：俯冲状态机
	_setup_weapon("albatross")
	var e2: EnemyBase = enemy_pool.acquire() as EnemyBase
	e2.spawn_at(player.global_position + Vector2(100, 0), player)
	await _simulate(120)
	var alb: WeaponAlbatross = _weapon_of("albatross") as WeaponAlbatross
	_assert(alb != null, "albatross 武器实例存在")
	if alb != null and alb._summons.size() > 0:
		var a0: SummonEntity = alb._summons[0]
		# 武器会自动俯冲索敌，先等一个巡航窗口再手动驱离（避免与自动俯冲竞争）
		var settled: bool = false
		for _i in 240:
			await get_tree().process_frame
			if a0.is_orbiting():
				settled = true
				break
		_assert(settled, "信天翁归位巡航")
		a0.dive_at(player.global_position + Vector2(150, 60))
		_assert(a0.get_state() == 1, "信天翁接收俯冲指令 (DIVING)")
		var back: bool = false
		for _i in 240:
			await get_tree().process_frame
			if a0.is_orbiting():
				back = true
				break
		_assert(back, "信天翁俯冲后归位巡航")
	# 单元：SummonEntity 独立构建（dive 模式状态机全链）
	var cfg: Dictionary = {"mode": "dive", "sprite": "albatross", "orbit_radius": 80.0,
		"orbit_speed": 2.0, "dive_speed": 800.0, "scale": 1.0}
	var unit: SummonEntity = _SUMMON.create(cfg, 0.0,
		func(): return player.global_position)
	add_child(unit)
	await _simulate(5)
	_assert(unit.is_orbiting(), "独立召唤物初始巡航")
	unit.dive_at(player.global_position + Vector2(90, 30))
	var back2: bool = false
	for _i in 240:
		await get_tree().process_frame
		if unit.is_orbiting():
			back2 = true
			break
	_assert(back2, "独立召唤物俯冲归位")
	unit.queue_free()
	if e1 != null and enemy_pool.get_active().find(e1) != -1:
		enemy_pool.release(e1)
	if e2 != null and enemy_pool.get_active().find(e2) != -1:
		enemy_pool.release(e2)


# ---- V5 锚链持久环绕视觉 -------------------------------------------------------
func _test_orbit_chain_visual() -> void:
	print("[assert] V5 锚链环绕视觉")
	_setup_weapon("anchor_chain")
	var e: EnemyBase = enemy_pool.acquire() as EnemyBase
	e.spawn_at(player.global_position + Vector2(30, 0), player)
	await _simulate(90)
	var chain: WeaponAnchorChain = _weapon_of("anchor_chain") as WeaponAnchorChain
	_assert(chain != null, "anchor_chain 武器实例存在")
	if chain != null:
		_assert(chain._orbit_vis != null and is_instance_valid(chain._orbit_vis),
			"锚链环绕视觉已创建")
		if chain._orbit_vis != null:
			var d: float = chain._orbit_vis.global_position.distance_to(player.global_position)
			_assert(d < 1.0, "环绕视觉跟随玩家 (d=%.2f)" % d)
			chain._orbit_vis.pulse()
			_assert(chain._orbit_vis._flash > 0.5, "tick 脉冲提亮")
	# 脉冲衰减：独立视觉验证（避免武器 tick 在此期间再次提亮）
	var unit: OrbitChainVisual = _ORBIT_VIS.create(func(): return player.global_position)
	add_child(unit)
	unit.pulse()
	_assert(unit._flash > 0.5, "独立视觉脉冲提亮")
	await _simulate(30)
	_assert(unit._flash <= 0.5, "独立视觉脉冲衰减 (%.2f)" % unit._flash)
	unit.queue_free()
	if e != null and enemy_pool.get_active().find(e) != -1:
		enemy_pool.release(e)


# ---- V6 HUD 槽位系色 UI -------------------------------------------------------
func _test_hud_series_ui() -> void:
	print("[assert] V6 HUD 槽位系色 UI")
	GameState.start_new_run("watcher")
	GameState.weapon_slots.clear()
	GameState.weapon_levels.clear()
	GameState.add_weapon("harpoon")
	GameState.add_weapon("spore")
	GameState.add_passive("pearl")
	weapon_manager.sync_from_game_state()
	var hud: Control = _HUD.new()
	$HudHost.add_child(hud)
	hud.init(weapon_manager)
	_assert(hud._weapon_box.get_child_count() >= 2, "武器槽 >= 2")
	# harpoon（潮汐系）图标应带 series 色条
	var found_strip: bool = false
	var summon_pulsed: bool = false
	for ic in hud._weapon_box.get_children():
		if ic is TextureRect:
			for sub in ic.get_children():
				if sub is ColorRect:
					found_strip = true
			if hud._summon_icons.has(ic):
				summon_pulsed = true
	_assert(found_strip, "武器图标有 series 色条")
	_assert(summon_pulsed, "召唤型武器（spore）进入呼吸动画列表")
	# 系色文字：harpoon（潮汐 4fc3f7）与纯白不同
	var lbl: Label = null
	for c in hud._weapon_box.get_children():
		if c is Label and (c as Label).text.contains("鱼叉"):
			lbl = c as Label
			break
	_assert(lbl != null, "找到鱼叉槽文字")
	if lbl != null:
		var col: Color = lbl.get_theme_color("font_color")
		_assert(not col.is_equal_approx(Color(1, 1, 1)), "槽文字使用系色 (非纯白)")
	# 被动槽 pearl（夜风系）也有色条
	var passive_strip: bool = false
	for ic in hud._passive_box.get_children():
		if ic is TextureRect and ic.get_child_count() > 0:
			passive_strip = true
	_assert(passive_strip, "被动图标有 series 色条")
	hud.queue_free()
