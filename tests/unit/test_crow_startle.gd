extends TestCase

## The two seconds after the wire empties: the take-off, and the mill.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE IS ABOUT
## ---------------------------------------------------------------------------
## Wave 2 built the departure as a translation. A bird was told a heading, held
## its perch for the length of the launch take, and then simply moved -- so the
## most legible moment the asset has (wings out, body coming up off a wire, a
## silhouette about three times the perched one) was a bird standing still while
## an animation played over it, and the moment after it was a straight line.
##
## Two things are asserted here and they are separate claims:
##
##   THE LIFT   the bird rises off the wire, on the take's own 0.30 m, with NO
##              forward component at all. "The body rising before it has any
##              forward speed" is the owner's phrase and it is a measurement:
##              horizontal travel through the whole launch must be zero.
##
##   THE MILL   it does not leave on a heading. It comes off the wire pointed
##              roughly the way it was standing, turns for a drawn number of
##              seconds, and only then commits. The hesitation is what makes a
##              flock read as alive rather than as five velocities, and it is the
##              axis the Art Bible's ruling names first among the things that
##              should differ every time.
##
## ---------------------------------------------------------------------------
## WHY THE VARIATION IS TESTED AS A SPREAD AND NOT AS A SEQUENCE
## ---------------------------------------------------------------------------
## "Different every time" cannot be asserted by comparing one run to a recorded
## one -- that is a snapshot test, and it passes for a system that varies by a
## millimetre. What it can be asserted as is: run the same burst under different
## seeds and measure how far apart the answers land. A canned sequence played at
## random would fail that; procedural variation along the ruling's own axes
## passes it.

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


func _a_crow() -> Crow:
	var crow: Crow = CrowScript.new()
	crow.perch_on(Vector3(0.0, 6.0, 0.0), Vector3(0.0, 0.0, -1.0))
	return crow


func _step(crow: Crow, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		crow.advance(FRAME)
		left -= FRAME


# --- the lift -------------------------------------------------------------------


## The crouch. The take opens with the bird gathering, and a bird that started
## rising on frame one would be levitating out of a pose it has not finished.
func test_the_feet_stay_on_the_wire_through_the_crouch() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(0.0, 0.4, -1.0).normalized(), 0.0)
	# Into the launch, but not past the crouch.
	_step(crow, crow.launch_seconds * crow.crouch_fraction * 0.5 + FRAME)
	assert_eq(crow.state(), Crow.State.LAUNCHING, "half-way through the crouch and the bird is not launching")
	assert_true(crow.has_feet_down(), "the bird left the wire during the crouch")
	assert_almost_eq(crow.where().y, 6.0, 0.0001, "the bird rose %.4f m during the crouch" % (crow.where().y - 6.0))
	crow.free()


## ...and are off it well before the launch take ends, so the rise is a rise and
## not a hop on the last frame.
func test_the_bird_is_airborne_for_most_of_the_launch() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(0.0, 0.4, -1.0).normalized(), 0.0)
	_step(crow, crow.launch_seconds * 0.75)
	assert_eq(crow.state(), Crow.State.LAUNCHING, "three quarters through and the launch is already over")
	assert_false(crow.has_feet_down(), "three quarters through the launch and the feet are still down")
	assert_true(
		crow.where().y > 6.05,
		"three quarters through the launch the bird has risen only %.4f m" % (crow.where().y - 6.0)
	)
	crow.free()


## The whole point, stated as a number: no forward speed until the bird is up.
func test_nothing_about_the_launch_is_horizontal() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(1.0, 0.4, 0.0).normalized(), 0.0)
	var worst := 0.0
	var left := crow.launch_seconds
	while left > 0.0:
		crow.advance(FRAME)
		left -= FRAME
		var off := crow.where() - Vector3(0.0, 6.0, 0.0)
		worst = maxf(worst, Vector2(off.x, off.z).length())
	assert_almost_eq(worst, 0.0, 0.001, "the bird drifted %.4f m sideways before it was off the wire" % worst)
	crow.free()


## And the climb is the take's, not a number somebody liked.
func test_the_rise_is_the_takes_own_climb() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(0.0, 0.4, -1.0).normalized(), 0.0)
	_step(crow, crow.launch_seconds)
	assert_almost_eq(
		crow.where().y - 6.0, crow.launch_climb_m, 0.02,
		"the bird rose %.4f m against the take's %.4f m" % [crow.where().y - 6.0, crow.launch_climb_m]
	)
	crow.free()


## The seam that used to be there. The launch handed the flight an overwritten
## velocity, so the climb the lift had built was thrown away on the frame it
## finished and replaced with a horizontal step.
func test_the_climb_carries_through_into_the_flight() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(0.0, 0.2, -1.0).normalized(), 0.0)
	_step(crow, crow.launch_seconds)
	var at_the_top := crow.where().y
	crow.advance(FRAME)
	assert_true(
		crow.where().y > at_the_top,
		"the bird stopped climbing on the frame the launch ended -- the lift's velocity was discarded"
	)
	crow.free()


# --- the mill --------------------------------------------------------------------


## It leaves undecided. Straight after the launch the bird is pointed roughly the
## way it was standing, NOT at the bearing it will end up on.
func test_a_wheeling_bird_is_not_yet_pointed_where_it_is_going() -> void:
	var crow := _a_crow()
	# Standing along -Z; sent away along +X. Ninety degrees apart, so "has it
	# committed yet" is a question with a big answer either way.
	var departure := Vector3(1.0, 0.3, 0.0).normalized()
	crow.scatter(departure, 0.0, 2.0, 1.2)
	_step(crow, crow.launch_seconds + FRAME * 2.0)
	assert_true(crow.is_wheeling(), "the bird is not milling straight after its launch")
	assert_almost_eq(
		crow.departure().angle_to(departure), 0.0, 0.001,
		"the bird forgot where it was sent"
	)
	assert_true(
		rad_to_deg(crow.heading().angle_to(departure)) > 30.0,
		"the bird came off the wire already pointed at its departure -- there is no hesitation"
	)
	crow.free()


## ...and it commits. The mill is bounded; a bird that circled forever would
## never leave the frame.
func test_it_commits_to_its_bearing_once_the_mill_has_run() -> void:
	var crow := _a_crow()
	var departure := Vector3(1.0, 0.3, 0.0).normalized()
	crow.scatter(departure, 0.0, 2.0, 0.9)
	_step(crow, crow.launch_seconds + 0.9 + FRAME * 2.0)
	assert_false(crow.is_wheeling(), "the bird is still milling after its wheel ran out")
	assert_almost_eq(
		crow.heading().angle_to(departure), 0.0, 0.001,
		"the bird committed to a bearing %.1f degrees off the one it was given" % \
			rad_to_deg(crow.heading().angle_to(departure))
	)
	crow.free()


## The mill is an ARC, not a corner. A bird whose heading turned but whose path
## did not would be a sprite being re-aimed.
func test_the_path_through_the_mill_actually_bends() -> void:
	var crow := _a_crow()
	crow.scatter(Vector3(0.0, 0.3, -1.0).normalized(), 0.0, 2.2, 1.4)
	_step(crow, crow.launch_seconds + 0.1)
	var a := crow.where()
	_step(crow, 0.35)
	var b := crow.where()
	_step(crow, 0.35)
	var c := crow.where()
	var first := (b - a)
	var second := (c - b)
	first.y = 0.0
	second.y = 0.0
	assert_true(first.length() > 0.2 and second.length() > 0.2, "the bird barely moved through the mill")
	var bend := rad_to_deg(first.angle_to(second))
	assert_true(
		bend > 15.0,
		"the path bent %.1f degrees across 0.7 s of milling -- that is a straight line" % bend
	)
	crow.free()


## Turning the other way is the other half of the axis, and it has to be a real
## mirror rather than the same arc with a sign somewhere.
func test_the_wheel_turns_whichever_way_it_was_told() -> void:
	var turned: Array = []
	for sign in [1.0, -1.0]:
		var crow := _a_crow()
		crow.scatter(Vector3(0.0, 0.3, -1.0).normalized(), 0.0, sign * 2.0, 1.2)
		_step(crow, crow.launch_seconds + 0.6)
		# Signed angle about the vertical, from where it started to where it is now.
		var flat := Vector3(crow.heading().x, 0.0, crow.heading().z).normalized()
		turned.append(atan2(flat.x, -flat.z))
		crow.free()
	assert_true(
		turned[0] * turned[1] < 0.0,
		"both signs wheeled the same way: %.3f and %.3f radians" % [turned[0], turned[1]]
	)


## No wheel asked for, no wheel taken. Every caller that predates the mill --
## and every test in the two files next to this one -- gets the straight
## departure it was written against.
func test_a_bird_told_nothing_about_a_wheel_flies_straight_out() -> void:
	var crow := _a_crow()
	var departure := Vector3(1.0, 0.3, 0.0).normalized()
	crow.scatter(departure, 0.0)
	_step(crow, crow.launch_seconds + FRAME * 2.0)
	assert_false(crow.is_wheeling(), "a bird that was given no wheel is milling anyway")
	assert_almost_eq(
		crow.heading().angle_to(departure), 0.0, 0.001,
		"a bird that was given no wheel is not pointed at its bearing"
	)
	crow.free()


# --- what the flock hands out ----------------------------------------------------


func _a_flock(seed: int, fewest := 3) -> CrowFlock:
	var flock: CrowFlock = FlockScript.new()
	flock.random_seed = seed
	flock.first_arrival_seconds = 0.0
	flock.fewest = fewest
	# `fewest` defaults to three here so a burst is big enough for "they all wheel
	# the same way" and "no two hesitate for the same time" to be questions with
	# answers at all. The COUNT is itself one of the varying axes, so the test
	# that measures the variation passes 1 and gets the shipped range back.
	flock.set_event_bus(BusStand.new())
	flock.set_world_clock(ClockStand.new())
	flock.set_perches(A_WIRE)
	flock.land_now()
	var left := 0.3
	while left > 0.0:
		flock.advance(FRAME)
		left -= FRAME
	return flock


## Birds mill together. A flock with three going one way and two the other is a
## collision rather than a wheel.
func test_a_whole_burst_wheels_the_same_way_round() -> void:
	var flock := _a_flock(20260812)
	flock.scatter(CrowFlock.CAUSE_PLAYER)
	var signs: Array = []
	for crow in flock.crows():
		assert_true(absf(crow.wheel_rate()) > 0.0001, "a bird in a burst was given no wheel at all")
		signs.append(signf(crow.wheel_rate()))
	assert_true(signs.size() >= 2, "the burst was too small to say anything about")
	for sign in signs:
		assert_eq(sign, signs[0], "the burst wheels both ways at once: %s" % str(signs))
	flock.free()


## ...but not identically. A rigid formation is the other failure.
func test_no_two_birds_in_a_burst_hesitate_for_the_same_time() -> void:
	var flock := _a_flock(773)
	flock.scatter(CrowFlock.CAUSE_PLAYER)
	var seen: Array = []
	for crow in flock.crows():
		for already in seen:
			assert_true(
				absf(crow.wheel_seconds() - already) > 0.001,
				"two birds hesitate for exactly %.4f s" % already
			)
		seen.append(crow.wheel_seconds())
	assert_true(seen.size() >= 2, "the burst was too small to say anything about")
	flock.free()


## Every drawn value inside the bounds a Director can read off the exports. The
## mill has to fit inside the ruling's two-or-three-second shot, and a rate
## outside the band is a barrel roll or a bird that never closes its circle.
func test_the_drawn_wheel_stays_inside_the_bounds_the_exports_declare() -> void:
	for seed in [1, 99, 4711, 20260812, 31337]:
		var flock := _a_flock(seed)
		flock.scatter(CrowFlock.CAUSE_PLAYER)
		for crow in flock.crows():
			var rate := absf(crow.wheel_rate())
			var floor_rate: float = flock.wheel_rate_min * (1.0 - flock.wheel_jitter)
			var ceiling_rate: float = flock.wheel_rate_max * (1.0 + flock.wheel_jitter)
			assert_true(
				rate >= floor_rate - 0.001 and rate <= ceiling_rate + 0.001,
				"seed %d drew a wheel rate of %.3f rad/s, outside %.3f..%.3f" % [
					seed, rate, floor_rate, ceiling_rate]
			)
			assert_true(
				crow.wheel_seconds() >= flock.wheel_seconds_min - 0.001 \
					and crow.wheel_seconds() <= flock.wheel_seconds_max + 0.001,
				"seed %d drew a hesitation of %.3f s, outside %.3f..%.3f" % [
					seed, crow.wheel_seconds(), flock.wheel_seconds_min, flock.wheel_seconds_max]
			)
		flock.free()


## THE "每一次都不一样" CLAIM, AS A MEASUREMENT.
##
## Five seeds, one burst each, and the four things the ruling says should differ.
## Asserted as a SPREAD rather than against a recorded run: a snapshot test is
## satisfied by a system that varies by a millimetre, and what is being claimed
## here is that the axes are wide enough to see.
func test_two_startles_from_the_same_wire_do_not_come_out_the_same() -> void:
	var counts: Dictionary = {}
	var directions: Dictionary = {}
	var slowest := 1e9
	var quickest := -1e9
	var narrowest := 1e9
	var widest := -1e9
	for seed in [7, 101, 4711, 20260812, 31337, 88, 9001]:
		var flock := _a_flock(seed, 1)
		var went := flock.scatter(CrowFlock.CAUSE_PLAYER)
		counts[went] = true
		var birds := flock.crows()
		if not birds.is_empty():
			directions[signf(birds[0].wheel_rate())] = true
		var fan_min := 1e9
		var fan_max := -1e9
		for crow in birds:
			slowest = minf(slowest, crow.wheel_seconds())
			quickest = maxf(quickest, crow.wheel_seconds())
			var flat := Vector3(crow.departure().x, 0.0, crow.departure().z).normalized()
			var bearing := atan2(flat.x, -flat.z)
			fan_min = minf(fan_min, bearing)
			fan_max = maxf(fan_max, bearing)
		if birds.size() >= 2:
			narrowest = minf(narrowest, fan_max - fan_min)
			widest = maxf(widest, fan_max - fan_min)
		flock.free()
	assert_true(counts.size() >= 2, "every seed put up exactly the same number of birds")
	assert_true(directions.size() == 2, "every burst wheeled the same way round")
	assert_true(
		quickest - slowest > 0.4,
		"the hesitation only varied by %.3f s across seven bursts" % (quickest - slowest)
	)
	assert_true(
		rad_to_deg(widest - narrowest) > 5.0,
		"the fan only varied by %.1f degrees across seven bursts" % rad_to_deg(widest - narrowest)
	)


## HE HAS TO BE ABLE TO SET THEM OFF BY WALKING UNDER THEM.
##
## Measured on the shipped scene: the perches in `main.tscn` are 5.09 m to 8.66 m
## up. A 3D flush test therefore spends most of an eight-metre radius on the
## height of the pole and leaves between 6.8 m and 1.95 m of horizontal reach --
## so a flock on the high perches could not be flushed at all, and the same
## feature worked or did not depending on where the birds happened to land.
##
## This uses the real numbers: a wire eight metres up and a man standing four
## metres to one side, which is well inside the tight framing stop and is what
## "the player passes underneath" means.
func test_a_man_walking_under_a_high_wire_still_puts_them_up() -> void:
	var high_wire: Array = []
	for index in range(3):
		high_wire.append({
			"at": Vector3(0.0, 8.2, float(index) * 2.0),
			"facing": Vector3(1.0, 0.0, 0.0),
		})
	var flock: CrowFlock = FlockScript.new()
	var bus := BusStand.new()
	flock.random_seed = 4711
	flock.first_arrival_seconds = 0.0
	flock.fewest = 3
	flock.set_event_bus(bus)
	flock.set_world_clock(ClockStand.new())
	flock.set_perches(high_wire)
	var man := Node3D.new()
	# Four metres to one side of a wire 8.2 m up. Flat distance 4.0, well inside
	# the eight-metre radius; 3D distance 9.0, well outside it.
	man.position = Vector3(4.0, 0.9, 2.0)
	flock.set_watched(man)
	flock.land_now()
	var left := 1.0
	while left > 0.0:
		flock.advance(FRAME)
		left -= FRAME
	assert_eq(
		flock.perched_count(), 0,
		"a man four metres from a wire 8.2 m up left %d crows sitting on it" % flock.perched_count()
	)
	assert_eq(bus.of(CrowFlock.EVENT_SCATTERED).size(), 1, "walking under the wire published no scatter")
	flock.free()
	man.free()


## ...and he still has to be near it. A radius that had become "anywhere in the
## valley" would be the other failure, and one line of arithmetic separates them.
func test_a_man_well_clear_of_the_wire_leaves_them_alone() -> void:
	var high_wire: Array = [{"at": Vector3(0.0, 8.2, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}]
	var flock: CrowFlock = FlockScript.new()
	flock.random_seed = 4711
	flock.first_arrival_seconds = 0.0
	flock.set_event_bus(BusStand.new())
	flock.set_world_clock(ClockStand.new())
	flock.set_perches(high_wire)
	var man := Node3D.new()
	man.position = Vector3(20.0, 0.9, 0.0)
	flock.set_watched(man)
	flock.land_now()
	var left := 1.0
	while left > 0.0:
		flock.advance(FRAME)
		left -= FRAME
	assert_true(flock.perched_count() > 0, "a man twenty metres away flushed the wire")
	flock.free()
	man.free()


## The camera needs to know where the BIRDS are, which is not where the fright
## was. Both are in the payload and they are different places.
func test_the_scatter_event_says_where_the_birds_are_as_well_as_what_startled_them() -> void:
	var flock: CrowFlock = FlockScript.new()
	var bus := BusStand.new()
	flock.random_seed = 4711
	flock.first_arrival_seconds = 0.0
	flock.set_event_bus(bus)
	flock.set_world_clock(ClockStand.new())
	var man := Node3D.new()
	man.position = Vector3(0.0, 0.0, 4.0)
	flock.set_watched(man)
	flock.set_perches(A_WIRE)
	flock.land_now()
	var left := 0.3
	while left > 0.0:
		flock.advance(FRAME)
		left -= FRAME
	flock.scatter(CrowFlock.CAUSE_PLAYER)
	var events := bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(events.size(), 1, "the scatter published %d events" % events.size())
	if events.is_empty():
		flock.free()
		man.free()
		return
	var payload: Dictionary = events[0]["payload"]
	assert_true(payload.has("aloft"), "the payload does not say where the birds are")
	var aloft: Vector3 = payload["aloft"]
	assert_true(aloft.y > 5.0, "the birds are reported at y = %.2f, which is not up a pole" % aloft.y)
	assert_true(
		aloft.distance_to(payload["position"] as Vector3) > 1.0,
		"the birds and the thing that startled them are being reported in the same place"
	)
	flock.free()
	man.free()
