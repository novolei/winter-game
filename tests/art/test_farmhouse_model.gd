extends TestCase

## The farmhouse is the hero building -- the player's home, the closest thing
## to the camera, the one warm window, and the only model the interior-reveal
## system takes apart. Two things about it are contracts rather than art
## choices, and neither is checked anywhere else.
##
## 1. THE GROUP NAMES. The reveal system fades a fixed list of parts when the
##    player crosses the threshold. That list is names, not indices, so that
##    re-running tools/blender/build_farmhouse.py -- which is how this model is
##    edited (Art Bible section 5.1) -- cannot silently renumber it. Rename or
##    regroup a part and the game keeps a wall in front of the camera, with no
##    error anywhere: the failure is a rendering one, seen only by a human
##    walking into the house.
##
## 2. THE WHOLE-BUILDING TRIANGLE COUNT. tests/art/test_topology.gd is a
##    *per-mesh* gate: it judges each mesh in a file against its folder's
##    budget. This building is nine meshes, one per reveal group, so every one
##    of them is comfortably inside any per-mesh budget while the building
##    could be several times over. Rule 6's 1,500 is a budget for the *asset*,
##    and this is where the asset is added up. (The general hole is recorded in
##    Docs/DEFERRED.md -- every multi-mesh asset has it, not just this one.)

const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

const MODEL_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"

## Art Bible section 2 rule 6: the hero building gets 1,500 where every other
## building gets 500, because the reference house cannot be built with a porch
## for less.
const HERO_BUDGET := 1500

## Faded when the player steps inside. Keep in step with DEFAULT_REVEAL in
## tools/blender/build_farmhouse.py and with the authored list in
## scenes/main.tscn, which tests/art/test_interior_reveal_wiring.gd checks
## against the .glb itself.
##
## ALL FIVE, and the last two were the open question the farmhouse task left.
## It built FH_Fade_SideLeft and FH_Fade_Divider addressable but out of the
## default set, because the camera's final yaw and pitch were not fixed yet.
## They are now -- CameraRig is orthographic, pitched 45 and yawed -35 -- and
## that camera looks at this building from off its front-LEFT corner, so the
## -X walls face the lens exactly as the +Z ones do. Shot both ways at game
## framing:
##
##   * with FH_Fade_SideLeft standing, the left wall covers about a third of
##     the room's width from the inside, and the two things it hides are the
##     bed and the chest -- one of them a station GDD section 4 needs the
##     player to reach every night;
##   * with FH_Fade_Divider standing, the wing is not visible at all. The
##     player walks through the doorway and vanishes behind a wall, under a
##     camera that cannot move to look round it.
##
## The divider was the more interesting call, because it is what makes the
## interior read as rooms rather than one shed. It loses to the second point
## above: losing the character is a harder failure than losing the read.
const REVEAL_GROUPS: Array[String] = [
	"FH_Fade_Roof",
	"FH_Fade_Front",
	"FH_Fade_Porch",
	"FH_Fade_SideLeft",
	"FH_Fade_Divider",
	# The hinged leaf. It fades with the facade it sits in -- an open door left
	# standing after the front wall had gone would be a rectangle floating in
	# the snow -- but it is its own object because it is the one part of this
	# building that moves. Its origin is on the hinge stile; see DOOR_HINGE in
	# tools/blender/build_farmhouse.py and src/entities/interior/door.gd.
	"FH_Door",
]

## Never faded.
const KEPT_GROUPS: Array[String] = [
	"FH_Shell",
	"FH_Porch",
	"FH_Room",
	"FH_Furniture",
]


## Every node in the imported model that carries a Mesh, by name.
##
## Read off PackedScene.get_state() rather than instantiate(): a SceneState is
## walked without building a node tree, so this test allocates no Node and has
## nothing to free (briefing section 2.2). Same reasoning, and same technique,
## as tests/framework/asset_probe.gd.
func _mesh_node_names() -> PackedStringArray:
	var names := PackedStringArray()
	var resource := ResourceLoader.load(MODEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return names
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			var value = state.get_node_property_value(node, property)
			if value is Mesh:
				names.append(state.get_node_name(node))
				break
	return names


func test_the_model_is_importable() -> void:
	var resource := ResourceLoader.load(MODEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(resource, "%s must import as a PackedScene; if this is null it has never been imported" % MODEL_PATH)
	assert_true(resource is PackedScene, "%s must import as a PackedScene" % MODEL_PATH)


func test_every_reveal_group_is_in_the_model() -> void:
	var names := _mesh_node_names()
	for group in REVEAL_GROUPS:
		assert_true(
			names.has(group),
			"the reveal system fades %s by name, and no mesh in %s is called that; it holds %s" % [group, MODEL_PATH, ", ".join(names)]
		)


func test_every_kept_group_is_in_the_model() -> void:
	var names := _mesh_node_names()
	for group in KEPT_GROUPS:
		assert_true(
			names.has(group),
			"%s is missing from %s; it holds %s" % [group, MODEL_PATH, ", ".join(names)]
		)


## The other half of the contract, and the half that is easy to forget: a part
## that belongs to no group is a part the reveal system cannot address, so it
## stays solid in front of the camera forever. The group list must be total.
func test_the_model_holds_no_ungrouped_mesh() -> void:
	var known := REVEAL_GROUPS + KEPT_GROUPS
	var strays := PackedStringArray()
	for name in _mesh_node_names():
		if not known.has(name):
			strays.append(name)
	assert_eq(strays.size(), 0, "every mesh must be in a named group; these are in none: %s" % ", ".join(strays))


func test_the_whole_building_is_within_the_hero_budget() -> void:
	var probe := AssetProbeScript.probe(MODEL_PATH)
	assert_eq(probe["error"], "", "%s could not be read: %s" % [MODEL_PATH, probe["error"]])
	var total := 0
	for entry in probe["meshes"]:
		var mesh: Mesh = entry["resource"]
		var faces := mesh.get_faces()
		total += faces.size() / 3
	# A zero here would mean the walk found nothing and the budget check below
	# passed by inspecting an empty list, which is the failure mode this whole
	# suite exists to prevent.
	assert_true(total > 0, "no triangles were counted in %s at all" % MODEL_PATH)
	assert_true(
		total <= HERO_BUDGET,
		"the farmhouse is %d triangles, over the %d hero budget" % [total, HERO_BUDGET]
	)
