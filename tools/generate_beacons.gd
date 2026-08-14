extends SceneTree

## Generates the five GDD beacons and the scene-scale landmark each belongs to.
## Positions, fuel economy, wind vulnerability and light are content data; the
## generic Beacon and BeaconNetwork contain no list of ids.

const OUT_DIR := "res://data/beacons"

const ROWS := [
	{
		"id": &"farmhouse_chimney", "display_name": "Farmhouse chimney",
		"position": Vector3(13.0, 0.0, -12.0), "model": "", "yaw": 0.0,
		"light_offset": Vector3(-0.6, 6.1, -0.6), "radius": 3.2,
		"capacity": 900.0, "burn": 0.25, "threshold": 0.78, "wind_rate": 0.035,
		"warm_radius": 2.8, "warm_falloff": 2.2,
		"warmth_recovery": 1.0 / 420.0, "rest_recovery": 1.0 / 900.0,
		"day": 1, "tone": 1, "energy": 3.1, "range": 19.0,
		"flame_height": 0.66,
	},
	{
		"id": &"gas_station", "display_name": "Gas station roof light",
		"position": Vector3(-38.0, 0.0, 7.0),
		"model": "res://assets/models/buildings/gas_station/gas_station.glb", "yaw": 18.0,
		"light_offset": Vector3(0.0, 3.2, -0.2), "radius": 5.0,
		"capacity": 900.0, "burn": 0.25, "threshold": 0.74, "wind_rate": 0.045,
		"warm_radius": 3.2, "warm_falloff": 2.6,
		"warmth_recovery": 1.0 / 390.0, "rest_recovery": 1.0 / 840.0,
		"day": 2, "tone": 1, "energy": 3.3, "range": 22.0,
		"flame_height": 0.58,
	},
	{
		"id": &"church_tower", "display_name": "Church bell tower",
		"position": Vector3(42.0, 0.0, 22.0),
		"model": "res://assets/models/buildings/church/church.glb", "yaw": -24.0,
		"light_offset": Vector3(0.0, 5.25, -3.6), "radius": 5.4,
		"capacity": 900.0, "burn": 0.25, "threshold": 0.69, "wind_rate": 0.055,
		"warm_radius": 3.4, "warm_falloff": 2.8,
		"warmth_recovery": 1.0 / 420.0, "rest_recovery": 1.0 / 900.0,
		"day": 3, "tone": 1, "energy": 3.5, "range": 24.0,
		"flame_height": 0.62,
	},
	{
		"id": &"logging_camp", "display_name": "Logging camp searchlight",
		"position": Vector3(-40.0, 0.0, -34.0),
		"model": "res://assets/models/buildings/logging_camp/logging_camp.glb", "yaw": 32.0,
		"light_offset": Vector3(-2.7, 2.25, -2.3), "radius": 5.6,
		"capacity": 900.0, "burn": 0.25, "threshold": 0.64, "wind_rate": 0.065,
		"warm_radius": 3.8, "warm_falloff": 3.0,
		"warmth_recovery": 1.0 / 360.0, "rest_recovery": 1.0 / 780.0,
		"day": 4, "tone": 2, "energy": 3.7, "range": 25.0,
		"flame_height": 0.56,
	},
	{
		"id": &"transmission_tower", "display_name": "Transmission tower",
		"position": Vector3(42.0, 0.0, -38.0),
		"model": "res://assets/models/buildings/transmission_tower/transmission_tower.glb", "yaw": -9.0,
		"light_offset": Vector3(0.0, 15.0, 0.0), "radius": 5.0,
		"capacity": 900.0, "burn": 0.25, "threshold": 0.58, "wind_rate": 0.08,
		"warm_radius": 3.1, "warm_falloff": 2.7,
		"warmth_recovery": 1.0 / 420.0, "rest_recovery": 1.0 / 900.0,
		"day": 5, "tone": 2, "energy": 4.0, "range": 29.0,
		"flame_height": 0.72,
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var DefinitionScript := load("res://src/definitions/beacon_definition.gd")
	var failed := false
	for row in ROWS:
		var definition: BeaconDefinition = DefinitionScript.new()
		definition.id = row["id"]
		definition.display_name = row["display_name"]
		definition.world_position = row["position"]
		definition.landmark_scene = load(row["model"]) as PackedScene if row["model"] != "" else null
		definition.landmark_yaw_degrees = row["yaw"]
		definition.light_offset = row["light_offset"]
		definition.interaction_radius_m = row["radius"]
		definition.fuel_capacity = row["capacity"]
		definition.refill_request_seconds = row["capacity"]
		definition.burn_rate = row["burn"]
		definition.warm_radius_m = row["warm_radius"]
		definition.warm_falloff_m = row["warm_falloff"]
		definition.warmth_recovery_per_second = row["warmth_recovery"]
		definition.rest_recovery_per_second = row["rest_recovery"]
		definition.wind_extinguish_threshold = row["threshold"]
		definition.wind_extinguish_rate_per_second = row["wind_rate"]
		definition.unlock_day = row["day"]
		definition.warm_tone_index = row["tone"]
		definition.light_energy = row["energy"]
		definition.light_range_m = row["range"]
		definition.flame_height_m = row["flame_height"]
		var path := "%s/%s.tres" % [OUT_DIR, row["id"]]
		var error := ResourceSaver.save(definition, path)
		print("generate_beacons: %s -> %d" % [path, error])
		failed = failed or error != OK
	quit(1 if failed else 0)
