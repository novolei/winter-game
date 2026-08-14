class_name BreadcrumbScatter
extends MultiMeshInstance3D

## One cheap, deterministic handful of bread.  MultiMesh keeps all visible
## pieces in one draw, while this node integrates the short arcs on the CPU so a
## food patch has a definite landing place for animal navigation.  The pigeon
## never tries to infer gameplay state from a GPU particle buffer.

const PALETTE: ColorBible = preload("res://data/palette/color_bible.tres")
const PIECES := 14
const GRAVITY_MPS2 := 7.0
const MIN_FLIGHT_SECONDS := 0.70
const MAX_FLIGHT_SECONDS := 0.78
const PATCH_HALF_WIDTH_M := 0.36
const PATCH_HALF_DEPTH_M := 0.27
# Long enough for a pigeon at the edge of the 4.8 m interaction range to walk
# to the 2.05 m throw, finish its 1.667 s peck, and still visibly eat the patch.
const SETTLED_LIFETIME_SECONDS := 12.0

var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _landings: Array[Vector3] = []
var _flight_left: Array[float] = []
var _settled: Array[bool] = []
var _turns: Array[float] = []
var _settled_for := 0.0


func _ready() -> void:
	_ensure_visual()


func _process(delta: float) -> void:
	advance(delta)


## `origin` and `target` are world-space.  The node is normally parented to the
## root-level flock, but keeping the samples in world-space makes the contract
## equally honest in a capture or under a moved harness.
func scatter(origin: Vector3, target: Vector3, seed: int) -> void:
	_ensure_visual()
	_positions.clear()
	_velocities.clear()
	_landings.clear()
	_flight_left.clear()
	_settled.clear()
	_turns.clear()
	_settled_for = 0.0

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for index in range(PIECES):
		# A disk-like handful rather than a square stamp: the forward rows are a
		# little narrower, which reads as one hand opening in a fan.
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf())
		var landing := target + Vector3(
			cos(angle) * PATCH_HALF_WIDTH_M * radius,
			0.0,
			sin(angle) * PATCH_HALF_DEPTH_M * radius
		)
		landing.y = target.y
		var seconds := rng.randf_range(MIN_FLIGHT_SECONDS, MAX_FLIGHT_SECONDS)
		var velocity := (landing - origin) / seconds
		velocity.y += 0.5 * GRAVITY_MPS2 * seconds
		_positions.append(origin)
		_velocities.append(velocity)
		_landings.append(landing)
		_flight_left.append(seconds)
		_settled.append(false)
		_turns.append(rng.randf_range(-PI, PI))
	_sync_instances()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _positions.is_empty():
		return
	var step := delta
	var all_down := true
	for index in range(_positions.size()):
		if _settled[index]:
			continue
		all_down = false
		var used := minf(step, _flight_left[index])
		var velocity := _velocities[index]
		_positions[index] += velocity * used + Vector3.DOWN * (0.5 * GRAVITY_MPS2 * used * used)
		velocity.y -= GRAVITY_MPS2 * used
		_velocities[index] = velocity
		_flight_left[index] -= used
		_turns[index] += used * (7.0 + float(index % 5))
		if _flight_left[index] <= 0.0001:
			_positions[index] = _landings[index]
			_velocities[index] = Vector3.ZERO
			_settled[index] = true
	if not all_down and settled_count() == _positions.size():
		all_down = true
	if all_down:
		_settled_for += step
		if _settled_for >= SETTLED_LIFETIME_SECONDS and is_inside_tree():
			queue_free()
	_sync_instances()


func crumb_count() -> int:
	return _positions.size()


func settled_count() -> int:
	var count := 0
	for down in _settled:
		if down:
			count += 1
	return count


func crumb_positions() -> Array[Vector3]:
	return _positions.duplicate()


func _ensure_visual() -> void:
	if multimesh != null:
		return
	var piece := BoxMesh.new()
	piece.size = Vector3(0.024, 0.012, 0.019)
	var material := StandardMaterial3D.new()
	if PALETTE != null and PALETTE.warm_tones.size() > 2:
		material.albedo_color = PALETTE.warm_tones[2]
	material.roughness = 1.0
	piece.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = piece
	instances.instance_count = 0
	multimesh = instances
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sync_instances() -> void:
	if multimesh == null:
		return
	if multimesh.instance_count != _positions.size():
		multimesh.instance_count = _positions.size()
	for index in range(_positions.size()):
		var basis := Basis(Vector3.UP, _turns[index])
		multimesh.set_instance_transform(index, Transform3D(basis, _positions[index]))
