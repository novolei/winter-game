class_name WeatherVfxLayer
extends GPUParticles3D

## One fixed-budget accent layer for the six weather identities.
##
## Snowfall remains snow, Spindrift remains wind over the ground, and the
## LightingDirector remains the atmosphere. This layer only supplies what those
## shared systems cannot say: brittle freezing-rain strokes, sparse suspended
## frost during a cold snap, or slow marks in snow fog. It polls weather and wind
## through ServiceRegistry because both are continuous state, not events.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const PROCESS_SHADER_PATH := "res://src/rendering/weather_flake_motion.gdshader"
const SERVICE := &"weather_vfx"

## Allocated once. Runtime density is always `amount_ratio`, never `amount`.
@export_range(64, 2048, 1) var particle_budget := 640
@export var life_seconds := 2.4
@export var volume_size := Vector3(34.0, 16.0, 30.0)
@export var ground_height := 1.0
@export var volume_lift := 8.0
@export_range(0.0, 1.0, 0.01) var palette_whiteness := 0.55

var _weather = null
var _wind = null
var _profile: WeatherVfxProfile = null
var _process_material: ShaderMaterial = null
var _quad: QuadMesh = null
var _surface: StandardMaterial3D = null
var _density := 0.0


func _ready() -> void:
	_build()
	var registry := _registry()
	if registry != null:
		registry.register(SERVICE, self)
	resolve_sources()
	advance()


func _exit_tree() -> void:
	var registry := _registry()
	if registry != null and registry.get_service(SERVICE) == self:
		registry.unregister(SERVICE)


func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


func set_weather_source(source) -> void:
	_weather = source


func set_wind_source(source) -> void:
	_wind = source


func resolve_sources() -> void:
	var registry := _registry()
	if registry == null:
		return
	if _weather == null:
		_weather = registry.get_service(&"weather")
	if _wind == null:
		_wind = registry.get_service(&"wind")


func active_profile() -> WeatherVfxProfile:
	return _profile


func density() -> float:
	return _density


## Continuous and pure enough to test without a tree. The arrival begins at the
## warning density, so the event boundary cannot make the air briefly empty.
static func density_for(
	profile: WeatherVfxProfile, phase: StringName, tell_progress: float, intensity: float
) -> float:
	if profile == null:
		return 0.0
	if phase == &"tell":
		return profile.tell_density * smoothstep(0.0, 1.0, clampf(tell_progress, 0.0, 1.0))
	if phase == &"active":
		return lerpf(
			profile.tell_density,
			profile.active_density,
			clampf(intensity, 0.0, 1.0)
		)
	if phase == &"fade":
		return profile.active_density * clampf(intensity, 0.0, 1.0)
	return 0.0


## Direction a mark travels. A profile supplies character, live wind supplies
## the changing heading; neither contains the other's tuning.
static func travel_direction(
	profile: WeatherVfxProfile, wind_velocity: Vector3
) -> Vector3:
	if profile == null:
		return Vector3.DOWN
	var fall := Vector3.DOWN * profile.downward_bias
	var carried := wind_velocity * profile.wind_influence
	var mixed := fall + carried
	return mixed.normalized() if mixed.length_squared() > 0.000001 else Vector3.DOWN


## Convert a resource's readable "fraction of birth spin left at death" into
## the exponential rate the shader integrates. A value of zero is treated as a
## practical extinction rather than infinity.
static func angular_damping_rate(end_multiplier: float, duration: float) -> float:
	var held_end := clampf(end_multiplier, 0.001, 1.0)
	return -log(held_end) / maxf(duration, 0.001)


## Total angle travelled by a freely decaying birth spin. Unlike integrating a
## mutable velocity per frame, this analytic form gives the same pose at 30, 60
## and 120 Hz and lets tests hold the residual spin below the rocking gesture.
static func damped_spin_travel_degrees(
	angular_speed: float, end_multiplier: float, duration: float
) -> float:
	var rate := angular_damping_rate(end_multiplier, duration)
	if rate <= 0.000001:
		return angular_speed * duration
	return angular_speed * (1.0 - exp(-rate * maxf(duration, 0.0))) / rate


## Fifth-order easing has zero angular velocity at both edges of a flip. A
## linear half-turn is the visual equivalent of a card driven by a motor.
static func flip_ease(progress: float) -> float:
	var q := clampf(progress, 0.0, 1.0)
	return q * q * q * (q * (q * 6.0 - 15.0) + 10.0)


static func flip_width_scale(progress: float, edge_scale: float) -> float:
	var eased := flip_ease(progress)
	return 1.0 - (1.0 - clampf(edge_scale, 0.1, 1.0)) * pow(sin(PI * eased), 2.0)


## GDScript mirror of the shader's safety rail. Curl may push across the wind,
## but contributes neither vertical lift nor acceleration along horizontal
## travel. Kept pure so that invariant does not rely on a screenshot.
static func lateral_turbulence(eddy: Vector3, direction: Vector3) -> Vector3:
	var lateral := Vector3(eddy.x, 0.0, eddy.z)
	var flat_travel := Vector3(direction.x, 0.0, direction.z)
	if flat_travel.length_squared() > 0.000001:
		flat_travel = flat_travel.normalized()
		lateral -= flat_travel * lateral.dot(flat_travel)
	return lateral


func advance() -> void:
	if _weather == null or not is_instance_valid(_weather):
		_weather = null
		resolve_sources()
	_profile = _read_profile()
	var phase := &"clear"
	var tell := 0.0
	var strength := 0.0
	if _weather != null:
		if _weather.has_method("phase"):
			phase = _weather.phase()
		if _weather.has_method("tell_progress"):
			tell = float(_weather.tell_progress())
		if _weather.has_method("intensity"):
			strength = float(_weather.intensity())
	_density = density_for(_profile, phase, tell, strength)
	_apply_profile()


func _process(_delta: float) -> void:
	_place()
	advance()


func _read_profile() -> WeatherVfxProfile:
	if _weather == null or not _weather.has_method("active_event"):
		return null
	var event = _weather.active_event()
	if event == null:
		return null
	return event.vfx_profile


func _wind_velocity() -> Vector3:
	if _wind == null or not is_instance_valid(_wind):
		_wind = null
		resolve_sources()
	if _wind != null and _wind.has_method("velocity"):
		return _wind.velocity()
	return Vector3.ZERO


func _apply_profile() -> void:
	if _process_material == null or _quad == null or _surface == null:
		return
	amount_ratio = clampf(_density, 0.0, 1.0)
	emitting = amount_ratio > 0.0
	if _profile == null:
		return
	randomness = _profile.emission_randomness
	_process_material.set_shader_parameter(
		"travel_direction", travel_direction(_profile, _wind_velocity())
	)
	_process_material.set_shader_parameter("speed_range", _profile.speed_range)
	_process_material.set_shader_parameter("spread_degrees", _profile.spread_degrees)
	_process_material.set_shader_parameter("scale_range", _profile.scale_range)
	_process_material.set_shader_parameter("fall_acceleration", _profile.fall_acceleration)
	_process_material.set_shader_parameter("damping_range", _profile.damping_range)
	_process_material.set_shader_parameter(
		"turbulence_influence_range", _profile.turbulence_influence_range
	)
	_process_material.set_shader_parameter("turbulence_scale", _profile.turbulence_scale)
	_process_material.set_shader_parameter("turbulence_drift", _profile.turbulence_drift)
	_process_material.set_shader_parameter(
		"angular_velocity_range", _profile.angular_velocity_range
	)
	_process_material.set_shader_parameter(
		"angular_damping",
		angular_damping_rate(_profile.angular_velocity_end_multiplier, lifetime)
	)
	_process_material.set_shader_parameter("rock_amplitude_range", _profile.rock_amplitude_range)
	_process_material.set_shader_parameter("rock_frequency_range", _profile.rock_frequency_range)
	_process_material.set_shader_parameter("rock_end_multiplier", _profile.rock_end_multiplier)
	_process_material.set_shader_parameter(
		"flutter_amplitude_range", _profile.flutter_amplitude_range
	)
	_process_material.set_shader_parameter(
		"flutter_frequency_range", _profile.flutter_frequency_range
	)
	_process_material.set_shader_parameter("flip_probability", _profile.flip_probability)
	_process_material.set_shader_parameter("flip_duration_range", _profile.flip_duration_range)
	_process_material.set_shader_parameter("flip_edge_scale", _profile.flip_edge_scale)
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY \
		if _profile.velocity_aligned else GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES \
		if not _profile.velocity_aligned else BaseMaterial3D.BILLBOARD_DISABLED
	_quad.size = _profile.mark_size
	var colour := _surface.albedo_color
	colour.a = _profile.opacity
	_surface.albedo_color = colour


func _place() -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	var focus := camera.global_position
	if forward.y < -0.001:
		focus += forward * ((ground_height - camera.global_position.y) / forward.y)
	global_position = Vector3(focus.x, ground_height + volume_lift, focus.z)


func _build() -> void:
	var bible := load(PALETTE_PATH) as ColorBible
	amount = maxi(particle_budget, 1)
	lifetime = maxf(life_seconds, 0.05)
	preprocess = lifetime
	local_coords = false
	one_shot = false
	explosiveness = 0.0
	randomness = 0.0
	fixed_fps = 30
	interpolate = true
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	_process_material = ShaderMaterial.new()
	_process_material.shader = load(PROCESS_SHADER_PATH)
	_process_material.set_shader_parameter("volume_extents", volume_size * 0.5)
	process_material = _process_material

	_surface = StandardMaterial3D.new()
	var snow := bible.snow_tones[0]
	_surface.albedo_color = snow.lerp(Color.WHITE, palette_whiteness)
	_surface.albedo_texture = _mark_texture()
	_surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_surface.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_surface.billboard_keep_scale = true
	_surface.disable_receive_shadows = true
	_surface.vertex_color_use_as_albedo = true

	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_quad.material = _surface
	draw_pass_1 = _quad
	visibility_aabb = AABB(-volume_size, volume_size * 2.0)
	emitting = false
	amount_ratio = 0.0


func _mark_texture() -> GradientTexture2D:
	var transparent := Color(Color.WHITE, 0.0)
	var solid := Color.WHITE
	var shoulder := Color(Color.WHITE, 0.58)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.72, 1.0])
	gradient.colors = PackedColorArray([solid, solid, shoulder, transparent])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	# Slightly off-centre: an asymmetric lentil makes a decaying tumble readable
	# without drawing a literal high-frequency snowflake icon into the low-poly art.
	texture.fill_from = Vector2(0.44, 0.48)
	texture.fill_to = Vector2(0.98, 0.48)
	texture.width = 32
	texture.height = 32
	return texture
