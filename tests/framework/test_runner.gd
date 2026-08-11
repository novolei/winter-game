extends SceneTree

## Headless test runner.
## Run: godot --headless --path <project> --script res://tests/framework/test_runner.gd
## Exits 0 when everything passes, 1 when anything fails.
##
## NOTE: autoloads are NOT instantiated under --script. Tests must build
## their subjects directly with preload(...).new().

const TEST_ROOTS: Array[String] = ["res://tests/unit", "res://tests/art"]

var _passed := 0
var _failed := 0
var _failure_log: PackedStringArray = []

func _initialize() -> void:
	print("")
	print("WinterTime test run")
	print("=".repeat(60))
	for root in TEST_ROOTS:
		for path in _find_test_scripts(root):
			_run_file(path)
	_print_report()
	quit(1 if _failed > 0 else 0)

func _find_test_scripts(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_test_scripts(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failed += 1
		_failure_log.append("  %s :: <load> -- could not load script" % path)
		return
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("test_"):
			continue
		var instance = script.new()
		instance.reset_failures()
		instance.before_each()
		instance.call(method_name)
		instance.after_each()
		var fails: Array[String] = instance.failures()
		if fails.is_empty():
			_passed += 1
			print("  PASS  %s :: %s" % [path.get_file(), method_name])
		else:
			_failed += 1
			print("  FAIL  %s :: %s" % [path.get_file(), method_name])
			for f in fails:
				_failure_log.append("  %s :: %s -- %s" % [path.get_file(), method_name, f])

func _print_report() -> void:
	print("=".repeat(60))
	if not _failure_log.is_empty():
		print("FAILURES:")
		for line in _failure_log:
			print(line)
		print("")
	print("%d passed, %d failed" % [_passed, _failed])
	print("")
