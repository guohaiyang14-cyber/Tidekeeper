# ============================================================================
# W17FrustrationTest — W17 挫败感控制 逻辑机检（headless）
# 验收项（数据驱动 config/frustration.json）：
#   W17-1 配置加载（首夜保护 / 挣扎模式 / 失败保底 / 死因可视化 参数齐全且符合设计）
#   W17-2 伤害来源追踪（damage_player(source_id) → 累计 + 最后一击）
#   W17-3 死因可视化（get_death_analysis：最后一击 + 伤害 TopN）
#   W17-4 首夜保护（前 4 夜死亡满血复活 1 次；>4 夜不触发；复活后短暂无敌）
#   W17-5 挣扎模式（免死窗口 + 击杀 K 敌复活；每局最多 1 次；窗口耗尽判负）
#   W17-6 失败保底结算（落败星尘 ≥ floor_pct × 满通应得）
#   W17-7 门控：未 begin_run 时挫败感复活不生效（与角色/灯塔特性同门控，不污染单元机检）
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w17_frustration_test.tscn
#       退出码 0=全过 / 1=有失败
# ============================================================================
extends Node

const _RESULT_UI := preload("res://scripts/core/result_ui.gd")
const _DAY_NIGHT := preload("res://scripts/core/day_night_state_machine.gd")

var _passed: int = 0
var _failed: int = 0
var _fail_msgs: Array[String] = []
var _sig_cap: Dictionary = {}  # player_down 信号捕获（W17-11）


func _ready() -> void:
	if not ConfigLoader.is_loaded:
		push_error("[W17FrustrationTest] ConfigLoader 未加载")
		get_tree().quit(1)
		return
	print("============================================================")
	print("W17 挫败感控制 机检")
	print("============================================================")
	_test_config()
	_test_damage_source_tracking()
	_test_death_analysis()
	_test_first_night()
	_test_first_night_expiry()
	_test_struggle_revive()
	_test_struggle_once_then_death()
	_test_struggle_expire()
	_test_failure_floor()
	_test_gate_no_run()
	_test_struggle_feedback()
	_test_death_analysis_caliber()
	_test_struggle_night_end()
	_test_fallback_enabled()
	_test_source_labels()
	print("------------------------------------------------------------")
	print("Result: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("失败项: " + ", ".join(_fail_msgs))
	print("============================================================")
	# 收尾：清掉本机检可能点亮的局外进度 / 结束 run 态，避免跨进程持久化存档污染后续机检
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
# W17-1 配置加载
# ============================================================================
func _test_config() -> void:
	print("[W17-1 配置加载]")
	var cfg: Dictionary = ConfigLoader.get_frustration_config()
	_assert(not cfg.is_empty(), "frustration.json 已加载")
	var fn: Dictionary = cfg.get("first_night", {})
	_assert(bool(fn.get("enabled", false)) == true, "首夜保护启用")
	_assert(int(fn.get("protect_nights", -1)) == 4, "首夜保护窗口 = 前 4 夜")
	_assert(int(fn.get("max_revives", -1)) == 1, "首夜保护最多复活 1 次")
	_assert(abs(float(fn.get("revive_invuln_sec", -1.0)) - 1.5) < 0.001, "首夜复活后无敌 1.5s（数据驱动）")
	var st: Dictionary = cfg.get("struggle", {})
	_assert(bool(st.get("enabled", false)) == true, "挣扎模式启用")
	_assert(abs(float(st.get("invuln_sec", -1.0)) - 3.0) < 0.001, "挣扎免死窗口 = 3.0s")
	_assert(int(st.get("kills_to_revive", -1)) == 5, "挣扎需击杀 5 敌复活")
	_assert(int(st.get("max_revives", -1)) == 1, "挣扎最多复活 1 次")
	_assert(abs(float(st.get("revive_invuln_sec", -1.0)) - 2.0) < 0.001, "挣扎复活后无敌 2.0s（数据驱动）")
	var fb: Dictionary = cfg.get("fallback", {})
	_assert(bool(fb.get("enabled", false)) == true, "失败保底启用")
	_assert(abs(float(fb.get("floor_pct", -1.0)) - 0.30) < 0.001, "失败保底 floor_pct = 0.30")
	var da: Dictionary = cfg.get("death_analysis", {})
	_assert(int(da.get("top_sources", -1)) == 3, "死因 Top3")


# ============================================================================
# W17-2 伤害来源追踪
# ============================================================================
func _test_damage_source_tracking() -> void:
	print("[W17-2 伤害来源追踪]")
	GameState.start_new_run("watcher")
	# 无 run 激活：减伤基线 0，applied == amount
	GameState.damage_player(30, "enemy_contact")
	GameState.damage_player(50, "boss_tide_archon")
	var a1: Dictionary = GameState.get_death_analysis()
	var total1: int = 0
	for v in a1.get("top_sources", []):
		total1 += int(v["damage"])
	# 累计：enemy_contact=30, boss_tide_archon=50
	_assert(GameState.player_health == 20, "累计受伤后 HP=20（减伤基线 0）")
	# 直接校验 top_sources 排序与量
	var ranked: Array = a1.get("top_sources", [])
	_assert(ranked.size() == 2, "已记录 2 个伤害来源")
	# 最后一击为 boss_tide_archon
	_assert(a1.get("last_hit_source") == "boss_tide_archon", "最后一击来源 = boss_tide_archon")
	_assert(int(a1.get("last_hit_amount")) == 50, "最后一击伤害 = 50")


# ============================================================================
# W17-3 死因可视化（get_death_analysis：最后一击 + TopN）
# ============================================================================
func _test_death_analysis() -> void:
	print("[W17-3 死因可视化]")
	GameState.start_new_run("watcher")
	GameState.damage_player(30, "enemy_contact")
	GameState.damage_player(50, "boss_tide_archon")
	GameState.damage_player(20, "enemy_contact")  # 致死（无 run 激活 → 直接判负）
	_assert(GameState.is_over == true, "致死伤害触发游戏结束")
	var a: Dictionary = GameState.get_death_analysis()
	_assert(a.get("last_hit_source") == "enemy_contact", "死因最后一击 = enemy_contact")
	_assert(int(a.get("last_hit_amount")) == 20, "死因最后一击伤害 = 20")
	# top_sources 按伤害降序：boss 50 / enemy_contact 50
	var top: Array = a.get("top_sources", [])
	_assert(top.size() == 2, "伤害来源 Top = 2")
	_assert(int(top[0]["damage"]) == 50 and int(top[1]["damage"]) == 50, "Top 伤害量均为 50")
	# 来源集合正确（不重复计数）
	var srcs: Array = []
	for s in top:
		srcs.append(String(s["source"]))
	_assert("boss_tide_archon" in srcs and "enemy_contact" in srcs, "Top 含 boss 与接触")
	_assert(int(a.get("total_damage")) == 100, "累计伤害 = 100")


# ============================================================================
# W17-4 首夜保护
# ============================================================================
func _test_first_night() -> void:
	print("[W17-4 首夜保护]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(1)  # 第 1 夜，在保护窗口内
	var max_hp: int = GameState.player_max_health
	GameState.damage_player(9999)  # 致命
	_assert(GameState.is_over == false, "首夜保护：未判负")
	_assert(GameState.player_health == max_hp, "首夜保护：满血复活")
	_assert(GameState.is_invulnerable() == true, "首夜保护：复活后短暂无敌")
	# 无敌期内伤害被忽略
	GameState.damage_player(10)
	_assert(GameState.player_health == max_hp, "无敌期内伤害被忽略（HP 仍满）")
	# 清空无敌后再次致命 → 首夜已用尽（max 1），转挣扎模式（仍非直接判负）
	var fn_cfg: Dictionary = ConfigLoader.get_frustration_config().get("first_night", {})
	GameState._advance_timers(float(fn_cfg.get("revive_invuln_sec", 1.5)) + 0.1)
	GameState.damage_player(9999)
	_assert(GameState.is_over == false, "首夜仅 1 次：二次致命进入挣扎而非判负")
	_assert(GameState.is_struggling() == true, "二次致命触发挣扎模式（首夜未二次复活）")
	# 挣扎窗口内击杀达标 → 复活
	for _i in int(ConfigLoader.get_frustration_config().get("struggle", {}).get("kills_to_revive", 5)):
		GameState.register_enemy_kill()
	_assert(GameState.player_health == max_hp, "挣扎击杀达标后满血复活")
	_assert(GameState.is_struggling() == false, "挣扎复活后窗口关闭")


# ============================================================================
# W17-5 首夜保护窗口过期（>4 夜不触发首夜）
# ============================================================================
func _test_first_night_expiry() -> void:
	print("[W17-5 首夜保护窗口过期]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(6)  # > protect_nights(4)
	GameState.damage_player(9999)
	_assert(GameState.is_over == false, "第 6 夜致命未直接判负")
	_assert(GameState.player_health == 0, "第 6 夜首夜保护未触发（HP 仍为 0）")
	_assert(GameState.is_struggling() == true, "第 6 夜致命进入挣扎模式（首夜已过期）")


# ============================================================================
# W17-6 挣扎模式：击杀达标复活
# ============================================================================
func _test_struggle_revive() -> void:
	print("[W17-6 挣扎模式击杀复活]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	var max_hp: int = GameState.player_max_health
	var need: int = int(ConfigLoader.get_frustration_config().get("struggle", {}).get("kills_to_revive", 5))
	GameState.damage_player(9999)
	_assert(GameState.is_struggling() == true, "致命进入挣扎模式")
	_assert(GameState.is_invulnerable() == true, "挣扎窗口内无敌")
	_assert(GameState.player_health == 0, "挣扎期间 HP=0 但存活")
	# 未达标击杀：仍挣扎
	for _i in (need - 2):
		GameState.register_enemy_kill()
	_assert(GameState.is_struggling() == true, "击杀未达标仍挣扎")
	_assert(GameState.player_health == 0, "未达标 HP 仍为 0")
	# 再击杀 2 次达标 → 复活
	GameState.register_enemy_kill()
	GameState.register_enemy_kill()
	_assert(GameState.player_health == max_hp, "击杀达标满血复活")
	_assert(GameState.is_struggling() == false, "复活后挣扎窗口关闭")


# ============================================================================
# W17-7 挣扎模式每局最多 1 次，用尽后真实死亡
# ============================================================================
func _test_struggle_once_then_death() -> void:
	print("[W17-7 挣扎模式仅 1 次]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	GameState.damage_player(9999)
	var need: int = int(ConfigLoader.get_frustration_config().get("struggle", {}).get("kills_to_revive", 5))
	for _i in need:
		GameState.register_enemy_kill()  # 第一次挣扎复活
	_assert(GameState.player_health == GameState.player_max_health, "挣扎第一次复活成功")
	var st_cfg: Dictionary = ConfigLoader.get_frustration_config().get("struggle", {})
	GameState._advance_timers(float(st_cfg.get("revive_invuln_sec", 2.0)) + 0.1)  # 清掉复活后无敌
	GameState.damage_player(9999)    # 二次致命：挣扎已用尽、首夜已过期
	_assert(GameState.is_over == true, "挣扎用尽后二次致命真实判负")
	_assert(GameState.is_struggling() == false, "二次致命未再进入挣扎")


# ============================================================================
# W17-8 挣扎窗口耗尽判负
# ============================================================================
func _test_struggle_expire() -> void:
	print("[W17-8 挣扎窗口耗尽判负]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	GameState.damage_player(9999)
	_assert(GameState.is_struggling() == true, "致命进入挣扎")
	var invuln: float = float(ConfigLoader.get_frustration_config().get("struggle", {}).get("invuln_sec", 3.0))
	GameState._advance_timers(invuln + 0.1)  # 窗口耗尽且未击杀达标
	_assert(GameState.is_over == true, "挣扎窗口耗尽未达标 → 判负")
	_assert(GameState.is_struggling() == false, "判负后挣扎窗口关闭")


# ============================================================================
# W17-9 失败保底结算
# ============================================================================
func _test_failure_floor() -> void:
	print("[W17-9 失败保底结算]")
	MetaSystem.reset_progress()
	# 满通应得 = base(60) × difficulty(1) = 60；floor = round(60 × 0.3) = 18
	_assert(MetaSystem.settle_stardust(2, false) == 18, "落败(2夜) 保底 = 18（≥30% 满通）")
	_assert(MetaSystem.settle_stardust(0, false) == 18, "落败(0夜) 保底 = 18")
	# 进度超过 floor 的按实际进度结算（不被 floor 压低）
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(10, false) == 30, "落败(10夜) = 30（>18 不触发保底）")
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(20, false) == 60, "落败(20夜) = 60")
	# 首通加成
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(20, true) == 90, "首通结算 = 90（×1.5）")
	_assert(SaveSystem.get_save_meta().get("first_clear", false) == true, "首通标记置位")
	var before: int = MetaSystem.get_stardust()
	MetaSystem.settle_stardust(20, true)  # 二次通关无首胜
	_assert(MetaSystem.get_stardust() == before + 60, "二次通关无首胜加成（+60）")


# ============================================================================
# W17-10 门控：未 begin_run 时复活不生效
# ============================================================================
func _test_gate_no_run() -> void:
	print("[W17-10 门控：未 begin_run 不触发复活]")
	MetaSystem.end_run()  # 确保未开局
	GameState.start_new_run("watcher")
	GameState.enter_night(1)
	GameState.damage_player(9999)
	_assert(GameState.is_over == true, "未 begin_run：致命直接判负")
	_assert(GameState.is_struggling() == false, "未 begin_run：不进入挣扎")
	_assert(GameState.player_health == 0, "未 begin_run：无首夜复活（HP=0）")


# ============================================================================
# W17-11 挣扎倒地反馈 / HUD 状态（P2-#2）
# ============================================================================
func _on_player_down(kind: String) -> void:
	_sig_cap["fired"] = true
	_sig_cap["kind"] = kind


func _test_struggle_feedback() -> void:
	print("[W17-11 挣扎倒地反馈/HUD 状态]")
	_sig_cap = {}
	GameState.player_down.connect(_on_player_down)
	# 注：GDScript 4.x 无 finally，_assert 仅记录失败不抛异常，故末尾 disconnect 总会执行
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	GameState.damage_player(9999)  # 致命 → 进入挣扎（HP=0 但未判负）
	_assert(_sig_cap.get("fired", false) == true, "进入挣扎 player_down 信号触发")
	_assert(_sig_cap.get("kind", "") == "struggle", "player_down kind=struggle")
	_assert(GameState.is_player_down() == true, "挣扎期 is_player_down()=true（HP=0 未判负，不被误判死亡）")
	_assert(GameState.is_over == false, "挣扎期未判负")
	_assert(GameState.get_struggle_remaining() > 0.0, "挣扎期剩余免死窗口 > 0")
	# 挣扎期内治疗不生效（P3：唯有击杀 K 敌可复活，治疗不 rescue）
	var healed: int = GameState.heal_player(50)
	_assert(healed == 0, "挣扎期内治疗返回 0（不生效）")
	_assert(GameState.player_health == 0, "挣扎期内 HP 仍 0（治疗未 rescue）")
	# 击杀达标复活后：不再 down
	var need: int = int(ConfigLoader.get_frustration_config().get("struggle", {}).get("kills_to_revive", 5))
	for _i in need:
		GameState.register_enemy_kill()
	_assert(GameState.is_player_down() == false, "复活后 is_player_down()=false")
	GameState.player_down.disconnect(_on_player_down)


# ============================================================================
# W17-12 死因统计口径（P2-#3）：每局重置（无跨局泄漏）+ 整局累计（含复活前后）
# ============================================================================
func _test_death_analysis_caliber() -> void:
	print("[W17-12 死因统计口径]")
	# (a) 每局重置：跨局无泄漏
	GameState.start_new_run("watcher")
	GameState.damage_player(30, "enemy_contact")
	GameState.damage_player(50, "boss_tide_archon")
	_assert(int(GameState.get_death_analysis().get("total_damage")) == 80, "首局累计 = 80")
	GameState.start_new_run("watcher")  # 第二局，应重置
	var a2: Dictionary = GameState.get_death_analysis()
	_assert(int(a2.get("total_damage")) == 0, "第二局 start_new_run 重置 _damage_taken（无跨局泄漏）")
	_assert(a2.get("top_sources", []).size() == 0, "第二局 top_sources 为空")
	# (b) 复活不重置统计（整局累计，含复活前后不分段）
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(1)
	GameState.damage_player(30, "enemy_contact")    # 复活前 30
	GameState.damage_player(100, "enemy_contact")    # 致命 → 首夜保护满血复活（100 仍计入）
	_assert(GameState.player_health == GameState.player_max_health, "首夜复活回满")
	_assert(int(GameState.get_death_analysis().get("total_damage")) == 130, "复活不重置：含复活前 30 + 致命 100 = 130")
	GameState._advance_timers(2.0)  # 清掉首夜复活后 1.5s 无敌，避免后续伤害被忽略
	GameState.damage_player(20, "boss_tide_archon")  # 复活后再受伤，继续累计
	_assert(int(GameState.get_death_analysis().get("total_damage")) == 150, "复活后再受伤继续累计 = 150")


# ============================================================================
# W17-13 夜尽挣扎未达标 → 立即判负（不带入抉择之昼）
# ============================================================================
func _test_struggle_night_end() -> void:
	print("[W17-13 夜尽挣扎判负]")
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	GameState.damage_player(9999)
	_assert(GameState.is_struggling() == true, "夜尽前处于挣扎")
	GameState.end_night()
	_assert(GameState.is_over == true, "夜尽挣扎未达标 → 判负")
	_assert(GameState.is_struggling() == false, "判负后挣扎关闭")
	_assert(GameState.is_player_down() == false, "判负后 is_player_down=false")
	# 状态机路径：无 World.stop 时停在 TRANSITION，不得切 DAY 开商店
	MetaSystem.begin_run()
	GameState.start_new_run("watcher")
	GameState.enter_night(10)
	GameState.damage_player(9999)
	var dn: DayNightStateMachine = _DAY_NIGHT.new() as DayNightStateMachine
	dn._current_night = 10
	dn._phase = DayNightStateMachine.Phase.NIGHT
	dn._end_night()
	_assert(GameState.is_over == true, "状态机夜尽挣扎 → 判负")
	_assert(dn.get_phase() != DayNightStateMachine.Phase.DAY, "夜尽挣扎状态机不进入抉择之昼")
	dn.free()


# ============================================================================
# W17-14 失败保底尊重 fallback.enabled
# ============================================================================
func _test_fallback_enabled() -> void:
	print("[W17-14 fallback.enabled]")
	MetaSystem.reset_progress()
	var fb: Dictionary = ConfigLoader.frustration.get("fallback", {})
	fb["enabled"] = false
	ConfigLoader.frustration["fallback"] = fb
	# 2/20 × 60 = 6；关保底后不得抬到 18
	_assert(MetaSystem.settle_stardust(2, false) == 6, "fallback.enabled=false 不触发保底（2夜=6）")
	fb["enabled"] = true
	ConfigLoader.frustration["fallback"] = fb
	MetaSystem.reset_progress()
	_assert(MetaSystem.settle_stardust(2, false) == 18, "恢复 enabled 后保底 = 18")


# ============================================================================
# W17-15 死因友好名：接触/自爆带敌人中文名
# ============================================================================
func _test_source_labels() -> void:
	print("[W17-15 死因友好名]")
	var ui: ResultUI = _RESULT_UI.new() as ResultUI
	_assert(ui._source_label("contact:small_goblin") == "接触·小水鬼", "接触来源映射敌人名")
	_assert(ui._source_label("explode:bomb_shell") == "自爆·爆炸贝", "自爆来源映射敌人名")
	_assert(ui._source_label("enemy_projectile") == "敌方弹幕", "弹幕固定映射")
	ui.free()
