# ============================================================================
# GroundBackdrop — 海底地面（可平铺像素地砖）
# 职责：在世界底层铺一张可平铺的地砖贴图，跟随玩家（相机中心）滚动，
#       解决「地图纯色、没有资源」的观感问题。
# 实现：Node2D._draw 里用 draw_texture_rect(..., tile=true) 平铺；
#       矩形原点按地砖尺寸对齐取整，避免跟随时花纹「游动」。
#       纹理重复需 CanvasItem.texture_repeat = ENABLED。
# 数据源：assets/sprites/ground/floor_<n>.png（tools/generate_pixel_sprites.py 生成）
# 红线：地砖索引/缩放只读 config（本文件不写数值常量除尺寸对齐外）；
#       玩家节点由 World 注入（set_target），不硬编码路径。
# ============================================================================
extends Node2D

const _SPRITE_LIB = preload("res://scripts/core/sprite_lib.gd")

## 覆盖范围（像素）：缺省；实际值读 config/map.json ground.cover_px
const COVER_DEFAULT: float = 4096.0

var _tex: Texture2D = null
var _tile_px: float = 48.0
var _cover: float = COVER_DEFAULT
## 跟随目标（玩家）；由 World 注入
var _target: Node2D = null
## 已绘制的对齐原点（避免每帧无谓 redraw）
var _last_origin: Vector2 = Vector2(INF, INF)


func _ready() -> void:
	# 地砖在所有实体之下
	z_index = -100
	# 平铺需要开启纹理重复
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cover = ConfigLoader.get_ground_cover_px()
	_load_tile()
	queue_redraw()


## 加载地砖贴图（config/map.json ground.tile_id；缺失则回退 floor_0）
func _load_tile() -> void:
	var ids: Array[String] = [ConfigLoader.get_ground_tile_id(), "floor_0"]
	for id in ids:
		var tex: Texture2D = _SPRITE_LIB.ground(id)
		if tex != null:
			_tex = tex
			_tile_px = maxf(float(tex.get_width()), 1.0)
			return


## 注入跟随目标（玩家）。World 在 _ready 调用。
func set_target(node: Node2D) -> void:
	_target = node


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	# 取玩家位置，按地砖尺寸对齐取整 → 稳定原点
	var center: Vector2 = _target.global_position
	var origin: Vector2 = Vector2(
		snappedf(center.x, _tile_px),
		snappedf(center.y, _tile_px)
	)
	if origin != _last_origin:
		_last_origin = origin
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var origin: Vector2 = _last_origin
	if origin.x == INF:
		return
	# 以对齐原点为中心铺开 cover×cover
	var rect := Rect2(origin - Vector2(_cover, _cover) * 0.5, Vector2(_cover, _cover))
	draw_texture_rect(_tex, rect, true)