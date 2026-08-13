extends Node

## What a TORSO is worth at the game's framing, measured the same way a HAND was.
##
##   Godot_console.exe --path <project> res://tools/capture_hunch_probe.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/hunch
##
## ---------------------------------------------------------------------------
## THE QUESTION
## ---------------------------------------------------------------------------
## tools/capture_stand_ladder.gd measured the whole frostbitten-hands readout at
## 934 pixels of moved outline -- 11.1% of the man's footprint -- because the two
## poses it blends between are both "arms held in front of the chest" and the
## readout owns only the top third of that blend.
##
## The alternative on the table is a HELD HUNCH: 饥饿 as a man bent over when he
## stops, rather than as a hand somewhere. Before anyone spends money on
## authoring or retargeting one, the question "how much bigger is that, in the
## pixels a player actually gets" should have a number rather than an opinion.
##
## So this stands the RPG-Character rig -- which lives at
## assets/rigs/rpg_character/Unarmed.glb, and which measurement says holds a 34.9
## degree lean for the whole of `UnarmedIdleInjured` -- in the real scene, at the
## real camera, and measures its two idles against each other with the identical
## plate-difference apparatus the hands ladder used. Same camera, same shot, same
## metric: the two numbers are comparable, which is the entire point of not
## writing a second measuring tool.
##
## THIS IS A PROBE, NOT A PROPOSAL. The rig is not the wanderer and nothing here
## retargets anything. It answers one question -- is the difference between a
## hunch and a stand worth materially more than the difference between two
## versions of hands-at-the-chest -- and then stops.

## Defaults are the RPG-Character pack, now under assets/rigs/ and tracked. It was
## loose in the project root when this probe was written.
##
## KNOWN LIMIT, AND ONE ATTEMPT AT REMOVING IT THAT DID NOT WORK
## ------------------------------------------------------------
## Unarmed.glb ships a proxy body -- no head mesh, splayed A-pose legs -- so its
## footprint is the proxy's and not the wanderer's. Both poses are of the SAME
## proxy under the same material, so the ratio between them stands; the absolute
## area does not, and a parka would hide more limb travel than a bare proxy does,
## which makes the percentage an upper bound rather than an estimate.
##
## The obvious fix was to run the same measurement on the wanderer's own rig,
## which measurement says holds a 37.1 degree lean through the whole of
## `crouch_creep`:
##
##     --model res://assets/models/characters/winter_wanderer.glb
##     --neutral idle --hunched crouch_creep --turn 0
##
## IT IS NOT A VALID COMPARISON AND THE NUMBER IT PRINTS (132.3%) SHOULD NOT BE
## QUOTED. Two reasons, both visible the moment the capture is looked at rather
## than read:
##
##   1. A raw instance of the model carries no material -- PlayerController
##      applies the cel material at build time -- so the figure renders WHITE on
##      snow. Its footprint came out 17998 px against the real player's 8603 for
##      the same body at the same framing.
##   2. `crouch_creep` is a locomotion take. The legs are apart and the body is
##      displaced sideways, so the two silhouettes barely overlap (7376 px of
##      intersection on footprints of 18000 and 20562) and the XOR exceeds 100%
##      of either. That is two poses in different PLACES, not one posture
##      against another.
##
## Left documented rather than deleted because it is the cheap mistake to make
## twice: the flags are still here, they still run, and the output still looks
## like a measurement.
const MODEL := "res://assets/rigs/rpg_character/Unarmed.glb"
const NEUTRAL := "UnarmedIdle"
const HUNCHED := "UnarmedIdleInjured"

const SETTLE_FRAMES := 90
const CROP := Vector2i(120, 150)
const ZOOM := 3
const PLATE_EPS := 2.0 / 255.0

var _out := "user://hunch"
var _model := MODEL
var _neutral := NEUTRAL
var _hunched := HUNCHED
var _turn := PI
var _player = null
var _camera: Camera3D = null
var _frames := 0
var _done := false
var _plate: Image = null
var _crops: Array[Image] = []
var _masks: Array = []
var _centre := Vector2i.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--model" and index + 1 < args.size():
			_model = args[index + 1]
		elif args[index] == "--neutral" and index + 1 < args.size():
			_neutral = args[index + 1]
		elif args[index] == "--hunched" and index + 1 < args.size():
			_hunched = args[index + 1]
		elif args[index] == "--turn" and index + 1 < args.size():
			_turn = deg_to_rad(float(args[index + 1]))
	_player = get_node_or_null("Main/Player")


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_done = true
	_run()


func _run() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null or _player == null:
		push_error("capture_hunch_probe: no CameraRig or no Player in scenes/main.tscn")
		get_tree().quit(1)
		return
	rig.call("snap_to_target")
	rig.set_process(false)
	rig.set_physics_process(false)
	_camera = rig.get_node_or_null("Camera3D") as Camera3D
	_player.set_physics_process(false)
	_player.set_process(false)
	_hush(get_tree().root)
	await _shoot()
	_measure()
	get_tree().quit()


func _hush(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
		(node as GPUParticles3D).visible = false
	elif node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
		(node as CPUParticles3D).visible = false
	for child in node.get_children():
		_hush(child)


func _shoot() -> void:
	# The wanderer steps out of the picture entirely: this probe is about the
	# stand-in, and two figures in one frame would make every footprint number
	# the sum of two men.
	_player.visible = false
	var stand_in := _stand_in()
	if stand_in == null:
		get_tree().quit(1)
		return
	var canvas := get_viewport().get_visible_rect().size
	var shot := Vector2(DisplayServer.window_get_size())
	# Canvas space -> PNG pixels. Briefing trap 10: unproject_position() answers
	# in the 1152x720 stretch canvas while the saved frame is the 1600x1000
	# window, and cropping at the raw value lands 215 px away from the man.
	var at := _camera.unproject_position(
		(stand_in as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	)
	_centre = Vector2i(at * Vector2(shot.x / maxf(canvas.x, 1.0), shot.y / maxf(canvas.y, 1.0)))
	stand_in.visible = false
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()
	plate.convert(Image.FORMAT_RGBA8)
	_plate = _crop(plate)
	stand_in.visible = true

	var player := _first(stand_in, "AnimationPlayer") as AnimationPlayer
	# The wanderer's takes are renamed on import; every other pack keeps the
	# names it shipped with.
	if _model == WandererAnimations.MODEL_PATH:
		if player.has_animation_library(&""):
			player.remove_animation_library(&"")
		player.add_animation_library(&"", WandererAnimations.build())
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for take in [_neutral, _hunched]:
		if not player.has_animation(take):
			push_error("capture_hunch_probe: %s has no take %s" % [_model, take])
			get_tree().quit(1)
			return
		player.play(take)
		# Halfway through, so neither pose is caught on a keyframe boundary. Both
		# takes hold their posture for their whole length -- measured -- so the
		# instant is not load bearing, and saying which one it was is cheaper
		# than arguing about it later.
		player.seek(player.get_animation(take).length * 0.5, true)
		player.advance(0.0)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		_crops.append(_crop(image))
		image.save_png("%s_%s.png" % [_out, take])


## The RPG-Character rig, scaled to the 1.88 m PlayerController builds and stood
## exactly where the wanderer was standing, facing the way he faced.
func _stand_in() -> Node3D:
	if not ResourceLoader.exists(_model):
		push_error("capture_hunch_probe: %s is not in the project" % _model)
		return null
	var scene := ResourceLoader.load(_model) as PackedScene
	var node := scene.instantiate() as Node3D
	_player.get_parent().add_child(node)
	node.global_transform = (_player as Node3D).global_transform
	var skeleton := _first(node, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("capture_hunch_probe: %s has no Skeleton3D" % _model)
		return null
	# Scaled off the SKELETON's rest pose, not off Mesh.get_aabb(): the AABB
	# reports these rigs at about 1/100 of life size (briefing trap 15.3), and a
	# scale derived from it would be out by two orders of magnitude.
	var top := -INF
	var bottom := INF
	for index in range(skeleton.get_bone_count()):
		var y: float = skeleton.get_bone_global_rest(index).origin.y
		top = maxf(top, y)
		bottom = minf(bottom, y)
	var height := maxf(top - bottom, 0.0001)
	# The rig's own local scale is already on the instanced node; this multiplies
	# it rather than replacing it, so whatever the exporter did is preserved.
	var local: float = 1.88 / (height * skeleton.global_transform.basis.get_scale().y)
	node.scale = node.scale * local
	print("capture_hunch_probe: %s rest height %.3f rig units, scaled by %.4f" % [
		_model, height, local,
	])
	# The RPG rig faces -Z and the wanderer faces +Z -- measured off the rest
	# pose by tools/measure_hand_gesture.gd, which reports fwd (-0.03 0.00 -1.00)
	# for this pack and (+0.01 +0.18 +0.98) for the wanderer. Half a turn puts
	# the stand-in's back to the camera the way the player's is.
	node.rotate_y(_turn)
	return node


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


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


func _apart(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	var w := image.get_width()
	out.resize(w * image.get_height())
	for y in range(image.get_height()):
		for x in range(w):
			out[y * w + x] = 1 if _apart(image.get_pixel(x, y), _plate.get_pixel(x, y)) > PLATE_EPS else 0
	return out


func _measure() -> void:
	for crop in _crops:
		_masks.append(_mask(crop))
	var w: int = _crops[0].get_width()
	var names := [_neutral, _hunched]
	print("")
	print("--- a torso, measured exactly as the hand was ---")
	print("%-22s %8s %6s %6s" % ["take", "area", "w px", "h px"])
	for index in range(_masks.size()):
		var mask: PackedByteArray = _masks[index]
		var area := 0
		var min_x := w
		var max_x := -1
		var min_y := 1 << 30
		var max_y := -1
		for i in range(mask.size()):
			if mask[i] == 0:
				continue
			area += 1
			min_x = mini(min_x, i % w)
			max_x = maxi(max_x, i % w)
			min_y = mini(min_y, i / w)
			max_y = maxi(max_y, i / w)
		print("%-22s %8d %6d %6d" % [
			names[index], area, maxi(max_x - min_x + 1, 0), maxi(max_y - min_y + 1, 0),
		])
	var a: PackedByteArray = _masks[0]
	var b: PackedByteArray = _masks[1]
	var diff := 0
	var area := 0
	for i in range(a.size()):
		if a[i] != b[i]:
			diff += 1
		if a[i] == 1:
			area += 1
	print("")
	print("%s against %s: %d px of outline moved, %.1f%% of the footprint" % [
		_hunched, _neutral, diff, 100.0 * float(diff) / maxf(float(area), 1.0),
	])
	print("(the frostbitten-hands readout, whole, on the same camera with the")
	print(" same metric: 934 px, 11.1%)")
	var sheet := Image.create_empty(w * ZOOM * _crops.size(), _crops[0].get_height() * ZOOM,
		false, Image.FORMAT_RGBA8)
	var strip := Image.create_empty(w * _crops.size() + 8, _crops[0].get_height(),
		false, Image.FORMAT_RGBA8)
	strip.fill(Color(1, 1, 1, 1))
	for index in range(_crops.size()):
		var big: Image = _crops[index].duplicate()
		big.resize(w * ZOOM, _crops[0].get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()),
			Vector2i(big.get_width() * index, 0))
		strip.blit_rect(_crops[index], Rect2i(0, 0, w, _crops[0].get_height()),
			Vector2i((w + 8) * index, 0))
	sheet.save_png("%s_sheet.png" % _out)
	strip.save_png("%s_true_scale.png" % _out)
	print("wrote %s_sheet.png (3x) and %s_true_scale.png (1:1)" % [_out, _out])
