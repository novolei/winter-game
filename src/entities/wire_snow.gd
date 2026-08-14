extends Node3D

## A narrow, low-poly crown of snow sitting on a stretched power wire.
##
## The wire mesh stays deliberately bare: a normal-based snow shader on a
## seven-centimetre cable breaks into distracting dark dashes. This component
## gives that special case one continuous 20-section top crown instead. It reads
## the same SnowAccumulation cover as every roof and prop, rebuilds only after a
## visible cover change, and carries no collider or per-frame particle rate.

const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const SnowfallLayerScript := preload("res://src/rendering/snowfall_layer.gd")
const PerchSnowShedScript := preload("res://src/entities/perch_snow_shed.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SNOW_SERVICE := &"snow_accumulation"

## A wire is a one-metre mesh on -Z; Farmstead stretches its parent transform
## to the actual span length. Twenty pieces are enough to look naturally lumpy
## from the fixed camera while remaining one ArrayMesh and one draw call.
const DRIFT_SEGMENTS := 20
const CAP_START := 0.0
const CAP_END := 1.0
## The span runs almost towards the fixed camera, so a narrow cable needs a
## broad readable snow lip. It grows only toward local +X: mirroring it around
## zero drew one grey snow line on each side of the dark cable. Keeping this
## side fixed (rather than following camera or wind) also prevents a visible
## side-swap when a gust changes or a cinematic camera becomes current.
## These are exactly 90% of the previously accepted root-to-lip spans (and 63%
## of the original broad crown), with the embedded root held fixed. Multiplying
## the lip coordinates themselves by .90 would not reduce the actual sheet by
## the requested ten percent because the root lives at negative X.
const CAP_THIN_LIP_X_M := 0.0632
const CAP_LIP_X_M := 0.0821
## The imported cable occupies X/Y=-.035..+.035. The inner root sits inside its
## upper half, while the lip rises outside +X. At opening cover the sheet first
## crosses Y=.035 at about X=+.013 m: every exposed pixel is therefore on one
## side, yet the 1.5 cm vertical overlap makes a raster gap impossible.
const CAP_ROOT_X_M := -0.025
const CAP_ROOT_Y_M := 0.020
const CAP_MIN_COVER := 0.035
## Match CelPainter's 8-bit visible-cover buckets. The former .015 threshold
## held four visible weather steps and made a slowly growing wire jump roughly
## once a minute; one bucket keeps the crown gradual without rebuilding it for
## sub-pixel cover noise every frame.
const CAP_REBUILD_DELTA := 1.0 / 255.0
const BIRD_CLEAR_SECONDS := 1.35
## Total physical width, not a fraction of the span. A fixed fraction made a
## bird punch a metre-wide hole in the long service wire.
const BIRD_CLEAR_WIDTH_M := 0.40
## Five crows and six pigeons can share this one wire. Manual GPU emissions use
## only inactive slots and fail silently when the pool is full, so capacity has
## to include both flocks plus a still-living landing tail for every bird.
const GRAIN_BUFFER := 512
const GRAIN_LIFETIME := 0.95
const MIST_BUFFER := 256
const MIST_LIFETIME := 0.82

var _snow: Object
var _painter: CelPainter
var _caps: MeshInstance3D
var _grains: GPUParticles3D
var _mist: GPUParticles3D
var _tone := Color()
var _cap_tone := Color()
var _rendered_cover := -1.0
var _cleared_until: Array[Dictionary] = []
var _grain_emissions := 0
var _mist_emissions := 0
var _last_burst_at := Vector3.ZERO
var _last_clear_width_m := 0.0
var _particle_bounds := AABB()


func _ready() -> void:
	prepare_visuals_for_test()


func _process(_delta: float) -> void:
	if _snow == null or not is_instance_valid(_snow):
		_resolve_snow()
	if _snow == null or not _snow.has_method(&"cover"):
		return
	var cover := clampf(float(_snow.call(&"cover")), 0.0, 1.0)
	var expired := _expire_cleared_patches()
	if expired or absf(cover - _rendered_cover) >= CAP_REBUILD_DELTA:
		_set_cover(cover, expired)


## Called through PerchPoints' parent by Bird. The landing removes just one
## hand-width of the cap, then throws a few hard grains and a restrained powder
## puff from that exposed spot. The particles are manually emitted, like boot
## snow, so there is no permanent emitter cost while the wire is empty.
func receive_perch_landing(perch: Dictionary) -> void:
	_receive_perch_event(perch, false)


## The feet have left the wire. Bird guarantees this callback once per launch;
## this receiver makes that one call wider and stronger to sell the wing wash.
func receive_perch_departure(perch: Dictionary) -> void:
	_receive_perch_event(perch, true)


func _receive_perch_event(perch: Dictionary, departure: bool) -> void:
	if _caps == null:
		return
	var cover := _current_cover()
	# Bare wire must not invent either particles or an exposed patch.
	if cover < CAP_MIN_COVER:
		return
	var span_length_m := _perch_span_length(perch)
	var clear_fraction := clearance_fraction(span_length_m)
	var local: Vector3 = perch.get("local", Vector3.ZERO)
	var fraction := clampf(-local.z, 0.0, 1.0)
	_record_clear_patch(fraction, clear_fraction * 0.5)
	_last_clear_width_m = clear_fraction * span_length_m
	_set_cover(cover, true)
	_emit_bird_shed(_perch_world_position(perch), perch, cover, departure)


## Public pure helpers: visual capture tests can judge the physical response
## without rendering a particle system or waiting for weather.
static func cap_height(cover: float) -> float:
	if cover < CAP_MIN_COVER:
		return 0.0
	var amount := smoothstep(CAP_MIN_COVER, 1.0, clampf(cover, 0.0, 1.0))
	# Six millimetres makes the first settled line continuous at the 10.5 m
	# camera stop; storm cover grows it into a crown rather than adding dashes.
	return lerpf(0.010, 0.085, amount)


static func cap_lip_x(cover: float) -> float:
	if cover < CAP_MIN_COVER:
		return 0.0
	var amount := smoothstep(CAP_MIN_COVER, 1.0, clampf(cover, 0.0, 1.0))
	return lerpf(CAP_THIN_LIP_X_M, CAP_LIP_X_M, amount)


static func drift_is_occupied(index: int, cover: float) -> bool:
	return index >= 0 and index < DRIFT_SEGMENTS and cover >= CAP_MIN_COVER


## Converts the physical hand-width into this particular span's local fraction.
## Multiplying the answer back by the span length always returns 0.40 m (unless
## the entire wire is shorter than that).
static func clearance_fraction(span_length_m: float) -> float:
	if span_length_m <= 0.0001:
		return 0.0
	return clampf(BIRD_CLEAR_WIDTH_M / span_length_m, 0.0, 1.0)


static func bird_clearance_metres() -> float:
	return BIRD_CLEAR_WIDTH_M


static func cover_rebuild_step() -> float:
	return CAP_REBUILD_DELTA


## One source of truth for both testable strength and the emitted populations.
	## Width is the physical bloom envelope, not the clear patch above.
static func burst_profile(cover: float, departure: bool) -> Dictionary:
	if cover < CAP_MIN_COVER:
		return {"grains": 0, "mist": 0, "width_m": 0.0, "speed_m_s": 0.0}
	var amount := smoothstep(CAP_MIN_COVER, 1.0, clampf(cover, 0.0, 1.0))
	if departure:
		return {
			"grains": int(round(lerpf(17.0, 28.0, amount))),
			"mist": int(round(lerpf(7.0, 13.0, amount))),
			"width_m": lerpf(0.48, 0.70, amount) \
				* PerchSnowShedScript.BLOOM_SPATIAL_SCALE,
			"speed_m_s": lerpf(0.48, 0.88, amount) \
				* PerchSnowShedScript.BLOOM_SPATIAL_SCALE,
		}
	return {
		# The live snowfall bed can visually swallow a very small landing puff.
		# Keep it below the wing-wash take-off, but give the foot impact enough
		# local density to read against an active storm at the gameplay camera.
		"grains": int(round(lerpf(10.0, 16.0, amount))),
		"mist": int(round(lerpf(4.0, 7.0, amount))),
		"width_m": lerpf(0.22, 0.32, amount) \
			* PerchSnowShedScript.BLOOM_SPATIAL_SCALE,
		"speed_m_s": lerpf(0.22, 0.42, amount) \
			* PerchSnowShedScript.BLOOM_SPATIAL_SCALE,
	}


## Read-only observation points used by unit/capture probes. They describe
## accepted manual emissions, not GPU completion, so they work headlessly.
func emission_totals() -> Dictionary:
	return {"grains": _grain_emissions, "mist": _mist_emissions}


func last_burst_position() -> Vector3:
	return _last_burst_at


func last_clear_width_metres() -> float:
	return _last_clear_width_m


## Build the draw nodes immediately for a deterministic test/capture probe.
## Production still enters through `_ready()`; the guard prevents a second set
## if a probe prepares the component before adding it to a SceneTree.
func prepare_visuals_for_test() -> void:
	if _caps != null:
		return
	_tone = _snow_tone()
	# The main near-field flakes are what the player reads as falling snow. Their
	# shared derived colour is used opaquely for this settled surface; bird-shed
	# particles retain the base palette snow tone below. Because this derived
	# colour is outside the stepped palette, CelPainter keeps it in both bands,
	# while still carrying the same world lighting profile as every roof.
	_cap_tone = SnowfallLayerScript.primary_flake_colour(_tone)
	_painter = CelPainterScript.new()
	_caps = MeshInstance3D.new()
	_caps.name = "SnowCaps"
	_caps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_caps.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_caps)
	_build_grains()
	_build_mist()
	_set_cover(0.0, true)


func _set_cover(cover: float, force := false) -> void:
	var clamped := clampf(cover, 0.0, 1.0)
	if not force and absf(clamped - _rendered_cover) < CAP_REBUILD_DELTA:
		return
	_rendered_cover = clamped
	_rebuild_caps(clamped)


func _rebuild_caps(cover: float) -> void:
	if _caps == null:
		return
	var height := cap_height(cover)
	if height <= 0.0:
		_caps.mesh = null
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var interval := (CAP_END - CAP_START) / float(DRIFT_SEGMENTS)
	var lip_x := cap_lip_x(cover)
	for index in range(DRIFT_SEGMENTS):
		if not drift_is_occupied(index, cover):
			continue
		var fraction_from := CAP_START + interval * float(index)
		var fraction_to := CAP_START + interval * float(index + 1)
		# Sections touch exactly and the first/last section meet the imported
		# cable's Z=0/-1 endpoints. The former 3.5% margins left more than a metre
		# of bare cable at each pole on the production span.
		for visible in _uncleared_ranges(fraction_from, fraction_to):
			_append_drift(
				vertices, normals, indices, -visible.x, -visible.y, height, lip_x
			)
	if vertices.is_empty():
		_caps.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_caps.mesh = mesh
	# `bare` prevents the generic accumulation overlay from laying a second,
	# darker snow layer over a mesh that is already entirely snow.
	_caps.material_override = _painter.material_for(_cap_tone, true)


## One broad, upward-facing sheet reads as snow resting on one side of the
## cable. Its root is hidden inside the real mesh and its outer lip carries the
## requested thickness. The old closed symmetric prism exposed two downward
## shoulder faces; they shaded grey and read as a second snow line on each side.
func _append_drift(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	z_from: float,
	z_to: float,
	height: float,
	lip_x: float
) -> void:
	var root := Vector3(CAP_ROOT_X_M, CAP_ROOT_Y_M, 0.0)
	var lip := Vector3(lip_x, height, 0.0)
	# This sheet is only a few pixels wide. Its geometric slope pushed it into a
	# dark band that read unlike every other upward snow surface, so author the
	# same UP normal the roof/ground snow presents to the shared cel lighting.
	var surface_normal := Vector3.UP
	_append_quad(vertices, normals, indices,
		root + Vector3(0.0, 0.0, z_from),
		lip + Vector3(0.0, 0.0, z_from),
		lip + Vector3(0.0, 0.0, z_to),
		root + Vector3(0.0, 0.0, z_to), surface_normal)


func _append_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3
) -> void:
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	# Godot treats clockwise triangles as front-facing. Reverse the mathematical
	# cross-product winding while retaining the authored upward normal, so the
	# shared roof-snow material shows its lit band instead of a culled top and two
	# dark shoulders.
	indices.append_array(PackedInt32Array([
		base, base + 2, base + 1, base, base + 3, base + 2,
	]))


func _build_grains() -> void:
	_grains = GPUParticles3D.new()
	_grains.name = "BirdSnowShed"
	_grains.local_coords = false
	_grains.amount = GRAIN_BUFFER
	_grains.lifetime = GRAIN_LIFETIME
	_grains.one_shot = false
	_grains.emitting = false
	_grains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grains.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grains.visibility_aabb = AABB(Vector3.ZERO, Vector3.ONE * 0.001)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = 0.8
	motion.damping_max = 1.25
	motion.gravity = Vector3(0.0, -4.5, 0.0)
	# At the default 17 m framing these resolve to 2.6--4.2 px in an 800 px
	# viewport. The old 1--2 px grains vanished into the ambient snowfall.
	motion.scale_min = 0.055
	motion.scale_max = 0.090
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -120.0
	motion.angular_velocity_max = 120.0
	_grains.process_material = motion
	_grains.draw_pass_1 = PerchSnowShedScript.irregular_grain_mesh(_grain_surface())
	add_child(_grains)
	# The wire parent is stretched tens of metres along Z. World-space particle
	# simulation alone does not remove that scale from the initial manual emit,
	# so detach the pool and keep its authored transforms truly world-space.
	_grains.set_as_top_level(true)
	_grains.global_transform = Transform3D.IDENTITY


func _build_mist() -> void:
	_mist = GPUParticles3D.new()
	_mist.name = "BirdSnowMist"
	_mist.local_coords = false
	_mist.amount = MIST_BUFFER
	_mist.lifetime = MIST_LIFETIME
	_mist.one_shot = false
	_mist.emitting = false
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mist.visibility_aabb = AABB(Vector3.ZERO, Vector3.ONE * 0.001)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = 2.4
	motion.damping_max = 3.2
	motion.gravity = Vector3(0.0, -0.42, 0.0)
	motion.scale_min = PerchSnowShedScript.MIST_MIN_DIAMETER_M
	motion.scale_max = PerchSnowShedScript.MIST_MAX_DIAMETER_M
	motion.scale_curve = _mist_scale_curve()
	_mist.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mist_surface()
	_mist.draw_pass_1 = quad
	add_child(_mist)
	_mist.set_as_top_level(true)
	_mist.global_transform = Transform3D.IDENTITY


func _emit_bird_shed(
	at: Vector3, perch: Dictionary, cover: float, departure: bool
) -> void:
	if _grains == null or _mist == null or cover < CAP_MIN_COVER:
		return
	var profile := burst_profile(cover, departure)
	var axes := _perch_axes(perch)
	var side: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var along: Vector3 = axes[2]
	var origin := at + up * cap_height(cover)
	var width_m := float(profile["width_m"])
	var speed_m_s := float(profile["speed_m_s"])
	_last_burst_at = at
	_expand_particle_bounds(at, width_m)
	var grain_count := int(profile["grains"])
	var grain_phase := randf()
	var bloom_shape := PerchSnowShedScript._random_bloom_shape()
	for index in range(grain_count):
		var sphere := PerchSnowShedScript.spherical_direction(
			index, grain_count, grain_phase, side, up, along
		)
		var radial := PerchSnowShedScript.irregular_bloom_vector(
			sphere, side, up, along, bloom_shape,
			PerchSnowShedScript._random_direction_jitter()
		)
		var lift := randf_range(0.06, 0.25) if departure else randf_range(0.03, 0.15)
		var velocity := radial * speed_m_s * randf_range(
			PerchSnowShedScript.GRAIN_REACH_MIN, PerchSnowShedScript.GRAIN_REACH_MAX
		) + up * lift
		var position := origin + radial * randf_range(0.0, width_m * 0.22)
		_grains.emit_particle(
			Transform3D(Basis.IDENTITY, position),
			velocity, _cap_tone, _cap_tone,
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
		)
	_grain_emissions += grain_count
	var mist_count := int(profile["mist"])
	var mist_phase := randf()
	for index in range(mist_count):
		var sphere := PerchSnowShedScript.spherical_direction(
			index, mist_count, mist_phase, side, up, along
		)
		var radial := PerchSnowShedScript.irregular_bloom_vector(
			sphere, side, up, along, bloom_shape,
			PerchSnowShedScript._random_direction_jitter()
		)
		var mist_speed := speed_m_s * randf_range(
			PerchSnowShedScript.MIST_REACH_MIN, PerchSnowShedScript.MIST_REACH_MAX
		)
		var lift := randf_range(0.02, 0.10)
		var velocity := radial * mist_speed + up * lift
		var position := origin + radial * randf_range(0.0, width_m * 0.12)
		_mist.emit_particle(
			Transform3D(Basis.IDENTITY, position), velocity, _cap_tone, _cap_tone,
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
		)
	_mist_emissions += mist_count


func _expand_particle_bounds(at: Vector3, width_m: float) -> void:
	# The detached pools have identity global transforms, so their culling boxes
	# use world coordinates too. Grow one conservative box around every live
	# contact rather than inheriting the wire's 30+ metre non-uniform scale.
	# The 2.2-times bloom plus its gravity tail can travel farther than the old
	# compact two-metre box. Keep the entire 0.95 s tail alive at the view edge.
	var margin := maxf(width_m + 3.5, 4.5)
	var extent := Vector3.ONE * margin
	var around := AABB(at - extent, extent * 2.0)
	if _particle_bounds.size.length_squared() <= 0.000001:
		_particle_bounds = around
	else:
		_particle_bounds = _particle_bounds.merge(around)
	_grains.visibility_aabb = _particle_bounds
	_mist.visibility_aabb = _particle_bounds


func _grain_surface() -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(_cap_tone.r, _cap_tone.g, _cap_tone.b, 0.95)
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	return surface


func _mist_surface() -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	# The radial texture gets every visible RGB channel from the palette tone;
	# its varying channel is alpha only, so this is softness rather than a new
	# scene colour gradient.
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
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 0.58, 0.82, 1.0])
	var colors := PackedColorArray()
	# A broad low-opacity radial falloff reads as suspended powder rather than
	# another set of bright flakes. Density and expansion provide visibility.
	for alpha in PerchSnowShedScript.MIST_ALPHA_PROFILE:
		colors.append(Color(_cap_tone.r, _cap_tone.g, _cap_tone.b, alpha))
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


func _mist_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 0.42))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(0.72, 1.68))
	curve.add_point(Vector2(0.92, 1.88))
	# Shrinking only in the final few frames prevents a low-alpha billboard from
	# blinking off; the short life keeps it a wing puff, not hanging fog.
	curve.add_point(Vector2(1.0, 0.02))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _resolve_snow() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method(&"get_service"):
		_snow = registry.call(&"get_service", SNOW_SERVICE)


func _current_cover() -> float:
	if _snow != null and _snow.has_method(&"cover"):
		return clampf(float(_snow.call(&"cover")), 0.0, 1.0)
	return maxf(_rendered_cover, 0.0)


func _record_clear_patch(fraction: float, half_width: float) -> void:
	var until := _now_seconds() + BIRD_CLEAR_SECONDS
	for index in range(_cleared_until.size()):
		var patch := _cleared_until[index]
		if absf(float(patch["fraction"]) - fraction) <= 0.0001:
			patch["until"] = until
			patch["half_width"] = maxf(float(patch["half_width"]), half_width)
			_cleared_until[index] = patch
			return
	_cleared_until.append({
		"fraction": fraction,
		"half_width": half_width,
		"until": until,
	})


## Subtracts the exact physical bird patch from a crown section. Testing only a
## section midpoint would quantise a 0.40 m hand-width to a 1.7 m chunk on the
## longest wire.
func _uncleared_ranges(fraction_from: float, fraction_to: float) -> Array[Vector2]:
	var ranges: Array[Vector2] = [Vector2(fraction_from, fraction_to)]
	for patch in _cleared_until:
		var centre := float(patch["fraction"])
		var half_width := float(patch["half_width"])
		var cut_from := centre - half_width
		var cut_to := centre + half_width
		var next: Array[Vector2] = []
		for visible in ranges:
			if cut_to <= visible.x or cut_from >= visible.y:
				next.append(visible)
				continue
			if cut_from > visible.x:
				next.append(Vector2(visible.x, minf(cut_from, visible.y)))
			if cut_to < visible.y:
				next.append(Vector2(maxf(cut_to, visible.x), visible.y))
		ranges = next
	return ranges


func _perch_world_position(perch: Dictionary) -> Vector3:
	var local: Vector3 = perch.get("local", Vector3.ZERO)
	var anchor = perch.get("anchor", null)
	if anchor != null and is_instance_valid(anchor) and anchor.has_method(&"placement"):
		var placed: Transform3D = anchor.call(&"placement")
		return placed * local
	return perch.get("at", _own_placement().origin)


func _perch_span_length(perch: Dictionary) -> float:
	var anchor = perch.get("anchor", null)
	if anchor != null and is_instance_valid(anchor) and anchor.has_method(&"placement"):
		var placed: Transform3D = anchor.call(&"placement")
		return placed.basis.z.length()
	return _own_placement().basis.z.length()


func _perch_axes(perch: Dictionary) -> Array[Vector3]:
	var placed := _own_placement()
	var anchor = perch.get("anchor", null)
	if anchor != null and is_instance_valid(anchor) and anchor.has_method(&"placement"):
		placed = anchor.call(&"placement")
	var side := placed.basis.x.normalized()
	var up := placed.basis.y.normalized()
	var along := -placed.basis.z.normalized()
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	return [side, up, along]


func _own_placement() -> Transform3D:
	if is_inside_tree():
		return global_transform
	var placed := transform
	var above := get_parent()
	while above is Node3D:
		placed = (above as Node3D).transform * placed
		above = above.get_parent()
	return placed


func _expire_cleared_patches() -> bool:
	var now := _now_seconds()
	var kept: Array[Dictionary] = []
	var expired := false
	for patch in _cleared_until:
		if float(patch["until"]) > now:
			kept.append(patch)
		else:
			expired = true
	_cleared_until = kept
	return expired


func _snow_tone() -> Color:
	var bible = load(PALETTE_PATH)
	if bible != null and bible.snow_tones.size() > 0:
		return bible.snow_tones[0]
	return Color()


static func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
