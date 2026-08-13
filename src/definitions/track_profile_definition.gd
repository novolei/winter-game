class_name TrackProfileDefinition
extends Resource

## One creature's authored language in snow.
##
## The mask still stores only anonymous compacted depth.  This resource decides
## the shape written at one footfall, so adding a bear, scavenger or different
## boot is a `.tres` addition rather than a new branch in TrackMask.

@export var profile_id: StringName = &""
@export var subjects: Array[StringName] = []

@export_group("Sole silhouette")
@export_range(-1.0, 1.0, 0.01) var heel_centre_x := -0.40
@export_range(0.05, 1.0, 0.01) var heel_half_length := 0.45
@export_range(0.05, 1.5, 0.01) var heel_half_width := 0.75
@export_range(-1.0, 1.0, 0.01) var waist_centre_x := 0.0
@export_range(0.05, 1.0, 0.01) var waist_half_length := 0.45
@export_range(0.05, 1.5, 0.01) var waist_half_width := 0.70
@export_range(-1.0, 1.0, 0.01) var forefoot_centre_x := 0.40
@export_range(0.05, 1.0, 0.01) var forefoot_half_length := 0.60
@export_range(0.05, 1.5, 0.01) var forefoot_half_width := 0.90

@export_group("Compression")
## A walking boot lands on the heel and leaves through the forefoot.  The
## difference is restrained: it should break the repeated-stamp read, never
## divide one print into two unrelated holes.
@export_range(0.1, 1.0, 0.01) var heel_weight := 1.0
@export_range(0.1, 1.0, 0.01) var forefoot_weight := 1.0
@export_range(-1.0, 1.0, 0.01) var weight_transition_from_x := -0.25
@export_range(-1.0, 1.0, 0.01) var weight_transition_to_x := 0.25

@export_group("Snow-depth language")
## `wade` is the same 0..1 fact locomotion and the furrow use.  A dusting is a
## scrape, shallow snow records the sole, then collapsing walls take that sole
## definition away again as the boot becomes a pocket in a drift.
@export_range(0.0, 1.0, 0.01) var shallow_wade := 0.35
@export_range(0.0, 1.0, 0.01) var medium_wade := 0.75
@export_range(0.0, 1.0, 0.01) var sole_definition_dust := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_shallow := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_medium := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_deep := 0.0


func sole_definition_at(wade: float) -> float:
	var depth := clampf(wade, 0.0, 1.0)
	var shallow := clampf(shallow_wade, 0.001, 0.999)
	var medium := clampf(medium_wade, shallow + 0.001, 1.0)
	if depth <= shallow:
		return lerpf(sole_definition_dust, sole_definition_shallow, depth / shallow)
	if depth <= medium:
		return lerpf(
			sole_definition_shallow, sole_definition_medium,
			(depth - shallow) / (medium - shallow)
		)
	return lerpf(
		sole_definition_medium, sole_definition_deep,
		(depth - medium) / maxf(1.0 - medium, 0.001)
	)


## Signed-distance-like union of three broad lobes.  It deliberately contains
## no tread grooves: at the game's camera they alias into noise, while this
## heel/waist/forefoot rhythm survives as one restrained boot silhouette.
func sole_distance(local: Vector2) -> float:
	return minf(
		_ellipse_distance(local, heel_centre_x, heel_half_length, heel_half_width),
		minf(
			_ellipse_distance(local, waist_centre_x, waist_half_length, waist_half_width),
			_ellipse_distance(
				local, forefoot_centre_x, forefoot_half_length, forefoot_half_width
			)
		)
	)


func compression_weight_at(along: float) -> float:
	var blend := smoothstep(weight_transition_from_x, weight_transition_to_x, along)
	return lerpf(heel_weight, forefoot_weight, blend)


static func _ellipse_distance(
	local: Vector2, centre_x: float, half_length: float, half_width: float
) -> float:
	return Vector2(
		(local.x - centre_x) / maxf(half_length, 0.001),
		local.y / maxf(half_width, 0.001)
	).length()
