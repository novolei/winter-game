extends Node

## Chimney-smoke sequence harness, and the instrument that measures the column
## off the picture rather than off the tuning.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1280x800 \
##       res://tools/capture_smoke.tscn -- \
##       --out D:/somewhere/smoke-gust --find gust --frames 12 --every 30
##
## ---------------------------------------------------------------------------
## HOW THE COLUMN IS MEASURED, AND WHY IT IS A DIFFERENCE
## ---------------------------------------------------------------------------
## The smoke is a pale cool grey over a pale cool sky, so no colour test can
## separate it from what is behind it -- and a threshold that "mostly works"
## would silently measure the roof on half the shots.
##
## So the first thing this harness does is take a REFERENCE frame with the smoke
## hidden, at the settled wind clock, and every later shot is compared against
## it pixel for pixel. What is left is the smoke and nothing else, which makes
## "how wide is the column" and "how far above the flue does it reach" ordinary
## arithmetic instead of a judgement.
##
## For that subtraction to mean anything the rest of the frame has to be still,
## so the snowfall is forced off and the crows are hidden for the run. Both are
## stated in the printed line, because a measurement whose conditions are not on
## the page is a measurement nobody can repeat. Briefing: when a number is
## supposed to describe the picture, check it against the picture.
##
## ---------------------------------------------------------------------------
## WHY THE WIND IS FOUND RATHER THAN FORCED
## ---------------------------------------------------------------------------
## `WindSystem`'s model is a pure function of t, so still air, a light breeze and
## a squall can all be located by arithmetic and then WATCHED at 1x. Forcing a
## strength would prove nothing: this column holds nine seconds of weather, so a
## wind poked to a value shows a picture the wind never actually produced. See
## `--find`.
##
## Arguments:
##   --out <prefix>     writes <prefix>-ref.png, <prefix>-00.png, ...  (required)
##   --find <what>      lull | light | gust -- scans the profile and starts the
##                      wind clock so that moment arrives during the sequence
##   --at <seconds>     an explicit clock instead of --find
##   --frames N         how many PNGs (default 12)
##   --every N          frames between shots (default 30, half a second)
##   --settle N         frames to run before the reference shot (default 660 --
##                      eleven seconds, which is longer than the nine-second puff
##                      life, so the column measured is a FULL one. At 150 the
##                      top third of it had not been emitted yet.)
##   --ortho <metres>   frame height; the rig offers 10.5 / 13.5 / 17.0
##   --preset <id>      force one of the Art Bible looks
##   --profile <path>   a different WindProfile .tres, e.g. the gale
##   --snowfall <0..1>  default 0, so the difference is only the smoke
##   --stand x,z        where to put the player, and therefore the camera. The
##                      farmhouse is at (13, -12); standing near it is what puts
##                      the chimney in frame.
##   --clean 0|1        default 1: hides the walker, the snow and the crows, so
##                      the reference subtraction sees only smoke. Pass 0 for a
##                      picture of the scene as it is actually played.

const SMOKE_SCENE := "res://scenes/effects/chimney_smoke.tscn"

var _out := ""
var _find := ""
var _at := -1.0
var _frames := 12
var _every := 30
var _settle := 660
var _ortho := 0.0
var _preset := ""
var _profile := ""
var _snowfall := 0.0
var _stand := ""
var _clean := true

var _shot := 0
var _frame := 0
var _done := false
var _reference: Image = null
var _smoke = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_find = _arg(args, "--find", "")
	_at = float(_arg(args, "--at", "-1"))
	_frames = int(_arg(args, "--frames", "12"))
	_every = maxi(1, int(_arg(args, "--every", "30")))
	_settle = int(_arg(args, "--settle", "660"))
	_ortho = float(_arg(args, "--ortho", "0"))
	_preset = _arg(args, "--preset", "")
	_profile = _arg(args, "--profile", "")
	_snowfall = float(_arg(args, "--snowfall", "0"))
	_stand = _arg(args, "--stand", "")
	_clean = _arg(args, "--clean", "1") != "0"
	if _out == "":
		push_error("capture_smoke: --out is required")
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
	# Two frames, not one, and not an `await`: hiding the emitter on the frame
	# whose draw call has already been submitted captures a reference that still
	# has smoke in it, and the failure is invisible -- every later shot then
	# measures the DIFFERENCE between two smokes.
	if _frame == _settle:
		if _smoke != null:
			_smoke.visible = false
		return
	if _frame == _settle + 1:
		_take_reference()
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

	# The smoke is added here when the scene does not already carry it, so this
	# harness works whether or not scenes/main.tscn has been edited yet -- that
	# file is contended and an instrument that cannot run until it settles is an
	# instrument that arrives after the decision it was meant to inform.
	_smoke = get_node_or_null("Main/Farmhouse/ChimneySmoke")
	if _smoke == null:
		var house := get_node_or_null("Main/Farmhouse")
		if house != null:
			_smoke = (load(SMOKE_SCENE) as PackedScene).instantiate()
			house.add_child(_smoke)
			print("capture_smoke: main.tscn carries no ChimneySmoke; added one for this run")

	# Everything else in the frame has to hold still, or the difference against
	# the reference is measuring weather instead of smoke.
	#
	# HIDDEN, not merely turned down to a rate of zero. That was the first
	# version and it left flakes in the air -- an emitter at rate 0 still runs,
	# and whatever was already falling went on falling. The diff then reported
	# 27,000 changed pixels and a 34 px "column" in the middle of the frame,
	# which was snow, and it looked exactly like a plausible measurement.
	var sky = _service(&"snowfall")
	if sky != null and sky.has_method("set_snowfall_rate"):
		sky.set_snowfall_rate(_snowfall)
		if sky.has_method("settle"):
			sky.settle()
	# EVERY MOVING THING BUT THE SMOKE, hidden together, because the reference
	# subtraction cannot tell them apart. The walker is on this list and it is the
	# one that is not obvious: he stands still but his idle take never does, so
	# the "densest smoke pixel" in the first run that framed him came back
	# #27344a over #9ec4f2 -- a dark coat over snow, reported with a straight
	# face as the darkest smoke in the picture.
	if _clean:
		for path in [
			"Main/Snowfall", "Main/CameraRig/Camera3D/SnowLens", "Main/Crows",
			"Main/Player", "Main/Wind/Spindrift",
		]:
			var moving := get_node_or_null(path) as Node3D
			if moving != null:
				moving.visible = false

	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null:
			lighting.apply_preset(StringName(_preset))

	var wind = _service(&"wind")
	if wind != null:
		if _profile != "":
			wind.set_profile(load(_profile))
		var clock := _clock_for(wind)
		# Straight onto the clock, then one step of zero so the latches settle at
		# the new time without publishing a storm of events for the minute we
		# skipped. capture_gust.gd's own trick.
		wind.set("_elapsed", clock)
		wind.advance(0.0)

	if _ortho > 0.0:
		_frame_at(_ortho)
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()


## Where to start the wind's clock so that the requested weather happens DURING
## the sequence rather than before it. The settle plus the shots is how long the
## run lasts; the moment is placed a little way into that.
func _clock_for(wind) -> float:
	if _at >= 0.0:
		return _at
	if _find == "":
		return 0.0
	var profile = wind.profile()
	if profile == null:
		return 0.0
	var lead := float(_settle) / 60.0
	var wanted := _scan(profile, _find)
	print("capture_smoke: --find %s put the wind at t=%.2f (strength %.3f)"
		% [_find, wanted, wind.strength_at(profile, wanted)])
	return maxf(wanted - lead, 0.0)


## Four minutes of the model, swept for the moment asked for. Pure function of t,
## so this costs a millisecond and needs no waiting.
func _scan(profile, what: String) -> float:
	var model := load("res://src/systems/wind_system.gd")
	var best := 0.0
	var best_value := -1.0 if what != "lull" else 99.0
	var t := 0.0
	while t < 240.0:
		var strength: float = model.strength_at(profile, t)
		match what:
			"lull":
				if strength < best_value:
					best_value = strength
					best = t
			"gust":
				if strength > best_value:
					best_value = strength
					best = t
			"light":
				# Nearest to the gust threshold from below: a breeze that bends
				# the column without tearing it.
				var distance := absf(strength - profile.gust_threshold * 0.6)
				if best_value < 0.0 or distance < best_value:
					best_value = distance
					best = t
		t += 0.05
	return best


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)


## The rig's own API, not its properties. See capture_frame.gd's note: writing
## `orthographic_size` and `camera.size` directly leaves the rig's framing model
## disagreeing with the camera.
func _frame_at(ortho: float) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.orthographic_size = ortho
	rig.refresh_framing()
	var tween: Tween = rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	rig.apply_framed_size(rig.framing_target())


## The frame with no smoke in it. Everything after this is measured against it.
func _take_reference() -> void:
	_reference = get_viewport().get_texture().get_image()
	_reference.convert(Image.FORMAT_RGBA8)
	_reference.save_png("%s-ref.png" % _out)
	if _smoke != null:
		_smoke.visible = true
	print("capture_smoke: reference (no smoke) %s-ref.png  %dx%d px, window %dx%d"
		% [_out, _reference.get_width(), _reference.get_height(),
			DisplayServer.window_get_size().x, DisplayServer.window_get_size().y])


func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, _shot]
	image.save_png(path)

	var line := "capture_smoke: %s" % path
	var wind = _service(&"wind")
	if wind != null:
		line += "  t=%6.2f  strength=%.3f  heading=%6.1f" % [
			wind.elapsed(), wind.strength(), wind.heading_degrees()
		]
	if _smoke != null:
		line += "  draught=%.2f  lit=%s  flue=%s" % [
			_smoke.column_strength(), _smoke.hearth_is_lit(), _smoke.flue_source()
		]
	line += _measure(image)
	print(line)
	_shot += 1


## What the column actually looks like, in pixels and then in metres.
##
## Every pixel that differs from the reference by more than `floor` is smoke.
## Reported: how many there are, the widest horizontal run of them, and how far
## the topmost one sits above the flue. The width is the number the legibility
## claim rests on -- a wisp too thin to survive the widest framing has failed --
## and it is measured here rather than reasoned about because the alpha, the
## bell texture and the overlap all change it.
func _measure(image: Image) -> String:
	if _reference == null:
		return ""
	image.convert(Image.FORMAT_RGBA8)
	var height := image.get_height()
	var width := image.get_width()
	if _reference.get_height() != height or _reference.get_width() != width:
		return "  (reference is a different size)"

	# Raw bytes rather than get_pixel(): a million Color allocations a shot turns
	# a measurement into a coffee break, and this harness takes three sequences
	# at three framings.
	var now := image.get_data()
	var was := _reference.get_data()

	# ONLY ABOVE THE FLUE, and "above" means a SMALLER row index -- image rows
	# count downward from the top. Getting that backwards scans the half of the
	# frame the smoke can never be in, which is not a null result: below the flue
	# sit the two lit windows and the stove's own light, easing over the first
	# seconds of a run, and the inverted version duly reported the densest smoke
	# in the picture as #303e55 over #ffce75 -- an amber window, changing by
	# itself. Smoke goes up; nothing below the mouth can be smoke.
	var camera := get_viewport().get_camera_3d()
	var flue_row := -1
	var last_row := height
	var per_pixel := 0.0
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		per_pixel = camera.size / float(height)
	if camera != null and _smoke != null:
		var rect := get_viewport().get_visible_rect().size.y
		if rect > 0.0:
			flue_row = int(camera.unproject_position(_smoke.column_position()).y
				* float(height) / rect)
			last_row = clampi(flue_row, 1, height)

	# Just above the 8-bit noise floor, so a sky that dithers by one level is not
	# counted as smoke. 3/255 = 0.0118.
	const FLOOR := 3
	var touched := 0
	var widest := 0
	var top_row := -1
	var widest_row := -1
	var widest_start := -1
	# The RIBBON, measured where it is a ribbon: the band from half a metre to
	# two and a half above the mouth. `widest` on its own answers a different
	# question -- during a gust the broadest run is the dispersed top of the
	# plume, twenty metres downwind, which is not what "is the wisp legible"
	# means.
	var base_widest := 0
	# Screen-vertical metres are the world's compressed by cos(pitch); the rig
	# pitches 45 degrees, so a metre of height is cos(45) of a metre on screen.
	var band := 0.7071 / maxf(per_pixel, 0.0001)
	var band_bottom := last_row - int(0.5 * band)
	var band_top := last_row - int(2.5 * band)
	for y in range(0, last_row):
		var run := 0
		var row_widest := 0
		var row_widest_start := -1
		var base := y * width * 4
		for x in range(width):
			var i := base + x * 4
			var difference := maxi(
				maxi(absi(now[i] - was[i]), absi(now[i + 1] - was[i + 1])),
				absi(now[i + 2] - was[i + 2]))
			if difference > FLOOR:
				touched += 1
				run += 1
				if run > row_widest:
					row_widest = run
					row_widest_start = x - run + 1
				if top_row < 0:
					top_row = y
			else:
				run = 0
		if row_widest > widest:
			widest = row_widest
			widest_row = y
			widest_start = row_widest_start
		if y >= band_top and y <= band_bottom:
			base_widest = maxi(base_widest, row_widest)

	if touched == 0:
		return "  smoke=NONE"

	# The camera's `size` is the frame height in metres and the image is that
	# height in pixels, so this is self-consistent whatever the render target
	# turns out to be -- which is the safe way round briefing trap 10, where
	# three different APIs each answer a different question about "screen size".
	# unproject_position answers in the viewport's own 2D space, which under
	# `canvas_items` stretch is NOT the image's pixel grid, so flue_row above is
	# scaled by the ratio of the two rather than assumed equal.
	var metres_per_pixel := per_pixel

	# WHAT COLOUR IT ACTUALLY CAME OUT, and what was behind it there. The whole
	# colour question for this effect is "does it read as a grey veil or as a
	# white cloud", and that is a comparison against the SNOW it is seen over --
	# which at this camera is most of the frame. Answering it by eye off a
	# screenshot is how the first pass shipped cotton wool.
	#
	# AVERAGED ACROSS THE WIDEST RUN rather than read off the single most-changed
	# pixel. That was the first version and it reported #3b4b63 over #d8edff --
	# a dark edge over bright snow, which is the ANTENNA, one pixel wide, moving
	# by a fraction under the anti-aliasing. The extreme of a distribution is
	# whatever is thinnest and highest-contrast in the frame; the mean over a
	# hundred-pixel run is the smoke.
	var sum_now := [0, 0, 0]
	var sum_was := [0, 0, 0]
	var counted := 0
	if widest_row >= 0 and widest_start >= 0:
		for x in range(widest_start, widest_start + widest):
			var i := widest_row * width * 4 + x * 4
			for c in range(3):
				sum_now[c] += now[i + c]
				sum_was[c] += was[i + c]
			counted += 1

	var out := "  smoke: px=%d ribbon=%dpx" % [touched, base_widest]
	if per_pixel > 0.0:
		out += "(%.2fm,%.1f%%)" % [
			float(base_widest) * per_pixel, float(base_widest) * 100.0 / float(height)]
	out += " widest=%dpx@row%d" % [widest, widest_row]
	if counted > 0:
		out += " tone=#%02x%02x%02x over #%02x%02x%02x" % [
			sum_now[0] / counted, sum_now[1] / counted, sum_now[2] / counted,
			sum_was[0] / counted, sum_was[1] / counted, sum_was[2] / counted,
		]
	if metres_per_pixel > 0.0:
		out += " (%.2f m)" % (float(widest) * metres_per_pixel)
	out += " frameshare=%.1f%%" % (float(widest) * 100.0 / float(height))
	if flue_row >= 0 and top_row >= 0:
		out += " reach=%dpx" % (flue_row - top_row)
		if metres_per_pixel > 0.0:
			out += " (%.2f m above the flue)" % (float(flue_row - top_row) * metres_per_pixel)
	return out
