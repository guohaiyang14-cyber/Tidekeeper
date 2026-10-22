# ============================================================================
# WeaponSpore — 水母孢子（召唤型，behavior_type=summon_jellyfish）
# 行为：以玩家为中心脉冲结算召唤物叮咬；优先打击最近的若干敌人。
# 数据：config/weapons.json spore（pulse_rate + behavior + summon）
# 可视化（2026-10-22）：真实召唤物实体（水母）环绕玩家漂浮，脉冲时朝目标叮刺；
#       伤害仍由本脉冲统一结算并归因 weapon_id（保持机检口径不变）。
# ============================================================================
class_name WeaponSpore
extends WeaponBase

const _SUMMON = preload("res://scripts/combat/summon_entity.gd")

var _summons: Array[SummonEntity] = []


func fire(_target: EnemyBase) -> void:
	var mgr: WeaponManager = get_parent() as WeaponManager
	if mgr == null:
		return
	var spatial_hash: SpatialHash = mgr.get_hash()
	if spatial_hash == null:
		return
	var origin: Vector2 = get_owner_pos.call()
	var base_r: float = get_behavior_float("base_radius", 120.0)
	var r_per: float = get_behavior_float("radius_per_level", 10.0)
	var radius: float = scale_area_radius(base_r + r_per * float(level - 1))
	var sting_count: int = get_behavior_int("base_targets", 3) + get_behavior_int("targets_per_level", 1) * (level - 1) + MetaSystem.get_extra_projectiles()
	var ranked: Array[EnemyBase] = query_nearest_enemies(spatial_hash, origin, radius, sting_count)
	# 视觉：召唤物编队跟随等级/弹道+1 伸缩；命中点叮刺特效（attack_fx.kind=sting）
	_sync_summons(sting_count)
	var sting_color: Color = get_behavior_color("sting_color", "8ff2e4")
	for e in ranked:
		e.take_damage(roll_hit_damage(), false, false, weapon_id)
		mgr.spawn_area_effect(e.global_position, 16.0, sting_color, get_attack_fx_kind("sting"))
	_cue_stings(ranked)


## 召唤物编队与 sting_count 对齐（增补/回收）；相位均匀错位
func _sync_summons(want: int) -> void:
	while _summons.size() > want:
		var extra: SummonEntity = _summons.pop_back()
		extra.queue_free()
	while _summons.size() < want:
		var cfg: Dictionary = _summon_cfg()
		if cfg.is_empty():
			return
		var idx: int = _summons.size()
		var angle: float = TAU * float(idx) / float(maxi(want, 1))
		var s: SummonEntity = _SUMMON.create(cfg, angle, get_owner_pos)
		add_child(s)
		_summons.append(s)
	# 相位按当前数量重排（数量变化后保持均匀间距，不随创建顺序漂移）
	var n: int = _summons.size()
	for i in n:
		_summons[i].set_phase(TAU * float(i) / float(maxi(n, 1)))


## 前 want 只召唤物依次朝 ranked 目标叮刺（视觉动作；不足时轮流）
func _cue_stings(ranked: Array[EnemyBase]) -> void:
	if ranked.is_empty():
		return
	for i in _summons.size():
		var e: EnemyBase = ranked[i % ranked.size()]
		if e != null and is_instance_valid(e):
			_summons[i].sting_at(e.global_position)


func _summon_cfg() -> Dictionary:
	var cfg: Variant = weapon_data.get("summon", null)
	return cfg as Dictionary if cfg is Dictionary else {}
