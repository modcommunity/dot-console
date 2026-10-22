extends Node

## The yml layout of dot-console's settings: the new path, the flat shim and the operator's layer.
##
## [codeblock]
## timeout 120 godot --headless --path . res://examples/cfg_selftest.tscn
## [/codeblock]

const FOLDER := "dot_console"
const FILE := "console.yml"
const LEGACY := "user://dot_console_cfg_selftest_legacy"

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-console cfg self-test")
	var addon_dir := "user://cfg/addons/" + FOLDER
	var server_dir := "user://cfg/server/addons/" + FOLDER
	_clean(addon_dir, server_dir)
	DotCfgLegacy.reset()

	_write(LEGACY.path_join(FILE), "scrollback_lines: 1000\nfont_size: 20\n")
	var config := DotConsoleConfig.new()
	var res := config.load_cfg(FILE, LEGACY)
	_check(res.ok and config.scrollback_lines == 1000, "only the flat file: it is still read")
	_check(DotCfgLegacy.warned_count() == 1, "and warned once")
	DotConsoleConfig.new().load_cfg(FILE, LEGACY)
	_check(DotCfgLegacy.warned_count() == 1, "a second load does not warn again")

	_write(addon_dir.path_join(FILE), "scrollback_lines: 2000\n")
	config = DotConsoleConfig.new()
	res = config.load_cfg(FILE, LEGACY)
	_check(res.ok and config.scrollback_lines == 2000, "the new path wins over the flat file")
	_check(config.font_size == DotConsoleConfig.new().font_size, "and the two are never merged")

	_write(server_dir.path_join(FILE), "scrollback_lines: 3000\n")
	config = DotConsoleConfig.new()
	res = config.load_cfg(FILE, LEGACY)
	_check(res.ok and config.scrollback_lines == 3000, "the operator's server layer wins")

	_clean(addon_dir, server_dir)
	DotCfgLegacy.reset()
	_write("user://cfg/server/" + FOLDER + "/" + FILE, "scrollback_lines: 4000\n")
	config = DotConsoleConfig.new()
	res = config.load_cfg(FILE, LEGACY)
	_check(res.ok and config.scrollback_lines == 4000, "the old cfg/server/dot_console/ still loads")
	_check(DotCfgLegacy.warned_count() == 1, "and warns once")
	DotPaths.remove_tree("user://cfg/server/" + FOLDER)

	_clean(addon_dir, server_dir)
	DotCfgLegacy.reset()
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _clean(addon_dir: String, server_dir: String) -> void:
	DotPaths.remove_tree(addon_dir)
	DotPaths.remove_tree(server_dir)
	DotPaths.remove_tree(LEGACY)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("   ok   ", what)
	else:
		_failed += 1
		print("  FAIL  ", what)
