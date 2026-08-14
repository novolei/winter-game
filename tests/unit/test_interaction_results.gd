extends TestCase

const ResultSurfacingScript := preload("res://src/ui/interaction_result_surfacing.gd")
const ReceiptScript := preload("res://src/ui/interaction_receipt.gd")
const DirectorScript := preload("res://src/ui/interaction_director.gd")
const UILayerScript := preload("res://src/ui/ui_layer.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _layer: UILayer = null
var _bus: Node = null
var _results: InteractionResultSurfacing = null


func before_each() -> void:
	_layer = UILayerScript.new()
	_layer.build()
	_bus = EventBusScript.new()
	_results = ResultSurfacingScript.new()
	_results.set_layer(_layer)
	_results.set_event_bus(_bus)
	_results.build()


func after_each() -> void:
	if _results != null:
		_results.free()
		_results = null
	if _layer != null:
		_layer.free()
		_layer = null
	if _bus != null:
		_bus.free()
		_bus = null


func _emit(event_id: StringName, payload: Dictionary) -> void:
	_bus.emit_event(event_id, payload)


func test_it_subscribes_once_to_every_result_event() -> void:
	_results.set_event_bus(_bus)
	for event_id in [
		&"item.picked_up",
		&"beacon.fueled",
		&"beacon.lit",
		&"stove.stoked",
		&"interaction.rejected",
	]:
		assert_eq(_bus.subscriber_count(event_id), 1, "%s was not subscribed exactly once" % event_id)


func test_beacon_fueled_and_lit_in_one_dispatch_turn_become_one_receipt() -> void:
	_emit(&"beacon.fueled", {
		"id": &"gas_station", "label": "Gas station", "added_seconds": 600.0,
		"fuel_seconds": 600.0, "world_position": Vector3(2.0, 0.0, 3.0),
	})
	_emit(&"beacon.lit", {
		"id": &"gas_station", "label": "Gas station", "fuel_seconds": 600.0,
		"world_position": Vector3(2.0, 0.0, 3.0),
	})
	assert_eq(_results.pending_count(), 1, "the synchronous beacon pair was queued twice")
	_results.flush_pending()
	assert_eq(_results.live_count(), 1)
	assert_eq(_layer.live_count(), 1)
	var receipt = _results.active_for(&"beacon:gas_station")
	assert_not_null(receipt)
	if receipt != null:
		assert_eq(receipt.copy_text(), "Lit · Gas station")
		assert_eq(receipt.amount_text(), "+10:00")


func test_beacon_merge_does_not_depend_on_event_order() -> void:
	_emit(&"beacon.lit", {
		"id": &"church", "label": "Church", "fuel_seconds": 300.0,
		"world_position": Vector3.ZERO,
	})
	_emit(&"beacon.fueled", {
		"id": &"church", "label": "Church", "added_seconds": 300.0,
		"fuel_seconds": 300.0, "world_position": Vector3.ZERO,
	})
	_results.flush_pending()
	var receipt = _results.active_for(&"beacon:church")
	assert_not_null(receipt)
	if receipt != null:
		assert_eq(receipt.copy_text(), "Lit · Church")
		assert_eq(receipt.amount_text(), "+5:00")


func test_two_beacons_in_one_turn_do_not_merge() -> void:
	_emit(&"beacon.fueled", {
		"id": &"alpha", "added_seconds": 60.0, "world_position": Vector3.ZERO,
	})
	_emit(&"beacon.lit", {
		"id": &"beta", "fuel_seconds": 60.0, "world_position": Vector3.ONE,
	})
	assert_eq(_results.pending_count(), 2)
	_results.flush_pending()
	assert_eq(_results.live_count(), 2, "different beacon identities collapsed into one receipt")


func test_pickup_stove_and_rejection_each_surface_current_payloads() -> void:
	_emit(&"item.picked_up", {
		"node_id": &"wood_01", "item_id": &"firewood", "count": 2, "total": 4,
		"world_position": Vector3.ZERO,
	})
	_emit(&"stove.stoked", {
		"id": &"farmhouse_hearth", "added_seconds": 600.0, "fuel_seconds": 1200.0,
		"lit": true, "world_position": Vector3.ONE,
	})
	_emit(&"interaction.rejected", {
		"id": &"beacon:locked", "kind": &"beacon", "reason": &"locked",
		"world_position": Vector3(2.0, 0.0, 0.0),
	})
	_results.flush_pending()
	assert_eq(_results.live_count(), 3)
	var pickup = _results.active_for(&"pickup:firewood")
	var stove = _results.active_for(&"stove:farmhouse_hearth")
	var rejected = _results.active_for(&"rejected:beacon:locked")
	assert_not_null(pickup)
	assert_not_null(stove)
	assert_not_null(rejected)
	if pickup != null:
		assert_eq(pickup.copy_text(), "Picked up · Firewood")
		assert_eq(pickup.amount_text(), "+2 · 4")
	if stove != null:
		assert_eq(stove.amount_text(), "+10:00")
	if rejected != null:
		assert_eq(rejected.copy_text(), "Beacon · Locked")
		assert_true(rejected.is_rejected())


func test_repeated_pickup_updates_one_control_and_refreshes_its_hold() -> void:
	_emit(&"item.picked_up", {
		"item_id": &"firewood", "count": 1, "total": 1,
		"world_position": Vector3.ZERO,
	})
	_results.flush_pending()
	var first = _results.active_for(&"pickup:firewood")
	assert_not_null(first)
	_layer.advance(_layer.tokens().bloom_seconds + 1.0)
	_emit(&"item.picked_up", {
		"item_id": &"firewood", "count": 2, "total": 3,
		"world_position": Vector3.ZERO,
	})
	_results.flush_pending()
	var refreshed = _results.active_for(&"pickup:firewood")
	assert_eq(refreshed, first, "the same item allocated another receipt")
	assert_eq(_layer.live_count(), 1, "refreshing adopted the same Control twice")
	if refreshed != null:
		assert_eq(refreshed.amount_text(), "+2 · 3")
	var breath: Breath = _layer.breath_for(refreshed)
	assert_not_null(breath)
	if breath != null:
		_layer.advance(breath.hold_seconds - 0.01)
		assert_eq(_layer.live_count(), 1, "the refreshed receipt kept its old death time")


func test_receipts_are_self_drawn_and_die_without_a_hud() -> void:
	var receipt = ReceiptScript.new()
	assert_true(receipt.build(_layer.tokens(), _layer.fonts(), {
		"key": &"test", "copy": "Picked up · Coal", "amount": "+1",
		"icon_id": &"coal", "rejected": false,
	}))
	receipt.layout_for(Vector2(1920.0, 1080.0))
	assert_eq(receipt.get_child_count(), 0, "the receipt grew a panel or Label child")
	assert_eq(receipt.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_layer.surface(receipt, InteractionResultSurfacing.SUCCESS_HOLD_SECONDS)
	var whole := _layer.tokens().bloom_seconds \
		+ InteractionResultSurfacing.SUCCESS_HOLD_SECONDS \
		+ _layer.tokens().drift_seconds + 0.01
	_layer.advance(whole)
	assert_eq(_layer.live_count(), 0, "the receipt became a permanent HUD element")


func test_malformed_and_unknown_events_are_silent() -> void:
	_bus.emit_event(&"item.picked_up", null)
	_bus.emit_event(&"beacon.fueled", "not a dictionary")
	_results.ingest(&"not.a.result", {"id": &"ignored"})
	_results.flush_pending()
	assert_eq(_results.pending_count(), 0)
	assert_eq(_results.live_count(), 0)
	assert_eq(_layer.live_count(), 0)


func test_ui_layer_rehome_survives_the_next_advance_and_keeps_drift() -> void:
	var control := Control.new()
	control.size = Vector2(100.0, 30.0)
	control.position = Vector2(10.0, 20.0)
	_layer.surface(control, 0.0)
	assert_true(_layer.rehome(control, Vector2(300.0, 220.0)))
	_layer.advance(_layer.tokens().bloom_seconds + _layer.tokens().drift_seconds * 0.5)
	var breath: Breath = _layer.breath_for(control)
	assert_not_null(breath)
	if breath != null:
		var expected := Vector2(300.0, 220.0) \
			+ breath.offset_at(_layer.tokens().bloom_seconds + _layer.tokens().drift_seconds * 0.5)
		assert_almost_eq(control.position.x, expected.x, 0.001)
		assert_almost_eq(control.position.y, expected.y, 0.001,
			"UILayer restored the first projected home instead of the latest one")


func test_interaction_director_rehomes_a_moving_world_prompt() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/interaction_director.gd")
	assert_true(source.contains("_layer.rehome(_prompt, _prompt.position)"),
		"the prompt projector never updates UILayer's captured home")


func test_success_receipts_do_not_play_a_second_confirmation_sound() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/interaction_result_surfacing.gd")
	assert_false(source.contains(".audio().play"),
		"the result layer duplicates InteractionDirector's ui.ripple")
	assert_false(source.contains("audio.play"),
		"success feedback must remain visually silent until activation sound ownership moves")


func test_main_runs_exactly_one_result_surfacing() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("res://src/ui/interaction_result_surfacing.gd"))
	assert_eq(source.count("[node name=\"ResultSurfacing\""), 1)
	assert_eq(source.count("script = ExtResource(\"51_interaction_results\")"), 1)


func test_a_live_result_child_lets_its_parent_finish_building_the_ui_stack() -> void:
	var layer := UILayerScript.new()
	var results := ResultSurfacingScript.new()
	results.set_event_bus(_bus)
	layer.add_child(results)
	Engine.get_main_loop().root.add_child(layer)
	assert_not_null(layer.tokens(), "the live UILayer never completed its own build")
	assert_not_null(layer.audio(), "child ready-time work stranded the UI voice off-tree")
	assert_eq(results.get_parent(), layer)
	layer.free()
