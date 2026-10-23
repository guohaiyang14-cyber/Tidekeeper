# ============================================================================
# Projectile — 武器弹道（W5，鱼叉枪等定向弹幕使用）
# 职责：沿方向飞行；用 SpatialHash 查命中敌人造成伤害；穿透耗尽回收进池
# 红线：运行时禁止 instantiate（走 projectile_pool）；不走 Physics2D；随机走 RNG
# 注册：通过 "spatial_hash" group 查找 SpatialHashHolder
# ============================================================================
class_name Projectile
extends Node2D

# 显式预加载 EnemyBase，确保 headless 下 class_name 注册（命中检测类型依赖）
const _ENEMY_BASE = preload("res://scripts/core/enemy_base.gd")

@export var speed: float = 420.0
@export var hit_radius: float = 14.0

## 弹道最大存活时间（秒）：即使未命中/未出界也强制回收，防止对象池被持续发射的弹道占满
## （鱼叉枪每发 5+ 弹道，稀疏/速杀场景下未命中弹道会飞到 5000 单位边界才回收，
##   约 12s 寿命 → 32 容量池几秒内耗尽 → 武器停火 → 玩家无敌防御被秒杀）
const MAX_LIFE: float = 2.0

## 绘制层级：玩家弹道画在黑夜雾罩（VisionOverlay z=80）**之上**。
## 2026-10-23 用户反馈「跑一会整屏全黑什么都没有」+ 选择方案 B：
## 拾取物与玩家侧弹道/特效抬到雾上（暗处也能看见自己打出的弹道，战斗有反馈），
## **敌人本体与其弹道仍留在雾下**（黑暗压迫感保留）。
## 层级栈：雾罩 80 < 玩家弹道/特效/拾取物 81 < 灯塔塔身 82 < 散落光源 83 < 玩家 84
const _RENDER_Z := preload("res://scripts/core/render_z.gd")
const Z_ABOVE_FOG: int = _RENDER_Z.ABOVE_FOG

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 0
var _pierce: int = 0
var _slow_factor: float = 1.0
var _slow_duration: float = 0.0
var _source_id: String = ""
var _hash: SpatialHash
var _hit_set: Dictionary = {}  # 已命中敌人，去重
var _active: bool = false
var _life: float = 0.0

## ---- 视觉（weapons.json projectile_visual，数据驱动；缺省回退黄色圆弹）----
var _vis_shape: String = "orb"
var _vis_color: Color = Color(0.95, 0.9, 0.5)
var _vis_length: float = 14.0
var _vis_width: float = 8.0
var _vis_trail: float = 0.0
var _vis_loaded_for: String = ""  # 已加载视觉配置的武器 id（避免每发重复解析）


func _on_acquire() -> void:
	z_index = Z_ABOVE_FOG
	_active = true
	_life = 0.0
	_slow_factor = 1.0
	_slow_duration = 0.0
	_source_id = ""
	_hit_set.clear()
	_vis_loaded_for = ""
	_ensure_hash()


func _on_release() -> void:
	_active = false


func _ensure_hash() -> void:
	if _hash != null:
		return
	var holders: Array = get_tree().get_nodes_in_group("spatial_hash")
	if not holders.is_empty():
		var holder: SpatialHashHolder = holders[0] as SpatialHashHolder
		if holder != null:
			_hash = holder.get_hash()


## 发射配置（由武器调用）；slow_factor<1 且 duration>0 时命中施加减速
## source_id：武器 id（TestBot 伤害归因）
func launch(
	pos: Vector2,
	dir: Vector2,
	damage: int,
	pierce: int,
	slow_factor: float = 1.0,
	slow_duration: float = 0.0,
	source_id: String = ""
) -> void:
	global_position = pos
	_direction = dir.normalized()
	_damage = damage
	_pierce = pierce
	_slow_factor = slow_factor
	_slow_duration = slow_duration
	_source_id = source_id
	_life = MAX_LIFE
	rotation = _direction.angle()  # 朝向飞行方向（_draw 沿本地 +X 绘制）
	_configure_visual(source_id)
	if is_inside_tree():
		visible = true
		queue_redraw()


## 按武器 id 读取 projectile_visual 配置（shape=dart/orb、color、尺寸、拖尾）；
## 配置缺失回退默认黄弹。同一武器只解析一次（_vis_loaded_for 记忆）
func _configure_visual(weapon_id: String) -> void:
	if weapon_id == "" or weapon_id == _vis_loaded_for:
		return
	_vis_loaded_for = weapon_id
	var data: Dictionary = ConfigLoader.get_weapon(weapon_id)
	var vis: Variant = data.get("projectile_visual", null)
	if not (vis is Dictionary):
		return
	var d: Dictionary = vis as Dictionary
	_vis_shape = String(d.get("shape", "orb"))
	_vis_color = _parse_vis_color(String(d.get("color", "ffe08a")), _vis_color)
	_vis_length = float(d.get("length_px", 14.0))
	_vis_width = float(d.get("width_px", 8.0))
	_vis_trail = float(d.get("trail_px", 0.0))


func _parse_vis_color(hex: String, fallback: Color) -> Color:
	var s: String = hex.strip_edges()
	if not s.begins_with("#"):
		s = "#" + s
	return Color.from_string(s, fallback)


## 自定义弹道绘制：沿本地 +X（已由 launch 旋转到飞行方向）
## dart=修长鱼叉（头尖尾圆 + 拖尾）；orb=圆球 + 内核高光
func _draw() -> void:
	if not _active:
		return
	var col: Color = _vis_color
	var col_dark: Color = col.darkened(0.45)
	var col_hi: Color = col.lightened(0.4)
	# 拖尾：飞行反方向的渐隐细线
	if _vis_trail > 0.0:
		draw_line(Vector2.ZERO, Vector2(-_vis_trail, 0.0), Color(col.r, col.g, col.b, 0.32), maxf(1.0, _vis_width * 0.45))
	if _vis_shape == "dart":
		var hl: float = _vis_length * 0.5
		var hw: float = _vis_width * 0.5
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(hl, 0.0),              # 尖
			Vector2(hl * 0.15, -hw),
			Vector2(-hl * 0.55, -hw * 0.8),
			Vector2(-hl, -hw * 0.35),      # 尾左
			Vector2(-hl, hw * 0.35),       # 尾右
			Vector2(-hl * 0.55, hw * 0.8),
			Vector2(hl * 0.15, hw),
		])
		draw_colored_polygon(pts, col)
		var outline: PackedVector2Array = pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, col_dark, 1.0)
		# 脊线高光
		draw_line(Vector2(hl * 0.1, 0.0), Vector2(-hl * 0.75, 0.0), col_hi, maxf(1.0, hw * 0.3))
	else:
		var r: float = _vis_width * 0.5
		draw_circle(Vector2.ZERO, r, col)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, col_dark, 1.0)
		draw_circle(Vector2(-r * 0.3, -r * 0.3), maxf(0.8, r * 0.28), col_hi)


func _process(delta: float) -> void:
	if not _active:
		return
	_life -= delta
	if _life <= 0.0:
		_recycle()
		return
	global_position += _direction * speed * delta
	# 命中检测（所在格 + 邻格，SKILL §2.4）
	if _hash != null:
		var candidates: Array = _hash.query_radius(global_position, hit_radius)
		for node in candidates:
			if node is EnemyBase and not _hit_set.has(node):
				_hit_set[node] = true
				var enemy: EnemyBase = node as EnemyBase
				# 每次命中独立掷暴击（穿透多段各自判定，W12）
				enemy.take_damage(PassiveSystem.apply_crit_to_damage(_damage), false, false, _source_id)
				# 命中音效（冷却/并发上限见 config/audio.json，热路径下由 AudioManager 节流）
				AudioManager.play_sfx("hit")
				if _slow_duration > 0.0 and _slow_factor < 1.0:
					enemy.apply_slow(_slow_factor, _slow_duration)
				_pierce -= 1
				if _pierce < 0:
					_recycle()
					return
	# 越界回收（防止极端情况泄漏）
	if abs(global_position.x) > 5000.0 or abs(global_position.y) > 5000.0:
		_recycle()


func _recycle() -> void:
	var pool: ObjectPool = get_parent() as ObjectPool
	if pool != null:
		pool.release(self)
