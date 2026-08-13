extends Node

## A FRAME STRIP OF ONE ELEMENT'S WHOLE LIFE -- 呵 · 持 · 散, sampled at chosen
## moments of its own envelope, from the game camera, over a chosen ground.
##
##   Godot_console.exe --path <project> res://tools/capture_breath_strip.tscn \
##       --resolution 1920x1080 -- --element prompt|note --out D:/dir \
##       [--preset pale_day] [--night] [--progress 0.35] [--day 3]
##       [--times 0.00,0.08,0.16,...] [--tag day]
##
## ---------------------------------------------------------------------------
## WHY A STRIP AND NOT A SCREENSHOT
## ---------------------------------------------------------------------------
## capture_time_prompt.tscn deliberately opens its shutter during the HOLD,
## because a single frame of an element should be a picture of the element and not
## of its arrival. That is right for judging ink, type and layout, and it is
## exactly wrong for judging motion: the half of this design language that carries
## the poetry is the 散, and a still taken 320 ms in has not reached it.
##
## So this samples the same real element, through the same real layer, at a LIST
## of moments -- dense at the entrance and denser at the exit.
##
## ---------------------------------------------------------------------------
## IT SEEKS BY REBUILDING, NOT BY REWINDING
## ---------------------------------------------------------------------------
## UILayer.advance() only goes forward, and `Breath` is a pure function of time
## but the layer's bookkeeping is not. Rather than add a seek nobody else needs --
## and which would be a second, untested path through the thing under test -- each
## frame of the strip surfaces a FRESH element and advances it once, by the whole
## interval. One advance of 4.2 s and 252 advances of 1/60 s land on the same
## place, because every value in the envelope is computed from the accumulated
## total rather than integrated.
##
## That also means each frame is independent: a strip cannot drift, and one bad
## frame cannot poison the next.

const DEFAULT_TIMES := "0.00,0.05,0.11,0.18,0.26,0.32,1.00,4.00,7.00,8.32,8.50,8.75,9.00,9.25,9.50,9.75,9.92"

var _element := "prompt"
var _out := "user://strip"
var _preset := ""
var _night := false
var _progress := 0.35
var _day := 3
var _tag := "strip"
var _times: Array = []
var _settle := 1.0
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_element = _string_arg(args, "--element", _element)
	_out = _string_arg(args, "--out", _out)
	_preset = _string_arg(args, "--preset", _preset)
	_progress = float(_string_arg(args, "--progress", str(_progress)))
	_day = int(_string_arg(args, "--day", str(_day)))
	_tag = _string_arg(args, "--tag", _tag)
	for arg in args:
		if arg == "--night":
			_night = true
	for piece in _string_arg(args, "--times", DEFAULT_TIMES).split(","):
		var value := piece.strip_edges()
		if value != "":
			_times.append(float(value))


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= _settle:
		_done = true
		_run()


func _run() -> void:
	var layer := get_node_or_null("Main/UI")
	if layer == null:
		push_error("capture_breath_strip: there is no UI layer in the scene")
		get_tree().quit(1)
		return

	# The ground, snapped at the shutter rather than at startup: WorldClock
	# announces day 1 on the first frame and the director crossfades to that day's
	# own preset, so a look forced in _ready() has faded away before the shot.
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_breath_strip: no lighting preset '%s'" % _preset)
			get_tree().quit(1)
			return

	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()

	# THE TREE IS STOPPED, OR EVERY TIMESTAMP ON THE STRIP IS A LIE.
	#
	# UILayer, TimePrompt and ThresholdSurfacing all forward _process() to their
	# own advance(). Two `await frame_post_draw` per strip frame therefore hand the
	# layer two real frame deltas that this tool never asked for, on top of the one
	# it did -- so a frame labelled 0 ms was photographed at about 30, and the
	# offset grows with anything that makes the harness render slower. Caught by
	# reading the first frame of a strip and finding an element that should have
	# been at alpha zero already half drawn.
	#
	# Paused rather than set_process(false) on the three of them by name: pausing
	# also stops WorldClock and SurvivalSystem, and a list of nodes to silence is a
	# list somebody has to remember to extend. Every advance() below is a direct
	# call and is unaffected.
	get_tree().paused = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	var written := 0
	for moment in _times:
		if await _frame(layer, float(moment)):
			written += 1
	print("capture_breath_strip: %s/%s, %d frame(s) into %s" % [
		_element, _tag, written, ProjectSettings.globalize_path(_out)])
	get_tree().quit()


## One frame of the strip: a fresh element, advanced once to `moment`, rendered
## and saved. Returns whether anything was actually on screen.
func _frame(layer, moment: float) -> bool:
	layer.clear()
	var control = _surface(layer)
	if control == null:
		push_error("capture_breath_strip: the %s refused to surface" % _element)
		return false
	# ONE advance, by the whole interval. See the header.
	if moment > 0.0:
		layer.advance(moment)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s_%06.0fms.png" % [_out, _element, _tag, moment * 1000.0]
	if image.save_png(path) != OK:
		push_error("capture_breath_strip: could not write %s" % path)
		return false
	return true


func _surface(layer):
	if _element == "note":
		var surfacing := get_node_or_null("Main/UI/ThresholdSurfacing")
		if surfacing == null:
			return null
		# The real path: publish the event the model publishes, then let the
		# surfacing raise its own note. Nothing here builds a ThresholdNote.
		var bus := get_node_or_null("/root/EventBus")
		if bus == null:
			return null
		bus.emit_event(&"survival.threshold_crossed", {
			"stat": &"frostbite_hands", "threshold": 0.5, "comparison": "below",
			"active": true, "value": 0.48, "targets": [],
		})
		# Past its 160 ms stagger and onto the layer.
		surfacing.advance(0.2)
		for child in layer.get_children():
			if child is ThresholdNote:
				return child
		return null

	var prompt := get_node_or_null("Main/UI/TimePrompt")
	if prompt == null:
		return null
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and _night and not clock.is_night():
		clock.advance(clock.phase_duration() - clock.phase_elapsed() + 0.01)
	if clock != null and _progress >= 0.0:
		var want: float = float(clock.phase_duration()) * clampf(_progress, 0.0, 0.999)
		var move: float = want - float(clock.phase_elapsed())
		if move > 0.0:
			clock.advance(move)
	var arc = prompt.surface_now()
	if arc != null and _day > 0:
		arc.set_phase(arc.is_night(), _day, arc.progress())
	return arc
