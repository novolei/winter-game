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
	return depth_at_key(tile_key(world_xz))


func depth_at_key(key: Vector2i) -> float:
	var record = _tiles.get(key, null)
	if not (record is Dictionary):
		return 0.0
	return float((record as Dictionary).get("depth", 0.0))


func add_at(world_xz: Vector2, amount_m: float, cap_m: float) -> void:
	if amount_m <= 0.0 or cap_m <= 0.0:
		return
	add_at_key(tile_key(world_xz), amount_m, cap_m)


func add_at_key(key: Vector2i, amount_m: float, cap_m: float) -> void:
	if amount_m <= 0.0 or cap_m <= 0.0:
		return
	var record: Dictionary = _tiles.get(key, {"depth": 0.0, "touched": _tick})
	record["depth"] = clampf(float(record.get("depth", 0.0)) + amount_m, 0.0, cap_m)
	record["touched"] = _tick
	_tiles[key] = record


## Wind transport stages all source and receiver deltas before it commits any
## of them.  This keeps a tile from being read in a half-updated state and lets
## the caller prove the transfer's mass balance.  A zero result is removed so
## the sparse layer cannot fill with historical empty keys.
func apply_depth_deltas(deltas: Dictionary, cap_m: float) -> void:
	if cap_m <= 0.0:
		return
	for raw_key in deltas:
		if not (raw_key is Vector2i):
			continue
		var key := raw_key as Vector2i
		var delta := float(deltas[raw_key])
		if absf(delta) <= 0.0000001:
			continue
		# Incoming transfers are capacity-limited by SnowField before they reach
		# here.  Do not clamp a source down to the *current* response cap: a
		# whiteout may leave a valid 0.18 m tile and a following wind-shift
		# response may cap new deposits at 0.12 m.  Re-clamping the source would
		# silently destroy 0.06 m instead of moving a finite amount of snow.
		var next := maxf(depth_at_key(key) + delta, 0.0)
		if next <= 0.0000001:
			_tiles.erase(key)
			continue
		_tiles[key] = {"depth": next, "touched": _tick}


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


func total_depth_m() -> float:
	var total := 0.0
	for record in _tiles.values():
		if record is Dictionary:
			total += float((record as Dictionary).get("depth", 0.0))
	return total


func _comes_before(left: Vector2i, right: Vector2i) -> bool:
	return left.x < right.x or (left.x == right.x and left.y < right.y)
