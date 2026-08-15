extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

func _ready() -> void:
	print("================ DIAG: HP drain under idle player ================")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: Node = main
	var enemy_pool: ObjectPool = world.get_node("EnemyPool")
	var player: Node2D = world.get_node("Player")
	var wm: Node = world.get_node("WeaponManager")
	var frame: int = 0
	var prev_hp: int = GameState.player_health
	while frame < 60 * 50:
		await get_tree().process_frame
		frame += 1
		var hp: int = GameState.player_health
		if hp < prev_hp:
			var nd: float = _nearest_dist(enemy_pool, player)
			var cnt: int = enemy_pool.active_count()
			print("[DIAG] frame=%d t=%.2fs HP %d->%d (Δ%d) nearest_enemy=%.1f active=%d" % [frame, frame/60.0, prev_hp, hp, prev_hp - hp, nd, cnt])
		prev_hp = hp
		if frame % 60 == 0:
			var nd: float = _nearest_dist(enemy_pool, player)
			print("[DIAG] t=%.1fs HP=%d active=%d nearest=%.1f weapons=%d is_over=%s" % [frame/60.0, hp, enemy_pool.active_count(), nd, wm.get_weapons().size(), GameState.is_over])
		if GameState.is_over:
			print("[DIAG] GAME OVER at frame %d (t=%.1fs)" % [frame, frame/60.0])
			break
	main.queue_free()
	get_tree().quit(0)


func _nearest_dist(pool: ObjectPool, player: Node2D) -> float:
	var best: float = -1.0
	for e in pool.get_active():
		var d: float = (e as Node2D).global_position.distance_to(player.global_position)
		if best < 0.0 or d < best:
			best = d
	return best
