extends TestCase

## The route's fuel is not a score. It has to reach the farmhouse hearth
## through the same one-focus interaction contract as doors, pickups and lamps.

const StoveScript := preload("res://src/entities/stove/stove.gd")
const DirectorScript := preload("res://src/ui/interaction_director.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _bus: Node = null
var _economy: Node = null
var _stove = null
var _director = null
var _occupant: Node3D = null
var _events: Array = []


func before_each() -> void:
	_bus = EventBusScript.new()
	_economy = FuelEconomyScript.new()
	_economy.load_from_directory()
	_occupant = Node3D.new()
	_director = DirectorScript.new()
	_director.set_event_bus(_bus)
	_director.set_occupant(_occupant)
	_bus.subscribe(&"stove.stoked", _record)
	_bus.subscribe(&"interaction.rejected", _record)
	_stove = StoveScript.new()
	_stove.interaction_id = &"test_hearth"
	_stove.set_fuel_economy(_economy)
	_stove.set_event_bus(_bus)
	_stove.set_occupant(_occupant)


func after_each() -> void:
	for node in [_stove, _director, _occupant, _economy, _bus]:
		if node != null:
			node.free()
	_stove = null
	_director = null
	_occupant = null
	_economy = null
	_bus = null
	_events.clear()


func _record(payload) -> void:
	_events.append(payload)


func test_the_stove_builds_one_real_interaction_area() -> void:
	_stove._ready()
	var area = _stove.interaction_area()
	assert_not_null(area, "the placed stove has no volume the player can enter")
	if area == null:
		return
	assert_true(area is Area3D)
	assert_eq(area.get_child_count(), 1, "the stove interaction grew duplicate shapes")
	assert_true(area.get_child(0) is CollisionShape3D)
	var shape := (area.get_child(0) as CollisionShape3D).shape
	assert_true(shape is BoxShape3D, "the stove's spherical prompt reaches through the farmhouse wall")
	assert_false(_stove.interaction_anchor_position().is_equal_approx(area.position),
		"the readable firebox anchor is coupled to the physical body-detection volume")


func test_one_activation_banks_one_whole_fuel_and_lights_the_hearth() -> void:
	_economy.add(&"firewood", 1)
	var worth: float = _economy.definition_of(&"firewood").fuel_value
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"stove:test_hearth")
	assert_true(_director.activate_focused())
	assert_eq(_economy.count_of(&"firewood"), 0, "the log stayed in the pack after going on the fire")
	assert_almost_eq(_stove.fuel_remaining(), worth, 0.001,
		"one interaction did not preserve the whole log's authored burn value")
	assert_true(_stove.is_lit(), "a cold empty hearth took fuel but did not ignite")
	assert_eq(_events.size(), 1, "the one stove action produced no single stable result")
	if _events.is_empty():
		return
	assert_eq(_events[0].get("id"), &"test_hearth")
	assert_almost_eq(float(_events[0].get("added_seconds", 0.0)), worth, 0.001)
	for value in (_events[0] as Dictionary).values():
		assert_false(value is Node, "stove.stoked carried a live scene node")


func test_a_burning_stove_adds_one_item_without_double_spending() -> void:
	_stove.add_fuel_seconds(120.0)
	_stove.light()
	_economy.add(&"petrol", 2)
	var worth: float = _economy.definition_of(&"petrol").fuel_value
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_true(_director.activate_focused())
	assert_eq(_economy.count_of(&"petrol"), 1, "one E consumed more than one fuel item")
	assert_almost_eq(_stove.fuel_remaining(), 120.0 + worth, 0.001)


func test_no_fuel_keeps_the_stove_visible_as_a_refusal_and_spends_nothing() -> void:
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"stove:test_hearth",
		"an empty pack made the hearth prompt disappear instead of explaining the refusal")
	assert_false(_director.activate_focused())
	assert_false(_stove.is_lit())
	assert_eq(_stove.fuel_remaining(), 0.0)
	assert_eq(_events.size(), 1)
	if _events.is_empty():
		return
	assert_eq(_events[0].get("reason"), &"no_fuel")


func test_stale_enabled_offer_returns_a_refusal_when_its_fuel_was_just_spent() -> void:
	_economy.add(&"firewood", 1)
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"stove:test_hearth")
	assert_eq(_economy.take(&"firewood", 1), 1,
		"the fixture did not create the stale-offer race")
	assert_true(_director.activate_focused(), "the cached enabled command was not dispatched")
	assert_false(_stove.is_lit())
	assert_eq(_events.size(), 1, "the failed command remained silent")
	if not _events.is_empty():
		assert_eq(_events[0].get("reason"), &"no_fuel")


func test_leaving_the_hearth_withdraws_its_offer() -> void:
	_stove.on_body_entered(_occupant)
	assert_eq(_director.offer_count(), 1)
	_stove.on_body_exited(_occupant)
	assert_eq(_director.offer_count(), 0, "the hearth prompt remained after walking away")


func test_main_authors_a_stable_hearth_identity() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("interaction_id = &\"farmhouse_hearth\""),
		"the shipped stove falls back to an unstable runtime path")
