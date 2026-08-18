# ============================================================================
# DiagVisibility — 验证「敌人弹幕可见」与「相机跟随玩家」
# 背景：enemy_projectile.tscn 原仅有 Node2D+脚本、无可见节点 → 敌人远程弹幕隐形扣血；
#       main.tscn 的 Camera2D 挂在 Main（不移动）→ 玩家走远出屏、敌人屏幕外生成。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/diag_visibility_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const _CLEANUP := preload("res://scripts/tests/test_cleanup.gd")
const ENEMY_PROJ_SCENE := preload("res://scripts/combat/enemy_projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("DiagVisibility (敌人弹幕可见 + 相机跟随玩家)")
	print("============================================================")

	# 1) 相机跟随玩家：main 场景中 Camera2D 必须是 Player 的子节点
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam: Node = main.get_node_or_null("Player/Camera2D")
	_assert(cam != null, "相机 Camera2D 位于 Player/Camera2D（跟随玩家）")
	_assert(cam != null and cam is Camera2D, "Camera2D 类型正确")
	_CLEANUP.free_node(main)

	# 2) 敌人弹幕可见：场景实例必须含可见 Visual 子节点
	var ep: Node = ENEMY_PROJ_SCENE.instantiate()
	add_child(ep)
	await get_tree().process_frame
	_assert(ep.has_node("Visual"), "敌人弹幕场景含 Visual 节点")
	var epv: Node = ep.get_node_or_null("Visual")
	_assert(epv != null and epv.visible, "敌人弹幕 Visual 可见（不再是隐形扣血）")
	_CLEANUP.free_node(ep)

	# 3) 敌人本体可见（回归基线）：红色方块
	var en: Node = ENEMY_SCENE.instantiate()
	add_child(en)
	await get_tree().process_frame
	_assert(en.has_node("Visual"), "敌人本体场景含 Visual 节点")
	_CLEANUP.free_node(en)

	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
