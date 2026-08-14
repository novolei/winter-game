extends TestCase

## The door, and the rule that makes going inside an arrival rather than a
## filter.
##
## Without it the player walks in anywhere along the wall and the roof lifts,
## which reads as a region the camera behaves differently in. With it, the house
## opens because you opened it -- GDD section 11 binds `E` to *interact: light a
## fire, pick up, open a door*, and this is that.
##
## The gate is the load-bearing half and it is tested against a real
## InteriorReveal here rather than against a stub, because the property being
## protected is the one that spans the two: **nothing in this world has a
## collision body yet**, so the door is currently the ONLY thing stopping entry
## through a wall. Making walls solid belongs to another agent; this must keep
## working either way.

const DoorScript := preload("res://src/entities/interior/door.gd")
const InteriorRevealScript := preload("res://src/entities/interior/interior_reveal.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _building: Node3D = null
var _bus = null
var _occupant: Node3D = null
var _stranger: Node3D = null
var _events: Array = []


func before_each() -> void:
	_events = []


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2).
	for node in [_building, _bus, _occupant, _stranger]:
		if node != null:
			node.free()
	_building = null
	_bus = null
	_occupant = null
	_stranger = null


# --- helpers ---------------------------------------------------------------

func _build() -> Door:
	_building = Node3D.new()
	_building.name = "Farmhouse"
	var model := Node3D.new()
	model.name = "Model"
	_building.add_child(model)
	# The leaf, offset from the building origin the way the exported FH_Door is:
	# its origin is on the hinge stile, not at the model origin.
	var leaf := MeshInstance3D.new()
	leaf.name = "FH_Door"
	leaf.position = Vector3(1.30, 0.45, 0.04)
	model.add_child(leaf)
	# A part the door must never touch.
	var wall := MeshInstance3D.new()
	wall.name = "FH_Fade_Front"
	model.add_child(wall)
	var door: Door = DoorScript.new()
	door.leaf_part = &"FH_Door"
	_building.add_child(door)
	door.resolve()
	return door


func _leaf() -> Node3D:
	return _building.find_child("FH_Door", true, false) as Node3D


func _with_bus(door: Door) -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(DoorScript.EVENT_OPENED, _record.bind("open"))
	_bus.subscribe(DoorScript.EVENT_CLOSED, _record.bind("shut"))
	door.set_event_bus(_bus)


func _record(payload, tag: String) -> void:
	_events.append({"tag": tag, "payload": payload})


func _tags() -> PackedStringArray:
	var tags := PackedStringArray()
	for event in _events:
		tags.append(event["tag"])
	return tags


# --- the leaf ---------------------------------------------------------------

func test_it_finds_the_leaf_it_was_named() -> void:
	var door := _build()
	assert_not_null(door.leaf(), "the door found nothing to swing")
	if door.leaf() == null:
		return
	assert_eq(door.leaf().name, "FH_Door", "the door swung the wrong part")


func test_a_leaf_the_building_does_not_have_leaves_the_door_inert_rather_than_crashing() -> void:
	var door := _build()
	door.leaf_part = &"FH_Hatch"
	door.resolve()
	assert_true(door.leaf() == null, "an unresolvable leaf must resolve to nothing")
	door.open()
	assert_true(door.is_open(), "the door still opens as far as the gate is concerned")


func test_a_shut_door_leaves_the_leaf_exactly_where_the_model_put_it() -> void:
	var door := _build()
	assert_false(door.is_open(), "a house is found shut")
	assert_almost_eq(door.swing(), 0.0, 0.0001, "a shut door is at swing 0")
	assert_almost_eq(
		_leaf().transform.basis.get_euler().y, 0.0, 0.0001,
		"a shut door must be at the model's own pose, not at an assumed identity"
	)


func test_opening_swings_the_leaf_about_its_hinge() -> void:
	var door := _build()
	door.open()
	assert_true(door.is_open(), "open() must open it")
	assert_almost_eq(door.swing(), 1.0, 0.0001, "an open door is at swing 1")
	assert_almost_eq(
		rad_to_deg(_leaf().transform.basis.get_euler().y), door.open_degrees, 0.01,
		"the leaf must be rotated by open_degrees"
	)
	# The hinge is the origin, so the leaf never translates. If this ever moves,
	# the origin has come off the hinge stile in the build script and the door
	# will swing through the wall.
	assert_eq(
		_leaf().position, Vector3(1.30, 0.45, 0.04),
		"a hinged door rotates and must never translate"
	)


func test_closing_puts_the_leaf_back() -> void:
	var door := _build()
	door.open()
	door.close()
	assert_false(door.is_open(), "close() must shut it")
	assert_almost_eq(_leaf().transform.basis.get_euler().y, 0.0, 0.0001, "a shut door is back at the model's pose")


func test_the_leaf_swings_inward() -> void:
	var door := _build()
	door.apply_swing(1.0)
	# The leaf runs from the hinge toward +X. A positive rotation about Y takes
	# +X to -Z, which is into the room; the porch and its steps are at +Z, and a
	# door opening onto them would foul the steps and be shut by the first drift.
	var swung: Vector3 = _leaf().transform.basis * Vector3(1.0, 0.0, 0.0)
	assert_true(swung.z < -0.9, "the leaf must swing into the room, not onto the porch; it went to %s" % swung)


func test_toggling_alternates() -> void:
	var door := _build()
	door.toggle()
	assert_true(door.is_open(), "the first press opens it")
	door.toggle()
	assert_false(door.is_open(), "the second press shuts it")


func test_the_swing_takes_a_stated_time_in_both_directions() -> void:
	var door := _build()
	assert_true(door.swing_seconds > 0.0, "a door that teleports open is a switch")
	assert_almost_eq(door.swing_duration_to(1.0), door.swing_seconds, 0.0001, "opening takes the full time")
	door.apply_swing(1.0)
	assert_almost_eq(door.swing_duration_to(0.0), door.swing_seconds, 0.0001, "shutting takes the full time")


func test_a_part_that_is_not_the_leaf_is_never_touched() -> void:
	var door := _build()
	door.open()
	var wall := _building.find_child("FH_Fade_Front", true, false) as Node3D
	assert_almost_eq(wall.transform.basis.get_euler().y, 0.0, 0.0001, "the wall must not swing with the door")


# --- who may open it --------------------------------------------------------

func test_only_the_occupant_is_at_the_door() -> void:
	var door := _build()
	_occupant = Node3D.new()
	_stranger = Node3D.new()
	door.set_occupant(_occupant)
	door.on_body_entered(_stranger)
	assert_false(door.is_occupant_near(), "something that is not the player is not at the door")
	door.on_body_entered(_occupant)
	assert_true(door.is_occupant_near(), "the player is at the door")
	door.on_body_exited(_occupant)
	assert_false(door.is_occupant_near(), "the player walked away")


func test_a_door_that_opens_on_approach_does() -> void:
	var door := _build()
	door.opens_on_approach = true
	_occupant = Node3D.new()
	door.set_occupant(_occupant)
	door.on_body_entered(_occupant)
	assert_true(door.is_open(), "opens_on_approach must open it without a keypress")


func test_by_default_walking_up_to_it_does_not_open_it() -> void:
	var door := _build()
	_occupant = Node3D.new()
	door.set_occupant(_occupant)
	door.on_body_entered(_occupant)
	assert_false(door.is_open(), "the design asks for E; approaching must not be enough")


func test_the_prompt_anchor_can_stay_on_the_door_inside_a_larger_approach_zone() -> void:
	var door := _build()
	var doorstep := CollisionShape3D.new()
	door.position = Vector3(3.0, 0.0, -2.0)
	doorstep.position = Vector3(1.8, 1.1, 1.5)
	door.add_child(doorstep)
	var anchor := Marker3D.new()
	anchor.name = "PromptAnchor"
	anchor.position = Vector3(1.8, 1.3, 0.0)
	door.add_child(anchor)
	door.interaction_anchor_path = NodePath("PromptAnchor")
	assert_eq(door._interaction_anchor(), Vector3(4.8, 1.3, -2.0),
		"the prompt followed the broad trigger instead of its authored point on the door")


func test_a_guided_door_opens_and_requests_one_walk_through_on_e() -> void:
	var door := _build()
	door.guides_entry = true
	door.interaction_id = &"farmhouse_front"
	door.entry_target_offset = Vector3(1.8, 0.0, -1.35)
	_with_bus(door)
	var entries: Array = []
	_bus.subscribe(DoorScript.EVENT_ENTRY_REQUESTED, func(payload): entries.append(payload))
	_occupant = Node3D.new()
	door.set_occupant(_occupant)
	door.on_body_entered(_occupant)
	door._on_interaction_activated({"id": &"door:farmhouse_front"})
	assert_true(door.is_open(), "E began the walk while the leaf still blocked the threshold")
	assert_eq(entries.size(), 1, "one E press requested more than one guided entry")
	if entries.is_empty():
		return
	assert_true(entries[0].get("destination", Vector3.INF) is Vector3,
		"the player received no value-only destination to walk toward")
	for value in entries[0].values():
		assert_false(value is Node, "the guided-entry event leaked a live scene node")


func test_opening_and_shutting_are_announced() -> void:
	var door := _build()
	_with_bus(door)
	door.open()
	door.close()
	assert_eq(Array(_tags()), ["open", "shut"], "both edges must be announced; got %s" % ", ".join(_tags()))


## ...AND WHO WORKED IT. A door only ever toggles for the occupant standing at
## it, so the payload can say who that was -- and while there is exactly one
## character in the world, its silence about that is invisible. Wave 4's bear and
## wave 5's threats come through the same doorway, and a listener choosing a
## sound, or a threat noticing it has been heard, has no way to tell whose door
## this was from a payload that only names the door.
func test_the_announcement_names_who_worked_the_door() -> void:
	var door := _build()
	_with_bus(door)
	_occupant = Node3D.new()
	door.set_occupant(_occupant)
	door.open()
	assert_eq(_events.size(), 1, "expected one announcement")
	if _events.is_empty():
		return
	assert_eq(
		(_events[0]["payload"] as Dictionary).get("occupant", null), _occupant,
		"the door said it opened but not who opened it"
	)


# --- the gate, which is the point -------------------------------------------

func test_walking_through_a_wall_with_the_door_shut_reveals_nothing() -> void:
	var door := _build()
	var reveal: InteriorReveal = InteriorRevealScript.new()
	var list: Array[StringName] = []
	list.assign([&"FH_Fade_Front"])
	reveal.fade_parts = list
	_building.add_child(reveal)
	reveal.entry_gate_path = reveal.get_path_to(door)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)

	reveal.on_body_entered(_occupant)
	assert_true(reveal.is_occupant_inside(), "the body did cross")
	assert_false(reveal.is_revealed(), "with the door shut, the roof must stay on")

	# Opening it from where he stands must open the house, without making him
	# walk back out and in again -- Area3D reports crossing once.
	door.open()
	reveal.reconsider()
	assert_true(reveal.is_revealed(), "opening the door from inside the threshold must reveal")


## Shutting the door behind you must not put the roof back on. The gate guards
## entering and nothing else.
func test_shutting_the_door_behind_you_does_not_put_the_roof_back() -> void:
	var door := _build()
	var reveal: InteriorReveal = InteriorRevealScript.new()
	var list: Array[StringName] = []
	list.assign([&"FH_Fade_Front"])
	reveal.fade_parts = list
	_building.add_child(reveal)
	reveal.entry_gate_path = reveal.get_path_to(door)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	door.open()
	reveal.on_body_entered(_occupant)
	assert_true(reveal.is_revealed(), "he came in through an open door")
	door.close()
	reveal.reconsider()
	assert_true(reveal.is_revealed(), "shutting the door behind him must not drop the roof on his head")


func test_leaving_conceals_however_the_door_is() -> void:
	var door := _build()
	var reveal: InteriorReveal = InteriorRevealScript.new()
	var list: Array[StringName] = []
	list.assign([&"FH_Fade_Front"])
	reveal.fade_parts = list
	_building.add_child(reveal)
	reveal.entry_gate_path = reveal.get_path_to(door)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	door.open()
	reveal.on_body_entered(_occupant)
	door.close()
	reveal.on_body_exited(_occupant)
	assert_false(reveal.is_revealed(), "leaving always puts the building back")


## With no gate at all a reveal must behave exactly as it did before the door
## existed. Wave 4's four buildings will not all have doors on day one.
func test_a_reveal_with_no_gate_is_unchanged() -> void:
	var door := _build()
	var reveal: InteriorReveal = InteriorRevealScript.new()
	var list: Array[StringName] = []
	list.assign([&"FH_Fade_Front"])
	reveal.fade_parts = list
	_building.add_child(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	assert_true(reveal.entry_is_open(), "no gate means nothing to open")
	reveal.on_body_entered(_occupant)
	assert_true(reveal.is_revealed(), "a building with no door still opens when entered")
