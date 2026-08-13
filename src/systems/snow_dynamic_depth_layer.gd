class_name SnowDynamicDepthLayer
extends RefCounted

## Sparse, world-anchored snow depth added after the run's mature opening
## field.  One value represents one square tile: this layer deliberately does
## not allocate a second 512 x 512 raster every simulation tick.

var tile_size_m := 3.75
var maximum_tiles := 2048

var _tiles: Dictionary = {}
var _tick := 0


func begin_tick() -> void:
	_tick += 1


func tile_key(world_xz: Vector2) -> Vector2i:
	var size := maxf(tile_size_m, 0.001)
	return Vector2i(floori(world_xz.x / size), floori(world_xz.y / size))


func tile_centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * tile_size_m


func depth_at(world_xz: Vector2) -> float:
	var record = _tiles.get(tile_key(world_xz), null)
	if not (record is Dictionary):
		return 0.0
	return float((record as Dictionary).get("depth", 0.0))


func add_at(world_xz: Vector2, amount_m: float, cap_m: float) -> void:
	if amount_m <= 0.0 or cap_m <= 0.0:
		return
	var key := tile_key(world_xz)
	var record: Dictionary = _tiles.get(key, {"depth": 0.0, "touched": _tick})
	record["depth"] = clampf(float(record.get("depth", 0.0)) + amount_m, 0.0, cap_m)
	record["touched"] = _tick
	_tiles[key] = record


func trim_to_limit() -> void:
	while _tiles.size() > maximum_tiles:
		var candidate := Vector2i.ZERO
		var candidate_tick := INF
		var found := false
		for raw_key in _tiles:
			var key := raw_key as Vector2i
			var record: Dictionary = _tiles[key]
			var touched := int(record.get("touched", 0))
			if not found or touched < candidate_tick \
					or (touched == candidate_tick and _comes_before(key, candidate)):
				candidate = key
				candidate_tick = touched
				found = true
		if found:
			_tiles.erase(candidate)


func tile_count() -> int:
	return _tiles.size()


func _comes_before(left: Vector2i, right: Vector2i) -> bool:
	return left.x < right.x or (left.x == right.x and left.y < right.y)
