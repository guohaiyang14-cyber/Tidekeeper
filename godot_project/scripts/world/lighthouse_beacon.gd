# ============================================================================
# LighthouseBeacon — 灯塔塔楼（2026-10-22 用户反馈：「灯塔应是有高度的塔+光束」）
# 职责：在灯塔圆心渲染塔楼精灵（assets/sprites/world/lighthouse_tower.png，96×168px，
#       底部中心对齐塔基）+ 夜间灯室辉光脉冲；旋转光束由 VisionOverlay 绘制
#       （雾罩开洞 + 楔形光带），本节点只提供光源坐标与塔身视觉。
# 混合：灯室辉光挂 BLEND_MODE_ADD（2026-10-23 用户反馈「所有的光都不应该会挡住
#       下面内容」——原 draw_circle 用 MIX 会盖住塔身下方与地面细节）。
# 数据：config/map.json lighthouse（sprite_id / lamp_glow_radius_px / collision_radius_units）
# 红线：碰撞由 Player 推出处理，不用 Physics2D；参数只读 config。
# ============================================================================
extends Node2D
class_name LighthouseBeacon

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")

var _radius_px: float = 30.0
var _glow_radius: float = 46.0
var _night: bool = false
var _pulse_t: float = 0.0
var _sprite: Sprite2D = null


func _ready() -> void:
	# 2026-10-23 用户反馈「所有的光都不应该会挡住下面内容」：
	# 灯室辉光原为 MIX 混合的 draw_circle，会盖住塔身下方与地面细节。
	# 挂 BLEND_MODE_ADD（只提亮不覆盖）；CanvasItem.material 不向子节点继承，
	# 因此塔身精灵仍是默认 MIX，保留自身调色板与像素层次。
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func setup(center: Vector2, radius_px: float, sprite_tex: Texture2D = null) -> void:
	global_position = center
	_radius_px = maxf(radius_px, 1.0)
	_glow_radius = ConfigLoader.get_lighthouse_glow_radius_px()
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	if sprite_tex != null:
		_sprite.texture = sprite_tex
	elif _sprite.texture == null:
		_sprite.texture = _SPRITE_LIB.world(ConfigLoader.get_lighthouse_sprite_id())
	# 底部中心对齐：塔基坐在灯塔圆心上，塔身向上（有高度）
	if _sprite.texture != null:
		_sprite.centered = true
		_sprite.position = Vector2(0.0, -float(_sprite.texture.get_height()) * 0.5)
	queue_redraw()


## 昼/夜切换（World._on_phase_changed 调用）：仅夜间点亮灯室辉光
func set_night(is_night: bool) -> void:
	_night = is_night
	set_process(_night)
	if not _night:
		queue_redraw()


func _process(delta: float) -> void:
	if not _night:
		return
	_pulse_t += delta
	queue_redraw()


func _draw() -> void:
	# 2026-10-23 用户反馈「灯塔底部不需要光圈」→ 移除塔基 draw_circle/draw_arc，
	# 仅保留塔顶灯室辉光（夜间呼吸脉冲），避免与 VisionOverlay 的照明亮圈叠加成双圈。
	# 2026-10-26 用户反馈「去掉所有发光」→ night.json vision.enabled=false 时灯室辉光一并关停
	if not _night or _sprite == null or _sprite.texture == null or _glow_radius <= 0.001:
		return
	if not bool(ConfigLoader.get_night_vision_config().get("enabled", true)):
		return
	# 灯室辉光：位于塔顶灯室高度（config lamp_height_px），呼吸脉冲
	var tex_h: float = float(_sprite.texture.get_height())  # 入口已保证 _sprite/texture 非空
	var lamp_y: float = -ConfigLoader.get_lighthouse_lamp_height_px()
	if lamp_y >= -0.001 and tex_h > 0.0:
		lamp_y = -tex_h * 0.82
	var pulse: float = 0.75 + 0.25 * sin(_pulse_t * 2.2)
	var r: float = _glow_radius * pulse
	for k in 3:
		var a: float = 0.34 * pulse * (1.0 - float(k) * 0.28)
		draw_circle(Vector2(0.0, lamp_y), r * (1.0 + float(k) * 0.8), Color(1.0, 0.90, 0.58, a))
