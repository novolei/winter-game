extends TestCase

## The other half of the reveal. src/entities/interior/interior_reveal.gd is a
## component that knows nothing about any building; this checks that the
## farmhouse actually carries one, that the list it was authored with names
## real parts of the real model, and that the stove is standing in the room the
## reveal uncovers.
##
## All three failures this catches are silent ones:
##
##   * a name typo or a rename in the model -- the roof stays on, and the only
##     thing that reports it is a human walking into the house;
##   * a name that IS in the model but must never fade -- fade FH_Room and the
##     player walks on a hole; fade FH_Furniture and the stove disappears out
##     from under its own firelight;
##   * a threshold with no shape -- an Area3D that cannot be crossed, which is
##     indistinguishable from a reveal that is simply never triggered.
##
## Walked off PackedScene.get_state() rather than instantiate(): main.tscn
## builds a 512-square noise field and a 320-subdivision terrain mesh in
## _ready(), which a wiring test has no business paying for, and a SceneState
## walk allocates no Node and has nothing to free (briefing constraint 2).

const ModelTest := preload("res://tests/art/test_farmhouse_model.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const MODEL_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"
const REVEAL_SCRIPT := "res://src/entities/interior/interior_reveal.gd"
const STOVE_SCENE := "res://scenes/entities/stove/stove.tscn"

## The main room's interior, in the farmhouse model's own coordinates: the
## floor slab runs x -3.44 .. 3.44 and z -5.84 .. -0.16, with its top face at
## y 0.45. Anything the room is supposed to contain has to be in here.
const ROOM_MIN := Vector3(-3.44, 0.30, -5.84)
const ROOM_MAX := Vector3(3.44, 3.05, -0.16)


## Every node in main.tscn, as path -> {name, type, instance, properties}.
func _scene() -> Dictionary:
	var nodes := {}
	var resource := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return nodes
	var state := (resource as PackedScene).get_state()
	for index in range(state.get_node_count()):
		var properties := {}
		for property in range(state.get_node_property_count(index)):
			properties[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		var instance := state.get_node_instance(index)
		nodes[String(state.get_node_path(index))] = {
			"name": String(state.get_node_name(index)),
			"type": String(state.get_node_type(index)),
			"instance": instance.resource_path if instance != null else "",
			"properties": properties,
		}
	return nodes


## The one node in main.tscn running interior_reveal.gd, as path -> record.
func _reveal() -> Dictionary:
	for path in _scene():
		var node: Dictionary = _scene()[path]
		var script = node["properties"].get("script", null)
		if script is Script and (script as Script).resource_path == REVEAL_SCRIPT:
			return {"path": path, "node": node}
	return {}


## SceneState reports paths relative to the scene root, so a direct child of
## Main comes back as "./Farmhouse" and its own child as "./Farmhouse/Stove".
## The leading "./" is the thing that is easy to write a test around and get
## silently wrong, so it is stripped in exactly one place.
static func _under(path: String, ancestor: String) -> bool:
	return path.trim_prefix("./").begins_with(ancestor + "/")


func _mesh_names() -> PackedStringArray:
	var names := PackedStringArray()
	var resource := ResourceLoader.load(MODEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return names
	var state := (resource as PackedScene).get_state()
	for index in range(state.get_node_count()):
		for property in range(state.get_node_property_count(index)):
			if state.get_node_property_value(index, property) is Mesh:
				names.append(String(state.get_node_name(index)))
				break
	return names


# --- the reveal is there and it is on the building --------------------------

func test_the_farmhouse_carries_an_interior_reveal() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	assert_true(
		_under(String(found["path"]), "Farmhouse"),
		"the reveal must hang under the building so it settles into the snow with it; it is at %s" % found["path"]
	)


## An Area3D with no shape is a threshold nothing can ever cross, and it fails
## in complete silence -- identical, from outside, to a reveal that works and is
## simply never walked into.
func test_the_threshold_has_a_shape_to_cross() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	var shapes := 0
	for path in _scene():
		if not path.begins_with(String(found["path"]) + "/"):
			continue
		var node: Dictionary = _scene()[path]
		if node["type"] != "CollisionShape3D":
			continue
		var shape = node["properties"].get("shape", null)
		assert_not_null(shape, "%s is a CollisionShape3D with no shape on it" % path)
		if shape != null:
			shapes += 1
	assert_true(shapes > 0, "the threshold under %s has no CollisionShape3D; nothing can cross it" % found["path"])


# --- the authored list is a real list ---------------------------------------

func test_the_authored_fade_list_is_not_empty() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	var list = found["node"]["properties"].get("fade_parts", [])
	assert_true(list is Array, "fade_parts must be an Array, it is %s" % [list])
	assert_true(
		(list as Array).size() > 0,
		"the farmhouse's reveal fades nothing; the roof would never come off"
	)


func test_every_authored_name_is_a_mesh_the_model_actually_has() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	var names := _mesh_names()
	assert_true(names.size() > 0, "no meshes were read out of %s at all" % MODEL_PATH)
	for name in found["node"]["properties"].get("fade_parts", []):
		assert_true(
			names.has(String(name)),
			"the reveal fades %s by name and %s holds no mesh called that; it holds %s"
				% [name, MODEL_PATH, ", ".join(names)]
		)


## The list must never name one of the parts the building is supposed to keep.
## This is the direction of the contract nothing else checks: fading FH_Room
## leaves the player walking on a hole, and fading FH_Furniture takes the stove
## out from under its own firelight.
func test_no_authored_name_is_a_part_the_building_must_keep() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	for name in found["node"]["properties"].get("fade_parts", []):
		assert_false(
			ModelTest.KEPT_GROUPS.has(String(name)),
			"%s is on the never-faded list in tests/art/test_farmhouse_model.gd and must not be faded" % name
		)


## Every mesh in the model is either faded or kept, and the model test already
## proves those two lists cover it. This closes the loop from the other end:
## whatever the scene chooses to fade, the parts it does NOT fade plus the parts
## it does must still be every mesh in the building -- so a part can never end
## up belonging to neither.
func test_the_authored_list_and_the_model_between_them_account_for_every_mesh() -> void:
	var found := _reveal()
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, REVEAL_SCRIPT])
	if found.is_empty():
		return
	var faded := PackedStringArray()
	for name in found["node"]["properties"].get("fade_parts", []):
		faded.append(String(name))
	var strays := PackedStringArray()
	for name in _mesh_names():
		if not faded.has(name) and not ModelTest.KEPT_GROUPS.has(name):
			strays.append(name)
	assert_eq(
		strays.size(), 0,
		"these meshes are neither faded by the scene nor on the never-faded list, "
			+ "so nothing has decided what happens to them when the player steps inside: %s"
				% ", ".join(strays)
	)


# --- the stove is in the room -----------------------------------------------

## The room exists because the stove is in it. GDD section 5's whole resource
## funnel runs through the fire, and until this the stove scene had been built
## and never placed anywhere -- so the reveal would have uncovered an empty box.
func test_the_stove_is_placed_inside_the_farmhouse() -> void:
	var stove := {}
	for path in _scene():
		if _scene()[path]["instance"] == STOVE_SCENE:
			stove = {"path": path, "node": _scene()[path]}
			break
	assert_false(stove.is_empty(), "%s does not instance %s anywhere" % [MAIN_SCENE, STOVE_SCENE])
	if stove.is_empty():
		return
	assert_true(
		_under(String(stove["path"]), "Farmhouse"),
		"the stove must be a child of the building, or it stays where the ground was "
			+ "when the farmhouse settled into the snow; it is at %s" % stove["path"]
	)
	var transform = stove["node"]["properties"].get("transform", null)
	assert_true(transform is Transform3D, "the stove has no transform in %s" % MAIN_SCENE)
	if not (transform is Transform3D):
		return
	var spot: Vector3 = (transform as Transform3D).origin
	for axis in range(3):
		assert_true(
			spot[axis] >= ROOM_MIN[axis] and spot[axis] <= ROOM_MAX[axis],
			"the stove is at %s, outside the main room (%s .. %s) on axis %d"
				% [spot, ROOM_MIN, ROOM_MAX, axis]
		)


## Lit, with fuel in it. Day 1 opens at home on the morning of a seven-day run
## and Stove.start_lit exists for exactly that; a cold stove would mean the
## revealed room has no warm point in it at all, which is the one thing GDD
## section 5 says the house is for.
func test_the_farmhouse_fire_is_burning_when_the_run_starts() -> void:
	for path in _scene():
		if _scene()[path]["instance"] != STOVE_SCENE:
			continue
		var properties: Dictionary = _scene()[path]["properties"]
		assert_true(bool(properties.get("start_lit", false)), "the farmhouse stove must start lit")
		assert_true(
			float(properties.get("starting_fuel_seconds", 0.0)) > 0.0,
			"a stove lit with no fuel in it goes out on the first frame"
		)
		return
	assert_true(false, "%s does not instance %s anywhere" % [MAIN_SCENE, STOVE_SCENE])


# --- the fire must not light the valley -------------------------------------

const WARMTH_SCRIPT := "res://src/entities/interior/interior_warmth.gd"
const DOOR_SCRIPT := "res://src/entities/interior/door.gd"

const InteriorWarmthScript := preload("res://src/entities/interior/interior_warmth.gd")


func _running(script_path: String) -> Dictionary:
	for path in _scene():
		var node: Dictionary = _scene()[path]
		var script = node["properties"].get("script", null)
		if script is Script and (script as Script).resource_path == script_path:
			return {"path": path, "node": node}
	return {}


## THE REGRESSION TEST FOR THE DISC.
##
## The stove's OmniLight has shadows off by design, and the world's two-band
## cel light() never reads LIGHT_COLOR -- it only picks between two palette
## entries off `lambert * ATTENUATION`. So a fire indoors on the default cull
## mask does not warm the room; it shines through the walls and lifts an 18 m
## circle of snow into the lit band. That shipped once and read as a debug
## gizmo on the ground around the house.
##
## Bit 0 is the layer everything in the world is on by default -- the terrain,
## the props, the trees. The fire must not be able to touch it.
func test_the_farmhouse_fire_cannot_light_anything_on_the_default_layer() -> void:
	for path in _scene():
		if _scene()[path]["instance"] != STOVE_SCENE:
			continue
		var mask := int(_scene()[path]["properties"].get("light_cull_mask", 1))
		assert_eq(
			mask & 1, 0,
			"the farmhouse stove lights render layer 1, which is the terrain and every prop "
				+ "in the valley; its mask is %d" % mask
		)
		assert_true(
			mask & InteriorWarmthScript.INTERIOR_LAYER != 0,
			"the stove must still light the room it is standing in; its mask is %d" % mask
		)
		# A fire that casts shadows AND reaches the default layer would put a
		# second, fire-shaped shadow direction across snow the sun already
		# shades. The cull mask is the only thing standing between the two.
		if bool(_scene()[path]["properties"].get("light_shadows", false)):
			assert_eq(
				mask & 1, 0,
				"the farmhouse fire casts shadows onto render layer 1, which is the valley"
			)
		return
	assert_true(false, "%s does not instance %s anywhere" % [MAIN_SCENE, STOVE_SCENE])


## The stove's origin sits on the floor, because that is where a stove stands.
## The FIRE has to be somewhere else, and the reason is not decoration: a floor's
## cel band is `lambert * ATTENUATION` with lambert the dot of +Y against the
## direction to the light, so a light lying in the floor plane cannot light the
## floor at any energy or range. Left at the origin it is also inside the stove's
## own casing, which with shadows on is a lamp in a closed box.
##
## Stove_Body in tools/blender/build_farmhouse.py is x -0.48 .. 0.48,
## y 0.45 .. 1.40, z -4.98 .. -5.72 in the model's own space, and the stove node
## is placed at 0, 0.45, -5.35 -- so the offset has to carry the light out of
## that box.
func test_the_farmhouse_fire_sits_in_the_firebox_and_not_in_the_floor() -> void:
	for path in _scene():
		if _scene()[path]["instance"] != STOVE_SCENE:
			continue
		var properties: Dictionary = _scene()[path]["properties"]
		var offset = properties.get("light_offset", Vector3.ZERO)
		assert_true(offset is Vector3, "the farmhouse stove has no light_offset")
		if not (offset is Vector3):
			return
		assert_true(
			(offset as Vector3).y > 0.3,
			"the fire is %.2f m above the floor it is meant to be lighting" % (offset as Vector3).y
		)
		var transform = properties.get("transform", null)
		if not (transform is Transform3D):
			return
		var flame: Vector3 = (transform as Transform3D).origin + (offset as Vector3)
		var body := AABB(Vector3(-0.48, 0.45, -5.72), Vector3(0.96, 0.95, 0.74))
		assert_false(
			body.has_point(flame),
			"the fire is at %s, inside Stove_Body %s .. %s -- a lamp in a closed box"
				% [flame, body.position, body.end]
		)
		return
	assert_true(false, "%s does not instance %s anywhere" % [MAIN_SCENE, STOVE_SCENE])


# --- the warm room ----------------------------------------------------------

func test_the_farmhouse_carries_an_interior_warmth() -> void:
	var found := _running(WARMTH_SCRIPT)
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, WARMTH_SCRIPT])
	if found.is_empty():
		return
	assert_true(
		_under(String(found["path"]), "Farmhouse"),
		"the warmth must hang under the building; it is at %s" % found["path"]
	)
	var list = found["node"]["properties"].get("warm_parts", [])
	assert_true((list as Array).size() > 0, "nothing is warmed, so the revealed room is a box")


## Both authored lists, as one set of names. The component resolves them
## together -- they differ only in which rung of the warm ladder they take -- so
## every check that asks "is this a real part of the building" has to see both,
## or half the room drops out of the gate the day a name is moved between them.
func _warmed_names(found: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for key in ["warm_parts", "furnishing_parts"]:
		for name in found["node"]["properties"].get(key, []):
			names.append(String(name))
	return names


func test_every_warmed_name_is_a_mesh_the_model_actually_has() -> void:
	var found := _running(WARMTH_SCRIPT)
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, WARMTH_SCRIPT])
	if found.is_empty():
		return
	var names := _mesh_names()
	for name in _warmed_names(found):
		assert_true(
			names.has(name),
			"the room warms %s by name and %s holds no mesh called that" % [name, MODEL_PATH]
		)


## THE REGRESSION TEST FOR THE ORANGE BOX, at the scene level.
##
## `mix(lit_color, warm_lit_color, warmth)` at warmth 1 is warm_lit_color
## outright, so a building that puts every part on one list gets one colour for
## the whole room: floor, walls, table, bed and stove all identical, and the
## payoff frame of the game is an even orange field with nothing in it. The
## furniture has to be on the darker rung, and the floor and the walls on the
## brighter one, or the reveal uncovers a box again.
func test_the_furniture_stands_on_the_room_rather_than_dissolving_into_it() -> void:
	var found := _running(WARMTH_SCRIPT)
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, WARMTH_SCRIPT])
	if found.is_empty():
		return
	var field := PackedStringArray()
	for name in found["node"]["properties"].get("warm_parts", []):
		field.append(String(name))
	var stood_on := PackedStringArray()
	for name in found["node"]["properties"].get("furnishing_parts", []):
		stood_on.append(String(name))
	assert_true(
		stood_on.has("FH_Furniture"),
		"FH_Furniture is not on furnishing_parts, so every stick of furniture is the same "
			+ "colour as the floor it stands on; the list is %s" % ", ".join(stood_on)
	)
	for name in ["FH_Room", "FH_Shell"]:
		assert_true(
			field.has(name),
			"%s is not on warm_parts, so the room has no lit field for anything to read against" % name
		)
		assert_false(stood_on.has(name), "%s is the field, not something standing on it" % name)


## A part cannot be both faded away and warmed: warming something the reveal
## deletes is work done on a surface nobody will ever see, and it means the
## authored lists have drifted apart.
func test_nothing_is_both_faded_and_warmed() -> void:
	var reveal := _reveal()
	var warmth := _running(WARMTH_SCRIPT)
	assert_false(reveal.is_empty(), "%s holds no reveal" % MAIN_SCENE)
	assert_false(warmth.is_empty(), "%s holds no warmth" % MAIN_SCENE)
	if reveal.is_empty() or warmth.is_empty():
		return
	var faded := PackedStringArray()
	for name in reveal["node"]["properties"].get("fade_parts", []):
		faded.append(String(name))
	for name in _warmed_names(warmth):
		assert_false(faded.has(name), "%s is both faded and warmed" % name)


# --- the door ---------------------------------------------------------------

func test_the_farmhouse_carries_a_door_on_the_hinged_leaf() -> void:
	var found := _running(DOOR_SCRIPT)
	assert_false(found.is_empty(), "%s holds no node running %s" % [MAIN_SCENE, DOOR_SCRIPT])
	if found.is_empty():
		return
	assert_true(_under(String(found["path"]), "Farmhouse"), "the door must hang under the building")
	var leaf := String(found["node"]["properties"].get("leaf_part", ""))
	assert_true(
		_mesh_names().has(leaf),
		"the door swings %s and the model holds no mesh called that" % leaf
	)


func test_the_doorstep_has_a_shape_to_stand_in() -> void:
	var found := _running(DOOR_SCRIPT)
	assert_false(found.is_empty(), "%s holds no door" % MAIN_SCENE)
	if found.is_empty():
		return
	var shapes := 0
	for path in _scene():
		if not path.begins_with(String(found["path"]) + "/"):
			continue
		if _scene()[path]["type"] != "CollisionShape3D":
			continue
		assert_not_null(_scene()[path]["properties"].get("shape", null), "%s has no shape" % path)
		shapes += 1
	assert_true(shapes > 0, "nothing can reach the door: it has no CollisionShape3D")


func test_the_farmhouse_door_offers_a_guided_entry_from_a_forgiving_zone() -> void:
	var found := _running(DOOR_SCRIPT)
	assert_false(found.is_empty(), "%s holds no door" % MAIN_SCENE)
	if found.is_empty():
		return
	assert_false(bool(found["node"]["properties"].get("opens_on_approach", false)),
		"merely seeing the farmhouse door should not take control away from the player")
	assert_true(bool(found["node"]["properties"].get("guides_entry", false)),
		"pressing E at the farmhouse door does not carry the player through the fixed-camera threshold")
	var target: Vector3 = found["node"]["properties"].get("entry_target_offset", Vector3.ZERO)
	assert_true(target.z <= -1.2,
		"the guided walk stops before the main-room threshold: %s" % target)
	assert_false(NodePath(found["node"]["properties"].get("interaction_anchor_path", NodePath())).is_empty(),
		"the generous approach zone has no separate prompt point on the visible door")
	var boxes: Array[BoxShape3D] = []
	for path in _scene():
		if not path.begins_with(String(found["path"]) + "/"):
			continue
		var shape = _scene()[path]["properties"].get("shape", null)
		if shape is BoxShape3D:
			boxes.append(shape)
	assert_eq(boxes.size(), 1, "the farmhouse door should carry one readable approach zone")
	if boxes.size() != 1:
		return
	assert_true(boxes[0].size.x >= 4.0 and boxes[0].size.z >= 4.6,
		"the door approach is still a precision funnel: %s" % boxes[0].size)


func test_the_doorway_and_main_room_are_one_continuous_interior_volume() -> void:
	var scene := _scene()
	var main: Dictionary = scene.get("./Farmhouse/InteriorReveal/MainRoom", {})
	var corridor: Dictionary = scene.get("./Farmhouse/InteriorReveal/EntryCorridor", {})
	assert_false(main.is_empty(), "the farmhouse has no main-room interior volume")
	assert_false(corridor.is_empty(),
		"the doorway still has an unclassified layer before the main room")
	if main.is_empty() or corridor.is_empty():
		return
	var main_shape := main["properties"].get("shape", null) as BoxShape3D
	var corridor_shape := corridor["properties"].get("shape", null) as BoxShape3D
	assert_not_null(main_shape, "the main-room trigger is not a box")
	assert_not_null(corridor_shape, "the entry corridor trigger is not a box")
	if main_shape == null or corridor_shape == null:
		return
	var main_transform: Transform3D = main["properties"].get("transform", Transform3D.IDENTITY)
	# Godot normalises a manually authored `position` back into `transform` when
	# the scene is re-saved. Read either representation so this checks the actual
	# geometry rather than the text spelling the editor happened to choose.
	var corridor_transform: Transform3D = corridor["properties"].get(
		"transform", Transform3D.IDENTITY)
	var corridor_position: Vector3 = corridor["properties"].get(
		"position", corridor_transform.origin)
	var main_front := main_transform.origin.z + main_shape.size.z * 0.5
	var corridor_inside := corridor_position.z - corridor_shape.size.z * 0.5
	var corridor_outside := corridor_position.z + corridor_shape.size.z * 0.5
	assert_true(corridor_outside >= 0.0,
		"the continuous interior does not reach the physical door plane")
	assert_true(corridor_inside < main_front,
		"a %.3f m unclassified layer remains between doorway and room"
		% (corridor_inside - main_front))
	assert_true(absf(corridor_position.x - 1.8) <= corridor_shape.size.x * 0.5,
		"the continuous volume misses the authored doorway")


func test_the_room_reveal_names_the_power_line_that_bisects_the_fixed_view() -> void:
	var reveal := _reveal()
	assert_false(reveal.is_empty(), "%s holds no reveal" % MAIN_SCENE)
	if reveal.is_empty():
		return
	var paths: Array = reveal["node"]["properties"].get("fade_paths", [])
	assert_true(paths.has(NodePath("../../Farmstead/Wires/WireToTruckPole")),
		"the foreground wire still crosses the revealed room from corner to corner")


## Without this the reveal fires wherever the player crosses the wall, and the
## door is decoration. Nothing else in the scene enforces entry at the door --
## the walls are not solid yet.
func test_the_reveal_is_gated_on_the_door() -> void:
	var reveal := _reveal()
	var door := _running(DOOR_SCRIPT)
	assert_false(reveal.is_empty(), "%s holds no reveal" % MAIN_SCENE)
	assert_false(door.is_empty(), "%s holds no door" % MAIN_SCENE)
	if reveal.is_empty() or door.is_empty():
		return
	var gate := String(reveal["node"]["properties"].get("entry_gate_path", NodePath()))
	assert_true(
		gate.ends_with("Door"),
		"the reveal's entry_gate_path is '%s'; with no gate the player walks in through a wall" % gate
	)
