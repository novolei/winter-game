extends TestCase

## A bird on a wire that the wind is moving.
##
## `src/rendering/wind_sway.gd` writes `global_position` on every span each
## frame, up to 0.14 m. `src/entities/wildlife/perch_points.gd` resolves a perch
## through whatever transform the prop currently has -- so the perch is right on
## every frame and the CROW was not: it was placed once, at landing, and then
## stood in the air the wire used to occupy. At the tight framing stop a crow is
## 26 px and the wire is a one-to-two-pixel stroke, so 0.14 m of separation is a
## bird standing on nothing.
##
## Everything here runs with no SceneTree, the same way `test_crow_flock.gd`
## does: `Crow.ride()` and `CrowFlock.advance()` are public and carry all the
## logic, and `PerchPoints.placement()` composes its parent chain by hand when it
## is out of a tree.

const CrowScript := preload("res://src/entities/wildlife/crow.gd")
const FlockScript := preload("res://src/entities/wildlife/crow_flock.gd")
const PerchScript := preload("res://src/entities/wildlife/perch_points.gd")

const FRAME := 1.0 / 60.0

## What `WireSway` actually does at full gale: 0.14 m across the wind plus 30 per
## cent of that in bob. Written here as a literal rather than read off that file,
## because this is the number this test exists to survive and importing it would
## make the test agree with the wind by construction.
const FULL_TRAVEL := Vector3(0.132, 0.042, 0.021)

var _wire: Node3D
var _perches: PerchPoints


func before_each() -> void:
	# An eight-metre span along its own -Z. `Farmstead._span()` writes
	# `scale.z = length`, so the basis carries the span's direction AND its
	# length, which is what `_span_perches` divides up.
	_wire = Node3D.new()
	_wire.position = Vector3(2.0, 6.0, 0.0)
	_wire.scale = Vector3(1.0, 1.0, 8.0)
	_perches = PerchScript.new()
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_wire.add_child(_perches)


func after_each() -> void:
	# Frees the child with it. Node is not reference-counted (briefing
	# constraint 2).
	_wire.free()


func _a_crow_on_the_first_perch() -> Crow:
	var crow: Crow = CrowScript.new()
	crow.grip(_perches.perches()[0])
	return crow


# --- the defect ----------------------------------------------------------------


## THE ONE THIS FILE EXISTS FOR, stated as the size of the error rather than as a
## boolean. A crow placed by `perch_on` alone knows a position and not a wire.
func test_a_perch_sampled_once_leaves_the_bird_the_wires_whole_travel_behind() -> void:
	var perch: Dictionary = _perches.perches()[0]
	var crow: Crow = CrowScript.new()
	crow.perch_on(perch["at"], perch["facing"])
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	var gap := crow.where().distance_to(_perches.perches()[0]["at"])
	assert_almost_eq(
		gap, FULL_TRAVEL.length(), 0.0001,
		"a bird with no anchor should still be exactly the wire's travel behind it, and was %.4f m" % gap
	)
	crow.free()


func test_a_crow_that_gripped_its_perch_rides_the_wire_that_moves_under_it() -> void:
	var crow := _a_crow_on_the_first_perch()
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	var gap := crow.where().distance_to(_perches.perches()[0]["at"])
	assert_almost_eq(gap, 0.0, 0.0001, "the bird is %.4f m off the wire it is standing on" % gap)
	crow.free()


## The sway is a sine, so most frames move the wire by a fraction of a
## millimetre. An early-out cheap enough to skip those would be a bird that
## follows a gale and ignores a breeze.
func test_it_follows_a_millimetre() -> void:
	var crow := _a_crow_on_the_first_perch()
	_wire.position += Vector3(0.001, 0.0, 0.0)
	crow.ride(0.0)
	var gap := crow.where().distance_to(_perches.perches()[0]["at"])
	assert_almost_eq(gap, 0.0, 0.00005, "a one-millimetre move left the bird %.5f m behind" % gap)
	crow.free()


## Still on the wire through the stagger and through the launch take -- see
## `Crow.is_on_the_wire()`. A bird that stopped riding the moment it was told to
## go would drift off during the 0.97 s the take-off take holds it in place.
func test_it_goes_on_riding_through_the_stagger_and_the_launch() -> void:
	var crow := _a_crow_on_the_first_perch()
	crow.scatter(Vector3(1.0, 0.4, 0.0), 0.2)
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	assert_almost_eq(
		crow.where().distance_to(_perches.perches()[0]["at"]), 0.0, 0.0001,
		"a bird waiting out its share of the stagger stopped following the wire"
	)
	# ...through the launch as well.
	crow.advance(0.25)
	assert_eq(crow.state(), Crow.State.LAUNCHING, "0.25 s past a 0.2 s delay should have started the launch")
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	assert_almost_eq(
		crow.where().distance_to(_perches.perches()[0]["at"]), 0.0, 0.0001,
		"a bird holding its perch through the take-off take stopped following the wire"
	)
	crow.free()


## And lets go the moment it is actually flying. A bird still tied to a wire it
## left is a bird being dragged back to it every frame.
func test_a_bird_in_the_air_is_no_longer_tied_to_the_wire() -> void:
	var crow := _a_crow_on_the_first_perch()
	crow.scatter(Vector3(1.0, 0.4, 0.0), 0.0)
	# A FRAME AT A TIME, the way the flock drives it. Written as one 1.2 s step
	# first, and that only reached LAUNCHING: `advance()` takes at most one state
	# transition per call and rebases its own clock on each, so a single long step
	# is not the same as the frames it stands for.
	var left := 1.5
	while left > 0.0:
		crow.ride(0.0)
		crow.advance(FRAME)
		left -= FRAME
	# `is_flying()` rather than a named state. Written first as `== BEATING`, which
	# stopped being true the day the mill was added between the launch and the
	# commit -- and the question this test is asking has nothing to do with which
	# of the airborne states the bird is in.
	assert_true(
		crow.is_flying(),
		"1.5 s of frames should have put the bird past its launch, and it is in state %d" % crow.state()
	)
	assert_false(crow.has_feet_down(), "a bird 1.5 s into its departure still has its feet on the wire")
	var flying := crow.where()
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	assert_eq(crow.where(), flying, "riding pulled a flying bird back toward the wire")
	crow.free()


# --- what moves, and what does not ---------------------------------------------


## `WireSway` only ever TRANSLATES a span -- rotating a straight segment about
## its own chord is a no-op, which is why that file settled on a rigid slide. So
## the honest answer to "does the bird need to re-aim in a gust" is no, and this
## measures it rather than asserting it in a comment.
func test_a_wire_that_only_slides_does_not_turn_the_bird_on_it() -> void:
	var crow := _a_crow_on_the_first_perch()
	var before := crow.facing()
	_wire.position += FULL_TRAVEL
	crow.ride(0.0)
	assert_almost_eq(
		crow.facing().angle_to(before), 0.0, 0.0001,
		"a pure translation turned the bird by %.3f degrees" % rad_to_deg(crow.facing().angle_to(before))
	)
	crow.free()


## ...and if a prop ever does turn -- a pole knocked over, a wire re-strung
## between two settled anchors on a reload -- the bird turns with it. Free,
## because it sits behind the same "did anything move" gate.
func test_a_prop_that_turns_turns_the_bird_standing_on_it() -> void:
	var crow := _a_crow_on_the_first_perch()
	var before := crow.facing()
	_wire.rotate_y(PI * 0.5)
	crow.ride(0.0)
	assert_almost_eq(
		rad_to_deg(crow.facing().angle_to(before)), 90.0, 0.5,
		"a quarter turn of the wire turned the bird by %.1f degrees" % rad_to_deg(crow.facing().angle_to(before))
	)
	assert_almost_eq(
		crow.where().distance_to(_perches.perches()[0]["at"]), 0.0, 0.0001,
		"a turned wire left the bird off its perch"
	)
	crow.free()


# --- the bird reacting rather than merely tracking ------------------------------


## `flap` -- Malbers' `Rav_Fly_Stand`, wings worked without leaving the perch --
## was imported in Wave 2 and never played. It is what a bird on a swaying wire
## does.
##
## The threshold is measured, not chosen: over an hour of `wind_valley` (the
## `pale_day` profile) a latch at 0.45 on / 0.36 off holds 10.8% of the time in
## stretches averaging 8.3 s. Long enough to read, rare enough to be an event.
func test_a_hard_enough_gust_puts_its_wings_out_for_balance() -> void:
	var crow := _a_crow_on_the_first_perch()
	assert_false(crow.is_balancing(), "a bird in still air should be sitting, not flapping")
	crow.ride(0.50)
	assert_true(crow.is_balancing(), "a crow in a 0.50 gust did not open its wings for balance")
	crow.free()


## Hysteresis, for the same reason `WindSystem._report()` has it: a strength
## hovering on a threshold would otherwise restart the take every other frame,
## which is a bird vibrating.
func test_it_does_not_flicker_on_the_threshold() -> void:
	var crow := _a_crow_on_the_first_perch()
	crow.ride(0.50)
	crow.ride(0.40)
	assert_true(crow.is_balancing(), "0.40 is inside the hysteresis band and should not have settled the bird")
	crow.ride(0.30)
	assert_false(crow.is_balancing(), "the gust passed and the bird went on flapping")
	crow.ride(0.40)
	assert_false(crow.is_balancing(), "0.40 is inside the hysteresis band and should not have started a flap")
	crow.free()


## A bird that has been told to go is playing `look`, and then `take_off`.
## Balancing on top of either would cut the departure's own animation off at the
## knees.
func test_a_bird_that_has_been_told_to_go_does_not_start_balancing() -> void:
	var crow := _a_crow_on_the_first_perch()
	crow.scatter(Vector3(1.0, 0.4, 0.0), 0.2)
	crow.ride(0.90)
	assert_false(crow.is_balancing(), "a bird already leaving started a balance take over its departure")
	crow.free()


## And a bird that was balancing when it was told to go stops, so the flag does
## not survive into a departure.
func test_being_told_to_go_settles_the_wings() -> void:
	var crow := _a_crow_on_the_first_perch()
	crow.ride(0.90)
	assert_true(crow.is_balancing(), "0.90 should have opened the wings")
	crow.scatter(Vector3(1.0, 0.4, 0.0), 0.0)
	assert_false(crow.is_balancing(), "the balance flag survived into the departure")
	crow.free()
