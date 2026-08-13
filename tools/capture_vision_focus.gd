extends Node

## 口渴's 画面轻微失焦, photographed from the game's camera and measured rather
## than looked at.
##
##   Godot_console.exe --path <project> res://tools/capture_vision_focus.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/focus [--mode probe|readout]
##
##   --mode probe     sweeps dof_blur_amount by hand. Answers "does depth of
##                    field do anything at all under an ORTHOGRAPHIC camera",
##                    which is not a question the docs answer and not one to
##                    take on trust.
##   --mode readout   drives the real thirst stat through the real VisionFocus
##                    consumer, which is the shipping path.
##
## ---------------------------------------------------------------------------
## THE METRIC
## ---------------------------------------------------------------------------
## Focus is high-frequency energy: a sharp picture has large differences between
## neighbouring pixels and a soft one does not. So the number is the mean
## absolute Laplacian of luminance,
##
##     |4*c - up - down - left - right|
##
## averaged over the frame, and reported as a PERCENTAGE OF THE SHARP FRAME so
## "17% of the detail is gone" is a sentence rather than a float.
##
## Measured in three windows as well as whole-frame, and that split is the point
## rather than a nicety: a depth-of-field blur is depth-graded by nature, and
## this project already has a depth-graded effect -- the air perspective. If the
## far window softens more than the near one, the defocus is a second aerial
## fade wearing a different name, and it will read as weather rather than as an
## eye. The three windows are what proves it uniform.
##
## The palette is sampled too. Trap 7 on this project is a colour that reaches
## the screen squared because two stages both applied it; a post-process pass
## that quietly regrades the frame would be the same class of defect, and the
## only way to know is to read the hexes back.

const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

const SETTLE_FRAMES := 90

## Raw dof_blur_amount values for --mode probe. Starts at zero so the sweep
## carries its own control.
const PROBE_AMOUNTS: Array[float] = [0.0, 0.002, 0.004, 0.006, 0.008, 0.010, 0.015, 0.020]

var _out := "user://focus"
var _mode := "probe"
var _player = null
var _body = null
var _camera: Camera3D = null
var _frames := 0
var _done := false
var _sharp := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--mode" and index + 1 < args.size():
			_mode = args[index + 1]
	_player = get_node_or_null("Main/Player")


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
	_hush(get_tree().root)
	if _camera == null:
		push_error("capture_vision_focus: no Camera3D under Main/CameraRig")
		get_tree().quit(1)
		return
	if _mode == "readout":
		await _readout()
	else:
		await _probe()
	get_tree().quit()


func _pin_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.call("snap_to_target")
	rig.set_process(false)
	rig.set_physics_process(false)
	_camera = rig.get_node_or_null("Camera3D") as Camera3D
	if _player != null:
		_player.set_physics_process(false)
		_player.set_process(false)


## Everything that moves on its own is stopped, so two frames differ only by the
## thing under test -- the briefing's condition for a comparison being evidence.
func _hush(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
		(node as GPUParticles3D).speed_scale = 0.0
	elif node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
		(node as CPUParticles3D).speed_scale = 0.0
	for child in node.get_children():
		_hush(child)


# --- probe --------------------------------------------------------------------

func _probe() -> void:
	print("--- does depth of field do anything under an ORTHOGRAPHIC camera? ---")
	print("camera projection %s, size %.2f, near %.2f, far %.1f" % [
		"ORTHOGONAL" if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "PERSPECTIVE",
		_camera.size, _camera.near, _camera.far,
	])
	# THE CONTROL COMES FIRST, AND IT IS `attributes = null` RATHER THAN
	# `dof_blur_amount = 0`. Assigning a CameraAttributes at all brings an
	# exposure_multiplier and an auto-exposure block with it, and trap 7 on this
	# project is a colour that reached the screen squared because two stages both
	# applied it and it looked like art direction. A sweep whose zero already has
	# the object attached cannot see that.
	_camera.attributes = null
	await RenderingServer.frame_post_draw
	var control := get_viewport().get_texture().get_image()
	control.convert(Image.FORMAT_RGBA8)
	_report(control, "no CameraAttributes at all (control)", true)
	control.save_png("%s_probe_control.png" % _out)

	var attributes := CameraAttributesPractical.new()
	# The same settings the shipping consumer uses, so the calibration this sweep
	# produces is a calibration OF IT and not of a different configuration that
	# happened to be convenient here.
	VisionFocus.configure(attributes)
	_camera.attributes = attributes
	for amount in PROBE_AMOUNTS:
		attributes.dof_blur_amount = amount
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		_report(image, "dof_blur_amount %.4f" % amount, false)
		image.save_png("%s_probe_%04d.png" % [_out, int(amount * 10000.0)])
	_camera.attributes = null


# --- readout ------------------------------------------------------------------

## The shipping path: a real thirsty man, the real consumer, the real camera.
func _readout() -> void:
	var focus := _find_focus(get_tree().root)
	if focus == null:
		push_error("capture_vision_focus: nothing in the tree answers as a VisionFocus")
		get_tree().quit(1)
		return
	_body = SurvivalSystemScript.new()
	_body.load_from_directory()
	_body.start()
	focus.set_survival_system(_body)
	print("--- 口渴 through the shipping consumer ---")
	for row in [["slaked", 1.0], ["thirsty", 0.20]]:
		var want: float = row[1]
		if want < 1.0:
			_drop_to(_body, &"thirst", want)
		# Settled outright rather than eased in, so the two frames differ by the
		# stat and not by where the ease happens to have got to.
		focus.settle_now()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		var label := "%-8s thirst %.3f  vision:focus %.3f  blur %.4f" % [
			row[0], _body.fraction_of(&"thirst"),
			_body.channel_value(&"vision:focus", 1.0), focus.blur(),
		]
		_report(image, label, want >= 1.0)
		image.save_png("%s_%s.png" % [_out, row[0]])


func _drop_to(body, stat_id: StringName, value: float) -> void:
	body.push_modifier(stat_id, &"capture", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while body.fraction_of(stat_id) > value and not body.is_dead() and guard < 40000:
		body.advance(0.25)
		guard += 1
	body.remove_source(&"capture")


func _find_focus(node: Node) -> Node:
	if node.has_method("blur") and node.has_method("settle_now"):
		return node
	for child in node.get_children():
		var found := _find_focus(child)
		if found != null:
			return found
	return null


# --- the measurement ----------------------------------------------------------

## Three windows, in fractions of the frame, chosen for what is IN them rather
## than for where they are: the character and his shadow carry the only hard
## silhouette edge in the picture, the far bank carries the cel band boundary
## the art direction is built on, and the sky/ridge carries the air perspective
## this effect must not duplicate.
const WINDOWS := {
	"figure": Rect2(0.42, 0.38, 0.20, 0.28),
	"cel band": Rect2(0.62, 0.20, 0.28, 0.28),
	"far ridge": Rect2(0.02, 0.02, 0.30, 0.16),
}


func _report(image: Image, label: String, is_reference: bool) -> void:
	var whole := _sharpness(image, Rect2(0.0, 0.0, 1.0, 1.0))
	if is_reference:
		_sharp["whole"] = whole
	var row := "%-44s  whole %8.5f (%5.1f%%)" % [
		label, whole, 100.0 * whole / maxf(float(_sharp.get("whole", whole)), 0.000001),
	]
	for key in WINDOWS:
		var here := _sharpness(image, WINDOWS[key])
		if is_reference:
			_sharp[key] = here
		row += "  %s %5.1f%%" % [
			key, 100.0 * here / maxf(float(_sharp.get(key, here)), 0.000001),
		]
	print(row)
	if is_reference:
		print("    palette check, sampled from the frame: " + _hexes(image))
	else:
		print("    palette check: " + _hexes(image))


## Mean absolute Laplacian of luminance over a window, from the raw byte buffer
## rather than get_pixel() -- 1.6 million calls per frame is minutes, not seconds.
func _sharpness(image: Image, window: Rect2) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var data := image.get_data()
	var x0: int = maxi(int(window.position.x * float(w)), 1)
	var y0: int = maxi(int(window.position.y * float(h)), 1)
	var x1: int = mini(int((window.position.x + window.size.x) * float(w)), w - 1)
	var y1: int = mini(int((window.position.y + window.size.y) * float(h)), h - 1)
	var total := 0.0
	var count := 0
	for y in range(y0, y1):
		var base := y * w
		for x in range(x0, x1):
			var c := _luma_at(data, (base + x) * 4)
			var lap := 4.0 * c 				- _luma_at(data, (base + x - 1) * 4) 				- _luma_at(data, (base + x + 1) * 4) 				- _luma_at(data, (base - w + x) * 4) 				- _luma_at(data, (base + w + x) * 4)
			total += absf(lap)
			count += 1
	return total / maxf(float(count), 1.0)


func _luma_at(data: PackedByteArray, at: int) -> float:
	return (
		0.2126 * float(data[at]) + 0.7152 * float(data[at + 1]) + 0.0722 * float(data[at + 2])
	) / 255.0


## Four fixed pixels, printed as hex. Trap 7's lesson is that a colour can reach
## the screen wrong and look like art direction; the only defence is reading the
## number back off the frame.
func _hexes(image: Image) -> String:
	var picks := [Vector2(0.10, 0.10), Vector2(0.50, 0.85), Vector2(0.80, 0.30), Vector2(0.30, 0.55)]
	var out := PackedStringArray()
	for pick in picks:
		var at := Vector2i(
			int(pick.x * float(image.get_width())), int(pick.y * float(image.get_height()))
		)
		out.append("#" + image.get_pixel(at.x, at.y).to_html(false))
	return " ".join(out)
