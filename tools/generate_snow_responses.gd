extends SceneTree

## Generates the weather-to-ground-snow response data and writes the reference
## from every weather definition that actually deposits snow.  Run with:
##
## Godot --headless --path <project> --script res://tools/generate_snow_responses.gd
##
## Content resources are never hand-authored in this repository.  Keeping the
## event wiring here makes it reviewable that new weather stays data-driven.

const RESPONSE_DIRECTORY := "res://data/snow/responses"
const WEATHER_DIRECTORY := "res://data/weather"
const SnowResponseScript := preload("res://src/definitions/snow_response_definition.gd")

const RESPONSES := {
	&"snow_fog": {"rate": 0.000030, "cap": 0.12, "wind": 0.000006},
	&"blizzard": {"rate": 0.000080, "cap": 0.18, "wind": 0.000030},
	&"clear_break": {"rate": 0.000008, "cap": 0.08, "wind": 0.000004},
	&"freezing_rain": {"rate": 0.000006, "cap": 0.04, "wind": 0.000002},
	&"cold_snap": {"rate": 0.000006, "cap": 0.04, "wind": 0.000001},
	# A veer deposits no new snow, but it is the data-authored event that tells
	# the field to move material already made mobile by the prior front.
	&"wind_shift": {"rate": 0.000000, "cap": 0.12, "wind": 0.000018},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESPONSE_DIRECTORY))
	for id in RESPONSES:
		var values: Dictionary = RESPONSES[id]
		var response: SnowResponseDefinition = SnowResponseScript.new()
		response.deposition_m_per_second = float(values["rate"])
		response.maximum_added_depth_m = float(values["cap"])
		response.wind_transport_m_per_second = float(values["wind"])
		response.wind_minimum_strength = 0.08
		response.wind_sample_distance_m = 3.75
		response.wind_shelter_deposition_gain = 1.35
		var response_path := "%s/%s.tres" % [RESPONSE_DIRECTORY, id]
		_save(response, response_path)
		var event_path := "%s/event_%s.tres" % [WEATHER_DIRECTORY, id]
		var event := load(event_path) as WeatherEventDefinition
		if event == null:
			push_error("generate_snow_responses: could not load %s" % event_path)
			quit(1)
			return
		event.snow_response = load(response_path) as SnowResponseDefinition
		_save(event, event_path)
	print("generate_snow_responses: wrote %d responses" % RESPONSES.size())
	quit()


func _save(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("generate_snow_responses: failed to save %s (%d)" % [path, error])
		quit(1)
