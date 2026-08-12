extends Node

## Gust-sequence harness. Stands the player still in the real main scene, starts
## the wind's clock at a chosen point, and writes one PNG every N frames with the
## strength and heading printed against each shot.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1280x800 \
##       res://tools/capture_gust.tscn -- \
##       --out D:/somewhere/gust --at 30.0 --frames 14 --every 30
##
## ---------------------------------------------------------------------------
## WHY THE PLAYER DOES NOT MOVE
## ---------------------------------------------------------------------------
## The briefing's rule, paid for once already: pin the camera when the capture is
## about the world rather than about the walk. A following camera turns "the wind
## picked up" into "the wind picked up AND we are looking at different ground",
## and the two are then impossible to separate by eye. Standing still pins the
## rig for free, and this sequence is about the sky, the ground and the wires.
##
## ---------------------------------------------------------------------------
## WHY THE WIND CLOCK IS SET RATHER THAN THE WIND FORCED
## ---------------------------------------------------------------------------
## The model is a pure function of t (see `WindSystem.strength_at`), so a squall
## can be found by arithmetic and then WATCHED at real speed instead of waited
## for. Forcing a strength would have been easier and would have proved nothing:
## every particle in this game responds over a second or more, so a wind poked to
## a value shows a picture that the wind never actually produced. `--at` moves the
## clock; from there everything runs at 1x and everything lags the way it will in
## play.
##
## Arguments:
##   --out <prefix>     writes <prefix>-00.png, -01.png, ...   (required)
##   --at <seconds>     where to start the wind's own clock (default 0)
##   --frames N         how many PNGs (default 14)
##   --every N          frames between shots (default 30, i.e. half a second)
##   --settle N         frames to run before the first shot (default 20)
##   --stand x,z        where to put the player (default: wherever he starts)
##   --preset <id>      force one of the Art Bible looks, held for the run
##   --snowfall <0..1>  force how hard it is snowing, held for the run
##   --profile <path>   a different WindProfile .tres, e.g. the gale

var _out := ""
var _at := 0.0
var _frames := 14
var _every := 30
var _settle := 20
var _preset := ""
var _profile := ""
var _snowfall := -1.0
var _stand := ""
var _shot := 0
var _frame := 0
var _done := false
var _wire_rest := Vector3.INF


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_at = float(_arg(args, "--at", "0"))
	_frames = int(_arg(args, "--frames", "14"))
	_every = maxi(1, int(_arg(args, "--every", "30")))
	_settle = int(_arg(args, "--settle", "20"))
	_preset = _arg(args, "--preset", "")
	_profile = _arg(args, "--profile", "")
	_snowfall = float(_arg(args, "--snowfall", "-1"))
	_stand = _arg(args, "--stand", "")
	if _out == "":
		push_error("capture_gust: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		_at_start()
		return
	if _frame < _settle:
		return
	if (_frame - _settle) % _every != 0:
		return
	if _shot >= _frames:
		_done = true
		get_tree().quit()
		return
	_capture()


func _at_start() -> void:
	if _stand != "":
		var parts := _stand.split(",")
		if parts.size() == 2:
			var body := get_node_or_null("Main/Player") as Node3D
			if body != null:
				body.global_position = Vector3(
					float(parts[0]), body.global_position.y, float(parts[1]))
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null:
			lighting.apply_preset(StringName(_preset))
	if _snowfall >= 0.0:
		var sky = _service(&"snowfall")
		if sky != null and sky.has_method("set_snowfall_rate"):
			sky.set_snowfall_rate(_snowfall)
			if sky.has_method("settle"):
				sky.settle()
	var wind = _service(&"wind")
	if wind != null:
		if _profile != "":
			wind.set_profile(load(_profile))
		# Straight onto the clock, then one step of zero so the state and the
		# latches settle at the new time without publishing a storm of events for
		# the minute we skipped.
		wind.set("_elapsed", _at)
		wind.advance(0.0)
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	var wire := get_node_or_null("Main/Farmstead/Wires/WireDrop") as Node3D
	if wire != null:
		_wire_rest = wire.global_position


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)


func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, _shot]
	image.save_png(path)
	var wind = _service(&"wind")
	var line := "capture_gust: %s" % path
	if wind != null:
		line += "  t=%6.2f  strength=%.3f  heading=%6.1f  consumers=%d" % [
			wind.elapsed(), wind.strength(), wind.heading_degrees(), wind.consumer_count()
		]
		var drift := get_node_or_null("Main/Wind/Spindrift")
		if drift != null:
			line += "  spindrift=%.3f/%.3f" % [drift.wind_strength(), drift.amount_ratio]
		# How far the middle wire has swung from where it was strung. Printed
		# because five pixels of coherent motion is exactly the size of cue that
		# is obvious in play and invisible when comparing two stills by eye.
		# The tyre swing, in degrees off vertical. A pendulum's whole value is that
		# it LAGS, and a lag is a relationship between two numbers over time --
		# invisible in any single frame, obvious in a column of them beside the
		# strength that caused it.
		var tyre := get_node_or_null("Main/Farmstead/TreeA/TireSwing") as Node3D
		if tyre != null:
			var swung := Vector2(tyre.rotation.z, tyre.rotation.x).length()
			line += "  tyre=%5.2fdeg" % rad_to_deg(swung)
		var wire := get_node_or_null("Main/Farmstead/Wires/WireDrop") as Node3D
		if wire != null and _wire_rest != Vector3.INF:
			line += "  wire=%+.3f,%+.3f,%+.3f" % [
				wire.global_position.x - _wire_rest.x,
				wire.global_position.y - _wire_rest.y,
				wire.global_position.z - _wire_rest.z,
			]
	print(line)
	_shot += 1
