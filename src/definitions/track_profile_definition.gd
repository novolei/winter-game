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
## `wade` is the same 0..1 fact locomotion and the furrow use.  A dusting keeps
## a light planted sole; shallow snow records it most clearly, then collapsing
## walls take that definition away as the boot becomes a pocket in a drift.
@export_range(0.0, 1.0, 0.01) var shallow_wade := 0.35
@export_range(0.0, 1.0, 0.01) var medium_wade := 0.75
@export_range(0.0, 1.0, 0.01) var sole_definition_dust := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_shallow := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_medium := 0.0
@export_range(0.0, 1.0, 0.01) var sole_definition_deep := 0.0
@export_range(0.7, 1.3, 0.01) var dust_length_scale := 1.0
@export_range(0.7, 1.3, 0.01) var dust_width_scale := 1.0
@export_range(0.0, 0.9, 0.01) var dust_core := 0.55
@export_range(0.0, 0.9, 0.01) var dust_break := 0.18
## Deep walls can collapse into coarse lobes; a dusting cannot.  Scaling the
## same irregularity down at the profile boundary keeps the light sole intact
## without taking the torn edge away from medium and deep prints.
@export_range(0.0, 1.0, 0.01) var dust_irregularity_scale := 1.0

@export_group("Dusting pressure")
## Powder too thin to hold a boot-shaped pocket records the two load-bearing
## contacts instead: a restrained heel and a stronger forefoot.  These values
## are blended in by `scuff`, so a deep print keeps the complete sole above.
@export_range(0.0, 1.0, 0.01) var dust_waist_influence := 1.0
@export_range(0.5, 1.0, 0.01) var dust_lobe_length_scale := 1.0
@export_range(0.05, 1.0, 0.01) var dust_heel_weight := 1.0
@export_range(0.05, 1.0, 0.01) var dust_forefoot_weight := 1.0
## Camera-scale readability for the two shallow pressure contacts. It is
## interpolated by the same continuous `scuff` fact as the dust silhouette, so
## 1.0 means no change and a deep footprint remains byte-identical.
@export_range(1.0, 2.0, 0.01) var dust_readability_gain := 1.0


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
