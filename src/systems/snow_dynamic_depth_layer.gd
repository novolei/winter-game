class_name SnowDynamicDepthLayer
extends RefCounted

## Sparse, world-anchored snow depth added after the run's mature opening
## field.  One value represents one square tile: this layer deliberately does
## not allocate a second 512 x 512 raster every simulation tick.

var tile_size_m := 3.75
var maximum_tiles := 2048

## This format is deliberately a list of changed world tiles, never a 512²
## image.  It is owned by the layer so a save owner can persist the same sparse
## state without reaching into its private map.
const PERSISTENCE_VERSION := 1
const MAX_PERSISTED_TILES := 8192

var _tiles: Dictionary = {}
var _tick := 0

## The sparse-store cap is reached only after a long run, so it must not turn
## the newest 64--96 writes into a fresh scan across every remembered tile.
## This binary heap keeps the exact former eviction order: lower touched tick
## first, then world X and Z.  `_age_positions` lets a touched or removed tile
## update the same index instead of leaving historical heap entries behind.
var _age_heap: Array[Dictionary] = []
var _age_positions: Dictionary = {}

## Runtime instrumentation for the performance HUD and the regression below.
## It counts heap probes/swaps performed by the latest trim, never tile-map
## scans.  At the persisted maximum of 8,192 tiles the heap height is 13, so a
## root removal takes no more than one pop plus three operations per level.
const MAX_TRIM_HEAP_WORK_PER_EVICTION := 40
var _last_trim_work := 0
var _last_trim_full_tile_scans := 0
var _measuring_trim_work := false


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
	_update_age_index(key, _tick)


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
			_remove_age_index(key)
			continue
		_tiles[key] = {"depth": next, "touched": _tick}
		_update_age_index(key, _tick)


func trim_to_limit() -> void:
	_last_trim_work = 0
	_last_trim_full_tile_scans = 0
	_measuring_trim_work = true
	while _tiles.size() > maximum_tiles:
		var raw_candidate = _pop_oldest_age_key()
		if not (raw_candidate is Vector2i):
			break
		_tiles.erase(raw_candidate as Vector2i)
	_measuring_trim_work = false


func last_trim_work() -> int:
	return _last_trim_work


func last_trim_full_tile_scans() -> int:
	return _last_trim_full_tile_scans


func _update_age_index(key: Vector2i, touched: int) -> void:
	var index := int(_age_positions.get(key, -1))
	if index < 0 or index >= _age_heap.size():
		_age_heap.append({"key": key, "touched": touched})
		index = _age_heap.size() - 1
		_age_positions[key] = index
		_sift_age_up(index)
		return
	var entry: Dictionary = _age_heap[index]
	entry["touched"] = touched
	_age_heap[index] = entry
	_rebalance_age_index(index)


func _remove_age_index(key: Vector2i) -> void:
	var index := int(_age_positions.get(key, -1))
	if index < 0 or index >= _age_heap.size():
		_age_positions.erase(key)
		return
	var last: Dictionary = _age_heap.pop_back()
	_age_positions.erase(key)
	if index >= _age_heap.size():
		return
	_age_heap[index] = last
	_age_positions[last["key"] as Vector2i] = index
	_rebalance_age_index(index)


func _pop_oldest_age_key():
	if _age_heap.is_empty():
		return null
	_count_trim_work()
	var entry: Dictionary = _age_heap[0]
	var key := entry["key"] as Vector2i
	_remove_age_index(key)
	return key


func _rebalance_age_index(index: int) -> void:
	if index > 0 and _age_entry_comes_before(_age_heap[index], _age_heap[(index - 1) / 2]):
		_sift_age_up(index)
	else:
		_sift_age_down(index)


func _sift_age_up(index: int) -> void:
	var current := index
	while current > 0:
		var parent := (current - 1) / 2
		if not _age_entry_comes_before(_age_heap[current], _age_heap[parent]):
			return
		_swap_age_entries(current, parent)
		current = parent


func _sift_age_down(index: int) -> void:
	var current := index
	while true:
		var left := current * 2 + 1
		if left >= _age_heap.size():
			return
		var smallest := left
		var right := left + 1
		if right < _age_heap.size() and _age_entry_comes_before(_age_heap[right], _age_heap[left]):
			smallest = right
		if not _age_entry_comes_before(_age_heap[smallest], _age_heap[current]):
			return
		_swap_age_entries(current, smallest)
		current = smallest


func _swap_age_entries(left_index: int, right_index: int) -> void:
	_count_trim_work()
	var left: Dictionary = _age_heap[left_index]
	var right: Dictionary = _age_heap[right_index]
	_age_heap[left_index] = right
	_age_heap[right_index] = left
	_age_positions[right["key"] as Vector2i] = left_index
	_age_positions[left["key"] as Vector2i] = right_index


func _age_entry_comes_before(left: Dictionary, right: Dictionary) -> bool:
	_count_trim_work()
	var left_tick := int(left["touched"])
	var right_tick := int(right["touched"])
	if left_tick != right_tick:
		return left_tick < right_tick
	return _comes_before(left["key"] as Vector2i, right["key"] as Vector2i)


func _count_trim_work() -> void:
	if _measuring_trim_work:
		_last_trim_work += 1


func tile_count() -> int:
	return _tiles.size()


func total_depth_m() -> float:
	var total := 0.0
	for record in _tiles.values():
		if record is Dictionary:
			total += float((record as Dictionary).get("depth", 0.0))
	return total


## A deterministic, Variant-serialisable view of the mutable sparse state.
## The caller owns file I/O and run policy; this layer only answers what one
## resumed simulation needs.  Sorting removes Dictionary iteration order from
## saves, which keeps replay diffs readable and stable.
func create_persistence_snapshot() -> Dictionary:
	var keys: Array[Vector2i] = []
	for raw_key in _tiles:
		if raw_key is Vector2i:
			keys.append(raw_key as Vector2i)
	keys.sort_custom(_comes_before)
	var tiles: Array[Dictionary] = []
	for key in keys:
		var record: Dictionary = _tiles[key]
		tiles.append({
			"x": key.x,
			"z": key.y,
			"depth_m": float(record.get("depth", 0.0)),
			"touched_tick": int(record.get("touched", 0)),
		})
	return {
		"version": PERSISTENCE_VERSION,
		"tile_size_m": tile_size_m,
		"maximum_tiles": maximum_tiles,
		"tick": _tick,
		"tiles": tiles,
	}


## Parses into this newly-created candidate only.  No caller state changes on
## malformed or newer data, so a failed load cannot erase live snow.
func restore_persistence_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", -1)) != PERSISTENCE_VERSION:
		return false
	if not _is_finite_number(snapshot.get("tile_size_m", null)) \
			or not _is_finite_number(snapshot.get("maximum_tiles", null)) \
			or not _is_finite_number(snapshot.get("tick", null)):
		return false
	var snapshot_tile_size := float(snapshot["tile_size_m"])
	var snapshot_maximum_tiles := int(snapshot["maximum_tiles"])
	var snapshot_tick := int(snapshot["tick"])
	if snapshot_tile_size <= 0.0 or snapshot_maximum_tiles < 1 \
			or snapshot_maximum_tiles > MAX_PERSISTED_TILES or snapshot_tick < 0:
		return false
	if absf(snapshot_tile_size - tile_size_m) > 0.000001 \
			or snapshot_maximum_tiles != maximum_tiles:
		return false
	var raw_tiles = snapshot.get("tiles", null)
	if not (raw_tiles is Array):
		return false
	var records := raw_tiles as Array
	if records.size() > snapshot_maximum_tiles:
		return false
	var restored := {}
	for raw_record in records:
		if not (raw_record is Dictionary):
			return false
		var record := raw_record as Dictionary
		if not (record.has("x") and record.has("z") and record.has("depth_m") \
				and record.has("touched_tick")):
			return false
		if not _is_finite_number(record["x"]) or not _is_finite_number(record["z"]) \
				or not _is_finite_number(record["depth_m"]) \
				or not _is_finite_number(record["touched_tick"]):
			return false
		var x := int(record["x"])
		var z := int(record["z"])
		var depth := float(record["depth_m"])
		var touched := int(record["touched_tick"])
		if float(x) != float(record["x"]) or float(z) != float(record["z"]) \
				or float(touched) != float(record["touched_tick"]) \
				or depth <= 0.0000001 or depth > 1.0 or touched < 0:
			return false
		var key := Vector2i(x, z)
		if restored.has(key):
			return false
		restored[key] = {"depth": depth, "touched": touched}
	_tiles = restored
	_tick = snapshot_tick
	_rebuild_age_index()
	return true


func persisted_tile_count() -> int:
	return _tiles.size()


func _rebuild_age_index() -> void:
	_age_heap.clear()
	_age_positions.clear()
	for raw_key in _tiles:
		if not (raw_key is Vector2i):
			continue
		var key := raw_key as Vector2i
		var record: Dictionary = _tiles[key]
		_update_age_index(key, int(record.get("touched", 0)))


static func _is_finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _comes_before(left: Vector2i, right: Vector2i) -> bool:
	return left.x < right.x or (left.x == right.x and left.y < right.y)
