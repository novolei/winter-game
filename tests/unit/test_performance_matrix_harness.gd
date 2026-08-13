extends TestCase

const HarnessScript := preload("res://tools/performance_matrix_60s.gd")
const QualityGateScript := preload("res://tools/capture_visual_quality_gate.gd")


func test_the_matrix_covers_the_four_requested_sixty_second_scenarios() -> void:
	assert_almost_eq(HarnessScript.SCENARIO_SECONDS, 60.0, 0.0001)
	assert_eq(HarnessScript.PERFORMANCE_RUN_SEED, 20260813)
	assert_eq(HarnessScript.scenario_names(), PackedStringArray([
		"stationary", "shallow_straight", "deep_straight", "deep_diagonal",
	]))
	assert_eq(HarnessScript.SCENARIOS["stationary"]["move"], Vector2.ZERO)
	assert_eq(HarnessScript.SCENARIOS["shallow_straight"]["trail"], &"shallow")
	assert_eq(HarnessScript.SCENARIOS["deep_straight"]["trail"], &"deep")
	assert_eq(HarnessScript.SCENARIOS["deep_diagonal"]["trail"], &"deep")
	assert_true(Vector2(HarnessScript.SCENARIOS["deep_diagonal"]["move"]).is_normalized())


func test_the_matrix_records_every_required_runtime_metric() -> void:
	var keys := HarnessScript.required_result_keys()
	for required in [
		"wall_elapsed_seconds", "frame_ms", "process_ms", "physics_ms", "draw_calls", "primitives",
		"objects", "ram_bytes", "vram_bytes", "snow_depth_m",
		"max_snow_recentre_ms", "max_dynamic_tiles", "track_upload_ms",
		"track_upload_layers", "track_upload_bytes", "frames_ge_33_3_ms",
		"frames_ge_50_ms", "worst_frame_events", "distance_m", "speed_mps",
	]:
		assert_true(required in keys, "the 60-second matrix does not record %s" % required)
	var source := FileAccess.get_file_as_string("res://tools/performance_matrix_60s.gd")
	for hitch_field in [
		'"process_ms"', '"snow_recentred_this_frame"', '"snow_recentre_ms"',
		'"track_upload_ms"', '"track_upload_layers"', '"track_upload_bytes"',
		'"track_flushed_this_frame"',
	]:
		assert_true(hitch_field in source, "hitch diagnostics omit %s" % hitch_field)
	assert_true("Time.get_ticks_usec()" in source)
	assert_false("Time.get_unix_time_from_system()" in source)


func test_low_end_safety_keeps_the_existing_visual_resolution_contract() -> void:
	assert_eq(TrackMask.RESOLUTION, 2048)
	assert_eq(TrackMask.UPLOAD_CHUNK, 512)
	assert_eq(TrackMask.UPLOAD_GUTTER, 1)
	assert_true(TrackMask.UPLOAD_BYTES_PER_LAYER < 300 * 1024)


func test_the_visual_gate_covers_shadow_fog_and_blizzard_without_a_quality_tier() -> void:
	assert_eq(QualityGateScript.gate_presets(), PackedStringArray([
		"pale_day", "deep_night", "whiteout",
	]))
	assert_true(QualityGateScript.SNOWFALL_RATES["whiteout"] > 0.99)
	assert_true(QualityGateScript.SNOWFALL_RATES["deep_night"] < 0.3)
	assert_true(QualityGateScript.SNOWFALL_RATES["pale_day"] < 0.2)
	# Tools are disposable consumers of shipping presets. They carry no switch
	# for shadow resolution, fog quality, particle count or project defaults.
	var source := FileAccess.get_file_as_string("res://tools/capture_visual_quality_gate.gd")
	assert_false("ProjectSettings.set_setting" in source)
	assert_false("quality_tier" in source)


func test_the_canonical_runner_refuses_a_contaminated_godot_session() -> void:
	var source := FileAccess.get_file_as_string("res://tools/run_performance_matrix_60s.ps1")
	assert_true("Get-CimInstance Win32_Process" in source)
	assert_true("Close Godot and retry" in source)
	for scenario in HarnessScript.scenario_names():
		assert_true(String(scenario) in source)
	for preset in QualityGateScript.gate_presets():
		assert_true(String(preset) in source)
