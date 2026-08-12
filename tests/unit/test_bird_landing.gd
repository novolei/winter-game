extends TestCase

## How a bird comes down, which is the half nobody bothers with.
##
## ---------------------------------------------------------------------------
## THE OWNER'S WORDS AND THE NUMBER UNDER THEM
## ---------------------------------------------------------------------------
##   停靠降落在电线上的过程太多余突兀和生硬了
##
## Measured on the shipped pigeon before this file existed, one whole return
## flown a frame at a time:
##
##   crow      descent 1.2953 s   peak descent rate  3.349 m/s   peak speed  5.107 m/s
##   pigeon    descent 0.2419 s   peak descent rate 18.097 m/s   peak speed 27.396 m/s
##
## The same code, the same 2.93 m of air, and a bird falling five and a half
## times faster than the other one. The reason is arithmetic rather than
## oversight: the descent window was `land_seconds * land_flare`, so it was the
## LANDING TAKE'S own length -- and `Rav_Land` is 67 frames where `Dove_Fly to
## Idle` is ten. A species whose pack shipped a short landing take got a short
## landing, and nothing in the project said the two were different questions.
##
## The seam was the other half of it. The bird crossed into the flare doing
## 4.200 m/s and the next frame had it at 10.140 -- because the old descent was
## a `smoothstep` from `_land_from`, which starts at REST. A bird gliding in was
## stopped dead and then thrown at the wire.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE HOLDS TO ACCOUNT
## ---------------------------------------------------------------------------
## Every claim here is about the MECHANISM and is asserted for both birds, so a
## third species from a pack with a two-frame landing take cannot inherit the
## defect this file was written for.
##
##   IT SLOWS DOWN        the bird is already slowing before the flare begins,
##                        and the flare opens at the speed the approach ended at
##                        rather than at zero
##   IT FLARES            the last stretch is a hang -- almost no descent left
##                        in the final quarter -- and the landing take's own
##                        touchdown frame falls on the frame the feet touch,
##                        whatever length that take happens to be
##   IT SETTLES           there is a beat between the feet touching and the bird
##                        becoming furniture, and it is riding the wire for it
##
## And one negative: THE CROW IS UNCHANGED IN LENGTH. Its landing was the one
## the Art Bible signed off, so `descent_seconds + settle_seconds` still has to
## come to `land_seconds` for it, to the millisecond.

const CrowScript := preload("res://src/entities/wildlife/crow.gd")
const PigeonScript := preload("res://src/entities/wildlife/pigeon.gd")
const SpeciesScript := preload("res://src/definitions/bird_species.gd")

const CROW: BirdSpecies = preload("res://data/wildlife/crow.tres")
const PIGEON: BirdSpecies = preload("res://data/wildlife/pigeon.tres")

const FRAME := 1.0 / 60.0

## Where the bird comes back to, and where it enters the world.
const PERCH := {"at": Vector3(0.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}
const FROM := Vector3(0.0, 12.0, 26.0)


## One whole return, sampled every frame.
##
## Returns the descent as rows of `{t, at, speed, down, feet}` where `t` is
## measured from the frame the flare began, plus the marks either side of it.
## A landing is a curve and a curve cannot be asserted from one number.
class Descent extends RefCounted:
	var began := -1.0
	var touched := -1.0
	var perched := -1.0
	var entry_speed := 0.0
	var opening_speed := 0.0
	var peak_speed := 0.0
	var peak_down := 0.0
	var rows: Array = []
	var facing_at_touchdown := Vector3.ZERO
	var settle_facing_turn := 0.0

	func flare_seconds() -> float:
		return touched - began

	func settle_seconds() -> float:
		return perched - touched

	## How much of the whole drop is still to come with `fraction` of the descent's
	## time left. A landing that hangs has almost none of it; one that arrives has
	## a quarter of it.
	func share_of_the_drop_left_in_the_last(fraction: float, floor_y: float) -> float:
		var mark := flare_seconds() * (1.0 - fraction)
		var high: float = (rows[0]["at"] as Vector3).y if not rows.is_empty() else floor_y
		var at_mark: float = high
		for row in rows:
			if row["t"] <= mark:
				at_mark = (row["at"] as Vector3).y
		return (at_mark - floor_y) / maxf(high - floor_y, 0.0001)


func _fly(bird: Bird) -> Descent:
	var out := Descent.new()
	bird.approach(PERCH, FROM, 1.8, 1.2)
	var previous := bird.where()
	var previous_speed := 0.0
	var t := 0.0
	var guard := 0
	while guard < 3600 and out.perched < 0.0:
		guard += 1
		bird.advance(FRAME)
		t += FRAME
		var now := bird.where()
		var speed := now.distance_to(previous) / FRAME
		var down := (previous.y - now.y) / FRAME
		if out.began < 0.0 and bird.is_landing():
			out.began = t
			out.entry_speed = previous_speed
			out.opening_speed = speed
		if out.began >= 0.0 and out.perched < 0.0:
			out.peak_speed = maxf(out.peak_speed, speed)
			out.peak_down = maxf(out.peak_down, down)
			out.rows.append({
				"t": t - out.began, "at": now, "speed": speed, "down": down,
				"feet": bird.has_feet_down(),
			})
		if out.began >= 0.0 and out.touched < 0.0 and bird.has_feet_down():
			out.touched = t
			out.facing_at_touchdown = bird.facing()
		if bird.is_perched():
			out.perched = t
			out.settle_facing_turn = rad_to_deg(out.facing_at_touchdown.angle_to(bird.facing()))
		previous = now
		previous_speed = speed
	return out


func _crow() -> Bird:
	return CrowScript.new()


func _pigeon() -> Bird:
	return PigeonScript.new()


# --- it slows down --------------------------------------------------------------


## THE SEAM. The old descent was a `smoothstep` from the flare point, and a
## smoothstep starts at rest -- so a bird gliding in at 4.200 m/s was stopped
## dead for one frame and then flung at the wire at 10.140. Whatever the curve
## is, it has to leave the approach at the speed the approach was doing.
func test_the_flare_opens_at_the_speed_the_approach_ended_at() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		assert_true(flown.began > 0.0, "the %s never started its landing" % pair[0])
		assert_true(
			absf(flown.opening_speed - flown.entry_speed) <= flown.entry_speed * 0.35,
			("the %s crossed into its flare at %.3f m/s and the first frame of the descent moved it at "
				+ "%.3f m/s -- a landing that starts with a step in the speed reads as two motions with "
				+ "a seam, which is the whole of 生硬") % [pair[0], flown.entry_speed, flown.opening_speed]
		)
		bird.free()


## ...and it is already slowing before that. A bird that flies at cruise until
## the frame it lands has no deceleration to read; the last stretch of the
## approach is where the impression lives.
func test_the_approach_sheds_speed_before_the_flare_rather_than_at_it() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		assert_true(
			flown.entry_speed < bird.mill_speed * 0.85,
			("the %s was still doing %.3f m/s of its %.3f m/s milling speed on the frame its flare began "
				+ "-- it arrived rather than slowed") % [pair[0], flown.entry_speed, bird.mill_speed]
		)
		bird.free()


# --- it flares ------------------------------------------------------------------


## THE NUMBER THE OWNER SAW. The pigeon came down at 18.097 m/s where the crow
## comes down at 3.349, out of the same 2.93 m of air, because the descent
## window was the landing TAKE's length and the dove pack's is ten frames.
##
## The bound is on the RATE rather than on the window, deliberately: a species
## whose approach geometry differs would satisfy a duration and still drop like
## a stone.
func test_no_bird_falls_onto_its_perch() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		assert_true(
			flown.peak_down <= 6.0,
			("the %s came down at %.3f m/s at its fastest. A bird settling onto a wire does not fall at it; "
				+ "the crow's own measured figure is 3.349 m/s.") % [pair[0], flown.peak_down]
		)
		bird.free()


## NO LANDING SPEEDS UP INTO THE PERCH. The universal half, and it holds for
## every bird whatever it declares: a descent that spent its last quarter of the
## time on more than its last quarter of the drop would be accelerating into the
## wire.
##
## Asserted on DISTANCE rather than on speed, because a share of the drop is a
## statement about the picture where a share of the peak is a statement about
## the curve.
func test_no_landing_speeds_up_into_the_perch() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		var left := flown.share_of_the_drop_left_in_the_last(0.25, (PERCH["at"] as Vector3).y)
		assert_true(
			left < 0.25,
			("the %s still had %.1f per cent of its drop to make with a quarter of its descent left "
				+ "-- it is speeding up into the wire, not slowing into it") % [pair[0], left * 100.0]
		)
		bird.free()


## A BEAT OF HANG BEFORE THE FEET TOUCH, for a bird that asks for one. Wings out,
## the body pitching up, and almost nothing left of the descent.
##
## SCOPED TO THE SPECIES THAT DECLARE IT, and that is not a softened test -- it
## is the true claim. `flare_hang` is per-species precisely because the bend is
## not free (see `BirdSpecies.flare_hang`), and the crow declines it: its landing
## was reviewed and approved with the unbent curve. Holding the crow to a tenth
## would be asserting that a shot which was signed off is wrong.
##
## The threshold is the measurement either side of it: an unbent descent leaves
## 15.5 per cent of the drop in the last quarter of the time and a bent one 7.4.
func test_a_bird_that_asks_for_a_flare_hang_gets_one() -> void:
	var asked := 0
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		if bird.flare_hang <= 1.0:
			bird.free()
			continue
		asked += 1
		var flown := _fly(bird)
		var left := flown.share_of_the_drop_left_in_the_last(0.25, (PERCH["at"] as Vector3).y)
		assert_true(
			left <= 0.10,
			("the %s declares flare_hang %.2f and still had %.1f per cent of its drop to make with a "
				+ "quarter of its descent left -- the bend is not reaching the curve")
				% [pair[0], bird.flare_hang, left * 100.0]
		)
		bird.free()
	assert_true(asked > 0, "no shipped species asks for a hang, so this test measured nothing")


## The crow declines it, and says so in its own data rather than by accident.
func test_the_crow_declines_the_hang_and_the_pigeon_asks_for_it() -> void:
	assert_almost_eq(
		CROW.flare_hang, 1.0, 0.0001,
		("the crow's landing was reviewed and approved with the unbent curve; flare_hang %.2f bends it "
			+ "and raises its fall rate as a side effect of a change made for another bird") % CROW.flare_hang
	)
	assert_true(
		PIGEON.flare_hang > 1.0,
		("the pigeon's pack gave it no flare to play -- `Dove_Fly to Idle` is ten frames -- so without "
			+ "a bend its descent is a symmetric slide. flare_hang is %.2f") % PIGEON.flare_hang
	)


## THE CROW'S DESCENT IS THE CURVE THAT WAS APPROVED, and this is what says so
## in numbers rather than in a duration.
##
## `test_the_crows_landing_still_lasts_exactly_its_take` pins the timing, which
## a change to the SHAPE would sail straight past. These two are the shape:
## measured on the shipped build before any of this work, one whole return flown
## at 1/60 s, the crow peaked at 3.349 m/s of descent and left 16.0 per cent of
## its drop for the last quarter of the time.
##
## Both are stated as absolutes rather than read off the code, so a future
## "shared" constant that quietly bends this bird again turns the suite red.
func test_the_crows_descent_is_still_the_shape_that_was_signed_off() -> void:
	var crow := _crow()
	var flown := _fly(crow)
	assert_almost_eq(
		flown.peak_down, 3.349, 0.10,
		"the crow now falls at %.3f m/s at its fastest; the approved landing peaked at 3.349" % flown.peak_down
	)
	var left := flown.share_of_the_drop_left_in_the_last(0.25, (PERCH["at"] as Vector3).y)
	assert_almost_eq(
		left, 0.160, 0.02,
		"the crow now leaves %.1f per cent of its drop for the last quarter; the approved landing left 16.0" % [
			left * 100.0]
	)
	crow.free()


## THE TAKE'S OWN TOUCHDOWN FRAME LANDS ON THE FRAME THE FEET TOUCH, whatever
## length the take is. `land_flare` is where in the take the animator brought the
## body down; a take shorter than the descent therefore has to start LATE, with
## the bird gliding down to meet it, rather than being stretched over the whole
## fall or being played at the top of it.
func test_the_landing_take_finishes_its_flare_on_the_frame_the_feet_touch() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var expected: float = bird.descent_seconds
		var flown := _fly(bird)
		assert_almost_eq(
			flown.flare_seconds(), expected, 0.02,
			"the %s's feet touched %.4f s into its landing, not the %.4f s its descent is" % [
				pair[0], flown.flare_seconds(), expected]
		)
		bird.free()


# --- it settles -------------------------------------------------------------------


## THE BIRD ARRIVING AND INSTANTLY BECOMING FURNITURE IS WHAT 生硬 MEANS. There
## has to be a beat after the feet touch -- a wing fold, a look about -- before
## the idle takes over.
func test_there_is_a_beat_between_the_feet_touching_and_the_idle() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		assert_true(
			flown.settle_seconds() >= 0.35,
			"the %s stood up as furniture %.4f s after its feet touched" % [pair[0], flown.settle_seconds()]
		)
		bird.free()


## And it is ON the wire for that beat, not hanging beside it. `_start_landing`
## left the anchor null until the whole take had finished, so a bird whose feet
## were down sat still through half a second of a swaying wire.
func test_a_bird_whose_feet_are_down_is_already_riding_the_wire() -> void:
	var span := PerchPoints.new()
	span.kind = PerchPoints.Kind.SPAN
	var holder := Node3D.new()
	holder.add_child(span)
	holder.position = Vector3(0.0, 6.0, 0.0)
	var bird := _pigeon()
	var perches := span.perches()
	assert_true(perches.size() > 0, "the stand-in wire declared no perches")
	if perches.size() > 0:
		var perch: Dictionary = perches[0]
		bird.approach(perch, perch["at"] as Vector3 + Vector3(0.0, 6.0, 24.0), 0.0, 0.0)
		var guard := 0
		while guard < 3600 and not bird.has_feet_down():
			guard += 1
			bird.advance(FRAME)
		assert_true(bird.has_feet_down(), "the bird never got its feet down")
		assert_false(bird.is_perched(), "the bird finished its whole landing before its feet touched")
		assert_not_null(
			bird.anchor(),
			"a bird standing on the wire with its landing take still running holds no declaration, "
				+ "so a gust that moved the wire under it would leave it beside the wire"
		)
	bird.free()
	holder.free()


## The bird squares up onto the wire rather than snapping to it. `_start_landing`
## used to `look_at` the perch's own facing on the frame the flare began, which
## is a bird changing heading instantly while it is still three metres up.
func test_the_bird_turns_onto_the_wire_over_the_landing_rather_than_snapping_to_it() -> void:
	for pair in [["crow", _crow()], ["pigeon", _pigeon()]]:
		var bird := pair[1] as Bird
		var flown := _fly(bird)
		assert_true(
			flown.settle_facing_turn > 0.5,
			("the %s's heading was already final on the frame its feet touched (%.2f degrees of settle) "
				+ "-- it snapped onto the wire somewhere earlier") % [pair[0], flown.settle_facing_turn]
		)
		bird.free()


# --- and the crow is unchanged -------------------------------------------------------


## THE ONE THING THAT MUST NOT HAVE MOVED. `Rav_Land` is 67 frames at 30 fps and
## its body comes down 58 per cent of the way through; the crow's whole landing
## was built on that and the Art Bible signed the shot off. Splitting the window
## into a descent and a settle may not change what it comes to.
func test_the_crows_landing_still_lasts_exactly_its_take() -> void:
	assert_almost_eq(
		CROW.descent_seconds + CROW.settle_seconds, 67.0 / 30.0, 0.001,
		"the crow's descent %.4f s plus its settle %.4f s no longer comes to Rav_Land's own 2.2333 s" % [
			CROW.descent_seconds, CROW.settle_seconds]
	)
	assert_almost_eq(
		CROW.descent_seconds, (67.0 / 30.0) * 0.58, 0.001,
		"the crow's feet no longer touch 58 per cent of the way through Rav_Land"
	)


## ...and the pigeon's no longer is its take, which is the whole change.
func test_the_pigeons_descent_is_no_longer_its_ten_frame_take() -> void:
	assert_true(
		PIGEON.descent_seconds > PIGEON.land_seconds * PIGEON.land_flare * 3.0,
		("the pigeon's descent is %.4f s against the %.4f s its landing take's flare window is -- "
			+ "the two are still the same question") % [
			PIGEON.descent_seconds, PIGEON.land_seconds * PIGEON.land_flare]
	)
	assert_almost_eq(
		PIGEON.land_seconds, 0.417, 0.001,
		"the dove's landing TAKE is still ten frames at 24 fps and that number may not drift"
	)


## Every species has to answer both, or a third bird gets a zero-length descent
## and drops onto the wire in one frame.
func test_every_species_declares_a_descent_and_a_settle() -> void:
	for species in [CROW, PIGEON]:
		var bird: BirdSpecies = species
		assert_true(
			bird.descent_seconds > 0.2,
			"%s declares a %.4f s descent, which is one or two frames" % [bird.species_name, bird.descent_seconds]
		)
		assert_true(
			bird.settle_seconds > 0.2,
			"%s declares a %.4f s settle" % [bird.species_name, bird.settle_seconds]
		)
