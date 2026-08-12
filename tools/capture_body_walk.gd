extends Node

## Two men, the same ground, the same input, one difference between them --
## photographed from the game's own camera at the framing the game is played at.
##
##   Godot_console.exe --path <project> res://tools/capture_body_walk.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/walk --mode hunger
##
##   --mode hunger      left man fed, right man starving
##   --mode frostbite   left man whole, right man's feet and hands gone
##   --mode probe       prints the snow depth along the chosen path and stops
##
## ---------------------------------------------------------------------------
## WHY THIS RUNS THE REAL SCENE AND NOT A DIORAMA
## ---------------------------------------------------------------------------
## The acceptance question is "can a player tell which of these two men is
## starving", and a player is looking at scenes/main.tscn through CameraRig at
## its 10.5 m stop, where a standing figure is 11.4% of frame height. Judged from
## a tight diagnostic view every one of these readings passes and none of them
## has been tested. So the harness instances the real scene, adds a SECOND
## PlayerController beside the one already in it, and lets both run their own
## _physics_process against the real SnowField.
##
## Both men are driven by the SAME key. Input.action_press() is read by every
## controller in the tree, so there is no per-body input path that could differ,
## and the only thing that is not identical between them is the survival model
## each was handed.
##
## ---------------------------------------------------------------------------
## THE CAMERA IS PINNED, AND THE BRIEFING SAYS WHY
## ---------------------------------------------------------------------------
## "Pin the camera to a fixed transform, not to a follow target, whenever the
## comparison is about the ground rather than about the walk... a commit halved
## his pace in deep snow, so a capture of fixed duration covered 28.5 m instead
## of 54.7 m, and the following camera came to rest over different ground."
##
## Here the comparison IS about the walk, and the same trap applies from the
## other side: a camera following either man would subtract exactly the
## difference this capture exists to show. So it is placed once, from the start
## position, and never moves.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## How far apart the two men stand, in metres, measured across the direction they
## walk. Close enough that they are in the same weather and the same drift, far
## enough that neither silhouette overlaps the other at the game's framing.
const LANE_METRES := 2.4

## How long they walk for. Long enough that a difference in pace has become a
## difference in POSITION, which is the only form of it a still frame can hold.
const WALK_SECONDS := 9.0

var _out := "user://walk"
var _mode := "hunger"
var _ortho := 0.0
var _seconds := WALK_SECONDS
var _left: PlayerController = null
var _right: PlayerController = null
var _left_body = null
var _right_body = null
var _camera: Camera3D = null
var _elapsed := 0.0
var _done := false
var _start := Vector3.ZERO
var _heading := Vector3.ZERO
var _frames: Array[Image] = []
var _next_frame := 0
var _wades: Array[float] = []


func _ready() -> void:
	_read_arguments()
	_left = get_node_or_null("Main/Player") as PlayerController
	if _left == null:
		push_error("capture_body_walk: scenes/main.tscn has no Player")
		get_tree().quit(1)
		return
	_pin_camera()
	_choose_ground()
	if _mode == "probe":
		_probe()
		get_tree().quit()
		return
	_stand_them_up()
	# Both bodies, before either has had a physics frame: PlayerController resolves
	# /root/SurvivalSystem lazily in _physics_process, and a model set first wins.
	# Left untouched, both men would share the autoload and there would be no
	# difference to photograph.
	_left_body = _fresh_body()
	_right_body = _fresh_body()
	_left.set_survival_system(_left_body)
	_right.set_survival_system(_right_body)
	_afflict(_right_body)
	print("capture_body_walk: mode %s, start %s, heading %s" % [_mode, _start, _heading])
	_report_bodies()
	# The hands are a STANDING readout and nothing else. They reach the body
	# through the idle blend, and at any walking speed `motion` is 1 and neither
	# idle contributes at all -- so a capture of two men walking would photograph
	# the feet and call it the hands.
	if _mode != "hands":
		Input.action_press(_walk_action())


func _exit_tree() -> void:
	# Both are plain Nodes handed in by injection rather than parented, so nothing
	# in the tree owns them (briefing constraint 2).
	if _left_body != null:
		_left_body.free()
	if _right_body != null:
		_right_body.free()


func _read_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--mode" and index + 1 < args.size():
			_mode = args[index + 1]
		elif args[index] == "--seconds" and index + 1 < args.size():
			_seconds = float(args[index + 1])
		elif args[index] == "--ortho" and index + 1 < args.size():
			# Diagnostic only. A judgement made at anything but the rig's own stop
			# is a judgement about a view no player ever gets.
			_ortho = float(args[index + 1])


# --- the two bodies -----------------------------------------------------------

func _fresh_body():
	var body = SurvivalSystemScript.new()
	body.load_from_directory()
	body.start()
	return body


## Drops a stat by ADDING to its drain and integrating -- the same path the tests
## use, and the only one there is: the model has no setter, deliberately, so that
## "why did my temperature jump" always has an answer in data.
func _drop_to(body, stat_id: StringName, value: float) -> void:
	body.push_modifier(stat_id, &"capture", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while body.value_of(stat_id) > value and not body.is_dead() and guard < 40000:
		body.advance(0.25)
		guard += 1
	body.remove_source(&"capture")


func _afflict(body) -> void:
	match _mode:
		"hands":
			_drop_to(body, &"frostbite_hands", 0.15)
		"frostbite":
			# Both limbs at once, because that is how they are earned: frostbite is
			# a function of the same exposure, and a man who has ruined his feet
			# has been just as cold about his hands.
			_drop_to(body, &"frostbite_feet", 0.15)
			_drop_to(body, &"frostbite_hands", 0.15)
		_:
			_drop_to(body, &"hunger", 0.01)


func _report_bodies() -> void:
	for row in [["left ", _left_body], ["right", _right_body]]:
		var body = row[1]
		print("  %s  hunger %.2f  feet %.2f  hands %.2f  core %.2f  rhythm %.3f  footing %.3f" % [
			row[0],
			body.fraction_of(&"hunger"), body.fraction_of(&"frostbite_feet"),
			body.fraction_of(&"frostbite_hands"), body.fraction_of(&"core_temperature"),
			body.channel_value(&"locomotion:rhythm", 0.45),
			body.channel_value(&"locomotion:footing", 1.0),
		])


# --- the ground ---------------------------------------------------------------

## Which way they walk, as an input action.
##
## Across the screen rather than into it. Under a camera yawed -35 degrees and
## pitched 45, a metre of separation along the view direction reads as less than
## a metre on screen and is confounded with depth; a metre across the frame reads
## as a metre. The gap this capture exists to show has to be measured by the eye
## in the direction the eye is best at.
func _walk_action() -> StringName:
	return &"move_right"


## Picks a start from which the whole walk stays in deep snow.
##
## Hunger reaches locomotion through `locomotion:rhythm`, which is bounded by the
## terrain's own penalty -- on ground that costs nothing there is nothing for it
## to take. So a capture on bare ground would show two identical men and would be
## evidence of NOTHING except that the harness stood them somewhere useless.
## Searched rather than typed in, and the depths are printed, so the shot can be
## checked against the claim.
func _choose_ground() -> void:
	var snow := _snow()
	var basis := _camera.global_transform.basis.x
	_heading = Vector3(basis.x, 0.0, basis.z).normalized()
	if snow == null:
		_start = Vector3.ZERO
		return
	var best := -1.0
	var best_at := Vector3.ZERO
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var at := Vector3(float(gx) * 2.0, 0.0, float(gz) * 2.0)
			var total := 0.0
			var samples := 12
			for step in range(samples):
				var here: Vector3 = at + _heading * (float(step) * 1.0)
				total += snow.wade_factor(here)
			var mean := total / float(samples)
			if mean > best:
				best = mean
				best_at = at
	_start = best_at
	print("capture_body_walk: mean wade along the chosen path %.3f" % best)


func _probe() -> void:
	var snow := _snow()
	if snow == null:
		print("capture_body_walk: no SnowField in the registry")
		return
	var row := ""
	for step in range(14):
		row += "%.2f " % snow.wade_factor(_start + _heading * float(step))
	print("capture_body_walk: wade along the path: %s" % row)


func _snow() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(&"snow_field") as Node


func _stand_them_up() -> void:
	# The second man is built here rather than instanced from a scene: there is no
	# player scene, the controller builds its own body in _ready(), and a second
	# one is therefore one line and identical to the first by construction.
	_right = PlayerControllerScript.new()
	_left.get_parent().add_child(_right)
	# EVERYTHING THE SCENE'S PLAYER CARRIES, the second man carries too.
	#
	# This is not tidiness. The scene hangs a SnowLoad on its player and the
	# controller builds its own BreathFog, so without this line one figure has
	# snow on his shoulders and the other does not -- and the two frames are no
	# longer of the same thing, which the briefing lists as the way a comparison
	# quietly stops being evidence. It already cost a misreading here: white on
	# the scene player's hood was read as a hand at his face, and the conclusion
	# drawn from it was the exact opposite of what the skeletons said.
	var load_node := _left.get_node_or_null("SnowLoad")
	if load_node != null:
		_right.add_child(load_node.duplicate())
	# Across the walk, so they set off level and the gap that opens is entirely
	# the difference in pace.
	var across := Vector3(-_heading.z, 0.0, _heading.x)
	_left.global_position = _start - across * (LANE_METRES * 0.5)
	_right.global_position = _start + across * (LANE_METRES * 0.5)
	# The scene's own player has already registered itself as the service; the new
	# one overwrote it in its _ready(). Put it back, so anything that resolves the
	# player during the capture resolves the one the scene shipped.
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"player", _left)


# --- the camera ---------------------------------------------------------------

func _pin_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	_camera = rig.get_node_or_null("Camera3D") as Camera3D
	# Stopped rather than merely snapped: the rig eases toward its target every
	# frame, so leaving it running would slowly subtract the very gap this capture
	# is of.
	rig.set_process(false)
	rig.set_physics_process(false)
	if _ortho > 0.0 and _camera != null:
		_camera.size = _ortho


func _place_camera() -> void:
	if _camera == null:
		return
	# Half a walk ahead of the start, so both the ground they set off from and the
	# ground they reach are in frame and neither man leaves the shot. Nothing
	# moves in the standing comparison, so the camera sits on them instead.
	var middle: float = 0.0 if _mode == "hands" else _left.top_speed_at(0.0) * _seconds * 0.35
	var look: Vector3 = _start + _heading * middle
	var back := _camera.global_transform.basis.z
	_camera.global_position = look + Vector3(0.0, 1.0, 0.0) + back * 90.0


# --- the run ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _done or _mode == "probe":
		return
	if _elapsed == 0.0:
		_place_camera()
	_elapsed += delta
	var snow := _snow()
	if snow != null:
		_wades.append(snow.wade_factor(_left.global_position))
	# Four moments across the walk, evenly spaced, so the strip shows the gap
	# OPENING rather than only its final size.
	var want := int(float(_next_frame + 1) * _seconds / 4.0)
	if _next_frame < 4 and _elapsed >= float(want):
		_next_frame += 1
		_grab()
	if _elapsed >= _seconds:
		_done = true
		_finish()


func _grab() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	_frames.append(image)


func _finish() -> void:
	Input.action_release(_walk_action())
	await RenderingServer.frame_post_draw
	var final := get_viewport().get_texture().get_image()
	final.convert(Image.FORMAT_RGBA8)
	final.save_png("%s_%s_final.png" % [_out, _mode])
	if not _frames.is_empty():
		var size := _frames[0].get_size()
		var strip := Image.create_empty(size.x, size.y * _frames.size(), false, Image.FORMAT_RGBA8)
		for index in range(_frames.size()):
			strip.blit_rect(
				_frames[index], Rect2i(0, 0, size.x, size.y), Vector2i(0, size.y * index)
			)
		strip.save_png("%s_%s_strip.png" % [_out, _mode])
	var mean := 0.0
	for w in _wades:
		mean += w
	mean /= maxf(float(_wades.size()), 1.0)
	var across := Vector3(-_heading.z, 0.0, _heading.x)
	var left_from: Vector3 = _left.global_position - (_start - across * (LANE_METRES * 0.5))
	var right_from: Vector3 = _right.global_position - (_start + across * (LANE_METRES * 0.5))
	var left_travel := Vector2(left_from.x, left_from.z).length()
	var right_travel := Vector2(right_from.x, right_from.z).length()
	print("capture_body_walk: %s over %.1f s at mean wade %.3f" % [_mode, _elapsed, mean])
	print("  left  travelled %.3f m   (%.3f m/s)" % [
		left_travel, left_travel / maxf(_elapsed, 0.0001),
	])
	print("  right travelled %.3f m   (%.3f m/s)" % [
		right_travel, right_travel / maxf(_elapsed, 0.0001),
	])
	print("  gap %.3f m (%.1f%%)" % [
		left_travel - right_travel,
		100.0 * (left_travel - right_travel) / maxf(left_travel, 0.0001),
	])
	print("  right footing blend %.3f, stand chill %.3f (left %.3f / %.3f)" % [
		_right.footing_blend(), _right.stand_chill(),
		_left.footing_blend(), _left.stand_chill(),
	])
	# WHERE EACH MAN IS ON THE SCREEN, from the camera rather than from
	# trigonometry. Working it out by hand got it backwards once and produced a
	# reading of the wrong figure -- and a capture whose subjects are mislabelled
	# is worse than no capture, because it is confidently wrong.
	for row in [["left  (whole)    ", _left], ["right (afflicted)", _right]]:
		var man: PlayerController = row[1]
		var at := Vector2.ZERO
		if _camera != null:
			at = _camera.unproject_position(man.global_position + Vector3(0.0, 0.9, 0.0))
		var tree := man.get_node_or_null("Gait") as AnimationTree
		var blend := -1.0
		if tree != null:
			blend = float(tree.get(&"parameters/chill/blend_amount"))
		print("  %s screen %4d,%4d  chill param %.3f  %s" % [
			row[0], int(at.x), int(at.y), blend, _hands_of(man),
		])


## Where this man's hands actually are, off his own skeleton.
##
## The picture would not settle it: the scene's player carries a SnowLoad and a
## BreathFog and the second man does not, so white patches on the head and a puff
## at the mouth are enough to make one figure look like it is doing something
## with its hands when it is not. Bones do not have that problem.
func _hands_of(man: PlayerController) -> String:
	var skeleton := _skeleton(man)
	if skeleton == null:
		return "no skeleton"
	var hips := skeleton.find_bone("Hips")
	var left := skeleton.find_bone("LeftHand")
	var right := skeleton.find_bone("RightHand")
	if hips < 0 or left < 0 or right < 0:
		return "no hand bones"
	var root := skeleton.get_bone_global_pose(hips).origin
	var lh := skeleton.get_bone_global_pose(left).origin - root
	var rh := skeleton.get_bone_global_pose(right).origin - root
	var head := skeleton.find_bone("Head")
	var stature := 0.0
	if head >= 0:
		stature = skeleton.get_bone_global_pose(head).origin.y
	return "hands %+.1f/%+.1f over the hips, %.1f apart; head at %.1f" % [
		lh.y, rh.y, (lh - rh).length(), stature,
	]


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null
	print("  %s_%s_final.png" % [_out, _mode])
	get_tree().quit()
