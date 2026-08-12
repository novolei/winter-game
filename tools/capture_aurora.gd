extends Node

## 极光 HARNESS. Two shots, because the feature is two halves:
##
##   THE GROUND CAST, at the ORDINARY GAME FRAMING with no camera move at all --
##     the fixed orthographic 45-degree rig, exactly as shipped. This is the
##     deliverable: the snow going teal is what the player notices, and the
##     numbers printed beside each frame are what says whether it did.
##
##   THE CURTAIN, with `--sky`, on a DEBUG PERSPECTIVE CAMERA. It has to be a
##     debug camera and it has to be perspective, and neither is a shortcut:
##
##       * the game's camera never looks up, and the lean that will one day let
##         it is another agent's work under the Art Bible rule 1 exception;
##       * under a PARALLEL projection every view ray is the same direction, so
##         a sky shader can only ever produce ONE FLAT COLOUR however far the
##         camera is tipped. The rule 1 ruling already says this
##         (正交投影下向上仰视没有透视收敛) and permits blending to perspective.
##
##     So this stands up its own camera beside the rig, touches nothing, and
##     tears it down. It is a measuring instrument, not a feature.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1280x800 \
##       res://tools/capture_aurora.tscn -- \
##       --out D:/somewhere/aurora --frames 8 --every 90
##
## Arguments:
##   --out <prefix>     writes <prefix>-00.png, -01.png, ...   (required)
##   --frames N         how many PNGs (default 8)
##   --every N          frames between shots (default 90)
##   --settle N         frames to run before the aurora begins (default 30)
##   --preset <id>      the night the aurora hangs in (default deep_night)
##   --aurora <id>      which aurora (default boreal_curtain)
##   --rise <seconds>   force the rise, so a whole arc fits in a short sequence
##   --hold <seconds>   force the hold
##   --sky              take the shots from a debug perspective camera aimed at
##                      the curtain instead of from the game rig
##   --elevation <deg>  override where the debug camera aims (default: the middle
##                      of the curtain, as AuroraSystem publishes it)
##   --fov <deg>        the debug camera's field of view (default 62)
##   --stand x,z        where to put the player (default: wherever he starts)
##   --seed N           the aurora system's RNG seed (default 20260812)
##   --cast <0..1>      override the ground cast strength, for a tuning sweep
##   --off              run the same sequence with NO aurora, for the before shot

var _out := ""
var _frames := 8
var _every := 90
var _settle := 30
var _preset := "deep_night"
var _aurora := "boreal_curtain"
var _rise := -1.0
var _hold := -1.0
var _sky := false
var _elevation := -1.0
var _fov := 62.0
var _stand := ""
var _seed := 20260812
var _cast := -1.0
var _off := false

var _shot := 0
var _frame := 0
var _done := false
var _begun := false
var _debug_camera: Camera3D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_frames = int(_arg(args, "--frames", "8"))
	_every = maxi(1, int(_arg(args, "--every", "90")))
	_settle = int(_arg(args, "--settle", "30"))
	_preset = _arg(args, "--preset", "deep_night")
	_aurora = _arg(args, "--aurora", "boreal_curtain")
	_rise = float(_arg(args, "--rise", "-1"))
	_hold = float(_arg(args, "--hold", "-1"))
	_sky = _flag(args, "--sky")
	_elevation = float(_arg(args, "--elevation", "-1"))
	_fov = float(_arg(args, "--fov", "62"))
	_stand = _arg(args, "--stand", "")
	_seed = int(_arg(args, "--seed", "20260812"))
	_cast = float(_arg(args, "--cast", "-1"))
	_off = _flag(args, "--off")
	if _out == "":
		push_error("capture_aurora: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _flag(args: PackedStringArray, name: String) -> bool:
	return args.has(name)


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
	# SHOT 00 IS THE WORLD BEFORE THE AURORA, and it is the whole point of the
	# sequence: the ground cast is a CHANGE, and a single frame of teal snow
	# cannot be read without the frame of blue snow it replaced.
	if not _begun:
		_begin()


func _at_start() -> void:
	if _stand != "":
		var parts := _stand.split(",")
		if parts.size() == 2:
			var body := get_node_or_null("Main/Player") as Node3D
			if body != null:
				body.global_position = Vector3(
					float(parts[0]), body.global_position.y, float(parts[1]))
	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null and _preset != "":
		lighting.apply_preset(StringName(_preset))
	var sky = _service(&"snowfall")
	if sky != null and sky.has_method("settle"):
		sky.settle()
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	# Nothing else may be drawn on top of the thing being watched. A weather that
	# rolled in mid-sequence would end the aurora, which is correct behaviour and
	# a useless capture.
	var weather = _service(&"weather")
	if weather != null:
		weather.enabled = false


func _begin() -> void:
	_begun = true
	if _off:
		return
	var aurora = _service(&"aurora")
	if aurora == null:
		push_error("capture_aurora: no aurora service -- is Main/Aurora in the scene?")
		get_tree().quit()
		return
	aurora.random_seed = _seed
	var definition = aurora.definition(StringName(_aurora))
	if definition == null:
		push_error("capture_aurora: no aurora '%s' in data/aurora" % _aurora)
		get_tree().quit()
		return
	# The DURATIONS only, so a whole arc fits in a sequence a reviewer will
	# actually look at. Every ramp, every ease and every repaint runs as shipped.
	if _rise > 0.0:
		definition.rise_seconds = _rise
	if _hold > 0.0:
		definition.hold_seconds = Vector2(_hold, _hold)
	# The one thing here that is not a duration. The cast's strength is the whole
	# argument about whether the ground reads, and it was chosen by running this
	# sweep rather than by picking a number.
	if _cast >= 0.0:
		definition.ground_cast_strength = _cast
	if not aurora.begin(StringName(_aurora)):
		push_error("capture_aurora: '%s' refused to begin" % _aurora)
		get_tree().quit()
		return
	if _sky:
		_aim_the_debug_camera(aurora)


## The instrument. See the class comment for why it is perspective and why it is
## not the game's camera.
func _aim_the_debug_camera(aurora) -> void:
	var player := get_node_or_null("Main/Player") as Node3D
	var eye := Vector3(0.0, 1.7, 0.0)
	if player != null:
		eye = player.global_position + Vector3(0.0, 1.7, 0.0)
	var direction: Vector3 = aurora.look_direction()
	if _elevation >= 0.0:
		var bearing := deg_to_rad(float(aurora.bearing_degrees()))
		var elevation := deg_to_rad(_elevation)
		var flat := cos(elevation)
		direction = Vector3(sin(bearing) * flat, sin(elevation), -cos(bearing) * flat)
	_debug_camera = Camera3D.new()
	add_child(_debug_camera)
	_debug_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_debug_camera.fov = _fov
	_debug_camera.near = 0.1
	_debug_camera.far = 800.0
	_debug_camera.global_position = eye
	_debug_camera.look_at(eye + direction, Vector3.UP)
	_debug_camera.current = true


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)


## Every number that decides whether the cast reads, printed beside the frame it
## belongs to. The briefing's rule: when a number is supposed to describe the
## picture, check it against the picture.
##
## THE TWO BANDS ARE MEASURED SEPARATELY, and that is the assertion the whole
## design rests on. The overlay multiplies the LIT cel band only, so:
##
##   lit    must go teal -- green and blue rising against red
##   shade  must NOT MOVE AT ALL -- it is a palette colour chosen outright, and
##          Art Bible section 4.1 is that it stays one
##
## Split by luminance rather than by position, because which pixels are in shade
## changes with the sun and the drifts but never with the aurora.
func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, _shot]
	image.save_png(path)
	var line := "capture_aurora: %s" % path
	var aurora = _service(&"aurora")
	if aurora != null:
		line += "  %-7s" % String(aurora.phase())
		line += " env=%.3f" % aurora.strength()
		line += " glow=%.3f" % aurora.glow()
		line += " bearing=%5.1f" % aurora.bearing_degrees()
	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null:
		var tint: Color = lighting.world_light_tint()
		line += "  tint=%.3f/%.3f/%.3f" % [tint.r, tint.g, tint.b]
		line += " overlay=%.3f" % lighting.world_light_overlay_strength()
	var bands := _bands(image)
	line += "  lit=%s" % bands["lit"].to_html(false)
	line += " shade=%s" % bands["shade"].to_html(false)
	# The one number that says "the snow went green": how far the lit band's green
	# and blue have pulled ahead of its red, in 8-bit steps.
	var lit: Color = bands["lit"]
	line += " lit_g-r=%+.0f" % ((lit.g - lit.r) * 255.0)
	line += " lit_b-r=%+.0f" % ((lit.b - lit.r) * 255.0)
	var shade: Color = bands["shade"]
	line += " shade_g-r=%+.0f" % ((shade.g - shade.r) * 255.0)
	print(line)
	_shot += 1


## The mean colour of the frame's brightest fifth and of its darkest fifth --
## the lit cel band and the shade cel band, near enough, at the framings this
## game uses where the frame is nearly all snow.
func _bands(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var samples: Array[Color] = []
	# A grid rather than every pixel: a 1280x800 frame is a million samples and
	# this runs once a shot inside a real frame budget.
	var step := 4
	for y in range(0, height, step):
		for x in range(0, width, step):
			samples.append(image.get_pixel(x, y))
	samples.sort_custom(func(a: Color, b: Color) -> bool:
		return (0.2126 * a.r + 0.7152 * a.g + 0.0722 * a.b) \
			< (0.2126 * b.r + 0.7152 * b.g + 0.0722 * b.b))
	var fifth := maxi(int(samples.size() / 5), 1)
	return {
		"shade": _mean(samples.slice(0, fifth)),
		"lit": _mean(samples.slice(samples.size() - fifth, samples.size())),
	}


func _mean(colours: Array) -> Color:
	if colours.is_empty():
		return Color.BLACK
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for colour in colours:
		r += colour.r
		g += colour.g
		b += colour.b
	var count := float(colours.size())
	return Color(r / count, g / count, b / count)
