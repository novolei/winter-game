extends MultiMeshInstance3D

## A tiny, pooled drawing of pigeon tracks. Forty-eight marks remain one draw
## call; inactive slots are zero-scaled, and old marks shrink as wind-blown snow
## closes over them. This deliberately does not enter the traveller's physical
## footprint, height-field or audio systems.

const PALETTE: ColorBible = preload("res://data/palette/color_bible.tres")

@export_range(8, 96, 1) var capacity := 48
@export var calm_lifetime_seconds := 6.0
@export var gale_lifetime_seconds := 2.2
@export var surface_lift_m := 0.018

const BOUNDS_PADDING := Vector3(0.10, 0.06, 0.10)

var _remaining: Array[float] = []
var _lifetimes: Array[float] = []
var _bases: Array[Transform3D] = []


func _ready() -> void:
	setup()


func setup() -> void:
	if multimesh != null:
		return
	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.mesh = _foot_mesh()
	pool.instance_count = capacity
	pool.visible_instance_count = 0
	multimesh = pool
	material_override = _material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 0.12


func stamp(at: Vector3, heading: Vector3, wind_strength := 0.0) -> void:
	setup()
	if multimesh == null or capacity <= 0:
		return
	var direction := Vector3(heading.x, 0.0, heading.z)
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var yaw := atan2(direction.x, direction.z)
	var basis := Basis(Vector3.UP, yaw)
	var local_at := to_local(at) if is_inside_tree() else at
	var base := Transform3D(basis, local_at + Vector3.UP * surface_lift_m)
	var lifetime := lifetime_for(wind_strength)
	if _bases.size() >= capacity:
		_bases.pop_front()
		_remaining.pop_front()
		_lifetimes.pop_front()
	_bases.append(base)
	_remaining.append(lifetime)
	_lifetimes.append(lifetime)
	_sync_instances()


func advance(delta: float) -> void:
	if multimesh == null or delta <= 0.0:
		return
	for index in range(_remaining.size() - 1, -1, -1):
		_remaining[index] = maxf(_remaining[index] - delta, 0.0)
		if _remaining[index] <= 0.0:
			_bases.remove_at(index)
			_remaining.remove_at(index)
			_lifetimes.remove_at(index)
	_sync_instances()


func _process(delta: float) -> void:
	advance(delta)


func active_count() -> int:
	return _remaining.size()


func instance_scale(index: int) -> float:
	if index < 0 or index >= _remaining.size():
		return 0.0
	return _scale_for(index)


func lifetime_for(wind_strength: float) -> float:
	return lerpf(
		maxf(calm_lifetime_seconds, 0.1),
		maxf(gale_lifetime_seconds, 0.1),
		clampf(wind_strength, 0.0, 1.0)
	)


func _scale_for(index: int) -> float:
	var fraction := _remaining[index] / maxf(_lifetimes[index], 0.001)
	return smoothstep(0.0, 0.68, fraction)


func _sync_instances() -> void:
	if multimesh == null:
		return
	for index in _bases.size():
		var base := _bases[index]
		var scale := _scale_for(index)
		multimesh.set_instance_transform(index, Transform3D(
			base.basis.scaled(Vector3.ONE * scale), base.origin))
	# Dense active instances avoid singular hidden transforms altogether. The
	# GPU submits precisely the live prefix and nothing for expired marks.
	multimesh.visible_instance_count = _bases.size()
	_sync_live_bounds()


## MultiMesh does not derive a useful AABB when it begins with zero visible
## instances. Without an explicit live bound, every valid footprint transform
## can be submitted and the renderer still culls the entire one-draw-call pool.
func _sync_live_bounds() -> void:
	if _bases.is_empty():
		custom_aabb = AABB()
		return
	var first := _bases[0].origin
	var bounds := AABB(first - BOUNDS_PADDING, BOUNDS_PADDING * 2.0)
	for index in range(1, _bases.size()):
		var at := _bases[index].origin
		bounds = bounds.expand(at - BOUNDS_PADDING)
		bounds = bounds.expand(at + BOUNDS_PADDING)
	custom_aabb = bounds


func _foot_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Four separate tapered strokes read as an unmistakable bird track: three
	# toes opening ahead and one short rear toe. The negative space between them
	# is deliberate. A single connected triangle fan collapsed into a dark dash
	# under the fixed orthographic camera and looked like droppings.
	_add_tapered_toe(tool, Vector2(0.000, 0.009), Vector2(0.000, 0.070), 0.008)
	_add_tapered_toe(tool, Vector2(-0.004, 0.008), Vector2(-0.048, 0.048), 0.007)
	_add_tapered_toe(tool, Vector2(0.004, 0.008), Vector2(0.048, 0.048), 0.007)
	_add_tapered_toe(tool, Vector2(0.000, 0.001), Vector2(-0.012, -0.035), 0.006)
	tool.generate_normals()
	return tool.commit()


func _add_tapered_toe(
	tool: SurfaceTool,
	base: Vector2,
	tip: Vector2,
	half_width: float
) -> void:
	var direction := (tip - base).normalized()
	var across := Vector2(-direction.y, direction.x) * half_width
	var shoulder := base.lerp(tip, 0.42)
	var left := shoulder + across
	var right := shoulder - across
	# Two triangles make a small pointed lozenge instead of one long needle.
	_add_triangle(tool, base, left, tip)
	_add_triangle(tool, base, tip, right)


func _add_triangle(tool: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	tool.add_vertex(Vector3(a.x, 0.0, a.y))
	tool.add_vertex(Vector3(b.x, 0.0, b.y))
	tool.add_vertex(Vector3(c.x, 0.0, c.y))


func _material() -> StandardMaterial3D:
	var ink := StandardMaterial3D.new()
	# A shallow compression in snow catches the same cool slate as the terrain's
	# own shadow band. It remains legible without becoming black graphic ink.
	ink.albedo_color = PALETTE.snow_tones[3]
	ink.roughness = 1.0
	ink.metallic = 0.0
	ink.metallic_specular = 0.0
	ink.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A track is a paper-thin calligraphic mark. Drawing both sides avoids losing
	# two splayed toes to winding when the fixed camera sees the snow from above.
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	return ink
