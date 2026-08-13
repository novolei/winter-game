extends Node

## Fixed-camera shadow/fog/blizzard gate. It never changes a project setting or
## quality default: each look is applied only to this disposable main-scene
## instance and written as an evidence PNG.
##
##   Godot --path <project> --rendering-driver d3d12 --resolution 1600x1000 \
##     res://tools/capture_visual_quality_gate.tscn -- \
##     --preset pale_day --out C:/Temp/pale_day.png

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DEFAULT_SETTLE_SECONDS := 8.0
const QUALITY_RUN_SEED := 20260813
const ALLOWED_PRESETS := ["pale_day", "deep_night", "whiteout"]
const SNOWFALL_RATES := {
	"pale_day": 0.12,
	"deep_night": 0.28,
	"whiteout": 1.0,
}

var _preset := "pale_day"
var _output := "user://visual_quality_gate.png"
var _settle_seconds := DEFAULT_SETTLE_SECONDS


static func gate_presets() -> PackedStringArray:
	return PackedStringArray(ALLOWED_PRESETS)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_preset = _arg(args, "--preset", _preset)
	_output = _arg(args, "--out", _output)
	_settle_seconds = maxf(float(_arg(args, "--settle", str(DEFAULT_SETTLE_SECONDS))), 0.0)
	if _preset not in ALLOWED_PRESETS:
		push_error("VISUAL_QUALITY_GATE_UNKNOWN_PRESET %s" % _preset)
		get_tree().quit(2)
		return
	call_deferred("_capture")


func _capture() -> void:
	var run_boot := get_node_or_null("/root/RunBoot")
	if run_boot != null:
		run_boot.set("run_seed", QUALITY_RUN_SEED)
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame in range(4):
		await get_tree().process_frame
	var lighting := main.get_node_or_null("Lighting")
	var snowfall := main.get_node_or_null("Snowfall")
	var rig := main.get_node_or_null("CameraRig")
	if lighting == null or snowfall == null or rig == null:
		push_error("VISUAL_QUALITY_GATE_SETUP_FAILED")
		get_tree().quit(2)
		return
	if not lighting.apply_preset(StringName(_preset)):
		push_error("VISUAL_QUALITY_GATE_PRESET_FAILED %s" % _preset)
		get_tree().quit(2)
		return
	# Drive the real snowfall layers long enough to settle. A one-frame preset
	# snap captures the fog but not a whiteout's authored particle population.
	snowfall.set_snowfall_rate(float(SNOWFALL_RATES[_preset]))
	if _settle_seconds > 0.0:
		await get_tree().create_timer(_settle_seconds).timeout
	# The camera remains in the shipping gameplay composition. Snap only removes
	# follow lag so all three captures use the identical transform.
	if rig.has_method("snap_to_target"):
		rig.snap_to_target()
	lighting.apply_preset(StringName(_preset))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(_output)
	var error := image.save_png(absolute)
	if error != OK:
		push_error("VISUAL_QUALITY_GATE_WRITE_FAILED %s error=%d" % [absolute, error])
		get_tree().quit(2)
		return
	print("VISUAL_QUALITY_GATE preset=%s size=%dx%d snowfall=%.2f output=%s" % [
		_preset, image.get_width(), image.get_height(), SNOWFALL_RATES[_preset], absolute,
	])
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit()


static func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback
