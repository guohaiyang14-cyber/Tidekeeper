# ============================================================================
# WeaponEffect — 武器攻击动作特效（池化，由 WeaponManager.spawn_area_effect 取用）
# 行为：按 kind 播放一次性攻击动作，结束自行归还对象池（不依赖外部信号）。
#   ring   灼烧火圈（圣火）：扩散实心盘 + 内焰跳动 + 外环
#   bolt   落雷（雷暴云）：顶部锯齿闪点 + 折线雷弧 + 地面冲击圈
#   slam   锤击（锚锤）：冲击环 + 朝 dir 扫出的两道挥击弧
#   muzzle 枪口火光（鱼叉）：沿 dir 的锥形闪光 + 小环
#   sting  叮刺（水母孢子）：命中点针刺 + 麻痹圈
#   dive   俯冲扬尘（信天翁）：冲击环 + 羽毛碎屑
# 红线：纯视觉、不参与任何伤害/索敌；走 ParticlePool（禁止运行时 instantiate）；
#       视觉抖动用本地 RNG 实例（不得消耗游戏 RNG，保持局内确定性）。
# ============================================================================
class_name WeaponEffect
extends Node2D

var _tween: Tween = null
var _pool: ObjectPool = null

## 播放参数（play() 注入）
var _kind: String = "ring"
var _radius: float = 40.0
var _color: Color = Color.WHITE
var _life: float = 0.35
var _dir: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _bolt_pts: PackedVector2Array = PackedVector2Array()  # bolt 预生成折线（本地 RNG）
var _rng: RandomNumberGenerator = null


func _on_acquire() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_pool = null
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	visible = true
	_age = 0.0


## 对象池 release 时杀掉 tween，避免 release_all 后回调二次 release
func _on_release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_pool = null


## 播放一次攻击动作；结束自行归还对象池
## kind: ring/bolt/slam/muzzle/sting/dive（缺省 ring，向后兼容旧 4 参调用）
## dir: 动作朝向（muzzle/slam 用；弹道类特效忽略）
## params: bolt 可传 {"height": 260.0}
func play(radius: float, color: Color, lifetime: float, pool: ObjectPool,
		kind: String = "ring", dir: Vector2 = Vector2.RIGHT, params: Dictionary = {}) -> void:
	_pool = pool
	_kind = kind
	_radius = maxf(6.0, radius)
	_color = color
	_life = maxf(0.05, lifetime)
	_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_age = 0.0
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	# bolt 折线按竖直方向生成（自顶向下落），固定不旋转；
	# 其余 kind 的本地 +X 对齐动作朝向（muzzle/slam 依赖 dir，ring/sting/dive/burst 对称）
	rotation = 0.0 if _kind == "bolt" else _dir.angle()
	# bolt：预生成锯齿折线（从顶部落到地面），每段横向抖动
	if _kind == "bolt":
		var h: float = float(params.get("height", 260.0))
		var segs: int = 7
		_bolt_pts = PackedVector2Array()
		for i in segs + 1:
			var t: float = float(i) / float(segs)
			var x: float = 0.0 if i == 0 or i == segs else _rng.randf_range(-14.0, 14.0) * (1.0 - t * 0.5)
			_bolt_pts.append(Vector2(x, -h * (1.0 - t)))
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# 升级/商店暂停时仍能播完并归还池
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 0.0, _life).set_ease(Tween.EASE_IN)
	# chain()：等淡出结束后再归还池（勿与 set_parallel(true) 同组，否则回调 t=0 立即 release）
	_tween.chain().tween_callback(func():
		if _pool != null and is_instance_valid(_pool):
			_pool.release(self)
	)


func _process(delta: float) -> void:
	if _tween == null:
		return
	_age += delta
	queue_redraw()


func _progress() -> float:
	return clampf(_age / _life, 0.0, 1.0)


func _draw() -> void:
	if _tween == null:
		return
	var t: float = _progress()
	var col: Color = _color
	var col_hi: Color = col.lightened(0.45)
	var col_dark: Color = col.darkened(0.35)
	match _kind:
		"bolt":
			_draw_bolt(t, col, col_hi)
		"slam":
			_draw_slam(t, col, col_hi, col_dark)
		"muzzle":
			_draw_muzzle(t, col, col_hi)
		"sting":
			_draw_sting(t, col, col_hi)
		"dive":
			_draw_dive(t, col, col_hi)
		"burst":
			_draw_burst(t, col, col_hi)
		_:
			_draw_ring(t, col, col_hi, col_dark)


## ring：扩散实心盘 + 内焰跳动 + 外环
func _draw_ring(t: float, col: Color, col_hi: Color, col_dark: Color) -> void:
	var r: float = _radius * (0.45 + 0.75 * t)
	var alpha: float = 1.0 - t
	draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, 0.30 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(col_hi.r, col_hi.g, col_hi.b, 0.9 * alpha), 3.0)
	# 内焰：三瓣跳动小三角（角度随进度旋转）
	var flick: float = sin(t * 18.0) * 0.5 + 0.5
	for i in 3:
		var a: float = t * 3.0 + TAU * float(i) / 3.0
		var d: float = r * (0.45 + 0.3 * flick)
		var tip: Vector2 = Vector2(cos(a), sin(a)) * d
		var base_a1: float = a + 0.35
		var base_a2: float = a - 0.35
		var p1: Vector2 = Vector2(cos(base_a1), sin(base_a1)) * (r * 0.3)
		var p2: Vector2 = Vector2(cos(base_a2), sin(base_a2)) * (r * 0.3)
		draw_colored_polygon(PackedVector2Array([tip, p1, p2]), Color(col_hi.r, col_hi.g, col_hi.b, 0.5 * alpha))
	draw_arc(Vector2.ZERO, _radius * 0.28, 0.0, TAU, 20, Color(col_dark.r, col_dark.g, col_dark.b, 0.6 * alpha), 2.0)


## bolt：锯齿折线雷弧（自顶部）+ 地面冲击圈 + 分叉
func _draw_bolt(t: float, col: Color, col_hi: Color) -> void:
	var alpha: float = 1.0 - t * 0.85
	if _bolt_pts.size() >= 2:
		# 前 40% 时间雷弧「生长」：只画到 progress 对应的段
		var grow: float = clampf(t / 0.4, 0.0, 1.0)
		var n: int = maxi(2, int(ceil(float(_bolt_pts.size() - 1) * grow)) + 1)
		var pts: PackedVector2Array = _bolt_pts.slice(0, mini(n, _bolt_pts.size()))
		draw_polyline(pts, Color(col_hi.r, col_hi.g, col_hi.b, alpha), 3.5)
		draw_polyline(pts, Color(col.r, col.g, col.b, alpha * 0.7), 6.0)
		# 分叉：从中点斜出一小段
		if pts.size() >= 4:
			var mid: Vector2 = pts[pts.size() / 2]
			var fork_end: Vector2 = mid + Vector2(16.0 if mid.x >= 0.0 else -16.0, 18.0)
			draw_line(mid, fork_end, Color(col_hi.r, col_hi.g, col_hi.b, alpha * 0.8), 2.0)
	# 顶部闪点
	if _bolt_pts.size() > 0:
		draw_circle(_bolt_pts[0], 5.0 + 4.0 * (1.0 - t), Color(col_hi.r, col_hi.g, col_hi.b, alpha))
	# 地面冲击圈
	var r: float = _radius * (0.5 + 0.6 * t)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(col_hi.r, col_hi.g, col_hi.b, 0.85 * alpha), 3.0)
	draw_circle(Vector2.ZERO, r * 0.55, Color(col.r, col.g, col.b, 0.25 * alpha))


## slam：冲击环 + 朝本地 +X 扫出的两道挥击弧
func _draw_slam(t: float, col: Color, col_hi: Color, col_dark: Color) -> void:
	var alpha: float = 1.0 - t
	var r: float = _radius * (0.55 + 0.5 * t)
	draw_circle(Vector2.ZERO, r * 0.85, Color(col_dark.r, col_dark.g, col_dark.b, 0.22 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(col_hi.r, col_hi.g, col_hi.b, 0.9 * alpha), 4.0)
	# 挥击弧：随进度从 -50° 扫到 +50°（两道错位弧模拟锤痕）
	for k in 2:
		var phase: float = clampf(t * 1.4 - float(k) * 0.18, 0.0, 1.0)
		if phase <= 0.0:
			continue
		var a0: float = lerpf(-0.9, 0.9, phase)
		var rr: float = _radius * (0.95 + 0.25 * float(k))
		var pts: PackedVector2Array = []
		for i in 9:
			var a: float = lerpf(a0 - 0.55, a0 + 0.1, float(i) / 8.0)
			pts.append(Vector2(cos(a), sin(a)) * rr)
		draw_polyline(pts, Color(col_hi.r, col_hi.g, col_hi.b, 0.75 * alpha), 3.0)


## muzzle：沿 +X 锥形火光 + 小环（玩家枪口）
func _draw_muzzle(t: float, col: Color, col_hi: Color) -> void:
	var alpha: float = 1.0 - t
	var len: float = 16.0 + 22.0 * (1.0 - t)
	var spread: float = 0.35 + 0.15 * t
	var p1: Vector2 = Vector2(cos(-spread), sin(-spread)) * len
	var p2: Vector2 = Vector2(cos(spread), sin(spread)) * len
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, p1, p2]), Color(col.r, col.g, col.b, 0.5 * alpha))
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, p1 * 0.55, p2 * 0.55]), Color(col_hi.r, col_hi.g, col_hi.b, 0.7 * alpha))
	draw_arc(Vector2.ZERO, 6.0 + 5.0 * t, 0.0, TAU, 16, Color(col_hi.r, col_hi.g, col_hi.b, 0.8 * alpha), 2.0)


## sting：针刺 + 麻痹圈（水母叮刺命中点）
func _draw_sting(t: float, col: Color, col_hi: Color) -> void:
	var alpha: float = 1.0 - t
	var len: float = 10.0 + 10.0 * (1.0 - t)
	# 三根放射短刺
	for i in 3:
		var a: float = -0.6 + 0.6 * float(i)
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * len, Color(col_hi.r, col_hi.g, col_hi.b, 0.9 * alpha), 2.0)
	var r: float = _radius * 0.4 * (0.5 + t)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 18, Color(col.r, col.g, col.b, 0.8 * alpha), 2.0)


## dive：俯冲扬尘（冲击环 + 斜向碎屑）
func _draw_dive(t: float, col: Color, col_hi: Color) -> void:
	var alpha: float = 1.0 - t
	var r: float = _radius * 0.45 * (0.5 + 0.8 * t)
	draw_circle(Vector2.ZERO, r * 0.6, Color(col.r, col.g, col.b, 0.20 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(col_hi.r, col_hi.g, col_hi.b, 0.75 * alpha), 2.5)
	# 碎屑：两侧斜飞短划
	for i in 4:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var a: float = side * (0.5 + 0.25 * float(i / 2)) + t * 0.8
		var d0: float = r * 0.5
		var d1: float = d0 + 10.0 * (1.0 - t)
		draw_line(Vector2(cos(a), sin(a)) * d0, Vector2(cos(a), sin(a)) * d1,
			Color(col_hi.r, col_hi.g, col_hi.b, 0.6 * alpha), 2.0)


## burst：环形弹幕齐射（玩家身处径向光环 + 8 辐条，水母炮）
func _draw_burst(t: float, col: Color, col_hi: Color) -> void:
	var alpha: float = 1.0 - t
	var r: float = _radius * (0.35 + 0.85 * t)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col_hi.r, col_hi.g, col_hi.b, 0.85 * alpha), 3.0)
	draw_circle(Vector2.ZERO, r * 0.35, Color(col.r, col.g, col.b, 0.22 * alpha))
	# 8 辐条：随进度外伸
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var d0: float = r * 0.35
		var d1: float = d0 + 12.0 * (1.0 - t)
		draw_line(Vector2(cos(a), sin(a)) * d0, Vector2(cos(a), sin(a)) * d1,
			Color(col.r, col.g, col.b, 0.55 * alpha), 2.0)
	# 中心闪光
	draw_circle(Vector2.ZERO, 5.0 * (1.0 - t) + 2.0, Color(col_hi.r, col_hi.g, col_hi.b, 0.8 * alpha))
