extends Node

## Screenshot harness for UI design document section 5.10's time prompt. Runs the
## real main scene, forces a phase, surfaces one prompt, renders a frame, writes
## a PNG.
##
##   Godot_console.exe --path <project> res://tools/capture_time_prompt.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/shot.png \
##       [--night] [--progress 0.35] [--day 4] [--preset pale_day] [--seconds 4]
##
## ---------------------------------------------------------------------------
## IT IS SURFACED, NOT WAITED FOR
## ---------------------------------------------------------------------------
## The prompt appears every four hours of world time, which on day one is every
## 150 seconds of real time, and it lives for about five. Photographing it by
## waiting would mean holding a scene open for two and a half minutes to catch a
## five second window, and every capture would be of a different moment of a
## different phase.
##
## So the harness asks the clock for the state it wants and then calls
## surface_now() -- the same call the cadence makes, through the same layer, with
## the same envelope. What is on screen is the real element and not a mock of it.
##
## ---------------------------------------------------------------------------
## THE SHUTTER OPENS AT THE HOLD, NOT AT THE BLOOM
## ---------------------------------------------------------------------------
## The element spends 320 ms arriving with a scale overshoot on it. A frame taken
## during that is a picture of the arrival rather than of the prompt, and it is
## the kind of capture that gets reviewed as "the icons look slightly too big".
## The layer is driven past the bloom before the frame is read.

const DEFAULT_OUTPUT := "user://time_prompt.png"
const Evidence := preload("res://tools/ui_evidence.gd")

var _out := DEFAULT_OUTPUT
var _night := false
var _progress := -1.0
var _day := 0
var _preset := ""
var _seconds := 2.0
var _verify := false
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_progress = float(_string_arg(args, "--progress", "-1"))
	_day = int(_string_arg(args, "--day", "0"))
	_preset = _string_arg(args, "--preset", "")
	_seconds = float(_string_arg(args, "--seconds", str(_seconds)))
	for arg in args:
		if arg == "--night":
			_night = true
		if arg == "--verify":
			_verify = true


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
	var clock := get_node_or_null("/root/WorldClock")
	var prompt := get_node_or_null("Main/UI/TimePrompt")
	var layer := get_node_or_null("Main/UI")
	if prompt == null or layer == null:
		push_error("capture_time_prompt: there is no TimePrompt in the scene")
		get_tree().quit(1)
		return

	# THE PHASE IS DRIVEN THROUGH THE CLOCK, not written onto the element. The
	# prompt asks the clock at the moment it surfaces (see TimePrompt._surface),
	# so pushing the clock is the only way to get a frame of the real path -- and
	# it is also what proves the asking works.
	if clock != null and _night and not clock.is_night():
		clock.advance(clock.phase_duration() - clock.phase_elapsed() + 0.01)
	if clock != null and _progress >= 0.0:
		var want: float = float(clock.phase_duration()) * clampf(_progress, 0.0, 0.999)
		var move: float = want - float(clock.phase_elapsed())
		if move > 0.0:
			clock.advance(move)

	if _preset != "":
		# Snapped at the shutter, not at startup: WorldClock announces day 1 on the
		# first frame and sets the director crossfading to that day's own preset,
		# so a look forced in _ready() is faded away before the shot.
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_time_prompt: no lighting preset '%s'" % _preset)

	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()

	# Freeze before the plate: world motion must not become false UI ink.
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()

	var arc = prompt.surface_now()
	if arc == null:
		push_error("capture_time_prompt: the prompt refused to surface")
		get_tree().quit(1)
		return
	if _day > 0:
		arc.set_phase(arc.is_night(), _day, arc.progress())

	# Past the bloom and into the hold. See the header.
	var tokens = layer.tokens()
	var steps := int(ceil(tokens.bloom_heavy_seconds / 0.02)) + 4
	for _step in range(steps):
		layer.advance(0.02)

	print("capture_time_prompt: %s day %d, %.0f%% through the phase, reading \"%s\"" % [
		"night" if arc.is_night() else "day", arc.day(), arc.progress() * 100.0, arc.text()])
	print("  element %.0f x %.0f px at %.0f, %.0f in a %.0f x %.0f canvas" % [
		arc.size.x, arc.size.y, arc.position.x, arc.position.y,
		get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y])

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var canvas := get_viewport().get_visible_rect().size
	var whole: Dictionary = Evidence.measure_delivered_ink(
		plate, image, canvas, Rect2(arc.position, arc.size))
	print(Evidence.describe("  whole instrument (graphic)", whole, Evidence.GRAPHIC_CORE_MIN_CONTRAST))
	# The line is the lower 1.5 label-heights of the already-public element bounds.
	# This preserves runtime drawing while measuring the actual delivered glyphs.
	var text_px: float = float(tokens.design_px(prompt.data().label_design_px, canvas))
	var text_rect := Rect2(arc.position + Vector2(0.0, arc.size.y - text_px * 1.5),
		Vector2(arc.size.x, text_px * 1.5))
	var text: Dictionary = Evidence.measure_delivered_ink(plate, image, canvas, text_rect)
	print(Evidence.describe("  time line (body)", text, Evidence.BODY_CORE_MIN_CONTRAST))
	var occupancy: Dictionary = Evidence.boundary_occupancy(Rect2(arc.position, arc.size), canvas)
	var anchored := Evidence.is_anchored_to_edge(
		Rect2(arc.position, arc.size), canvas, tokens.edge_pixels(canvas), &"bottom")
	var occupancy_pass := bool(occupancy.get("inside_frame", false)) \
		and float(occupancy.get("frame_fraction", 1.0)) <= Evidence.TRANSIENT_MAX_FRAME_OCCUPANCY and anchored
	print("  boundary: %.3f%% frame, %s, bottom-anchor %s — %s" % [
		float(occupancy.get("frame_fraction", 1.0)) * 100.0,
		"in frame" if bool(occupancy.get("inside_frame", false)) else "CLIPPED",
		"PASS" if anchored else "FAIL", "PASS" if occupancy_pass else "FAIL"])
	var error := image.save_png(_out)
	if error != OK:
		push_error("capture_time_prompt: could not write %s (error %d)" % [_out, error])
	else:
		print("capture_time_prompt: wrote ", ProjectSettings.globalize_path(_out))
	Engine.time_scale = 1.0
	if _verify and (not bool(whole.get("ok", false))
		or float(whole.get("core_contrast", 0.0)) < Evidence.GRAPHIC_CORE_MIN_CONTRAST
		or not bool(text.get("ok", false))
		or float(text.get("core_contrast", 0.0)) < Evidence.BODY_CORE_MIN_CONTRAST
		or not occupancy_pass):
		push_error("capture_time_prompt: UI evidence gate failed")
		get_tree().quit(1)
		return
	get_tree().quit()
