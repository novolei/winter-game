extends TestCase

## The crows: daylight only, on the props' own perches, and away in a burst when
## something comes near.
##
## Everything here runs with no SceneTree. `CrowFlock.advance()` and
## `Crow.advance()` are public and carry all the logic for exactly this reason,
## and the flock's collaborators -- the bus, the clock, the thing it is
## frightened of -- are all injected, so a whole afternoon is a few calls.

const FlockScript := preload("res://src/entities/wildlife/crow_flock.gd")

## Somewhere for five birds to sit, spaced along a line. Not a wire in the
## scene -- the point of `set_perches` is that the flock does not care where a
## perch came from.
const A_WIRE := [
	{"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 2.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 4.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 6.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 8.0), "facing": Vector3(1.0, 0.0, 0.0)},
]

const FRAME := 1.0 / 60.0

var _flock: CrowFlock
var _bus: BusStand
var _clock: ClockStand
var _watched: Node3D


## EventBus's whole contract, in the two calls this uses. RefCounted rather than
## the real autoload's Node, so nothing here has to be freed (briefing section
## 2.2) -- and so a test asserting what was published does not also have to
## unpick whatever else in the process is subscribed.
class BusStand extends RefCounted:
	var published: Array = []
	var subscriptions: Dictionary = {}

	func subscribe(event: StringName, callback: Callable) -> void:
		if not subscriptions.has(event):
			subscriptions[event] = []
		var list: Array = subscriptions[event]
		if not list.has(callback):
			list.append(callback)

	func unsubscribe(event: StringName, callback: Callable) -> void:
		if subscriptions.has(event):
			(subscriptions[event] as Array).erase(callback)

	func emit_event(event: StringName, payload: Variant = null) -> void:
		published.append({"event": event, "payload": payload})
		for callback in (subscriptions.get(event, []) as Array).duplicate():
			(callback as Callable).call(payload)

	func of(event: StringName) -> Array:
		var found: Array = []
		for entry in published:
			if entry["event"] == event:
				found.append(entry)
		return found


## WorldClock in the one respect the flock reads it.
class ClockStand extends RefCounted:
	var night := false

	func is_night() -> bool:
		return night


func before_each() -> void:
	_bus = BusStand.new()
	_clock = ClockStand.new()
	_watched = Node3D.new()
	_watched.position = Vector3(0.0, 0.0, 200.0)
	_flock = FlockScript.new()
	_flock.random_seed = 4711
	_flock.first_arrival_seconds = 1.0
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(_clock)
	_flock.set_watched(_watched)
	_flock.set_perches(A_WIRE)


func after_each() -> void:
	# Node is not reference-counted; the flock owns every crow it hatched, so
	# freeing it frees them (briefing constraint 2).
	_flock.free()
	_watched.free()


## Runs the flock for `seconds`, a frame at a time, the way the game does.
func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_flock.advance(FRAME)
		left -= FRAME


func _birds() -> Array:
	var found: Array = []
	for child in _flock.get_children():
		if child is Crow:
			found.append(child)
	return found


## Birds that have been told to go and have not started their launch yet.
func _waiting() -> int:
	var waiting := 0
	for crow in _birds():
		if (crow as Crow).state() == Crow.State.WAITING:
			waiting += 1
	return waiting


# --- the phase it was born into ----------------------------------------------


## THE ONE THIS FILE EXISTS FOR. A system that only subscribes to
## `clock.night_started` learns the phase at the next transition and not before,
## so a flock built during the night is out all night and nothing says a word.
func test_it_asks_the_clock_what_time_it_is_rather_than_assuming_daylight() -> void:
	_clock.night = true
	_flock.attach()
	assert_true(
		_flock.is_night(),
		"attach() subscribed but never asked -- a flock built at night believes it is day until dawn"
	)


func test_a_flock_attached_in_daylight_knows_it_is_day() -> void:
	_clock.night = false
	_flock.attach()
	assert_false(_flock.is_night(), "attach() in daylight must not leave the flock believing it is night")


## The other half. Asking is what makes the opening state right; the
## subscription is what keeps it right.
func test_the_clock_events_still_move_it() -> void:
	_flock.attach()
	_bus.emit_event(CrowFlock.EVENT_NIGHT_STARTED, 1)
	assert_true(_flock.is_night(), "clock.night_started must reach the flock")
	_bus.emit_event(CrowFlock.EVENT_DAY_STARTED, 2)
	assert_false(_flock.is_night(), "clock.day_started must reach the flock")


func test_no_crow_arrives_at_night() -> void:
	_clock.night = true
	_flock.attach()
	_run(30.0)
	assert_eq(_flock.crow_count(), 0, "crows arrived in the dark; the owner asked for daylight only")


## The timer, not the landing: four seconds is enough for a flock to have SET OFF.
## Since the return work the birds fly in from thirty metres out, so a test that
## waited four seconds for them to be standing on the wire would be waiting for
## the approach rather than for the decision. `land_now()` is what the tests below
## use when they want birds already down.
func test_a_flock_arrives_in_daylight() -> void:
	_flock.attach()
	_run(4.0)
	assert_true(_flock.crow_count() >= 1, "no crow set off for the wire in four daylight seconds")
	assert_true(
		_flock.crow_count() <= _flock.most,
		"%d crows arrived, more than the %d bound" % [_flock.crow_count(), _flock.most]
	)


func test_two_crows_never_land_in_the_same_place() -> void:
	_flock.attach()
	_flock.land_now()
	var seen: Dictionary = {}
	for crow in _birds():
		var key := (crow as Crow).where().snapped(Vector3(0.01, 0.01, 0.01))
		assert_false(seen.has(key), "two crows landed on the same perch at %s" % key)
		seen[key] = true
	assert_true(seen.size() >= 1, "nothing landed, so this test checked nothing")


## Nightfall clears the wires, and it does it by sending them up -- a bird that
## vanished on a phase boundary would be the one thing on screen that reads as a
## bug rather than as weather.
func test_nightfall_sends_them_up_rather_than_deleting_them() -> void:
	_flock.attach()
	_flock.land_now()
	var landed := _flock.crow_count()
	assert_true(landed >= 1, "nothing landed, so this test checked nothing")
	_bus.emit_event(CrowFlock.EVENT_NIGHT_STARTED, 1)
	assert_eq(_flock.crow_count(), landed, "nightfall deleted the birds instead of flushing them")
	assert_eq(_flock.perched_count(), 0, "nightfall left crows sitting on the wire")
	var scatters := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scatters.size(), 1, "nightfall published %d scatter events" % scatters.size())
	assert_eq(
		scatters[0]["payload"]["cause"], CrowFlock.CAUSE_NIGHTFALL,
		"the nightfall scatter must say so, or a listener cannot tell it from a threat"
	)


# --- the player ---------------------------------------------------------------


func test_a_body_outside_the_flush_radius_leaves_them_alone() -> void:
	_flock.attach()
	_flock.land_now()
	assert_true(_flock.perched_count() >= 1, "nothing landed, so this test checked nothing")
	_watched.position = Vector3(0.0, 0.0, 4.0) + Vector3(_flock.flush_radius_m + 6.0, 0.0, 0.0)
	_run(1.0)
	assert_true(_flock.perched_count() >= 1, "the crows left with nobody within the flush radius")


func test_a_body_inside_the_flush_radius_puts_them_up() -> void:
	_flock.attach()
	_flock.land_now()
	assert_true(_flock.perched_count() >= 1, "nothing landed, so this test checked nothing")
	_watched.position = Vector3(0.0, 0.0, 4.0)
	_run(2.0)
	assert_eq(_flock.perched_count(), 0, "the player walked under the wire and nothing moved")


func test_the_scatter_is_published_once_and_says_how_many() -> void:
	_flock.attach()
	_flock.land_now()
	var landed := _flock.crow_count()
	_watched.position = Vector3(0.0, 0.0, 4.0)
	_run(2.0)
	var scatters := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scatters.size(), 1, "expected exactly one wildlife.crows_scattered, got %d" % scatters.size())
	if scatters.is_empty():
		return
	var payload: Dictionary = scatters[0]["payload"]
	assert_eq(payload["count"], landed, "the event under-counted the birds that left")
	assert_eq(payload["cause"], CrowFlock.CAUSE_PLAYER, "a player flush must be attributed to the player")
	assert_true(payload.has("position"), "the event carries no position, so a listener cannot tell where")


## A player loitering under the wire must not spawn a bird a second, each one
## flushed on the frame after it lands.
func test_a_flock_does_not_land_on_top_of_whoever_is_standing_there() -> void:
	_flock.attach()
	_watched.position = Vector3(0.0, 0.0, 4.0)
	_run(30.0)
	assert_eq(_flock.crow_count(), 0, "a flock landed on a wire the player was standing under")


# --- the burst ----------------------------------------------------------------


func test_they_leave_on_different_bearings() -> void:
	_flock.fewest = 5
	_flock.most = 5
	_flock.attach()
	_flock.land_now()
	var crows := _birds()
	assert_eq(crows.size(), 5, "expected five birds for this test, got %d" % crows.size())
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	var headings: Array = []
	for crow in crows:
		headings.append((crow as Crow).heading())
	for index in range(headings.size()):
		var one: Vector3 = headings[index]
		assert_true(one.y > 0.0, "a crow left without climbing: %s" % one)
		for other_index in range(index + 1, headings.size()):
			var other: Vector3 = headings[other_index]
			var apart := rad_to_deg(one.angle_to(other))
			assert_true(
				apart >= 4.0,
				"two of five left within %.1f degrees of each other -- a flock that leaves on one bearing reads as one object" % apart
			)


func test_the_burst_is_staggered_rather_than_simultaneous() -> void:
	_flock.fewest = 5
	_flock.most = 5
	_flock.attach()
	_flock.land_now()
	assert_eq(_flock.perched_count(), 5, "expected five perched birds, got %d" % _flock.perched_count())
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	# Counted by STATE rather than by position: the stagger is the delay before
	# each bird starts its launch take, and the launch itself keeps it on the wire
	# for another second, so "has it moved yet" cannot see the ripple at all.
	assert_eq(_waiting(), 5, "the whole flock should be waiting its turn on the frame the burst starts")
	# A step and a half in, the first two have gone and three are still waiting.
	_run(_flock.stagger_seconds * 1.5)
	var waiting := _waiting()
	assert_true(
		waiting >= 2 and waiting <= 4,
		"%d of five were still waiting a step and a half into the burst -- it fired as one event" % waiting
	)
	_run(_flock.stagger_seconds * 5.0)
	assert_eq(_waiting(), 0, "the tail of the burst never left")


func test_a_bird_that_has_gone_is_freed() -> void:
	_flock.attach()
	_flock.land_now()
	assert_true(_flock.crow_count() >= 1, "nothing landed, so this test checked nothing")
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	_run(20.0)
	assert_eq(_flock.crow_count(), 0, "a departed crow is still being ticked")
	assert_eq(_birds().size(), 0, "a departed crow is still in the tree")


## A second scatter while the flock is already in the air must not restart
## anything: a bird that took the call twice would drop back to the perch it is
## fifty metres from.
func test_scattering_an_empty_wire_does_nothing() -> void:
	_flock.attach()
	_flock.land_now()
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	assert_eq(_flock.scatter(CrowFlock.CAUSE_PLAYER), 0, "a second scatter re-flushed birds already in the air")
	assert_eq(
		_bus.of(CrowFlock.EVENT_SCATTERED).size(), 1,
		"a scatter with nothing perched still published an event"
	)


# --- one bird's own timeline ---------------------------------------------------


## THE TAKE-OFF, WHICH USED TO BE A TRANSLATION.
##
## This asserted `travelled() == 0` through the whole launch, on the grounds that
## the take's baked root motion and this code must not both be driving the bird.
## That still holds -- and it is now the HORIZONTAL half of it that says so,
## because the launch deliberately drives the vertical: the bird crouches, beats,
## and comes up off the wire before it has any forward speed at all.
##
## The climb is the take's own 0.30 m, restored in code because `CrowAnimations`
## flattens the root track. A launch that moved the bird sideways would mean the
## forward push had leaked back into the lift, which is the exact thing the
## owner's note is about.
func test_a_crow_rises_off_the_wire_before_it_has_any_forward_speed() -> void:
	var crow := Crow.new()
	var perch := Vector3(0.0, 6.0, 0.0)
	crow.perch_on(perch, Vector3(0.0, 0.0, -1.0))
	assert_true(crow.is_perched(), "a crow that has just been placed is perched")
	assert_true(crow.has_feet_down(), "a perched crow is not standing on anything")
	crow.scatter(Vector3(0.0, 0.4, -1.0).normalized(), 0.0)
	# Through the wait and the whole of the launch take.
	var left := crow.launch_seconds
	var lifted_yet := false
	while left > 0.0:
		crow.advance(FRAME)
		left -= FRAME
		if not crow.has_feet_down() and not lifted_yet:
			lifted_yet = true
			assert_true(
				crow.where().y - perch.y < 0.02,
				"the bird was already %.3f m up on the frame its feet left the wire" % (crow.where().y - perch.y)
			)
	assert_true(lifted_yet, "the feet never left the wire during the launch")
	var risen := crow.where() - perch
	assert_almost_eq(
		Vector2(risen.x, risen.z).length(), 0.0, 0.001,
		"the crow travelled %.3f m sideways during the launch -- the lift has forward speed in it" % \
			Vector2(risen.x, risen.z).length()
	)
	assert_almost_eq(
		risen.y, crow.launch_climb_m, 0.02,
		"the crow rose %.3f m off the wire, not the take's own %.3f m" % [risen.y, crow.launch_climb_m]
	)
	var flying := 1.0
	while flying > 0.0:
		crow.advance(FRAME)
		flying -= FRAME
	assert_true(crow.travelled() > 1.0, "a second after the launch the crow has gone nowhere")
	assert_false(crow.is_perched(), "the crow is still reporting itself perched in mid air")
	assert_false(crow.has_feet_down(), "the crow in mid air still says its feet are down")
	crow.free()


func test_a_crow_stops_existing_once_it_is_far_enough_away() -> void:
	var crow := Crow.new()
	crow.perch_on(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	crow.scatter(Vector3(0.0, 0.3, -1.0).normalized(), 0.0)
	var left := 30.0
	while left > 0.0 and not crow.is_gone():
		crow.advance(FRAME)
		left -= FRAME
	assert_true(crow.is_gone(), "a crow flying at cruise for thirty seconds is still in the world")
	assert_true(
		crow.travelled() >= crow.vanish_distance_m,
		"the crow gave up at %.1f m, short of the %.1f m it takes to leave an orthographic frame" % [
			crow.travelled(), crow.vanish_distance_m]
	)
	crow.free()


func test_a_perched_crow_ignores_a_zero_or_backwards_frame() -> void:
	var crow := Crow.new()
	crow.perch_on(Vector3(1.0, 6.0, 2.0), Vector3(0.0, 0.0, -1.0))
	crow.scatter(Vector3(0.0, 0.3, -1.0).normalized(), 0.5)
	crow.advance(0.0)
	crow.advance(-1.0)
	crow.advance(NAN)
	assert_almost_eq(crow.travelled(), 0.0, 0.0001, "a zero, negative or NAN frame moved the bird")
	crow.free()
