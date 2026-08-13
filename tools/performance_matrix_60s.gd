extends Node

## Real D3D12 performance matrix for the shipping main scene.
##
## Each scenario records a full 60 seconds after a five-second warm-up. The
## shallow/deep labels describe the workload applied to the real TrackMask path:
## shallow writes stride-spaced scuffs; deep writes full prints and a continuous
## wading furrow. The SnowField remains the shipping seeded field and its actual
## depth distribution is recorded alongside the workload, so the report cannot
## silently claim that a synthetic constant-depth map was tested.
##
## Run one scenario:
##   Godot --path <project> --rendering-driver d3d12 \
##     res://tools/performance_matrix_60s.tscn -- \
##     --scenario stationary --out C:/Temp/stationary.json

const MAIN_SCENE := preload("res://scenes/main.tscn")
const SCENARIO_SECONDS := 60.0
const WARMUP_SECONDS := 5.0
const FRAME_BUDGET_30_FPS_MS := 33.3
const HITCH_BUDGET_MS := 50.0
const STRIDE_M := 0.72
const DEEP_FURROW_HALF_WIDTH_M := 0.17
const DEEP_FURROW_STRENGTH := 0.72
const DEFAULT_OUTPUT := "user://performance_matrix_60s.json"
const PERFORMANCE_RUN_SEED := 20260813
const SCENARIOS := {
	"stationary": {"move": Vector2.ZERO, "trail": &"none", "start": &"shallow"},
	"shallow_straight": {"move": Vector2(0.0, -1.0), "trail": &"shallow", "start": &"shallow"},
	"deep_straight": {"move": Vector2(0.0, -1.0), "trail": &"deep", "start": &"deep"},
	"deep_diagonal": {"move": Vector2(0.70710678, -0.70710678), "trail": &"deep", "start": &"deep"},
}

var _scenario_name := "stationary"
var _output_path := DEFAULT_OUTPUT
var _duration_seconds := SCENARIO_SECONDS
var _warmup_seconds := WARMUP_SECONDS
var _main: Node3D = null
var _player: CharacterBody3D = null
var _snow: SnowField = null
var _tracks: TrackMask = null
var _scenario: Dictionary = {}
var _start_ticks_us := 0
var _warmup_end_ticks_us := 0
var _finish_ticks_us := 0
var _previous_frame_ticks_us := 0
var _last_position := Vector3.ZERO
var _stride_bank := 0.0
var _samples: Dictionary = {
	"frame_ms": PackedFloat32Array(),
	"process_ms": PackedFloat32Array(),
	"physics_ms": PackedFloat32Array(),
	"draw_calls": PackedFloat32Array(),
	"primitives": PackedFloat32Array(),
	"objects": PackedFloat32Array(),
	"ram_bytes": PackedFloat32Array(),
	"vram_bytes": PackedFloat32Array(),
	"snow_depth_m": PackedFloat32Array(),
	"speed_mps": PackedFloat32Array(),
	"track_upload_ms": PackedFloat32Array(),
}
var _track_bytes := 0
var _track_layers := 0
var _track_base_bytes := 0
var _track_base_layers := 0
var _distance_m := 0.0
var _recenter_count := 0
var _last_snow_origin := Vector2.ZERO
var _max_recenter_ms := 0.0
var _max_dynamic_tiles := 0
var _recording := false
var _finishing := false
var _started := false
var _worst_frame_events: Array[Dictionary] = []
var _last_snow_recentre_ms := 0.0
var _frame_index := 0


static func scenario_names() -> PackedStringArray:
	return PackedStringArray(SCENARIOS.keys())


static func required_result_keys() -> PackedStringArray:
	return PackedStringArray([
		"scenario", "run_seed", "duration_seconds", "wall_elapsed_seconds", "frames", "frame_ms", "process_ms",
		"physics_ms", "draw_calls", "primitives", "objects", "ram_bytes",
		"vram_bytes", "snow_depth_m", "snow_recentres", "max_snow_recentre_ms",
		"max_dynamic_tiles", "track_upload_ms", "track_upload_layers",
		"track_upload_bytes", "distance_m", "speed_mps", "frames_ge_33_3_ms",
		"frames_ge_50_ms", "worst_frame_events",
	])


func _ready() -> void:
	# Measurement must finish even if a shipping fail/death menu pauses gameplay.
	# The paused interval still appears in wall-frame timing, while movement and
	# distance expose that the scenario stopped instead of silently hanging CI.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	var args := OS.get_cmdline_user_args()
	_scenario_name = _arg(args, "--scenario", _scenario_name)
	_output_path = _arg(args, "--out", DEFAULT_OUTPUT)
	# Short values are for harness smoke tests only. Acceptance runs omit both
	# arguments and are pinned by the test to the authored 5 + 60 seconds.
	_duration_seconds = maxf(float(_arg(args, "--seconds", str(SCENARIO_SECONDS))), 1.0)
	_warmup_seconds = maxf(float(_arg(args, "--warmup", str(WARMUP_SECONDS))), 0.0)
	if not SCENARIOS.has(_scenario_name):
		push_error("PERFORMANCE_MATRIX_UNKNOWN_SCENARIO %s" % _scenario_name)
		get_tree().quit(2)
		return
	_scenario = SCENARIOS[_scenario_name]
	call_deferred("_begin")


func _begin() -> void:
	var run_boot := get_node_or_null("/root/RunBoot")
	if run_boot != null:
		run_boot.set("run_seed", PERFORMANCE_RUN_SEED)
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_player = _main.get_node_or_null("Player") as CharacterBody3D
	_snow = _main.get_node_or_null("SnowField") as SnowField
	_tracks = _main.get_node_or_null("TrackMask") as TrackMask
	if _player == null or _snow == null or _tracks == null:
		push_error("PERFORMANCE_MATRIX_SETUP_FAILED")
		get_tree().quit(2)
		return
	# Position before the first physics frame. Teleporting after four frames makes
	# the player's already-live stride/furrow state interpret setup as travel and
	# leaves a decaying track in the nominally stationary case.
	_player.global_position = _find_start(StringName(_scenario["start"]))
	for _frame in range(4):
		await get_tree().process_frame
	_last_position = _player.global_position
	_last_snow_origin = _snow.origin()
	_reset_samples()
	_release_movement()
	_apply_movement(Vector2(_scenario["move"]))
	# Monotonic engine ticks are real elapsed time (not simulation delta), and
	# cannot jump if Windows adjusts its calendar clock during a long sample.
	_start_ticks_us = Time.get_ticks_usec()
	_warmup_end_ticks_us = _start_ticks_us + roundi(_warmup_seconds * 1_000_000.0)
	_finish_ticks_us = _warmup_end_ticks_us + roundi(_duration_seconds * 1_000_000.0)
	_previous_frame_ticks_us = _start_ticks_us
	_started = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _started or _finishing or _player == null:
		return
	var now_ticks_us := Time.get_ticks_usec()
	var frame_ms := float(now_ticks_us - _previous_frame_ticks_us) / 1000.0
	_previous_frame_ticks_us = now_ticks_us
	_drive_trail()
	if now_ticks_us < _warmup_end_ticks_us:
		return
	if not _recording:
		_recording = true
		# Exclude the warm-up interval itself from the first measured frame.
		_previous_frame_ticks_us = now_ticks_us
		_last_snow_origin = _snow.origin()
		_recenter_count = 0
		_max_recenter_ms = 0.0
		_track_base_bytes = _tracks.total_upload_bytes()
		_track_base_layers = _tracks.total_upload_layer_count()
		return
	_frame_index += 1
	_record(frame_ms)
	_record_worst_frame_event(frame_ms, now_ticks_us)
	if now_ticks_us >= _finish_ticks_us:
		_finishing = true
		_finish()


func _find_start(kind: StringName) -> Vector3:
	var best := Vector3.ZERO
	var best_depth := INF if kind == &"shallow" else -INF
	# Search the current 80 m square without recentring it. This picks a real
	# crest/hollow for the first frame while leaving the infinite seeded field
	# free to vary naturally over the following minute.
	# x=36 keeps the minute-long route clear of the authored farmstead while
	# remaining inside the initial live snow window. The diagonal heads outward
	# from the same column, so collision stalls cannot masquerade as GPU results.
	for z in range(-36, 37, 2):
		var point := Vector3(36.0, 0.0, float(z))
		var depth := _snow.depth_at(point)
		if (kind == &"shallow" and depth < best_depth) \
		or (kind == &"deep" and depth > best_depth):
			best = point
			best_depth = depth
	print("PERFORMANCE_MATRIX_START scenario=%s kind=%s point=%s depth_m=%.3f" % [
		_scenario_name, kind, str(best), best_depth,
	])
	return best


func _drive_trail() -> void:
	var position := _player.global_position
	var travelled := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	if _recording and travelled < 0.5:
		_distance_m += travelled
	var trail := StringName(_scenario["trail"])
	if trail == &"deep" and travelled > 0.0001 and travelled < 0.5:
		_tracks.plough(_last_position, position, DEEP_FURROW_HALF_WIDTH_M, DEEP_FURROW_STRENGTH)
	_stride_bank += travelled
	if trail != &"none" and _stride_bank >= STRIDE_M:
		_stride_bank = fmod(_stride_bank, STRIDE_M)
		var heading := Vector2(position.x - _last_position.x, position.z - _last_position.z).normalized()
		if heading.length_squared() < 0.5:
			heading = Vector2(0.0, -1.0)
		if trail == &"shallow":
			_tracks.stamp(position, 0.28, 0.22, heading, 1.9, 0.74, 0.34, 0.0, Vector2.ZERO, 1.0, 1.0)
		else:
			_tracks.stamp(position, 0.28, 1.0, heading, 1.5, 0.66, 0.46)
	_last_position = position


func _record(frame_ms: float) -> void:
	_append("frame_ms", frame_ms)
	_append("process_ms", _monitor(Performance.TIME_PROCESS) * 1000.0)
	_append("physics_ms", _monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_append("draw_calls", _monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_append("primitives", _monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_append("objects", _monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_append("ram_bytes", _monitor(Performance.MEMORY_STATIC))
	_append("vram_bytes", _monitor(Performance.RENDER_VIDEO_MEM_USED))
	_append("snow_depth_m", _snow.depth_at(_player.global_position))
	_append("speed_mps", Vector2(_player.velocity.x, _player.velocity.z).length())
	_append("track_upload_ms", _tracks.last_upload_duration_ms())
	_track_bytes = _tracks.total_upload_bytes() - _track_base_bytes
	_track_layers = _tracks.total_upload_layer_count() - _track_base_layers
	_max_dynamic_tiles = maxi(_max_dynamic_tiles, _snow.dynamic_tile_count())
	var origin := _snow.origin()
	if not origin.is_equal_approx(_last_snow_origin):
		_recenter_count += 1
		_last_snow_recentre_ms = _snow.last_recentre_duration_ms()
		_max_recenter_ms = maxf(_max_recenter_ms, _last_snow_recentre_ms)
		_last_snow_origin = origin
	else:
		_last_snow_recentre_ms = 0.0


func _finish() -> void:
	set_process(false)
	_release_movement()
	var frames: PackedFloat32Array = _samples["frame_ms"]
	var result := {
		"scenario": _scenario_name,
		"run_seed": PERFORMANCE_RUN_SEED,
		"duration_seconds": _duration_seconds,
		"wall_elapsed_seconds": float(Time.get_ticks_usec() - _warmup_end_ticks_us) / 1_000_000.0,
		"frames": frames.size(),
		"frame_ms": _summary(frames),
		"process_ms": _summary(_samples["process_ms"]),
		"physics_ms": _summary(_samples["physics_ms"]),
		"draw_calls": _summary(_samples["draw_calls"]),
		"primitives": _summary(_samples["primitives"]),
		"objects": _summary(_samples["objects"]),
		"ram_bytes": _summary(_samples["ram_bytes"]),
		"vram_bytes": _summary(_samples["vram_bytes"]),
		"snow_depth_m": _summary(_samples["snow_depth_m"]),
		"snow_recentres": _recenter_count,
		"max_snow_recentre_ms": _max_recenter_ms,
		"max_dynamic_tiles": _max_dynamic_tiles,
		"track_upload_ms": _summary(_samples["track_upload_ms"]),
		"track_upload_layers": _track_layers,
		"track_upload_bytes": _track_bytes,
		"distance_m": _distance_m,
		"speed_mps": _summary(_samples["speed_mps"]),
		"frames_ge_33_3_ms": _count_at_least(frames, FRAME_BUDGET_30_FPS_MS),
		"frames_ge_50_ms": _count_at_least(frames, HITCH_BUDGET_MS),
		"worst_frame_events": _worst_frame_events,
		"renderer": RenderingServer.get_rendering_device() != null,
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info().get("string", "unknown"),
	}
	var absolute := ProjectSettings.globalize_path(_output_path)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("PERFORMANCE_MATRIX_WRITE_FAILED %s" % absolute)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PERFORMANCE_MATRIX_RESULT ", JSON.stringify(result))
	print("PERFORMANCE_MATRIX_WROTE ", absolute)
	_main.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _reset_samples() -> void:
	for key in _samples:
		_samples[key] = PackedFloat32Array()
	_worst_frame_events.clear()
	_last_snow_recentre_ms = 0.0
	_frame_index = 0


func _record_worst_frame_event(frame_ms: float, now_ticks_us: int) -> void:
	if frame_ms < FRAME_BUDGET_30_FPS_MS:
		return
	var event := {
		"frame_index": _frame_index,
		"elapsed_seconds": float(now_ticks_us - _warmup_end_ticks_us) / 1_000_000.0,
		"frame_ms": frame_ms,
		"process_ms": _monitor(Performance.TIME_PROCESS) * 1000.0,
		"snow_origin": _snow.origin(),
		"snow_recentred_this_frame": _last_snow_recentre_ms > 0.0,
		"snow_recentre_ms": _last_snow_recentre_ms,
		"track_upload_ms": _tracks.last_upload_duration_ms(),
		"track_upload_layers": _tracks.last_upload_layer_count(),
		"track_upload_bytes": _tracks.last_upload_bytes(),
		"track_flushed_this_frame": _tracks.last_upload_layer_count() > 0,
		"player_position": _player.global_position,
	}
	_worst_frame_events.append(event)
	if _worst_frame_events.size() > 32:
		_worst_frame_events.pop_front()


func _append(key: String, value: float) -> void:
	var values: PackedFloat32Array = _samples[key]
	values.append(value)
	_samples[key] = values


static func _summary(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "distinct": 0}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"max": sorted[sorted.size() - 1],
		"distinct": _distinct_count(sorted),
	}


static func _percentile(sorted: PackedFloat32Array, percentile: float) -> float:
	var index := clampi(ceili(percentile * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]


static func _count_at_least(values: PackedFloat32Array, threshold: float) -> int:
	var count := 0
	for value in values:
		if value >= threshold:
			count += 1
	return count


static func _distinct_count(sorted: PackedFloat32Array) -> int:
	if sorted.is_empty():
		return 0
	var count := 1
	var previous := sorted[0]
	for index in range(1, sorted.size()):
		if not is_equal_approx(sorted[index], previous):
			count += 1
			previous = sorted[index]
	return count


static func _monitor(monitor: Performance.Monitor) -> float:
	var value := float(Performance.get_monitor(monitor))
	return value if is_finite(value) and value >= 0.0 else 0.0


static func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _apply_movement(direction: Vector2) -> void:
	_axis(&"move_right", &"move_left", direction.x)
	_axis(&"move_back", &"move_forward", direction.y)


func _axis(positive: StringName, negative: StringName, amount: float) -> void:
	if amount > 0.0:
		Input.action_press(positive, absf(amount))
	elif amount < 0.0:
		Input.action_press(negative, absf(amount))


func _release_movement() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)


func _exit_tree() -> void:
	_release_movement()
