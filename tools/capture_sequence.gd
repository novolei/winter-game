extends Node

## Frame-sequence harness. Walks the player along a list of waypoints in the
## real main scene and writes one PNG every N frames, with a log line per shot.
##
## `tools/capture_frame.gd` answers "what does the frame look like". This one
## answers "what does the frame DO", which is the only way to judge anything
## about motion: a fade that fires at the wrong moment, or fails to release, or
## snaps rather than eases, is invisible in a still and obvious in eight of
## them side by side.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1280x800 \
##       res://tools/capture_sequence.tscn -- \
##       --out D:/somewhere/walk --start 14.8,-6 --waypoints "14.8,-16" \
##       --frames 16 --every 6
##
## `--fixed-fps` is not optional in spirit. Saving a PNG takes tens of
## milliseconds, and without a fixed delta that cost lands in the NEXT frame's
## `delta` -- so the player lurches forward between shots and the sequence no
## longer samples an even walk. With it the simulated clock is exactly
## `frames / fps` whatever the disk does.
##
## Arguments:
##   --out <prefix>      writes <prefix>-00.png, -01.png, ...   (required)
##   --start x,z         where the player is put before the walk begins
##   --waypoints "x,z;x,z"   walked in order, at the player's own speed,
##                       through Input actions -- the same path a player takes
##   --frames N          how many PNGs
##   --every N           frames between shots
##   --settle N          frames to run before the first shot
##   --open-door         opens the farmhouse door at the start, so a walk can
##                       cross the threshold without an interact keypress
##   --preset <id>       force one of the Art Bible looks, held for the run
##   --arrive <m>        how near a waypoint counts as reached (default 0.45)

const ARRIVE := 0.45

var _out := ""
var _frames := 16
var _every := 6
var _settle := 12
var _arrive := ARRIVE
var _preset := ""
var _open_door := false
var _waypoints: Array[Vector2] = []
var _leg := 0
var _shot := 0
var _frame := 0
var _elapsed := 0.0
var _busy := false
var _done := false
var _held: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_frames = int(_arg(args, "--frames", "16"))
	_every = maxi(1, int(_arg(args, "--every", "6")))
	_settle = int(_arg(args, "--settle", "12"))
	_arrive = float(_arg(args, "--arrive", str(ARRIVE)))
	_preset = _arg(args, "--preset", "")
	_open_door = _arg(args, "--open-door", "") != "" or args.has("--open-door")
	for pair in _arg(args, "--waypoints", "").split(";", false):
		var parts := pair.split(",")
		if parts.size() == 2:
			_waypoints.append(Vector2(float(parts[0]), float(parts[1])))
	var start := _arg(args, "--start", "")
	if start != "":
		var parts := start.split(",")
		if parts.size() == 2:
			var body := get_node_or_null("Main/Player") as Node3D
			if body != null:
				body.global_position = Vector3(
					float(parts[0]), body.global_position.y, float(parts[1]))
	if _out == "":
		push_error("capture_sequence: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	# Counted and driven even on the frames a PNG is being written. Under
	# --fixed-fps the simulated clock advances whatever the disk is doing, so a
	# harness that stopped counting during a save would under-report every
	# elapsed time it printed -- which is how a 0.26 s fade first read as 0.15 s
	# here, and sent me looking for a bug in the tween that was not there.
	_frame += 1
	_elapsed += delta
	if _frame == 1:
		_at_start()
	_drive()
	if _busy:
		return
	if _frame < _settle:
		return
	if (_frame - _settle) % _every != 0:
		return
	if _shot >= _frames:
		_release()
		_done = true
		get_tree().quit()
		return
	_capture()


func _at_start() -> void:
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null:
			lighting.apply_preset(StringName(_preset))
	if _open_door:
		var door := get_node_or_null("Main/Farmhouse/Door")
		if door != null and door.has_method("open"):
			door.open()
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()


## Walk toward the current waypoint by pressing the same actions a player
## presses. Analogue strength, so the heading is exact rather than one of eight.
func _drive() -> void:
	var player := _player()
	if player == null or _leg >= _waypoints.size():
		_release()
		return
	var here := Vector2(player.global_position.x, player.global_position.z)
	var wanted: Vector2 = _waypoints[_leg]
	if here.distance_to(wanted) <= _arrive:
		_leg += 1
		return
	# SCREEN-RELATIVE, not world. PlayerController rotates the input vector by
	# the camera's yaw before it moves anything -- "up the keyboard" means "up
	# the screen" on a camera that never turns -- so a waypoint given in world
	# metres has to be rotated back into the input's own frame first. Driving it
	# raw walks the player 35 degrees off the line every time, which is how the
	# first threshold capture ended up pressed against the east wall instead of
	# in the doorway.
	var toward := (wanted - here).normalized()
	var camera := get_viewport().get_camera_3d()
	var yaw := camera.global_rotation.y if camera != null else 0.0
	var local := toward.rotated(yaw)
	_axis(&"move_right", &"move_left", local.x)
	# move_forward is -Y in the controller's Input.get_vector() call.
	_axis(&"move_back", &"move_forward", local.y)


func _axis(positive: StringName, negative: StringName, amount: float) -> void:
	var pressed := positive if amount >= 0.0 else negative
	var released := negative if amount >= 0.0 else positive
	if _held.has(released):
		Input.action_release(released)
		_held.erase(released)
	Input.action_press(pressed, absf(amount))
	_held[pressed] = true


func _release() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()


func _player() -> Node3D:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(&"player") as Node3D


func _capture() -> void:
	_busy = true
	var index := _shot
	_shot += 1
	print("capture_sequence: %s" % _state(index))
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, index]
	var error := image.save_png(path)
	if error != OK:
		push_error("capture_sequence: could not write %s (error %d)" % [path, error])
	_busy = false


## One line per shot: where the player is, and what every fading unit holds.
## This is the half of the sequence a picture cannot carry -- the numbers say
## whether a fade is eased or linear, and the pictures say whether it looks it.
func _state(index: int) -> String:
	var player := _player()
	var line := "%02d  t=%5.2f" % [index, _elapsed]
	if player != null:
		line += "  at (%6.2f, %6.2f)" % [player.global_position.x, player.global_position.z]
	var fader := get_node_or_null("/root/OccluderFader")
	if fader != null and fader.has_method("report"):
		line += "  " + String(fader.report())
	var reveal := get_node_or_null("Main/Farmhouse/InteriorReveal")
	if reveal != null and reveal.has_method("fade"):
		line += "  reveal=%.2f" % reveal.fade()
	return line
