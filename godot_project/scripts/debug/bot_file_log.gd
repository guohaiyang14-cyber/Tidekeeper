# ============================================================================
# BotFileLog — TestBot 详细日志落盘（Debug）
# 职责：把高频 [TestBot] STAT 等行写入 user://bot_logs/，避免控制台刷屏堵死管道
# 查看：python tools/view_bot_runs.py（默认优先读最新 bot_logs/session_*.log）
# ============================================================================
class_name BotFileLog
extends RefCounted

const DEFAULT_DIR: String = "user://bot_logs/"
## 每写多少行强制 flush（防崩溃丢尾）
const FLUSH_EVERY: int = 32
## 会话文件保留上限（与 CombatLog max_runs 量级接近）
const MAX_SESSION_FILES: int = 20

var _dir: String = DEFAULT_DIR
var _path: String = ""
var _file: FileAccess = null
var _lines_since_flush: int = 0


func open_session() -> String:
	close()
	_dir = DEFAULT_DIR
	var abs_dir: String = ProjectSettings.globalize_path(_dir)
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("[BotFileLog] 无法创建目录 %s (err=%d)" % [_dir, err])
		return ""
	var stamp: String = Time.get_datetime_string_from_system(true)
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	_path = _dir.path_join("session_%s.log" % stamp)
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("[BotFileLog] 无法创建: %s (err=%d)" % [_path, FileAccess.get_open_error()])
		_path = ""
		return ""
	_lines_since_flush = 0
	_prune_old_sessions()
	write_line("[BotFileLog] session_open path=%s" % _path)
	return _path


func is_open() -> bool:
	return _file != null


func get_path() -> String:
	return _path


## 只落盘，不打控制台
func write_line(line: String) -> void:
	if _file == null:
		return
	_file.store_string(line)
	if not line.ends_with("\n"):
		_file.store_string("\n")
	_lines_since_flush += 1
	if _lines_since_flush >= FLUSH_EVERY:
		flush()


## 落盘 + 控制台摘要（里程碑用）
func write_line_console(line: String) -> void:
	write_line(line)
	print(line)


func flush() -> void:
	if _file == null:
		return
	_file.flush()
	_lines_since_flush = 0


func close() -> void:
	if _file == null:
		return
	write_line("[BotFileLog] session_close")
	flush()
	_file.close()
	_file = null


func _prune_old_sessions() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(_dir)
	var da: DirAccess = DirAccess.open(abs_dir)
	if da == null:
		return
	var names: PackedStringArray = da.get_files()
	var sessions: Array[String] = []
	for n in names:
		var name: String = String(n)
		if name.begins_with("session_") and name.ends_with(".log"):
			sessions.append(name)
	if sessions.size() <= MAX_SESSION_FILES:
		return
	sessions.sort()
	var remove_n: int = sessions.size() - MAX_SESSION_FILES
	for i in range(remove_n):
		da.remove(sessions[i])
