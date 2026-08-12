extends Node

## The snow arriving, photographed.
##
## `tools/capture_frame.gd` answers "what does the frame look like" and
## `tools/capture_sequence.gd` answers "what does the frame do while somebody
## walks". Neither can answer the only question this feature is judged on --
## does the snow POP -- because a pop is a discontinuity across a transition and
## you can only see one by holding everything else still and stepping the one
## thing that moves.
##
## So this holds the camera, the light and the player completely still and walks
## the accumulation through its range, shooting the identical framing at each
## stop, and printing the scalar and its slope beside every shot. Both halves
## matter: the pictures say whether the snow spreads or arrives, and the numbers
## say whether the curve has a corner in it that the eye happened to miss.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1600x1000 \
##       res://tools/capture_accumulation.tscn -- \
##       --out D:/somewhere/accum --look 6,-14 --ortho 42 \
##       --covers "0.0;0.2;0.36;0.55;0.75;0.9"
##
## Arguments:
##   --out <prefix>     writes <prefix>-00.png, -01.png, ...   (required)
##   --covers "a;b;c"   the accumulations to shoot, in order
##   --transition       shoot a live weather cut instead: settle at --from,
##                      cut the weather to --to, and shoot every --every
##                      simulated seconds for --frames shots
##   --from <0..1>      snowfall before the cut          (default 0.12, PALE DAY)
##   --to <0..1>        snowfall after it                (default 1.0, WHITEOUT)
##   --frames N         shots in transition mode         (default 12)
##   --every <seconds>  simulated seconds between them   (default 12)
##   --look x,z         where the camera is aimed
##   --ortho <m>        frame height in metres
##   --preset <id>      one of Art Bible section 4.2's six, held for the run
##
## THE WEATHER IS DRIVEN THROUGH THE REAL PATH. Nothing here assigns a cover:
## it sets the snowfall on the accumulation's own hook and calls advance() until
## the model has walked where it is going. A harness that poked the scalar
## directly would photograph a state the game can never be in, and would be
## unable to see the exact defect it exists to look for.

const STEP := 0.05
const FAST_FORWARD_BUDGET := 200000


var _out := ""
var _covers: Array[float] = []
var _transition := false
var _from := 0.12
var _to := 1.0
var _frames := 12
var _every := 12.0
var _look := Vector2(6.0, -14.0)
var _ortho := 0.0
var _preset := ""
var _shot := 0
var _busy := false
var _done := false
var _started := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_transition = args.has("--transition")
	_from = float(_arg(args, "--from", str(_from)))
	_to = float(_arg(args, "--to", str(_to)))
	_frames = int(_arg(args, "--frames", str(_frames)))
	_every = float(_arg(args, "--every", str(_every)))
	_preset = _arg(args, "--preset", "")
	for entry in _arg(args, "--covers", "0.0;0.2;0.36;0.55;0.75;0.9").split(";", false):
		_covers.append(clampf(float(entry), 0.0, 1.0))
	var look := _arg(args, "--look", "")
	if look != "":
		var parts := look.split(",")
		if parts.size() == 2:
			_look = Vector2(float(parts[0]), float(parts[1]))
	_ortho = float(_arg(args, "--ortho", "0"))
	if _out == "":
		push_error("capture_accumulation: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _snow() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(&"snow_accumulation") as Node


func _process(_delta: float) -> void:
	if _done or _busy:
		return
	if not _started:
		_started = true
		_frame_the_shot()
		return
	_busy = true
	if _transition:
		await _shoot_transition()
	else:
		await _shoot_stops()
	_done = true
	get_tree().quit()


## The camera never moves for the whole run, and neither does the player. The
## only thing that changes between shots is the snow -- which is the only way a
## step in it can be told apart from a step in anything else.
func _frame_the_shot() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	if rig != null:
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null and not lighting.apply_preset(StringName(_preset)):
			push_error("capture_accumulation: no lighting preset '%s'" % _preset)
	_pin_frame(true)


## THE FRAME IS RE-PINNED BEFORE EVERY SHOT, and the first sequence off this
## harness is why. CameraRig snaps its own size to the nearest of its framing
## stops and eases toward it, so a size written once in _ready() drifts across
## the run -- and a sequence whose whole purpose is "hold everything still and
## move one thing" had a camera creeping forward through it. The first and last
## frames were 9% different in scale, which is not much and is exactly enough to
## make two pictures uncomparable.
##
## `stops` is annotated rather than inferred. framing_stops is Array[float], and
## an untyped array literal assigned into a typed property is a runtime error
## that ABORTS the caller silently (briefing trap 4) -- which here would leave
## the frame unpinned again with nothing said.
func _pin_frame(rebase: bool) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	# The rig eases toward the player every frame, so an aim set once in _ready()
	# creeps back to him across the run. The first sequence off this harness
	# panned nearly two metres between its first and last shot.
	if rig != null:
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)
	if _ortho <= 0.0:
		return
	if rig != null:
		if rebase:
			var stops: Array[float] = [_ortho]
			rig.framing_stops = stops
			rig.orthographic_size = _ortho
			if rig.has_method("set_framing_index"):
				rig.set_framing_index(0)
		# THE TWEEN HAS TO DIE OR THE SIZE DOES NOT STICK. Asking the rig for a
		# new frame starts an ease toward it, and the ease writes the camera every
		# frame -- so apply_framed_size() is overwritten on the next tick and the
		# sequence is shot part-way through a zoom. Two captures were lost to this.
		if rig.has_method("framing_tween"):
			var tween: Tween = rig.framing_tween()
			if tween != null and tween.is_valid():
				tween.kill()
		if rig.has_method("apply_framed_size"):
			rig.apply_framed_size(_ortho)
	var camera := get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	if camera != null:
		camera.size = _ortho


## Walks the model to each requested cover through its own hooks and shoots.
func _shoot_stops() -> void:
	var snow := _snow()
	if snow == null:
		push_error("capture_accumulation: no snow_accumulation service")
		return
	for wanted in _covers:
		_fast_forward_to(snow, wanted)
		await _capture(snow, "stop %.3f" % wanted)


## Sets the weather that has `wanted` as its destination and then runs the model
## until it gets there. Nothing is assigned: the cover arrives where it arrives
## by integrating, exactly as it does in play, only faster than real time.
func _fast_forward_to(snow: Node, wanted: float) -> void:
	# equilibrium = gain / (gain + shed), so the snowfall that settles at
	# `wanted` is the one making gain = shed * wanted / (1 - wanted). Solved
	# rather than searched, and clamped because a cover of exactly 1 has no
	# finite weather that reaches it -- which is the whole point of the model.
	var reachable := clampf(wanted, 0.0, 0.97)
	var shed: float = 1.0 / float(snow.shed_seconds)
	var gain: float = shed * reachable / maxf(1.0 - reachable, 0.0001)
	snow.set_snowfall_rate(clampf(gain * float(snow.settle_seconds), 0.0, 1.0))
	var budget := FAST_FORWARD_BUDGET
	while budget > 0 and absf(snow.cover() - reachable) > 0.002:
		snow.advance(STEP)
		budget -= 1
	if budget <= 0:
		push_warning("capture_accumulation: could not reach cover %.3f" % wanted)


## The live weather cut. Settles at `--from`, shoots, then changes ONE thing --
## the snowfall -- and shoots the transition at even intervals of simulated
## time. If the snow steps anywhere, it steps between two of these.
func _shoot_transition() -> void:
	var snow := _snow()
	if snow == null:
		push_error("capture_accumulation: no snow_accumulation service")
		return
	snow.set_snowfall_rate(_from)
	var settle := int(snow.shed_seconds * 8.0 / STEP)
	for _step in range(settle):
		snow.advance(STEP)
	await _capture(snow, "before the cut, snowfall %.2f" % _from)

	snow.set_snowfall_rate(_to)
	var per_shot := maxi(int(_every / STEP), 1)
	for shot in range(_frames):
		for _step in range(per_shot):
			snow.advance(STEP)
		await _capture(snow, "t+%.0fs" % (float(shot + 1) * _every))


## One PNG, and one line of numbers beside it. The line is the half a picture
## cannot carry: a cover that moved twice as far between two shots as between
## the two before them is a corner, whether or not the eye can see it.
func _capture(snow: Node, label: String) -> void:
	var index := _shot
	_shot += 1
	print("capture_accumulation: %02d  cover=%.4f  rate=%+.6f/s  %s" % [
		index, snow.cover(), snow.rate(), label,
	])
	# Two frames: one for the material broadcast TerrainRenderer makes from its
	# own _process to reach the compositor, and one to draw with it. The frame is
	# re-pinned on both, because the rig ticks in between them.
	_pin_frame(false)
	await RenderingServer.frame_post_draw
	_pin_frame(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, index]
	var error := image.save_png(path)
	if error != OK:
		push_error("capture_accumulation: could not write %s (error %d)" % [path, error])
