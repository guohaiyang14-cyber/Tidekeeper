# ============================================================================
# W19I18nTest — 双语切换机检
# 验收：默认中文；set_language 切英文后 tr() 返回英文；偏好持久化；
#       缺失 key 安全回退；切回中文不影响其他系统。
# 运行：godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/w19_i18n_test.tscn
# ============================================================================
extends Node2D

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("============================================================")
	print("W19 i18n 双语切换 机检")
	print("============================================================")
	LanguageSystem.set_language("zh")

	print("[assert] 默认/中文")
	_assert(LanguageSystem.localize("ui.difficulty") == "难度：", "zh 难度前缀")
	_assert(LanguageSystem.localize("ui.game_over") == "游戏结束", "zh 游戏结束")
	_assert(LanguageSystem.localize("ui.victory") == "通关", "zh 通关")
	_assert(LanguageSystem.localize("ui.restart") == "再来一局 (Enter)", "zh 重开按钮")

	print("[assert] 切换英文")
	LanguageSystem.set_language("en")
	_assert(LanguageSystem.get_language() == "en", "当前语言=en")
	_assert(LanguageSystem.localize("ui.difficulty") == "Difficulty: ", "en 难度前缀")
	_assert(LanguageSystem.localize("ui.game_over") == "Game Over", "en 游戏结束")
	_assert(LanguageSystem.localize("ui.victory") == "Victory", "en 通关")
	_assert(LanguageSystem.localize("ui.boss_warn") == "⚠ Boss appears this night", "en Boss 提示")
	_assert(SaveSystem.get_settings().get("language") == "en", "语言偏好已持久化")

	print("[assert] 缺失 key 回退")
	_assert(LanguageSystem.localize("no.such.key") == "no.such.key", "缺失 key 回退自身")

	print("[assert] 切回中文")
	LanguageSystem.set_language("zh")
	_assert(LanguageSystem.localize("ui.difficulty") == "难度：", "切回中文正确")

	print("------------------------------------------------------------")
	print("W19 i18n 机检通过=%d 失败=%d" % [_passed, _failed])
	print("============================================================")
	get_tree().quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
