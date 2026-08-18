# ============================================================================
# TestCleanup — headless 测试释放辅助
# 职责：同步卸下并 free 实例化的 main 场景，避免 queue_free 后立刻 quit 导致 ObjectDB 泄漏
# ============================================================================
extends Object


## 解除暂停、移出场景树并立即 free（不要 queue_free 后马上 quit）
static func free_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tree: SceneTree = node.get_tree()
	if tree != null:
		tree.paused = false
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
