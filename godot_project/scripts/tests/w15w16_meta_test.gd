# ============================================================================
# W15W16MetaTest — W15 角色系统 / W16 灯塔·星尘·存档 逻辑机检（headless）
# 验收项：
#   W15-a 角色共 3 个（watcher/blacksmith/stargazer）
#   W15-b 解锁：守望者默认；铁匠累计3局；星象师通关第5夜
#   W15-c 开局武器映射（鱼叉枪/锚锤/雷暴云）
#   W15-d 角色生命（100/120/85，数据驱动）
#   W15-e 角色特性数值（守望者全+5%；铁匠范围+30%/攻速-15%；星象师伤害-10%/弹道+1）
#   W15-f 角色特性倍率聚合（MetaSystem 修正 getter）
#   W16-a 灯塔 3×5 = 15 节点
#   W16-b 灯塔购买门控（前置链 + 星尘）
#   W16-c 星尘结算公式（基础×进度×难度×首胜）
#   W16-d 存档版本化读写（星尘/灯塔/清夜进度持久化）
#   W16-e 灯塔最大生命加成叠加开局生命
#   W16-f 灯塔休息夜 regen
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w15w16_meta_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

var _passed: int = 0
var _failed: int = 0
var _fail_msgs: Array[String] = []


func _ready() -> void:
	if not ConfigLoader.is_loaded:
		push_error("[W15W16MetaTest] ConfigLoader 未加载")
		get_tree().quit(1)
		return
	print("============================================================")
	print("W15-W16 角色 / 灯塔 / 星尘 / 存档 机检")
	print("============================================================")
	_test_characters()
	_test_lighthouse_and_settlement()
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("失败项: " + ", ".join(_fail_msgs))
	print("============================================================")
	# 收尾：清掉本机检过程中点亮/购买的局外进度，避免跨进程持久化存档污染后续机检场景
	MetaSystem.end_run()
	MetaSystem.reset_progress()
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		_fail_msgs.append(label)
		print("  [FAIL] %s" % label)


# ============================================================================
# W15 角色系统
# ============================================================================
func _test_characters() -> void:
	print("[W15 角色系统]")
	# 激活局内特性倍率：本机检直接读取 MetaSystem 修正 getter（W15-g），需 _run_active=true
	MetaSystem.begin_run()
	# W15-a
	var ids: Array[String] = ConfigLoader.get_all_character_ids()
	_assert(ids.size() == 3, "角色共 3 个")
	_assert(ids.has("watcher") and ids.has("blacksmith") and ids.has("stargazer"), "含 watcher/blacksmith/stargazer")

	# W15-b 解锁（重置后守望者默认，其余锁定）
	MetaSystem.reset_progress()
	_assert(MetaSystem.is_character_unlocked("watcher") == true, "守望者默认解锁")
	_assert(MetaSystem.is_character_unlocked("blacksmith") == false, "铁匠初始锁定")
	_assert(MetaSystem.is_character_unlocked("stargazer") == false, "星象师初始锁定")
	MetaSystem.record_run_started("watcher")
	MetaSystem.record_run_started("watcher")
	MetaSystem.record_run_started("watcher")
	_assert(MetaSystem.is_character_unlocked("blacksmith") == true, "累计3局解锁铁匠")
	MetaSystem.record_night_cleared(5)
	_assert(MetaSystem.is_character_unlocked("stargazer") == true, "通关第5夜解锁星象师")

	# W15-c 开局武器
	_assert(ConfigLoader.get_character_starting_weapon("watcher") == "harpoon", "守望者开局鱼叉枪")
	_assert(ConfigLoader.get_character_starting_weapon("blacksmith") == "anchor_hammer", "铁匠开局锚锤")
	_assert(ConfigLoader.get_character_starting_weapon("stargazer") == "storm_cloud", "星象师开局雷暴云")

	# W15-d 生命
	_assert(ConfigLoader.get_character_max_health("watcher") == 100, "守望者生命 100")
	_assert(ConfigLoader.get_character_max_health("blacksmith") == 120, "铁匠生命 120")
	_assert(ConfigLoader.get_character_max_health("stargazer") == 85, "星象师生命 85")

	# W15-e 特性数值
	var w: Dictionary = ConfigLoader.get_character("watcher").get("traits", {})
	_assert(int(w.get("damage_pct", 0)) == 5, "守望者伤害 +5%")
	var b: Dictionary = ConfigLoader.get_character("blacksmith").get("traits", {})
	_assert(int(b.get("area_pct", 0)) == 30, "铁匠范围 +30%")
	_assert(int(b.get("attack_speed_pct", 0)) == -15, "铁匠攻速 -15%")
	var s: Dictionary = ConfigLoader.get_character("stargazer").get("traits", {})
	_assert(int(s.get("damage_pct", 0)) == -10, "星象师伤害 -10%")
	_assert(int(s.get("projectile_bonus", 0)) == 1, "星象师弹道 +1")

	# W15-f 开局生命（数据驱动，覆盖全局 match 旧实现）
	GameState.start_new_run("blacksmith")
	_assert(GameState.player_max_health == 120, "开局铁匠生命 = 120")
	GameState.start_new_run("stargazer")
	_assert(GameState.player_max_health == 85, "开局星象师生命 = 85")
	GameState.start_new_run("watcher")
	_assert(GameState.player_max_health == 100, "开局守望者生命 = 100")

	# W15-g 特性倍率聚合（依赖 T3 解锁状态）
	MetaSystem.set_active_character("watcher")
	_assert(abs(MetaSystem.get_damage_mult() - 1.05) < 0.001, "守望者伤害 ×1.05")
	_assert(abs(MetaSystem.get_attack_speed_mult() - 1.05) < 0.001, "守望者攻速 ×1.05")
	_assert(abs(MetaSystem.get_area_mult() - 1.05) < 0.001, "守望者范围 ×1.05")
	_assert(abs(MetaSystem.get_move_speed_mult() - 1.05) < 0.001, "守望者移速 ×1.05")
	_assert(abs(MetaSystem.get_exp_mult() - 1.0) < 0.001, "守望者经验 ×1.0（不触碰 w1 经验断言）")
	MetaSystem.set_active_character("blacksmith")
	_assert(abs(MetaSystem.get_area_mult() - 1.30) < 0.001, "铁匠范围 ×1.30")
	_assert(abs(MetaSystem.get_attack_speed_mult() - 0.85) < 0.001, "铁匠攻速 ×0.85")
	MetaSystem.set_active_character("stargazer")
	_assert(abs(MetaSystem.get_damage_mult() - 0.90) < 0.001, "星象师伤害 ×0.90")
	_assert(MetaSystem.get_extra_projectiles() == 1, "星象师弹道 +1")


# ============================================================================
# W16 灯塔 / 星尘 / 存档
# ============================================================================
func _test_lighthouse_and_settlement() -> void:
	print("[W16 灯塔 / 星尘 / 存档]")
	# W16-a 节点结构
	var nodes: Dictionary = ConfigLoader.get_all_lighthouse_nodes()
	_assert(nodes.size() == 15, "灯塔节点共 15 个")
	var branches: Dictionary = ConfigLoader.get_lighthouse_branches()
	_assert(branches.size() == 3, "灯塔 3 分支")
	for b in branches.keys():
		var bn: Dictionary = branches[b]
		_assert((bn.get("nodes", {}) as Dictionary).size() == 5, "分支 %s 5 节点" % b)

	# W16-b 购买门控（重置 → 仅 60 星尘）
	MetaSystem.reset_progress()
	MetaSystem.settle_stardust(20, false)  # +60
	_assert(MetaSystem.can_purchase_node("vigil_2") == false, "前置未点亮不可购买 vigil_2")
	_assert(MetaSystem.can_purchase_node("vigil_1") == true, "vigil_1 可购买")
	_assert(MetaSystem.purchase_node("vigil_1") == true, "购买 vigil_1 成功")
	_assert(MetaSystem.is_node_purchased("vigil_1") == true, "vigil_1 已点亮")
	_assert(MetaSystem.get_stardust() == 30, "购买后星尘 = 30")
	_assert(MetaSystem.can_purchase_node("vigil_2") == false, "星尘不足不可购买 vigil_2")
	_assert(MetaSystem.purchase_node("vigil_2") == false, "星尘不足购买 vigil_2 返回 false")
	MetaSystem.settle_stardust(20, false)  # +60 → 90
	_assert(MetaSystem.can_purchase_node("vigil_2") == true, "星尘充足可购买 vigil_2")
	_assert(MetaSystem.purchase_node("vigil_2") == true, "购买 vigil_2 成功")

	# W16-c 结算公式
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(20, false) == 60, "结算(20夜,未通关) = 60")
	_assert(MetaSystem.settle_stardust(10, false) == 30, "结算(10夜,未通关) = 30")
	_assert(MetaSystem.settle_stardust(20, true) == 90, "首通结算 = 90 (×1.5)")
	_assert(SaveSystem.get_save_meta().get("first_clear", false) == true, "首通标记置位")
	var before_second: int = MetaSystem.get_stardust()
	_assert(MetaSystem.settle_stardust(20, true) == 60, "二次通关无首胜加成 = 60")
	_assert(MetaSystem.get_stardust() == before_second + 60, "二次通关星尘累加正确")

	# W16-d 存档版本化读写
	MetaSystem.reset_progress()
	MetaSystem.settle_stardust(20, false)         # +60
	MetaSystem.purchase_node("vigil_1")            # -30 → 30
	MetaSystem.record_night_cleared(7)             # max_night_cleared = 7
	SaveSystem.load_save()                         # 重新读取磁盘
	var m: Dictionary = SaveSystem.get_save_meta()
	_assert(int(m.get("stardust", 0)) == 30, "重载后星尘 = 30")
	_assert(bool((m.get("lighthouse", {}) as Dictionary).get("vigil_1", false)) == true, "重载后灯塔 vigil_1 已点亮")
	_assert(int(m.get("max_night_cleared", 0)) == 7, "重载后 max_night_cleared = 7")

	# W16-e 灯塔最大生命加成叠加开局生命
	MetaSystem.reset_progress()
	MetaSystem.settle_stardust(20, false)  # +60
	MetaSystem.purchase_node("vigil_1")     # +20 max_health
	_assert(MetaSystem.get_max_health_bonus() == 20, "灯塔最大生命加成 = 20")
	GameState.start_new_run("watcher")
	_assert(GameState.player_max_health == 120, "守望者 + 灯塔 = 120 生命")

	# W16-f 灯塔 regen_per_night（进昼未满血）（点亮 vigil_1~4 链）
	MetaSystem.reset_progress()
	for _i in 6:
		MetaSystem.settle_stardust(20, false)  # 6 × 60 = 360
	_assert(MetaSystem.purchase_node("vigil_1") == true, "购买 vigil_1")
	_assert(MetaSystem.purchase_node("vigil_2") == true, "购买 vigil_2")
	_assert(MetaSystem.purchase_node("vigil_3") == true, "购买 vigil_3")
	_assert(MetaSystem.purchase_node("vigil_4") == true, "购买 vigil_4（regen +8）")
	_assert(MetaSystem.get_regen_per_night() == 8, "灯塔 regen = 8")
	# W16-f 实回血：regen 在未满血时生效（休息回满后不再加）
	GameState.start_new_run("watcher")
	GameState.player_health = 50
	_assert(RestSystem.try_apply_night_regen() == 8, "未满血 regen 回复 8")
	_assert(GameState.player_health == 58, "HP 50+8=58")
	GameState.player_health = GameState.player_max_health
	_assert(RestSystem.try_apply_night_regen() == 0, "满血 regen 不加")

	# W16-g 灯塔减伤只经 PassiveSystem 叠一次（vigil_2 = 5%）
	_assert(abs(PassiveSystem.get_damage_reduction() - 0.05) < 0.001, "灯塔减伤 5% 已计入 PassiveSystem")
	GameState.is_over = false
	GameState.player_health = 100
	GameState.damage_player(20)
	_assert(GameState.player_health == 81, "减伤只叠一次：100 - 20×0.95 = 81")

	# W16-h 事件星尘并入局终结算
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(20, false, 1) == 61, "结算含事件星尘 +1 = 61")
