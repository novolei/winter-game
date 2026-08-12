class_name CameraRig
extends Node3D

## The fixed three-quarter view. Set once in _ready() and never touched again;
## follow is position only, so nothing the player does can rotate the frame.
##
## Orthographic, not perspective. The deciding evidence is in the reference
## in-game frame: two characters standing at clearly different depths are drawn
## at almost identical heights. Perspective cannot do that at any playable
## distance -- only a parallel projection can -- and it is what gives the image
## its flat diorama read. This overrides the Art Bible's "slight perspective"
## in rule 1, which was written from the establishing shot in level.jpg.
##
## `size` is the *vertical* world extent of the frame (keep_aspect defaults to
## KEEP_HEIGHT). Under a pitched camera a standing figure of height h projects
## to h * cos(pitch), so the figure's share of frame height is
##
##     h * cos(pitch) / size
##
## and that is the number the reference pins down: 125 px of a 1101 px frame,
## about 11%. Everything else about the framing follows from it.

## A vertical wall projects at cos(pitch) of its height while the ground
## compresses by sin(pitch), so the ratio between them is 1/tan(pitch): at 57
## degrees a wall reads at 0.65 of its ground footprint and every building
## collapses into its own roof. At 45 it reads at exactly 1.0 -- a box looks
## like a box, a trunk reads as a long vertical line, and a standing figure
## reads as a figure instead of a shadow with a hat.
@export var pitch_degrees := 45.0
@export var yaw_degrees := -35.0

## Vertical world extent of the frame, in metres, and under a parallel
## projection the *only* control over apparent size -- boom_length moves the
## camera without changing the picture at all, and exists solely to keep
## geometry in front of the near plane.
##
## Set by measurement, not by arithmetic: the predicted value put the figure at
## 9.8% of frame height rather than 11%, because a capsule's silhouette under a
## pitched camera is wider than h * cos(pitch). 10.5 measures at 11.4%, against
## the reference's 125 px in 1101.
##
## THIS IS NOW THE BASE OF A MODIFIER STACK, not the number the camera is given.
## It holds the stop the PLAYER chose; framing_target() is what that resolves to
## once anything else has had its say, and framed_size() is where the frame
## actually is while it eases between the two. Writing to it directly still
## works -- tools/capture_frame.gd's `--ortho` does -- but call refresh_framing()
## afterwards if the camera should move to meet it.
@export var orthographic_size := 10.5
@export var boom_length := 90.0

## Kept for the perspective fallback, unused while orthographic.
@export var field_of_view := 22.0
@export var use_orthographic := true

## Metres per second the rig closes on the target. Low enough that the frame
## drifts rather than snaps, high enough that a running player does not outrun
## the middle of the shot.
@export var follow_speed := 4.5

## Where in the frame the player sits. Pushed slightly forward of centre so
## there is room ahead and the trail behind stays in shot.
@export var target_height := 1.0

## ---------------------------------------------------------------------------
## The three framings, and why the player's choice is a BASE and not a value
## ---------------------------------------------------------------------------
## Shift + wheel steps through these and wraps at both ends. They are not three
## sizes, they are three screen SHARES -- how much of the frame's height a
## standing figure fills, h * cos(pitch) / size, which is the quantity the
## reference frame pins down and the only one the eye reads:
##
##     10.5  11.4%  breath vapour, the scarf, the interior light pool
##     13.5   8.9%  travel -- the furrow and the print chain read as a TRAIL
##     17.0   7.1%  landscape -- aerial perspective, and the wires crossing it
##
## The floor is set by the breath staying legible and the ceiling by a charging
## bear needing readable body language in Wave 4.
##
## THE STOP IS THE BASE OF A MODIFIER STACK. Later waves want the frame to pull
## in when the player steps inside a building and push out during a whiteout,
## and there are exactly two ways to build that: stack on top of what the player
## chose, or overwrite it. The second works perfectly the day it ships and
## throws his setting away the first time anything registers -- silently,
## because a camera at the wrong stop just looks like a camera at a stop. So the
## seam is built now, with nothing registered, because doing it later is a
## refactor and doing it now is free.
@export var framing_stops: Array[float] = [10.5, 13.5, 17.0]

## Named actions rather than a raw InputEventMouseButton read, so the binding is
## rebindable and lives in project.godot. Unlike PlayerController's four
## movement keys these are NOT registered at runtime as a fallback: the project
## file is their only home, and tests/unit/test_camera_framing.gd asserts it, so
## losing them is a failing test rather than a control that quietly stopped
## working.
const FRAMING_TIGHTER := &"camera_framing_tighter"
const FRAMING_WIDER := &"camera_framing_wider"

## How long one notch takes. Quick: this is a UI response to an input, not a
## cinematic, so it should land softly rather than glide. Eased OUT, so it
## leaves immediately and settles at the end.
@export var framing_notch_seconds := 0.22

## The wrap gets its own, shorter time, and the reasoning is worth keeping.
##
## Widest to tightest is a 1.62x change against a notch's 1.29x. Given the same
## seconds it already travels at twice the perceived rate; given the same RATE
## it would take twice as long, and a half-second swoop across two stops reads
## as the camera having lost its place rather than as a feature. Shorter than a
## notch says the true thing about it: the wrap is not a zoom, it is a return to
## the start of the list, and 17.0 and 10.5 are adjacent in the list only. Six
## frames at 60 Hz -- fast enough to read as a jump, slow enough not to be a cut.
@export var framing_wrap_seconds := 0.12

var _camera: Camera3D
var _target: Node3D

## Everything with an opinion about the frame, folded onto the player's stop.
## Empty today, and the point is that it does not have to stay that way.
var _framing := ModifierStack.new()

## Which stop the player is on. The base is framing_stops[_framing_index],
## mirrored into orthographic_size so the export stays the readable one.
var _framing_index := 0

## Where the frame actually is, mid-ease. NAN until something applies one, so an
## un-readied rig reports what it would settle at rather than a stale number.
var _framed_size := NAN

var _framing_tween: Tween = null

## ---------------------------------------------------------------------------
## The lean, and why it is an OFFSET rather than a value
## ---------------------------------------------------------------------------
## Art Bible rule 1 says the camera never rotates, and its one approved exception
## -- the crow startle close-up -- is granted on five conditions, of which the
## fourth is that the shot must return to "逐位相同" framing: bit for bit where it
## started, with the player unable to detect a shift.
##
## That condition is unsatisfiable for anything that WRITES the pitch and yaw,
## because writing them means remembering them, and a remembered float that has
## been through an ease is not the float it started as. So the shot does not
## write the rotation at all. It writes an offset, `rotation` is `base + offset`
## every time either changes, and the offset returning to exactly zero returns
## the rotation to exactly `base_rotation()` -- which is recomputed from the two
## exports rather than restored from a snapshot, so there is nothing to get
## stale.
##
## Same shape as `_framing`, one level simpler: the frame's SIZE has a full
## ModifierStack because several systems will want a say in it; its ANGLE has one
## approved caller in the whole game and rule 1 says it should stay that way.
var _lean := Vector3.ZERO

## Where the frame is aimed, over and above the player's own head.
##
## The look-up needs this and the rotation cannot supply it. Pitching the rig
## turns the world about the rig's origin, and the rig's origin is the player --
## so a pure rotation leaves him pinned at the centre of the frame with the sky
## swinging around him, and the birds, which are eight metres up a pole, sail off
## the top. Raising the aim point is what puts them in the picture.
##
## This one is a FOLLOW target rather than a written transform: `_process`
## already eases `global_position` toward the player at `follow_speed`, so an
## offset pushed through the same lerp arrives with the same lag as everything
## else and needs no easing of its own. It also means the return is the ordinary
## follow doing its ordinary job, not a special case.
var _aim_offset := Vector3.ZERO


func _ready() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	_apply_lean()
	# Both of these before the camera guard, and neither is optional. Which stop
	# the rig is on and where the frame currently sits are RIG state, not camera
	# state: a rig assembled without a Camera3D still has to carry them, or the
	# first notch has nothing to move away from and lands instantly.
	_framing_index = nearest_framing_index(orthographic_size)
	apply_framed_size(framing_target())
	if _camera == null:
		return
	if use_orthographic:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = field_of_view
	_camera.position = Vector3(0.0, 0.0, boom_length)
	_camera.rotation = Vector3.ZERO
	# Under a parallel projection the near plane is a real clipping plane at a
	# fixed distance rather than something distance hides, so it sits close to
	# the camera and the boom does the work of keeping the world in front of it.
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true


func _resolve() -> void:
	if _target != null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	_target = registry.get_service(&"player") as Node3D


func _process(delta: float) -> void:
	# First, and outside the _target guard: a modifier with a duration has to
	# expire whether or not there is anything to follow.
	_tick_framing(delta)
	_resolve()
	if _target == null:
		return
	var wanted := _target.global_position + Vector3(0.0, target_height, 0.0) + _aim_offset
	# Exponential smoothing, frame-rate independent: the fraction of the gap
	# closed per second is what is fixed, not the fraction closed per frame.
	var blend := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(wanted, blend)


func _exit_tree() -> void:
	# A tween outlives the node it was created on only long enough to notice,
	# and a rig pulled out of the tree mid-ease has no business still moving.
	if _framing_tween != null and _framing_tween.is_valid():
		_framing_tween.kill()
	_framing_tween = null


## Used by the capture harness to skip the follow lag and frame the shot
## immediately.
func snap_to_target() -> void:
	_resolve()
	if _target == null:
		return
	global_position = _target.global_position + Vector3(0.0, target_height, 0.0) + _aim_offset


## ---------------------------------------------------------------------------
## The lean -- rule 1's one approved exception
## ---------------------------------------------------------------------------


## The angle the rig sits at with nothing acting on it, recomputed from the two
## exports rather than remembered. That is what makes the return exact: there is
## no stored value to drift, and `set_lean(Vector3.ZERO)` puts the rig back on
## the identical bits it was on before anything touched it.
func base_rotation() -> Vector3:
	return Vector3(deg_to_rad(-pitch_degrees), deg_to_rad(yaw_degrees), 0.0)


## Radians, added to the base. `x` tilts the camera up (the base pitch is
## negative, so a positive lean brings the view toward the horizon and the sky);
## `y` swings it round. Zero is the shipped framing, exactly.
func set_lean(offset: Vector3) -> void:
	if not (is_finite(offset.x) and is_finite(offset.y) and is_finite(offset.z)):
		return
	_lean = offset
	_apply_lean()


func lean() -> Vector3:
	return _lean


## Metres, added to the follow target. See `_aim_offset`.
func set_aim_offset(offset: Vector3) -> void:
	if not (is_finite(offset.x) and is_finite(offset.y) and is_finite(offset.z)):
		return
	_aim_offset = offset


func aim_offset() -> Vector3:
	return _aim_offset


## Whether anything is currently leaning the frame. For a test, and for a system
## that must not start a second shot over the first.
func is_leaning() -> bool:
	return _lean != Vector3.ZERO or _aim_offset != Vector3.ZERO


func _apply_lean() -> void:
	# The branch is not an optimisation, it is the CONTRACT. Adding a zero vector
	# happens to be exact for finite floats, but writing it as a separate path is
	# what makes "returns to exactly the framing it left" something a reader can
	# check by looking rather than something they have to know about IEEE 754.
	if _lean == Vector3.ZERO:
		rotation = base_rotation()
		return
	rotation = base_rotation() + _lean


## ---------------------------------------------------------------------------
## Framing
## ---------------------------------------------------------------------------
## Handled as an event rather than polled, for the one reason that matters here:
## an event can be left alone. A bare wheel with no modifier matches nothing --
## exact_match compares the whole modifier mask -- so it falls straight through
## to whatever else wants it, and only a notch that was actually taken is
## consumed.
func _unhandled_input(event: InputEvent) -> void:
	if not handle_framing_input(event):
		return
	get_viewport().set_input_as_handled()


## True when this event was a framing notch and was acted on, which is also the
## signal to consume it. Public so the binding can be exercised without a
## viewport, an OS event queue, or a human at a mouse.
func handle_framing_input(event: InputEvent) -> bool:
	if event == null:
		return false
	# The trailing `true` is exact_match, and it is the whole of "do not consume
	# a plain scroll": without it a bare wheel event matches the shifted binding
	# and the camera jumps every time anything scrolls.
	if event.is_action_pressed(FRAMING_TIGHTER, false, true):
		cycle_framing(-1)
		return true
	if event.is_action_pressed(FRAMING_WIDER, false, true):
		cycle_framing(1)
		return true
	return false


func framing_index() -> int:
	return _framing_index


## The stop the player chose. The BASE -- see framing_stops.
func framing_base() -> float:
	return orthographic_size


## What that resolves to once everything else has had its say. The same as the
## base while nothing is registered, which is today.
func framing_target() -> float:
	return _framing.apply(orthographic_size)


## Where the frame actually is, which differs from the target only while it is
## easing between two of them.
func framed_size() -> float:
	return framing_target() if is_nan(_framed_size) else _framed_size


## The stack itself, for a system that wants to read what is currently acting on
## the frame. Add and remove through push_framing_modifier() and
## remove_framing_modifiers() rather than through this -- they re-aim the camera,
## and a modifier pushed straight onto the stack would not take effect until
## something else moved it.
func framing_modifiers() -> ModifierStack:
	return _framing


## The move currently in flight, or null. Exposed so a test can step it.
func framing_tween() -> Tween:
	return _framing_tween


## Whichever stop is closest to `size`. Used at startup so that whatever the
## scene authored decides which stop the first notch moves away from, rather
## than the frame silently snapping to a stop the moment the game begins.
func nearest_framing_index(size: float) -> int:
	var best := 0
	var best_gap := INF
	for index in range(framing_stops.size()):
		var gap := absf(framing_stops[index] - size)
		if gap < best_gap:
			best_gap = gap
			best = index
	return best


## One notch out (positive) or in (negative), wrapping at both ends forever.
func cycle_framing(steps: int) -> void:
	var count := framing_stops.size()
	if count == 0 or steps == 0:
		return
	var raw := _framing_index + steps
	# Wrapped iff the step ran off one end of the list. Recorded rather than
	# inferred from the sizes, because two stops can be far apart without the
	# move being a wrap.
	var wrapped := raw < 0 or raw >= count
	set_framing_index(wrapi(raw, 0, count), wrapped)


func set_framing_index(index: int, wrapped := false) -> void:
	var count := framing_stops.size()
	if count == 0:
		return
	# Pin where the frame is before the base moves under it. Until something has
	# applied a frame, framed_size() falls back to the target -- so reading it
	# after the base changed would report where the frame is GOING, the move
	# would measure as zero, and the notch would snap instead of easing.
	apply_framed_size(framed_size())
	_framing_index = clampi(index, 0, count - 1)
	orthographic_size = framing_stops[_framing_index]
	_retarget(wrapped)


## Move the frame to whatever the stack currently resolves to. Call after
## writing orthographic_size by hand.
func refresh_framing() -> void:
	_retarget(false)


## The same, but NOW and with no tween.
##
## For a modifier whose value is being driven every frame. `_retarget` starts a
## `framing_notch_seconds` ease, which is right for a control answering a mouse
## wheel and wrong for a caller that is already doing its own easing -- a tween
## created per frame never gets past its first step, so the frame crawls behind
## the value and then snaps when the driving stops. Killing the tween is part of
## it: a notch taken mid-shot would otherwise keep pulling the size somewhere
## else underneath.
func settle_framing() -> void:
	if _framing_tween != null and _framing_tween.is_valid():
		_framing_tween.kill()
	_framing_tween = null
	apply_framed_size(framing_target())


func push_framing_modifier(mod: Modifier) -> void:
	if mod == null:
		return
	_framing.add(mod)
	_retarget(false)


func remove_framing_modifiers(source_id: StringName) -> int:
	var removed := _framing.remove_by_source(source_id)
	if removed > 0:
		_retarget(false)
	return removed


## Seconds a move from `from_size` to `to_size` should take. Pure, so the policy
## can be argued with in a test rather than watched for.
func framing_duration(from_size: float, to_size: float, wrapped: bool) -> float:
	if is_equal_approx(from_size, to_size):
		return 0.0
	return framing_wrap_seconds if wrapped else framing_notch_seconds


## The one place the frame is written. Everything else asks for a target and
## lets the tween arrive here a step at a time.
func apply_framed_size(value: float) -> void:
	if not is_finite(value):
		return
	# A zero or negative parallel frame is a degenerate projection rather than a
	# tight one, and nothing upstream should be able to produce one by arithmetic.
	_framed_size = maxf(value, 0.001)
	if _camera != null:
		_camera.size = _framed_size


func _retarget(wrapped: bool) -> void:
	var target := framing_target()
	var from := framed_size()
	if _framing_tween != null and _framing_tween.is_valid():
		_framing_tween.kill()
	_framing_tween = null
	var duration := framing_duration(from, target, wrapped)
	if not is_inside_tree() or duration <= 0.0:
		apply_framed_size(target)
		return
	# From `from`, not from the stop the last notch was heading for: two notches
	# in quick succession have to turn around from where the frame actually is.
	# Killing the old tween above is what makes that the current value rather
	# than a stale one.
	_framing_tween = create_tween()
	# EASE_OUT in both cases -- a control that answers an input has to leave at
	# once. QUINT for the wrap puts nearly all of a much larger move into the
	# first third of an already shorter time, which is what makes it read as a
	# jump back to the start of the list instead of a long swoop across it.
	_framing_tween.set_trans(Tween.TRANS_QUINT if wrapped else Tween.TRANS_CUBIC)
	_framing_tween.set_ease(Tween.EASE_OUT)
	_framing_tween.tween_method(apply_framed_size, from, target, duration)


func _tick_framing(delta: float) -> void:
	var before := _framing.size()
	if before == 0:
		return
	_framing.tick(delta)
	if _framing.size() != before:
		_retarget(false)
