extends TestCase

## The wind taking the flock off the wire, and refusing to let another one land
## while it is still blowing.
##
## This is the same departure the player's approach already triggers -- one
## `scatter()`, one `wildlife.crows_scattered` event -- with a different cause
## and a different bearing. A second departure would have been a second thing to
## keep in step with the first.
##
## THE THRESHOLD IS MEASURED. Swept over an hour of each shipped profile
## (`tools/_probe_wind.gd`, thrown away after), a latch at 0.75 on / 0.62 off
## fires 24 times an hour on `wind_valley` -- the `pale_day` wind, and the one a
## daylight-only bird actually lives in -- never on `wind_calm`, and holds a
## third of the time on `wind_gale`. So: never on a still day, a few times an
## afternoon on a normal one, and no crow perches at all in a whiteout.

const FlockScript := preload("res://src/entities/wildlife/crow_flock.gd")

const FRAME := 1.0 / 60.0

## Five places to sit, spaced along a line, the same stand-in
## `test_crow_flock.gd` uses. No `anchor` key, so nothing here rides anything --
## that is `test_crow_wind.gd`'s subject and this file's noise.
const A_WIRE := [
	{"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 2.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 4.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 6.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 8.0), "facing": Vector3(1.0, 0.0, 0.0)},
]

var _flock: CrowFlock
var _bus: BusStand
var _clock: ClockStand
var _watched: Node3D


## EventBus's whole contract in the two calls this uses. RefCounted, so nothing
## here has to be freed (briefing constraint 2).
class BusStand extends RefCounted:
	var published: Array = []

	func subscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func unsubscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func emit_event(event: StringName, payload: Variant = null) -> void:
		published.append({"event": event, "payload": payload})

	func of(event: StringName) -> Array:
		var found: Array = []
		for entry in published:
			if entry["event"] == event:
				found.append(entry)
		return found


class ClockStand extends RefCounted:
	var night := false

	func is_night() -> bool:
		return night


func before_each() -> void:
	_bus = BusStand.new()
	_clock = ClockStand.new()
	# Far away, so nothing in this file is flushed by the man.
	_watched = Node3D.new()
	_watched.position = Vector3(0.0, 0.0, 200.0)
	_flock = FlockScript.new()
	_flock.random_seed = 4711
	_flock.first_arrival_seconds = 0.0
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(_clock)
	_flock.set_watched(_watched)
	_flock.set_perches(A_WIRE)


func after_each() -> void:
	_flock.free()
	_watched.free()


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_flock.advance(FRAME)
		left -= FRAME


func _land_a_flock() -> int:
	var landed := _flock.arrive_now()
	# Past `stagger_seconds`, which is the guard that stops a flock being flushed
	# on the frame it lands.
	_run(0.3)
	return landed


# --- the hook the wind system already knows how to find -------------------------


## `WindSystem._collect()` finds a consumer by the hooks it publishes, not by its
## type or its path, and `drive()` calls exactly these. Naming them anything else
## means a flock that is never told the weather, with nothing to report it.
func test_the_flock_publishes_the_hooks_the_wind_system_drives() -> void:
	assert_true(_flock.has_method("set_wind_strength"), "no set_wind_strength(), so WindSystem will never drive the flock")
	assert_true(_flock.has_method("set_wind"), "no set_wind(), so the flock never learns which way the wind blows")
	_flock.set_wind_strength(0.42)
	assert_almost_eq(_flock.wind_strength(), 0.42, 0.0001, "the flock did not keep the strength it was handed")


## And NOT the sky's hooks. `WindSystem._is_fed_by_the_sky()` skips any consumer
## that has both `set_snowfall_source` and `wind_strength`, on the grounds that
## the sky is already feeding it -- so a flock that grew a `set_snowfall_source`
## would silently stop being driven and no test would notice.
func test_the_flock_is_not_mistaken_for_something_the_sky_already_feeds() -> void:
	assert_false(
		_flock.has_method("set_snowfall_source"),
		"a consumer with both set_snowfall_source() and wind_strength() is skipped by WindSystem.drive()"
	)


# --- the gust that takes them ---------------------------------------------------


func test_a_hard_gust_takes_the_whole_flock_off_the_wire() -> void:
	var landed := _land_a_flock()
	assert_true(landed > 0, "no flock landed, so there was nothing for the wind to take")
	_flock.set_wind_strength(0.80)
	_run(0.1)
	assert_eq(_flock.perched_count(), 0, "a 0.80 gust left %d birds on the wire" % _flock.perched_count())
	var scattered := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scattered.size(), 1, "expected one scatter event, got %d" % scattered.size())
	assert_eq(
		scattered[0]["payload"]["cause"], CrowFlock.CAUSE_GUST,
		"the wind's departure was published as '%s'" % scattered[0]["payload"]["cause"]
	)
	assert_eq(scattered[0]["payload"]["count"], landed, "the event undercounted the flock it sent up")


## An ordinary gust is weather, not an eviction. `wind_valley` is above 0.45 for
## a tenth of the hour; if that emptied the wires there would never be a crow on
## them.
func test_an_ordinary_gust_leaves_them_where_they_are() -> void:
	_land_a_flock()
	var landed := _flock.perched_count()
	_flock.set_wind_strength(0.60)
	_run(2.0)
	assert_eq(_flock.perched_count(), landed, "a 0.60 gust emptied the wire")
	assert_eq(_bus.of(CrowFlock.EVENT_SCATTERED).size(), 0, "a 0.60 gust published a scatter")


## The latch, for the same reason `WindSystem._report()` has one: a strength
## sitting on the threshold must not publish a storm of events.
func test_the_threshold_does_not_chatter() -> void:
	_land_a_flock()
	_flock.set_wind_strength(0.80)
	_run(0.1)
	_flock.set_wind_strength(0.70)
	_run(0.1)
	_flock.set_wind_strength(0.80)
	_run(0.1)
	assert_eq(
		_bus.of(CrowFlock.EVENT_SCATTERED).size(), 1,
		"the wind published %d scatters for one gust" % _bus.of(CrowFlock.EVENT_SCATTERED).size()
	)


## A crow does not land on a wire in a gale, and a flock that landed into one
## would be flushed on the frame after it arrived -- five birds spawned and freed
## for nothing, over and over.
func test_no_flock_lands_while_the_wind_is_still_blowing() -> void:
	_flock.set_wind_strength(0.80)
	_run(2.0)
	assert_eq(_flock.crow_count(), 0, "%d birds landed in a gale" % _flock.crow_count())
	_flock.set_wind_strength(0.10)
	_run(2.0)
	assert_true(_flock.crow_count() > 0, "the wind dropped and still nothing landed")


## Downwind, not away from a man who is two hundred metres off. A flock all
## streaming one way IS the wind cue; a flock fanning away from nothing is a
## flock reacting to a disturbance that did not happen.
func test_a_gust_sends_them_downwind() -> void:
	_land_a_flock()
	_flock.set_wind(Vector3(6.0, 0.0, 0.0))
	_flock.set_wind_strength(0.80)
	_run(0.1)
	var birds := 0
	for child in _flock.get_children():
		var crow := child as Crow
		if crow == null:
			continue
		birds += 1
		var flat := Vector3(crow.heading().x, 0.0, crow.heading().z).normalized()
		var off := rad_to_deg(flat.angle_to(Vector3(1.0, 0.0, 0.0)))
		assert_true(
			off <= _flock.gust_spread_degrees,
			"a bird blown off went %.1f degrees from downwind, outside the %.0f degree fan" % [
				off, _flock.gust_spread_degrees]
		)
	assert_true(birds > 0, "no birds left, so nothing was measured")


## The wind's departure must not cost the player's. Whoever walks under the wire
## on a still day still gets the burst.
func test_the_man_still_flushes_them_when_the_wind_is_down() -> void:
	_land_a_flock()
	_flock.set_wind_strength(0.05)
	_watched.position = Vector3(0.0, 0.0, 4.0)
	_run(0.2)
	assert_eq(_flock.perched_count(), 0, "the man walked under the wire and nothing moved")
	var scattered := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scattered.size(), 1, "expected one scatter event, got %d" % scattered.size())
	assert_eq(
		scattered[0]["payload"]["cause"], CrowFlock.CAUSE_PLAYER,
		"a flush by the man was published as '%s'" % scattered[0]["payload"]["cause"]
	)


## Every perched bird is handed the strength every frame, which is what decides
## whether it braces. Asserted through the flock rather than by calling
## `Crow.ride()` directly, because the wiring is the part that breaks.
func test_the_flock_passes_the_wind_down_to_every_bird() -> void:
	_land_a_flock()
	_flock.set_wind_strength(0.50)
	_run(0.1)
	var balancing := 0
	var birds := 0
	for child in _flock.get_children():
		var crow := child as Crow
		if crow == null:
			continue
		birds += 1
		if crow.is_balancing():
			balancing += 1
	assert_true(birds > 0, "no birds landed, so nothing was measured")
	assert_eq(balancing, birds, "%d of %d birds were told about a 0.50 gust" % [balancing, birds])
