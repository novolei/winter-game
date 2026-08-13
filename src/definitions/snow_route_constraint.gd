class_name SnowRouteConstraint
extends Resource

## A world-space corridor whose mature, seed-derived snow stays at the authored
## baseline.  It is deliberately a route rather than a collection of named
## gameplay objects: the snow field does not need to know what a road, doorstep
## or trail is in order to preserve the route they make possible.

@export var points := PackedVector2Array()
@export var half_width_m := 0.0
@export var feather_m := 0.0


## 1 inside the protected corridor, then a smooth fall to zero.  A smooth edge
## matters: a depth step is a normal step in the terrain shader, visible as a
## seam even when its colour is correct.
func protection_at(world_xz: Vector2) -> float:
	if points.size() < 2 or half_width_m <= 0.0:
		return 0.0
	var nearest := INF
	for index in range(points.size() - 1):
		nearest = minf(nearest, _distance_to_segment(world_xz, points[index], points[index + 1]))
	if nearest <= half_width_m:
		return 1.0
	if feather_m <= 0.0 or nearest >= half_width_m + feather_m:
		return 0.0
	return 1.0 - smoothstep(half_width_m, half_width_m + feather_m, nearest)


static func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var span := to - from
	var squared := span.length_squared()
	if squared <= 0.000001:
		return point.distance_to(from)
	var along := clampf((point - from).dot(span) / squared, 0.0, 1.0)
	return point.distance_to(from + span * along)
