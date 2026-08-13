extends TestCase

## A rendered shadow is the acceptance surface here.  The static checks below
## do not pretend to judge an image; they pin the reproducible main-scene
## shutter and the verified narrow-penumbra contract so a future lighting edit
## cannot silently remove the evidence and reintroduce the ripple pattern.

const CAPTURE_SCENE_PATH := "res://tools/capture_shadow_ripple_ab.tscn"
const CAPTURE_SCRIPT_PATH := "res://tools/capture_shadow_ripple_ab.gd"
const DIRECTOR_PATH := "res://src/rendering/lighting_director.gd"


func test_the_ripple_probe_runs_the_real_main_scene_at_one_camera() -> void:
	assert_true(
		FileAccess.file_exists(CAPTURE_SCENE_PATH),
		"missing the real-main-scene shadow ripple capture: %s" % CAPTURE_SCENE_PATH
	)
	assert_true(
		FileAccess.file_exists(CAPTURE_SCRIPT_PATH),
		"missing the shadow ripple A/B controls: %s" % CAPTURE_SCRIPT_PATH
	)
	var scene_code := FileAccess.get_file_as_string(CAPTURE_SCENE_PATH)
	var script_code := FileAccess.get_file_as_string(CAPTURE_SCRIPT_PATH)
	assert_true(
		scene_code.contains("res://scenes/main.tscn"),
		"the shadow probe must instance the game, not a lighting mock"
	)
	for mode in [
		"no_terrain_cast",
		"no_shadows",
		"no_grain",
		"flat_ground",
		"no_penumbra",
		"penumbra_030",
	]:
		assert_true(
			script_code.contains('"%s"' % mode),
			"the A/B probe lost the '%s' control needed to isolate the ripple" % mode
		)


func test_the_shipping_penumbra_is_narrow_and_the_capture_can_prove_it() -> void:
	var code := FileAccess.get_file_as_string(DIRECTOR_PATH)
	assert_false(code.is_empty(), "missing LightingDirector: %s" % DIRECTOR_PATH)
	assert_true(
		code.contains("@export var sun_angular_softness := 0.3"),
		"the directional penumbra is no longer the 0.30-degree, capture-verified ripple-free value"
	)
	assert_true(
		code.contains("_sun.shadow_blur = 0.5"),
		"the constant blur no longer matches the narrow verified penumbra"
	)
	assert_true(
		int(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			-1
		)) >= 3,
		"the directional filter must retain enough PCF samples for a soft tree-shadow silhouette"
	)
