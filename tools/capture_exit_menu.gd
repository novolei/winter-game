extends Node

## Visual acceptance harness for the actual pause and exit-confirmation states.
## It instances the shipping main scene, opens the real menu, and records both
## compositions after their authored bloom has settled.

const DEFAULT_OUTPUT := "user://pause_menu.png"

var _output := DEFAULT_OUTPUT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_output = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_capture_states.call_deferred()


func _capture_states() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var menu := get_node_or_null("Main/ExitMenu") as ExitMenu
	if menu == null:
		push_error("capture_exit_menu: shipping main scene has no ExitMenu")
		get_tree().quit(1)
		return
	var rig := get_node_or_null("Main/CameraRig") as CameraRig
	var original_frame := 0.0 if rig == null else rig.framed_size()
	var original_lean := Vector3.ZERO if rig == null else rig.lean()
	var original_offset := Vector2.ZERO if rig == null else rig.composition_offset()
	var original_boom_factor := 1.0 if rig == null else rig.boom_factor()
	menu.open()
	# The push is decoupled from the cascade and lands at push_seconds (1.6);
	# capture after the lens has actually settled, not when the type has.
	await get_tree().create_timer(1.9, true).timeout
	var lean_y_override := _float_arg(args, "--lean-y-deg", NAN)
	if rig != null and not is_nan(lean_y_override):
		var current_lean := rig.lean()
		current_lean.y = deg_to_rad(lean_y_override)
		rig.set_lean(current_lean)
	if rig != null:
		print("capture_exit_menu: camera %.3f -> %.3f" % [original_frame, rig.framed_size()])
		print("capture_exit_menu: lean %s, composition %s, boom %.3f" % [
			rig.lean(), rig.composition_offset(), rig.boom_factor()])
	await _save(_output)

	menu.request_exit()
	# The state swap runs the quick transition cascade (~0.3s), not the opening
	# ceremony; wait past it so the confirmation is actually on screen.
	await get_tree().create_timer(0.5, true).timeout
	var confirm_output := _output.get_basename() + "_confirm." + _output.get_extension()
	await _save(confirm_output)

	# The settings page is the third state; capture it too so all three are
	# reviewed from pictures, not from memory.
	menu.cancel_exit()
	await get_tree().create_timer(0.4, true).timeout
	menu.open_settings()
	await get_tree().create_timer(0.5, true).timeout
	var settings_output := _output.get_basename() + "_settings." + _output.get_extension()
	await _save(settings_output)

	menu.close()
	# The return is return_seconds (0.55) of QUAD IN; checking earlier reads a
	# camera that is still travelling as a camera that did not return.
	await get_tree().create_timer(0.8, true).timeout
	if rig != null and not is_equal_approx(rig.framed_size(), original_frame):
		push_error("capture_exit_menu: camera did not return (%.3f != %.3f)" % [
			rig.framed_size(), original_frame])
	if rig != null and rig.lean() != original_lean:
		push_error("capture_exit_menu: angle did not return (%s != %s)" % [
			rig.lean(), original_lean])
	if rig != null and rig.composition_offset() != original_offset:
		push_error("capture_exit_menu: composition did not return (%s != %s)" % [
			rig.composition_offset(), original_offset])
	if rig != null and not is_equal_approx(rig.boom_factor(), original_boom_factor):
		push_error("capture_exit_menu: boom did not return (%.3f != %.3f)" % [
			rig.boom_factor(), original_boom_factor])
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("capture_exit_menu: could not write %s (%d)" % [path, error])
	else:
		print("capture_exit_menu: wrote %s" % ProjectSettings.globalize_path(path))


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _float_arg(args: PackedStringArray, name: String, fallback: float) -> float:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1].to_float()
	return fallback
