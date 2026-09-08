# ============================================================================
# BotSuite — TestBot 验收任务预设（对齐 docs/原型验证验收清单.md）
# 职责：解析 --bot-suite / 角色 / 难度 / 夜上限 / 局数上限；打印 ACCEPT 行供工具汇总
# 红线：仅 Debug Bot；不改玩法数值；清单 id 与文档编号一致
# ============================================================================
class_name BotSuite
extends RefCounted

const SUITE_VALUES: Array[String] = ["smoke", "crash", "full", "meta", "acceptance"]
const CHAR_VALUES: Array[String] = ["watcher", "blacksmith", "stargazer", "cycle", "random"]
const DIFF_VALUES: Array[String] = ["lighthouse", "watcher", "cycle"]
const CHAR_CYCLE: Array[String] = ["watcher", "blacksmith", "stargazer"]
const DIFF_CYCLE: Array[String] = ["watcher", "lighthouse"]

## suite → 默认参数（显式 CLI / 环境变量优先覆盖）
## lighthouse 空串 = 不覆盖（沿用原 random 默认）
const SUITE_DEFAULTS: Dictionary = {
	"smoke": {
		"character": "watcher",
		"difficulty": "lighthouse",
		"lighthouse": "none",
		"max_night": 10,
		"max_runs": 3,
		"unlock_all": false,
		"runs_per_config": 1,
		"checklist": ["1.1.1", "1.1.2", "1.2.3", "3.3", "5.2"],
	},
	"crash": {
		"character": "watcher",
		"difficulty": "lighthouse",
		"lighthouse": "none",
		"max_night": 8,
		"max_runs": 3,
		"unlock_all": false,
		"runs_per_config": 1,
		"checklist": ["5.2", "3.3"],
	},
	"full": {
		"character": "watcher",
		"difficulty": "lighthouse",
		"lighthouse": "random",
		"max_night": 20,
		"max_runs": 5,
		"unlock_all": false,
		"runs_per_config": 1,
		"checklist": ["1.1.1", "1.1.2", "3.3", "2.5.3", "4.10.1", "5.2"],
	},
	"meta": {
		"character": "cycle",
		"difficulty": "cycle",
		"lighthouse": "cycle",
		"max_night": 12,
		"max_runs": 9,
		"unlock_all": true,
		"runs_per_config": 1,
		"checklist": ["4.6.1", "4.6.3", "4.6.5", "4.8.1", "1.2.3"],
	},
	"acceptance": {
		"character": "watcher",
		"difficulty": "lighthouse",
		"lighthouse": "sweep",
		"max_night": 20,
		"max_runs": 6,
		"unlock_all": false,
		"runs_per_config": 2,
		"checklist": [
			"1.1.1", "1.1.2", "1.2.1", "1.2.3", "3.3", "5.2",
			"4.5.2", "4.5.3", "4.2.8", "2.5.3",
		],
	},
}


static func resolve_suite_name() -> String:
	var from_cli: String = _parse_kv("--bot-suite")
	if from_cli != "" and from_cli in SUITE_VALUES:
		return from_cli
	if from_cli != "":
		push_warning("[TestBot] 非法 --bot-suite=%s，忽略" % from_cli)
	if OS.has_environment("TIDEKEEPER_BOT_SUITE"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_SUITE").strip_edges().to_lower()
		if env_raw in SUITE_VALUES:
			return env_raw
		if env_raw != "":
			push_warning("[TestBot] 非法 TIDEKEEPER_BOT_SUITE=%s，忽略" % env_raw)
	return ""


static func suite_defaults(suite: String) -> Dictionary:
	if SUITE_DEFAULTS.has(suite):
		return (SUITE_DEFAULTS[suite] as Dictionary).duplicate(true)
	return {}


static func resolve_character(suite_default: String = "") -> String:
	var from_cli: String = _parse_kv("--bot-character")
	if from_cli != "" and from_cli in CHAR_VALUES:
		return from_cli
	if from_cli != "":
		push_warning("[TestBot] 非法 --bot-character=%s，回落 suite/默认" % from_cli)
	if OS.has_environment("TIDEKEEPER_BOT_CHARACTER"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_CHARACTER").strip_edges().to_lower()
		if env_raw in CHAR_VALUES:
			return env_raw
	if suite_default != "" and suite_default in CHAR_VALUES:
		return suite_default
	# 无 suite / 无 CLI：沿用旧逻辑（当前已解锁角色）
	return "auto"


static func resolve_difficulty(suite_default: String = "") -> String:
	var from_cli: String = _parse_kv("--bot-difficulty")
	if from_cli != "" and from_cli in DIFF_VALUES:
		return from_cli
	if from_cli != "":
		push_warning("[TestBot] 非法 --bot-difficulty=%s，回落 suite/默认" % from_cli)
	if OS.has_environment("TIDEKEEPER_BOT_DIFFICULTY"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_DIFFICULTY").strip_edges().to_lower()
		if env_raw in DIFF_VALUES:
			return env_raw
	if suite_default != "" and suite_default in DIFF_VALUES:
		return suite_default
	# 无 suite：不强制改难度
	return "auto"


static func resolve_max_night(suite_default: int = 0) -> int:
	var from_cli: int = _parse_int_kv("--bot-max-night")
	if from_cli >= 0:
		return from_cli
	if OS.has_environment("TIDEKEEPER_BOT_MAX_NIGHT"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_MAX_NIGHT").strip_edges()
		if env_raw.is_valid_int():
			return maxi(0, env_raw.to_int())
	return maxi(0, suite_default)


static func resolve_max_runs(suite_default: int = 0) -> int:
	var from_cli: int = _parse_int_kv("--bot-max-runs")
	if from_cli >= 0:
		return from_cli
	if OS.has_environment("TIDEKEEPER_BOT_MAX_RUNS"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_MAX_RUNS").strip_edges()
		if env_raw.is_valid_int():
			return maxi(0, env_raw.to_int())
	return maxi(0, suite_default)


## 若 CLI/ENV 已给 --bot-lighthouse 则返回空（由 TestBot 原逻辑解析）；否则返回 suite 默认
static func suite_lighthouse_if_unset(suite_lh: String) -> String:
	if _parse_kv("--bot-lighthouse") != "":
		return ""
	if OS.has_environment("TIDEKEEPER_BOT_LIGHTHOUSE"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_LIGHTHOUSE").strip_edges()
		if env_raw != "":
			return ""
	return suite_lh


static func suite_runs_per_config_if_unset(suite_n: int) -> int:
	if _parse_int_kv("--bot-runs-per-config") > 0:
		return -1
	if OS.has_environment("TIDEKEEPER_BOT_RUNS_PER_CONFIG"):
		var env_raw: String = OS.get_environment("TIDEKEEPER_BOT_RUNS_PER_CONFIG").strip_edges()
		if env_raw.is_valid_int():
			return -1
	return maxi(1, suite_n)


static func emit_accept(id: String, status: String, detail: String = "") -> void:
	var safe_status: String = status if status in ["pass", "fail", "skip", "info"] else "info"
	if detail.strip_edges() == "":
		print("[TestBot] ACCEPT id=%s status=%s" % [id, safe_status])
	else:
		print("[TestBot] ACCEPT id=%s status=%s detail=%s" % [id, safe_status, detail.replace(" ", "_")])


static func expected_night_duration(night: int) -> float:
	return DayNightStateMachine.duration_for_night(night)


static func _parse_kv(flag: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_args()
	var prefix: String = flag + "="
	for i in args.size():
		var arg: String = args[i]
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges().to_lower()
		if arg == flag and i + 1 < args.size():
			return String(args[i + 1]).strip_edges().to_lower()
	return ""


static func _parse_int_kv(flag: String) -> int:
	var raw: String = _parse_kv(flag)
	if raw == "":
		return -1
	if raw.is_valid_int():
		return maxi(0, raw.to_int())
	push_warning("[TestBot] 非法 %s=%s" % [flag, raw])
	return -1
