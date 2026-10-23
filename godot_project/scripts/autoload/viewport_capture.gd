# ============================================================================
# ViewportCapture — 视口定时截图工具（调试/视觉验证用，默认关闭）
# 启用：命令行加 --capture-interval=<秒> [--capture-dir=<user:// 子目录名>]
# 输出：user://<capture-dir>/shot_XXX.png（默认 user://captures/）
# 说明：直接从根视口纹理取图，不依赖窗口焦点/前台状态（PrintWindow 对 Godot
#       GPU 渲染窗口会截到全黑，故用此途径）；headless 下无渲染则不产出。
#       无开关时 set_process(false)，零开销；33 个机检场景不受影响。
# ============================================================================
extends Node

var _enabled: bool = false
var _interval: float = 5.0
var _dir_name: String = "captures"
var _elapsed: float = 0.0
var _count: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var interval_str: String = ""
	for i in args.size():
		var a: String = str(args[i])
		if a.begins_with("--capture-interval="):
			interval_str = a.trim_prefix("--capture-interval=")
		elif a == "--capture-dir" and i + 1 < args.size():
			_dir_name = _sanitize(str(args[i + 1]))
		elif a.begins_with("--capture-dir="):
			_dir_name = _sanitize(a.trim_prefix("--capture-dir="))
	if interval_str.is_empty():
		set_process(false)
		return
	_interval = clampf(float(interval_str), 0.5, 60.0)
	_enabled = true
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists(_dir_name):
		dir.make_dir_recursive(_dir_name)
	print("[ViewportCapture] enabled interval=%.1fs dir=user://%s" % [_interval, _dir_name])


func _sanitize(name: String) -> String:
	var out := ""
	for c in name:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	return out if not out.is_empty() else "captures"


func _process(delta: float) -> void:
	if not _enabled:
		return
	_elapsed += delta
	if _elapsed < _interval:
		return
	_elapsed = 0.0
	_capture()


func _capture() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := "user://%s/shot_%03d.png" % [_dir_name, _count]
	var err := img.save_png(path)
	if err == OK:
		_count += 1
		print("[ViewportCapture] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		printerr("[ViewportCapture] save failed: ", path, " err=", err)
