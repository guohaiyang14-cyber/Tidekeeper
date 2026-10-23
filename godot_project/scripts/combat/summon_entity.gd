# ============================================================================
# SummonEntity — 武器召唤物实体（2026-10-22 召唤类武器可视化）
# 行为：跟随玩家做环绕巡航；脉冲指令到时执行「动作」——
#   orbit_sting（水母孢子）：朝目标短刺（lunge + 缩放脉冲）
#   dive（信天翁）：朝目标俯冲、命中扬尘、归位
# 红线：纯视觉+动作编排，不参与任何伤害/索敌（伤害仍由武器脉冲结算并归因 weapon_id）；
#       挂武器实例下（queue_free 武器即全部回收）；运行时用 .new() 程序化构建，
#       不走场景 instantiate（与武器实例同策略）。
# 数据：config/weapons.json <weapon>.summon（sprite/mode/orbit_*/dive_speed/scale）
# ============================================================================
class_name SummonEntity
extends Node2D

## 绘制层级：玩家侧攻击单位画在黑夜雾罩（VisionOverlay z=80）**之上**
## 层级栈：雾罩 80 < 玩家弹道/特效/召唤物/拾取物 81 < 灯塔塔身 82 < 散落光源 83 < 玩家 84
const _RENDER_Z := preload("res://scripts/core/render_z.gd")
const Z_ABOVE_FOG: int = _RENDER_Z.ABOVE_FOG

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")

## 俯冲状态机
const STATE_ORBIT: int = 0
const STATE_DIVING: int = 1
const STATE_RETURN: int = 2

@onready var _sprite: Sprite2D = $Sprite2D

var _mode: String = "orbit_sting"
var _orbit_radius: float = 70.0
var _orbit_speed: float = 1.6
var _bob_amp: float = 6.0
var _dive_speed: float = 620.0
var _scale: float = 1.0

## 注入（由武器 setup）：玩家位置
var _get_owner_pos: Callable = Callable()

var _angle: float = 0.0          # 环绕相位（编队错位用）
var _state: int = STATE_ORBIT
var _dive_target: Vector2 = Vector2.ZERO
var _lunge_t: float = -1.0       # >=0 表示刺击动作进行中（0→1）
var _lunge_from: Vector2 = Vector2.ZERO
var _lunge_to: Vector2 = Vector2.ZERO
var _tween: Tween = null


func _ready() -> void:
	if _sprite != null:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.scale = Vector2(_scale, _scale)


## 配置（ weapons.json summon 块；angle_offset 为编队相位 ）
func setup(cfg: Dictionary, angle_offset: float, get_owner_pos: Callable) -> void:
	_mode = String(cfg.get("mode", "orbit_sting"))
	_orbit_radius = float(cfg.get("orbit_radius", 70.0))
	_orbit_speed = float(cfg.get("orbit_speed", 1.6))
	_bob_amp = float(cfg.get("bob_amplitude", 6.0))
	_dive_speed = float(cfg.get("dive_speed", 620.0))
	_scale = float(cfg.get("scale", 1.0))
	_angle = angle_offset
	_get_owner_pos = get_owner_pos
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite != null:
		_sprite.texture = _SPRITE_LIB.summon(String(cfg.get("sprite", "")))
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.scale = Vector2(_scale, _scale)


## 编队相位（环绕角）；武器在数量变化时重排，保持均匀间距
func set_phase(angle: float) -> void:
	_angle = angle


func _process(delta: float) -> void:
	var owner_pos: Vector2 = _call_owner_pos()
	match _state:
		STATE_ORBIT:
			_orbit(delta, owner_pos)
		STATE_DIVING:
			_dive_step(delta, owner_pos)
		STATE_RETURN:
			_return_step(delta, owner_pos)
	# 刺击动作（水母）：在巡航位置上叠加短距插值
	if _lunge_t >= 0.0:
		_lunge_t += delta / 0.18
		if _lunge_t >= 1.0:
			_lunge_t = -1.0
			position = _lunge_from
		else:
			# 去回（0→0.5 刺出，0.5→1 收回）
			var k: float = _lunge_t if _lunge_t < 0.5 else 1.0 - (_lunge_t - 0.5) * 2.0
			position = _lunge_from.lerp(_lunge_to, k * 0.55)


func _call_owner_pos() -> Vector2:
	if _get_owner_pos.is_valid():
		var p: Variant = _get_owner_pos.call()
		if p is Vector2:
			return p as Vector2
	return Vector2.ZERO


## 环绕巡航（水母纵向压扁 + 上下浮沉；信天翁正圆 + 倾角）
func _orbit(delta: float, owner_pos: Vector2) -> void:
	_angle += delta * _orbit_speed
	var squash: float = 0.62 if _mode == "orbit_sting" else 1.0
	var bob: float = sin(_angle * 2.3) * _bob_amp if _mode == "orbit_sting" else 0.0
	var offset: Vector2 = Vector2(cos(_angle), sin(_angle) * squash) * _orbit_radius
	position = owner_pos + offset + Vector2(0.0, bob)
	if _mode == "dive":
		# 盘旋时机头朝切线方向
		var tangent: Vector2 = Vector2(-sin(_angle), cos(_angle) * squash)
		rotation = tangent.angle()
	else:
		rotation = 0.0


## 俯冲（信天翁动作指令）：锁定目标点，飞去 → 扬尘 → 归位
func dive_at(target_pos: Vector2) -> void:
	if _state != STATE_ORBIT:
		return
	_dive_target = target_pos
	_state = STATE_DIVING


func _dive_step(delta: float, owner_pos: Vector2) -> void:
	var to_target: Vector2 = _dive_target - position
	var dist: float = to_target.length()
	if dist <= 10.0:
		# 命中扬尘：缩放脉冲后进入返回
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_sprite, "scale", Vector2(_scale * 1.35, _scale * 1.35), 0.08)
		_tween.tween_property(_sprite, "scale", Vector2(_scale, _scale), 0.12)
		_state = STATE_RETURN
		return
	var step: Vector2 = to_target / dist * (_dive_speed * delta)
	position += step
	rotation = to_target.angle()


## 返回巡航锚点（跟随玩家实时位置）
func _return_step(delta: float, owner_pos: Vector2) -> void:
	var squash: float = 0.62 if _mode == "orbit_sting" else 1.0
	var anchor: Vector2 = owner_pos + Vector2(cos(_angle), sin(_angle) * squash) * _orbit_radius
	var to_anchor: Vector2 = anchor - position
	var dist: float = to_anchor.length()
	if dist <= 14.0:
		_state = STATE_ORBIT
		position = anchor
		return
	position += to_anchor / dist * (_dive_speed * 0.8 * delta)
	rotation = to_anchor.angle()


## 叮刺（水母动作指令）：朝目标短距刺出并收回（纯视觉）
func sting_at(target_pos: Vector2) -> void:
	if _state != STATE_ORBIT or _lunge_t >= 0.0:
		return
	_lunge_from = position
	var dir: Vector2 = (target_pos - position).normalized()
	_lunge_to = position + dir * minf(26.0, position.distance_to(target_pos) * 0.5)
	_lunge_t = 0.0
	# 触手伸缩：Y 轴轻微拉伸脉冲
	if _sprite != null:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_sprite, "scale", Vector2(_scale * 0.85, _scale * 1.2), 0.07)
		_tween.tween_property(_sprite, "scale", Vector2(_scale, _scale), 0.11)


## 机检/调试：当前状态
func get_state() -> int:
	return _state


## 机检/调试：是否处于巡航
func is_orbiting() -> bool:
	return _state == STATE_ORBIT


## 工厂：程序化构建一个召唤物（Sprite2D 子节点 + setup），供武器挂载
static func create(cfg: Dictionary, angle_offset: float, get_owner_pos: Callable) -> SummonEntity:
	var e := SummonEntity.new()
	# 召唤物属于玩家侧攻击单位：抬到黑夜雾罩（VisionOverlay z=80）之上，
	# 暗处也能看见信天翁/孢子等同伴（2026-10-23 用户选方案 B，与弹道/特效同层）
	e.z_index = Z_ABOVE_FOG
	var sp := Sprite2D.new()
	sp.name = "Sprite2D"
	e.add_child(sp)
	e.setup(cfg, angle_offset, get_owner_pos)
	return e
