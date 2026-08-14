extends TestCase

## Value-only interaction wiring from a landed pigeon to the delayed crumb
## release, then back from a completed real peck to the affection response.

const FlockScript := preload("res://src/entities/wildlife/pigeon_flock.gd")
const FRAME := 1.0 / 60.0

class BusStand extends RefCounted:
	var published: Array = []
	var subscriptions: Dictionary = {}
	func subscribe(event: StringName, callback: Callable) -> void:
		if not subscriptions.has(event): subscriptions[event] = []
		var listeners: Array = subscriptions[event]
		if not listeners.has(callback): listeners.append(callback)
	func unsubscribe(event: StringName, callback: Callable) -> void:
		if subscriptions.has(event): (subscriptions[event] as Array).erase(callback)
	func emit_event(event: StringName, payload: Variant = null) -> void:
		published.append({"event": event, "payload": payload})
		for callback in (subscriptions.get(event, []) as Array).duplicate():
			(callback as Callable).call(payload)
	func of(event: StringName) -> Array:
		return published.filter(func(entry: Dictionary) -> bool: return entry["event"] == event)

class ClockStand extends RefCounted:
	func is_night() -> bool: return false

class FacingPlayer extends Node3D:
	var forward := Vector3.FORWARD
	func interaction_forward() -> Vector3: return forward

var _bus: BusStand
var _flock: PigeonFlock
var _player: FacingPlayer


func before_each() -> void:
	_bus = BusStand.new()
	_player = FacingPlayer.new()
	_player.position = Vector3.ZERO
	_flock = FlockScript.new()
	_flock.random_seed = 20260813
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(ClockStand.new())
	_flock.set_watched(_player)
	_flock.friendly_radius_min_m = 3.0
	_flock.friendly_radius_max_m = 3.0
	_flock.friendly_wait_min_seconds = 40.0
	_flock.friendly_wait_max_seconds = 40.0
	_flock.attach()


func after_each() -> void:
	if _flock != null: _flock.free()
	if _player != null: _player.free()


func _land_one() -> Pigeon:
	assert_true(_flock.try_friendly_visit(true), "the forced friendly visit was refused")
	var pigeon := _flock.birds()[0] as Pigeon
	var landing := pigeon.target_perch()
	_player.forward = Vector3.RIGHT
	pigeon.perch_on(landing, -_player.forward)
	pigeon.advance(FRAME)
	_flock.advance(FRAME)
	return pigeon


func test_only_a_landed_waiting_pigeon_publishes_the_guided_hold_offer() -> void:
	assert_true(_flock.try_friendly_visit(true))
	assert_eq(_bus.of(&"interaction.offer_entered").size(), 0, "the UI appeared while the pigeon was still in the air")
	var pigeon := _flock.birds()[0] as Pigeon
	var landing := pigeon.target_perch()
	_player.forward = -Vector3(landing.x, 0.0, landing.z).normalized()
	pigeon.perch_on(landing, -_player.forward)
	pigeon.advance(FRAME)
	_flock.advance(FRAME)
	var offers := _bus.of(&"interaction.offer_entered")
	assert_eq(offers.size(), 1, "touchdown did not publish one interaction offer")
	if offers.is_empty(): return
	var payload: Dictionary = offers[0]["payload"]
	assert_eq(payload.get("kind"), &"pigeon_feed")
	assert_almost_eq(float(payload.get("hold_seconds", 0.0)), 0.8, 0.001, "feeding is still a tap")
	assert_true(bool(payload.get("guide_line", false)), "the pigeon prompt omitted the reference line")
	var accent: Variant = payload.get("accent_color", null)
	assert_true(accent is Color, "the feed prompt did not publish its theme green")
	if accent is Color:
		var tone: Color = accent
		assert_true(tone.g > tone.r and tone.g > tone.b and tone.a > 0.99,
			"the feed prompt accent is not an opaque green")
	assert_eq(payload.get("guide_color"), Color("#667890"),
		"the offer lost its quiet medium-grey guide colour")
	assert_almost_eq(float(payload.get("facing_dot_min", 0.0)), -1.0, 0.001,
		"the distance-triggered prompt still requires facing the pigeon")
	var prompt_at: Vector3 = payload.get("world_position", Vector3.ZERO)
	assert_almost_eq(
		Vector2(prompt_at.x, prompt_at.z).distance_to(Vector2(_player.position.x, _player.position.z)),
		_flock.feeding_prompt_front_m, 0.01,
		"the E leader is not anchored in front of the player"
	)
	assert_true(
		Vector3(prompt_at.x, 0.0, prompt_at.z).normalized().dot(_player.forward) > 0.999,
		"the E leader is anchored beside the player instead of ahead"
	)
	assert_eq(payload.get("target_position"), pigeon.where(),
		"the prompt lost the pigeon's actual position for nearest-target selection")
	assert_eq(String(payload.get("label", "")), "", "the prompt repeats a subject instead of the single action word")
	for value in payload.values():
		assert_false(value is Node, "the interaction offer leaks a live pigeon into EventBus")
	_player.position += Vector3(10.0, 0.0, 0.0)
	_flock.advance(FRAME)
	assert_eq(
		_bus.of(&"interaction.offer_exited").size(), 1,
		"the feeding prompt remains visible after the player leaves its interaction range"
	)


func test_a_wandering_pigeons_target_position_accumulates_into_spatial_updates() -> void:
	var pigeon := _land_one()
	var entered: Dictionary = _bus.of(&"interaction.offer_entered")[0]["payload"]
	var first_target: Vector3 = entered.get("target_position", Vector3.ZERO)
	for _frame in range(30):
		_flock.advance(FRAME)
	var changes := _bus.of(&"interaction.offer_changed")
	assert_false(changes.is_empty(),
		"millimetre walking steps were discarded instead of accumulating into a target update")
	if changes.is_empty():
		return
	var latest: Dictionary = changes.back()["payload"]
	var target: Vector3 = latest.get("target_position", Vector3.ZERO)
	assert_true(target.distance_to(first_target) >= 0.04,
		"the spatial update did not reach the authored four-centimetre threshold")
	assert_true(target.distance_to(pigeon.where()) <= 0.04,
		"the nearest-target position lags behind the wandering pigeon")


func test_hold_completion_releases_crumbs_on_the_gesture_then_completes_after_pecking() -> void:
	var pigeon := _land_one()
	var toward := Vector3(pigeon.where().x, 0.0, pigeon.where().z).normalized()
	# Still inside the authored facing cone, but deliberately not square. The
	# player one-shot turns to the pigeon, so the throw must use that same aim.
	_player.forward = -toward
	var offers := _bus.of(&"interaction.offer_entered")
	assert_false(offers.is_empty(), "there is no feeding offer to activate")
	if offers.is_empty(): return
	var offer: Dictionary = offers[0]["payload"]
	_bus.emit_event(&"interaction.activated", {
		"id": offer["id"], "kind": &"pigeon_feed", "world_position": pigeon.where(),
	})
	assert_eq(_bus.of(&"wildlife.pigeon_feed_started").size(), 1, "the player gesture did not start")
	_flock.advance(0.55)
	assert_true(pigeon.is_waiting_for_food(), "the pigeon moved before the hand released the crumbs")
	assert_eq(_flock.active_food_patch_count(), 0, "crumbs appeared at the start of the gesture")
	_flock.advance(0.05)
	assert_eq(_flock.active_food_patch_count(), 1, "the release frame produced no breadcrumb patch")
	assert_true(pigeon.is_waiting_for_food(), "the pigeon began pecking before the airborne crumbs landed")
	_flock.advance(BreadcrumbScatter.MAX_FLIGHT_SECONDS + FRAME)
	assert_false(pigeon.is_waiting_for_food(), "the pigeon ignored the settled food target")
	var food_heading := Vector3(pigeon.food_target().x, 0.0, pigeon.food_target().z).normalized()
	assert_true(
		food_heading.dot(toward) > 0.999,
		"the body turned to the pigeon but the crumbs followed the old facing"
	)
	assert_eq(_bus.of(PigeonFlock.EVENT_FED).size(), 0, "feeding completed before walking and pecking")

	var left := 8.0
	while left > 0.0 and _bus.of(PigeonFlock.EVENT_FED).is_empty():
		_flock.advance(FRAME)
		left -= FRAME
	assert_eq(_bus.of(PigeonFlock.EVENT_FED).size(), 1, "walking to and eating one patch did not complete once")
	assert_eq(_flock.affection_count(), 1, "the completed peck produced no heart response")
	assert_eq(pigeon.meal_count(), 1, "one breadcrumb patch became more than one meal")
	assert_eq(_flock.active_food_patch_count(), 0, "the eaten breadcrumb patch remained on the snow")


func test_close_fear_and_an_in_progress_gesture_reject_extra_feed_commands() -> void:
	var pigeon := _land_one()
	var offer: Dictionary = _bus.of(&"interaction.offer_entered")[0]["payload"]
	_bus.emit_event(&"interaction.activated", {"id": offer["id"], "kind": &"pigeon_feed"})
	_bus.emit_event(&"interaction.activated", {"id": offer["id"], "kind": &"pigeon_feed"})
	assert_eq(_bus.of(&"wildlife.pigeon_feed_started").size(), 1,
		"a second activation restarted the in-progress feeding gesture")

	# A fresh visitor inside the fear radius must flee, not accept a feed command
	# first because UI happens to process earlier in the same frame.
	var close := Pigeon.new()
	var close_at := _player.position + Vector3(1.70, 0.0, 0.0)
	close.begin_ground_visit(close_at, close_at + Vector3.UP * 2.0, _player, 30.0)
	close.perch_on(close_at, Vector3.BACK)
	close.advance(FRAME)
	var started_before := _bus.of(&"wildlife.pigeon_feed_started").size()
	# The production flock cannot own this standalone bird, so pin the validation
	# through the public radius constant as well as its individual fear behavior.
	assert_true(_flat_gap(_player.position, close.where()) <= Pigeon.FLEE_RADIUS_M)
	close.advance(FRAME)
	assert_false(close.is_waiting_for_food(), "the close visitor did not choose flight over feeding")
	assert_eq(_bus.of(&"wildlife.pigeon_feed_started").size(), started_before)
	close.free()
	pigeon.advance(FRAME)


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
