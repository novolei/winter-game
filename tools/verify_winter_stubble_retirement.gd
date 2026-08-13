extends SceneTree

const StubbleRetirement := preload("res://tests/art/test_winter_stubble_retirement.gd")

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var subject: TestCase = StubbleRetirement.new()
	subject.reset_failures()
	subject.before_each()
	subject.test_the_retired_upright_stubble_script_no_longer_ships()
	subject.test_main_scene_has_no_node_using_the_retired_stubble()
	subject.test_farmstead_baked_stubble_remains_the_canonical_field_evidence()
	subject.after_each()
	var failures := subject.failures()
	if failures.is_empty():
		print("winter_stubble_retirement: 3 focused checks passed")
		quit(0)
		return true
	for failure in failures:
		push_error("winter_stubble_retirement: %s" % failure)
	quit(1)
	return true
