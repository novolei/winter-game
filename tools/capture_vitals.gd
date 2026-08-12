extends Node

## Screenshot harness for the survival readouts. Runs the real main scene, puts
## the body in a chosen state, pins the camera, renders a frame, writes a PNG.
##
##   Godot_console.exe --path <project> res://tools/capture_vitals.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/shot.png \
##       [--ortho 13.5] [--chill 0.85] [--hide] [--seconds 6]
##
## ---------------------------------------------------------------------------
## `--hide` IS THE WHOLE POINT OF THIS FILE
## ---------------------------------------------------------------------------
## The acceptance question for a permanent readout is not "does it look good", it
## is **does the breath vapour still get the eye first**. That can only be
## answered by two frames of the SAME SHOT, one with the interface and one
## without -- and the briefing's own note says a before-and-after is worthless if
## the two frames are not of the same thing.
##
## So both frames come out of one harness with one flag between them, the camera
## is pinned to a fixed transform rather than following the walker, and the body
## is driven to an exact state rather than left to drift for a while. Nothing
## about the shot changes except whether the readout exists.
##
## ---------------------------------------------------------------------------
## THE BODY IS DRIVEN, NOT WAITED FOR
## ---------------------------------------------------------------------------
## core_temperature drains at 0.000833 per second, so photographing a man in
## trouble by waiting would take twenty minutes of wall clock per frame and every
## frame would be of a different moment. `--chill` pushes a drain modifier and
## advances the model directly, which is the same code path the weather uses and
## reaches an exact value every time.

const DEFAULT_OUTPUT := "user://vitals.png"

## Where the camera stands, in world XZ. The farmstead, chosen so the frame holds
## snow, the farmhouse and its warm window -- everything the readout has to
## compete with.
const LOOK_AT := Vector2(4.0, -8.0)

var _out := DEFAULT_OUTPUT
var _ortho := 0.0
var _chill := 0.0
var _hide := false
var _seconds := 4.0
var _cross := false
var _preset := ""
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_ortho = float(_string_arg(args, "--ortho", "0"))
	_chill = float(_string_arg(args, "--chill", "0"))
	_seconds = float(_string_arg(args, "--seconds", str(_seconds)))
	# The HUD has to be legible on the brightest ground the game makes, not only
	# on the darkest. `whiteout` is a near-white screen and it is exactly the
	# weather in which a player most needs to read his own state.
	_preset = _string_arg(args, "--preset", "")
	for arg in args:
		if arg == "--hide":
			_hide = true
		if arg == "--cross":
			_cross = true

	if _ortho > 0.0:
		_frame_at(_ortho)

	if _hide:
		# Removed outright rather than made invisible. A hidden Control still
		# occupies the layer and still runs; deleting it is the only way to be
		# certain the "without" frame really is without.
		var ui := get_node_or_null("Main/UI")
		if ui != null:
			ui.get_parent().remove_child(ui)
			ui.queue_free()


## Applied THROUGH the rig, the way tools/capture_frame.gd documents at length:
## writing `camera.size` directly produces the right picture and leaves every rig
## accessor reporting the stop it settled at in _ready(), which is confidently
## wrong in exactly the captures an agent takes to judge a framing question.
func _frame_at(ortho: float) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		push_error("capture_vitals: --ortho given but there is no CameraRig")
		return
	rig.orthographic_size = ortho
	rig.refresh_framing()
	var tween: Tween = rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	rig.apply_framed_size(rig.framing_target())


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= _seconds:
		_done = true
		_capture()


func _capture() -> void:
	var survival := get_node_or_null("/root/SurvivalSystem")
	if survival != null and _chill > 0.0:
		# A big multiply on the drain channel, then integrate until the reserve
		# has fallen where it was asked to. The model sub-steps at 0.25 s, so the
		# thresholds on the way down really do fire and the interface really does
		# hear them.
		# 200x on a 0.000833/s base is 0.167 per second, so one 0.25 s sub-step
		# moves the reserve about four hundredths. Coarser than that and the loop
		# below sails past its target -- the first attempt used 4000x and landed
		# every stat on zero, which is a dead man rather than a cold one, and a
		# dead man's model has stopped ticking.
		survival.push_modifier(
			&"core_temperature", &"capture", Modifier.Operation.MULTIPLY, 200.0)
		survival.push_modifier(&"fatigue", &"capture", Modifier.Operation.MULTIPLY, 150.0)
		survival.push_modifier(&"hunger", &"capture", Modifier.Operation.MULTIPLY, 110.0)
		var guard := 0
		while survival.fraction_of(&"core_temperature") > 1.0 - _chill and guard < 20000:
			survival.advance(0.25)
			guard += 1
		survival.remove_source(&"capture")
		print("capture_vitals: core %.2f  fatigue %.2f  hunger %.2f" % [
			survival.fraction_of(&"core_temperature"),
			survival.fraction_of(&"fatigue"),
			survival.fraction_of(&"hunger"),
		])

	# Pinned by SNAPPING TO A WALKER WHO HAS NOT MOVED. There is no input in this
	# harness, so the player stands where he spawned and the rig resolves to the
	# same transform on every run -- which is what makes the with-and-without
	# pair the same shot. The briefing's own note on comparing captures is that
	# a following camera plus anything that changes a walker's speed silently
	# frames different ground; here nothing walks at all.
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()

	var vitals := get_node_or_null("Main/UI/Vitals")
	if vitals != null:
		# Photograph a readout that has finished crystallising rather than one
		# caught part-grown -- the growth is 0.62 s and the shutter is arbitrary.
		vitals.advance(0.016)
		vitals.finish_growth()

	var surfacing := get_node_or_null("Main/UI/ThresholdSurfacing")
	if surfacing != null:
		var bus := get_node_or_null("/root/EventBus")
		if _cross and bus != null:
			# Announced through the bus, so the frame is of the real path rather
			# than of a note built by the harness.
			bus.emit_event(&"survival.threshold_crossed", {
				"stat": &"core_temperature", "threshold": 0.15, "active": true,
				"comparison": "below", "value": 0.14, "targets": [],
			})
			bus.emit_event(&"survival.threshold_crossed", {
				"stat": &"fatigue", "threshold": 0.3, "active": true,
				"comparison": "below", "value": 0.29, "targets": [],
			})
		# Long enough for the last of a staggered batch to be released AND
		# bloomed, short enough that the first has not begun to drift: six notes
		# at 160 ms apart put the last one at 0.80 s, its bloom finishes at
		# 1.00 s, and the first starts leaving at 2.60 s.
		var layer := get_node_or_null("Main/UI")
		for step in range(60):
			surfacing.advance(0.02)
			if layer != null:
				layer.advance(0.02)

	if _preset != "":
		# Snapped at the shutter, not at startup: WorldClock announces day 1 on
		# the first frame and sets the director crossfading to that day's own
		# preset, so a look forced in _ready() is faded away before the shot.
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_vitals: no lighting preset '%s'" % _preset)
		await RenderingServer.frame_post_draw

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_out)
	if error != OK:
		push_error("capture_vitals: could not write %s (error %d)" % [_out, error])
	else:
		print("capture_vitals: wrote ", ProjectSettings.globalize_path(_out))
	get_tree().quit()
