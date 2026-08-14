class_name SurvivalRouteDefinition
extends Resource

## One leg of the four-landmark survival circuit. Geometry, traversal snow and
## narrative identity are content; SurvivalRouteLayer is only the renderer.

@export var id: StringName = &""
@export var display_name := ""
@export var from_beacon: StringName = &""
@export var to_beacon: StringName = &""
@export var points := PackedVector2Array()

@export_group("Snow trace")
@export var bed_half_width_m := 1.05
@export_range(0.0, 1.0, 0.01) var bed_strength := 0.14
@export var rut_gauge_m := 0.66
@export var rut_radius_m := 0.08
@export_range(0.0, 1.0, 0.01) var rut_strength := 0.58
@export var edge_irregularity := 0.25

@export_group("Traversal")
@export var protected_half_width_m := 1.15
@export var protected_feather_m := 1.25


func is_valid() -> bool:
	return id != &"" \
		and from_beacon != &"" and to_beacon != &"" \
		and from_beacon != to_beacon \
		and points.size() >= 2 \
		and bed_half_width_m > 0.0 \
		and rut_gauge_m > 0.0 and rut_radius_m > 0.0 \
		and protected_half_width_m > 0.0 and protected_feather_m >= 0.0


func world_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points:
		result.append(Vector3(point.x, 0.0, point.y))
	return result

