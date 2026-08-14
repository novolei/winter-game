extends Node

## Deterministic valley-wide beacon proof. It lights the real five runtime
## entities, frames every landmark, applies the authored night look and writes
## one image. This is a capture harness only; gameplay still spends inventory.

var _out := "user://beacons.png"
var _ortho := 112.0
var _look := Vector2(0.0, -8.0)
var _preset := &"nightfall"
var _light_beacons := true
var _frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", _out)
	_ortho = float(_arg(args, "--ortho", str(_ortho)))
	_preset = StringName(_arg(args, "--preset", String(_preset)))
	_light_beacons = _arg(args, "--light", "true").to_lower() != "false"
	var look := _arg(args, "--look", "0,-8").split(",")
	if look.size() == 2:
		_look = Vector2(float(look[0]), float(look[1]))
	# Children are ready before their parent, so Main and the network already
	# exist here. The shutter itself is frame-counted in _process: this avoids
	# depending on a renderer-specific frame_post_draw await during automation.
	_prepare_beacons()
	_frame_world()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		# WorldClock applies day one after startup; win that final write immediately
		# before the shutter so the capture is the authored nightfall, not a blend.
		var lighting = get_node_or_null("Main/Lighting")
		if lighting != null:
			lighting.apply_preset(_preset)
	elif _frame == 32:
		_capture()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _prepare_beacons() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	var network = registry.get_service(&"beacon_network") if registry != null else null
	if network == null:
		push_error("capture_beacons: no beacon_network service")
		get_tree().quit(1)
		return
	network.set_process(false)
	network.set_day(5)
	if _light_beacons:
		for lamp in network.beacons():
			lamp.add_fuel_seconds(lamp.definition.fuel_capacity)
			lamp.light()
	print("capture_beacons: lit %d/%d runtime beacons" % [
		network.lit_count(), network.total_count(),
	])


func _frame_world() -> void:
	var rig = get_node_or_null("Main/CameraRig")
	if rig != null:
		rig.orthographic_size = _ortho
		rig.refresh_framing()
		var tween: Tween = rig.framing_tween()
		if tween != null and tween.is_valid():
			tween.kill()
		rig.apply_framed_size(rig.framing_target())
		# A location proof is not a follow shot. Freeze the rig after asking its own
		# framing API to size the camera, otherwise it recentres on the player before
		# the close-up shutter.
		rig.set_process(false)
		rig.set_physics_process(false)
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)


func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_out)
	if error != OK:
		push_error("capture_beacons: failed to write %s (%d)" % [_out, error])
		get_tree().quit(1)
		return
	print("capture_beacons: wrote %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()
