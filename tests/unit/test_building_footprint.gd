extends TestCase

## What a building says about the ground it stands on.
##
## InteriorReveal already knows where the rooms are -- it is how the roof knows
## when to come off. This is the SAME SHAPES read for a second question: which
## patch of snow does this building displace, and where is the floor the player
## is supposed to end up standing on.
##
## One set of boxes answers both, and that is the whole point. A second registry
## of footprints would be free to drift out of step with the first, and the
## symptom would be a house whose roof lifts along one line and whose snow
## clears along another.
##
## Nothing here is a farmhouse. The fixture is a one-room hut with a floor slab,
## a wall and a door leaf, built in the test, because the reveal is a component
## and wave 4 hangs four more buildings off it.

const RevealScript := preload("res://src/entities/interior/interior_reveal.gd")
const DoorScript := preload("res://src/entities/interior/door.gd")

## The hut: interior 4 x 6, walls 0.2 thick, floor slab topping out at 0.5,
## and the whole thing stood at (10, 0.7, -4) and turned a quarter turn so that
## a footprint reported in the building's own axes rather than the world's
## fails loudly instead of coincidentally passing.
const HUT_AT := Vector3(10.0, 0.7, -4.0)
const HUT_YAW := 90.0
const ROOM_HALF := Vector2(2.0, 3.0)
const ROOM_AT := Vector3(0.0, 1.0, -1.0)
const WALL := 0.2
const FLOOR_TOP := 0.5
const DOOR_WIDTH := 1.0
const DOOR_AT := Vector3(0.6, 1.45, 2.0)

var _hut: Node3D
var _reveal: InteriorReveal
var _door: Door


func before_each() -> void:
	_hut = Node3D.new()
	_hut.name = "Hut"
	_hut.position = HUT_AT
	_hut.rotation.y = deg_to_rad(HUT_YAW)

	_reveal = RevealScript.new()
	_reveal.name = "InteriorReveal"
	_reveal.wall_thickness = WALL
	_hut.add_child(_reveal)

	var shape := BoxShape3D.new()
	shape.size = Vector3(ROOM_HALF.x * 2.0, 3.0, ROOM_HALF.y * 2.0)
	var room := CollisionShape3D.new()
	room.name = "Room"
	room.shape = shape
	room.position = ROOM_AT
	_reveal.add_child(room)

	# What the room stands on. Its top face is the floor.
	_add_box("Floor", Vector3(4.0, 0.2, 6.0), Vector3(0.0, FLOOR_TOP - 0.1, -1.0))
	# And a wall, which is also under the room in plan and must NOT be mistaken
	# for the floor -- the rule is "the highest thing below the middle of the
	# room", and a wall runs straight past it.
	_add_box("Wall", Vector3(4.4, 3.0, 6.4), Vector3(0.0, 1.5, -1.0))

	_door = DoorScript.new()
	_door.name = "Door"
	_door.leaf_part = &"Leaf"
	_hut.add_child(_door)
	_add_box("Leaf", Vector3(DOOR_WIDTH, 2.1, 0.08), DOOR_AT)
	_reveal.entry_gate_path = ^"../Door"


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2). Freeing the root
	# takes the whole hut with it.
	_hut.free()
	_hut = null
	_reveal = null
	_door = null


func _add_box(part: String, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = mesh
	instance.position = at
	_hut.add_child(instance)


# --- the rooms --------------------------------------------------------------

## The threshold shapes bound the INSIDE of the walls -- that is what makes them
## the right shapes for the reveal, because the reveal fires when the player is
## in the room. Snow lies against the OUTSIDE, so the footprint is those same
## boxes grown by one wall.
func test_the_footprint_is_the_room_grown_to_the_outer_face_of_the_wall() -> void:
	var areas := _reveal.footprint_areas()
	assert_eq(areas.size(), 1)
	var half: Vector2 = areas[0]["half"]
	assert_almost_eq(half.x, ROOM_HALF.x + WALL, 0.0001)
	assert_almost_eq(half.y, ROOM_HALF.y + WALL, 0.0001)


## A quarter turn puts the room's local -Z at the world -X. If this comes back
## in world axes the carve is a rectangle at the wrong angle, and the wrong
## corners of the house end up buried.
func test_the_footprint_turns_with_the_building() -> void:
	var areas := _reveal.footprint_areas()
	var axis_x: Vector2 = areas[0]["axis_x"]
	var axis_z: Vector2 = areas[0]["axis_z"]
	assert_almost_eq(axis_x.x, 0.0, 0.0001)
	assert_almost_eq(axis_x.y, -1.0, 0.0001)
	assert_almost_eq(axis_z.x, 1.0, 0.0001)
	assert_almost_eq(axis_z.y, 0.0, 0.0001)


## Node3D.global_transform is the obvious way to place these and it is the wrong
## one: outside a tree it prints an error and returns identity, so every unit
## test of a footprint would quietly assert about the world origin. The chain is
## walked instead.
func test_the_footprint_stands_where_the_building_stands() -> void:
	var areas := _reveal.footprint_areas()
	var centre: Vector2 = areas[0]["centre"]
	# Local (0, -1) through a +90 degree yaw is world (-1, 0).
	assert_almost_eq(centre.x, HUT_AT.x - 1.0, 0.0001)
	assert_almost_eq(centre.y, HUT_AT.z, 0.0001)


## Two rooms is the farmhouse's case -- an L cannot be one box -- and the reveal
## already takes them as two shapes on one Area3D.
func test_every_threshold_shape_is_a_room_of_the_footprint() -> void:
	var second := CollisionShape3D.new()
	second.name = "Wing"
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 3.0, 2.0)
	second.shape = shape
	second.position = Vector3(3.0, 1.0, 0.0)
	_reveal.add_child(second)
	assert_eq(_reveal.footprint_areas().size(), 2)


# --- the floor --------------------------------------------------------------

## The measurement rule, in one sentence: the floor is the top of the highest
## piece of the building that is still below the middle of the room. A floor is
## the only thing that can be -- a wall runs past the middle, furniture stands
## on top of it, and a roof is nowhere near.
func test_the_floor_is_measured_from_what_the_room_stands_on() -> void:
	assert_almost_eq(_reveal.interior_floor_height(), HUT_AT.y + FLOOR_TOP, 0.0001)


## A building that states it wins, because a building that needs to state it is
## one this rule got wrong, and the fix must not be a code change.
func test_a_stated_floor_height_wins_over_the_measurement() -> void:
	_reveal.floor_height = 0.62
	assert_almost_eq(_reveal.interior_floor_height(), HUT_AT.y + 0.62, 0.0001)


## The failure the brief warned about: carve the snow out from under a building
## with no floor and you have swapped a room full of snow for a room with bare
## ground in it. NAN says so rather than guessing a height.
func test_a_room_with_nothing_under_it_reports_no_floor() -> void:
	var slab := _hut.find_child("Floor", true, false)
	_hut.remove_child(slab)
	slab.free()
	assert_true(is_nan(_reveal.interior_floor_height()))


# --- the doorway ------------------------------------------------------------

## Not a guess at where a door might be: the hole is the leaf that fills it, and
## the door already resolves that leaf by name so it can swing it.
func test_the_doorway_is_the_shut_leaf() -> void:
	var doors := _reveal.doorways()
	assert_eq(doors.size(), 1)
	assert_almost_eq(float(doors[0]["width"]), DOOR_WIDTH, 0.0001)


## Which way the snow blows. The leaf sits in the room's +Z wall, so the drift
## runs along the room's -Z -- which a quarter turn puts along the world -X.
func test_the_doorway_points_into_the_room() -> void:
	var inward: Vector2 = _reveal.doorways()[0]["inward"]
	assert_almost_eq(inward.x, -1.0, 0.0001)
	assert_almost_eq(inward.y, 0.0, 0.0001)


func test_a_building_with_no_gate_reports_no_doorway() -> void:
	_reveal.entry_gate_path = ^""
	assert_eq(_reveal.doorways().size(), 0)


# --- what goes on the bus ---------------------------------------------------

func test_the_published_footprint_carries_the_rooms_the_floor_and_the_door() -> void:
	var footprint := _reveal.footprint()
	assert_eq((footprint["areas"] as Array).size(), 1)
	assert_almost_eq(float(footprint["floor_y"]), HUT_AT.y + FLOOR_TOP, 0.0001)
	assert_eq((footprint["doorways"] as Array).size(), 1)
	assert_eq(int(footprint["id"]), int(_reveal.get_instance_id()))


## The field must not be reachable from here and is not: the footprint is an
## event, and whether anything is listening is not this building's business.
func test_the_footprint_goes_out_on_the_bus() -> void:
	var bus := preload("res://src/core/event_bus.gd").new()
	var spy := _Spy.new()
	bus.subscribe(InteriorReveal.EVENT_FOOTPRINT, spy.on_event)
	_reveal.set_event_bus(bus)
	_reveal.announce_footprint()
	assert_eq(spy.count, 1)
	assert_eq(int((spy.last as Dictionary)["id"]), int(_reveal.get_instance_id()))
	bus.free()


class _Spy extends RefCounted:
	var count := 0
	var last = null

	func on_event(payload) -> void:
		count += 1
		last = payload
