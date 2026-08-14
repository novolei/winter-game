extends TestCase

## The route's fuel is not a score. It has to reach the farmhouse hearth
## through the same one-focus interaction contract as doors, pickups and lamps.

const StoveScript := preload("res://src/entities/stove/stove.gd")
const DirectorScript := preload("res://src/ui/interaction_director.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _bus: Node = null
var _economy: Node = null
var _survival: Node = null
var _stove = null
var _director = null
var _occupant: Node3D = null
var _events: Array = []


func before_each() -> void:
	_bus = EventBusScript.new()
	_economy = FuelEconomyScript.new()
	_economy.load_from_directory()
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	_economy.set_survival_system(_survival)
	_occupant = Node3D.new()
	_director = DirectorScript.new()
	_director.set_event_bus(_bus)
	_director.set_occupant(_occupant)
	_bus.subscribe(&"stove.stoked", _record)
	_bus.subscribe(&"interaction.rejected", _record)
	_stove = StoveScript.new()
	_stove.interaction_id = &"test_hearth"
	_stove.set_fuel_economy(_economy)
	_stove.set_survival_system(_survival)
	_stove.set_event_bus(_bus)
	_stove.set_occupant(_occupant)


func after_each() -> void:
	for node in [_stove, _director, _occupant, _economy, _survival, _bus]:
		if node != null:
			node.free()
	_stove = null
	_director = null
	_occupant = null
	_economy = null
	_survival = null
	_bus = null
	_events.clear()


func _record(payload) -> void:
	_events.append(payload)


func _drop_to(stat_id: StringName, value: float) -> void:
	_survival.push_modifier(stat_id, &"test_drop", Modifier.Operation.MULTIPLY, 200.0)
	var guard := 0
	while _survival.value_of(stat_id) > value and not _survival.is_dead() and guard < 10000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")


func _tap_e() -> bool:
	var activated: bool = bool(_director.advance_interaction(0.10, true, true))
	activated = _director.advance_interaction(0.0, false) or activated
	return activated


func _hold_e() -> bool:
	var offer: Dictionary = _director.focused_offer()
	var duration := float(offer.get("hold_seconds", 0.0))
	var activated: bool = bool(_director.advance_interaction(duration, true, true))
	activated = _director.advance_interaction(0.0, false) or activated
	return activated


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


func test_two_e_presses_cook_then_eat_through_the_world_interaction() -> void:
	_drop_to(&"hunger", 0.20)
	_stove.add_fuel_seconds(600.0)
	_stove.light()
	_economy.add(&"canned_stew", 1)
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_offer().get("verb"), "Cook Tin of stew")
	var fuel_before: float = _stove.fuel_remaining()
	var cook_cost: float = _economy.definition_of(&"canned_stew").heat_seconds

	assert_true(_tap_e(), "the first E press never reached the stove's cook command")
	assert_eq(_economy.count_of(&"canned_stew"), 0)
	assert_eq(_economy.count_of(&"hot_stew"), 1)
	assert_almost_eq(_stove.fuel_remaining(), fuel_before - cook_cost, 0.001)
	assert_eq(_director.focused_offer().get("verb"), "Eat Hot stew",
		"cooking did not refresh the same hearth prompt into the next action")

	var hunger_before: float = _survival.value_of(&"hunger")
	assert_true(_tap_e(), "the second E press never reached the eat command")
	assert_eq(_economy.count_of(&"hot_stew"), 0)
	assert_true(_survival.value_of(&"hunger") > hunger_before,
		"the player ate at the hearth but hunger did not recover")


func test_two_e_presses_melt_then_drink_through_the_world_interaction() -> void:
	_drop_to(&"thirst", 0.20)
	_stove.add_fuel_seconds(600.0)
	_stove.light()
	_economy.add(&"snow", 1)
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_offer().get("verb"), "Melt Packed snow")
	var fuel_before: float = _stove.fuel_remaining()
	var melt_cost: float = _economy.definition_of(&"snow").heat_seconds

	assert_true(_tap_e(), "the first E press never reached the stove's melt command")
	assert_eq(_economy.count_of(&"snow"), 0)
	assert_eq(_economy.count_of(&"meltwater"), 1)
	assert_almost_eq(_stove.fuel_remaining(), fuel_before - melt_cost, 0.001)
	assert_eq(_director.focused_offer().get("verb"), "Drink Meltwater")

	var thirst_before: float = _survival.value_of(&"thirst")
	assert_true(_tap_e(), "the second E press never reached the drink command")
	assert_eq(_economy.count_of(&"meltwater"), 0)
	assert_true(_survival.value_of(&"thirst") > thirst_before,
		"the player drank at the hearth but thirst did not recover")


func test_hold_e_can_extinguish_without_processing_or_spending_while_hungry_and_thirsty() -> void:
	_drop_to(&"hunger", 0.20)
	_drop_to(&"thirst", 0.20)
	_stove.add_fuel_seconds(600.0)
	_stove.light()
	_economy.add(&"snow", 1)
	_economy.add(&"canned_stew", 1)
	_economy.add(&"firewood", 1)
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	var offer: Dictionary = _director.focused_offer()
	assert_true(bool(offer.get("alternate_hold", false)),
		"the hearth did not expose its opt-in hold gesture")
	assert_eq(offer.get("hold_verb"), "Extinguish")
	assert_false(bool(offer.get("guide_line", false)),
		"the hearth copied the pigeon's vertical lead instead of only its E ring")

	var fuel_before: float = _stove.fuel_remaining()
	assert_true(_hold_e(), "holding the shared E ring did not reach the stove")
	assert_false(_stove.is_lit(), "the hold action left the fire burning")
	assert_almost_eq(_stove.fuel_remaining(), fuel_before, 0.001,
		"smothering destroyed the fuel already banked in the firebox")
	assert_eq(_economy.count_of(&"snow"), 1,
		"the hold also ran the short-press processing action")
	assert_eq(_economy.count_of(&"canned_stew"), 1,
		"the hold forced the player to cook or eat before banking the fire")
	assert_eq(_economy.count_of(&"firewood"), 1,
		"smothering silently added another log")


func test_short_e_can_add_repeated_fuel_items_until_nominal_capacity() -> void:
	_stove.add_fuel_seconds(120.0)
	_stove.light()
	_economy.add(&"firewood", 6)
	_stove.on_body_entered(_occupant)
	_director.reconsider()

	for remaining in range(5, -1, -1):
		assert_eq(_director.focused_offer().get("verb"), "Add fuel")
		assert_true(_tap_e(), "a short E press stopped refilling below capacity")
		assert_eq(_economy.count_of(&"firewood"), remaining)
	assert_almost_eq(_stove.fuel_remaining(), 3720.0, 0.001,
		"whole-item refilling did not preserve the documented capacity overflow")
	assert_eq(_director.focused_offer().get("verb"), "Extinguish",
		"the prompt did not stop offering fuel after the nominal capacity")


func test_a_stale_processing_command_refuses_without_touching_another_item() -> void:
	_drop_to(&"thirst", 0.20)
	_stove.add_fuel_seconds(600.0)
	_stove.light()
	_economy.add(&"snow", 1)
	_economy.add(&"canned_stew", 1)
	_stove.on_body_entered(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_offer().get("verb"), "Melt Packed snow")
	assert_eq(_economy.take(&"snow", 1), 1, "the fixture did not stale the pictured item")

	assert_true(_director.activate_focused(), "the cached value command was not dispatched")
	assert_eq(_economy.count_of(&"meltwater"), 0)
	assert_eq(_economy.count_of(&"canned_stew"), 1,
		"a stale snow command fell through and cooked a different inventory item")
	assert_eq(_events.size(), 1)
	if not _events.is_empty():
		assert_eq(_events[0].get("reason"), &"stale_action")


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
