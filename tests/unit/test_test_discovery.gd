extends TestCase

## Covers the discovery/introspection rule the runner depends on to avoid
## silently skipping a test file that failed to parse (see test_runner.gd's
## "no tests found" failure branch). Broken sources are built in memory via
## GDScript.new() + source_code + reload() rather than committed to disk,
## so the repo never carries a permanently-malformed .gd file.

const TestDiscovery := preload("res://tests/framework/test_discovery.gd")

func _build_script(source: String) -> Dictionary:
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	return {"script": script, "err": err}

func test_test_methods_returns_only_test_prefixed_methods() -> void:
	var built := _build_script(
		"extends RefCounted\n" +
		"func test_one() -> void:\n\tpass\n" +
		"func test_two() -> void:\n\tpass\n" +
		"func helper() -> void:\n\tpass\n"
	)
	assert_eq(built["err"], OK, "well-formed source must compile cleanly")
	var methods := TestDiscovery.test_methods(built["script"])
	assert_eq(methods.size(), 2, "only the two test_-prefixed methods must be returned")
	assert_true(methods.has("test_one"), "test_one must be found")
	assert_true(methods.has("test_two"), "test_two must be found")
	assert_false(methods.has("helper"), "non-test methods must be excluded")

func test_test_methods_is_empty_for_a_script_that_failed_to_parse() -> void:
	var built := _build_script(
		"extends RefCounted\n" +
		"func test_broken(:\n\tpass\n"
	)
	assert_true(built["err"] != OK, "malformed source must fail to compile")
	var methods := TestDiscovery.test_methods(built["script"])
	assert_true(methods.is_empty(), "a script that failed to parse must report zero test methods -- this is precisely the condition the runner must now fail on")

func test_test_methods_is_empty_for_a_well_formed_script_with_no_tests() -> void:
	var built := _build_script(
		"extends RefCounted\n" +
		"func helper() -> void:\n\tpass\n"
	)
	assert_eq(built["err"], OK, "well-formed source must compile cleanly")
	var methods := TestDiscovery.test_methods(built["script"])
	assert_true(methods.is_empty(), "a script with no test_ methods must report zero test methods even though it parsed fine")

func test_find_test_scripts_on_missing_root_returns_empty() -> void:
	var found := TestDiscovery.find_test_scripts("res://tests/unit/__does_not_exist__")
	assert_true(found.is_empty(), "a missing root must yield no discovered scripts, not an error")
