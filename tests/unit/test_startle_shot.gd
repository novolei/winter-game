extends TestCase

## The camera exception, held to what the owner asked for and to what survived
## of the Art Bible's ruling.
##
## ---------------------------------------------------------------------------
## THE FIVE STEPS, IN HIS OWN ORDER
## ---------------------------------------------------------------------------
##   当乌鸦被惊飞的时候，默认的摄像机只要自动动画聚焦到乌鸦起飞的范围内就好了，
##   不要对玩家角色做任何的操作，动画播放完毕后自动恢复到摄像机原位置
##
##   1. 类似范围触发       he walks inside a radius and it fires
##   2. 自动动画聚焦        the camera animates to frame the take-off
##   3. 不要对玩家做任何操作 NOTHING touches the player
##   4. 自动恢复到原位置     and it animates back to exactly where it was
##
## and the Art Bible ruling, unamended:
##
##   RETURNS EXACTLY   asserted as EQUALITY, not almost-equality. "逐位相同" is
##                     what the ruling says; `assert_almost_eq` would pass for a
##                     shot that left the camera a thousandth of a degree over,
##                     and a thousandth of a degree per startle over seven days
##                     is a camera nobody authored.
##   NEVER A CUT       every frame of the move watched for a step.
##   NEVER TAKES       nothing in `startle_shot.gd` calls into the player at all,
##   CONTROL           and `test_it_never_touches_the_player` is what pins that.
##   SHORT, RARE       a drawn length, and a cooldown.
##
## And the one the coordinator added: DO NOT LOSE THE MAN. Most players will walk
## straight through the trigger without stopping, so
## `test_walking_straight_through_never_loses_him` does exactly that and asserts
## he is inside the picture on every frame of the move.

const ShotScript := preload("res://src/rendering/startle_shot.gd")
const RigScript := preload("res://src/rendering/camera_rig.gd")
const FlockScript := preload("res://src/entities/wildlife/crow_flock.gd")

const FRAME := 1.0 / 60.0

## A wire off to one side of him, so "did it turn toward the birds" and "which
## shoulder" are questions with big answers.
const A_WIRE := [
	{"at": Vector3(10.0, 7.0, 2.0), "facing": Vector3(0.0, 0.0, 1.0)},
	{"at": Vector3(10.0, 7.0, 4.0), "facing": Vector3(0.0, 0.0, 1.0)},
	{"at": Vector3(10.0, 7.0, 6.0), "facing": Vector3(0.0, 0.0, 1.0)},
]


class BusStand extends RefCounted:
	func subscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func unsubscribe(_event: StringName, _callback: Callable) -> void:
		pass

	func emit_event(_event: StringName, _payload: Variant = null) -> void:
		pass


class ClockStand extends RefCounted:
	func is_night() -> bool:
		return false


## Something with a position, and a tripwire. `touched` is set by anything the
## shot might plausibly do to a player; nothing must ever set it.
class ManStand extends Node3D:
	var touched := false

	func face_toward(_direction: Vector3) -> void:
		touched = true

	func set_facing(_direction: Vector3) -> void:
		touched = true

	func stop() -> void:
		touched = true


var _rig: CameraRig
var _shot: StartleShot
var _flock: CrowFlock
var _man: ManStand


func before_each() -> void:
	_rig = RigScript.new()
	_rig.position = Vector3.ZERO
	# What `CameraRig._ready()` does, by hand: a rig built with `.new()` never
	# runs it, so its `rotation` would be zero rather than the framing and every
	# "came back to where it started" assertion below would be comparing against a
	# rig that had never been anywhere.
	_rig.set_lean(Vector3.ZERO)
	_man = ManStand.new()
	# OUT OF RANGE to begin with. The trigger is proximity, so a man standing
	# inside it in `before_each` means every test starts with a shot already
	# running and `begin_now()` refusing -- which is what happened, and reported
	# itself as "seed 1 refused to start a shot".
	_man.position = Vector3(-40.0, 0.0, 4.0)
	_flock = FlockScript.new()
	_flock.random_seed = 4711
	_flock.first_arrival_seconds = 0.0
	_flock.fewest = 3
	# Nothing else may empty this wire: the shot is what puts them up.
	_flock.flush_radius_m = 0.0
	_flock.set_event_bus(BusStand.new())
	_flock.set_world_clock(ClockStand.new())
	_flock.set_perches(A_WIRE)
	_flock.land_now()
	_shot = ShotScript.new()
	_shot.random_seed = 4711
	_shot.set_event_bus(BusStand.new())
	_shot.set_camera_rig(_rig)
	_shot.set_crow_flock(_flock)
	_shot.set_watched(_man)
	_shot.attach()


func after_each() -> void:
	_shot.free()
	_flock.free()
	_rig.free()
	_man.free()


## One frame of everything, INCLUDING the rig's own follow -- which `_process`
## does in the game and which a rig built with `.new()` never runs. Without it
## the rig sits at the origin, `frame_position()` measures against a camera that
## is not where the camera is, and every framing assertion below is nonsense.
func _tick() -> void:
	_shot.advance(FRAME)
	_flock.advance(FRAME)
	var wanted := _man.position + Vector3(0.0, _rig.target_height, 0.0) + _rig.aim_offset()
	_rig.position = _rig.position.lerp(wanted, 1.0 - exp(-_rig.follow_speed * FRAME))


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_tick()
		left -= FRAME


func _run_to_the_end() -> float:
	var ran := 0.0
	while _shot.is_running() and ran < 12.0:
		_tick()
		ran += FRAME
	return ran


# --- 1. the proximity trigger -----------------------------------------------------


## He walks inside the radius and it fires. Not "when they happen to scatter" --
## a range check, so it is reliable and he can go and find it again.
func test_walking_inside_the_radius_fires_it() -> void:
	# Well outside, which is where `before_each` leaves him.
	_run(0.5)
	assert_false(_shot.is_running(), "the shot fired from forty metres away")
	# ...and inside.
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	assert_true(_shot.is_running(), "he walked under the wire and nothing happened")


## The radius has to be WIDER than the flock's own flush radius, or the birds
## burst before the camera has moved and the whole sequence watches an empty
## wire. This is arithmetic, not taste, so it is asserted rather than commented.
func test_the_trigger_reaches_further_than_the_flock_flushes() -> void:
	var shipped: CrowFlock = FlockScript.new()
	assert_true(
		_shot.trigger_radius_m > shipped.flush_radius_m,
		"the camera triggers at %.1f m and the birds leave at %.1f m -- the shot would open on an empty wire" % [
			_shot.trigger_radius_m, shipped.flush_radius_m]
	)
	shipped.free()


## An empty wire is not a startle. Nothing to be startled means nothing to watch.
func test_an_empty_wire_does_not_fire_anything() -> void:
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	_run(6.0)
	assert_eq(_flock.perched_count(), 0, "the wire did not empty")
	_shot.advance(_shot.cooldown_seconds + 1.0)
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.5)
	assert_false(_shot.is_running(), "the camera moved for a wire with nothing on it")


# --- 2. nothing touches the player ------------------------------------------------


## 不要对玩家角色做任何的操作. The tripwire: `ManStand` records any call the shot
## could plausibly make on a player, and nothing may set it.
##
## This is the condition the whole design turns on. An earlier version of this
## file DID turn his body, and it was charming exactly once -- a proximity trigger
## fires many times across seven days, and anything that moves him starts reading
## as the game taking him by the arm.
func test_it_never_touches_the_player() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	var where_he_was := _man.position
	var how_he_was := _man.rotation
	_run(0.1)
	assert_true(_shot.is_running(), "the shot did not fire")
	_run_to_the_end()
	assert_false(_man.touched, "the shot called into the player")
	assert_eq(_man.position, where_he_was, "the shot moved him")
	assert_eq(_man.rotation, how_he_was, "the shot turned him")


# --- 3, 4, 5. the move ------------------------------------------------------------


## Over his SHOULDER: the frame has to hold him and the birds at once, which is
## what a third-person shot of something above you is.
func test_the_camera_frames_him_and_the_birds_together() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	# To the hold, where the move is fully applied.
	_run(_shot.shot_seconds_min * (_shot.dolly_in_fraction + _shot.hold_fraction * 0.5))
	var aim := _shot.looking_at()
	# `position`, not `global_position`: nothing here is in a tree, and reading
	# the global one prints an engine error the runner cannot see but the wrapper
	# can -- which is exactly what it did.
	var him := _man.position + Vector3(0.0, 1.7, 0.0)
	var birds := Vector3(10.0, 7.0, 4.0)
	assert_true(
		aim.y > him.y + 0.5,
		"the camera is aimed at %.2f m, barely above his head at %.2f m" % [aim.y, him.y]
	)
	assert_true(
		aim.y < birds.y,
		"the camera is aimed at %.2f m, above the birds at %.2f m -- he is out of the picture" % [
			aim.y, birds.y]
	)
	# It swung round toward them rather than staying on the isometric bearing --
	# and not so far that he is off the back of the frame, which is what the cap is.
	assert_true(
		absf(_rig.lean().y) > deg_to_rad(10.0),
		"the camera only swung %.1f degrees -- it is not looking at them" % rad_to_deg(absf(_rig.lean().y))
	)
	assert_true(
		absf(_rig.lean().y) <= deg_to_rad(_shot.swing_max_degrees) + 0.001,
		"the camera swung %.1f degrees, past its own %.1f cap" % [
			rad_to_deg(absf(_rig.lean().y)), _shot.swing_max_degrees]
	)
	# ...and up off the 45-degree isometric, which is what "shoulder" means here.
	assert_true(
		_rig.rotation.x > _rig.base_rotation().x + deg_to_rad(20.0),
		"the camera pitched to %.1f degrees from %.1f -- it is still the isometric view" % [
			rad_to_deg(_rig.rotation.x), rad_to_deg(_rig.base_rotation().x)]
	)


## The birds go up while the camera is watching, not before it has arrived.
func test_the_burst_happens_after_the_camera_has_got_there() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	assert_true(_shot.is_running(), "the shot did not fire")
	assert_true(_flock.perched_count() > 0, "the birds went before the camera moved")
	# Just short of the burst.
	_run(_shot.shot_seconds_min * _shot.burst_at * 0.7)
	assert_true(
		_flock.perched_count() > 0,
		"the birds went %.0f%% into the shot, before the camera had arrived" % (_shot.burst_at * 70.0)
	)
	_run_to_the_end()
	assert_eq(_flock.perched_count(), 0, "the shot ran and the birds never left")


func test_it_runs_for_the_length_it_drew_and_no_longer() -> void:
	for seed in [1, 77, 4711, 20260812]:
		_shot.random_seed = seed
		_shot.attach()
		_shot.advance(_shot.cooldown_seconds + 1.0)
		assert_true(_shot.begin_now(), "seed %d refused to start a shot" % seed)
		var ran := _run_to_the_end()
		assert_true(
			ran >= _shot.shot_seconds_min - 0.05 and ran <= _shot.shot_seconds_max + 0.05,
			"seed %d ran a %.2f s shot, outside %.1f..%.1f" % [
				seed, ran, _shot.shot_seconds_min, _shot.shot_seconds_max]
		)
		_shot.advance(_shot.cooldown_seconds + 1.0)


## 以动画的形式, both ways. Every frame of the whole move, watched for a step.
func test_nothing_about_the_move_ever_jumps() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	var last_lean := _rig.lean()
	var last_size := _rig.framing_target()
	var last_aim := _rig.aim_offset()
	var worst_lean := 0.0
	var worst_size := 0.0
	var worst_aim := 0.0
	while _shot.is_running():
		_shot.advance(FRAME)
		_flock.advance(FRAME)
		worst_lean = maxf(worst_lean, (_rig.lean() - last_lean).length())
		worst_size = maxf(worst_size, absf(_rig.framing_target() - last_size))
		worst_aim = maxf(worst_aim, (_rig.aim_offset() - last_aim).length())
		last_lean = _rig.lean()
		last_size = _rig.framing_target()
		last_aim = _rig.aim_offset()
	# A smoothstep over ~0.8 s has a peak slope of 1.5, so the biggest single
	# frame of a 40-degree swing is about 0.017 rad. An order of magnitude past
	# that is a step rather than an ease.
	assert_true(worst_lean < 0.06, "the camera turned %.4f rad in one frame -- that is a cut" % worst_lean)
	assert_true(worst_size < 0.35, "the frame size moved %.4f m in one frame" % worst_size)
	assert_true(worst_aim < 0.60, "the aim point moved %.4f m in one frame" % worst_aim)


## The first frame is the game's own framing. A move that opened somewhere would
## be a cut however smooth the rest of it was.
func test_the_first_frame_is_the_game_framing() -> void:
	var before := _rig.base_rotation()
	_man.position = Vector3(2.0, 0.0, 4.0)
	_shot.advance(FRAME)
	assert_true(_shot.is_running(), "the shot did not fire")
	assert_true(
		_rig.lean().length() < 0.002,
		"the move opened %.4f rad away from the game framing" % _rig.lean().length()
	)
	assert_true(
		(_rig.rotation - before).length() < 0.002,
		"the camera was already turned on the first frame"
	)


## 5. 移轴回到默认的位置 -- and EQUALITY, not almost-equality.
func test_the_camera_comes_back_to_exactly_where_it_was() -> void:
	var rotation_before := _rig.rotation
	var stop_before := _rig.framing_base()
	var target_before := _rig.framing_target()
	var aim_before := _rig.aim_offset()
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	assert_true(_shot.is_running(), "the shot did not fire")
	_run_to_the_end()
	assert_false(_shot.is_running(), "the shot never ended")
	assert_eq(_rig.rotation, rotation_before, "the camera came back to a different angle")
	assert_eq(_rig.lean(), Vector3.ZERO, "the lean was left on the rig")
	assert_eq(_rig.aim_offset(), aim_before, "the aim offset was left on the rig")
	assert_eq(_rig.framing_base(), stop_before, "the player's chosen stop was changed")
	assert_eq(_rig.framing_target(), target_before, "the frame did not come back to its own size")
	assert_eq(_rig.framing_modifiers().size(), 0, "the shot left a modifier on the framing stack")


## The widen is a MODIFIER on the stop he chose, not an overwrite -- so a player
## who set the widest framing gets the widest framing back, not the default.
func test_the_widen_is_a_modifier_on_his_stop_and_not_an_overwrite() -> void:
	_rig.set_framing_index(2)
	var his := _rig.framing_base()
	assert_almost_eq(his, 17.0, 0.0001, "the third stop is not the widest one")
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	_run(_shot.shot_seconds_min * (_shot.dolly_in_fraction + _shot.hold_fraction * 0.5))
	assert_true(
		_rig.framing_target() > his,
		"the camera did not widen at all: %.3f against a base of %.3f" % [_rig.framing_target(), his]
	)
	assert_eq(_rig.framing_base(), his, "the shot wrote his stop instead of stacking on it")
	_run_to_the_end()
	assert_eq(_rig.framing_base(), his, "his stop did not survive the shot")
	assert_eq(_rig.framing_target(), his, "the frame did not return to his stop")


## A rig pulled out from under a running shot must not be left at the shoulder.
## Nothing else in the game knows how to put the camera back.
func test_a_shot_torn_down_mid_move_puts_the_camera_back_first() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.6)
	assert_true(_rig.is_leaning(), "the camera never moved")
	_shot.detach()
	assert_eq(_rig.lean(), Vector3.ZERO, "detaching left the camera turned")
	assert_eq(_rig.rotation, _rig.base_rotation(), "detaching left the camera off its own angle")
	assert_eq(_rig.framing_modifiers().size(), 0, "detaching left a modifier on the framing stack")


# --- do not lose the man ------------------------------------------------------------


## THE CASE MOST PLAYERS WILL ACTUALLY BE IN: he walks straight through the
## trigger at a walk and never stops. If the camera goes off to watch the birds
## he is off-frame and walking into things he cannot see -- a good shot and a bad
## game.
##
## Checked on EVERY frame, not at the ends: the failure is a middle-of-the-move
## one, where the aim has slid furthest and the frame has not widened enough to
## carry him.
func test_walking_straight_through_never_loses_him() -> void:
	_man.position = Vector3(-20.0, 0.0, 4.0)
	var fired := false
	var worst := Vector2.ZERO
	var lost := 0
	var walked := 0.0
	while walked < 34.0:
		# 1.5 m/s, straight through, no pause anywhere.
		_man.position += Vector3(1.5, 0.0, 0.0) * FRAME
		walked += 1.5 * FRAME
		_tick()
		if not _shot.is_running():
			continue
		fired = true
		var him := _shot.frame_position(_man.position + Vector3(0.0, 1.7, 0.0))
		if absf(him.y) > absf(worst.y):
			worst = him
		# HIM on every frame. The take-off AREA cannot be in every frame and is not
		# meant to be: the shot opens on the ordinary isometric framing, which does
		# not contain a wire eight metres up -- that is what the move is FOR. The
		# area is asserted at the hold, in
		# `test_the_frame_widens_rather_than_pushing_in`.
		if not _shot.frames_him():
			lost += 1
	assert_true(fired, "walking straight through the trigger never fired the shot")
	assert_eq(
		lost, 0,
		"the frame lost him on %d frames; his worst position was (%.2f, %.2f) of frame height" % [
			lost, worst.x, worst.y]
	)
	assert_true(
		absf(worst.y) < 0.45,
		"he got to %.2f of frame height -- that is the very edge of the picture" % worst.y
	)


## ...and the same thing said the other way: the move WIDENS. A push-in cannot
## hold him and a flock ten metres off at once, and the arithmetic is in the
## header rather than in anybody's judgement.
func test_the_frame_widens_rather_than_pushing_in() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	var base := _rig.framing_base()
	_run(_shot.shot_seconds_min * (_shot.dolly_in_fraction + _shot.hold_fraction * 0.5))
	assert_true(
		_rig.framing_target() > base,
		"the frame went from %.2f m to %.2f m -- it pushed in, and he will not fit" % [
			base, _rig.framing_target()]
	)
	assert_true(
		_shot.frames_both(),
		"the frame at the hold does not hold both him and the birds"
	)


# --- rare ---------------------------------------------------------------------------


func test_a_second_flock_inside_the_cooldown_gets_no_shot() -> void:
	_man.position = Vector3(2.0, 0.0, 4.0)
	_run(0.1)
	assert_true(_shot.is_running(), "the first shot did not fire")
	_run_to_the_end()
	assert_true(_shot.cooldown_left() > 0.0, "the shot ended with no cooldown at all")
	assert_false(_shot.is_running(), "the shot is still running")
	_flock.land_now()
	_run(0.5)
	assert_false(_shot.is_running(), "a second shot fired inside the cooldown")
	_shot.advance(_shot.cooldown_seconds + 1.0)
	_run(0.1)
	assert_true(_shot.is_running(), "the cooldown never expired")


func test_a_shot_will_not_start_over_a_camera_that_is_already_leaning() -> void:
	_rig.set_lean(Vector3(0.2, 0.0, 0.0))
	assert_false(_shot.begin_now(), "a shot started over an existing lean")
	_rig.set_lean(Vector3.ZERO)


# --- 每一次都不一样 -------------------------------------------------------------------


## THE CLAIM, AS A SPREAD. Same starting conditions, different seeds; the axes
## this file owns have to land in visibly different places. Asserted as a range
## rather than against a recorded run: a snapshot test passes for a system that
## varies by a millimetre.
func test_no_two_shots_are_framed_the_same() -> void:
	var lengths: Array = []
	var tilts: Array = []
	var widens: Array = []
	var shares: Array = []
	for seed in [3, 41, 4711, 20260812, 31337, 9001]:
		_shot.random_seed = seed
		_shot.attach()
		_shot.advance(_shot.cooldown_seconds + 1.0)
		_flock.land_now()
		assert_true(_shot.begin_now(), "seed %d refused to start" % seed)
		# AT THE MIDDLE OF ITS OWN HOLD, not at a fixed number of seconds. Sampled
		# at a fixed time first, and that reads the ease as well as the amount -- a
		# longer shot is less far through its dolly at the same instant, which pulls
		# its measurement back toward the un-moved framing and hides most of the
		# spread this test exists to find.
		var hold_at: float = _shot.dolly_in_fraction + _shot.hold_fraction * 0.5
		var ran := 0.0
		while _shot.is_running() and _shot.progress() < hold_at and ran < 10.0:
			_shot.advance(FRAME)
			_flock.advance(FRAME)
			ran += FRAME
		tilts.append(_rig.lean().x)
		widens.append(_rig.framing_target())
		shares.append(_shot.looking_at().y)
		while _shot.is_running() and ran < 12.0:
			_shot.advance(FRAME)
			_flock.advance(FRAME)
			ran += FRAME
		lengths.append(ran)
	assert_true(
		rad_to_deg(_spread(tilts)) > 4.0,
		"six shots pitched within %.2f degrees of each other" % rad_to_deg(_spread(tilts))
	)
	assert_true(
		_spread(widens) > 0.6,
		"six shots widened to within %.3f m of the same frame: %s" % [_spread(widens), str(widens)]
	)
	assert_true(
		_spread(lengths) > 0.3,
		"six shots ran within %.3f s of the same length" % _spread(lengths)
	)
	assert_true(
		_spread(shares) > 0.3,
		"six shots aimed within %.3f m of the same height: %s" % [_spread(shares), str(shares)]
	)


func _spread(values: Array) -> float:
	var low := 1e9
	var high := -1e9
	for value in values:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	return high - low
