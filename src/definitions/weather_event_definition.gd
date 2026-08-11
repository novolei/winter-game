class_name WeatherEventDefinition
extends Resource

## One weather event, in three phases: tell, active, fade.
## The tell phase is mandatory -- an unannounced storm is unfair, not hard.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Timing")
## Seconds of warning before the event lands. Spec floor: 20-40s.
@export var tell_duration_range := Vector2(20.0, 40.0)
@export var active_duration_range := Vector2(60.0, 180.0)
@export var fade_duration := 15.0

@export_group("Effects")
@export var stat_modifiers: Array[Modifier] = []
@export var visibility_multiplier := 1.0
@export var wind_speed_multiplier := 1.0
@export var snowfall_rate := 0.0

@export_group("Beacons")
@export var extinguishes_beacons := false
@export var min_beacons_extinguished := 0
