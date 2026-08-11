class_name BeaconDefinition
extends Resource

## One of the five lamps. Lighting all five and keeping them burning to
## dawn on day 8 is the win condition.

@export var id: StringName = &""
@export var display_name: String = ""

@export var world_position := Vector3.ZERO

## Seconds of burn time on a full load of fuel.
@export var fuel_capacity := 600.0

## Wind speed above which this beacon may be blown out.
@export var wind_extinguish_threshold := 18.0

## The day this beacon becomes lightable.
@export var unlock_day := 1
