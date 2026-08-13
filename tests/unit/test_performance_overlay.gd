extends TestCase

const PerformanceOverlayScript := preload("res://src/ui/performance_overlay.gd")
const UITokensScript := preload("res://src/definitions/ui_tokens.gd")
const UIFontsScript := preload("res://src/ui/ui_fonts.gd")
const UILayerScript := preload("res://src/ui/ui_layer.gd")

var _overlay: Control = null


func before_each() -> void:
	_overlay = PerformanceOverlayScript.new()
	var tokens := ResourceLoader.load("res://data/ui/tokens.tres") as UITokens
	var fonts := UIFontsScript.new()
	fonts.build(tokens)
	_overlay.attach(tokens, fonts)


func after_each() -> void:
	if _overlay != null:
		_overlay.free()
		_overlay = null


func _f3(shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F3
	event.shift_pressed = shift
	event.pressed = true
	return event


func test_the_toggle_action_is_a_real_f3_binding() -> void:
	assert_true(InputMap.has_action(&"toggle_performance_metrics"))
	var events := InputMap.action_get_events(&"toggle_performance_metrics")
	assert_eq(events.size(), 1, "the performance overlay needs one unambiguous binding")
	if events.size() != 1:
		return
	var event := events[0] as InputEventKey
	assert_not_null(event)
	if event == null:
		return
	assert_eq(event.physical_keycode, KEY_F3)
	assert_eq(event.device, -1, "-1 accepts the keyboard actually attached to the player")


func test_the_overlay_is_hidden_until_the_developer_opens_it() -> void:
	assert_false(_overlay.is_open())
	assert_false(_overlay.visible)


func test_the_debug_ui_layer_owns_the_overlay_without_a_scene_path() -> void:
	var layer := UILayerScript.new()
	layer.build()
	assert_not_null(layer.performance_overlay())
	assert_false(layer.performance_overlay().visible)
	layer.free()


func test_f3_toggles_the_overlay_without_consuming_shift_f3() -> void:
	assert_true(_overlay.handle_input(_f3()))
	assert_true(_overlay.is_open())
	assert_true(_overlay.visible)
	assert_true(_overlay.handle_input(_f3()))
	assert_false(_overlay.is_open())
	assert_false(_overlay.handle_input(_f3(true)), "Shift+F3 remains the lighting preview")


func test_the_visible_overlay_retains_a_real_hitch_for_the_worst_window() -> void:
	_overlay.set_open(true)
	_overlay.advance(0.016)
	_overlay.advance(0.084)
	assert_almost_eq(_overlay.worst_frame_ms(), 84.0, 0.001)
	_overlay.set_open(false)
	_overlay.advance(0.250)
	assert_almost_eq(_overlay.worst_frame_ms(), 84.0, 0.001, "a hidden overlay must not sample")


func test_the_readout_includes_render_memory_and_snow_diagnostics() -> void:
	var text := PerformanceOverlayScript.format_metrics({
		"fps": 60.0,
		"frame_ms": 16.7,
		"worst_frame_ms": 42.5,
		"process_ms": 4.2,
		"physics_ms": 1.1,
		"draw_calls": 208,
		"primitives": 12345,
		"objects": 88,
		"ram_bytes": 64.0 * 1024.0 * 1024.0,
		"vram_bytes": 128.0 * 1024.0 * 1024.0,
		"snow_tiles": 31,
		"recenter_ms": 7.5,
	})
	assert_true("FPS" in text)
	assert_true("GPU draws" in text)
	assert_true("RAM 64 MiB" in text)
	assert_true("VRAM 128 MiB" in text)
	assert_true("Snow tiles   31" in text)
	assert_true("recenter   7.5 ms" in text)
