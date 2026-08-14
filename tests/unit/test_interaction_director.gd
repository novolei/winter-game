extends TestCase

## One E press, one world object. The farmhouse threshold and its chimney
## beacon overlap, as do the gas-station beacon and the nearest petrol pickup;
## letting every Area3D poll the same action makes one keypress mutate two
## pieces of state. These tests pin the single focus that prevents it.

const DirectorScript := preload("res://src/ui/interaction_director.gd")
const PromptScript := preload("res://src/ui/interaction_prompt.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const DoorScript := preload("res://src/entities/interior/door.gd")
const BeaconScript := preload("res://src/entities/beacon/beacon.gd")

var _bus: Node = null
var _director = null
var _occupant: Node3D = null
var _events: Array = []


class FacingOccupant:
	extends Node3D

	var interaction_heading := Vector3.FORWARD


	func interaction_forward() -> Vector3:
		return interaction_heading


func before_each() -> void:
	_bus = EventBusScript.new()
	_director = DirectorScript.new()
	_director.set_event_bus(_bus)
	_occupant = FacingOccupant.new()
	_director.set_occupant(_occupant)
	_bus.subscribe(&"interaction.activated", _record_activation)


func after_each() -> void:
	Input.action_release(&"interact")
	if _director != null:
		_director.free()
		_director = null
	if _occupant != null:
		_occupant.free()
		_occupant = null
	if _bus != null:
		_bus.free()
		_bus = null
	_events.clear()


func _record_activation(payload) -> void:
	_events.append(payload)


func _offer(id: StringName, at: Vector3, verb := "Use", label := "Thing") -> Dictionary:
	return {
		"id": id,
		"kind": &"test",
		"verb": verb,
		"label": label,
		"world_position": at,
	}


func test_interact_is_a_real_any_device_keyboard_and_gamepad_binding() -> void:
	assert_true(InputMap.has_action(&"interact"), "interact exists only if an entity happened to spawn")
	var key := false
	var pad := false
	for event in InputMap.action_get_events(&"interact"):
		assert_eq(event.device, -1, "the interaction binding ignores the keyboard or pad actually attached")
		if event is InputEventKey and event.physical_keycode == KEY_E:
			key = true
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
			pad = true
	assert_true(key, "GDD section 11's E binding is missing")
	assert_true(pad, "the interaction has no controller path")


func test_the_nearest_offer_is_the_only_focus() -> void:
	_occupant.position = Vector3.ZERO
	_bus.emit_event(&"interaction.offer_entered", _offer(&"far", Vector3(5.0, 0.0, 0.0)))
	_bus.emit_event(&"interaction.offer_entered", _offer(&"near", Vector3(1.0, 0.0, 0.0)))
	_director.reconsider()
	assert_eq(_director.offer_count(), 2)
	assert_eq(_director.focused_id(), &"near", "fixed-camera ambiguity was not resolved by distance")


func test_selection_position_chooses_the_nearest_target_without_moving_the_prompt() -> void:
	var far := _offer(&"far_pigeon", Vector3(0.0, 0.0, -1.0))
	far["target_position"] = Vector3(0.0, 0.0, -4.0)
	var near := _offer(&"near_pigeon", Vector3(0.0, 0.0, -1.0))
	near["target_position"] = Vector3(0.0, 0.0, -2.5)
	_bus.emit_event(&"interaction.offer_entered", far)
	_bus.emit_event(&"interaction.offer_entered", near)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"near_pigeon",
		"two prompts at the player's feet selected a pigeon by id instead of target distance")
	assert_eq(_director.focused_offer().get("world_position"), Vector3(0.0, 0.0, -1.0),
		"target selection moved the visible E leader away from the player")


func test_an_equal_distance_tie_is_stable_and_does_not_follow_event_order() -> void:
	_bus.emit_event(&"interaction.offer_entered", _offer(&"zeta", Vector3.LEFT))
	_bus.emit_event(&"interaction.offer_entered", _offer(&"alpha", Vector3.RIGHT))
	_director.reconsider()
	assert_eq(_director.focused_id(), &"alpha", "an equal tie depends on which Area signal happened first")
	for _tick in range(5):
		_director.reconsider()
		assert_eq(_director.focused_id(), &"alpha", "the prompt flickers between equal candidates")


func test_activation_names_one_stable_id_and_never_carries_a_live_node() -> void:
	_bus.emit_event(&"interaction.offer_entered", _offer(&"one", Vector3.ZERO, "Open", "Door"))
	_director.reconsider()
	assert_true(_director.activate_focused())
	assert_eq(_events.size(), 1, "one activation dispatched more than once")
	if _events.is_empty():
		return
	var payload: Dictionary = _events[0]
	assert_eq(payload.get("id"), &"one")
	for value in payload.values():
		assert_false(value is Node, "an interaction event carries a live scene node")


func test_hold_offer_activates_once_then_latches_until_release() -> void:
	var offer := _offer(&"feed", Vector3(0.0, 0.0, -1.0), "Feed", "Pigeon")
	offer["hold_seconds"] = 0.8
	offer["guide_line"] = true
	_bus.emit_event(&"interaction.offer_entered", offer)

	_director.advance_interaction(0.39, true, true)
	assert_eq(_events.size(), 0, "a partial hold activated the offer")
	assert_almost_eq(_director.hold_progress(), 0.4875, 0.0001)
	_director.advance_interaction(0.41, true)
	assert_eq(_events.size(), 1, "a completed hold did not activate exactly once")
	assert_almost_eq(_director.hold_progress(), 1.0, 0.0001)
	_director.advance_interaction(2.0, true)
	assert_eq(_events.size(), 1, "a held key repeated the completed interaction")

	_director.advance_interaction(0.0, false)
	assert_almost_eq(_director.hold_progress(), 0.0, 0.0001)
	_director.advance_interaction(0.8, true, true)
	assert_eq(_events.size(), 2, "release did not unlock the next deliberate hold")


func test_completed_hold_stays_latched_when_a_new_hold_offer_takes_focus() -> void:
	var first := _offer(&"first_pigeon", Vector3(0.0, 0.0, -1.0), "Feed", "Pigeon")
	first["hold_seconds"] = 0.8
	_bus.emit_event(&"interaction.offer_entered", first)
	_director.advance_interaction(0.8, true, true)
	assert_eq(_events.size(), 1)

	# The feeding producer withdraws the accepted pigeon synchronously, while E
	# may still be physically down. A second bird becoming focus must not inherit
	# that same press as a fresh hold.
	_bus.emit_event(&"interaction.offer_exited", {"id": &"first_pigeon"})
	var second := _offer(&"second_pigeon", Vector3(0.0, 0.0, -1.0), "Feed", "Pigeon")
	second["hold_seconds"] = 0.8
	_bus.emit_event(&"interaction.offer_entered", second)
	assert_eq(_director.focused_id(), &"second_pigeon")
	_director.advance_interaction(0.8, true, false)
	assert_eq(_events.size(), 1,
		"one uninterrupted E hold activated two successive pigeons")

	_director.advance_interaction(0.0, false)
	_director.advance_interaction(0.8, true, true)
	assert_eq(_events.size(), 2,
		"a physical release did not unlock the next deliberate pigeon hold")


func test_releasing_or_losing_focus_resets_partial_hold() -> void:
	var first := _offer(&"first", Vector3(0.0, 0.0, -2.0))
	first["hold_seconds"] = 1.0
	_bus.emit_event(&"interaction.offer_entered", first)
	_director.advance_interaction(0.4, true, true)
	assert_almost_eq(_director.hold_progress(), 0.4, 0.0001)

	_director.advance_interaction(0.0, false)
	assert_almost_eq(_director.hold_progress(), 0.0, 0.0001,
		"releasing E left stale charge in the ring")
	_director.advance_interaction(0.4, true, true)
	_bus.emit_event(&"interaction.offer_exited", {"id": &"first"})
	var second := _offer(&"second", Vector3(0.0, 0.0, -1.0))
	second["hold_seconds"] = 1.0
	_bus.emit_event(&"interaction.offer_entered", second)
	assert_eq(_director.focused_id(), &"second")
	assert_almost_eq(_director.hold_progress(), 0.0, 0.0001,
		"a new focused object inherited the previous object's charge")


func test_facing_gate_uses_the_occupants_stable_interaction_forward() -> void:
	var occupant := _occupant as FacingOccupant
	var offer := _offer(&"feed", Vector3(0.0, 0.0, -2.0))
	offer["hold_seconds"] = 1.0
	offer["facing_dot_min"] = 0.5
	offer["guide_line"] = true
	occupant.interaction_heading = Vector3.BACK
	_bus.emit_event(&"interaction.offer_entered", offer)
	assert_eq(_director.focused_id(), &"", "an offer behind the player's facing direction became focus")

	occupant.interaction_heading = Vector3.FORWARD
	_director.reconsider()
	assert_eq(_director.focused_id(), &"feed", "turning toward the offer did not reveal it")
	var clean: Dictionary = _director.focused_offer()
	assert_almost_eq(float(clean.get("hold_seconds", -1.0)), 1.0, 0.0001)
	assert_almost_eq(float(clean.get("facing_dot_min", -2.0)), 0.5, 0.0001)
	assert_true(bool(clean.get("guide_line", false)))

	_director.advance_interaction(0.4, true, true)
	occupant.interaction_heading = Vector3.BACK
	_director.reconsider()
	assert_eq(_director.focused_id(), &"")
	assert_almost_eq(_director.hold_progress(), 0.0, 0.0001,
		"losing the facing cone kept a partial hold alive")
	assert_eq(_events.size(), 0)


func test_world_anchor_motion_preserves_prompt_and_hold_state() -> void:
	var offer := _offer(&"pigeon", Vector3(0.0, 0.0, -2.0), "Feed", "Pigeon")
	offer["hold_seconds"] = 1.0
	offer["guide_line"] = true
	offer["target_position"] = Vector3(0.0, 0.0, -3.0)
	_bus.emit_event(&"interaction.offer_entered", offer)
	_director.advance_interaction(0.4, true, true)
	var revision: int = _director.prompt_revision()
	var competitor := _offer(&"other_pigeon", Vector3(0.0, 0.0, -1.95), "Feed", "Pigeon")
	competitor["hold_seconds"] = 1.0
	competitor["guide_line"] = true
	_bus.emit_event(&"interaction.offer_entered", competitor)
	assert_eq(_director.focused_id(), &"pigeon",
		"a second wandering pigeon stole an in-progress hold")
	assert_almost_eq(_director.hold_progress(), 0.4, 0.0001,
		"the second pigeon emptied the first pigeon's ring")

	offer["world_position"] = Vector3(0.25, 0.0, -2.0)
	offer["target_position"] = Vector3(0.40, 0.0, -3.0)
	_bus.emit_event(&"interaction.offer_changed", offer)
	assert_eq(_director.prompt_revision(), revision,
		"a moving world anchor rebuilt the prompt instead of moving it in place")
	assert_almost_eq(_director.hold_progress(), 0.4, 0.0001,
		"following a moving prompt and pigeon target discarded the player's hold")
	assert_eq(_director.focused_offer().get("world_position"), Vector3(0.25, 0.0, -2.0))


func test_tap_offer_still_activates_on_the_press_edge() -> void:
	_bus.emit_event(&"interaction.offer_entered", _offer(&"tap", Vector3.ZERO))
	_director.advance_interaction(1.0, true, true)
	assert_eq(_events.size(), 1)
	_director.advance_interaction(1.0, true, false)
	assert_eq(_events.size(), 1, "a tap offer repeated while the key remained held")
	_director.advance_interaction(0.0, false)
	_director.advance_interaction(0.0, true, true)
	assert_eq(_events.size(), 2)


func test_dual_gesture_short_press_activates_tap_once_on_release_and_cancels_on_content_change() -> void:
	var offer := _offer(&"hearth", Vector3.ZERO, "Cook", "Stove")
	offer["hold_seconds"] = 0.8
	offer["alternate_hold"] = true
	offer["hold_verb"] = "Extinguish"
	# Dual gestures deliberately reuse only the pigeon's E ring. A producer
	# cannot accidentally bring the vertical world guide back into an interior.
	offer["guide_line"] = true
	_bus.emit_event(&"interaction.offer_entered", offer)
	var clean: Dictionary = _director.focused_offer()
	assert_true(bool(clean.get("alternate_hold", false)))
	assert_false(bool(clean.get("guide_line", true)))

	assert_false(_director.advance_interaction(0.20, true, true),
		"a dual offer fired its tap action on the press edge")
	assert_eq(_events.size(), 0)
	assert_true(_director.advance_interaction(0.0, false),
		"releasing a short dual gesture did not activate its tap action")
	assert_eq(_events.size(), 1)
	if not _events.is_empty():
		var payload: Dictionary = _events[0]
		assert_eq(payload.get("gesture"), &"tap")
		for value in payload.values():
			assert_false(value is Object, "a dual tap payload carries a live Object")
	assert_false(_director.advance_interaction(0.0, false))
	assert_eq(_events.size(), 1, "one release repeated the dual tap action")

	_director.advance_interaction(0.20, true, true)
	offer["verb"] = "Drink"
	_bus.emit_event(&"interaction.offer_changed", offer)
	assert_almost_eq(_director.hold_progress(), 0.0, 0.0001,
		"changed offer copy kept the previous action's partial gesture")
	_director.advance_interaction(0.0, false)
	assert_eq(_events.size(), 1,
		"releasing after the pictured action changed dispatched a stale tap")


func test_dual_gesture_long_press_activates_hold_once_and_focus_loss_cancels_release() -> void:
	var offer := _offer(&"hearth", Vector3.ZERO, "Eat", "Stove")
	offer["hold_seconds"] = 0.8
	offer["alternate_hold"] = true
	offer["hold_verb"] = "Extinguish"
	_bus.emit_event(&"interaction.offer_entered", offer)

	assert_false(_director.advance_interaction(0.39, true, true))
	assert_true(_director.advance_interaction(0.41, true),
		"completing the dual ring did not activate its hold action")
	assert_eq(_events.size(), 1)
	if not _events.is_empty():
		var payload: Dictionary = _events[0]
		assert_eq(payload.get("gesture"), &"hold")
		for value in payload.values():
			assert_false(value is Object, "a dual hold payload carries a live Object")
	assert_false(_director.advance_interaction(2.0, true))
	assert_eq(_events.size(), 1, "holding E repeated a completed dual gesture")
	assert_false(_director.advance_interaction(0.0, false))
	assert_eq(_events.size(), 1, "releasing a completed hold also fired its tap action")

	_director.advance_interaction(0.20, true, true)
	_bus.emit_event(&"interaction.offer_exited", {"id": &"hearth"})
	_bus.emit_event(&"interaction.offer_entered", _offer(&"door", Vector3.ZERO))
	assert_eq(_director.focused_id(), &"door")
	assert_almost_eq(_director.hold_progress(), 1.0, 0.0001,
		"the replacement tap offer did not start in its ordinary complete-ring state")
	_director.advance_interaction(0.0, false)
	assert_eq(_events.size(), 1,
		"release after focus loss dispatched the departed offer's tap action")


func test_leaving_the_focus_hands_focus_to_the_next_nearest_offer() -> void:
	_bus.emit_event(&"interaction.offer_entered", _offer(&"first", Vector3(1.0, 0.0, 0.0)))
	_bus.emit_event(&"interaction.offer_entered", _offer(&"second", Vector3(2.0, 0.0, 0.0)))
	_director.reconsider()
	assert_eq(_director.focused_id(), &"first")
	_bus.emit_event(&"interaction.offer_exited", {"id": &"first"})
	assert_eq(_director.focused_id(), &"second")


func test_changing_the_focused_offer_refreshes_the_copy_without_changing_focus() -> void:
	_bus.emit_event(&"interaction.offer_entered", _offer(&"hearth", Vector3.ZERO, "Light", "Stove"))
	_director.reconsider()
	assert_eq(_director.focused_id(), &"hearth")
	assert_eq(_director.focused_offer().get("verb"), "Light")
	var first_revision: int = _director.prompt_revision()
	_bus.emit_event(&"interaction.offer_changed", _offer(&"hearth", Vector3.ZERO, "Add fuel", "Stove"))
	assert_eq(_director.focused_id(), &"hearth")
	assert_eq(_director.focused_offer().get("verb"), "Add fuel")
	assert_true(_director.prompt_revision() > first_revision,
		"the same stove id changed state but its visible prompt remained stale")


func test_overlapping_door_and_beacon_do_not_both_consume_one_activation() -> void:
	var door := DoorScript.new() as Door
	door.interaction_id = &"test_door"
	door.position = Vector3.ZERO
	door.set_occupant(_occupant)
	door.set_event_bus(_bus)
	door.on_body_entered(_occupant)

	var definition := BeaconDefinition.new()
	definition.id = &"test_beacon"
	definition.display_name = "Test beacon"
	definition.world_position = Vector3(2.0, 0.0, 0.0)
	var beacon := BeaconScript.new() as Beacon
	beacon.definition = definition
	beacon.position = definition.world_position
	beacon.set_occupant(_occupant)
	beacon.set_event_bus(_bus)
	beacon.set_unlocked(true)
	beacon.add_fuel_seconds(100.0)
	beacon._on_body_entered(_occupant)

	_occupant.position = Vector3(0.1, 0.0, 0.0)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"door:test_door")
	assert_true(_director.activate_focused())
	assert_true(door.is_open(), "the nearest door did not consume the interaction")
	assert_false(beacon.is_lit(), "the overlapping beacon consumed the door's same keypress")

	door.on_body_exited(_occupant)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"beacon:test_beacon")
	assert_true(_director.activate_focused())
	assert_true(beacon.is_lit(), "the beacon did not become focus after leaving the door")
	assert_true(door.is_open(), "activating the beacon toggled the departed door")
	door.free()
	beacon.free()


func test_the_prompt_is_ring_and_specific_copy_without_a_panel() -> void:
	var layer := UILayer.new()
	layer.build()
	var prompt = PromptScript.new()
	assert_true(prompt.build(layer.tokens(), layer.fonts(), "E", "Pick up", "Firewood"))
	prompt.layout_for(Vector2(1920.0, 1080.0))
	assert_eq(prompt.key_text(), "E")
	assert_eq(prompt.copy_text(), "Pick up · Firewood")
	assert_true(prompt.size.x > prompt.size.y, "the verb was not laid beside the key ring")
	assert_eq(prompt.get_child_count(), 0, "the prompt grew a rectangular panel child")
	prompt.free()
	layer.free()


func test_hold_prompt_adds_a_clamped_progress_arc_and_vertical_guide() -> void:
	var layer := UILayer.new()
	layer.build()
	var prompt = PromptScript.new()
	assert_true(prompt.build(layer.tokens(), layer.fonts(), "E", "Feed", "Pigeon"))
	var theme_green := Color(0.32, 1.0, 0.18, 1.0)
	prompt.set_accent_color(theme_green)
	var guide_grey := Color("#667890")
	prompt.set_guide_color(guide_grey)
	var ordinary_size: Vector2 = prompt.layout_for(Vector2(1920.0, 1080.0))
	prompt.set_guide_line(true)
	prompt.set_hold_progress(1.5)
	var guided_size: Vector2 = prompt.layout_for(Vector2(1920.0, 1080.0))
	assert_true(prompt.guide_line_enabled())
	assert_true(prompt.has_accent_color())
	assert_eq(prompt.accent_color(), theme_green)
	assert_true(prompt.has_guide_color())
	assert_eq(prompt.guide_color(), guide_grey)
	assert_almost_eq(prompt.guide_color().a, 1.0, 0.0001,
		"the straight guide colour carries the old low-opacity treatment")
	assert_almost_eq(prompt.hold_progress(), 1.0, 0.0001)
	assert_true(guided_size.y > ordinary_size.y,
		"the guide line has no vertical drawing space beneath the key ring")
	var guide: PackedVector2Array = prompt.guide_line_points()
	assert_eq(guide.size(), 2, "the low-key guide is no longer one straight segment")
	if guide.size() == 2:
		var ring_bottom := ordinary_size.y
		assert_true(guide[0].y >= ring_bottom + prompt.guide_gap_pixels() - 1.0,
			"the guide touches the hold ring instead of leaving the requested gap")
		assert_almost_eq(guide[0].x, guide[1].x, 0.0001,
			"the requested straight guide still bows sideways")
	prompt.set_hold_progress(-0.5)
	assert_almost_eq(prompt.hold_progress(), 0.0, 0.0001)
	prompt.set_guide_line(false)
	var restored_size: Vector2 = prompt.layout_for(Vector2(1920.0, 1080.0))
	assert_almost_eq(restored_size.y, ordinary_size.y, 0.0001,
		"turning the guide off left its old minimum height behind")
	prompt.free()
	layer.free()


func test_entities_no_longer_poll_the_shared_action_independently() -> void:
	for path in [
		"res://src/entities/interior/door.gd",
		"res://src/entities/beacon/beacon.gd",
		"res://src/entities/survival_route_node.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_false(source.contains("Input.is_action_just_pressed(interact_action)"),
			"%s still races every overlapping interaction Area for the same E press" % path)


func test_main_scene_runs_the_single_interaction_director() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("res://src/ui/interaction_director.gd"))
	assert_eq(source.count("script = ExtResource(\"50_interaction\")"), 1,
		"Main must have exactly one input owner")


func test_live_layer_owns_its_build_instead_of_the_child_mutating_a_busy_parent() -> void:
	var layer := UILayer.new()
	var director = DirectorScript.new()
	layer.add_child(director)
	Engine.get_main_loop().root.add_child(layer)
	assert_not_null(layer.tokens(), "UILayer did not complete its own ready-time build")
	layer.free()
