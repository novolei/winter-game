extends SceneTree

## Headless test runner.
## Run: godot --headless --path <project> --script res://tests/framework/test_runner.gd
## Exits 0 when everything passes, 1 when anything fails.
##
## The suite runs from _process(), not _initialize(). Autoloads ARE
## instantiated under --script and /root is populated during _initialize(),
## but a node added there does not receive _ready() until the tree ticks --
## so a test that needs a system's _ready() to have run would otherwise see
## an unwired object and quietly pass.
##
## Tests still build their subjects with preload(...).new(): not because the
## autoload is missing, but because a test reaching for the live singleton
## tests the singleton rather than the unit, and inherits state from every
## test before it.

const TEST_ROOTS: Array[String] = ["res://tests/unit", "res://tests/art"]
const TestDiscovery := preload("res://tests/framework/test_discovery.gd")

## The floor for how many tests must actually execute.
##
## RAISE THIS WHENEVER TESTS ARE ADDED. It is not a target and not a count to
## be proud of -- it is a tripwire, and its only job is to notice that tests
## which used to run have stopped running.
##
## Every other guard in this runner judges tests it observed. None of them can
## see a test that never ran at all. If script.new() errors, the very next
## line here aborts _run_file(), that file's remaining methods are skipped in
## silence, the loop moves on, and the report prints "N passed, 0 failed" with
## quit(0) over a suite that lost a whole file. Nothing compared N against
## anything -- so an empty suite was indistinguishable from a passing one.
const MINIMUM_TESTS := 900

var _passed := 0
var _failed := 0
var _failure_log: PackedStringArray = []

func _initialize() -> void:
	print("")
	print("WinterTime test run")
	print("=".repeat(60))

## The suite runs on the first _process iteration, NOT in _initialize(), and
## that placement is load-bearing.
##
## Under --script the SceneTree object already exists during _initialize(),
## but its root Window is not yet inside the tree. Measured on 4.7.1, in
## _initialize(): root.is_inside_tree() is false, root.get_tree() is null,
## add_child() does NOT fire _ready() on the child, and any absolute-path
## lookup fails outright with "Can't use get_node() with absolute paths from
## outside the active scene tree". By the first _process() call every one of
## those works normally.
##
## So any test of how one node finds another at runtime -- see the trap-3
## regression test in test_world_clock.gd, which is the reason this moved --
## is impossible in the first phase and routine in the second. Returning true
## ends the run after exactly one pass.
##
## Note the loop variable is `test_root`, not `root`: `root` is SceneTree's
## own property, and shadowing it here would be a trap for the next reader.
func _process(_delta: float) -> bool:
	for test_root in TEST_ROOTS:
		for path in TestDiscovery.find_test_scripts(test_root):
			_run_file(path)
	_check_minimum()
	_print_report()
	quit(1 if _failed > 0 else 0)
	return true

func _check_minimum() -> void:
	var total := _passed + _failed
	if total >= MINIMUM_TESTS:
		return
	_failed += 1
	_failure_log.append(
		"  <suite> :: <minimum> -- only %d test(s) ran, but MINIMUM_TESTS is %d. Tests that used to run are being skipped silently; find the file that stopped loading, do not just lower the constant." % [total, MINIMUM_TESTS]
	)

func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failed += 1
		_failure_log.append("  %s :: <load> -- could not load script" % path)
		return
	var methods := TestDiscovery.test_methods(script)
	if methods.is_empty():
		_failed += 1
		_failure_log.append("  %s :: <no tests> -- no test methods found; the file may have failed to parse" % path)
		return
	for method_name in methods:
		var instance = script.new()
		instance.reset_failures()
		instance.before_each()
		instance.call(method_name)
		instance.after_each()
		var fails: Array[String] = []
		fails.append_array(instance.failures())
		# A test that executed no assertion proves nothing. Either it is
		# empty, or a GDScript runtime error aborted it partway -- the VM
		# drops the rest of the function and returns, leaving an empty
		# failure list that would otherwise be reported as a PASS.
		if instance.assertion_count() == 0:
			fails.append("no assertions executed -- the test is empty, or a runtime error aborted it partway")
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
