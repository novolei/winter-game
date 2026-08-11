extends SceneTree

## One-off generator for res://data/schedule/day_01..07.tres.
## Values come from GDD section 4.
## Run: godot --headless --path <project> --script res://tools/generate_schedules.gd

func _initialize() -> void:
	var DayScheduleScript := load("res://src/definitions/day_schedule.gd")

	# day, daylight, night, preset, allowed events, forced event, beacon
	var rows := [
		[1, 600.0, 300.0, &"pale_day",  [],                                            &"",         &"farmhouse_chimney"],
		[2, 600.0, 300.0, &"pale_day",  [&"snow_fog"],                                 &"",         &"fuel_station"],
		[3, 480.0, 420.0, &"nightfall", [&"snow_fog", &"clear_break"],                 &"",         &"church_tower"],
		[4, 480.0, 420.0, &"deep_night",[&"wind_shift", &"snow_fog"],                  &"",         &"logging_camp"],
		[5, 420.0, 480.0, &"sunrise",   [&"clear_break", &"cold_snap"],                &"",         &"power_pylon"],
		[6, 300.0, 600.0, &"nightfall", [&"cold_snap", &"freezing_rain", &"wind_shift"], &"",       &""],
		[7, 240.0, 660.0, &"whiteout",  [&"wind_shift"],                               &"blizzard", &""],
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/schedule"))
	for row in rows:
		var schedule = DayScheduleScript.new()
		schedule.day_number = row[0]
		schedule.daylight_seconds = row[1]
		schedule.night_seconds = row[2]
		schedule.primary_lighting_preset = row[3]
		var events: Array[StringName] = []
		for e in row[4]:
			events.append(e)
		schedule.allowed_weather_events = events
		schedule.forced_weather_event = row[5]
		schedule.beacon_unlocked = row[6]

		var path := "res://data/schedule/day_%02d.tres" % row[0]
		var error := ResourceSaver.save(schedule, path)
		if error != OK:
			print("generate_schedules: FAILED %s (%d)" % [path, error])
			quit(1)
		print("generate_schedules: wrote %s" % path)
	quit(0)
