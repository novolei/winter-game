extends SceneTree

## Generates the shipped snow-contact language.  Run with:
##
##   Godot --headless --path <project> --script res://tools/generate_snow_interactions.gd

const OUTPUT_DIRECTORY := "res://data/snow_interactions"
const DefinitionScript := preload("res://src/definitions/snow_interaction_definition.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var definitions := [
		_make(&"footprint", &"footprint", 1.0, 0.86, 0.24, 1800.0, 1.0, 1.0, 0.55, 0.20),
		_make(&"furrow", &"furrow", 0.72, 0.58, 0.40, 1700.0, 1.0, 0.76, 0.0, 0.0, 0.48, 0.012),
		_make(&"body_press", &"contact", 0.86, 0.72, 0.44, 1450.0, 1.0, 1.0, 0.38, 0.14),
		_make(&"impact", &"contact", 1.0, 0.86, 0.42, 1150.0, 1.0, 1.0, 0.34, 0.18),
		_make(&"drag", &"groove", 0.62, 0.54, 0.34, 1250.0, 1.0, 0.72, 0.24, 0.12, 0.62, 0.015),
	]
	for definition: SnowInteractionDefinition in definitions:
		var path := OUTPUT_DIRECTORY.path_join("%s.tres" % definition.interaction_id)
		var error := ResourceSaver.save(definition, path)
		if error != OK:
			push_error("generate_snow_interactions: failed to save %s (%d)" % [path, error])
			quit(1)
			return
	print("generate_snow_interactions: wrote %d definitions" % definitions.size())
	quit()


func _make(
	id: StringName, primitive: StringName, strength_scale: float, max_strength: float,
	depth_reference_m: float, pressure_reference: float, length_scale: float,
	width_scale: float, core: float, irregularity: float,
	continuity_floor := 1.0, meander_m := 0.0
) -> SnowInteractionDefinition:
	var definition: SnowInteractionDefinition = DefinitionScript.new()
	definition.interaction_id = id
	definition.primitive = primitive
	definition.strength_scale = strength_scale
	definition.max_strength = max_strength
	definition.depth_reference_m = depth_reference_m
	definition.pressure_reference_ns_m2 = pressure_reference
	definition.length_scale = length_scale
	definition.width_scale = width_scale
	definition.core = core
	definition.irregularity = irregularity
	definition.continuity_floor = continuity_floor
	definition.meander_m = meander_m
	return definition
