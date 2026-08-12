extends TestCase

## They come back.
##
## ---------------------------------------------------------------------------
## WHY THIS IS NOT A SMALL FEATURE
## ---------------------------------------------------------------------------
##   白天的时候乌鸦会被玩家惊飞，飞起盘旋一段时间后乌鸦还会回到随机的一个可以落脚的地方
##
## A flock that leaves and never returns means the player empties the valley on
## day one and the wires are bare for the remaining six. The difference between a
## world and a set of one-shot props is whether the world recovers from him.
##
## Four claims, and they are separate:
##
##   IT COMES BACK          a wire emptied by the man is occupied again later
##   IT ARRIVES, NOT        the birds fly in from outside and land; they do not
##   APPEARS                appear already sitting there
##   IT DOES NOT REWIND     the perches are drawn fresh, so the flock does not
##                          reassemble in the arrangement it left
##   IT DOES NOT LOOP       a man still standing under the wire does not get a
##                          flock that lands and immediately bursts again

const CrowScript := preload("res://src/entities/wildlife/crow.gd")
const FlockScript := preload("res://src/entities/wildlife/crow_flock.gd")

const FRAME := 1.0 / 60.0

const A_WIRE := [
	{"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 2.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 4.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 6.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 6.0, 8.0), "facing": Vector3(1.0, 0.0, 0.0)},
]


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


var _flock: CrowFlock
var _bus: BusStand
var _man: Node3D


func before_each() -> void:
	_bus = BusStand.new()
	_man = Node3D.new()
	# Far away, so nothing happens that this file did not ask for.
	_man.position = Vector3(0.0, 0.0, 300.0)
	_flock = FlockScript.new()
	_flock.random_seed = 4711
	_flock.first_arrival_seconds = 0.0
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(ClockStand.new())
	_flock.set_watched(_man)
	_flock.set_perches(A_WIRE)


func after_each() -> void:
	_flock.free()
	_man.free()


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_flock.advance(FRAME)
		left -= FRAME


# --- the arrival ------------------------------------------------------------------


## They FLY IN. The failure this catches is the one the feature shipped with:
## `_arrive()` built birds already gripping their perches, so a flock materialised
## on the wire between one frame and the next.
func test_a_flock_flies_in_rather_than_appearing_on_the_wire() -> void:
	assert_true(_flock.arrive_now() > 0, "no flock arrived at all")
	var inbound := 0
	var perched := 0
	var far := 0.0
	for crow in _flock.crows():
		if crow.is_inbound():
			inbound += 1
		if crow.is_perched():
			perched += 1
		far = maxf(far, crow.where().distance_to(crow.target_perch()))
	assert_true(inbound > 0, "the flock arrived with %d birds and none of them was flying" % _flock.crow_count())
	assert_eq(perched, 0, "%d birds were already standing on the wire on the frame they arrived" % perched)
	assert_true(
		far > 20.0,
		"the furthest bird entered only %.1f m from its perch -- it appeared in shot rather than flying into it" % far
	)


## ...and they get there.
func test_they_actually_land() -> void:
	_flock.arrive_now()
	var out := _flock.crow_count()
	_run(11.0)
	assert_eq(
		_flock.perched_count(), out,
		"%d of %d birds were still not down after eleven seconds" % [out - _flock.perched_count(), out]
	)
	# On the perch, not near it. `A_WIRE` is a stand-in with no `anchor` key, so
	# `grip()` degrades to a plain placement here -- that a landed bird holds its
	# DECLARATION is `test_crow_wind.gd`'s subject and needs a real `PerchPoints`.
	for crow in _flock.crows():
		var gap := 1e9
		for perch in A_WIRE:
			gap = minf(gap, crow.where().distance_to(perch["at"] as Vector3))
		assert_almost_eq(gap, 0.0, 0.01, "a bird finished its landing %.3f m from any perch" % gap)


## The landing is a FLARE, not a drop. The take's own body comes down 58 per cent
## of the way through it, and the code's descent is timed to touch then -- so a
## bird whose feet arrived early would stand on the wire flapping at nothing and
## one whose feet arrived late would finish its landing in the air.
func test_the_feet_touch_when_the_takes_own_body_comes_down() -> void:
	var crow: Crow = CrowScript.new()
	var perch := {"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}
	assert_true(crow.approach(perch, Vector3(0.0, 12.0, 26.0), 0.0, 0.0), "the bird refused to come back")
	var left := 12.0
	var touched_at := -1.0
	var landing_started := -1.0
	var flown := 0.0
	while left > 0.0 and not crow.is_perched():
		crow.advance(FRAME)
		left -= FRAME
		flown += FRAME
		if landing_started < 0.0 and crow.is_landing():
			landing_started = flown
		if landing_started >= 0.0 and touched_at < 0.0 and crow.has_feet_down():
			touched_at = flown
	assert_true(landing_started > 0.0, "the bird never started its landing take")
	assert_true(touched_at > 0.0, "the bird's feet never touched")
	var through := (touched_at - landing_started) / crow.land_seconds
	assert_almost_eq(
		through, Crow.SPECIES.land_flare, 0.03,
		"the feet touched %.0f%% through the landing take, not %.0f%%" % [
			through * 100.0, Crow.SPECIES.land_flare * 100.0]
	)
	assert_true(crow.is_perched(), "the bird never finished its landing")
	assert_almost_eq(
		crow.where().distance_to(perch["at"] as Vector3), 0.0, 0.01,
		"the bird landed %.3f m from the perch it was aiming at" % \
			crow.where().distance_to(perch["at"] as Vector3)
	)
	crow.free()


## The approach circles. Same axis as the departure's mill and for the same
## reason -- a bird that flew a ruler at the wire reads as a projectile.
func test_the_approach_curves_rather_than_flying_a_straight_line() -> void:
	var crow: Crow = CrowScript.new()
	var perch := {"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}
	crow.approach(perch, Vector3(0.0, 12.0, 26.0), 2.0, 1.4)
	var opening := crow.heading()
	var left := 1.0
	while left > 0.0:
		crow.advance(FRAME)
		left -= FRAME
	assert_true(crow.is_inbound(), "the bird was already down a second into a 26 m approach")
	assert_true(
		rad_to_deg(crow.heading().angle_to(opening)) > 20.0,
		"the approach bent %.1f degrees in a second of circling" % \
			rad_to_deg(crow.heading().angle_to(opening))
	)
	crow.free()


# --- coming back after HE put them up ----------------------------------------------


## The whole feature, end to end: he walks under the wire, they go, and later the
## wire is occupied again.
func test_a_wire_he_emptied_fills_up_again() -> void:
	_flock.land_now()
	assert_true(_flock.perched_count() > 0, "nothing landed to begin with")
	# Him, under it.
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.5)
	assert_eq(_flock.perched_count(), 0, "walking under the wire left crows on it")
	# ...and away again, before they think about coming back.
	_man.position = Vector3(0.0, 0.0, 300.0)
	# Long enough for the departure, the return timer and a whole approach.
	_run(80.0)
	assert_true(
		_flock.crow_count() > 0,
		"the wire was still empty eighty seconds after he walked past -- the valley does not recover"
	)
	_run(14.0)
	assert_true(
		_flock.perched_count() > 0,
		"the flock came back but never landed: %d birds still in the air" % _flock.crow_count()
	)


## The return is SHORTER than the ordinary quiet, because it is the same
## disturbance resolving rather than a fresh flock's turn.
func test_he_gets_them_back_sooner_than_the_ordinary_quiet() -> void:
	assert_true(
		_flock.return_max_seconds < _flock.quiet_min_seconds,
		"the return window (%.0f..%.0f s) is not shorter than the ordinary quiet (%.0f..%.0f s)" % [
			_flock.return_min_seconds, _flock.return_max_seconds,
			_flock.quiet_min_seconds, _flock.quiet_max_seconds]
	)


## THEY DO NOT REWIND. Fresh perches, and the count may differ -- the owner asked
## for "一只或者多只" on the way back too.
func test_the_flock_does_not_come_back_in_the_arrangement_it_left() -> void:
	var arrangements: Dictionary = {}
	var counts: Dictionary = {}
	for seed in [3, 41, 4711, 20260812, 31337, 9001, 77]:
		var flock: CrowFlock = FlockScript.new()
		flock.random_seed = seed
		flock.first_arrival_seconds = 0.0
		flock.set_event_bus(BusStand.new())
		flock.set_world_clock(ClockStand.new())
		flock.set_perches(A_WIRE)
		flock.land_now()
		var where := ""
		for crow in flock.crows():
			where += "%.1f," % crow.where().z
		arrangements[where] = true
		counts[flock.crow_count()] = true
		flock.free()
	assert_true(
		arrangements.size() >= 5,
		"seven arrivals produced only %d distinct arrangements" % arrangements.size()
	)
	assert_true(counts.size() >= 2, "every arrival was the same size")


# --- and it does not loop -----------------------------------------------------------


## HE IS STILL STANDING THERE. The failure this catches is a wire that cycles --
## a flock lands, is flushed on the next frame, comes back, is flushed again --
## which the player can watch happen and which reads as broken rather than as
## skittish.
func test_a_flock_will_not_land_on_a_man_who_has_not_moved() -> void:
	_flock.arrive_now()
	assert_true(_flock.crow_count() > 0, "nothing set off toward the wire")
	# He arrives underneath while they are still on their way in.
	_man.position = Vector3(1.0, 0.0, 4.0)
	_run(0.5)
	for crow in _flock.crows():
		assert_false(crow.is_inbound(), "a bird carried on landing on top of him")
		assert_false(crow.is_perched(), "a bird landed on a wire he is standing under")
	# ...and they leave rather than hanging about.
	_run(14.0)
	assert_eq(
		_flock.crow_count(), 0,
		"%d birds that called off their landing are still in the world" % _flock.crow_count()
	)


## No scatter event for a landing that was called off. Nothing was startled --
## and a Wave 5 listener that treats `crows_scattered` as "something is out
## there" must not be told about birds that simply changed their minds.
func test_calling_off_a_landing_is_not_a_scatter() -> void:
	_flock.arrive_now()
	_man.position = Vector3(1.0, 0.0, 4.0)
	_run(0.5)
	assert_eq(
		_bus.of(CrowFlock.EVENT_SCATTERED).size(), 0,
		"calling off a landing published a scatter"
	)
