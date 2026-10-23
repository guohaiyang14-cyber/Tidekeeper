# ============================================================================
# VisionLightFx — 黑夜「光效层」（加色混合）
# 职责：绘制**只提亮、不遮挡**的光——灯塔旋转光束楔形 + 命中闪光的底光/冲击环。
# 为什么单独一层：雾罩本体必须保持 MIX 混合（否则黑夜直接失效，什么都能看见），
#       但「光」不能遮挡雾罩下面的地面 / 敌人 / 掉落物。
#       2026-10-23 用户反馈：「灯塔的光束不能挡住下面视野，所有的光都不应该会挡住下面内容」。
#       CanvasItem.material 每个节点只能挂一个，所以把光效从雾罩拆出来单独挂
#       CanvasItemMaterial.BLEND_MODE_ADD（加色：dst = src + dst，只增亮不覆盖）。
# 数据/状态：全部由 VisionOverlay 持有，本节点只负责「在正确的混合模式下画出来」。
# 注意：draw_* 是 CanvasItem 方法，必须在**正在绘制的那个节点**上调用，
#       故统一回调 overlay.draw_light_fx(self)，由它转调 target.draw_*(...)。
# 红线：不持有任何 config；层级/混合模式由 VisionOverlay._setup_light_fx() 设置。
# ============================================================================
class_name VisionLightFx
extends Node2D

## 归属的雾罩（提供光束/闪光状态与绘制逻辑）
var _overlay: Node = null


func bind(overlay: Node) -> void:
	_overlay = overlay
	# 绝对层级（具体值由 VisionOverlay._setup_light_fx() 以 LIGHT_FX_Z_INDEX 设置，
	# 单一来源勿在本文件硬编码）；父节点隐藏时子节点自动跟随隐藏
	z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _draw() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.has_method("draw_light_fx"):
		_overlay.call("draw_light_fx", self)
