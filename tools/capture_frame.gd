extends Node

## Screenshot harness. Runs the real main scene, walks the player along a fixed
## route so there are tracks in the snow, renders a frame, writes a PNG, quits.
##
## Lives in tools/ and is never referenced by the game: the acceptance
## criterion for the first playable slice is an image, and an image needs to be
## producible from a shell without a human at the keyboard.
##
##   Godot_console.exe --path <project> res://tools/capture_frame.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/shot.png [--seconds 37]
##
## Optional: `--settle`, `--ortho` (frame height in metres), `--start x,z` (walk
## the route from somewhere else), `--look x,z` (aim the camera at a place
## rather than at the player -- which is what an establishing shot of a
## farmstead the player is standing in the middle of needs), and `--preset <id>`
## (force one of Art Bible section 4.2's six looks).
##
## `--preset` is applied at the shutter and NOT at startup, deliberately. RunBoot
## starts WorldClock on the first frame, which announces day 1 and sets the
## director crossfading to that day's own preset -- so a look forced in _ready()
## would be faded away again before the shot. Snapping it at the last moment is
## also what makes the six comparable: every frame is the preset at full
## strength, never a blend.
##
## Input goes through Input.action_press rather than by poking the controller,
## so the route exercises the same code path a player would.

const DEFAULT_OUTPUT := "user://winter_slice.png"

## [from_seconds, to_seconds, action]. Read as a timeline: whichever rows cover
## the current moment have their action held down.
##
## Roughly a closed loop rather than a straight line. Two reasons: the trail has
## to be visibly a *trail* in the frame and a straight walk just runs off the
## top of it, and the camera follows, so a route with net drift carries the
## blocked-out buildings out of shot before the shutter opens.
##
## Timed in SECONDS, not frames. This machine renders at a few hundred frames a
## second while physics runs at 60, so a frame-numbered route walked a different
## distance every time the rendering cost changed -- 34 m before the terrain
## work and 13 m after it, on the identical route.
const ROUTE := [
	[0.5, 6.0, &"move_forward"],
	[6.5, 12.0, &"move_forward"],
	[6.5, 12.0, &"move_right"],
	[12.5, 18.0, &"move_right"],
	[18.5, 24.0, &"move_back"],
	[18.5, 24.0, &"move_right"],
	[24.5, 30.0, &"move_back"],
	[24.5, 30.0, &"move_left"],
	[30.5, 36.0, &"move_left"],
]

## ---------------------------------------------------------------------------
## `--route curve` -- a walk with no straight lines in it
## ---------------------------------------------------------------------------
## ROUTE above is eight straight legs, and a straight leg cannot photograph the
## one defect that has now been shipped twice in the tracks: a trail assembled
## from segments is a polyline by construction and only shows it where the walk
## changes direction. So there is a second route that never stops turning.
##
## The heading is a slow lap with a fast weave laid over it:
##
##     heading(t) = 2*PI*t/CURVE_LAP + CURVE_SWING * sin(2*PI*t/CURVE_WEAVE)
##
## The lap keeps the walker inside one drift -- at wading pace it closes a
## circle about 5 m across -- while the weave reverses the curvature twice a
## period, so a single frame holds hard left turns, hard right turns and the
## straight moments between them. The tightest radius is about 1.6 m, which is
## far tighter than anything a player would walk and is the point.
##
## Driven through Input.action_press's STRENGTH argument rather than by pressing
## keys, because four digital keys can only express eight headings and every one
## of those is a corner. The controller reads Input.get_vector(), which sums the
## action strengths, so an analogue press is the same code path a gamepad takes.
const CURVE_LAP := 20.0
const CURVE_WEAVE := 5.0
const CURVE_SWING := 0.5
const CURVE_START := 0.5

var _elapsed := 0.0
var _output := DEFAULT_OUTPUT
var _capture_at := 37.0
var _settle := 0.9
var _held: Dictionary = {}
var _done := false
var _start := Vector2.ZERO
var _has_start := false
var _look := Vector2.ZERO
var _has_look := false
var _preset := ""
var _curve := false

# Sampled along the route so the run can state, rather than assume, that the
# snow actually varies and that speed actually responds to it. A shot of a
# uniform blue field looks identical whether the mechanic works or not.
var _shallowest := INF
var _deepest := -INF
var _slowest := INF
var _fastest := -INF
var _distance := 0.0
var _last_spot := Vector3.ZERO
var _sampled := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_output = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_capture_at = float(_string_arg(args, "--seconds", str(_capture_at)))
	# `--settle 0` shoots mid-stride, which is the only way to see the walk
	# cycle in a still. It also quits while a footstep one-shot is still in the
	# AudioServer, so expect the shutdown resource complaint on such a run --
	# see _capture() below.
	_settle = float(_string_arg(args, "--settle", str(_settle)))
	# Lets one run produce the gameplay framing and another a close-up of the
	# same trail, without two scenes or an edit between them.
	var ortho := float(_string_arg(args, "--ortho", "0"))
	if ortho > 0.0:
		_frame_at(ortho)

	# There is deliberately no `--boom`. The 90 m boom looks like it should be a
	# problem for a wide shot -- the directional shadow cascades run out at 75 m
	# and the camera is further away than that -- so a shortened boom was tried
	# and measured against the default at both gameplay and establishing
	# framing. It is worse at both: the shadows lose their edge and the
	# footprints go soft. Godot lays the cascades out over the orthographic box
	# rather than by distance from the lens, so the boom really is what
	# CameraRig says it is, a device for keeping geometry off the near plane,
	# and nothing about the picture depends on it. Recorded here because the
	# hypothesis is an obvious one to have twice.

	# `--look x,z` frames the shot on a place instead of on the player. The rig
	# normally follows the player, which is right for gameplay and wrong for an
	# establishing shot of a farmstead the player is standing in the middle of.
	var look := _string_arg(args, "--look", "")
	if look != "":
		var look_parts := look.split(",")
		if look_parts.size() == 2:
			_look = Vector2(float(look_parts[0]), float(look_parts[1]))
			_has_look = true

	# `--preset <id>` forces one of the six. Recorded here, applied at the
	# shutter -- see the header.
	_preset = _string_arg(args, "--preset", "")

	# `--route curve` swaps the eight straight legs for a walk that never stops
	# turning. See the CURVE_ constants for what it is for.
	_curve = _string_arg(args, "--route", "loop") == "curve"

	# `--start x,z` walks the same route from somewhere else. The camera frames
	# 17 m by 15 m of ground, so anything more than a short walk from the origin
	# -- the farmhouse, for one -- cannot be photographed from the spawn point at
	# game framing, and moving the harness is honest where widening the frame or
	# moving the spawn would not be. The route, the speed and the snow are
	# untouched.
	var start := _string_arg(args, "--start", "")
	if start != "":
		var parts := start.split(",")
		if parts.size() == 2:
			_start = Vector2(float(parts[0]), float(parts[1]))
			_has_start = true
	if _has_start:
		# Children are ready before their parent, so Main and everything under it
		# has already run _ready() by the time this does. The player has not had a
		# physics frame yet, so it still lands on the snow rather than easing down
		# to it -- see PlayerController._grounded.
		var body := get_node_or_null("Main/Player") as Node3D
		if body != null:
			body.global_position = Vector3(_start.x, body.global_position.y, _start.y)


## `--ortho`, applied THROUGH THE RIG rather than around it.
##
## The old version wrote `rig.orthographic_size` and `camera.size` directly. It
## produced the right picture and left the rig lying: `framing_base()`,
## `framing_target()` and `framed_size()` all went on reporting the stop the rig
## had settled at in _ready(), while the camera drew something else. Nothing
## errors, nothing warns, and the numbers are confidently wrong -- in exactly the
## captures an agent takes to judge a framing question. It has already been
## budgeted for once: the snowfall reads `camera.size` rather than the rig partly
## because of this.
##
## So the base is set and refresh_framing() is asked to move the camera to meet
## it, which is the rig's own documented path and keeps every accessor truthful.
## The tween is then killed and the target applied outright, because a capture is
## not a zoom: `refresh_framing()` eases over ~0.22 s, which is shorter than any
## real capture's settle but not shorter than `--seconds 0 --settle 0`, and a
## harness whose framing depends on how long the walk was is a harness that will
## eventually take a wrong picture. All three calls are public rig API.
func _frame_at(ortho: float) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		push_error("capture_frame: --ortho given but there is no CameraRig")
		return
	rig.orthographic_size = ortho
	rig.refresh_framing()
	var tween: Tween = rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	rig.apply_framed_size(rig.framing_target())
	print("capture_frame: framed at %.2f m (rig reports %.2f)" % [ortho, rig.framed_size()])


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_drive()
	_sample()
	if _elapsed >= _capture_at:
		_done = true
		_release_all()
		_capture()


func _drive() -> void:
	if _curve:
		_drive_curve()
		return
	var wanted: Dictionary = {}
	for row in ROUTE:
		if _elapsed >= float(row[0]) and _elapsed <= float(row[1]):
			wanted[row[2]] = true
	for action in wanted:
		if not _held.has(action):
			Input.action_press(action)
			_held[action] = true
	for action in _held.keys():
		if not wanted.has(action):
			Input.action_release(action)
			_held.erase(action)


## The analogue walk. `_held` is still the record of what is down, so
## _release_all() at the shutter works for both routes.
func _drive_curve() -> void:
	if _elapsed < CURVE_START:
		return
	var t := _elapsed - CURVE_START
	var heading := TAU * t / CURVE_LAP + CURVE_SWING * sin(TAU * t / CURVE_WEAVE)
	# Unit length, so get_vector() returns a full-strength direction: the walker
	# is always at his top speed and only the heading changes.
	var wanted := Vector2(sin(heading), cos(heading))
	_axis(&"move_right", &"move_left", wanted.x)
	# move_forward is -Y in the controller's Input.get_vector() call, so "up the
	# screen" is the negative of this axis.
	_axis(&"move_back", &"move_forward", wanted.y)


func _axis(positive: StringName, negative: StringName, amount: float) -> void:
	var pressed := positive if amount >= 0.0 else negative
	var released := negative if amount >= 0.0 else positive
	if _held.has(released):
		Input.action_release(released)
		_held.erase(released)
	# Re-pressed every frame rather than only on the edge: action_press carries
	# the strength, and the strength is the whole of this route.
	Input.action_press(pressed, absf(amount))
	_held[pressed] = true


func _sample() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	var player := registry.get_service(&"player") as CharacterBody3D
	var snow := registry.get_service(&"snow_field") as Node
	if player == null or snow == null:
		return
	var depth: float = snow.depth_at(player.global_position)
	_shallowest = minf(_shallowest, depth)
	_deepest = maxf(_deepest, depth)
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if speed > 0.05:
		_slowest = minf(_slowest, speed)
		_fastest = maxf(_fastest, speed)
	if _sampled:
		_distance += Vector2(
			player.global_position.x - _last_spot.x,
			player.global_position.z - _last_spot.z
		).length()
	_last_spot = player.global_position
	_sampled = true


func _release_all() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()


func _capture() -> void:
	# Let the walk settle before the shutter. Two reasons, one cosmetic and one
	# not: the player coasts to a stop so the frame is not caught mid-stride,
	# and any footstep one-shot (0.52-0.63 s) finishes. Quitting while one is
	# still playing leaves the AudioServer holding its playback and both WAVs
	# with it -- "ERROR: 2 resources still in use at exit". Stopping the player
	# in _exit_tree() is not enough, because the release only lands on the next
	# audio mix and quit() does not wait for one.
	if _settle > 0.0:
		await get_tree().create_timer(_settle).timeout

	# The rig lags the player by design; without this the shot is framed on
	# where the player was half a second ago.
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	if rig != null and _has_look:
		# After the snap, so it wins. The rig only ever translates -- the frame
		# is the same frame, aimed somewhere else.
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)
	# The look, snapped rather than faded, after the rig has settled and before
	# the shutter. apply_preset() abandons whatever crossfade the clock started.
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_frame: no lighting preset '%s'" % _preset)
		else:
			print("capture_frame: lit with %s" % _preset)
		# One frame for the Environment change to reach the compositor before the
		# frame that gets saved.
		await RenderingServer.frame_post_draw

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output)
	if error != OK:
		push_error("capture_frame: could not write %s (error %d)" % [_output, error])
	else:
		print("capture_frame: wrote ", ProjectSettings.globalize_path(_output))
	print("capture_frame: %.0f s, walked %.1f m; snow depth %.2f..%.2f m; speed %.2f..%.2f m/s" % [
		_elapsed, _distance, _shallowest, _deepest, _slowest, _fastest,
	])
	get_tree().quit()
