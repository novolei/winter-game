extends TestCase

## The real house, on the real site, against the real noise.
##
## tests/unit/test_snow_carve.gd proves the carve does what it says on a hut the
## test invented. This is the one that would have caught the defect: it stands
## the actual farmhouse at the actual place scenes/main.tscn puts it, beds it
## down the way Farmhouse._settle() does, and asks whether a man standing in the
## main room would be on the floorboards or on a snowdrift.
##
## Before the carve he was on a drift, over 90% of the room, by up to 0.61 m.
## test_the_room_is_buried_with_no_carve below is that measurement kept, so the
## defect cannot come back unnoticed -- if it ever stops failing to be buried,
## something upstream has moved and the rest of this file is measuring nothing.
##
## Instantiated rather than walked off SceneState, which is the other art tests'
## habit: this one needs the model's actual AABBs -- where the floor is is the
## whole question -- and a SceneState does not have them placed.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const RevealScript := preload("res://src/entities/interior/interior_reveal.gd")
const DoorScript := preload("res://src/entities/interior/door.gd")
const FarmhouseScript := preload("res://src/entities/farmhouse.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const MODEL_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"

## How far under the boards a man may stand before it reads as standing in
## them. The pad is rounded down onto an 8-bit raster, which at this house's
## height is a 2.6 cm step, so anything tighter than that is not achievable
## without widening the terrain texture -- which is another agent's shader.
const SINK_TOLERANCE := 0.05

var _field: SnowField
var _house: Node3D
var _reveal: InteriorReveal


func before_each() -> void:
	_field = SnowFieldScript.new()
	_field.build_at(Vector3.ZERO)
	_house = _stand_the_house()


func after_each() -> void:
	_house.free()
	_house = null
	_reveal = null
	_field.free()
	_field = null


# --- the fixture ------------------------------------------------------------

## Every node in main.tscn, as path -> {type, properties}. Same walk as
## tests/art/test_interior_reveal_wiring.gd, and for the same reason: the
## authored numbers are the contract, and a test that retyped them would pass a
## house that had been moved.
func _scene() -> Dictionary:
	var nodes := {}
	var resource := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return nodes
	var state := (resource as PackedScene).get_state()
	for index in range(state.get_node_count()):
		var properties := {}
		for property in range(state.get_node_property_count(index)):
			properties[state.get_node_property_name(index, property)] = \
				state.get_node_property_value(index, property)
		nodes[String(state.get_node_path(index))] = {
			"type": String(state.get_node_type(index)),
			"properties": properties,
		}
	return nodes


## The farmhouse as main.tscn stands it: the model, an InteriorReveal carrying
## the scene's own threshold shapes, and the Door it gates entry through.
## Nothing is retyped -- the transform, both room boxes and the door's leaf name
## all come out of the scene file, so a house that gets moved or re-shaped moves
## this test with it.
func _stand_the_house() -> Node3D:
	var scene := _scene()
	var building := Node3D.new()
	building.name = "Farmhouse"
	var properties := _properties(scene, "./Farmhouse")
	if properties.has("transform"):
		building.transform = properties["transform"]

	var model_scene := ResourceLoader.load(MODEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if model_scene is PackedScene:
		var model: Node = (model_scene as PackedScene).instantiate()
		model.name = "Model"
		building.add_child(model)

	var door := DoorScript.new()
	door.name = "Door"
	var door_properties := _properties(scene, "./Farmhouse/Door")
	if door_properties.has("leaf_part"):
		door.leaf_part = door_properties["leaf_part"]
	building.add_child(door)

	_reveal = RevealScript.new()
	_reveal.name = "InteriorReveal"
	var reveal_properties := _properties(scene, "./Farmhouse/InteriorReveal")
	if reveal_properties.has("entry_gate_path"):
		_reveal.entry_gate_path = reveal_properties["entry_gate_path"]
	building.add_child(_reveal)
	for path in scene:
		if not String(path).begins_with("./Farmhouse/InteriorReveal/"):
			continue
		var node: Dictionary = scene[path]
		if String(node["type"]) != "CollisionShape3D":
			continue
		var shape_properties: Dictionary = node["properties"]
		var collider := CollisionShape3D.new()
		collider.name = String(path).get_file()
		if shape_properties.has("transform"):
			collider.transform = shape_properties["transform"]
		if shape_properties.has("shape"):
			collider.shape = shape_properties["shape"]
		_reveal.add_child(collider)
	return building


func _properties(scene: Dictionary, path: String) -> Dictionary:
	var node: Dictionary = scene.get(path, {})
	return node.get("properties", {})


## Farmhouse._settle(), reproduced -- the loop is six lines and the constants
## that drive it are read off the real script's exports rather than copied, so
## moving the footprint or the bed depth moves this too.
func _bed_the_house_down() -> void:
	var rules: Farmhouse = FarmhouseScript.new()
	var lowest := INF
	var here := _house.position
	var x: float = rules.footprint_min.x
	while x <= rules.footprint_max.x:
		var z: float = rules.footprint_min.y
		while z <= rules.footprint_max.y:
			var spot := here + Vector3(x, 0.0, z)
			lowest = minf(lowest, _field.terrain_height_at(spot) + _field.depth_at(spot))
			z += rules.footprint_step
		x += rules.footprint_step
	_house.position.y = lowest - rules.bed_depth
	rules.free()


## Every interior point of both rooms, on a quarter-metre grid. The reveal's
## footprint areas reach the OUTER wall face, so they come back in by one wall
## to give the floor.
func _room_samples() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for area in _reveal.footprint_areas():
		var centre: Vector2 = area["centre"]
		var axis_x: Vector2 = area["axis_x"]
		var axis_z: Vector2 = area["axis_z"]
		var half: Vector2 = area["half"] - Vector2.ONE * _reveal.wall_thickness
		var u := -half.x + 0.2
		while u <= half.x - 0.2:
			var v := -half.y + 0.2
			while v <= half.y - 0.2:
				var flat := centre + axis_x * u + axis_z * v
				spots.append(Vector3(flat.x, 0.0, flat.y))
				v += 0.25
			u += 0.25
	return spots


func _carve() -> void:
	_field.carve_building(_reveal.footprint())


# --- the floor exists -------------------------------------------------------

## The carve levels the ground to the floorboards and hides the snow mesh under
## them. With no floor mesh it would level the ground to a plane that draws
## nothing, and the room would read as bare terrain -- one wrong picture traded
## for another. So the floor is a contract now.
func test_the_farmhouse_has_a_floor_under_its_rooms() -> void:
	_bed_the_house_down()
	var floor_y := _reveal.interior_floor_height()
	assert_false(is_nan(floor_y), "no floor was found under the farmhouse's rooms")
	# 0.45 above the building origin -- FLOOR_Z in tools/blender/build_farmhouse.py.
	assert_almost_eq(floor_y - _house.position.y, 0.45, 0.001)


# --- the defect, kept -------------------------------------------------------

## THE MEASUREMENT THIS TASK EXISTS FOR. Without the carve the field runs
## straight through the floorboards over almost the whole main room.
##
## Note what buries it: sampled on this site the snow in the main room is seven
## millimetres deep. It is the BARE GROUND that is over the boards -- the house
## stands on the flank of a scoured crest -- which is why removing snow alone
## would have changed nothing here.
func test_the_room_is_buried_with_no_carve() -> void:
	_bed_the_house_down()
	var floor_y := _reveal.interior_floor_height()
	var buried := 0
	var spots := _room_samples()
	for spot in spots:
		if _field.surface_height_at(spot) > floor_y:
			buried += 1
	assert_true(
		float(buried) / float(spots.size()) > 0.5,
		"only %d of %d sampled points are over the floor; the defect this file "
		% [buried, spots.size()]
		+ "guards has moved and every other test here is now measuring nothing"
	)


# --- the fix ----------------------------------------------------------------

## The room is under the boards everywhere, and the ONLY exception is the drift
## that blew in at the door -- which is snow lying on the floor and is supposed
## to be there. Written as "nothing else is above them" rather than "nothing is",
## because the version that forbade everything would have been satisfied by a
## carve that sealed the doorway, and that is the failure this house is meant to
## demonstrate the absence of.
func test_nothing_but_the_doorway_drift_stands_over_the_boards() -> void:
	_bed_the_house_down()
	_carve()
	var floor_y := _reveal.interior_floor_height()
	var doorway: Dictionary = _reveal.doorways()[0]
	var centre: Vector2 = doorway["centre"]
	var inward: Vector2 = doorway["inward"]
	var strays := 0
	var worst := 0.0
	var furthest := 0.0
	for spot in _room_samples():
		var over: float = _field.surface_height_at(spot) - floor_y
		if over <= 0.0:
			continue
		worst = maxf(worst, over)
		var offset := Vector2(spot.x, spot.z) - centre
		var along := offset.dot(inward)
		var aside := absf(offset.dot(Vector2(-inward.y, inward.x)))
		if along < 0.0 or along > _field.doorway_reach_m \
				or aside > doorway["width"] * 0.5 + _field.doorway_spread_m:
			strays += 1
			furthest = maxf(furthest, along)
	assert_eq(strays, 0, "%d points stand over the boards away from the door, up to %.2f m in" % [strays, furthest])
	assert_true(
		worst <= _field.doorway_drift_m + 0.03,
		"the drift stands %.3f m over the boards, against a %.2f m budget" % [worst, _field.doorway_drift_m]
	)


func test_the_carve_leaves_a_man_standing_on_the_boards_and_not_in_them() -> void:
	_bed_the_house_down()
	_carve()
	var floor_y := _reveal.interior_floor_height()
	var deepest := INF
	for spot in _room_samples():
		# player_controller.gd grounds the body at ground + depth * (1 - sink).
		var feet: float = _field.terrain_height_at(spot) + _field.depth_at(spot) * 0.25
		deepest = minf(deepest, feet)
	assert_true(
		deepest > floor_y - SINK_TOLERANCE,
		"a man in this room stands %.3f m below the boards" % (floor_y - deepest)
	)


func test_the_carve_leaves_no_snow_indoors_to_wade_through() -> void:
	_bed_the_house_down()
	_carve()
	var worst := 0.0
	for spot in _room_samples():
		worst = maxf(worst, _field.wade_factor(spot))
	assert_almost_eq(worst, 0.0, 0.0001)


## The house is not a rectangle stamped on the field: it has a door, and snow
## comes through it. The threshold drift is the visible proof, so it is checked
## on the real doorway rather than only on the invented one.
func test_snow_lies_on_the_boards_at_the_real_doorway() -> void:
	_bed_the_house_down()
	var doorways := _reveal.doorways()
	assert_eq(doorways.size(), 1, "the farmhouse's reveal found no doorway to blow snow through")
	_carve()
	var floor_y := _reveal.interior_floor_height()
	var centre: Vector2 = doorways[0]["centre"]
	var inward: Vector2 = doorways[0]["inward"]
	var sill := centre + inward * 0.3
	var height: float = _field.surface_height_at(Vector3(sill.x, 0.0, sill.y))
	assert_true(height > floor_y, "the threshold is bare: %.3f m against boards at %.3f" % [height, floor_y])
