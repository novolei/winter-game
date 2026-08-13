extends SceneTree

## Reproducible sparse-cap probe.  Run with the console Godot binary so the
## reported CPU time and bounded work counter can accompany a long-run capture.
func _initialize() -> void:
	var layer: SnowDynamicDepthLayer = SnowDynamicDepthLayer.new()
	layer.maximum_tiles = 2048
	layer.begin_tick()
	for x in range(2048):
		layer.add_at_key(Vector2i(x, 0), 0.02, 0.2)
	layer.begin_tick()
	for x in range(2048, 2304):
		layer.add_at_key(Vector2i(x, 0), 0.02, 0.2)
	var started_us := Time.get_ticks_usec()
	layer.trim_to_limit()
	var elapsed_us := Time.get_ticks_usec() - started_us
	print("snow_eviction tile_count=%d evictions=256 heap_work=%d full_tile_scans=%d elapsed_us=%d" % [
		layer.tile_count(),
		layer.last_trim_work(),
		layer.last_trim_full_tile_scans(),
		elapsed_us,
	])
	quit()
