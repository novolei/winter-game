extends SceneTree

## Generates the opening mature-snow profile.  Run with:
##
##   Godot --headless --path <project> --script res://tools/generate_snow_field_profile.gd
##
## The safe corridors are copied from the scene's authored first-day anchors
## and Farmstead's existing road/trail geometry.  Keep this generator, rather
## than hand-editing the .tres, so the data file remains reproducible.

const OUTPUT_PATH := "res://data/snow/valley_profile.tres"
const FarmsteadScript := preload("res://src/entities/farmstead.gd")
const SnowFieldProfileScript := preload("res://src/definitions/snow_field_profile.gd")
const SnowRouteConstraintScript := preload("res://src/definitions/snow_route_constraint.gd")
const SnowShelterDefinitionScript := preload("res://src/definitions/snow_shelter_definition.gd")


func _initialize() -> void:
	var profile: SnowFieldProfile = SnowFieldProfileScript.new()
	# The sparse dynamic/persistence interpretation is unchanged: the veneer is
	# derived at query/render time and stores no new per-tile state.
	profile.persistence_version = 1
	profile.mature_variation_m = 0.08
	profile.variation_frequency_per_m = 0.025
	profile.variation_octaves = 2
	profile.variation_gain = 0.45
	profile.minimum_imprintable_cover_m = 0.08
	profile.full_imprint_depth_m = 0.08
	profile.max_boot_depression_m = 0.035
	profile.residual_cover_m = 0.02
	profile.footprint_response_depth_m = 0.16
	profile.protected_routes = [
		_route(_points([
			Vector3.ZERO,
			# Player's zero transform to Farmhouse + Doorstep in scenes/main.tscn.
			Vector3(14.8, 0.0, -10.8),
		]), 2.6, 1.8),
		_route(_points(FarmsteadScript.ROAD), 3.2, 1.8),
		_route(_points([
			FarmsteadScript.SPUR_JUNCTION,
			FarmsteadScript.SPUR_BEND,
			# Truck transform in scenes/main.tscn; _spur() continues below it.
			Vector3(4.85, 0.0, -18.16),
		]), 2.2, 1.5),
		_route(_points(FarmsteadScript.YARD), 4.0, 1.8),
		_route(_points(FarmsteadScript.TRAIL_TO_THE_EAST), 0.75, 1.25),
		_route(_points(FarmsteadScript.TRAIL_TO_THE_WELL), 0.75, 1.25),
	]
	# These are fixed, large wind breaks authored as location facts rather than
	# discovered by an every-tick scene query.  The corridor itself stays safe;
	# the nearby lee pockets merely give optional open snow a readable drift.
	profile.shelters = [
		_shelter(Vector2(21.0, -13.0), 3.0, 10.0, 5.0, 0.75),
		_shelter(Vector2(-18.0, -10.0), 2.0, 8.0, 4.0, 0.60),
		_shelter(Vector2(30.0, 18.0), 2.5, 12.0, 5.0, 0.65),
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/snow"))
	var error := ResourceSaver.save(profile, OUTPUT_PATH)
	if error != OK:
		push_error("generate_snow_field_profile: failed to save %s (%d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("generate_snow_field_profile: wrote %s" % OUTPUT_PATH)
	quit()


func _route(points: PackedVector2Array, half_width_m: float, feather_m: float) -> SnowRouteConstraint:
	var route: SnowRouteConstraint = SnowRouteConstraintScript.new()
	route.points = points
	route.half_width_m = half_width_m
	route.feather_m = feather_m
	return route


func _shelter(
	centre: Vector2, radius_m: float, lee_length_m: float, lee_half_width_m: float, strength: float
) -> SnowShelterDefinition:
	var shelter: SnowShelterDefinition = SnowShelterDefinitionScript.new()
	shelter.centre = centre
	shelter.radius_m = radius_m
	shelter.lee_length_m = lee_length_m
	shelter.lee_half_width_m = lee_half_width_m
	shelter.shelter_strength = strength
	return shelter


func _points(world_points: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for world in world_points:
		if world is Vector3:
			var point := world as Vector3
			points.append(Vector2(point.x, point.z))
	return points
