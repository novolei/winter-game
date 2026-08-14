class_name WeatherVfxProfile
extends Resource

## The visual punctuation that distinguishes one weather from another after the
## shared wind, snowfall and lighting have done their work.
##
## This is intentionally a small description of one fixed-budget GPU emitter.
## Density moves through `amount_ratio`; the particle buffer is never resized at
## runtime. A seventh weather can therefore acquire its own air signature by
## assigning one more resource, with no renderer branch named after the event.
##
## Motion is described as air acting on a flake: exponential response toward the
## live wind, a bounded lateral curl force, and a damped tumble. It is not a
## ballistic speed line. That distinction preserves the authored fall instead of
## letting noise replace it and suspend particles inside their emission box.

@export var id: StringName = &""

@export_group("Presence")
## Share of the fixed particle budget at the end of the warning and while the
## event is fully active. Zero is a real profile: clear weather needs no garnish.
@export_range(0.0, 1.0, 0.01) var tell_density := 0.0
@export_range(0.0, 1.0, 0.01) var active_density := 0.0

@export_group("Shape")
## Width and length of one mark, in metres. Only genuinely streak-like weather
## opts into velocity alignment; a flake remains camera-facing so its tumble can
## be read.
@export var mark_size := Vector2(0.025, 0.22)
@export var scale_range := Vector2(0.75, 1.25)
@export_range(0.0, 90.0, 0.5) var spread_degrees := 8.0
## Streaks such as freezing rain face along travel. Flakes opt out so their
## authored tumble reads as wind-borne flutter instead of a meteor field.
@export var velocity_aligned := false

@export_group("Motion")
## Metres per second at birth. `downward_bias` is mixed with the live wind
## vector, so the same profile changes heading without changing identity.
@export var speed_range := Vector2(2.0, 4.0)
@export_range(0.0, 1.0, 0.01) var downward_bias := 0.8
@export_range(0.0, 3.0, 0.05) var wind_influence := 1.0
@export_range(0.0, 2.0, 0.05) var fall_acceleration := 0.25
## Jitters emission timing without changing the allocation, preventing one
## simulation tick from releasing a visible marching row.
@export_range(0.0, 1.0, 0.01) var emission_randomness := 0.0
## Lateral curl acceleration in m/s^2. The shader projects it perpendicular to
## horizontal travel, so turbulence bends the path without deleting gravity.
@export var turbulence_influence_range := Vector2.ZERO
## Approximate eddy width in metres and how quickly the field itself evolves.
@export_range(0.05, 8.0, 0.05) var turbulence_scale := 0.8
@export_range(0.0, 2.0, 0.01) var turbulence_drift := 0.12
## Per-particle exponential response rate toward the surrounding air, in 1/s.
@export var damping_range := Vector2.ZERO
## Birth spin in degrees/s, followed by exponential angular damping. A range
## crossing zero supplies both clockwise and anticlockwise flakes.
@export var angular_velocity_range := Vector2.ZERO
@export_range(0.0, 1.0, 0.01) var angular_velocity_end_multiplier := 1.0
## The visible pose is not one angular velocity. A slow, irregular rock carries
## most of the gesture; a smaller high-frequency flutter keeps its edge alive;
## and a minority of flakes ease through one half-turn with a readable side-on
## squash. Every range is rolled once at birth so a field never beats in unison.
@export var rock_amplitude_range := Vector2.ZERO
@export var rock_frequency_range := Vector2.ZERO
@export_range(0.0, 1.0, 0.01) var rock_end_multiplier := 1.0
@export var flutter_amplitude_range := Vector2.ZERO
@export var flutter_frequency_range := Vector2.ZERO
@export_range(0.0, 1.0, 0.01) var flip_probability := 0.0
@export var flip_duration_range := Vector2.ZERO
@export_range(0.1, 1.0, 0.01) var flip_edge_scale := 1.0

@export_group("Surface")
## Multiplies the palette-derived material alpha. It never introduces a colour.
@export_range(0.0, 1.0, 0.01) var opacity := 0.5


func is_inert() -> bool:
	return tell_density <= 0.0 and active_density <= 0.0


func is_valid() -> bool:
	return id != &"" \
		and tell_density >= 0.0 and tell_density <= 1.0 \
		and active_density >= 0.0 and active_density <= 1.0 \
		and mark_size.x > 0.0 and mark_size.y > 0.0 \
		and scale_range.x > 0.0 and scale_range.y >= scale_range.x \
		and speed_range.x >= 0.0 and speed_range.y >= speed_range.x \
		and downward_bias >= 0.0 and downward_bias <= 1.0 \
		and wind_influence >= 0.0 \
		and fall_acceleration >= 0.0 \
		and emission_randomness >= 0.0 and emission_randomness <= 1.0 \
		and turbulence_influence_range.x >= 0.0 \
		and turbulence_influence_range.y >= turbulence_influence_range.x \
		and turbulence_scale > 0.0 and turbulence_drift >= 0.0 \
		and damping_range.x >= 0.0 and damping_range.y >= damping_range.x \
		and angular_velocity_range.y >= angular_velocity_range.x \
		and angular_velocity_end_multiplier >= 0.0 \
		and angular_velocity_end_multiplier <= 1.0 \
		and rock_amplitude_range.x >= 0.0 \
		and rock_amplitude_range.y >= rock_amplitude_range.x \
		and rock_frequency_range.x >= 0.0 \
		and rock_frequency_range.y >= rock_frequency_range.x \
		and rock_end_multiplier >= 0.0 and rock_end_multiplier <= 1.0 \
		and flutter_amplitude_range.x >= 0.0 \
		and flutter_amplitude_range.y >= flutter_amplitude_range.x \
		and flutter_frequency_range.x >= 0.0 \
		and flutter_frequency_range.y >= flutter_frequency_range.x \
		and flip_probability >= 0.0 and flip_probability <= 1.0 \
		and flip_duration_range.x >= 0.0 \
		and flip_duration_range.y >= flip_duration_range.x \
		and (flip_probability <= 0.0 or flip_duration_range.x > 0.0) \
		and flip_edge_scale >= 0.1 and flip_edge_scale <= 1.0 \
		and opacity >= 0.0 and opacity <= 1.0
