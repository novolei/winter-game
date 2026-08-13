class_name SnowShelterDefinition
extends Resource

## One authored obstruction whose lee collects wind-transported snow.  It is a
## world-space fact supplied by a location profile, not a runtime raycast
## against scene geometry.  That makes the snow field deterministic, cheap and
## replayable when a tile is revisited.

@export var centre := Vector2.ZERO
@export_range(0.0, 20.0, 0.1, "suffix:m") var radius_m := 0.0
@export_range(0.0, 40.0, 0.1, "suffix:m") var lee_length_m := 0.0
@export_range(0.0, 30.0, 0.1, "suffix:m") var lee_half_width_m := 0.0
@export_range(0.0, 1.0, 0.01) var shelter_strength := 0.0


## The wind vector points where the air is travelling.  `centre + wind` is the
## lee, so a weather veer naturally moves the pocket to the other side without
## storing directional state in the shelter itself.
func lee_weight_at(world_xz: Vector2, wind_direction: Vector2) -> float:
	if shelter_strength <= 0.0 or lee_length_m <= 0.0 or lee_half_width_m <= 0.0:
		return 0.0
	if wind_direction.length_squared() <= 0.000001:
		return 0.0
	var downwind := wind_direction.normalized()
	var offset := world_xz - centre
	var along := offset.dot(downwind)
	if along <= radius_m or along >= radius_m + lee_length_m:
		return 0.0
	var lateral := absf(offset.cross(downwind))
	if lateral >= lee_half_width_m:
		return 0.0
	var start := smoothstep(radius_m, radius_m + minf(lee_length_m * 0.25, 1.5), along)
	var end := 1.0 - smoothstep(
		radius_m + lee_length_m * 0.65, radius_m + lee_length_m, along
	)
	var width := 1.0 - smoothstep(lee_half_width_m * 0.55, lee_half_width_m, lateral)
	return clampf(start * end * width * shelter_strength, 0.0, 1.0)
