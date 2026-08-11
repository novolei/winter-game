extends Node

## Screenshot harness. Runs the real main scene, walks the player along a fixed
## route so there are tracks in the snow, renders a frame, writes a PNG, quits.
##
## Lives in tools/ and is never referenced by the game: the acceptance
## criterion for the first playable slice is an image, and an image needs to be
## producible from a shell without a human at the keyboard.
##
##   Godot_console.exe --path <project> res://tools/capture_frame.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/shot.png [--frames 420]
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

var _elapsed := 0.0
var _output := DEFAULT_OUTPUT
var _capture_at := 37.0
var _settle := 0.9
var _held: Dictionary = {}
var _done := false

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
		# Children are ready before their parent, so CameraRig._ready() has
		# already pushed its own size onto the Camera3D by the time this runs.
		# Setting the export alone is therefore silent and does nothing --
		# which cost a capture. Set both.
		var rig := get_node_or_null("Main/CameraRig")
		if rig != null:
			rig.orthographic_size = ortho
		var camera := get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
		if camera != null:
			camera.size = ortho


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
