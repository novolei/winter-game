extends Node

## Two questions about the hunger stand, asked in the pixels a player gets.
##
##   Godot_console.exe --path <project> res://tools/capture_hunch_ladder.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/hunch [--mode ladder|postures]
##
##   ladder     Where does the blend stop being an upright man with noise on him
##              and start being a hunched one? Steps the BLEND at ONE INSTANT.
##   postures   Can a viewer tell cold from tired from hungry? Photographs each
##              state through the real survival model at the real camera and lays
##              the crops out at 1:1, unlabelled.
##
## ---------------------------------------------------------------------------
## WHY THE BLEND AND NOT THE TIME
## ---------------------------------------------------------------------------
## The briefing's instrument note: "A contact sheet stepping TIME at one blend
## value cannot show this -- every frame looks like a plausible pose. Step the
## BLEND value at one instant instead and read the silhouettes." So the clock is
## stopped, the AnimationTree is put in manual callback mode and advanced by
## ZERO, and the only thing that differs between two rungs is one float.
##
## Apparatus lifted wholesale from tools/capture_stand_ladder.gd, deliberately:
## the number this produces has to be comparable with the 934 px / 11.1% that
## harness measured for the frostbitten hands and the 4323 px / 44.0% the hunch
## probe measured on the donor rig. A second measuring tool would have made
## three numbers that cannot be put in one table.
##
## The footprint is measured against a PLATE -- one frame with the man hidden --
## rather than against a luminance threshold. He is cel-shaded, so a threshold
## returns a dither of the shade band with holes through the middle of him, and
## the difference between two rungs is then dominated by interior speckle. A
## plate difference is solid by construction, needs no threshold anybody chose,
## and includes his cast shadow, which is part of what he puts on the screen.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## The rungs. Dense across the whole axis, because where the silhouette changes
## character is the thing being looked for and it cannot be assumed to be near
## either end.
const RUNGS: Array[float] = [0.00, 0.15, 0.30, 0.45, 0.60, 0.70, 0.80, 0.90, 1.00]

## Everything is measured from rung 0.00 -- a fed man's stand -- because that is
## what a viewer is being asked to notice a difference from.
const REFERENCE := 0.00

## What `chill` holds while the hunger ladder is stepped.
##
## IDLE_CHILL_FLOOR, which is where a WARM man already stands: a man outdoors in
## this weather is never perfectly still, so two thirds of the cold huddle is in
## the body before hunger says anything. Stepping the hunch against chill 0 would
## measure it against a pose the game never draws and flatter it.
const WARM_STAND := PlayerControllerScript.IDLE_CHILL_FLOOR

## The states the postures sheet asks a viewer to tell apart. Each is
## [label, stat, value] -- one stat taken down, everything else put back up, so
## each figure is that reading and nothing else.
##
## `cold+hungry` is last and is the disclosure: the two readouts share one body
## and the graph puts the hunch downstream, so it is the composite rather than
## either half.
const POSTURES: Array = [
	["fed warm rested", &"", 1.0],
	["cold", &"core_temperature", 0.05],
	["tired", &"fatigue", 0.01],
	["hungry", &"hunger", 0.01],
	["cold+hungry", &"", 0.0],
]

const SETTLE_FRAMES := 90
const CROP := Vector2i(120, 150)
const ZOOM := 3
const JND := 2.0 / 255.0
const PLATE_EPS := 2.0 / 255.0

var _out := "user://hunch"
var _mode := "ladder"
var _player: PlayerController = null
var _body = null
var _camera: Camera3D = null
var _tree: AnimationTree = null
var _frames := 0
var _done := false
var _crops: Array[Image] = []
var _masks: Array = []
var _stats: Array = []
var _labels: Array = []
var _centre := Vector2i.ZERO
var _plate: Image = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--mode" and index + 1 < args.size():
			_mode = args[index + 1]
	_player = get_node_or_null("Main/Player") as PlayerController
	if _player == null:
		push_error("capture_hunch_ladder: scenes/main.tscn has no Player")
		get_tree().quit(1)
		return
	_body = SurvivalSystemScript.new()
	_body.load_from_directory()
	_body.start()
	_player.set_survival_system(_body)
	# The eases are asymmetric on purpose and both are slow -- hunger takes ten
	# seconds to arrive, which is right in play and is six hundred physics frames
	# in a harness. Opened up so the state under test is reached rather than
	# photographed halfway there. The SHIPPING path is otherwise untouched: the
	# controller still computes the target from the channel and still eases to it.
	_player.hunch_rise = 100.0
	_player.hunch_fall = 100.0


func _exit_tree() -> void:
	if _body != null:
		_body.free()


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_done = true
	_run()


func _run() -> void:
	_pin_camera()
	if _mode == "postures":
		await _shoot_postures()
	else:
		_freeze()
		await _shoot_ladder()
	_measure()
	_write()
	get_tree().quit()


func _pin_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.call("snap_to_target")
	# Stopped, not merely snapped: the rig eases toward its target every frame and
	# a frame that drifts between rungs is not the same shot.
	rig.set_process(false)
	rig.set_physics_process(false)
	_camera = rig.get_node_or_null("Camera3D") as Camera3D


func _freeze() -> void:
	_player.set_physics_process(false)
	_player.set_process(false)
	_tree = _player.get_node_or_null("Gait") as AnimationTree
	if _tree != null:
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_hush(get_tree().root)


func _hush(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu := node as GPUParticles3D
		gpu.emitting = false
		gpu.speed_scale = 0.0
		gpu.visible = false
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.emitting = false
		cpu.speed_scale = 0.0
		cpu.visible = false
	for child in node.get_children():
		_hush(child)


func _locate() -> void:
	# Briefing trap 10: unproject_position() answers in the 1152x720 stretch
	# canvas while the saved PNG is the 1600x1000 window, and cropping at the raw
	# value lands 215 px away from the man and measures his shadow.
	var canvas := get_viewport().get_visible_rect().size
	var shot := Vector2(DisplayServer.window_get_size())
	var at := _camera.unproject_position(_player.global_position + Vector3(0.0, 0.9, 0.0))
	_centre = Vector2i(at * Vector2(shot.x / maxf(canvas.x, 1.0), shot.y / maxf(canvas.y, 1.0)))
	var top := _camera.unproject_position(_player.global_position + Vector3(0.0, 1.88, 0.0))
	var foot := _camera.unproject_position(_player.global_position)
	var scale: float = shot.y / maxf(canvas.y, 1.0)
	print("capture_hunch_ladder: window %s; a 1.88 m man projects %.1f px, %.1f%% of the frame" % [
		DisplayServer.window_get_size(), absf(top.y - foot.y) * scale,
		100.0 * absf(top.y - foot.y) * scale / maxf(shot.y, 1.0),
	])


func _take_plate() -> void:
	_player.visible = false
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()
	plate.convert(Image.FORMAT_RGBA8)
	_plate = _crop(plate)
	_player.visible = true


func _shoot_ladder() -> void:
	_locate()
	await _take_plate()
	for rung in RUNGS:
		_player.chill = WARM_STAND
		if _tree != null:
			_tree.set(&"parameters/chill/blend_amount", WARM_STAND)
			_tree.set(&"parameters/hunch/blend_amount", rung)
			# Zero, so the take does not advance: same frame, same clips, one float
			# different.
			_tree.advance(0.0)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		_crops.append(_crop(image))
		_stats.append(_posture())
		_labels.append("%.2f" % rung)
	_check_the_walk_is_untouched()


## The defect a filtered blend could ship silently.
##
## `hunch` filters the spine chain, and a filter changes which INPUT supplies a
## track rather than how much of it there is. If Godot's FILTER_BLEND passed the
## unfiltered paths at full weight instead of at the weight the graph handed it,
## the standing branch's arms would bleed through the walk -- a man walking with
## an idle's arms, at every hunger value, which reads as a broken animation
## rather than as a wiring fault.
##
## So: force `motion` fully onto the locomotion branch and step the hunger blend
## through its whole range. The pose must not move at all.
func _check_the_walk_is_untouched() -> void:
	if _tree == null:
		return
	print("")
	print("--- and the walk, with the same rungs, which must not move ---")
	var line := PackedStringArray()
	var first := Vector3.ZERO
	var worst := 0.0
	for rung in RUNGS:
		_tree.set(&"parameters/motion/blend_amount", 1.0)
		_tree.set(&"parameters/hunch/blend_amount", rung)
		_tree.advance(0.0)
		var here := _hand_of(_player)
		if rung == RUNGS[0]:
			first = here
		worst = maxf(worst, (here - first).length())
		line.append("%.2f %.4f" % [rung, (here - first).length()])
	print("  left hand, metres from where rung 0.00 put it: " + " | ".join(line))
	print("  worst %.4f m -- anything but zero means the filter is leaking into the walk"
		% worst)
	_tree.set(&"parameters/motion/blend_amount", 0.0)


func _hand_of(player: Node) -> Vector3:
	var skeleton := _skeleton(player)
	if skeleton == null:
		return Vector3.ZERO
	var hips := skeleton.find_bone("Hips")
	var hand := skeleton.find_bone("LeftHand")
	if hips < 0 or hand < 0:
		return Vector3.ZERO
	return (skeleton.get_bone_global_pose(hand).origin
		- skeleton.get_bone_global_pose(hips).origin)


## The postures, each driven through the real survival model and the real
## controller -- no AnimationTree parameter is written by hand here.
func _shoot_postures() -> void:
	_locate()
	_freeze()
	# Everything else in the valley stops too, and this node keeps running.
	# Without it the wind, the snow field and the sky advance between shots, and
	# the plate difference would then hold pixels that are not the man -- two
	# frames that are not of the same thing, which is the briefing's own
	# condition for a comparison being evidence.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	await _take_plate()
	for row in POSTURES:
		_set_state(row[1], float(row[2]), String(row[0]) == "cold+hungry")
		# Driven through the controller's own physics tick rather than by writing
		# an AnimationTree parameter, so what is photographed is what the shipping
		# path produces: the channel, the remap, the ease and the blend all run.
		for _step in range(4):
			_player._physics_process(1.0 / 60.0)
		if _tree != null:
			_tree.advance(0.0)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		_crops.append(_crop(image))
		_stats.append(_posture())
		_labels.append(String(row[0]))
		print("  %-16s core %.2f hunger %.2f fatigue %.2f | carriage %.2f chill %.2f hunch %.2f" % [
			row[0], _body.fraction_of(&"core_temperature"), _body.fraction_of(&"hunger"),
			_body.fraction_of(&"fatigue"), _player.carriage_ceiling(),
			_player.stand_chill(), _player.hunch_blend(),
		])


## One stat down, everything else back to full.
##
## `restore()` after the drop rather than a modifier before it: dropping a stat
## means integrating the model, and integrating drains the other four -- a
## "hungry" figure would quietly also be a cold one, and the picture would be
## of two readouts at once. This is the same trap test_body_readouts.gd records
## having fallen into with the breath.
func _set_state(stat: StringName, value: float, both: bool) -> void:
	for id in _body.stat_ids():
		_body.restore(id, 2.0)
	if both:
		_drop_to(&"core_temperature", 0.05)
		_drop_to(&"hunger", 0.01)
		for id in [&"fatigue", &"thirst", &"frostbite_hands", &"frostbite_feet"]:
			_body.restore(id, 2.0)
		return
	if String(stat) == "":
		return
	_drop_to(stat, value)
	for id in _body.stat_ids():
		if id != stat:
			_body.restore(id, 2.0)


func _drop_to(stat: StringName, value: float) -> void:
	_body.push_modifier(stat, &"capture_drop", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while _body.value_of(stat) > value and not _body.is_dead() and guard < 20000:
		_body.advance(0.25)
		guard += 1
	_body.remove_source(&"capture_drop")


func _crop(image: Image) -> Image:
	var size := image.get_size()
	var rect := Rect2i(
		clampi(_centre.x - CROP.x, 0, maxi(size.x - CROP.x * 2, 0)),
		clampi(_centre.y - CROP.y, 0, maxi(size.y - CROP.y * 2, 0)),
		mini(CROP.x * 2, size.x), mini(CROP.y * 2, size.y)
	)
	var out := Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(image, rect, Vector2i.ZERO)
	return out


## What this body is doing, off its own skeleton: the lean of the hips-to-head
## line in degrees, and how far the head has dropped and come forward in cm.
##
## The same quantity tools/measure_hand_gesture.gd reports, so these numbers sit
## in the same table as the 34.9 degrees the donor take holds and the 1.9 / 14.6
## the wanderer's own two idles measure.
func _posture() -> Array:
	var skeleton := _skeleton(_player)
	if skeleton == null:
		return [0.0, 0.0, 0.0, 0.0]
	var hips := skeleton.find_bone("Hips")
	var head := skeleton.find_bone("Head")
	if hips < 0 or head < 0:
		return [0.0, 0.0, 0.0, 0.0]
	var up := (skeleton.get_bone_global_rest(head).origin
		- skeleton.get_bone_global_rest(hips).origin)
	var scale := 188.0 / _rest_height(skeleton, up.normalized())
	var offset := (skeleton.get_bone_global_pose(head).origin
		- skeleton.get_bone_global_pose(hips).origin)
	var along := offset.dot(up.normalized())
	var across := (offset - up.normalized() * along).length()
	# ...and the claim that has to be true in PIXELS rather than in centimetres:
	# the hunch is supposed to change the figure's HEIGHT, which is the property
	# that makes it readable with no second man to compare against. Measured off
	# the camera, converted out of the stretch canvas into window pixels
	# (briefing trap 10), and NOT off the footprint's bounding box -- that box
	# includes his cast shadow, which grows as he leans and would report a
	# hunched man as a TALLER one.
	var canvas := get_viewport().get_visible_rect().size
	var shot := Vector2(DisplayServer.window_get_size())
	var to_pixels: float = shot.y / maxf(canvas.y, 1.0)
	var crown := _camera.unproject_position(
		skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	).y * to_pixels
	var ground := _camera.unproject_position(_player.global_position).y * to_pixels
	return [rad_to_deg(atan2(across, along)), along * scale, across * scale, ground - crown]


func _rest_height(skeleton: Skeleton3D, up: Vector3) -> float:
	var top := -INF
	var bottom := INF
	for index in range(skeleton.get_bone_count()):
		var along := skeleton.get_bone_global_rest(index).origin.dot(up)
		top = maxf(top, along)
		bottom = minf(bottom, along)
	return maxf(top - bottom, 0.0001)


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null


## The widest channel's difference. Max rather than mean: a shift confined to one
## channel is still visible, and averaging across three divides it by three and
## calls it invisible.
func _apart(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	var w := image.get_width()
	out.resize(w * image.get_height())
	for y in range(image.get_height()):
		for x in range(w):
			out[y * w + x] = 1 if _apart(
				image.get_pixel(x, y), _plate.get_pixel(x, y)
			) > PLATE_EPS else 0
	return out


func _measure() -> void:
	for crop in _crops:
		_masks.append(_mask(crop))
	var width: int = _crops[0].get_width()
	var reference := 0 if _mode == "postures" else RUNGS.find(REFERENCE)
	print("")
	if _mode == "postures":
		print("--- the three readouts, one body, at the game's own framing ---")
		print("xor is against the fed warm rested figure: how much of his outline moved.")
	else:
		print("--- the hunger ladder, at the game's own framing ---")
		print("chill is held at %.2f (IDLE_CHILL_FLOOR) so the rungs measure what hunger" % WARM_STAND)
		print("ADDS to the stand a warm man already has. xor is against rung 0.00.")
	print("%-16s %7s %6s %6s %8s %7s %9s %7s %8s %8s %8s" % [
		"rung", "area", "w px", "h px", "xor px", "xor %", "changed", "lean", "head up",
		"head fwd", "crown px",
	])
	for index in range(_crops.size()):
		var mask: PackedByteArray = _masks[index]
		var area := 0
		var min_x := width
		var max_x := -1
		var min_y := 1 << 30
		var max_y := -1
		for i in range(mask.size()):
			if mask[i] == 0:
				continue
			area += 1
			min_x = mini(min_x, i % width)
			max_x = maxi(max_x, i % width)
			min_y = mini(min_y, i / width)
			max_y = maxi(max_y, i / width)
		var xor_count := 0
		var changed := 0
		if reference >= 0:
			var base: PackedByteArray = _masks[reference]
			var base_image: Image = _crops[reference]
			var here: Image = _crops[index]
			for i in range(mask.size()):
				if mask[i] != base[i]:
					xor_count += 1
			for y in range(here.get_height()):
				for x in range(width):
					if _apart(here.get_pixel(x, y), base_image.get_pixel(x, y)) > JND:
						changed += 1
		var stat: Array = _stats[index]
		print("%-16s %7d %6d %6d %8d %6.1f%% %9d %7.1f %8.1f %8.1f %8.1f" % [
			_labels[index], area, maxi(max_x - min_x + 1, 0), maxi(max_y - min_y + 1, 0),
			xor_count, 100.0 * float(xor_count) / maxf(float(area), 1.0), changed,
			float(stat[0]), float(stat[1]), float(stat[2]), float(stat[3]),
		])
	if _mode == "postures":
		_measure_pairs(width)


## Every pair against every other, because "can a viewer tell these apart" is a
## question about PAIRS and a column of differences from one baseline cannot
## answer it. Two figures that both differ from the baseline by 30% may be
## identical to each other.
func _measure_pairs(width: int) -> void:
	print("")
	print("--- every posture against every other: how much outline separates them ---")
	print("%-16s %-16s %8s %8s" % ["a", "b", "xor px", "of a"])
	for i in range(_masks.size()):
		for j in range(i + 1, _masks.size()):
			var a: PackedByteArray = _masks[i]
			var b: PackedByteArray = _masks[j]
			var diff := 0
			var area := 0
			for k in range(a.size()):
				if a[k] != b[k]:
					diff += 1
				if a[k] == 1:
					area += 1
			print("%-16s %-16s %8d %7.1f%%" % [
				_labels[i], _labels[j], diff, 100.0 * float(diff) / maxf(float(area), 1.0),
			])
	print("")
	print("(the frostbitten-hands readout, whole, same camera and metric: 934 px, 11.1%%;")
	print(" width above is the crop's %d px)" % width)


func _write() -> void:
	var w: int = _crops[0].get_width()
	var h: int = _crops[0].get_height()
	var count := _crops.size()
	var sheet := Image.create_empty(w * ZOOM * count, h * ZOOM, false, Image.FORMAT_RGBA8)
	var silhouettes := Image.create_empty(w * ZOOM * count, h * ZOOM, false, Image.FORMAT_RGBA8)
	for index in range(count):
		var big: Image = _crops[index].duplicate()
		big.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(big, Rect2i(0, 0, w * ZOOM, h * ZOOM), Vector2i(w * ZOOM * index, 0))
		var flat := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		var mask: PackedByteArray = _masks[index]
		for y in range(h):
			for x in range(w):
				flat.set_pixel(x, y, Color.BLACK if mask[y * w + x] == 1 else Color.WHITE)
		flat.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
		silhouettes.blit_rect(flat, Rect2i(0, 0, w * ZOOM, h * ZOOM), Vector2i(w * ZOOM * index, 0))
	sheet.save_png("%s_%s_sheet.png" % [_out, _mode])
	silhouettes.save_png("%s_%s_masks.png" % [_out, _mode])

	# 1:1, and it is the only honest place to judge whether a difference is one a
	# player would notice: the magnified sheet draws the man three times the size
	# the game ever does, and two agents on this project have already judged a
	# readout from a diagnostic view.
	var gap := 8
	var strip := Image.create_empty((w + gap) * count - gap, h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(1, 1, 1, 1))
	for index in range(count):
		strip.blit_rect(_crops[index], Rect2i(0, 0, w, h), Vector2i((w + gap) * index, 0))
	strip.save_png("%s_%s_true_scale.png" % [_out, _mode])
	print("")
	print("wrote %s_%s_sheet.png (3x), %s_%s_masks.png, %s_%s_true_scale.png (1:1)" % [
		_out, _mode, _out, _mode, _out, _mode,
	])
	print("the 1:1 strip is in the order printed above and carries no labels, which is")
	print("the only form in which the question 'can you tell which is which' can be put.")
