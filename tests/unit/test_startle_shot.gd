extends TestCase

## The camera exception, held to the five conditions it was granted on.
##
## ---------------------------------------------------------------------------
## WHY THIS FILE IS SHAPED LIKE THE RULING
## ---------------------------------------------------------------------------
## Art Bible rule 1 forbids the camera rotating, and the Director granted exactly
## one exception -- the crow startle close-up -- on five numbered conditions with
## the note that it is written "as a bounded exception rather than letting it be
## quietly broken in some implementation". A bounded exception whose bounds are
## only in prose is quietly broken the first time anybody tunes it.
##
## So there is a test per condition, named after it, and each one fails in a way
## that says which condition went:
##
##   1. 短                two or three seconds
##   2. 不夺取控制权       yields if he stops or turns
##   3. 不切镜头，只倾斜    no frame jumps, either end
##   4. 精确回到原处       bit-for-bit return
##   5. 稀有              a cooldown that actually holds
##
## Condition 4 is asserted as EQUALITY, not as almost-equality, and that is
## deliberate: "逐位相同" is what the ruling says, `assert_almost_eq` would pass
## for a shot that left the camera a thousandth of a degree over, and a thousandth
## of a degree accumulated over an afternoon of startles is a camera nobody
## authored.

const ShotScript := preload("res://src/rendering/startle_shot.gd")
const RigScript := preload("res://src/rendering/camera_rig.gd")

const FRAME := 1.0 / 60.0


class BusStand extends RefCounted:
	var published: Array = []

	func subscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func unsubscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func emit_event(event: StringName, payload: Variant = null) -> void:
		published.append({"event": event, "payload": payload})


var _rig: CameraRig
var _shot: StartleShot
var _man: Node3D


func before_each() -> void:
	_rig = RigScript.new()
	_rig.position = Vector3.ZERO
	# What `CameraRig._ready()` does, done by hand: a rig built with `.new()`
	# never runs it, so its `rotation` would be zero rather than the framing, and
	# every "came back to where it started" assertion below would be comparing
	# against a rig that had never been anywhere.
	_rig.set_lean(Vector3.ZERO)
	_man = Node3D.new()
	_shot = ShotScript.new()
	_shot.random_seed = 4711
	_shot.set_event_bus(BusStand.new())
	_shot.set_camera_rig(_rig)
	_shot.set_watched(_man)


func after_each() -> void:
	_shot.free()
	_rig.free()
	_man.free()


## A man walking a straight line at a steady pace, which is condition 2's
## "玩家继续走" -- the case where the camera is allowed to stay.
func _walk(seconds: float, heading := Vector3(0.0, 0.0, -1.0), speed := 1.4) -> void:
	var left := seconds
	while left > 0.0:
		_man.position += heading * speed * FRAME
		_shot.advance(FRAME)
		left -= FRAME


# --- condition 1: 短 ------------------------------------------------------------


func test_the_shot_is_two_or_three_seconds_and_no_longer() -> void:
	for seed in [1, 77, 4711, 20260812]:
		_shot.random_seed = seed
		_shot.attach()
		assert_true(_shot.begin_now(Vector3(2.0, 8.0, 2.0)), "seed %d refused to start a shot" % seed)
		var ran := 0.0
		while _shot.is_running() and ran < 10.0:
			_man.position += Vector3(0.0, 0.0, -1.4) * FRAME
			_shot.advance(FRAME)
			ran += FRAME
		assert_true(
			ran >= _shot.shot_seconds_min - 0.05 and ran <= _shot.shot_seconds_max + 0.05,
			"seed %d ran a %.2f s shot, outside %.1f..%.1f" % [
				seed, ran, _shot.shot_seconds_min, _shot.shot_seconds_max]
		)
		# Clear the cooldown for the next seed.
		_shot.advance(_shot.cooldown_seconds + 1.0)


# --- condition 2: 不夺取控制权 ----------------------------------------------------


## He keeps walking, so the camera keeps the shot.
func test_a_man_who_keeps_walking_keeps_the_shot() -> void:
	_shot.begin_now(Vector3(2.0, 8.0, 2.0))
	_walk(1.0)
	assert_true(_shot.is_running(), "the shot ended early on a man doing nothing unusual")
	assert_false(_shot.has_yielded(), "the shot gave way to a man walking in a straight line")


## He stops, and it gives way. Standing still is the strongest signal a player
## without a HUD can send that he wants to look at something himself.
func test_it_gives_way_the_moment_he_stops() -> void:
	_shot.begin_now(Vector3(2.0, 8.0, 2.0))
	_walk(0.4)
	assert_false(_shot.has_yielded(), "it yielded before he had done anything")
	# Standing.
	var left := 0.3
	while left > 0.0:
		_shot.advance(FRAME)
		left -= FRAME
	assert_true(_shot.has_yielded(), "the shot held on after he stopped walking")


## He turns, and it gives way. NOT on a wander -- a man walking a line drifts by
## ten or fifteen degrees and did not mean anything by it.
func test_it_gives_way_when_he_turns_but_not_when_he_wanders() -> void:
	_shot.begin_now(Vector3(2.0, 8.0, 2.0))
	_walk(0.4, Vector3(0.0, 0.0, -1.0))
	_walk(0.3, Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(12.0)))
	assert_false(_shot.has_yielded(), "a twelve-degree wander took the camera back")
	_walk(0.2, Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(95.0)))
	assert_true(_shot.has_yielded(), "he turned ninety-five degrees and the camera held on")


## A framing notch is intent as much as a turn is.
func test_a_notch_of_the_framing_wheel_takes_it_back() -> void:
	_shot.begin_now(Vector3(2.0, 8.0, 2.0))
	_walk(0.3)
	assert_false(_shot.has_yielded(), "it yielded before he touched anything")
	_rig.cycle_framing(1)
	_walk(0.1)
	assert_true(_shot.has_yielded(), "he changed the framing and the shot ignored it")


## Yielding is still a LEAN HOME, not a cut. Condition 3 does not stop applying
## because condition 2 fired.
##
## THE FAILURE THIS CATCHES IS A JUMP UP, NOT A JUMP DOWN. Written first as "move
## `_elapsed` into the lean-out phase", which reads as the obvious way to end a
## shot early -- and the start of the lean-out is where the ease curve is ONE. A
## man who stopped half a second in, with the shot a third of the way applied,
## made the camera SNAP TO FULL TILT and then ease down from there. Every frame
## of the whole shot is watched here, not just the frames after the yield,
## because the step was on the frame the yield happened.
func test_giving_way_eases_home_rather_than_snapping() -> void:
	_shot.begin_now(Vector3(2.0, 8.0, 2.0))
	# Stopped early and deliberately: a third of the way in is where a jump to the
	# lean-out's peak is biggest.
	_walk(0.5)
	var leaning := _rig.lean().x
	assert_true(leaning > 0.01, "the camera never leaned at all")
	var last := _rig.lean()
	var worst := 0.0
	var rose_after_yielding := 0.0
	var left := 4.0
	while _shot.is_running() and left > 0.0:
		var before_this_frame := _rig.lean().x
		var yielded_already := _shot.has_yielded()
		_shot.advance(FRAME)
		worst = maxf(worst, (_rig.lean() - last).length())
		if yielded_already:
			rose_after_yielding = maxf(rose_after_yielding, _rig.lean().x - before_this_frame)
		last = _rig.lean()
		left -= FRAME
	assert_true(_shot.has_yielded(), "standing still never yielded")
	assert_false(_shot.is_running(), "the shot never finished after yielding")
	assert_true(
		worst < 0.05,
		"the lean moved %.4f rad in one frame while giving way -- that is a cut" % worst
	)
	assert_almost_eq(
		rose_after_yielding, 0.0, 0.0005,
		"the lean went UP by %.4f rad after the shot had already yielded" % rose_after_yielding
	)
	assert_eq(_rig.lean(), Vector3.ZERO, "the shot yielded and left the camera leaning")


# --- condition 3: 不切镜头，只倾斜 -------------------------------------------------


## The whole shot, frame by frame, watching for a step. A cut in a game with a
## fixed isometric camera is read as a bug or as a cutscene, and this is the
## measurement that says there is not one.
func test_nothing_about_the_shot_ever_jumps() -> void:
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	var last_lean := _rig.lean()
	var last_size := _rig.framing_target()
	var last_aim := _rig.aim_offset()
	var worst_lean := 0.0
	var worst_size := 0.0
	var worst_aim := 0.0
	while _shot.is_running():
		_man.position += Vector3(0.0, 0.0, -1.4) * FRAME
		_shot.advance(FRAME)
		worst_lean = maxf(worst_lean, (_rig.lean() - last_lean).length())
		worst_size = maxf(worst_size, absf(_rig.framing_target() - last_size))
		worst_aim = maxf(worst_aim, (_rig.aim_offset() - last_aim).length())
		last_lean = _rig.lean()
		last_size = _rig.framing_target()
		last_aim = _rig.aim_offset()
	# A smoothstep over ~0.9 s of lean-in has a peak slope of 1.5, so the biggest
	# single frame of a 33-degree tilt is about 0.014 rad. Anything an order of
	# magnitude past that is a step rather than an ease.
	assert_true(
		worst_lean < 0.05,
		"the lean moved %.4f rad in one frame -- that is a cut, not a lean" % worst_lean
	)
	assert_true(
		worst_size < 0.35,
		"the frame size moved %.4f m in one frame" % worst_size
	)
	assert_true(
		worst_aim < 0.35,
		"the aim point moved %.4f m in one frame" % worst_aim
	)


## It starts from the game framing and returns to it, rather than starting from
## somewhere. The first frame must be indistinguishable from no shot at all.
func test_the_first_frame_of_the_shot_is_the_game_framing() -> void:
	var before := _rig.base_rotation()
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	_shot.advance(FRAME)
	assert_true(
		_rig.lean().length() < 0.002,
		"the shot opened %.4f rad away from the game framing" % _rig.lean().length()
	)
	assert_true(
		(_rig.rotation - before).length() < 0.002,
		"the camera was already turned on the first frame of the shot"
	)


# --- condition 4: 精确回到原处 ----------------------------------------------------


## EQUALITY, not almost-equality. See this file's header.
func test_the_camera_comes_back_to_exactly_where_it_was() -> void:
	var rotation_before := _rig.rotation
	var stop_before := _rig.framing_base()
	var target_before := _rig.framing_target()
	var aim_before := _rig.aim_offset()
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	var left := 6.0
	while _shot.is_running() and left > 0.0:
		_man.position += Vector3(0.0, 0.0, -1.4) * FRAME
		_shot.advance(FRAME)
		left -= FRAME
	assert_false(_shot.is_running(), "the shot never ended")
	assert_eq(_rig.rotation, rotation_before, "the camera came back to a different angle")
	assert_eq(_rig.lean(), Vector3.ZERO, "the lean was left on the rig")
	assert_eq(_rig.aim_offset(), aim_before, "the aim offset was left on the rig")
	assert_eq(_rig.framing_base(), stop_before, "the player's chosen stop was changed")
	assert_eq(_rig.framing_target(), target_before, "the frame did not come back to its own size")
	assert_eq(_rig.framing_modifiers().size(), 0, "the shot left a modifier on the framing stack")


## The stop is the BASE and the shot is a modifier on top -- so a player who
## notched the framing before the startle gets HIS stop back, not the default.
func test_the_shot_is_a_modifier_on_the_players_stop_and_not_an_overwrite() -> void:
	_rig.set_framing_index(2)
	var his := _rig.framing_base()
	assert_almost_eq(his, 17.0, 0.0001, "the third stop is not the widest one")
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	_shot.advance(0.9)
	assert_true(
		_rig.framing_target() < his,
		"the camera did not push in at all: %.3f against a base of %.3f" % [_rig.framing_target(), his]
	)
	assert_eq(_rig.framing_base(), his, "the shot wrote the player's stop instead of stacking on it")
	var left := 6.0
	while _shot.is_running() and left > 0.0:
		_shot.advance(FRAME)
		left -= FRAME
	assert_eq(_rig.framing_base(), his, "the player's stop did not survive the shot")
	assert_eq(_rig.framing_target(), his, "the frame did not return to the player's stop")


## A rig pulled out from under a running shot must not be left leaning. Nothing
## else in the game knows how to put the camera back.
func test_a_shot_torn_down_mid_lean_puts_the_camera_back_first() -> void:
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	_shot.advance(0.9)
	assert_true(_rig.is_leaning(), "the camera never leaned")
	_shot.detach()
	assert_eq(_rig.lean(), Vector3.ZERO, "detaching left the camera leaning")
	assert_eq(_rig.rotation, _rig.base_rotation(), "detaching left the camera turned")
	assert_eq(_rig.framing_modifiers().size(), 0, "detaching left a modifier on the framing stack")


# --- condition 5: 稀有 ------------------------------------------------------------


func test_a_second_startle_inside_the_cooldown_gets_no_shot() -> void:
	assert_true(_shot.begin_now(Vector3(4.0, 8.0, 0.0)), "the first shot did not start")
	var left := 6.0
	while _shot.is_running() and left > 0.0:
		_shot.advance(FRAME)
		left -= FRAME
	assert_true(_shot.cooldown_left() > 0.0, "the shot ended with no cooldown at all")
	assert_false(_shot.begin_now(Vector3(4.0, 8.0, 0.0)), "a second shot fired inside the cooldown")
	_shot.advance(_shot.cooldown_seconds + 1.0)
	assert_true(_shot.begin_now(Vector3(4.0, 8.0, 0.0)), "the cooldown never expired")


func test_a_shot_will_not_start_over_a_camera_that_is_already_leaning() -> void:
	_rig.set_lean(Vector3(0.2, 0.0, 0.0))
	assert_false(_shot.begin_now(Vector3(4.0, 8.0, 0.0)), "a shot started over an existing lean")
	_rig.set_lean(Vector3.ZERO)


# --- the composition -------------------------------------------------------------


## Up. The whole argument for this shot is that it inverts the game's usual dark
## on bright -- so if it does not actually raise the camera toward the sky there
## is no reason for it to exist.
func test_the_camera_actually_looks_up() -> void:
	var before := _rig.base_rotation().x
	_shot.begin_now(Vector3(4.0, 8.0, 0.0))
	_shot.advance(1.0)
	assert_true(
		_rig.rotation.x > before + deg_to_rad(tilt_floor()),
		"the camera pitched to %.1f degrees from %.1f -- it is still looking at the ground" % [
			rad_to_deg(_rig.rotation.x), rad_to_deg(before)]
	)
	# ...and the aim point rose with it, or the birds are off the top of the frame.
	assert_true(
		_rig.aim_offset().y > 2.0,
		"the aim point only rose %.2f m, so the shot is pointed over the player's head at nothing" % \
			_rig.aim_offset().y
	)


func tilt_floor() -> float:
	return _shot.tilt_min_degrees * 0.7


## It swings TOWARD the birds, and it swings the other way for birds on the other
## side. A yaw that ignored where the flock was would be a lean for its own sake.
func test_it_swings_toward_the_flock_and_not_at_random() -> void:
	var swings: Array = []
	for aloft in [Vector3(20.0, 8.0, 0.0), Vector3(-20.0, 8.0, 0.0)]:
		_shot.advance(_shot.cooldown_seconds + 1.0)
		assert_true(_shot.begin_now(aloft), "the shot refused to start for %s" % str(aloft))
		_shot.advance(1.0)
		swings.append(_rig.lean().y)
		# Home again.
		var left := 6.0
		while _shot.is_running() and left > 0.0:
			_shot.advance(FRAME)
			left -= FRAME
	assert_true(
		absf(swings[0]) > 0.001 and absf(swings[1]) > 0.001,
		"the camera did not swing at all: %s" % str(swings)
	)
	assert_true(
		swings[0] * swings[1] < 0.0,
		"the camera swung the same way for flocks on opposite sides: %.4f and %.4f" % [swings[0], swings[1]]
	)


## ...and never further than the cap. Rule 1's whole point is that the world does
## not turn, and a big yaw is the part of a lean that reads as the world turning.
func test_the_swing_is_capped_however_far_round_the_flock_is() -> void:
	_shot.begin_now(Vector3(0.0, 8.0, 60.0))
	_shot.advance(1.2)
	assert_true(
		absf(_rig.lean().y) <= deg_to_rad(_shot.swing_max_degrees) + 0.001,
		"the camera swung %.1f degrees, past its %.1f cap" % [
			rad_to_deg(absf(_rig.lean().y)), _shot.swing_max_degrees]
	)


# --- "每一次都不一样" ---------------------------------------------------------------


## THE CLAIM, AS A SPREAD. Same starting conditions, different seeds; the four
## axes this file owns have to land in visibly different places. Asserted as a
## range rather than against a recorded run, for the reason in
## `test_crow_startle.gd`: a snapshot test passes for a system that varies by a
## millimetre.
func test_no_two_shots_are_framed_the_same() -> void:
	var lengths: Array = []
	var tilts: Array = []
	var pushes: Array = []
	var swings: Array = []
	for seed in [3, 41, 4711, 20260812, 31337, 9001]:
		_shot.random_seed = seed
		_shot.attach()
		_shot.advance(_shot.cooldown_seconds + 1.0)
		assert_true(_shot.begin_now(Vector3(6.0, 8.0, 3.0)), "seed %d refused to start" % seed)
		# AT THE MIDDLE OF ITS OWN HOLD, not at a fixed number of seconds. Sampled
		# at a fixed 1.0 s first, and that reads the ease as well as the amount --
		# a longer shot is less far through its lean-in at the same instant, which
		# pulls its measurement back toward the un-leaned framing and hides most of
		# the spread this test exists to find.
		var hold_at: float = _shot.lean_in_fraction + _shot.hold_fraction * 0.5
		var ran := 0.0
		while _shot.is_running() and _shot.progress() < hold_at and ran < 10.0:
			_man.position += Vector3(0.0, 0.0, -1.4) * FRAME
			_shot.advance(FRAME)
			ran += FRAME
		tilts.append(_rig.lean().x)
		pushes.append(_rig.framing_target())
		swings.append(absf(_rig.lean().y))
		while _shot.is_running() and ran < 10.0:
			_man.position += Vector3(0.0, 0.0, -1.4) * FRAME
			_shot.advance(FRAME)
			ran += FRAME
		lengths.append(ran)
	assert_true(
		rad_to_deg(_spread(tilts)) > 4.0,
		"six shots tilted within %.2f degrees of each other" % rad_to_deg(_spread(tilts))
	)
	assert_true(
		_spread(pushes) > 0.4,
		"six shots pushed to within %.3f m of the same frame: %s" % [_spread(pushes), str(pushes)]
	)
	assert_true(
		_spread(lengths) > 0.3,
		"six shots ran within %.3f s of the same length" % _spread(lengths)
	)
	# THE ONE THAT WAS SILENTLY CONSTANT. The flock sits further round than the cap
	# in most of the valley, so a fixed cap meant every shot swung exactly to it --
	# measured at -13.0 degrees in all three captures before the cap itself became
	# a draw. A range that is always saturated is not a range.
	assert_true(
		rad_to_deg(_spread(swings)) > 2.0,
		"six shots swung within %.2f degrees of each other: %s" % [
			rad_to_deg(_spread(swings)), str(swings)]
	)


func _spread(values: Array) -> float:
	var low := 1e9
	var high := -1e9
	for value in values:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	return high - low


# --- what it does and does not fire for ------------------------------------------


## Nightfall empties the wires every single day and a gust does it a few times an
## afternoon. A camera that leaned for those is leaning several times an hour,
## which is condition 5 gone -- and it is the wrong subject anyway: the shot is
## about HIM having startled something.
func test_only_the_man_gets_a_shot() -> void:
	for cause in [CrowFlock.CAUSE_NIGHTFALL, CrowFlock.CAUSE_GUST]:
		_shot.advance(_shot.cooldown_seconds + 1.0)
		_shot._on_scattered({"cause": cause, "aloft": Vector3(4.0, 8.0, 0.0), "count": 3})
		assert_false(_shot.is_running(), "a %s scatter started a camera shot" % cause)
	_shot.chance = 1.0
	_shot.advance(_shot.cooldown_seconds + 1.0)
	_shot._on_scattered({"cause": CrowFlock.CAUSE_PLAYER, "aloft": Vector3(4.0, 8.0, 0.0), "count": 3})
	assert_true(_shot.is_running(), "the man walking under the wire got no shot")
