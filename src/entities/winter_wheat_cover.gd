class_name WinterWheatCover
extends Node3D

## A single, dense crown layer for the winter field.
##
## The planted furrows remain a snow-mask detail owned by Farmstead.  This node
## supplies what a mask cannot: the short, clustered silhouettes of living
## wheat.  It builds once into one MultiMesh, has no per-frame work, and keeps
## its field placement deterministic so composition does not change per run.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const WHEAT_SHADER_PATH := "res://src/rendering/winter_wheat_cover.gdshader"
## A 16 x 16 threshold tile is large enough that its blue-noise ordering does
## not repeat as a visible stamp between neighbouring furrows.  The tile is
## built once and shared by the single field cover.
const BLUE_TILE_SIZE := 16
## This void-and-cluster threshold order was baked at authoring time, rather
## than solved while the player enters the farm.  It preserves the progressive
## blue-noise property at every density threshold with only one array lookup
## per candidate in the shipped build.
static var _blue_noise_ranks := PackedFloat32Array([
	0.000000, 0.980469, 0.187500, 0.871094, 0.050781, 0.675781, 0.140625, 0.621094, 0.011719, 0.605469, 0.144531, 0.546875, 0.042969, 0.503906, 0.195312, 0.519531,
	0.800781, 0.257812, 0.574219, 0.476562, 0.628906, 0.382812, 0.804688, 0.281250, 0.656250, 0.468750, 0.710938, 0.300781, 0.667969, 0.445312, 0.691406, 0.484375,
	0.214844, 0.972656, 0.066406, 0.632812, 0.210938, 0.769531, 0.074219, 0.859375, 0.226562, 0.714844, 0.093750, 0.832031, 0.218750, 0.500000, 0.085938, 0.914062,
	0.906250, 0.472656, 0.570312, 0.425781, 0.554688, 0.421875, 0.878906, 0.402344, 0.937500, 0.304688, 0.886719, 0.292969, 0.789062, 0.253906, 0.707031, 0.437500,
	0.046875, 0.679688, 0.207031, 0.613281, 0.019531, 0.996094, 0.164062, 0.562500, 0.054688, 0.761719, 0.191406, 0.746094, 0.027344, 0.988281, 0.203125, 0.957031,
	0.941406, 0.441406, 0.687500, 0.378906, 0.824219, 0.386719, 0.660156, 0.250000, 0.960938, 0.296875, 0.535156, 0.453125, 0.867188, 0.269531, 0.601562, 0.363281,
	0.222656, 0.992188, 0.101562, 0.917969, 0.128906, 0.945312, 0.109375, 0.781250, 0.160156, 0.812500, 0.117188, 0.585938, 0.156250, 0.531250, 0.105469, 0.820312,
	0.582031, 0.316406, 0.742188, 0.359375, 0.910156, 0.488281, 0.851562, 0.496094, 0.695312, 0.492188, 0.773438, 0.328125, 0.921875, 0.347656, 0.964844, 0.417969,
	0.007812, 0.968750, 0.238281, 0.597656, 0.039062, 0.855469, 0.125000, 0.839844, 0.003906, 0.593750, 0.199219, 0.703125, 0.031250, 0.523438, 0.132812, 0.785156,
	0.816406, 0.339844, 0.722656, 0.308594, 0.527344, 0.410156, 0.550781, 0.320312, 0.644531, 0.261719, 0.882812, 0.433594, 0.664062, 0.324219, 0.875000, 0.285156,
	0.148438, 0.792969, 0.082031, 0.617188, 0.179688, 0.847656, 0.089844, 0.765625, 0.167969, 0.953125, 0.097656, 0.828125, 0.234375, 0.863281, 0.121094, 0.648438,
	0.730469, 0.355469, 0.515625, 0.398438, 0.835938, 0.429688, 0.507812, 0.343750, 0.738281, 0.460938, 0.976562, 0.449219, 0.640625, 0.464844, 0.625000, 0.371094,
	0.058594, 0.902344, 0.152344, 0.683594, 0.023438, 0.718750, 0.171875, 0.777344, 0.035156, 0.933594, 0.175781, 0.578125, 0.015625, 0.609375, 0.230469, 0.894531,
	0.757812, 0.277344, 0.843750, 0.480469, 0.929688, 0.457031, 0.566406, 0.332031, 0.898438, 0.394531, 0.589844, 0.289062, 0.753906, 0.273438, 0.808594, 0.335938,
	0.246094, 0.652344, 0.113281, 0.511719, 0.136719, 0.925781, 0.062500, 0.671875, 0.242188, 0.750000, 0.078125, 0.542969, 0.183594, 0.796875, 0.070312, 0.699219,
	0.636719, 0.390625, 0.558594, 0.414062, 0.726562, 0.367188, 0.734375, 0.351562, 0.539062, 0.312500, 0.890625, 0.406250, 0.984375, 0.265625, 0.949219, 0.375000,
])

## Matches Farmstead's planted field in world space.  Keeping the field here
## rather than reaching into Farmstead lets this surface remain reusable.
@export var field_origin := Vector2(-26.0, -62.0)
@export var field_length_m := 62.0
@export var field_width_m := 36.0

## One jittered candidate per 27 cm square.  The blue-noise rank decides which
## candidates survive; accepted tufts therefore stay mutually separated while
## broad patches still breathe in density.
@export var candidate_spacing_m := 0.27
@export var density_floor := 0.56
@export var density_ceil := 0.96
@export var density_patch_m := 6.5
@export var edge_feather_m := 0.9
@export var density_seed := 41077

## A four-leaf crown, 14 cm at its tallest before per-tuft variation.  This is
## intentionally lower than the old stubble: it should read as a soft field
## held down by snow, never as long upright grass.
@export var tuft_height_m := 0.14
@export var blades_per_tuft := 4

var estimated_tuft_count: int:
	get:
		var columns := int(ceil(field_length_m / candidate_spacing_m))
		var rows := int(ceil(field_width_m / candidate_spacing_m))
		return int(float(columns * rows) * (density_floor + density_ceil) * 0.5)


var estimated_triangle_count: int:
	get:
		return estimated_tuft_count * blades_per_tuft * 2


var built_tuft_count := 0
var built_triangle_count := 0


func _ready() -> void:
	_build_cover()


## Broad growth variation only decides how many already-spaced candidates
## survive.  It does not move the field rows or the furrow mask, so the result
## is a living field rather than unrelated dark confetti on top of the snow.
func density_at(world_position: Vector2) -> float:
	var coarse := _value_noise(world_position / density_patch_m, density_seed)
	var detail := _value_noise(world_position / (density_patch_m * 0.46), density_seed + 193)
	var growth := clampf(coarse * 0.72 + detail * 0.28, 0.0, 1.0)
	return lerpf(density_floor, density_ceil, smoothstep(0.16, 0.84, growth))


func _build_cover() -> void:
	var mesh := _build_tuft_mesh()
	if mesh == null:
		return
	var accepted := _accepted_transforms()
	built_tuft_count = accepted.size()
	built_triangle_count = built_tuft_count * blades_per_tuft * 2
	if accepted.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = accepted.size()
	for index in range(accepted.size()):
		multimesh.set_instance_transform(index, accepted[index])

	var crowns := MultiMeshInstance3D.new()
	crowns.name = "WinterWheatCrowns"
	crowns.multimesh = multimesh
	crowns.material_override = _material()
	crowns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crowns.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(crowns)


func _accepted_transforms() -> Array[Transform3D]:
	var columns := int(ceil(field_length_m / candidate_spacing_m))
	var rows := int(ceil(field_width_m / candidate_spacing_m))
	var transforms: Array[Transform3D] = []
	transforms.resize(0)
	var snow := _snow_field()
	for row in range(rows):
		for column in range(columns):
			var cell := Vector2i(column, row)
			var local := _candidate_position(cell)
			var world := field_origin + local
			var accepted_density := density_at(world) * edge_density_at(local)
			if blue_noise_rank(cell, density_seed) > accepted_density:
				continue
			var height := 0.84 + _hash_unit(cell.x, cell.y, density_seed + 41) * 0.28
			var width := 0.90 + _hash_unit(cell.x, cell.y, density_seed + 89) * 0.18
			var yaw := _hash_unit(cell.x, cell.y, density_seed + 149) * TAU
			var surface := 0.0
			if snow != null and snow.has_method(&"surface_height_at"):
				surface = float(snow.surface_height_at(Vector3(world.x, 0.0, world.y)))
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(width, height, width))
			transforms.append(Transform3D(basis, Vector3(world.x, surface, world.y)))
	return transforms


## Winter fields do have an edge, but it is never a mathematically sharp cut:
## snow settles into the headland and wind catches the outer rows first. The
## same blue threshold which spaces the interior feathers that transition,
## leaving a readable field boundary without a rectangular asset stamp.
func edge_density_at(local_position: Vector2) -> float:
	var nearest_edge := minf(
		minf(local_position.x, field_length_m - local_position.x),
		minf(local_position.y, field_width_m - local_position.y)
	)
	return smoothstep(0.04, maxf(0.05, edge_feather_m), nearest_edge)


## A short crossed leaf crown.  The leaves are deliberately flatter than a
## summer grass blade: their silhouette is a snow-pressed, low wheat carpet,
## not a field of dark upright needles. Four broad two-triangle ribbons buy a
## soft silhouette at this camera with only eight triangles per instance; at
## the expected count the entire field remains below 190k triangles.
func _build_tuft_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(blades_per_tuft):
		var angle := TAU * float(blade) / float(blades_per_tuft) + 0.18
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var root_width := 0.040
		var tip_width := 0.012
		var tip := direction * 0.165 + Vector3(0.0, tuft_height_m, 0.0)
		_add_leaf_triangle(tool, -side * root_width, side * root_width, tip + side * tip_width,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0))
		_add_leaf_triangle(tool, -side * root_width, tip + side * tip_width, tip - side * tip_width,
			Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
	tool.generate_normals()
	return tool.commit()


func _add_leaf_triangle(
	tool: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2
) -> void:
	tool.set_uv(uv_a)
	tool.add_vertex(a)
	tool.set_uv(uv_b)
	tool.add_vertex(b)
	tool.set_uv(uv_c)
	tool.add_vertex(c)


func _candidate_position(cell: Vector2i) -> Vector2:
	var x_jitter := (_hash_unit(cell.x, cell.y, density_seed + 17) - 0.5) * 0.54
	var z_jitter := (_hash_unit(cell.x, cell.y, density_seed + 71) - 0.5) * 0.54
	return Vector2(
		(float(cell.x) + 0.5 + x_jitter) * candidate_spacing_m,
		(float(cell.y) + 0.5 + z_jitter) * candidate_spacing_m
	)


func _material() -> ShaderMaterial:
	var bible: ColorBible = load(PALETTE_PATH)
	var material := ShaderMaterial.new()
	material.shader = load(WHEAT_SHADER_PATH) as Shader
	# The crown belongs one restrained step inside the snow family.  Using the
	# building family here made a distant field resolve into black pinpricks.
	material.set_shader_parameter("wheat_lit", bible.snow_tones[2])
	material.set_shader_parameter("wheat_shade", bible.snow_tones[4])
	material.set_shader_parameter("snow_lit", bible.snow_tones[0])
	material.set_shader_parameter("snow_shade", bible.snow_tones[3])
	CelPainter.register_world_material(material)
	return material


func _snow_field() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(&"snow_field") as Node


## A deterministic blue-noise threshold tile.  Rank 0 is placed first;
## every following rank is the unoccupied cell farthest from all earlier ranks
## on a wrapping 16x16 tile.  Thresholding it at any density therefore preserves
## separation instead of turning density variation into clumped white-noise
## holes.
static func blue_noise_rank(cell: Vector2i, seed: int) -> float:
	# The seed shifts the precomputed toroidal tile; the per-cell candidate
	# jitter supplies the non-repeating micro-variation without a runtime solve.
	var x := posmod(cell.x + (seed & 15), BLUE_TILE_SIZE)
	var y := posmod(cell.y + ((seed >> 4) & 15), BLUE_TILE_SIZE)
	return _blue_noise_ranks[y * BLUE_TILE_SIZE + x]


static func _value_noise(position: Vector2, seed: int) -> float:
	var cell := Vector2i(floori(position.x), floori(position.y))
	var fraction := position - Vector2(floor(position.x), floor(position.y))
	fraction = fraction * fraction * (Vector2(3.0, 3.0) - fraction * 2.0)
	var a := _hash_unit(cell.x, cell.y, seed)
	var b := _hash_unit(cell.x + 1, cell.y, seed)
	var c := _hash_unit(cell.x, cell.y + 1, seed)
	var d := _hash_unit(cell.x + 1, cell.y + 1, seed)
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)


static func _hash_unit(x: int, y: int, seed: int) -> float:
	var value := x * 374761393 + y * 668265263 + seed * 69069
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x00ffffff) / float(0x01000000)
