extends SceneTree

## Minimal CPU-only regression runner for the TrackMask interaction slice.
## It avoids loading the complete game/art suite while iterating on contact
## rasterisation.  The repository wrapper remains the release gate.

const TEST_FILES := [
	"res://tests/unit/test_footprint_visual_profile.gd",
	"res://tests/unit/test_track_mask.gd",
	"res://tests/unit/test_snow_interaction.gd",
]


func _initialize() -> void:
	var passed := 0
	var failed := 0
	for path in TEST_FILES:
		var script: GDScript = load(path)
		if script == null:
			failed += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var method_name: StringName = method.get("name", &"")
			if not String(method_name).begins_with("test_"):
				continue
			var instance = script.new()
			instance.reset_failures()
			instance.before_each()
			instance.call(method_name)
			instance.after_each()
			if instance.failures().is_empty() and instance.assertion_count() > 0:
				passed += 1
			else:
				failed += 1
				for failure in instance.failures():
					print("FAIL %s :: %s -- %s" % [path.get_file(), method_name, failure])
	print("snow interaction focused: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
