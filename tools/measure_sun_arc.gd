extends Node

## THE SUN'S ARC, PHOTOGRAPHED AND MEASURED FROM THE GAME CAMERA.
##
## Runs the real main scene, pins the camera and the man, stops the snowfall, and
## then steps a case list -- each case a preset and a point in the phase -- saving
## a PNG and a row of numbers for each.
##
##   Godot_console.exe --path <project> res://tools/measure_sun_arc.tscn \
##       --resolution 1280x800 --fixed-fps 60 -- --out D:/dir/prefix \
##       --cases pale_day@0.00,pale_day@0.50,pale_day@1.00
##
## A case is `preset@position[/night]`. `position` is where in the phase the sun
## is, 0 at the arc's morning end and 1 at its evening end.
##
## ---------------------------------------------------------------------------
## WHAT IT REPORTS, AND WHY THOSE FOUR
## ---------------------------------------------------------------------------
## The living-light proposal established, with a measured noise floor, that this
## game's two world channels are unambiguous: NIGHT moves brightness 9.2x more
## than it moves flatness, and THE STORM moves flatness 5.9x more than it moves
## brightness. That separation is why a player can tell "night is coming" from "a
## storm is coming" in a game with no HUD. The arc adds a third axis, so the four
## columns are the three old claims plus the new one:
##
##   mean linear luminance   "the world got darker"        -> TIME's old word
##   p90 - p10               "the world went flat"         -> WEATHER's word
##   shadow rake             "the shadows turned"          -> TIME's new word
##   detail                  mean |Laplacian| of luminance -> legibility
##
## THE RAKE IS MEASURED, NOT DERIVED. The proposal computed it from the director's
## published screen-projection formula. Here it is read off the LIVE camera by
## projecting a ground-plane shadow direction through `unproject_position` --
## which measures the camera that is actually in the scene rather than the one the
## formula assumes. The two are printed side by side so a disagreement is visible.
##
## Angles survive `unproject_position` even though lengths do not: under this
## project's `canvas_items` stretch it returns 2D canvas space (1152x720) while
## the PNG is the window (1280x800), and that is a UNIFORM 1.111x on both axes, so
## a direction is unchanged. Briefing trap 10 is about lengths; this is not one.
##
## ---------------------------------------------------------------------------
## THE GRAIN PATCH
## ---------------------------------------------------------------------------
## The proposal flagged that the arc moves the snow grain more than expected and
## did not explain it. `--patch x0,y0,x1,y1` is the instrument for that: a
## rectangle of bare lit snow, classified against ITS OWN mean luminance so the
## measurement is of the PATTERN and not of the level. Two questions, separately:
##
##   swim %   -- how much of the patch changed which side of its own mean it is
##               on, versus the first case. A grain that swims as the sun turns
##               is a different defect from a shadow that rakes.
##   std      -- the patch's luminance spread. If the grain were being DELETED
##               rather than moved, this is what would fall.
##
## The noise floor for `swim` is a case repeated: put the same case twice at the
## head of the list and read row 2.

var _out := ""
var _cases: PackedStringArray = []
var _stand := "0,0"
var _look := ""
var _settle := 180
var _hold := 90
var _patch := "80,330,480,600"
## Which row the "vs base" columns are measured against. Not always row 0: a case
## list has to run in increasing phase order, so the shipped light (mid-phase) may
## not be the first shot even when it is the thing everything else is compared to.
var _base := 0

## `--bias N` overrides DirectionalLight3D.shadow_normal_bias for the run; -1
## leaves the shipped value alone, which is the default and what every table in
## the sun-arc report was measured at.
##
## IT IS HERE BECAUSE OF A REGISTERED OPEN ITEM: 2.0 is on file as the suspected
## root cause of shadow seams on white surfaces, awaiting evidence. The evidence
## is a pair of frames, and a pair of frames needs a knob -- so the knob is in the
## harness, where turning it is a measurement, rather than in the director, where
## turning it would be a change. **Nothing here writes the value back.**
var _bias := -1.0

var _frame := 0
var _step := -1
var _next_at := 0
var _done := false
var _rows: Array = []
var _grain_masks: Array = []
var _cam := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_cases = _arg(args, "--cases", "pale_day@0.5").split(",")
	_stand = _arg(args, "--stand", _stand)
	_look = _arg(args, "--look", "")
	_settle = int(_arg(args, "--settle", str(_settle)))
	_hold = int(_arg(args, "--hold", str(_hold)))
	_patch = _arg(args, "--patch", _patch)
	_base = int(_arg(args, "--base", "0"))
	_bias = float(_arg(args, "--bias", "-1"))
	if _out == "":
		push_error("measure_sun_arc: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == key:
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
	_pin()
	if _frame < _next_at:
		return
	if _step >= 0:
		_record(_cases[_step])
	_step += 1
	if _step >= _cases.size():
		_done = true
		_report()
		get_tree().quit()
		return
	_set_case(_cases[_step])
	_next_at = _frame + _hold


func _at_start() -> void:
	var parts := _stand.split(",")
	if parts.size() == 2:
		var body := get_node_or_null("Main/Player") as Node3D
		if body != null:
			body.global_position = Vector3(
				float(parts[0]), body.global_position.y, float(parts[1]))
	# Snowfall off: a falling flake is a moving pixel and every column here is a
	# frame statistic.
	var sky = _service(&"snowfall")
	if sky != null and sky.has_method("settle"):
		sky.settle()
	if sky != null and sky.has_method("set_snowfall_rate"):
		sky.set_snowfall_rate(0.0)
	# The bias override, applied once and read back. Read back rather than
	# assumed: this project's most repeated defect is a value that was set and
	# never applied, and the whole worth of a bias pair is that the two frames
	# genuinely differ in the one number they are named after.
	if _bias >= 0.0:
		var sun := get_node_or_null("Main/Lighting/Sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_normal_bias = _bias
			print("shadow_normal_bias set to %.3f, reads back %.3f"
				% [_bias, sun.shadow_normal_bias])
	_next_at = _settle


## GameState starts the clock on the first frame, which announces day 1 and sets
## the director crossfading to the schedule's own preset -- and, now, walking the
## arc. Both have to be re-forced every frame or a case drifts while it waits.
## THE MAN IS RE-PLANTED EVERY FRAME, NOT ONCE.
##
## Planting him at frame 1 was not enough and the first run of this harness shows
## why: over the ~7 s of game time a five-case list takes, he drifted far enough
## that TrackMask laid three metres of new trail, and the trail is the strongest
## line in the frame (Art Bible rule 11). Dawn and dusk came back with the road
## in visibly different places while the camera signature was byte-identical, so
## the harness reported `cam_same=true` on two frames that were not the same shot.
## That is the briefing's own recorded failure, reproduced exactly: same script,
## same seconds, different picture.
func _pin() -> void:
	var parts := _stand.split(",")
	var body := get_node_or_null("Main/Player") as Node3D
	if body != null and parts.size() == 2:
		body.global_position = Vector3(
			float(parts[0]), body.global_position.y, float(parts[1]))
	var rig := get_node_or_null("Main/CameraRig") as Node3D
	if rig != null:
		if rig.has_method("snap_to_target"):
			rig.snap_to_target()
		if _look != "":
			var look := _look.split(",")
			if look.size() == 2:
				rig.global_position = Vector3(float(look[0]), 1.0, float(look[1]))
	# AND THE SNOWFALL, EVERY FRAME. Setting it once at startup is not enough:
	# WeatherSystem owns the rate and pushes its own value whenever an event
	# arrives, so a run long enough to hold seven cases gets its snow back. It
	# came back mid-list on the first separability run and put a thousand bright
	# streaks over two frames -- mean +0.96%, detail +83% -- which is a change in
	# the picture that has nothing to do with the case being photographed.
	var sky = _service(&"snowfall")
	if sky != null and sky.has_method("set_snowfall_rate"):
		sky.set_snowfall_rate(0.0)
	if _step < 0 or _step >= _cases.size():
		return
	_set_case(_cases[_step])


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)


## Forces the preset and scrubs the clock to the wanted point in the phase.
##
## The clock is driven rather than the director: `_arc_position` is private and
## poking it would test the harness rather than the game. WorldClock.advance() is
## public and is the same call `_process` makes, so the sun arrives here exactly
## the way it arrives in a run.
func _set_case(spec: String) -> void:
	var head := spec.split("@")
	var wanted_preset := StringName(head[0])
	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null and lighting.target_preset_id() != wanted_preset:
		lighting.apply_preset(wanted_preset)
	if head.size() < 2:
		return
	var wanted := clampf(float(head[1]), 0.0, 1.0)
	var clock = get_node_or_null("/root/WorldClock")
	if clock == null or not clock.has_method("phase_duration"):
		return
	var duration := float(clock.phase_duration())
	if duration <= 0.0:
		return
	# advance() only runs forwards, and crossing a phase boundary would change
	# the preset underneath the case -- so the case list has to be in increasing
	# order of position. Driving the CLOCK rather than the director's own
	# `_arc_position` is deliberate: the sun then arrives here by exactly the path
	# it takes in a run, and this measures the game rather than the harness.
	#
	# THE MARGIN IS THE WHOLE HOLD, NOT AN EPSILON, AND THAT COST A WRONG NUMBER.
	#
	# It was `duration - now - 0.01` -- a hundredth of a second short of the
	# boundary. But a case is then HELD for `_hold` frames while the clock keeps
	# running, so `@1.00` parked the sun 0.01 s from dusk and the hold walked it
	# straight over. WorldClock started the night, `is_night()` went true, and on
	# the next frame `_pin()` re-ran this function -- which now read the NIGHT's
	# duration, found `1.00 * night_duration` far ahead of `now`, and sprinted the
	# clock through the entire night into day 2.
	#
	# The measured symptom: `pale_day@1.00` reported `pos=0.000 az=69.00` -- the
	# dawn azimuth, on the row that was supposed to photograph dusk. Nothing
	# errored. The frame was a real frame of a real daylight phase at a real
	# azimuth, the camera signature matched, and every other column was correct.
	# It simply was not the case that was asked for, and read as "the arc wraps at
	# the end of the day", which the arc does not do.
	#
	# So the clamp leaves room for the hold to run inside the phase, and the case
	# is reported at wherever it actually landed (`arcPos` is read back off the
	# director, never assumed from the spec).
	var now := float(clock.phase_elapsed())
	var hold_seconds := float(_hold) / 60.0 + 1.0
	var ceiling := maxf(now, duration - hold_seconds)
	var elapsed := minf(wanted * duration, ceiling)
	if elapsed > now:
		clock.advance(elapsed - now)


func _record(spec: String) -> void:
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("%s-%02d-%s.png" % [_out, _step, spec.replace("@", "-at-").replace("/", "-")])
	var stats := _frame_stats(shot)
	var grain := _patch_stats(shot)
	_grain_masks.append(grain["mask"])
	var lighting := get_node_or_null("Main/Lighting")
	var sun := get_node_or_null("Main/Lighting/Sun") as DirectionalLight3D
	var camera := get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	var aimed := rad_to_deg(sun.rotation.y) if sun != null else 0.0
	var elevation := rad_to_deg(-sun.rotation.x) if sun != null else 0.0
	# GUARDED SO THIS RUNS AGAINST A TREE THAT HAS NO ARC, which is the whole
	# point of owning a before/after: a harness that only compiles against the
	# feature cannot measure the frame without it, and "I could not run the
	# control" is how a regression gets attributed to the wrong commit.
	var position := -1.0
	if lighting != null and lighting.has_method("arc_position"):
		position = float(lighting.arc_position())
	var signature := ""
	if camera != null:
		var t := camera.global_transform
		signature = "o=(%.3f,%.3f,%.3f) size=%.3f" % [
			t.origin.x, t.origin.y, t.origin.z, camera.size]
	if _cam == "":
		_cam = signature
	_rows.append({
		"spec": spec,
		"pos": position,
		"az": aimed,
		"el": elevation,
		"rake": _rake_measured(camera, aimed),
		"rake_formula": _rake_derived(aimed),
		"lin": stats["lin"],
		"range": stats["p90"] - stats["p10"],
		"detail": stats["detail"],
		"gstd": grain["std"],
		"gdetail": grain["detail"],
		"cam_same": signature == _cam,
	})
	# THE SHOT'S OWN IDENTITY, printed on every row rather than asserted once.
	# Two frames that are not of the same thing make every column above a lie,
	# and a frame can stop being the same thing because of something nowhere near
	# the camera -- the first run of this harness moved three metres of trail
	# while the camera signature stayed byte-identical.
	var body := get_node_or_null("Main/Player") as Node3D
	var mask = _service(&"track_mask")
	var where := body.global_position if body != null else Vector3.ZERO
	var mask_origin := Vector2.ZERO
	if mask != null and mask.has_method("origin"):
		mask_origin = mask.origin()
	print("case %-20s pos=%.3f az=%6.2f el=%5.2f rake=%5.2f lin=%.5f range=%.4f man=(%.2f,%.2f) mask=(%.2f,%.2f) cam=%s" % [
		spec, position, aimed, elevation, _rake_measured(camera, aimed),
		stats["lin"], stats["p90"] - stats["p10"],
		where.x, where.z, mask_origin.x, mask_origin.y,
		signature if _step == 0 else str(signature == _cam)])


## THE RAKE, OFF THE LIVE CAMERA. A shadow runs along the light's own horizontal
## travel, (-sin a, -cos a); project a step of it on the ground plane and read the
## angle the segment makes with the horizontal in screen space.
func _rake_measured(camera: Camera3D, azimuth_degrees: float) -> float:
	if camera == null:
		return 0.0
	var a := deg_to_rad(azimuth_degrees)
	var foot := Vector3(0.0, 0.0, 0.0)
	var tip := foot + Vector3(-sin(a), 0.0, -cos(a)) * 6.0
	var p0 := camera.unproject_position(foot)
	var p1 := camera.unproject_position(tip)
	var d := p1 - p0
	if is_zero_approx(d.x) and is_zero_approx(d.y):
		return 0.0
	return rad_to_deg(atan2(absf(d.y), absf(d.x)))


## The director's own published solution, for cross-check: with the rig pitched 45
## and yawed -35, screen rake = atan(0.7071 * |cot(a + 35)|).
func _rake_derived(azimuth_degrees: float) -> float:
	var phi := deg_to_rad(azimuth_degrees + 35.0)
	if is_zero_approx(sin(phi)):
		return 0.0
	return rad_to_deg(atan(0.7071 * absf(cos(phi) / sin(phi))))


func _frame_stats(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var stride := 3
	var lin_total := 0.0
	var count := 0
	var samples: Array[float] = []
	for y in range(0, height, stride):
		for x in range(0, width, stride):
			var c := image.get_pixel(x, y)
			lin_total += (0.2126 * _to_linear(c.r) + 0.7152 * _to_linear(c.g)
				+ 0.0722 * _to_linear(c.b))
			samples.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
			count += 1
	samples.sort()
	return {
		"lin": lin_total / maxf(1.0, float(count)),
		"p10": samples[int(samples.size() * 0.10)],
		"p90": samples[int(samples.size() * 0.90)],
		"detail": _detail(image, 0, 0, width, height, 3),
	}


## Mean absolute Laplacian of luminance -- the project's own legibility
## instrument, the one VisionFocus was calibrated with.
func _detail(image: Image, x0: int, y0: int, x1: int, y1: int, stride: int) -> float:
	var total := 0.0
	var count := 0
	for y in range(maxi(y0 + stride, stride), mini(y1, image.get_height() - stride), stride):
		for x in range(maxi(x0 + stride, stride), mini(x1, image.get_width() - stride), stride):
			var here := _luma(image, x, y)
			var acc := 4.0 * here \
				- _luma(image, x - stride, y) - _luma(image, x + stride, y) \
				- _luma(image, x, y - stride) - _luma(image, x, y + stride)
			total += absf(acc)
			count += 1
	return total / maxf(1.0, float(count))


func _luma(image: Image, x: int, y: int) -> float:
	var c := image.get_pixel(x, y)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## The grain patch, classified against its OWN mean so the reading is the pattern
## rather than the level.
func _patch_stats(image: Image) -> Dictionary:
	var parts := _patch.split(",")
	var x0 := int(parts[0])
	var y0 := int(parts[1])
	var x1 := mini(int(parts[2]), image.get_width())
	var y1 := mini(int(parts[3]), image.get_height())
	var values: Array[float] = []
	for y in range(y0, y1):
		for x in range(x0, x1):
			values.append(_luma(image, x, y))
	var mean := 0.0
	for v in values:
		mean += v
	mean /= maxf(1.0, float(values.size()))
	var variance := 0.0
	for v in values:
		variance += (v - mean) * (v - mean)
	variance /= maxf(1.0, float(values.size()))
	var mask := PackedByteArray()
	mask.resize(values.size())
	var low := 0
	for i in range(values.size()):
		if values[i] < mean:
			mask[i] = 1
			low += 1
		else:
			mask[i] = 0
	return {
		"mask": mask,
		"mean": mean,
		"std": sqrt(variance),
		"low": float(low) / maxf(1.0, float(values.size())),
		"detail": _detail(image, x0, y0, x1, y1, 1),
	}


func _to_linear(v: float) -> float:
	if v <= 0.04045:
		return v / 12.92
	return pow((v + 0.055) / 1.055, 2.4)


func _report() -> void:
	print("")
	print("=== THE ARC, FROM THE GAME CAMERA ===")
	print("case                  arcPos    az     el   rake(cam) rake(formula)   meanLin   vs base    p90-p10   vs base   detail    grainStd  grainDetail  grainSwim%")
	if _rows.is_empty():
		return
	var index := clampi(_base, 0, _rows.size() - 1)
	print("base row: %d (%s)" % [index, _rows[index]["spec"]])
	var base: Dictionary = _rows[index]
	var base_mask: PackedByteArray = _grain_masks[index]
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var other: PackedByteArray = _grain_masks[i]
		var moved := 0
		for j in range(base_mask.size()):
			if base_mask[j] != other[j]:
				moved += 1
		print("%-20s  %.3f  %6.2f  %5.2f    %5.2f       %5.2f      %.5f  %+6.2f%%   %.4f  %+6.2f%%   %.5f   %.5f   %.5f     %5.1f%%" % [
			row["spec"], row["pos"], row["az"], row["el"], row["rake"], row["rake_formula"],
			row["lin"], 100.0 * (row["lin"] / base["lin"] - 1.0),
			row["range"], 100.0 * (row["range"] / base["range"] - 1.0),
			row["detail"], row["gstd"], row["gdetail"],
			100.0 * float(moved) / maxf(1.0, float(base_mask.size())),
		])
	print("")
	print("camera identical across every shot: %s" % str(_rows.all(func(r): return r["cam_same"])))
	print("=== end ===")
