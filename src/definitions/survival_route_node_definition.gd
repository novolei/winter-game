class_name SurvivalRouteNodeDefinition
extends Resource

## A readable beat along a route: sign, broken boundary, abandoned possession,
## or a finite pickup. Adding another beat is one generated .tres, never code.

@export var id: StringName = &""
@export var route_id: StringName = &""
@export var sequence := 0
@export var world_position := Vector3.ZERO
@export var yaw_degrees := 0.0
@export var model_scale := Vector3.ONE
@export var model_scene: PackedScene = null

@export_group("Pickup")
@export var item_id: StringName = &""
@export var item_count := 0
@export var interaction_radius_m := 2.2

@export_group("Snow")
@export var snow_receptivity_scale := 1.28
@export var snow_threshold_bias := -0.06


func is_pickup() -> bool:
	return item_id != &"" and item_count > 0


func is_valid() -> bool:
	return id != &"" \
		and route_id != &"" \
		and sequence >= 0 \
		and model_scene != null \
		and model_scale.x > 0.0 and model_scale.y > 0.0 and model_scale.z > 0.0 \
		and ((item_id == &"" and item_count == 0) \
			or (item_id != &"" and item_count > 0 and interaction_radius_m > 0.0))

