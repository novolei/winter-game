extends Node

## Photographs one crow startle, end to end, through the real game camera.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1600x1000 \
##       res://tools/capture_startle.tscn -- --out D:/somewhere/startle-a --seed 7
##
## Run three times with three different seeds and NOTHING ELSE CHANGED. That is
## the deliverable: if the three sets look like the same shot three times, the
## variation has failed, and no amount of description fixes it.
##
## ---------------------------------------------------------------------------
## WHAT IS HELD FIXED, AND WHY IT MATTERS THAT IT IS EVERYTHING
## ---------------------------------------------------------------------------
## The briefing's rule for a capture that is evidence: before comparing two
## captures, prove they are the same shot. So the man does not walk himself --
## his controller is switched off and he is driven along a scripted line at a
## scripted pace, from a scripted start, into a scripted flock. The sky preset,
## the framing stop, the resolution, the frame rate and the wire are all fixed.
##
## The ONLY difference between two runs is `--seed`, which feeds the flock and
## the camera shot. Everything the owner sees differ between them is therefore
## the procedural variation and not the weather, the light, or where he happened
## to be standing.
##
## ---------------------------------------------------------------------------
## THE SKY MEASUREMENT, AND THE TWO FROZEN FRAMES IT COSTS
## ---------------------------------------------------------------------------
## The composition argument for this shot is that it inverts the game: dark birds
## on a BRIGHT SKY, against the dark-on-snow everything else is. That is a claim
## about the picture, so it is measured on the picture rather than asserted.
##
## At the peak of the lean the world is hidden and the same frame re-rendered:
## every pixel of THAT frame is sky, so a pixel of the real frame that matches it
## is sky and one that does not is something in front of it. Exact, and it costs
## two frames -- during which `_process` is off on the rig, the shot, the flock
## and the man, so no state advances and the sequence resumes exactly where it
## paused. A measurement that perturbed the thing it measures would be no
## measurement at all.
##
##   --out <prefix>     required
##   --seed <n>         the flock's and the shot's RNG (default 7)
##   --shots <n>        frames across the shot (default 14)
##   --preset <id>      the sky (default pale_day)
##   --stop <metres>    the player's framing stop (default 10.5, the tight one)
##   --lead <seconds>   how long he walks before the birds go up (default 1.2)
##   --perspective      also grab one frame at the peak through a matched
##                      perspective camera, for the ruling's projection question
##   --return           keep shooting past the end of the camera shot, until the
##                      flock has come back and landed. Writes `<out>-rNN.png`.
##                      The return WAIT is shortened (the arrival itself is not)
##                      so a capture is not thirty seconds of an empty wire
##   --reversed         put the handedness bug BACK, by yawing every bird's rig a
##                      further half turn. The "before" half of the facing
##                      comparison, produced by the shipped code path with the
##                      correction undone rather than by an old build

const SETTLE_FRAMES := 40

## How fast he walks, and from how far out. He has to START OUTSIDE the shot's
## own trigger radius (12 m) or the sequence fires on frame one and there is no
## approach to photograph -- written as 9 m first, which is inside it.
const WALK_SPEED := 1.5
const APPROACH_M := 22.0

## Which wires are close enough to be worth landing a flock on.
const NEAR_M := 11.0

var _out := ""
var _seed := 7
var _shots := 14
var _preset := "pale_day"
var _stop := 10.5
var _lead := 1.2

var _frame := 0
var _started := false
var _done := false
var _shot := 0
var _clock := 0.0
var _next := 0.0
var _every := 0.2

var _flock: CrowFlock = null
var _startle: StartleShot = null
var _calls: CrowCalls = null
var _rig: CameraRig = null
var _man: Node3D = null
var _walk_from := Vector3.ZERO
var _walk_to := Vector3.ZERO
var _walked := 0.0
var _fired := false
var _sky_done := false
var _sky_stage := 0
var _sky_fraction := -1.0
var _sky_image: Image = null
var _peak_shot := 0
var _luminance_before := -1.0
var _luminance_peak := -1.0
var _perspective := false
var _reversed := false
var _watch_return := false
var _returning := false
var _return_shot := 0
var _watch_the_wire := Vector3.INF
## What the shot drew, printed once so the three runs can be compared as numbers
## and not only as pictures.
var _drawn := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_seed = int(_arg(args, "--seed", "7"))
	_shots = maxi(int(_arg(args, "--shots", "14")), 2)
	_preset = _arg(args, "--preset", "pale_day")
	_stop = float(_arg(args, "--stop", "10.5"))
	_lead = float(_arg(args, "--lead", "1.2"))
	_perspective = args.has("--perspective")
	_reversed = args.has("--reversed")
	_watch_return = args.has("--return")
	_peak_shot = int(float(_shots) * 0.45)
	if _out == "":
		push_error("capture_startle: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	if not _started:
		_start()
		return
	if _sky_stage > 0:
		_sky_step()
		return
	if _watch_the_wire != Vector3.INF:
		_rig.global_position = _watch_the_wire
	_walk(delta)
	if not _fired:
		return
	_clock += delta
	if _clock < _next:
		return
	_next += _every
	if _returning:
		_capture_return()
		return
	if _shot >= _shots:
		_finish()
		return
	_capture()


func _start() -> void:
	_started = true
	_rig = get_node_or_null("Main/CameraRig") as CameraRig
	_flock = get_node_or_null("Main/Crows") as CrowFlock
	_calls = get_node_or_null("Main/Crows/Calls") as CrowCalls
	_startle = get_node_or_null("Main/StartleShot") as StartleShot
	_man = get_node_or_null("Main/Player") as Node3D
	if _rig == null or _flock == null or _startle == null or _man == null:
		push_error("capture_startle: expected Main/CameraRig, Main/Crows, Main/StartleShot, Main/Player")
		get_tree().quit()
		return

	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null:
		lighting.apply_preset(StringName(_preset))

	# HIS CONTROLLER OFF, AND HIM DRIVEN. A capture whose walker is simulated is a
	# capture that is not the same shot twice.
	_man.set_physics_process(false)
	_man.set_process(false)

	_flock.random_seed = _seed
	_flock.first_arrival_seconds = 0.0
	# fewest/most left at the shipped 1..5 ON PURPOSE: how many birds go up is the
	# first axis the ruling names, so pinning it here would be pinning the thing
	# under test.
	_flock.attach()
	_flock.set_perches(_near_perches())

	if _calls != null:
		_calls.random_seed = _seed
		_calls.seed_rng()

	# Always, and at once. The rarity is real and is asserted in
	# `tests/unit/test_startle_shot.gd`; a capture that waited out a coin flip and
	# a hundred-second cooldown would photograph the cooldown.
	_startle.random_seed = _seed
	_startle.chance = 1.0
	_startle.cooldown_seconds = 0.0
	_startle.attach()
	print("capture_startle: shot triggers at %.1f m, the flock flushes at %.1f m" % [
		_startle.trigger_radius_m, _flock.flush_radius_m])

	_frame_at(_stop)

	var landed := _flock.land_now()
	if _reversed:
		# MODEL_YAW put back to what Wave 2 shipped. Not a rebuild and not an old
		# commit: the same crows, the same takes, the same flight, with only the
		# half-turn that corrects Unity's +Z forward removed -- so the two sets of
		# frames differ in exactly one thing.
		for crow in _flock.crows():
			var rig := crow.get_node_or_null("Rig") as Node3D
			if rig != null:
				rig.rotate_y(PI)
		print("capture_startle: MODEL_YAW UNDONE -- these frames are the bug")
	var middle := Vector3.ZERO
	for crow in _flock.crows():
		middle += crow.where()
	middle /= maxf(float(_flock.crow_count()), 1.0)
	# Straight at them, from far enough out that he is already walking steadily by
	# the time he is inside the flush radius.
	var along := Vector3(0.0, 0.0, 1.0)
	_walk_to = Vector3(middle.x, 0.0, middle.z)
	_walk_from = _walk_to - along * APPROACH_M
	_man.global_position = _walk_from
	_rig.snap_to_target()
	print("capture_startle: seed %d, %d birds landed, walking (%.1f, %.1f) -> (%.1f, %.1f)" % [
		_seed, landed, _walk_from.x, _walk_from.z, _walk_to.x, _walk_to.z])


## One frame of the scripted walk. He keeps going right through the shot, which
## is the case the ruling allows the camera to hold.
func _walk(delta: float) -> void:
	_walked += WALK_SPEED * delta
	var along := (_walk_to - _walk_from)
	var total := along.length()
	if total < 0.001:
		return
	along /= total
	var at := _walk_from + along * _walked
	# Onto the snow, so he is not walking through the terrain or above it.
	at.y = _ground_at(at)
	_man.global_position = at
	if not _fired and _startle.is_running():
		_fired = true
		_drawn = "shot %.2f s, pitch up to %.1f deg below level, frame share %.2f, widen x%.3f" % [
			_startle.get("_seconds"),
			_rig.pitch_degrees - rad_to_deg(_startle.get("_tilt")),
			_startle.get("_share"), _startle.get("_widen")]
		# Spread the shots across the shot's own length, whatever it drew.
		_every = float(_startle.get("_seconds")) / float(_shots - 1)
		_next = 0.0
		print("capture_startle: %s" % _drawn)


func _capture() -> void:
	var path := "%s-%02d.png" % [_out, _shot]
	_save(get_viewport().get_texture().get_image(), path)
	var wheeling := 0
	var committed := 0
	var feet := 0
	var lifting := 0
	for crow in _flock.crows():
		if crow.has_feet_down():
			feet += 1
		elif not crow.is_flying():
			lifting += 1
		elif crow.is_wheeling():
			wheeling += 1
		else:
			committed += 1
	# The upper half's mean brightness, which is the composition claim as a number:
	# the shot is supposed to move the frame toward a pale background so the birds
	# read dark on bright, and shot 00 is the game's ordinary framing to compare it
	# against.
	var lift := _upper_luminance(get_viewport().get_texture().get_image())
	if _shot == 0:
		_luminance_before = lift
	print("shot %02d  t=%5.2f  pitch %+6.2f deg  swing %+6.2f deg  frame %5.2f m  him in shot: %s  upper %.3f  birds %d wire / %d lifting / %d wheeling / %d away" % [
		_shot, _clock,
		rad_to_deg(_rig.rotation.x), rad_to_deg(_rig.lean().y),
		_rig.framed_size(), "yes" if _startle.frames_him() else "NO", lift,
		feet, lifting, wheeling, committed])
	_luminance_peak = maxf(_luminance_peak, lift)
	_shot += 1
	if _shot == _peak_shot and not _sky_done:
		# AFTER the burst, not at the top of the shot: the calls are scheduled when
		# the birds are told to go, which is a third of the way in. Printed before
		# that, the schedule is empty and the capture reports "0 caws" for a burst
		# that has three.
		_print_the_flock()
		_print_the_calls()
		_sky_stage = 1


## Freeze, hide the world, re-render, compare, unhide, thaw. See the header for
## why the freeze is not optional.
func _sky_step() -> void:
	match _sky_stage:
		1:
			_freeze(true)
			_show_world(false)
			_sky_stage = 2
		2:
			_sky_image = get_viewport().get_texture().get_image()
			_show_world(true)
			_sky_stage = 3
		3:
			var real := get_viewport().get_texture().get_image()
			_sky_fraction = _matching(real, _sky_image)
			_save(_sky_image, "%s-sky.png" % _out)
			print("capture_startle: sky fills %.1f%% of the frame at the peak of the lean" % (
				_sky_fraction * 100.0))
			if _perspective:
				_to_perspective()
				_sky_stage = 4
				return
			_freeze(false)
			_sky_done = true
			_sky_stage = 0
		4:
			# THE EXPERIMENT THE RULING ASKS FOR AN ANSWER ON. The same instant,
			# same lean, same subject, rendered through a perspective camera whose
			# frustum matches the parallel frame AT THE SUBJECT PLANE -- so the
			# birds are the same size in both and the only difference in the two
			# pictures is convergence. That is the comparison; anything else would
			# be comparing two framings.
			_save(get_viewport().get_texture().get_image(), "%s-perspective.png" % _out)
			_to_orthographic()
			_sky_stage = 5
		5:
			_freeze(false)
			_sky_done = true
			_sky_stage = 0


## Perspective, matched to the parallel frame at the subject.
##
## A parallel frame of vertical extent `s` is matched by a perspective camera of
## vertical fov `f` at distance `d` when `s = 2 * d * tan(f/2)`. Solve for `d`,
## put the camera there along the boom, and the subject plane is drawn identically
## -- everything nearer converges in and everything further converges out, which
## is the whole of what perspective adds and the whole of what it costs.
func _to_perspective() -> void:
	var camera := _rig.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	var fov := 24.0
	var distance := _rig.framed_size() / (2.0 * tan(deg_to_rad(fov) * 0.5))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = fov
	camera.position = Vector3(0.0, 0.0, distance)
	camera.near = 0.5
	camera.far = 800.0
	print("capture_startle: perspective at fov %.1f, boom %.1f m, matched to a %.2f m parallel frame" % [
		fov, distance, _rig.framed_size()])


func _to_orthographic() -> void:
	var camera := _rig.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 0.0, _rig.boom_length)
	camera.near = 0.05
	camera.far = 400.0
	camera.size = _rig.framed_size()


## Mean luminance of the top half of the frame. The composition claim, measured:
## a shot that has moved the background toward pale reads brighter up there than
## the game's ordinary framing does.
func _upper_luminance(image: Image) -> float:
	if image == null:
		return -1.0
	var total := 0.0
	var seen := 0
	for y in range(0, image.get_height() / 2, 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			total += 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
			seen += 1
	return 0.0 if seen == 0 else total / float(seen)


func _freeze(on: bool) -> void:
	for node in [_rig, _flock, _startle, _calls, _man,
			get_node_or_null("Main/Snowfall"), get_node_or_null("Main/Wind")]:
		if node != null:
			(node as Node).set_process(not on)
			(node as Node).set_physics_process(not on)


func _show_world(on: bool) -> void:
	for path in ["Main/Terrain", "Main/Farmhouse", "Main/Farmstead", "Main/Player",
			"Main/Crows", "Main/Snowfall", "Main/Wind"]:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			node.visible = on


## The fraction of pixels that are the sky exactly. Not a colour heuristic: the
## reference frame IS the sky, rendered from the same camera on the same frame.
func _matching(real: Image, sky: Image) -> float:
	if real == null or sky == null or real.get_size() != sky.get_size():
		return -1.0
	var same := 0
	var total := 0
	var step := 4
	for y in range(0, real.get_height(), step):
		for x in range(0, real.get_width(), step):
			total += 1
			var a := real.get_pixel(x, y)
			var b := sky.get_pixel(x, y)
			if absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02:
				same += 1
	return 0.0 if total == 0 else float(same) / float(total)


func _print_the_flock() -> void:
	var birds := _flock.crows()
	var line := "capture_startle: %d birds, wheel %s" % [
		birds.size(), "clockwise" if birds.is_empty() or birds[0].wheel_rate() > 0.0 else "anticlockwise"]
	for crow in birds:
		line += " | %.2f rad/s for %.2f s" % [absf(crow.wheel_rate()), crow.wheel_seconds()]
	print(line)


func _print_the_calls() -> void:
	if _calls == null:
		return
	var pending := _calls.pending()
	var line := "capture_startle: %d caws scheduled (%d streams on disk) at" % [
		pending.size(), _calls.call_count()]
	for entry in pending:
		line += " %.2fs(bird %d)" % [float(entry["at"]), int(entry["bird"])]
	print(line)


func _finish() -> void:
	print("capture_startle: seed %d done -- %s | sky %.1f%% | upper luminance %.3f at the game framing, %.3f at the peak (%+.1f%%)" % [
		_seed, _drawn, _sky_fraction * 100.0, _luminance_before, _luminance_peak,
		(_luminance_peak / maxf(_luminance_before, 0.0001) - 1.0) * 100.0])
	if _watch_return and not _returning:
		_start_the_return()
		return
	_done = true
	get_tree().quit()


## Past the shot, into the thing that makes the valley recover from him: the
## flock coming back. NO CAMERA -- the ordinary framing, deliberately. The startle
## earns its lean because it is a surprise and a landing does not, and a second
## camera move inside a minute would spend the exception the Art Bible granted.
##
## Only the WAIT is shortened. The approach, the circle and the flare all run at
## the length the game runs them at, which is what these frames are of.
func _start_the_return() -> void:
	_returning = true
	_flock.return_min_seconds = 2.5
	_flock.return_max_seconds = 2.5
	# Him, well clear -- otherwise they call the landing off, which is correct and
	# is not what this sequence is photographing.
	_walk_to = _walk_from + (_walk_to - _walk_from).normalized() * 60.0
	_every = 0.45
	_clock = 0.0
	_next = 0.0
	# PIN THE CAMERA ON THE WIRE. The game camera follows the man, and the man has
	# to walk away or the birds call the landing off -- so the game's own framing
	# of the return is sixty metres of empty snow, which is CORRECT and is not
	# evidence. Photographed the other way first and got exactly that.
	#
	# This is the capture looking somewhere, not the shot leaning: `lean` is
	# printed on every frame below and stays at 0.00, which is the claim.
	var middle := Vector3.ZERO
	var perches := _flock.available_perches()
	for perch in perches:
		middle += perch["at"] as Vector3
	if not perches.is_empty():
		middle /= float(perches.size())
	_watch_the_wire = Vector3(middle.x, 4.6, middle.z)
	print("capture_startle: --return -- WAIT shortened to 2.5 s (the approach is the game's own); camera pinned on the wire at (%.1f, %.1f)" % [
		_watch_the_wire.x, _watch_the_wire.z])


func _capture_return() -> void:
	var path := "%s-r%02d.png" % [_out, _return_shot]
	_save(get_viewport().get_texture().get_image(), path)
	var inbound := 0
	var landing := 0
	var perched := 0
	var far := 0.0
	for crow in _flock.crows():
		if crow.is_inbound():
			inbound += 1
			far = maxf(far, crow.where().distance_to(crow.target_perch()))
		elif crow.is_landing():
			landing += 1
		elif crow.is_perched():
			perched += 1
	print("return %02d  t=%5.2f  lean %+5.2f deg  %d in the world: %d leaving / %d inbound (furthest %.1f m out) / %d flaring / %d down" % [
		_return_shot, _clock, rad_to_deg(_rig.lean().x), _flock.crow_count(),
		_flock.crow_count() - inbound - landing - perched, inbound, far, landing, perched])
	_return_shot += 1
	if _return_shot >= 64 or (perched > 0 and inbound == 0 and landing == 0):
		print("capture_startle: the flock is back -- %d on the wire" % perched)
		_done = true
		get_tree().quit()


func _save(image: Image, path: String) -> void:
	if image == null:
		return
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	image.save_png(path)


func _frame_at(ortho: float) -> void:
	_rig.orthographic_size = ortho
	_rig.refresh_framing()
	var tween := _rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	_rig.apply_framed_size(_rig.framing_target())


func _ground_at(at: Vector3) -> float:
	var field = _service(&"snow_field")
	if field != null and field.has_method("height_at"):
		return float(field.height_at(Vector2(at.x, at.z)))
	return at.y


## Perches on a wire, near the pole. Filters the props' own offer rather than
## inventing one, so every bird still holds a declaration and still rides.
func _near_perches() -> Array:
	var offered := _flock.available_perches()
	var pole := get_node_or_null("Main/Farmstead/PowerPole") as Node3D
	var spot := pole.global_position if pole != null else Vector3.ZERO
	var near: Array = []
	for perch in offered:
		var span := perch.get("anchor", null) as PerchPoints
		if span == null or span.kind != PerchPoints.Kind.SPAN:
			continue
		var at: Vector3 = perch["at"]
		if Vector2(at.x - spot.x, at.z - spot.z).length() <= NEAR_M:
			near.append(perch)
	print("capture_startle: %d of %d perches are on a wire within %.0f m of the pole" % [
		near.size(), offered.size(), NEAR_M])
	return near


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)
