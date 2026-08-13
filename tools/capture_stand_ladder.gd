extends Node

## The stand blend, stepped at ONE INSTANT, photographed from the game's camera,
## and the silhouette measured in the pixels a player actually gets.
##
##   Godot_console.exe --path <project> res://tools/capture_stand_ladder.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/stand
##
## ---------------------------------------------------------------------------
## WHY THE BLEND AND NOT THE TIME
## ---------------------------------------------------------------------------
## The briefing's own instrument note: "A contact sheet stepping TIME at one
## blend value cannot show this -- every frame looks like a plausible pose. Step
## the BLEND value at one instant instead and read the silhouettes."
##
## So the clock is stopped and the only thing that moves between rungs is
## `parameters/chill/blend_amount`. The AnimationTree is put in manual callback
## mode and advanced by zero, which applies the new parameter to the same frame
## of the same take -- the two rungs are the same shot by construction, which is
## the briefing's condition for a comparison being evidence.
##
## Every particle system in the scene is stopped for the same reason. Breath
## vapour, snowfall and the lens flakes are not functions of the blend, so any
## pixel they move is noise in the one number this harness exists to produce.
## The snow ON HIS SHOULDERS stays -- it is static, identical across rungs, and
## part of the silhouette a player reads.
##
## ---------------------------------------------------------------------------
## WHAT IS MEASURED
## ---------------------------------------------------------------------------
## Bone positions answer "did the pose change". They do not answer "can it be
## seen", which is the question, so the silhouette is measured in the frame:
##
##   area      his footprint -- every pixel he contributes to the frame
##   w, h      the bounding box of it
##   xor       pixels inside one rung's footprint and outside the other's
##   changed   pixels whose COLOUR moved by more than a just-noticeable amount
##
## THE FOOTPRINT IS MEASURED AGAINST A PLATE, not against a luma threshold, and
## the first version of this harness got that wrong in a way worth recording. A
## threshold picks out "dark pixels", and this character is cel-shaded -- he has
## a lit half and a shade half -- so the mask came back as a dither of the shade
## band with holes through the middle of the man. The XOR between two rungs was
## then dominated by interior speckle wandering across the bands, and reported
## 49% of him changing when the outline had barely moved. A number can be exactly
## right about the wrong quantity.
##
## So the man is hidden for one frame, that plate is kept, and his footprint at
## every rung is simply where the frame differs from it. That is a solid region
## by construction, it needs no threshold chosen by anybody, and it includes his
## CAST SHADOW -- which is correct: the shadow is part of what he puts on the
## screen, and at this sun angle it is the larger part.
##
## `xor` is the headline. It is literally how much of the outline moved, in the
## units the acceptance question is asked in.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## The rungs. Dense through the range the readouts actually use so the threshold
## can be found, and taken to both ends so the whole axis is on the sheet.
const RUNGS: Array[float] = [0.00, 0.20, 0.40, 0.50, 0.60, 0.65, 0.75, 0.85, 1.00]

## Which rung everything is compared against. 0.65 is IDLE_CHILL_FLOOR -- where a
## warm man with sound hands already stands -- so a difference measured from here
## is exactly what the hands readout is able to add.
const REFERENCE := 0.65

## Frames of ordinary physics before the clock stops. Enough for the controller
## to have found the ground, resolved the snow field and settled its idle.
const SETTLE_FRAMES := 90

## Half-width and half-height of the crop taken around the figure, in pixels of
## the captured frame. Big enough to hold him and his arms at any rung, small
## enough that the sheet is readable.
const CROP := Vector2i(120, 150)

## Nearest-neighbour magnification for the contact sheet only. The NUMBERS are
## all measured at 1:1; this exists so a human can see what the numbers say.
const ZOOM := 3

var _out := "user://stand"
var _player: PlayerController = null
var _body = null
var _camera: Camera3D = null
var _tree: AnimationTree = null
var _frames := 0
var _done := false
var _crops: Array[Image] = []
var _masks: Array = []
var _stats: Array = []
var _centre := Vector2i.ZERO
var _plate: Image = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
	_player = get_node_or_null("Main/Player") as PlayerController
	if _player == null:
		push_error("capture_stand_ladder: scenes/main.tscn has no Player")
		get_tree().quit(1)
		return
	_body = SurvivalSystemScript.new()
	_body.load_from_directory()
	_body.start()
	_player.set_survival_system(_body)


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
	_freeze()
	await _shoot()
	_measure()
	_write()
	get_tree().quit()


# --- the shot -----------------------------------------------------------------

func _pin_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.call("snap_to_target")
	# Stopped, not merely snapped: the rig eases toward its target every frame,
	# and a frame that drifts between rungs is not the same shot.
	rig.set_process(false)
	rig.set_physics_process(false)
	_camera = rig.get_node_or_null("Camera3D") as Camera3D


## Stops the clock for everything that is not the blend.
func _freeze() -> void:
	# The controller writes chill from stand_chill() every physics frame, so it
	# would overwrite each rung before it was photographed.
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


## Anything below this and two pixels are the same colour to a viewer. 2/255 on
## the widest channel -- one step of an 8-bit ramp, which is what a PNG holds.
const JND := 2.0 / 255.0

## The colour distance at which a pixel counts as "he is here". The same one
## step: a difference smaller than the file can represent is not a difference.
const PLATE_EPS := 2.0 / 255.0


func _shoot() -> void:
	# Where he is on the screen, from the camera rather than from trigonometry --
	# working it out by hand got it backwards once on this project and produced a
	# reading of the wrong figure.
	#
	# ...AND THEN CONVERTED, WHICH IS BRIEFING TRAP 10. unproject_position()
	# answers in the viewport's 2D canvas space -- 1152x720 under this project's
	# `canvas_items` stretch -- while the saved PNG is the window, 1600x1000. The
	# first run of this harness cropped at the raw canvas coordinate, landed 215
	# px up and left of the man, and measured his SHADOW: 15 px wide, 118 tall,
	# which reads as a plausible figure right up until you look at the picture.
	var canvas := get_viewport().get_visible_rect().size
	var shot := Vector2(DisplayServer.window_get_size())
	var at := _camera.unproject_position(_player.global_position + Vector3(0.0, 0.9, 0.0))
	_centre = Vector2i(at * Vector2(shot.x / maxf(canvas.x, 1.0), shot.y / maxf(canvas.y, 1.0)))
	print("capture_stand_ladder: canvas %s, window %s, figure at canvas %s -> pixel %s" % [
		canvas, shot, at.round(), _centre,
	])
	# The plate: the same shot with nobody in it. Everything else in the scene is
	# already stopped, so the only difference between this and any rung below is
	# the man himself.
	_player.visible = false
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()
	plate.convert(Image.FORMAT_RGBA8)
	_report_frame(plate)
	_plate = _crop(plate)
	_player.visible = true
	for rung in RUNGS:
		_player.chill = rung
		if _tree != null:
			_tree.set(&"parameters/chill/blend_amount", rung)
			# Zero, so the take does not advance: the pose is the same frame of the
			# same clip at every rung and the blend is the only difference.
			_tree.advance(0.0)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		_crops.append(_crop(image))
		_stats.append(_hands())


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


func _report_frame(image: Image) -> void:
	# Window.size is the one of the three "screen size" APIs that describes the
	# saved PNG (briefing trap 10), and this is a claim about pixels a human sees.
	var top := _camera.unproject_position(_player.global_position + Vector3(0.0, 1.88, 0.0))
	var foot := _camera.unproject_position(_player.global_position)
	var canvas := get_viewport().get_visible_rect().size
	var scale: float = float(DisplayServer.window_get_size().y) / maxf(canvas.y, 1.0)
	var stature := absf(top.y - foot.y) * scale
	print("capture_stand_ladder: frame %dx%d, window %s" % [
		image.get_width(), image.get_height(), DisplayServer.window_get_size(),
	])
	print("  a 1.88 m man projects %.1f px of a %d px frame -- %.1f%%, against the" % [
		stature, image.get_height(), 100.0 * stature / float(image.get_height()),
	])
	print("  11.4%% CameraRig's own comment claims for the 10.5 m stop")


## Where this man's hands are, off his own skeleton, in centimetres over the hips.
func _hands() -> Array:
	var skeleton := _skeleton(_player)
	if skeleton == null:
		return [0.0, 0.0, 0.0]
	var hips := skeleton.find_bone("Hips")
	var left := skeleton.find_bone("LeftHand")
	var right := skeleton.find_bone("RightHand")
	if hips < 0 or left < 0 or right < 0:
		return [0.0, 0.0, 0.0]
	var root := skeleton.get_bone_global_pose(hips).origin
	var lh := skeleton.get_bone_global_pose(left).origin - root
	var rh := skeleton.get_bone_global_pose(right).origin - root
	return [lh.y, rh.y, (lh - rh).length()]


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null


# --- the silhouette -----------------------------------------------------------

## The widest channel's difference between two colours. Max rather than mean: a
## shift confined to one channel is still visible, and averaging it across three
## would divide it by three and call it invisible.
func _apart(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


## Where the man is: every pixel this frame differs from the plate.
func _mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	var w := image.get_width()
	out.resize(w * image.get_height())
	for y in range(image.get_height()):
		for x in range(w):
			var here := _apart(image.get_pixel(x, y), _plate.get_pixel(x, y))
			out[y * w + x] = 1 if here > PLATE_EPS else 0
	return out


func _measure() -> void:
	for crop in _crops:
		_masks.append(_mask(crop))
	var width: int = _crops[0].get_width()
	var reference := RUNGS.find(REFERENCE)
	print("")
	print("--- the ladder, at the game's own framing ---")
	print("reference rung is %.2f (IDLE_CHILL_FLOOR), against which xor and changed" % REFERENCE)
	print("are measured -- it is where a warm man with sound hands already stands,")
	print("so the 0.65 -> 1.00 rows ARE the whole hands readout.")
	print("%6s %7s %6s %6s %8s %7s %9s %8s %8s" % [
		"blend", "area", "w px", "h px", "xor px", "xor %", "changed", "hand y", "hands",
	])
	for index in range(RUNGS.size()):
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
			var x := i % width
			var y := i / width
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
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
		print("%6.2f %7d %6d %6d %8d %6.1f%% %9d %8.1f %8.1f" % [
			RUNGS[index], area, maxi(max_x - min_x + 1, 0), maxi(max_y - min_y + 1, 0),
			xor_count, 100.0 * float(xor_count) / maxf(float(area), 1.0), changed,
			float(stat[0]), float(stat[2]),
		])
	print("")
	print("--- rung against its neighbour, which is what a CHANGE would look like ---")
	print("%14s %9s %9s" % ["step", "xor px", "of area"])
	for index in range(1, RUNGS.size()):
		var a: PackedByteArray = _masks[index - 1]
		var b: PackedByteArray = _masks[index]
		var diff := 0
		var area := 0
		for i in range(a.size()):
			if a[i] != b[i]:
				diff += 1
			if b[i] == 1:
				area += 1
		print("%6.2f -> %.2f %9d %8.1f%%" % [
			RUNGS[index - 1], RUNGS[index], diff, 100.0 * float(diff) / maxf(float(area), 1.0),
		])


# --- the sheet ----------------------------------------------------------------

func _write() -> void:
	var w: int = _crops[0].get_width()
	var h: int = _crops[0].get_height()
	var sheet := Image.create_empty(w * ZOOM * RUNGS.size(), h * ZOOM, false, Image.FORMAT_RGBA8)
	var silhouettes := Image.create_empty(
		w * ZOOM * RUNGS.size(), h * ZOOM, false, Image.FORMAT_RGBA8
	)
	for index in range(_crops.size()):
		var big: Image = _crops[index].duplicate()
		big.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(big, Rect2i(0, 0, w * ZOOM, h * ZOOM), Vector2i(w * ZOOM * index, 0))
		# The mask on its own, which is the thing the numbers are of. Two flat
		# tones and nothing else -- an outline is much easier to compare against
		# another outline than a figure is against a figure.
		var flat := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		var mask: PackedByteArray = _masks[index]
		for y in range(h):
			for x in range(w):
				flat.set_pixel(x, y, Color.BLACK if mask[y * w + x] == 1 else Color.WHITE)
		flat.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
		silhouettes.blit_rect(
			flat, Rect2i(0, 0, w * ZOOM, h * ZOOM), Vector2i(w * ZOOM * index, 0)
		)
	sheet.save_png("%s_ladder.png" % _out)
	silhouettes.save_png("%s_masks.png" % _out)
	_write_true_scale(w, h)
	# ...and one untouched frame at the reference rung, so the sheet above can be
	# checked against the picture the game actually draws.
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	full.convert(Image.FORMAT_RGBA8)
	full.save_png("%s_frame.png" % _out)
	print("")
	print("wrote %s_ladder.png, %s_masks.png, %s_ab.png, %s_frame.png" % [
		_out, _out, _out, _out,
	])


## The three rungs that matter, at 1:1 and nothing else done to them.
##
## The magnified sheet is for finding WHERE the difference is. This is the only
## honest place to judge whether it is one a player would notice, because the
## magnified sheet shows a man three times the size the game ever draws him and
## a difference that is obvious at 3x can be nothing at 1x. Two agents on this
## project have now judged a readout from a diagnostic view.
func _write_true_scale(w: int, h: int) -> void:
	var picks: Array[int] = [RUNGS.find(0.00), RUNGS.find(REFERENCE), RUNGS.find(1.00)]
	var gap := 8
	var strip := Image.create_empty(
		(w + gap) * picks.size() - gap, h, false, Image.FORMAT_RGBA8
	)
	strip.fill(Color(1, 1, 1, 1))
	for index in range(picks.size()):
		var pick: int = picks[index]
		if pick < 0:
			continue
		strip.blit_rect(_crops[pick], Rect2i(0, 0, w, h), Vector2i((w + gap) * index, 0))
	strip.save_png("%s_ab.png" % _out)
