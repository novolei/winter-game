extends TestCase

## The farmhouse is now standing in the world, and putting it there is the one
## edit that can quietly break the interior-reveal contract without touching the
## model at all: a node renamed in scenes/main.tscn, or the placement pointed at
## a different file, and FH_Fade_Roof stops resolving. Nothing would report it
## -- the building simply keeps its roof on when the player walks inside, in a
## wave that has not been written yet, so the failure would surface months from
## now with no clue attached.
##
## tests/art/test_farmhouse_model.gd guards the names inside the .glb. This
## guards the other half: that the scene really places that .glb, and that the
## names survive being instanced under a parent.

const MAIN_SCENE := "res://scenes/main.tscn"
const MODEL_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"
const FARMHOUSE_SCRIPT := "res://src/entities/farmhouse.gd"

const ModelTest := preload("res://tests/art/test_farmhouse_model.gd")


## The node in main.tscn carrying the placement script, and the resource its
## child is an instance of. Walked off SceneState rather than instantiated: the
## main scene builds a 512-square noise field and a 320-subdivision terrain mesh
## on _ready(), which a naming test has no business paying for.
func _placement() -> Dictionary:
	var found := {"script": false, "instances": PackedStringArray(), "transform": Transform3D()}
	var resource := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return found
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		var instance := state.get_node_instance(node)
		if instance != null:
			found["instances"].append(instance.resource_path)
		for property in range(state.get_node_property_count(node)):
			var value = state.get_node_property_value(node, property)
			if value is Script and (value as Script).resource_path == FARMHOUSE_SCRIPT:
				found["script"] = true
			if state.get_node_property_name(node, property) == "transform" and value is Transform3D:
				if state.get_node_name(node) == "Farmhouse":
					found["transform"] = value
	return found


func test_the_main_scene_places_the_farmhouse() -> void:
	var placement := _placement()
	assert_true(placement["script"], "%s holds no node running %s" % [MAIN_SCENE, FARMHOUSE_SCRIPT])
	assert_true(
		placement["instances"].has(MODEL_PATH),
		"%s must instance %s; it instances %s" % [MAIN_SCENE, MODEL_PATH, ", ".join(placement["instances"])]
	)


## Near the player's start, and not on top of it. The upper bound is what makes
## this a real assertion: the terrain has no flat ground close to the origin, so
## the site was chosen a short walk away, and a later edit that drags the house
## out to the edge of the field should have to argue for itself.
func test_the_farmhouse_stands_near_the_player_start() -> void:
	var placement := _placement()
	var spot: Vector3 = (placement["transform"] as Transform3D).origin
	var distance := Vector2(spot.x, spot.z).length()
	assert_true(distance > 6.0, "the farmhouse is %.1f m from the player's start, close enough to spawn inside it" % distance)
	assert_true(distance < 30.0, "the farmhouse is %.1f m from the player's start, further than a short walk" % distance)
	assert_almost_eq(spot.y, 0.0, 0.001, "the placement must leave y to Farmhouse._settle(), which reads the terrain at runtime")


## The scene decides what fades; this test decides that it still agrees with
## what the model test calls faded.
##
## This used to compare src/entities/farmhouse.gd's own hardcoded REVEAL_GROUPS
## against the model test's. That constant is gone: the list is authored on the
## InteriorReveal in scenes/main.tscn now, because it has to be per-building
## data before wave 4 adds four more buildings. So the pair being compared has
## changed, and the property is unchanged and slightly stronger -- one of the
## two ends is now the scene that actually ships rather than a third copy of
## the list sitting in a script.
##
## tests/art/test_interior_reveal_wiring.gd checks the same authored list
## against the .glb itself, so the chain runs scene -> model test -> mesh names.
func test_the_scene_fades_exactly_what_the_model_test_calls_faded() -> void:
	var authored := PackedStringArray()
	var resource := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource is PackedScene, "%s did not load as a PackedScene" % MAIN_SCENE)
	if not (resource is PackedScene):
		return
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) != "fade_parts":
				continue
			for name in state.get_node_property_value(node, property):
				authored.append(String(name))
	assert_eq(
		Array(authored), Array(ModelTest.REVEAL_GROUPS),
		"%s fades %s; tests/art/test_farmhouse_model.gd says the fade set is %s"
			% [MAIN_SCENE, ", ".join(authored), ", ".join(ModelTest.REVEAL_GROUPS)]
	)


## Instanced, not merely present in the file: find_child() with owned = false is
## how the placement script and the future reveal system will reach these, and a
## group that is in the .glb but unreachable through an instance is the failure
## this is here to catch.
func test_every_reveal_group_is_reachable_through_an_instance() -> void:
	var resource := ResourceLoader.load(MODEL_PATH)
	assert_true(resource is PackedScene, "%s did not load as a PackedScene" % MODEL_PATH)
	if not (resource is PackedScene):
		return
	var model := (resource as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.add_child(model)
	for group in ModelTest.REVEAL_GROUPS:
		assert_not_null(
			holder.find_child(group, true, false),
			"%s is not reachable under an instanced farmhouse; the reveal system addresses it by that name" % group
		)
	# Node is not reference counted (briefing section 2.2); freeing the holder
	# takes the instanced model with it.
	holder.free()
