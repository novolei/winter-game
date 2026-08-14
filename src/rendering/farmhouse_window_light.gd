class_name FarmhouseWindowLight
extends Node3D

## Turns the farmhouse's high/low warm panes into one visual promise: the upper
## storey is the hero light and the lower storey is its quieter homecoming echo.
##
## The effect is deliberately layered rather than made from one powerful light:
##
##   PANE    an isolated HDR emissive material, so the window has a bright core;
##   HALO    a restrained rectangular corona, so bloom does not erase the frame;
##   SHAFT   a thin sheet of warm air between the pane and the porch roof;
##   SPILL   two emissive Decals: upper on the porch roof, lower on nearby snow.
##
## A SpotLight3D is intentionally absent. The snow shader now has a controlled
## local-fire path, but this broad architectural reflection is still authored
## as a shaped Decal rather than as another unbounded light source.
##
## The master signal is equally deliberate:
##
##   LightingPreset.warm_accent_energy * Stove fire fraction * (1 - reveal)
##
## LightingDirector already crossfades that first value through day, night and
## weather.  This component consumes the result instead of learning what a day
## or a storm is, so there is no second clock or weather state machine to drift.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const PANE_SHADER_PATH := "res://src/rendering/window_emission.gdshader"
const SCATTER_SHADER_PATH := "res://src/rendering/window_scatter.gdshader"
## TerrainRenderer owns visual layer 4 for snow. The window spill is an
## intentionally shaped reflection on that surface, unlike unbounded local
## point lights, so it follows the snow across the layer split.
const SNOW_RENDER_LAYER := 1 << 3

const RUNTIME_HALO_UPPER := &"WindowHaloUpper"
const RUNTIME_HALO_LOWER := &"WindowHaloLower"
const RUNTIME_SHAFT_UPPER := &"WindowShaftUpper"
const RUNTIME_SHAFT_LOWER := &"WindowShaftLower"
const RUNTIME_SPILL_ROOF := &"PorchRoofSpill"
const RUNTIME_SPILL_LOWER := &"LowerSnowSpill"
const UPPER_WARM_SLOT := "PAL_WARM_3"
const LOWER_WARM_SLOT := "PAL_WARM_3_AUX"

@export_group("Authored Contract")
@export var model_path := NodePath("../Model")
@export var window_part_path := NodePath("../Model/FH_Fade_Front")
@export var anchor_path := NodePath("../Model/Warm_Window_Upper")
@export var lower_anchor_path := NodePath("../Model/Warm_Window_Lower")
@export var fire_path := NodePath("../Stove")
@export var reveal_path := NodePath("../InteriorReveal")

@export_group("Upper Story Window")
@export var window_size := Vector2(1.0, 1.10)
@export var pane_emission_gain := 1.76
@export_range(0.0, 1.0, 0.01) var upper_muntin_strength := 0.88
## The pane itself reaches the palette's full amber at dusk. Before that it is
## a quieter cold-to-warm mixture; emission alone cannot prevent a flat orange
## albedo rectangle from shouting in broad daylight.
@export var pane_full_warm_energy := 1.60
@export var halo_expand := Vector2(0.66, 0.58)
@export var halo_offset := 0.035
@export var halo_energy_gain := 0.58
@export var halo_opacity := 0.14
@export var halo_edge_softness := 0.42

@export_group("Lower Story Window")
@export var lower_window_size := Vector2(1.40, 1.40)
@export var lower_pane_night_gain := 0.46
@export var lower_pane_day_gain := 0.30
@export_range(0.0, 1.0, 0.01) var lower_muntin_strength := 0.90
@export var lower_halo_expand := Vector2(0.72, 0.66)
@export var lower_halo_offset := 0.038
@export var lower_halo_energy_gain := 0.32
@export var lower_halo_opacity := 0.14
@export var lower_halo_edge_softness := 0.42

@export_group("Air Shaft")
## Local to the authored anchor.  The far edge rests just above the porch snow.
@export var shaft_near_offset := Vector3(0.0, -0.14, 0.045)
@export var shaft_far_offset := Vector3(0.0, -1.02, 1.58)
@export var shaft_near_width := 0.84
@export var shaft_far_width := 1.36
@export var shaft_energy_gain := 0.14
@export var shaft_opacity := 0.050
@export var shaft_edge_softness := 0.32

## A shorter, quieter breath from the lower wing pane to nearby snow.
@export var lower_shaft_near_offset := Vector3(0.0, -0.18, 0.045)
@export var lower_shaft_far_offset := Vector3(0.0, -1.56, 2.30)
@export var lower_shaft_near_width := 0.88
@export var lower_shaft_far_width := 2.10
@export var lower_shaft_energy_gain := 0.030
@export var lower_shaft_opacity := 0.025

@export_group("Porch Roof Spill")
## The porch roof falls 0.63 m over 3.25 m.  Keeping the slope here instead of
## rotating a scene node by eye makes the decal's projection axis agree with the
## generated roof and keeps the mask rectangular on the snow.
@export var porch_roof_slope := 0.63 / 3.25
@export var spill_offset := Vector3(0.0, -0.91, 1.36)
@export var spill_size := Vector2(1.34, 1.82)
@export var spill_projection_depth := 0.62
@export var spill_energy_gain := 0.76
@export_range(17, 129, 2) var spill_texture_size := 65

@export_group("Lower Window Snow Spill")
@export var lower_spill_offset := Vector3(0.0, -1.68, 2.55)
@export var lower_spill_size := Vector2(4.80, 5.40)
@export var lower_spill_projection_depth := 0.80
@export var lower_spill_energy_gain := 0.20

@export_group("Scatter Adaptation")
## Air and reflected snow are held back more aggressively than the pane while
## the world is bright. At night this reaches one; at pale_day it is a whisper.
@export var scatter_full_energy := 2.20
@export var scatter_gamma := 1.42

@export_group("Response")
## Seconds to arrive within roughly 99% of a new value.  Night changes over an
## eight-second LightingDirector crossfade; these only remove numerical steps
## and give a dying fire a little visual inertia.
@export var rise_seconds := 0.80
@export var fall_seconds := 1.35
@export var breath_amplitude := 0.026
@export var breath_hz := 0.115

var _lighting = null
var _fire = null
var _reveal = null

var _window_part: MeshInstance3D = null
var _anchor: Node3D = null
var _lower_anchor: Node3D = null
var _upper_warm_surface := -1
var _lower_warm_surface := -1
var _pane_material: ShaderMaterial = null
var _lower_pane_material: ShaderMaterial = null
var _halo_materials: Array[ShaderMaterial] = []
var _halo_gains := PackedFloat32Array()
var _shaft_materials: Array[ShaderMaterial] = []
var _shaft_gains := PackedFloat32Array()
var _spills: Array[Decal] = []
var _spill_gains := PackedFloat32Array()

var _resolved := false
var _elapsed := 0.0
var _energy := 0.0
var _scatter_energy := 0.0
var _accent_energy := 0.0
var _source_visibility := 0.0


func _ready() -> void:
	# Children ready before parents. Farmhouse._ready() repaints its whole model
	# through CelPainter, so applying the pane override now would be overwritten
	# one call later. This is the same load-bearing defer as InteriorWarmth.
	_start.call_deferred()


func _start() -> void:
	if not resolve():
		push_error(
			"farmhouse_window_light: could not resolve the authored window contract; "
			+ "the farmhouse will lose its paired exterior warm source"
		)


func set_lighting(source) -> void:
	_lighting = source


func set_fire(source) -> void:
	_fire = source


func set_reveal(source) -> void:
	_reveal = source


func pane_material() -> ShaderMaterial:
	return _pane_material


func lower_pane_material() -> ShaderMaterial:
	return _lower_pane_material


func energy() -> float:
	return _energy


func source_visibility() -> float:
	return _source_visibility


func roof_spill() -> Decal:
	return _spills[0] if not _spills.is_empty() else null


func lower_spill() -> Decal:
	return _spills[1] if _spills.size() > 1 else null


## The three inputs are public because their relationship is the behaviour, and
## because a test should not need a renderer to prove a dead stove is dark.
func target_energy(accent: float, fire_fraction: float, reveal_fade: float) -> float:
	if not is_finite(accent) or not is_finite(fire_fraction) or not is_finite(reveal_fade):
		return 0.0
	return maxf(accent, 0.0) * clampf(fire_fraction, 0.0, 1.0) \
		* (1.0 - clampf(reveal_fade, 0.0, 1.0))


## Albedo follows the same environment input as emission, but saturates at
## dusk. This keeps a trace of shelter in a pale day and reserves the complete
## amber pane for the hours when it becomes the composition's visual anchor.
func pane_warmth(accent: float, fire_fraction: float, reveal_fade: float) -> float:
	if not is_finite(accent) or not is_finite(fire_fraction) or not is_finite(reveal_fade):
		return 0.0
	var environment := 1.0 if pane_full_warm_energy <= 0.0 \
		else clampf(maxf(accent, 0.0) / pane_full_warm_energy, 0.0, 1.0)
	return environment * clampf(fire_fraction, 0.0, 1.0) \
		* (1.0 - clampf(reveal_fade, 0.0, 1.0))


## The lower storey says "someone is home" without competing with the upper
## story's promise. It stays especially quiet by day, then rises only to 46%
## of the hero pane after dusk.
func lower_pane_multiplier(accent: float) -> float:
	if not is_finite(accent):
		return 0.0
	var full := maxf(pane_full_warm_energy, 0.001)
	var t := smoothstep(0.25, 1.0, clampf(maxf(accent, 0.0) / full, 0.0, 1.0))
	return lerpf(lower_pane_day_gain, lower_pane_night_gain, t)


## Haze and reflected snow emerge later than the pane. Raising the normalized
## environment accent to a gentle gamma keeps pale-day spill from becoming a
## salmon decal while preserving the authored deep-night endpoint exactly.
func target_scatter_energy(accent: float, fire_fraction: float, reveal_fade: float) -> float:
	if not is_finite(accent) or not is_finite(fire_fraction) or not is_finite(reveal_fade):
		return 0.0
	var full := maxf(scatter_full_energy, 0.001)
	var adapted := full * pow(maxf(accent, 0.0) / full, maxf(scatter_gamma, 0.01))
	return adapted * clampf(fire_fraction, 0.0, 1.0) \
		* (1.0 - clampf(reveal_fade, 0.0, 1.0))


## Two incommensurate, very slow sines.  There is motion in a held shot, but no
## high-frequency flicker and no trough deep enough to read as the fire failing.
func breath_multiplier(seconds: float) -> float:
	if not is_finite(seconds):
		return 1.0
	var first := sin(seconds * TAU * breath_hz)
	var second := sin(seconds * TAU * breath_hz * 0.43 + 1.71)
	return 1.0 + breath_amplitude * (first * 0.72 + second * 0.28)


## A soft trapezoid painted in the palette's amber.  RGB never changes across
## the mask; only alpha describes how much light reaches a point, so this cannot
## introduce an unapproved hue into the world.
func spill_mask_image(size: int) -> Image:
	var bible := load(PALETTE_PATH) as ColorBible
	if bible == null or bible.warm_tones.is_empty():
		return null
	var side := maxi(size, 3)
	if side % 2 == 0:
		side += 1
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var warm: Color = bible.warm_tones[bible.warm_tones.size() - 1]
	for y in range(side):
		var v := float(y) / float(side - 1)
		# Wider away from the window, like the rectangular frustum that made it.
		var half_width := lerpf(0.30, 0.48, v)
		var along := smoothstep(0.0, 0.15, v) * (1.0 - smoothstep(0.48, 1.0, v))
		var falloff := lerpf(1.0, 0.48, v)
		for x in range(side):
			var u := float(x) / float(side - 1)
			var from_centre := absf(u - 0.5)
			var edge := 1.0 - smoothstep(half_width - 0.15, half_width, from_centre)
			var strength := clampf(edge * along * falloff, 0.0, 1.0)
			# Decal emission reads RGB, not the source texture's alpha. Premultiply
			# the palette hue so the black edge emits nothing and the feather is
			# visible instead of becoming one hard orange projector rectangle.
			var pixel := Color(warm.r * strength, warm.g * strength, warm.b * strength, strength)
			image.set_pixel(x, y, pixel)
	return image


## The ground outside the lower window is not a second beam. It is the broad,
## low-contrast return of light from snow: narrow where it leaves the wall,
## opening across several metres and dissolving before its projector boundary.
func area_spill_mask_image(size: int) -> Image:
	var bible := load(PALETTE_PATH) as ColorBible
	if bible == null or bible.warm_tones.is_empty():
		return null
	var side := maxi(size, 3)
	if side % 2 == 0:
		side += 1
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var warm: Color = bible.warm_tones[bible.warm_tones.size() - 1]
	for y in range(side):
		var v := float(y) / float(side - 1)
		var half_width := lerpf(0.18, 0.50, smoothstep(0.0, 0.82, v))
		var leaves_window := smoothstep(0.0, 0.10, v)
		var long_fade := 1.0 - smoothstep(0.18, 1.0, v)
		var along := leaves_window * long_fade * lerpf(0.88, 0.32, v)
		for x in range(side):
			var u := float(x) / float(side - 1)
			var from_centre := absf(u - 0.5)
			var feather := lerpf(0.12, 0.22, v)
			var across := 1.0 - smoothstep(half_width - feather, half_width, from_centre)
			var strength := clampf(along * across, 0.0, 1.0)
			image.set_pixel(x, y, Color(
				warm.r * strength, warm.g * strength, warm.b * strength, strength))
	return image


## Resolve the generated anchor and isolate only its PAL_WARM_3 surface.  Safe
## outside a SceneTree so the material and geometry contract can be unit tested.
func resolve() -> bool:
	if _resolved:
		return true
	var raw_part := get_node_or_null(window_part_path)
	var raw_anchor := get_node_or_null(anchor_path)
	var raw_lower_anchor := get_node_or_null(lower_anchor_path)
	_window_part = raw_part as MeshInstance3D
	_anchor = raw_anchor as Node3D
	_lower_anchor = raw_lower_anchor as Node3D
	if _window_part == null or _window_part.mesh == null \
			or _anchor == null or _lower_anchor == null:
		return false
	_upper_warm_surface = _find_surface(_window_part, UPPER_WARM_SLOT)
	_lower_warm_surface = _find_surface(_window_part, LOWER_WARM_SLOT)
	if _upper_warm_surface < 0 or _lower_warm_surface < 0:
		return false
	var bible := load(PALETTE_PATH) as ColorBible
	var pane_shader := load(PANE_SHADER_PATH) as Shader
	var scatter_shader := load(SCATTER_SHADER_PATH) as Shader
	if bible == null or bible.structure_tones.is_empty() or bible.warm_tones.is_empty() \
			or pane_shader == null or scatter_shader == null:
		return false
	var cold: Color = bible.structure_tones[bible.structure_tones.size() - 1]
	var warm: Color = bible.warm_tones[bible.warm_tones.size() - 1]
	var part_here := _transform_to_ancestor(_window_part, get_parent() as Node3D)
	var upper_in_part := part_here.affine_inverse() \
		* _transform_to_ancestor(_anchor, get_parent() as Node3D)
	var lower_in_part := part_here.affine_inverse() \
		* _transform_to_ancestor(_lower_anchor, get_parent() as Node3D)
	_pane_material = _make_pane_material(pane_shader, cold, warm,
		Vector2(upper_in_part.origin.x, upper_in_part.origin.y), window_size,
		upper_muntin_strength)
	_lower_pane_material = _make_pane_material(pane_shader, cold, warm,
		Vector2(lower_in_part.origin.x, lower_in_part.origin.y), lower_window_size,
		lower_muntin_strength)
	_window_part.set_surface_override_material(_upper_warm_surface, _pane_material)
	_window_part.set_surface_override_material(_lower_warm_surface, _lower_pane_material)

	var upper_here := _anchor_transform(_anchor)
	var lower_here := _anchor_transform(_lower_anchor)
	_build_halo(upper_here, warm, scatter_shader, window_size, halo_expand,
		halo_offset, halo_opacity, halo_edge_softness, halo_energy_gain, RUNTIME_HALO_UPPER)
	_build_halo(lower_here, warm, scatter_shader, lower_window_size, lower_halo_expand,
		lower_halo_offset, lower_halo_opacity, lower_halo_edge_softness,
		lower_halo_energy_gain, RUNTIME_HALO_LOWER)
	_build_shaft(upper_here, warm, scatter_shader, shaft_near_offset, shaft_far_offset,
		shaft_near_width, shaft_far_width, shaft_opacity, shaft_edge_softness,
		shaft_energy_gain, RUNTIME_SHAFT_UPPER)
	_build_shaft(lower_here, warm, scatter_shader,
		lower_shaft_near_offset, lower_shaft_far_offset,
		lower_shaft_near_width, lower_shaft_far_width, lower_shaft_opacity,
		shaft_edge_softness, lower_shaft_energy_gain, RUNTIME_SHAFT_LOWER)
	var mask := spill_mask_image(spill_texture_size)
	var area_mask := area_spill_mask_image(spill_texture_size)
	if mask == null or area_mask == null:
		return false
	var spill_texture := ImageTexture.create_from_image(mask)
	var area_texture := ImageTexture.create_from_image(area_mask)
	var roof_normal := Vector3(0.0, 1.0, porch_roof_slope).normalized()
	_build_spill(upper_here, spill_texture, roof_normal, spill_offset, spill_size,
		spill_projection_depth, spill_energy_gain, RUNTIME_SPILL_ROOF)
	_build_spill(lower_here, area_texture, Vector3.UP, lower_spill_offset,
		lower_spill_size, lower_spill_projection_depth, lower_spill_energy_gain,
		RUNTIME_SPILL_LOWER)
	_resolved = true
	_apply_visuals()
	return true


func _make_pane_material(
		shader: Shader, cold: Color, warm: Color,
		pane_center: Vector2, pane_extent: Vector2, muntin_strength: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cold_color", cold)
	material.set_shader_parameter("warm_color", warm)
	material.set_shader_parameter("warmth", 0.0)
	material.set_shader_parameter("emission_energy", 0.0)
	material.set_shader_parameter("pane_center", pane_center)
	material.set_shader_parameter("pane_size", pane_extent)
	material.set_shader_parameter("muntin_strength", muntin_strength)
	return material


func _find_surface(instance: MeshInstance3D, slot: String) -> int:
	for surface in range(instance.mesh.get_surface_count()):
		var material := instance.mesh.surface_get_material(surface)
		if material != null and _slot_matches(material.resource_name, slot):
			return surface
	return -1


func _slot_matches(resource_name: String, slot: String) -> bool:
	return resource_name == slot or resource_name.begins_with(slot + ".")


## Transform the anchor into this node's coordinates without touching a global
## transform. Node3D.global_position asserts outside a tree and returns a lying
## origin; unit subjects are intentionally outside a tree.
func _anchor_transform(anchor: Node3D) -> Transform3D:
	var parent_space := _transform_to_ancestor(anchor, get_parent() as Node3D)
	return transform.affine_inverse() * parent_space


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			chain.push_front((cursor as Node3D).transform)
		cursor = cursor.get_parent()
	var result := Transform3D.IDENTITY
	for step in chain:
		result *= step
	return result


func _build_halo(
		anchor_here: Transform3D, warm: Color, shader: Shader,
		pane_size: Vector2, expand: Vector2, offset: float, opacity: float,
		edge_softness: float, gain: float, node_name: StringName) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("light_color", warm)
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("edge_softness", edge_softness)
	material.set_shader_parameter("halo_mode", true)
	var quad := QuadMesh.new()
	quad.size = pane_size + expand
	quad.material = material
	var halo := MeshInstance3D.new()
	halo.name = node_name
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	halo.transform = anchor_here
	halo.position += anchor_here.basis.z.normalized() * offset
	add_child(halo)
	_halo_materials.append(material)
	_halo_gains.append(gain)


func _build_shaft(
		anchor_here: Transform3D, warm: Color, shader: Shader,
		near_offset: Vector3, far_offset: Vector3, near_width: float, far_width: float,
		opacity: float, edge_softness: float, gain: float, node_name: StringName) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("light_color", warm)
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("edge_softness", edge_softness)
	material.set_shader_parameter("halo_mode", false)
	var origin := anchor_here.origin
	var right := anchor_here.basis.x.normalized()
	var near := origin + anchor_here.basis * near_offset
	var far := origin + anchor_here.basis * far_offset
	var vertices := PackedVector3Array([
		near - right * near_width * 0.5,
		near + right * near_width * 0.5,
		far + right * far_width * 0.5,
		far - right * far_width * 0.5,
	])
	var uv := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var shaft := MeshInstance3D.new()
	shaft.name = node_name
	shaft.mesh = mesh
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(shaft)
	_shaft_materials.append(material)
	_shaft_gains.append(gain)


func _build_spill(
		anchor_here: Transform3D, texture: Texture2D, normal: Vector3,
		offset: Vector3, footprint: Vector2, projection_depth: float,
		gain: float, node_name: StringName) -> void:
	var along := Vector3.RIGHT.cross(normal).normalized()
	var basis := Basis(Vector3.RIGHT, normal, along)
	var spill := Decal.new()
	spill.name = node_name
	spill.size = Vector3(footprint.x, projection_depth, footprint.y)
	spill.transform = Transform3D(basis, anchor_here.origin + anchor_here.basis * offset)
	spill.texture_emission = texture
	spill.emission_energy = 0.0
	spill.upper_fade = 0.0
	spill.lower_fade = 0.0
	spill.normal_fade = 0.72
	# Snow only. The player and ordinary props must not turn orange merely by
	# crossing the intentionally authored ground reflection.
	spill.cull_mask = SNOW_RENDER_LAYER
	spill.visible = false
	add_child(spill)
	_spills.append(spill)
	_spill_gains.append(gain)


func _resolve_sources() -> void:
	if _lighting == null or not is_instance_valid(_lighting):
		var registry := get_node_or_null("/root/ServiceRegistry")
		if registry != null:
			_lighting = registry.call(&"get_service", &"lighting")
	if (_fire == null or not is_instance_valid(_fire)) and not fire_path.is_empty():
		_fire = get_node_or_null(fire_path)
	if (_reveal == null or not is_instance_valid(_reveal)) and not reveal_path.is_empty():
		_reveal = get_node_or_null(reveal_path)


func _accent() -> float:
	if _lighting == null or not is_instance_valid(_lighting) \
			or not _lighting.has_method(&"warm_accent_energy"):
		return 0.0
	var value: Variant = _lighting.call(&"warm_accent_energy")
	return float(value) if value is float or value is int else 0.0


func _fire_fraction() -> float:
	if _fire == null or not is_instance_valid(_fire):
		return 0.0
	if _fire.has_method(&"light_energy_now"):
		var now_value: Variant = _fire.call(&"light_energy_now")
		var maximum_value: Variant = _fire.get("light_energy")
		if (now_value is float or now_value is int) \
				and (maximum_value is float or maximum_value is int):
			var maximum := float(maximum_value)
			if is_finite(maximum) and maximum > 0.0:
				return clampf(float(now_value) / maximum, 0.0, 1.0)
	if _fire.has_method(&"is_lit"):
		return 1.0 if bool(_fire.call(&"is_lit")) else 0.0
	return 0.0


func _reveal_fade() -> float:
	if _reveal == null or not is_instance_valid(_reveal) or not _reveal.has_method(&"fade"):
		return 0.0
	var value: Variant = _reveal.call(&"fade")
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), 0.0, 1.0)


func _approach(current: float, target: float, delta: float) -> float:
	var seconds := rise_seconds if target > current else fall_seconds
	if seconds <= 0.0 or delta <= 0.0:
		return target if seconds <= 0.0 else current
	# exp(-4.605) = 0.01: after `seconds`, 99% of the move has arrived.
	var weight := 1.0 - exp(-4.605170 * delta / seconds)
	return lerpf(current, target, clampf(weight, 0.0, 1.0))


## Public tick for deterministic tests and captures; _process delegates to it.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_elapsed += delta
	_resolve_sources()
	var accent := _accent()
	var fire_fraction := _fire_fraction()
	var fade := _reveal_fade()
	var target := target_energy(accent, fire_fraction, fade)
	var scatter_target := target_scatter_energy(accent, fire_fraction, fade)
	var visible_target := pane_warmth(accent, fire_fraction, fade)
	_accent_energy = maxf(accent, 0.0) if is_finite(accent) else 0.0
	_energy = _approach(_energy, target, delta)
	_scatter_energy = _approach(_scatter_energy, scatter_target, delta)
	_source_visibility = _approach(_source_visibility, visible_target, delta)
	_apply_visuals()


func apply_immediately(accent: float, fire_fraction: float, reveal_fade: float) -> void:
	_accent_energy = maxf(accent, 0.0) if is_finite(accent) else 0.0
	_energy = target_energy(accent, fire_fraction, reveal_fade)
	_scatter_energy = target_scatter_energy(accent, fire_fraction, reveal_fade)
	_source_visibility = pane_warmth(accent, fire_fraction, reveal_fade)
	_apply_visuals()


func _geometry_visibility() -> float:
	if _window_part == null or not is_instance_valid(_window_part):
		return 1.0
	if not _window_part.visible:
		return 0.0
	# OccluderFader's second half replaces transparency with a silhouette
	# material and carries its actual alpha in this instance parameter. Reading
	# the rendered contract avoids a direct dependency and prevents the two
	# detached haze meshes from reappearing after the farmhouse itself faded.
	if _window_part.material_override != null:
		# The override is OccluderFader's deliberately neutral silhouette. Warm
		# haze is semantic light, not part of that readability silhouette, so it
		# must leave completely instead of glowing through the player.
		return 0.0
	return 1.0 - clampf(_window_part.transparency, 0.0, 1.0)


func _apply_visuals() -> void:
	if not _resolved:
		return
	var breath := breath_multiplier(_elapsed)
	var outside := _geometry_visibility()
	var lower_gain := lower_pane_multiplier(_accent_energy)
	_pane_material.set_shader_parameter("warmth", _source_visibility)
	_pane_material.set_shader_parameter("emission_energy", pane_emission_gain * _energy * breath)
	_lower_pane_material.set_shader_parameter("warmth", _source_visibility * lower_gain)
	_lower_pane_material.set_shader_parameter(
		"emission_energy", pane_emission_gain * lower_gain * _energy * breath)
	var scatter := _scatter_energy * breath * outside
	for index in range(_halo_materials.size()):
		_halo_materials[index].set_shader_parameter("intensity", _halo_gains[index] * scatter)
	for index in range(_shaft_materials.size()):
		_shaft_materials[index].set_shader_parameter("intensity", _shaft_gains[index] * scatter)
	for index in range(_spills.size()):
		var spill := _spills[index]
		spill.emission_energy = _spill_gains[index] * scatter
		spill.visible = spill.emission_energy > 0.001


func _process(delta: float) -> void:
	advance(delta)
