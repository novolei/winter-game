extends TestCase

## The retired upright 62 x 32 m stubble patch was a local rectangular
## MultiMesh, not a map-streaming boundary. Farmstead's deterministic marks
## baked into TrackMask remain the canonical field evidence. This guard bans
## only that retired implementation so a future, separately reviewed ground
## treatment cannot be confused with it.

const MAIN_SCENE := "res://scenes/main.tscn"
const RETIRED_SCRIPT := "res://src/entities/winter_stubble.gd"
const RETIRED_NODE := &"WinterStubble"
const FarmsteadScript := preload("res://src/entities/farmstead.gd")


func test_the_retired_upright_stubble_script_no_longer_ships() -> void:
	assert_false(
		ResourceLoader.exists(RETIRED_SCRIPT),
		"the retired 62 x 32 m upright stubble patch must not ship at %s" % RETIRED_SCRIPT
	)


func test_main_scene_has_no_node_using_the_retired_stubble() -> void:
	var scene: PackedScene = ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(scene, "%s must remain loadable" % MAIN_SCENE)
	if scene == null:
		return
	var state := scene.get_state()
	var offenders := PackedStringArray()
	for index in range(state.get_node_count()):
		var name: StringName = state.get_node_name(index)
		if name == RETIRED_NODE:
			offenders.append(str(name))
		for property in range(state.get_node_property_count(index)):
			var value: Variant = state.get_node_property_value(index, property)
			if value is Script and (value as Script).resource_path == RETIRED_SCRIPT:
				offenders.append(str(name))
	assert_eq(
		offenders.size(), 0,
		"%s still contains retired upright stubble on %s" % [MAIN_SCENE, ", ".join(offenders)]
	)


func test_farmstead_baked_stubble_remains_the_canonical_field_evidence() -> void:
	var farmstead: Farmstead = FarmsteadScript.new()
	assert_true(farmstead.has_method(&"_bake_stubble"), "Farmstead must retain its TrackMask bake path")
	assert_true(farmstead.stubble_rows > 0, "the baked field needs deterministic rows of snow marks")
	assert_true(farmstead.stubble_per_row > 0, "the baked field needs deterministic marks within each row")
	farmstead.free()
