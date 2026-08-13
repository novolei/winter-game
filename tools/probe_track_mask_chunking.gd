extends Node

## Real-main, real-frame validation for TrackMask's chunked GPU transport.
## It renders 300 deep-snow-equivalent steps at 60 Hz, then a 100 m zigzag
## which crosses/recentres the world-anchored window.  The probe never changes
## shipping state or input bindings.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const WALK_SAMPLES := 300
const WALK_STEP_M := 3.3 / 60.0
const ZIGZAG_STEP_M := 0.5
const ZIGZAG_STEPS := 200
const HITCH_MS := 50.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame in range(3):
		await get_tree().process_frame
	var player := main.get_node_or_null("Player") as Node3D
	var tracks := main.get_node_or_null("TrackMask") as TrackMask
	if player == null or tracks == null:
		push_error("TRACK_CHUNK_PROBE_SETUP_FAILED")
		get_tree().quit(2)
		return

	var upload_samples := PackedFloat32Array()
	var frame_samples := PackedFloat32Array()
	var byte_total := 0
	var layer_total := 0
	for index in range(WALK_SAMPLES):
		var start_us := Time.get_ticks_usec()
		player.global_position.x += WALK_STEP_M
		tracks.stamp(player.global_position, 0.28, 1.0, Vector2.RIGHT, 2.0)
		await get_tree().process_frame
		frame_samples.append(float(Time.get_ticks_usec() - start_us) / 1000.0)
		upload_samples.append(tracks.last_upload_duration_ms())
		byte_total += tracks.last_upload_bytes()
		layer_total += tracks.last_upload_layer_count()
	upload_samples.sort()
	frame_samples.sort()
	print("TRACK_CHUNK_WALK samples=%d layers=%d bytes=%d p50_upload_ms=%.3f p95_upload_ms=%.3f p99_upload_ms=%.3f p50_frame_ms=%.3f p95_frame_ms=%.3f p99_frame_ms=%.3f" % [
		WALK_SAMPLES, layer_total, byte_total,
		_percentile(upload_samples, 0.50), _percentile(upload_samples, 0.95),
		_percentile(upload_samples, 0.99), _percentile(frame_samples, 0.50),
		_percentile(frame_samples, 0.95), _percentile(frame_samples, 0.99),
	])

	var hitch_count := 0
	var worst_frame_ms := 0.0
	var max_upload_ms := 0.0
	var direction := Vector3(1.0, 0.0, 0.45).normalized()
	for step in range(ZIGZAG_STEPS):
		if step > 0 and step % 25 == 0:
			direction.z = -direction.z
		var start_us := Time.get_ticks_usec()
		player.global_position += direction * ZIGZAG_STEP_M
		tracks.stamp(
			player.global_position, 0.28, 0.9,
			Vector2(direction.x, direction.z), 2.0
		)
		await get_tree().process_frame
		var frame_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
		worst_frame_ms = maxf(worst_frame_ms, frame_ms)
		max_upload_ms = maxf(max_upload_ms, tracks.last_upload_duration_ms())
		if frame_ms >= HITCH_MS:
			hitch_count += 1
	print("TRACK_CHUNK_ZIGZAG distance_m=%.1f hitches=%d worst_frame_ms=%.3f max_upload_ms=%.3f last_value=%.3f" % [
		ZIGZAG_STEPS * ZIGZAG_STEP_M, hitch_count, worst_frame_ms, max_upload_ms,
		tracks.value_at(player.global_position),
	])

	var passed := hitch_count == 0 and tracks.value_at(player.global_position) > 0.1
	main.queue_free()
	await get_tree().process_frame
	if not passed:
		push_error("TRACK_CHUNK_PROBE_FAILED")
		get_tree().quit(1)
		return
	get_tree().quit()


func _percentile(sorted: PackedFloat32Array, percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := clampi(ceili(percentile * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]
