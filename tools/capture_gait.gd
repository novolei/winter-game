extends Node

## Photographs the animation graph, because the straddle is a MID-BLEND artefact
## and neither a still frame nor a number can show it.
##
##   Godot_console.exe --path <project> res://tools/capture_gait.tscn \
##       --resolution 900x900 -- --out D:/somewhere/gait [--broken]
##
## Writes one contact sheet per scenario -- <out>_walk.png, _run.png, _mid.png,
## _blend.png, _idle_warm.png, _idle_mid.png, _idle_cold.png -- each a strip of
## frames across one full cycle, so a leg that splays at an intermediate blend is
## visible as a shape rather than inferred.
##
## `--broken` rebuilds the graph the way it was before the fix: sync off on all
## three Blend2 nodes, both gait clips back on their own timelines, and the old
## speed-ratio pace. That is what makes this an A/B rather than an assertion --
## the same harness, the same camera, the same frames, one flag apart.
##
## The camera matches src/rendering/camera_rig.gd's angles (pitch 45, yaw -35,
## orthographic) because that is the only view the player ever gets, but it is
## pulled in tight on the figure: the game frames 10.5 m of world and a man is a
## ninth of it, which is far too small to judge a stance.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")

const PITCH_DEGREES := 45.0
const YAW_DEGREES := -35.0
## Vertical world extent. The figure is 1.88 m, so this fills most of the frame.
const FRAME_METRES := 2.6

## Frames per contact sheet, and the cell size they are laid out at.
##
## The render is square and the figure is narrow, so most of a square frame is
## background. Each shot is cropped to a portrait strip down the middle before it
## goes on the sheet -- six tall cells rather than eight small ones, because a
## straddle is a shape and it has to be big enough to see.
const CELL_W := 300
const CELL_H := 600
const COLUMNS := 6

var _out := "user://gait"
var _broken := false
var _probe := false
var _probe_idle_only := false
var _player: PlayerController = null
var _tree: AnimationTree = null
var _camera: Camera3D = null


func _ready() -> void:
	_read_arguments()
	_build_world()
	# One frame for the tree to come up before anything is driven or captured.
	await RenderingServer.frame_post_draw
	if _probe_idle_only:
		await _probe_idle()
	elif _probe:
		await _probe_periods()
	else:
		await _capture_everything()
	get_tree().quit()


## Measures the cycle the graph actually produces, from the skeleton rather than
## from the parameters -- the only way to check what use_custom_timeline and
## stretch_time_scale really do on this build instead of trusting the docs.
##
## The thigh's fore-aft swing is the gait. Sampled at a fixed pace of 1 so the
## number that comes out is the clip's own period through the graph.
func _probe_periods() -> void:
	var skeleton := _first_skeleton(_player)
	var thigh := skeleton.find_bone("LeftUpLeg")
	print("probe: %s   walk_period=%.4f  run_period=%.4f  shared=%.4f" % [
		"BROKEN (sync off, clips on their own lengths)" if _broken else "fixed (sync on, cycles locked)",
		_player._walk_period, _player._run_period, _player._cycle_period,
	])
	for gait in [0.0, 0.5, 1.0]:
		_tree.set(&"parameters/motion/blend_amount", 1.0)
		_tree.set(&"parameters/gait/blend_amount", gait)
		_tree.set(&"parameters/pace/scale", 1.0)
		# Settle, then sample two seconds at 100 Hz.
		for i in range(30):
			_tree.advance(0.01)
			await RenderingServer.frame_post_draw
		var trace: Array[float] = []
		for i in range(500):
			_tree.advance(0.01)
			await RenderingServer.frame_post_draw
			trace.append(Basis(skeleton.get_bone_pose_rotation(thigh)).get_euler().x)
		print("  gait %.1f  period %.4f s   swing range %.3f rad" % [
			gait, _period_of(trace, 0.01), _range_of(trace),
		])


## How much shiver is actually in the pose at each chill value.
##
## A shiver is FAST and SMALL; the neutral idle is slow and larger. Measuring the
## pose's total angular speed separates them: tremor shows up as speed, sway does
## not. Reported against the excursion so the two are comparable.
##
## This exists because `chill` blending is linear, so a floor of 0.45 puts 55% of
## a still pose into the take the owner asked for by name, and the question of
## whether that still reads as his shiver is not answerable from the constant.
func _probe_idle() -> void:
	var skeleton := _first_skeleton(_player)
	var bones := range(skeleton.get_bone_count())
	_tree.set(&"parameters/motion/blend_amount", 0.0)
	print("chill   tremor(rad/s)   excursion(rad)   share of full shiver")
	var full := 0.0
	var rows := []
	for chill in [0.0, 0.2, 0.45, 0.6, 0.7, 0.85, 1.0]:
		_tree.set(&"parameters/chill/blend_amount", chill)
		for i in range(30):
			_tree.advance(1.0 / 60.0)
			await RenderingServer.frame_post_draw
		var previous: Array[Quaternion] = []
		var mean_pose: Array[Quaternion] = []
		var speeds: Array[float] = []
		var excursion := 0.0
		for i in range(240):
			_tree.advance(1.0 / 60.0)
			await RenderingServer.frame_post_draw
			var pose: Array[Quaternion] = []
			for b in bones:
				pose.append(skeleton.get_bone_pose_rotation(b))
			if not previous.is_empty():
				var total := 0.0
				for b in range(pose.size()):
					total += previous[b].angle_to(pose[b])
				speeds.append(total * 60.0)
			if mean_pose.is_empty():
				mean_pose = pose.duplicate()
			else:
				var away := 0.0
				for b in range(pose.size()):
					away += mean_pose[b].angle_to(pose[b])
				excursion = maxf(excursion, away)
			previous = pose
		var rms := 0.0
		for s in speeds:
			rms += s * s
		rms = sqrt(rms / maxf(float(speeds.size()), 1.0))
		if chill == 1.0:
			full = rms
		rows.append([chill, rms, excursion])
	for row in rows:
		print("  %.2f      %8.4f        %8.4f         %5.1f%%" % [
			row[0], row[1], row[2], 100.0 * float(row[1]) / maxf(full, 0.0001),
		])


func _first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _first_skeleton(child)
		if found != null:
			return found
	return null


func _range_of(trace: Array[float]) -> float:
	var low := INF
	var high := -INF
	for v in trace:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


## Autocorrelation: the lag at which the trace best repeats itself is its period.
func _period_of(trace: Array[float], dt: float) -> float:
	var mean := 0.0
	for v in trace:
		mean += v
	mean /= float(trace.size())
	var best_lag := 0
	var best := -INF
	# From 10 samples up, so the zero lag does not win outright.
	for lag in range(10, trace.size() / 2):
		var score := 0.0
		for i in range(trace.size() - lag):
			score += (trace[i] - mean) * (trace[i + lag] - mean)
		score /= float(trace.size() - lag)
		if score > best:
			best = score
			best_lag = lag
	return float(best_lag) * dt


func _read_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--broken":
			_broken = true
		elif args[index] == "--probe":
			_probe = true
		elif args[index] == "--probe-idle":
			_probe_idle_only = true


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Mid grey, off-palette on purpose: this is a diagnostic contact sheet and
	# nothing here is art. A pale background is what makes a dark silhouette's
	# legs readable, which is the entire job.
	env.background_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.79, 0.85)
	env.ambient_light_energy = 0.9
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-70.0), 0.0)
	sun.light_energy = 1.6
	add_child(sun)

	_player = PlayerControllerScript.new()
	add_child(_player)
	# The graph is what is under test; the locomotion model is not. Driving the
	# parameters directly is also the only way to hold an intermediate blend
	# still, which is exactly where the defect lives.
	_player.set_physics_process(false)
	_tree = _player.get_node_or_null("Gait") as AnimationTree
	if _tree == null:
		push_error("capture_gait: the controller built no AnimationTree")
		return
	# MANUAL, or the tree advances twice per iteration: once by its own idle
	# processing with the real frame delta, and again by the explicit advance()
	# below. That put a machine-dependent frame rate inside every measurement.
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if _broken:
		_break_the_graph()

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = FRAME_METRES
	var aim := Vector3(deg_to_rad(-PITCH_DEGREES), deg_to_rad(YAW_DEGREES), 0.0)
	_camera.rotation = aim
	# From the rotation rather than from global_transform: the camera is not in
	# the tree yet, and asking an orphan for its global transform is an error.
	var back := Basis.from_euler(aim).z
	_camera.position = Vector3(0.0, 0.95, 0.0) + back * 8.0
	_camera.near = 0.05
	_camera.far = 60.0
	add_child(_camera)
	_camera.make_current()


## Puts the graph back the way it was before the fix, so the two sheets differ by
## the defect and by nothing else.
func _break_the_graph() -> void:
	var graph := _tree.tree_root as AnimationNodeBlendTree
	for name in ["chill", "gait", "motion"]:
		var blend := graph.get_node(name) as AnimationNodeBlend2
		blend.sync = false
	# Both clips back on their own lengths, which is what "no phase lock" means
	# now that the lock is a pair of TimeScale nodes.
	_tree.set(&"parameters/walk_rate/scale", 1.0)
	_tree.set(&"parameters/run_rate/scale", 1.0)


## What _drive_animation() would set at this ground speed, computed the same way
## so the sheets photograph the shipping arithmetic rather than a guess.
func _drive(speed: float) -> void:
	var gait := clampf(
		inverse_lerp(_player.anim_walk_speed, _player.anim_run_speed, speed), 0.0, 1.0
	)
	var pace := 0.0
	if _broken:
		var reference: float = lerpf(_player.anim_walk_speed, _player.anim_run_speed, gait)
		pace = speed / reference
	else:
		var stride := lerpf(
			_player.anim_walk_speed * _player._walk_period,
			_player.anim_run_speed * _player._run_period,
			gait
		)
		pace = speed * _player._cycle_period / maxf(stride, 0.0001)
	_tree.set(&"parameters/motion/blend_amount", 1.0)
	_tree.set(&"parameters/gait/blend_amount", gait)
	_tree.set(&"parameters/pace/scale", clampf(pace, 0.0, _player.anim_max_pace))


func _shot() -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# Crop to a portrait strip down the middle before scaling: the figure is
	# narrow and a square frame spends most of itself on background.
	var full := image.get_size()
	var strip := int(float(full.y) * 0.5)
	image = image.get_region(Rect2i((full.x - strip) / 2, 0, strip, full.y))
	image.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
	# The viewport hands back RGB8 or RGBAH depending on the driver, and
	# blit_rect refuses a format mismatch outright rather than converting.
	image.convert(Image.FORMAT_RGBA8)
	return image


## Runs the tree forward for `seconds` at a fixed parameter set, grabbing COLUMNS
## frames evenly across it, and lays them out left to right.
func _sheet(seconds: float, label: String, speed: float, ramp := false) -> void:
	var sheet := Image.create_empty(CELL_W * COLUMNS, CELL_H, false, Image.FORMAT_RGBA8)
	var step := seconds / float(COLUMNS)
	for column in range(COLUMNS):
		if ramp:
			# The transition: speed climbs from the walk to the run across the
			# sheet, which is the moment the owner is describing.
			_drive(lerpf(_player.walk_speed, _player.run_speed, float(column) / float(COLUMNS - 1)))
		else:
			_drive(speed)
		# advance() rather than waiting on real time: the sheet has to sample the
		# cycle at exact intervals, and this machine's frame rate is not a clock.
		_tree.advance(step)
		var frame: Image = await _shot()
		sheet.blit_rect(frame, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * column, 0))
	var path := "%s_%s.png" % [_out, label]
	print("capture_gait: %s  (%s)" % [path, "BROKEN" if _broken else "fixed"])
	sheet.save_png(path)


func _idle_sheet(chill_amount: float, label: String) -> void:
	var sheet := Image.create_empty(CELL_W * COLUMNS, CELL_H, false, Image.FORMAT_RGBA8)
	_tree.set(&"parameters/motion/blend_amount", 0.0)
	_tree.set(&"parameters/chill/blend_amount", chill_amount)
	# A SHORT window, not a whole idle cycle. A shiver is fast and small: sampled
	# half a second apart the tremor aliases into noise and every cell looks like
	# a different still pose. At 0.1 s apart, adjacent cells that jitter against
	# each other ARE the shiver, and adjacent cells that look identical are its
	# absence -- which is the thing being judged.
	for column in range(COLUMNS):
		_tree.advance(0.6 / float(COLUMNS))
		var frame: Image = await _shot()
		sheet.blit_rect(frame, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * column, 0))
	var path := "%s_%s.png" % [_out, label]
	print("capture_gait: %s  (%s)" % [path, "BROKEN" if _broken else "fixed"])
	sheet.save_png(path)


## One sheet whose columns are CHILL values rather than moments in time, all
## sampled at the same point in the idle. The floor is a judgement about a
## silhouette -- the two idles differ in POSTURE, not just in tremor amplitude --
## and a ladder is the only way to see where the cold posture arrives.
func _chill_ladder(values: Array, label: String) -> void:
	var sheet := Image.create_empty(CELL_W * values.size(), CELL_H, false, Image.FORMAT_RGBA8)
	_tree.set(&"parameters/motion/blend_amount", 0.0)
	for column in range(values.size()):
		_tree.set(&"parameters/chill/blend_amount", float(values[column]))
		# Settle at the new blend without advancing the clips, so every column is
		# the same moment of the idle and only the blend differs.
		_tree.advance(0.0)
		var frame: Image = await _shot()
		sheet.blit_rect(frame, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * column, 0))
	var path := "%s_%s.png" % [_out, label]
	print("capture_gait: %s  columns %s" % [path, str(values)])
	sheet.save_png(path)


func _capture_everything() -> void:
	# One full shared cycle at each gait, so a sheet reads as a stride.
	var cycle: float = _player._cycle_period if not _broken else _player._run_period
	await _sheet(cycle, "walk", _player.walk_speed)
	await _sheet(cycle, "mid", 2.4)
	await _sheet(cycle, "run", _player.run_speed)
	await _sheet(cycle * 3.0, "blend", 0.0, true)
	# The floor, the middle of the remap, the top, and a no-shiver reference.
	await _idle_sheet(0.0, "idle_chill000")
	await _idle_sheet(0.45, "idle_chill045")
	await _idle_sheet(0.70, "idle_chill070")
	await _idle_sheet(1.0, "idle_chill100")
	await _chill_ladder([0.45, 0.55, 0.60, 0.65, 0.70, 0.80], "ladder")
