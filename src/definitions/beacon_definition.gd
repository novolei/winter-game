class_name BeaconDefinition
extends Resource

## One of the five lamps. Lighting all five and keeping them burning to
## dawn on day 8 is the win condition.

@export var id: StringName = &""
@export var display_name: String = ""

@export var world_position := Vector3.ZERO

@export_group("Landmark")
## Optional scene-scale silhouette this beacon belongs to. The farmhouse lamp
## leaves this empty because its building already exists in Main; the other four
## definitions point at their authored location models.
@export var landmark_scene: PackedScene = null
@export var landmark_yaw_degrees := 0.0
@export var light_offset := Vector3(0.0, 3.0, 0.0)
@export var interaction_radius_m := 3.0

## Seconds of burn time on a full load of fuel.
@export var fuel_capacity := 600.0
@export var burn_rate := 1.0
@export var refill_request_seconds := 600.0

@export_group("Warmth")
## Full refuge close to the beacon controls, then a short readable falloff.
## These are deliberately smaller than the light range: a lamp can guide the
## player from far away without pretending the whole landmark is warm.
@export var warm_radius_m := 3.0
@export var warm_falloff_m := 2.5
## A signal fire is useful shelter, but not as restorative as the farmhouse
## stove. Both rates target the same recovery channels as every other fire.
@export var warmth_recovery_per_second := 1.0 / 480.0
@export var rest_recovery_per_second := 1.0 / 960.0

@export_group("Wind")
## Normalised WindSystem strength above which this lamp may be blown out.
## Weather's mandatory blizzard extinguish is handled separately by the network.
@export_range(0.0, 1.0, 0.01) var wind_extinguish_threshold := 0.72
## Hazard rate at a full gale. Converted to a frame-rate-independent probability
## by Beacon.wind_extinguish_probability().
@export_range(0.0, 1.0, 0.005) var wind_extinguish_rate_per_second := 0.04

## The day this beacon becomes lightable.
@export var unlock_day := 1

@export_group("Light")
## Index into ColorBible.warm_tones. Beacons are one of Art Bible rule 12's few
## authorised warm marks, but the colour still comes from the shared palette.
@export_range(0, 2, 1) var warm_tone_index := 1
@export var light_energy := 3.0
@export var light_range_m := 18.0
## Height of the low-poly emissive flame marker. The light alone cannot be seen
## against empty air, so this keeps a distant beacon legible as an authored dot.
@export var flame_height_m := 0.62
@export var low_fuel_fade_seconds := 90.0
@export var pulse_seconds := 2.8
@export_range(0.0, 0.25, 0.01) var pulse_fraction := 0.06


func is_valid() -> bool:
	return id != &"" \
		and fuel_capacity > 0.0 \
		and burn_rate > 0.0 \
		and refill_request_seconds > 0.0 \
		and warm_radius_m > 0.0 \
		and warm_falloff_m >= 0.0 \
		and warmth_recovery_per_second >= 0.0 \
		and rest_recovery_per_second >= 0.0 \
		and interaction_radius_m > 0.0 \
		and wind_extinguish_threshold >= 0.0 and wind_extinguish_threshold <= 1.0 \
		and wind_extinguish_rate_per_second >= 0.0 \
		and unlock_day >= 1 \
		and light_energy >= 0.0 and light_range_m > 0.0 \
		and flame_height_m > 0.0
