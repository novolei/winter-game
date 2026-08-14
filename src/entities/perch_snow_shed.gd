class_name PerchSnowShed
extends Node3D

## Loose snow thrown by a bird gripping any declared snowy perch.
##
## This node is deliberately a SURFACE receiver rather than a bird behaviour.
## `Bird` already offers landings and departures to the direct parent of its
## `PerchPoints`; putting a declaration under this node therefore gives crows
## and pigeons the same physical response without either species learning what
## it stood on.
##
## It also deliberately owns NO settled geometry.  A wire has a narrow crown
## and a roof has a modelled blend-shape mass; those surfaces keep deciding how
## snow lies and whether a landing leaves a mark.  This one reusable component
## owns only the hard grains and short powder puff both surfaces can delegate.

const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const SnowfallLayerScript := preload("res://src/rendering/snowfall_layer.gd")

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SNOW_SERVICE := &"snow_accumulation"

enum Response {
	## Flat exposed tops use the world's accumulation cover directly.
	DIRECT_COVER,
	## A modelled roof begins later; use the same curve as its visible blend shape.
	ROOF_MASS,
}

@export var snow_response: Response = Response.DIRECT_COVER
## Five crows and six pigeons can overlap one snowy host: crows do not reserve
## occupied slots. Budget the two production flocks, not just the five authored
## positions, or a late bird's manual emission is silently dropped by the GPU.
@export_range(1, 32, 1) var max_shared_birds := 11

const DIRECT_COVER_ONSET := 0.035
const MIN_VISIBLE_SNOW := 0.015
const MAX_LANDING_GRAINS := 16
const MAX_DEPARTURE_GRAINS := 28
const MAX_LANDING_MIST := 7
const MAX_DEPARTURE_MIST := 13
const BUFFER_QUANTUM := 64
const GRAIN_LIFETIME := 0.95
const MIST_LIFETIME := 0.82
## The accepted compact bloom is now presented at 2.2 times its former spatial
## scale. Counts, lifetime, opacity and individual grain diameters stay put.
const BLOOM_SPATIAL_SCALE := 2.2
## Broad independent reach bands and a per-burst axis warp keep the edge
## organic. The Fibonacci base still guarantees coverage on every side.
const BLOOM_AXIS_MIN := 0.76
const BLOOM_AXIS_MAX := 1.24
const BLOOM_DIRECTION_JITTER := 0.12
const GRAIN_REACH_MIN := 0.32
const GRAIN_REACH_MAX := 1.08
const MIST_REACH_MIN := 0.26
const MIST_REACH_MAX := 0.92

## Matches the strengthened wire vocabulary. At the shipping 17 m frame in an
## 800 px-tall window the smallest grain is 2.59 px, clear of the two-pixel art
## gate while remaining much smaller than a bird's foot.
const GRAIN_MIN_DIAMETER_M := 0.055
const GRAIN_MAX_DIAMETER_M := 0.090
## Powder discs are independently 2.2x larger as requested; their low-alpha
## texture and short lifetime still keep them in the register of thin fog.
const MIST_VISUAL_SCALE := 2.2
const MIST_MIN_DIAMETER_M := 0.16 * MIST_VISUAL_SCALE
const MIST_MAX_DIAMETER_M := 0.26 * MIST_VISUAL_SCALE
## Larger discs overlap more often. Keep the 2.2x volume but reduce opacity so
## the overlap reads as thin suspended powder rather than bright round blobs.
const MIST_ALPHA_PROFILE := [0.14, 0.12, 0.07, 0.025, 0.0]

const INITIAL_VISIBILITY_BOUNDS := AABB(
	Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0)
)

var _snow: Object
var _grains: GPUParticles3D
var _mist: GPUParticles3D
var _grain_tone := Color()
var _mist_tone := Color()
var _visibility_bounds := INITIAL_VISIBILITY_BOUNDS
var _grain_emissions := 0
var _mist_emissions := 0
var _last_burst_at := Vector3.ZERO
var _last_axes: Array[Vector3] = []
var _last_profile: Dictionary = {}


func _ready() -> void:
	prepare_visuals_for_test()
	if _snow == null or not is_instance_valid(_snow):
		_resolve_snow()


## Injection seam used by a surface composition and by headless tests.  Normal
## production instances resolve the same service from ServiceRegistry in
## `_ready()` or on the first event if registration order ever changes.
func set_snow_source(source: Object) -> void:
	_snow = source


## Bird's direct-parent receiver vocabulary.
func receive_perch_landing(perch: Dictionary) -> void:
	_receive_perch_event(perch, false)


func receive_perch_departure(perch: Dictionary) -> void:
	_receive_perch_event(perch, true)


func _receive_perch_event(perch: Dictionary, departure: bool) -> void:
	if _snow == null or not is_instance_valid(_snow):
		_resolve_snow()
	var amount := surface_amount(_current_cover(), snow_response)
	emit_shed(perch, amount, departure)


## Public composition door for a specialised host such as WireSnow.  The host
## remains responsible for deciding how much loose snow its own visible surface
## carries; this method owns profile, placement, particle populations and rings.
func emit_shed(perch: Dictionary, snow_amount: float, departure: bool) -> void:
	prepare_visuals_for_test()
	if _grains == null or _mist == null:
		return
	var profile := burst_profile(snow_amount, departure)
	var grain_count := int(profile["grains"])
	var mist_count := int(profile["mist"])
	if grain_count <= 0 and mist_count <= 0:
		return
	var at := perch_world_position(perch)
	var axes := perch_axes(perch)
	var side: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var along: Vector3 = axes[2]
	var width_m := float(profile["width_m"])
	var speed_m_s := float(profile["speed_m_s"])
	var origin := at + up * float(profile["origin_lift_m"])
	_expand_visibility(at, width_m)
	_last_burst_at = at
	_last_axes = axes
	_last_profile = profile.duplicate()

	var grain_phase := randf()
	var bloom_shape := _random_bloom_shape()
	for index in range(grain_count):
		var sphere := spherical_direction(
			index, grain_count, grain_phase, side, up, along
		)
		var radial := irregular_bloom_vector(
			sphere, side, up, along, bloom_shape, _random_direction_jitter()
		)
		var lift := randf_range(0.06, 0.25) if departure else randf_range(0.03, 0.15)
		var velocity := radial * speed_m_s * randf_range(GRAIN_REACH_MIN, GRAIN_REACH_MAX) \
			+ up * lift
		var position := origin + radial * randf_range(0.0, width_m * 0.22)
		_grains.emit_particle(
			Transform3D(Basis.IDENTITY, position), velocity, _grain_tone, _grain_tone,
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
		)
	_grain_emissions += grain_count

	var mist_phase := randf()
	for index in range(mist_count):
		var sphere := spherical_direction(index, mist_count, mist_phase, side, up, along)
		var radial := irregular_bloom_vector(
			sphere, side, up, along, bloom_shape, _random_direction_jitter()
		)
		var mist_speed := speed_m_s * randf_range(MIST_REACH_MIN, MIST_REACH_MAX)
		var velocity := radial * mist_speed + up * randf_range(0.02, 0.10)
		var position := origin + radial * randf_range(0.0, width_m * 0.12)
		_mist.emit_particle(
			Transform3D(Basis.IDENTITY, position), velocity, _mist_tone, _mist_tone,
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
		)
	_mist_emissions += mist_count


## Converts world accumulation into loose snow actually present at this surface.
## A roof cannot use cover directly: its plane is marked bare and the player sees
## only CelPainter's later modelled mass curve.
static func surface_amount(cover: float, response: int) -> float:
	var clamped := clampf(cover, 0.0, 1.0)
	if response == Response.ROOF_MASS:
		return CelPainterScript.snow_mass(clamped)
	if clamped <= DIRECT_COVER_ONSET:
		return 0.0
	return smoothstep(DIRECT_COVER_ONSET, 1.0, clamped)


## One shared physical vocabulary for eaves, crossarms and a later WireSnow
## delegation.  Input is effective loose snow, NOT raw world cover.
static func burst_profile(snow_amount: float, departure: bool) -> Dictionary:
	var amount := clampf(snow_amount, 0.0, 1.0)
	if amount < MIN_VISIBLE_SNOW:
		return {
			"grains": 0, "mist": 0, "width_m": 0.0,
			"speed_m_s": 0.0, "origin_lift_m": 0.0,
		}
	var strength := smoothstep(MIN_VISIBLE_SNOW, 1.0, amount)
	if departure:
		return {
			"grains": int(round(lerpf(17.0, 28.0, strength))),
			"mist": int(round(lerpf(7.0, 13.0, strength))),
			"width_m": lerpf(0.48, 0.70, strength) * BLOOM_SPATIAL_SCALE,
			"speed_m_s": lerpf(0.48, 0.88, strength) * BLOOM_SPATIAL_SCALE,
			"origin_lift_m": lerpf(0.04, 0.12, strength),
		}
	return {
		"grains": int(round(lerpf(10.0, 16.0, strength))),
		"mist": int(round(lerpf(4.0, 7.0, strength))),
		"width_m": lerpf(0.22, 0.32, strength) * BLOOM_SPATIAL_SCALE,
		"speed_m_s": lerpf(0.22, 0.42, strength) * BLOOM_SPATIAL_SCALE,
		"origin_lift_m": lerpf(0.02, 0.07, strength),
	}


## Manual rings cannot overwrite a living particle. Budget one strongest foot
## impact plus one strongest wing-wash tail per occupied perch, then round to a
## GPU-friendly block. Five authored places use 256 / 128; a future eleven-bird
## wire delegate gets 512 / 256 without cloning a second cache policy.
static func buffer_sizes(shared_birds: int) -> Vector2i:
	var birds := maxi(shared_birds, 1)
	var hard_need := birds * (MAX_LANDING_GRAINS + MAX_DEPARTURE_GRAINS)
	var mist_need := birds * (MAX_LANDING_MIST + MAX_DEPARTURE_MIST)
	return Vector2i(
		_round_buffer(hard_need),
		_round_buffer(mist_need),
	)


## A Fibonacci sphere gives every burst volume around the contact point instead
## of a long one-axis fan or a flat disc. One random phase rotates the sphere
## while the stratification prevents all particles clustering on one side.
static func spherical_direction(
	index: int, count: int, phase: float,
	side: Vector3, up: Vector3, along: Vector3
) -> Vector3:
	var safe_count := maxi(count, 1)
	var sample := float(index) + 0.5
	var vertical := 1.0 - 2.0 * sample / float(safe_count)
	var ring := sqrt(maxf(1.0 - vertical * vertical, 0.0))
	var turn := fposmod(sample * 0.61803398875 + phase, 1.0)
	var angle := turn * TAU
	var direction := side * (cos(angle) * ring) \
		+ along * (sin(angle) * ring) + up * vertical
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP


## Warps a stratified sphere into a slightly different irregular volume for
## every burst, then gives each particle its own small angular offset. Do not
## normalise: the retained length variation is what breaks the perfect shell.
static func irregular_bloom_vector(
	sphere: Vector3, side: Vector3, up: Vector3, along: Vector3,
	shape: Vector3, jitter: Vector3
) -> Vector3:
	var vector := side * (sphere.dot(side) * shape.x + jitter.x) \
		+ up * (sphere.dot(up) * shape.y + jitter.y) \
		+ along * (sphere.dot(along) * shape.z + jitter.z)
	return vector if vector.length_squared() > 0.0001 else up


static func _random_bloom_shape() -> Vector3:
	return Vector3(
		randf_range(BLOOM_AXIS_MIN, BLOOM_AXIS_MAX),
		randf_range(BLOOM_AXIS_MIN, BLOOM_AXIS_MAX),
		randf_range(BLOOM_AXIS_MIN, BLOOM_AXIS_MAX)
	)


static func _random_direction_jitter() -> Vector3:
	return Vector3(
		randf_range(-BLOOM_DIRECTION_JITTER, BLOOM_DIRECTION_JITTER),
		randf_range(-BLOOM_DIRECTION_JITTER, BLOOM_DIRECTION_JITTER),
		randf_range(-BLOOM_DIRECTION_JITTER, BLOOM_DIRECTION_JITTER)
	)


static func _round_buffer(required: int) -> int:
	return int(ceili(float(required) / float(BUFFER_QUANTUM))) * BUFFER_QUANTUM


## Live position, never the snapshot sampled when the flock chose the perch.
static func perch_world_position(perch: Dictionary) -> Vector3:
	var local: Vector3 = perch.get("local", Vector3.ZERO)
	var anchor = perch.get("anchor", null)
	if anchor != null and is_instance_valid(anchor) and anchor.has_method(&"placement"):
		var placed: Transform3D = anchor.call(&"placement")
		return placed * local
	return perch.get("at", Vector3.ZERO)


## `{side, up, along}` for the surface on this frame.  RUN declarations carry
## local +X on the eave while SPAN carries local -Z on a wire, so the declaration's
## `local_facing` is the authority; assuming one model axis breaks the other.
static func perch_axes(perch: Dictionary) -> Array[Vector3]:
	var placed := Transform3D.IDENTITY
	var anchor = perch.get("anchor", null)
	if anchor != null and is_instance_valid(anchor) and anchor.has_method(&"placement"):
		placed = anchor.call(&"placement")
	var up := placed.basis.y.normalized()
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	var local_facing: Vector3 = perch.get("local_facing", Vector3.ZERO)
	var along: Vector3 = placed.basis * local_facing if local_facing.length_squared() > 0.0001 \
		else perch.get("facing", Vector3.FORWARD)
	along -= up * along.dot(up)
	if along.length_squared() < 0.0001:
		along = -placed.basis.z
		along -= up * along.dot(up)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	along = along.normalized()
	var side: Vector3 = along.cross(up).normalized()
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	up = side.cross(along).normalized()
	return [side, up, along]


## Deterministic observation points for tests and renderer captures.  They count
## accepted manual emissions, not asynchronous GPU completion.
func emission_totals() -> Dictionary:
	return {"grains": _grain_emissions, "mist": _mist_emissions}


func last_burst_position() -> Vector3:
	return _last_burst_at


func last_burst_axes() -> Array[Vector3]:
	return _last_axes.duplicate()


func last_burst_profile() -> Dictionary:
	return _last_profile.duplicate()


func visibility_bounds() -> AABB:
	return _visibility_bounds


## Production enters through `_ready`; probes may build before entering a tree.
func prepare_visuals_for_test() -> void:
	if _grains != null:
		return
	var base_tone := _snow_tone()
	_grain_tone = particle_tone(base_tone)
	_mist_tone = _grain_tone
	_build_grains()
	_build_mist()


## Shared colour vocabulary for a later WireSnow delegate: both grains and the
## alpha-softened mist use the main falling flake colour, never an unrelated
## hardcoded white or a darker base snow swatch.
static func particle_tone(base_snow: Color) -> Color:
	return SnowfallLayerScript.primary_flake_colour(base_snow)


func _build_grains() -> void:
	_grains = GPUParticles3D.new()
	_grains.name = "PerchSnowGrains"
	_grains.local_coords = false
	_grains.amount = buffer_sizes(max_shared_birds).x
	_grains.lifetime = GRAIN_LIFETIME
	_grains.one_shot = false
	_grains.emitting = false
	_grains.fixed_fps = 60
	_grains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grains.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grains.visibility_aabb = _visibility_bounds
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = 0.65
	motion.damping_max = 1.05
	motion.gravity = Vector3(0.0, -5.2, 0.0)
	motion.scale_min = GRAIN_MIN_DIAMETER_M
	motion.scale_max = GRAIN_MAX_DIAMETER_M
	motion.scale_curve = _grain_scale_curve()
	# One asymmetric shard plus random orientation/rotation reads as many broken
	# snow clumps instead of a stream of identical square billboards.
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -120.0
	motion.angular_velocity_max = 120.0
	_grains.process_material = motion
	_grains.draw_pass_1 = irregular_grain_mesh(_grain_surface())
	add_child(_grains)


func _build_mist() -> void:
	_mist = GPUParticles3D.new()
	_mist.name = "PerchSnowMist"
	_mist.local_coords = false
	_mist.amount = buffer_sizes(max_shared_birds).y
	_mist.lifetime = MIST_LIFETIME
	_mist.one_shot = false
	_mist.emitting = false
	_mist.fixed_fps = 60
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mist.visibility_aabb = _visibility_bounds
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = 2.2
	motion.damping_max = 3.1
	motion.gravity = Vector3(0.0, -0.52, 0.0)
	motion.scale_min = MIST_MIN_DIAMETER_M
	motion.scale_max = MIST_MAX_DIAMETER_M
	motion.scale_curve = _mist_scale_curve()
	_mist.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mist_surface()
	_mist.draw_pass_1 = quad
	add_child(_mist)


func _grain_surface() -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = _with_alpha(_grain_tone, 0.98)
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	return surface


func _mist_surface() -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_texture = _mist_texture()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	return surface

func _mist_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.58, 0.84, 1.0])
	var colours := PackedColorArray()
	for alpha in MIST_ALPHA_PROFILE:
		colours.append(_with_alpha(_mist_tone, float(alpha)))
	gradient.colors = colours
	return _radial_texture(gradient, 32)


## A small centred eight-sided shard. The uneven perimeter is intentional and
## remains visible after arbitrary billboard rotation; scale randomness then
## gives the GPU population another independent silhouette dimension.
static func irregular_grain_mesh(material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3.ZERO,
		Vector3(-0.46, -0.14, 0.0),
		Vector3(-0.28, -0.47, 0.0),
		Vector3(0.08, -0.42, 0.0),
		Vector3(0.43, -0.24, 0.0),
		Vector3(0.49, 0.13, 0.0),
		Vector3(0.17, 0.44, 0.0),
		Vector3(-0.12, 0.38, 0.0),
		Vector3(-0.42, 0.25, 0.0),
	])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	# Godot considers clockwise triangles front-facing. A positive-Z billboard
	# therefore needs the mathematical cross product to point toward -Z while
	# its authored shading normal points toward +Z, matching QuadMesh FACE_Z.
	normals.fill(Vector3.BACK)
	var indices := PackedInt32Array()
	for outer in range(1, vertices.size()):
		var following := outer + 1 if outer + 1 < vertices.size() else 1
		indices.append_array(PackedInt32Array([0, following, outer]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _radial_texture(gradient: Gradient, size: int) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


func _grain_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.72))
	curve.add_point(Vector2(0.12, 1.0))
	curve.add_point(Vector2(0.76, 0.82))
	curve.add_point(Vector2(1.0, 0.04))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _mist_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 2.4
	curve.add_point(Vector2(0.0, 0.42))
	curve.add_point(Vector2(0.16, 1.0))
	curve.add_point(Vector2(0.70, 1.92))
	curve.add_point(Vector2(0.94, 2.18))
	curve.add_point(Vector2(1.0, 0.03))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## The custom AABB is emitter-local even though particles simulate in world
## coordinates.  Grow it around every accepted perch so the 8.5 m crossarm and
## a later long wire are not culled by a tiny box at their owner's origin.
func _expand_visibility(at: Vector3, width_m: float) -> void:
	var local_at := _own_placement().affine_inverse() * at
	# The 2.2-times bloom plus its gravity tail can travel farther than the old
	# compact two-metre box. Keep the entire 0.95 s tail alive at the view edge.
	var margin := maxf(width_m + 3.5, 4.5)
	var around := AABB(
		local_at - Vector3(margin, margin, margin),
		Vector3.ONE * margin * 2.0
	)
	_visibility_bounds = _visibility_bounds.merge(around)
	_grains.visibility_aabb = _visibility_bounds
	_mist.visibility_aabb = _visibility_bounds


func _own_placement() -> Transform3D:
	if is_inside_tree():
		return global_transform
	var placed := transform
	var above := get_parent()
	while above is Node3D:
		placed = (above as Node3D).transform * placed
		above = above.get_parent()
	return placed


func _resolve_snow() -> void:
	if not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method(&"get_service"):
		_snow = registry.call(&"get_service", SNOW_SERVICE)


func _current_cover() -> float:
	if _snow != null and is_instance_valid(_snow) and _snow.has_method(&"cover"):
		return clampf(float(_snow.call(&"cover")), 0.0, 1.0)
	return 0.0


func _snow_tone() -> Color:
	var bible = load(PALETTE_PATH)
	if bible != null and bible.snow_tones.size() > 0:
		return bible.snow_tones[0]
	return Color()


static func _with_alpha(tone: Color, alpha: float) -> Color:
	return Color(tone.r, tone.g, tone.b, alpha)
