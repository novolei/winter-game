extends TestCase

## The pigeons: the same wires as the crows, the same burst, and -- the one
## behavioural difference the brief asked for -- still there after dark.
##
## Same shape as `test_crow_flock.gd`, and deliberately so: everything runs with
## no SceneTree, because `advance()` is public and every collaborator is
## injected. What is asserted here is only what DIFFERS from the parent; the
## flock's own machinery is the crow's and is covered by the crow's file. A
## second copy of those eighteen tests would be a second copy to keep in step.

const FlockScript := preload("res://src/entities/wildlife/pigeon_flock.gd")
const CrowFlockScript := preload("res://src/entities/wildlife/crow_flock.gd")

const AN_EAVE := [
	{"at": Vector3(0.0, 3.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 1.5), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 3.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 4.5), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 6.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 7.5), "facing": Vector3(1.0, 0.0, 0.0)},
]

const FRAME := 1.0 / 60.0

var _flock: PigeonFlock
var _bus: BusStand
var _clock: ClockStand
var _watched: Node3D


## EventBus's whole contract, in the three calls this uses. RefCounted, so
## nothing here has to be freed (briefing constraint 2).
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


## WorldClock in the one respect a flock reads it.
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
	_flock.random_seed = 20260812
	_flock.first_arrival_seconds = 1.0
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(_clock)
	_flock.set_watched(_watched)
	_flock.set_perches(AN_EAVE)


func after_each() -> void:
	# Node is not reference-counted; the flock owns every bird it hatched, so
	# freeing it frees them.
	_flock.free()
	_watched.free()


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_flock.advance(FRAME)
		left -= FRAME


func _birds() -> Array:
	var found: Array = []
	for child in _flock.get_children():
		if child is Bird:
			found.append(child)
	return found


# --- what it builds -----------------------------------------------------------


## A `Pigeon` is a `Bird` carrying `data/wildlife/pigeon.tres`, and so is a
## `Crow` -- which is why this has to be asserted rather than assumed. A
## `_new_bird()` that had lost its override would hand back plain birds wearing
## the pigeon species, every OTHER test in this file would still pass, and
## nothing would report it. It is the same assertion that guarded the five
## overrides this class used to need.
func test_the_flock_hatches_pigeons_and_not_crows() -> void:
	_flock.arrive_now()
	var birds := _birds()
	assert_true(birds.size() > 0, "no bird arrived at all")
	var wrong := 0
	for bird in birds:
		if not (bird is Pigeon):
			wrong += 1
	assert_eq(wrong, 0, "%d of %d birds are plain crows" % [wrong, birds.size()])


func test_a_flock_of_pigeons_is_bigger_than_a_flock_of_crows() -> void:
	var crows: CrowFlock = CrowFlockScript.new()
	assert_true(
		_flock.most > crows.most or _flock.fewest > crows.fewest,
		"pigeons flock in %d..%d against the crows' %d..%d, so there is nothing to tell them apart at a glance" % [
			_flock.fewest, _flock.most, crows.fewest, crows.most]
	)
	assert_true(
		_flock.flush_radius_m < crows.flush_radius_m,
		"a pigeon is used to people and should let him closer than a crow does"
	)
	crows.free()


# --- day AND night, which is the whole difference -----------------------------


## The crows' rule is "daylight only". This one's is not, and the difference has
## to survive both halves of the day/night wiring -- the subscription AND the
## question asked on attach.
func test_a_flock_arrives_after_dark() -> void:
	_clock.night = true
	_flock.attach()
	_run(6.0)
	assert_true(_birds().size() > 0, "the wire is empty at night; a rock dove roosts on the ledge it feeds from")


## The half a subscription cannot do. A flock born into night that only listened
## would sit at its member's default until the first sunrise -- which is up to a
## whole phase away, and reads as a tuning choice rather than as a defect.
func test_it_asks_the_clock_what_time_it_is_rather_than_waiting_to_be_told() -> void:
	_clock.night = true
	_flock.attach()
	assert_true(_flock.is_dark(), "the flock was born at night and does not know it")
	_clock.night = false
	_flock.attach()
	assert_false(_flock.is_dark(), "the flock was born in daylight and thinks it is night")


## And the parent's own gate stays open, which is the mechanism.
##
## `CrowFlock._night` means one thing in the parent's logic: the wires must be
## empty. For this bird that is never true, so the flag is held at false and the
## real phase is kept as `is_dark()`. Asserting both is what stops a later edit
## from "tidying" the two back into one.
func test_the_parents_empty_the_wires_flag_is_never_set() -> void:
	_clock.night = true
	_flock.attach()
	assert_true(_flock.is_dark(), "the clock says night and the flock disagrees")
	assert_false(_flock.is_night(), "the parent's flag is set, which blocks every arrival until sunrise")


func test_nightfall_does_not_flush_the_wire() -> void:
	_flock.attach()
	_flock.land_now()
	var before := _flock.perched_count()
	assert_true(before > 0, "nothing landed, so there is nothing to flush")
	_bus.emit_event(&"clock.night_started", null)
	_run(0.5)
	assert_eq(
		_flock.perched_count(), before,
		"nightfall put %d of %d pigeons up; only the crows go home at dusk" % [
			before - _flock.perched_count(), before]
	)
	assert_eq(_bus.of(CrowFlock.EVENT_SCATTERED).size(), 0, "nightfall published a scatter")


## The same event, the same cause, unchanged from the parent -- because a Wave 5
## listener wanting "something is out there" wants one subscription and does not
## care which bird raised it.
func test_the_man_still_puts_them_up_and_it_is_still_published() -> void:
	_flock.attach()
	_flock.land_now()
	var landed := _flock.perched_count()
	assert_true(landed > 0, "nothing landed")
	_watched.position = Vector3(0.0, 0.0, 3.0)
	_run(0.5)
	var scattered := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scattered.size(), 1, "the burst was published %d times" % scattered.size())
	if scattered.is_empty():
		return
	var payload: Dictionary = scattered[0]["payload"]
	assert_eq(payload["cause"], CrowFlock.CAUSE_PLAYER, "the cause was %s" % payload["cause"])
	assert_eq(payload["count"], landed, "%d birds went up out of %d" % [payload["count"], landed])


## And it happens at night as well, which the crows can never do -- a crow flock
## is empty after dark, so this event only ever had a daylight source.
func test_they_can_be_put_up_after_dark() -> void:
	_clock.night = true
	_flock.attach()
	_flock.land_now()
	assert_true(_flock.perched_count() > 0, "nothing landed after dark")
	_watched.position = Vector3(0.0, 0.0, 3.0)
	_run(0.5)
	assert_eq(_bus.of(CrowFlock.EVENT_SCATTERED).size(), 1, "a night startle published nothing")


# --- and it will not land on somebody -----------------------------------------


func test_a_perch_somebody_is_standing_on_is_not_offered() -> void:
	var free := FlockScript.free_of(AN_EAVE, [Vector3(0.0, 3.0, 1.5)])
	assert_eq(free.size(), AN_EAVE.size() - 1, "%d perches came back out of %d" % [free.size(), AN_EAVE.size()])
	for perch in free:
		assert_true(
			(perch["at"] as Vector3).distance_to(Vector3(0.0, 3.0, 1.5)) > PigeonFlock.OCCUPIED_WITHIN_M,
			"the occupied perch is still on offer"
		)


## The neighbours must survive. A radius wide enough to clear a whole wire would
## empty the valley the moment one bird landed on it.
func test_a_bird_on_one_perch_does_not_close_the_ones_beside_it() -> void:
	var free := FlockScript.free_of(AN_EAVE, [Vector3(0.0, 3.0, 0.0)])
	assert_eq(free.size(), AN_EAVE.size() - 1, "one bird closed %d perches" % [AN_EAVE.size() - free.size()])


func test_an_empty_sky_leaves_every_perch_on_offer() -> void:
	assert_eq(FlockScript.free_of(AN_EAVE, []).size(), AN_EAVE.size(), "perches went missing with nothing standing on them")


## The filter is on the flock's own door, so a flock that has been handed
## explicit perches still gets them. Otherwise a capture that placed a bird
## exactly where it wanted one would find the perch refused.
func test_the_filter_leaves_explicit_perches_alone_outside_a_tree() -> void:
	assert_eq(
		_flock.available_perches().size(), AN_EAVE.size(),
		"the perches handed to the flock came back short"
	)
