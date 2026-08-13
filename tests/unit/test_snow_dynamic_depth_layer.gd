extends TestCase


## A full sparse store must not turn each later tile eviction into another walk
## across every historical record.  This deliberately crosses the production
## 2,048-tile limit: the old selection scan would perform 524,288 record visits
## for these 256 evictions.
func test_trim_crosses_production_cap_with_bounded_heap_work_and_stable_order() -> void:
	var layer: SnowDynamicDepthLayer = SnowDynamicDepthLayer.new()
	layer.maximum_tiles = 2048
	layer.begin_tick()
	for x in range(2048):
		layer.add_at_key(Vector2i(x, 0), 0.02, 0.2)
	layer.begin_tick()
	for x in range(2048, 2304):
		layer.add_at_key(Vector2i(x, 0), 0.02, 0.2)

	layer.trim_to_limit()

	assert_eq(layer.tile_count(), 2048)
	assert_almost_eq(layer.depth_at_key(Vector2i(0, 0)), 0.0, 0.000001)
	assert_almost_eq(layer.depth_at_key(Vector2i(255, 0)), 0.0, 0.000001)
	assert_almost_eq(layer.depth_at_key(Vector2i(256, 0)), 0.02, 0.000001)
	assert_almost_eq(layer.depth_at_key(Vector2i(2303, 0)), 0.02, 0.000001)
	assert_eq(layer.last_trim_full_tile_scans(), 0,
		"trim scanned the sparse store once per eviction")
	assert_true(layer.last_trim_work() <= 256 * 32,
		"trim used %d heap operations for 256 evictions" % layer.last_trim_work())
	var snapshot: Dictionary = layer.create_persistence_snapshot()
	var tiles: Array = snapshot["tiles"]
	assert_eq((tiles.front() as Dictionary)["x"], 256)
	assert_eq((tiles.back() as Dictionary)["x"], 2303)


## Loading has to rebuild the same age index as a continuous run.  Otherwise a
## save/load boundary changes which optional route tile disappears at capacity.
func test_restored_sparse_layer_keeps_the_same_next_eviction_order() -> void:
	var source: SnowDynamicDepthLayer = SnowDynamicDepthLayer.new()
	source.maximum_tiles = 3
	source.begin_tick()
	source.add_at_key(Vector2i(9, 0), 0.02, 0.2)
	source.add_at_key(Vector2i(1, 0), 0.02, 0.2)
	source.begin_tick()
	source.add_at_key(Vector2i(5, 0), 0.02, 0.2)
	var snapshot: Dictionary = source.create_persistence_snapshot()

	var restored: SnowDynamicDepthLayer = SnowDynamicDepthLayer.new()
	restored.maximum_tiles = 3
	assert_true(restored.restore_persistence_snapshot(snapshot))
	restored.begin_tick()
	restored.add_at_key(Vector2i(12, 0), 0.02, 0.2)
	restored.trim_to_limit()

	assert_almost_eq(restored.depth_at_key(Vector2i(1, 0)), 0.0, 0.000001)
	assert_almost_eq(restored.depth_at_key(Vector2i(9, 0)), 0.02, 0.000001)
	assert_almost_eq(restored.depth_at_key(Vector2i(5, 0)), 0.02, 0.000001)
	assert_almost_eq(restored.depth_at_key(Vector2i(12, 0)), 0.02, 0.000001)


## A repeatedly snowed-on tile is no longer the oldest record.  This catches
## a stale-index implementation that appends new ages but still evicts its old
## entry after a later tick.
func test_touching_a_tile_updates_its_eviction_age_without_duplicate_history() -> void:
	var layer: SnowDynamicDepthLayer = SnowDynamicDepthLayer.new()
	layer.maximum_tiles = 2
	layer.begin_tick()
	layer.add_at_key(Vector2i(1, 0), 0.02, 0.2)
	layer.add_at_key(Vector2i(2, 0), 0.02, 0.2)
	layer.begin_tick()
	layer.add_at_key(Vector2i(1, 0), 0.02, 0.2)
	layer.add_at_key(Vector2i(3, 0), 0.02, 0.2)
	layer.trim_to_limit()

	assert_almost_eq(layer.depth_at_key(Vector2i(2, 0)), 0.0, 0.000001)
	assert_almost_eq(layer.depth_at_key(Vector2i(1, 0)), 0.04, 0.000001)
	assert_almost_eq(layer.depth_at_key(Vector2i(3, 0)), 0.02, 0.000001)
