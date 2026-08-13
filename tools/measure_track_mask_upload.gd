extends SceneTree

## D3D12/Vulkan CPU-side upload probe for the dynamic footprint transport.
##
## Run without --headless so the requested rendering driver owns real textures:
##
##   Godot --path <project> --rendering-driver d3d12 \
##     --script res://tools/measure_track_mask_upload.gd
##
## This deliberately stamps and flushes every frame-equivalent, which models
## the worst deep-snow walk. It reports transport bytes and the p50/p95/p99 CPU
## submission duration exposed by TrackMask itself.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const SAMPLE_COUNT := 300


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var mask: TrackMask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	mask.flush()
	var samples := PackedFloat32Array()
	var byte_total := 0
	var layer_total := 0
	for index in range(SAMPLE_COUNT):
		# A compact real walk stays inside one transport core. Oscillation prevents
		# repeated max-compositing from turning later stamps into no-ops.
		var x := -12.0 + float(index % 80) * 0.05
		var z := -12.0 + sin(float(index) * 0.37) * 1.5
		mask.stamp(Vector3(x, 0.0, z), 0.28, 1.0, Vector2.RIGHT, 2.0)
		mask.flush()
		samples.append(mask.last_upload_duration_ms())
		if mask.last_upload_duration_ms() > 1.0:
			print("TRACK_MASK_UPLOAD_SPIKE sample=%d ms=%.3f layers=%d" % [
				index, mask.last_upload_duration_ms(), mask.last_upload_layer_count()
			])
		byte_total += mask.last_upload_bytes()
		layer_total += mask.last_upload_layer_count()
	samples.sort()
	print("TRACK_MASK_CHUNK_UPLOAD samples=%d layers=%d bytes=%d p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f" % [
		SAMPLE_COUNT,
		layer_total,
		byte_total,
		_percentile(samples, 0.50),
		_percentile(samples, 0.95),
		_percentile(samples, 0.99),
		samples[samples.size() - 1],
	])
	mask.free()
	quit()


func _percentile(sorted: PackedFloat32Array, percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := clampi(ceili(percentile * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]
