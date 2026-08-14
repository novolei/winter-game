class_name WeatherFogProfile
extends Resource

## Data for one weather's local, noisy snow veil.
##
## The renderer owns one fixed FogVolume and never asks which weather is active.
## A weather that needs local air assigns one of these resources; a weather that
## does not leaves the field null. Density remains a continuous function of the
## shared weather phase, while every shape and motion choice lives here.

## Local fog only occupies a short, camera-gated section of each ray. A global
## 0.002 density acts over the whole view and was too destructive; the same
## number inside this 30-40 m window measured below one code value in the A/B.
## 0.064 is therefore the absolute local ceiling, not an authored target. The
## shipped peaks remain below it and were set from a same-frame D3D12 A/B.
const MAX_LOCAL_DENSITY := 0.064

@export var id: StringName = &""

@export_group("Presence")
## Local volumetric density at the end of the warning and at full strength.
@export_range(0.0, MAX_LOCAL_DENSITY, 0.00001) var tell_density := 0.0
@export_range(0.0, MAX_LOCAL_DENSITY, 0.00001) var active_density := 0.0
## Last safety rail after noise modulation. No resource may raise it above the
## measured local-window ceiling.
@export_range(0.0, MAX_LOCAL_DENSITY, 0.00001) var peak_density := MAX_LOCAL_DENSITY

@export_group("World-space Noise")
## Metres covered by one repeat of the shared 3D field. Unequal axes stretch the
## pattern into wind-borne veils rather than spherical smoke puffs.
@export var macro_scale_m := Vector3(12.0, 5.0, 8.0)
@export var detail_scale_m := Vector3(4.5, 2.5, 3.0)
@export_range(0.0, 0.5, 0.01) var detail_weight := 0.28
## Symmetric modulation around authored density. It never creates a thresholded
## empty/full cloud and therefore cannot turn the storm into isolated clumps.
@export_range(0.0, 0.75, 0.01) var noise_contrast := 0.30

@export_group("Advection")
## Live wind is scaled, speed-limited, then followed exponentially. The renderer
## integrates that resolved flow, so a heading change bends the field instead of
## teleporting its noise coordinates.
@export_range(0.0, 1.0, 0.01) var wind_advection_multiplier := 0.12
@export_range(0.0, 3.0, 0.05) var max_advection_speed_mps := 0.80
@export_range(0.05, 12.0, 0.05) var wind_response_per_second := 2.40

@export_group("Camera Depth")
## Distances from the camera, in metres. The first interval protects the player,
## nearby trees and footprints; the second feathers the far face of the box.
@export_range(0.0, 160.0, 0.5) var near_clear_depth_m := 76.0
@export_range(0.0, 160.0, 0.5) var near_full_depth_m := 88.0
@export_range(0.0, 180.0, 0.5) var far_fade_start_m := 112.0
@export_range(0.0, 200.0, 0.5) var far_fade_end_m := 128.0


func is_inert() -> bool:
	return tell_density <= 0.0 and active_density <= 0.0


func is_valid() -> bool:
	return id != &"" \
		and tell_density >= 0.0 and tell_density <= peak_density \
		and active_density >= 0.0 and active_density <= peak_density \
		and peak_density >= 0.0 and peak_density <= MAX_LOCAL_DENSITY \
		and macro_scale_m.x > 0.0 and macro_scale_m.y > 0.0 and macro_scale_m.z > 0.0 \
		and detail_scale_m.x > 0.0 and detail_scale_m.y > 0.0 and detail_scale_m.z > 0.0 \
		and detail_weight >= 0.0 and detail_weight <= 0.5 \
		and noise_contrast >= 0.0 and noise_contrast <= 0.75 \
		and wind_advection_multiplier >= 0.0 \
		and max_advection_speed_mps >= 0.0 \
		and wind_response_per_second > 0.0 \
		and near_clear_depth_m >= 0.0 \
		and near_full_depth_m > near_clear_depth_m \
		and far_fade_start_m > near_full_depth_m \
		and far_fade_end_m > far_fade_start_m
