# ============================================================================
# Chest — 夜场宝箱（MVP 最小可用）
# 职责：灯塔外环刷新；玩家主动触碰开启；不吸附
# 数据源：config/pickups.json.chest
# 红线：走对象池（ChestPool），禁止运行时 instantiate；不用 Physics2D
# ============================================================================
class_name Chest
extends Node2D

## 稀有度（与 pickups.json.chest.rarity_names 对齐）
enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
}

const RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.7, 0.55, 0.95),
	Color(0.35, 0.85, 0.45, 0.95),
	Color(0.35, 0.55, 1.0, 1.0),
	Color(0.9, 0.4, 1.0, 1.0),
]

## 开箱时写入的稀有度（由 PickupSystem 在生成时设定）
var rarity: Rarity = Rarity.COMMON


## 绘制层级：抬到黑夜雾罩（VisionOverlay z=80）之上，暗处也看得见宝箱（原为 3）
## 层级栈：雾罩 80 < 玩家弹道/特效/拾取物 81 < 灯塔塔身 82 < 散落光源 83 < 玩家 84
const _RENDER_Z := preload("res://scripts/core/render_z.gd")
const Z_ABOVE_FOG: int = _RENDER_Z.ABOVE_FOG


func _ready() -> void:
	z_index = Z_ABOVE_FOG


func _draw() -> void:
	var c: Color = RARITY_COLORS[clampi(int(rarity), 0, RARITY_COLORS.size() - 1)]
	draw_rect(Rect2(Vector2(-10, -8), Vector2(20, 16)), c)
	draw_rect(Rect2(Vector2(-10, -8), Vector2(20, 16)), Color(1, 1, 1, 0.55), false, 1.5)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color(1, 1, 1, 0.35), 1.0)


func _on_acquire() -> void:
	rarity = Rarity.COMMON
	queue_redraw()


func _on_release() -> void:
	rarity = Rarity.COMMON
	queue_redraw()


func set_rarity(r: Rarity) -> void:
	rarity = r
	queue_redraw()
