# ============================================================================
# WeaponEffect — 武器打击特效（池化，由 WeaponManager.spawn_area_effect 取用）
# 行为：在获取位置播放一次「扩散 + 淡出」的打击圈（实心 Disc + 描边 Ring），
#       颜色/半径由调用方传入；动画结束自行归还对象池（不依赖外部信号，避免泄漏）。
# 用途：给 area_burn / area_lightning / melee_burst 等无可见弹道的武器补视觉反馈，
#       让玩家能「看到」它们在开火（修复「买了 4 武器只看到鱼叉子弹」的视觉缺失）。
# 红线：纯视觉、不参与任何伤害/索敌；走 ParticlePool（禁止运行时 instantiate）。
# ============================================================================
class_name WeaponEffect
extends Node2D

@onready var _disc: Polygon2D = $Disc
@onready var _ring: Line2D = $Ring

var _tween: Tween = null
var _pool: ObjectPool = null


func _ready() -> void:
	_build_shapes()


## 以单位圆（半径 1）为底构建 Disc 多边形与 Ring 描边点；运行时按 radius 缩放
func _build_shapes() -> void:
	var seg: int = 30
	var pts: PackedVector2Array = []
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a), sin(a)))
	_disc.polygon = pts
	var ring_pts: PackedVector2Array = pts.duplicate()
	ring_pts.append(pts[0])  # 闭合
	_ring.points = ring_pts


## 池化复用复位：杀掉残留 tween、复位缩放/透明度（对象池 acquire 时调用）
func _on_acquire() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_pool = null
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	visible = true


## 对象池 release 时杀掉 tween，避免 release_all 后回调二次 release
func _on_release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_pool = null


## 播放一次打击特效；结束自行归还对象池
func play(radius: float, color: Color, lifetime: float, pool: ObjectPool) -> void:
	_pool = pool
	_disc.scale = Vector2.ONE * radius
	_ring.scale = Vector2.ONE * radius
	_disc.color = Color(color.r, color.g, color.b, 0.32)
	_ring.default_color = color.lightened(0.2)
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 升级/商店暂停时仍能播完并归还池
	_tween.tween_property(self, "scale", Vector2.ONE * 1.18, lifetime).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
	# chain()：等并行动画结束后再归还池（勿与 set_parallel(true) 同组，否则回调 t=0 立即 release）
	_tween.chain().tween_callback(func():
		if _pool != null and is_instance_valid(_pool):
			_pool.release(self)
	)
