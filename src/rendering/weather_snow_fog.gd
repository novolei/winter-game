class_name WeatherSnowFog
extends FogVolume

## Camera-local volumetric air for weather profiles that opt into it.
##
## Weather and wind are continuous state, so they are polled through the
## registry. The event bus only receives the one fact another renderer needs:
## whether this volume crossed its inactive/active boundary.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const PROCESS_SHADER_PATH := "res://src/rendering/weather_" + "snow_" + "fog.gdshader"
const EVENT_ACTIVE_CHANGED := &"rendering.local_volumetric_fog_changed"
const NOISE_RESOLUTION := 48

@export var volume_size := Vector3(48.0, 48.0, 132.0)
@export_range(0, 4, 1) var palette_snow_tone := 0
@export var noise_seed := 20260813

var _weather = null
var _wind = null
var _bus = null
var _profile: WeatherFogProfile = null
var _fog_material: ShaderMaterial = null
var _noise_texture: NoiseTexture3D = null
var _density := 0.0
var _active := false
var _resolved_flow := Vector3.ZERO
var _advection_offset := Vector3.ZERO


func _ready() -> void:
	_build()
	resolve_sources()
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
	advance(0.0)


func _exit_tree() -> void:
	_set_active(false)


func _process(delta: float) -> void:
	advance(delta)


func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


func set_weather_source(source) -> void:
	_weather = source


func set_wind_source(source) -> void:
	_wind = source


func set_event_bus(bus) -> void:
	_bus = bus


func resolve_sources() -> void:
	var registry := _registry()
	if registry == null:
		return
	if _weather == null:
		_weather = registry.get_service(&"weather")
	if _wind == null:
		_wind = registry.get_service(&"wind")


func active_profile() -> WeatherFogProfile:
	return _profile


func density() -> float:
	return _density


func noise_texture() -> NoiseTexture3D:
	return _noise_texture


func fog_shader_material() -> ShaderMaterial:
	return _fog_material


func advection_offset() -> Vector3:
	return _advection_offset


## The active phase begins exactly at tell density and the fade ends at zero.
## The final clamp is deliberately repeated in the shader: malformed live data
## is unable to cross the measured ceiling on either side of the render bridge.
static func density_for(
	profile: WeatherFogProfile, phase: StringName, tell_progress: float, intensity: float
) -> float:
	if profile == null:
		return 0.0
	var value := 0.0
	if phase == &"tell":
		value = profile.tell_density * smoothstep(0.0, 1.0, clampf(tell_progress, 0.0, 1.0))
	elif phase == &"active":
		value = lerpf(
			profile.tell_density,
			profile.active_density,
			clampf(intensity, 0.0, 1.0)
		)
	elif phase == &"fade":
		value = profile.active_density * clampf(intensity, 0.0, 1.0)
	var ceiling := clampf(
		profile.peak_density,
		0.0,
		WeatherFogProfile.MAX_LOCAL_DENSITY
	)
	return clampf(value, 0.0, ceiling)


## Exponential wind following and its exact integral. Taking the displacement
## from the old resolved flow before updating it makes this independent of the
## caller's frame rate, including while the wind turns.
static func flow_after(
	current: Vector3,
	wind_velocity: Vector3,
	delta: float,
	response_per_second: float,
	max_speed: float
) -> Vector3:
	var held := Vector3(current.x, 0.0, current.z)
	var duration := maxf(delta, 0.0)
	if duration <= 0.0 or response_per_second <= 0.0:
		return held
	var target := _limited_horizontal(wind_velocity, max_speed)
	var decay := exp(-response_per_second * duration)
	return target + (held - target) * decay


static func flow_displacement(
	current: Vector3,
	wind_velocity: Vector3,
	delta: float,
	response_per_second: float,
	max_speed: float
) -> Vector3:
	var held := Vector3(current.x, 0.0, current.z)
	var duration := maxf(delta, 0.0)
	if duration <= 0.0:
		return Vector3.ZERO
	if response_per_second <= 0.0:
		return held * duration
	var target := _limited_horizontal(wind_velocity, max_speed)
	var decay := exp(-response_per_second * duration)
	return target * duration \
		+ (held - target) * ((1.0 - decay) / response_per_second)


static func _limited_horizontal(value: Vector3, max_speed: float) -> Vector3:
	var horizontal := Vector3(value.x, 0.0, value.z)
	var limit := maxf(max_speed, 0.0)
	if horizontal.length() > limit and limit > 0.0:
		return horizontal.normalized() * limit
	return horizontal if limit > 0.0 else Vector3.ZERO


## CPU mirror of the shader gate, kept pure so foreground protection is a
## contract rather than something inferred from a capture.
static func depth_gate(
	depth: float,
	near_clear: float,
	near_full: float,
	far_fade_start: float,
	far_fade_end: float
) -> float:
	var near_gate := smoothstep(near_clear, near_full, depth)
	var far_gate := 1.0 - smoothstep(far_fade_start, far_fade_end, depth)
	return clampf(near_gate * far_gate, 0.0, 1.0)


## The near box face rests on the lens plane; its full Z extent lies ahead of
## the camera. The far depth feather therefore completes before the box ends.
static func volume_transform_for(camera_transform: Transform3D, box_size: Vector3) -> Transform3D:
	var basis := camera_transform.basis.orthonormalized()
	var forward := -basis.z
	return Transform3D(
		basis,
		camera_transform.origin + forward * maxf(box_size.z, 0.0) * 0.5
	)


func follow_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	global_transform = volume_transform_for(camera.global_transform, volume_size)
	if _fog_material == null:
		return
	var camera_basis := camera.global_transform.basis.orthonormalized()
	_fog_material.set_shader_parameter("camera_position", camera.global_position)
	_fog_material.set_shader_parameter("camera_forward", -camera_basis.z)


func advance(delta := 0.0) -> void:
	if _fog_material == null:
		_build()
	if _weather != null and not is_instance_valid(_weather):
		_weather = null
	if _wind != null and not is_instance_valid(_wind):
		_wind = null
	if _weather == null or _wind == null:
		resolve_sources()

	_profile = _read_profile()
	var phase := &"clear"
	var tell := 0.0
	var strength := 0.0
	if _weather != null:
		if _weather.has_method("phase"):
			phase = StringName(_weather.phase())
		if _weather.has_method("tell_progress"):
			tell = float(_weather.tell_progress())
		if _weather.has_method("intensity"):
			strength = float(_weather.intensity())
	_density = density_for(_profile, phase, tell, strength)

	if _profile != null:
		var requested_flow := _wind_velocity() * _profile.wind_advection_multiplier
		var duration := maxf(float(delta), 0.0)
		_advection_offset += flow_displacement(
			_resolved_flow,
			requested_flow,
			duration,
			_profile.wind_response_per_second,
			_profile.max_advection_speed_mps
		)
		_resolved_flow = flow_after(
			_resolved_flow,
			requested_flow,
			duration,
			_profile.wind_response_per_second,
			_profile.max_advection_speed_mps
		)
	else:
		_resolved_flow = Vector3.ZERO

	_apply_profile()
	_follow_current_camera()
	_set_active(_profile != null and _density > 0.0)


func _read_profile() -> WeatherFogProfile:
	if _weather == null or not _weather.has_method("active_event"):
		return null
	var event = _weather.active_event()
	if event == null:
		return null
	# The definition field is deliberately discovered structurally. The renderer
	# knows the profile contract, never an event identifier or catalogue entry.
	for entry in event.get_property_list():
		if StringName(entry.get("name", "")) == &"fog_profile":
			return event.get(&"fog_profile") as WeatherFogProfile
	return null


func _wind_velocity() -> Vector3:
	if _wind == null or not is_instance_valid(_wind):
		_wind = null
		resolve_sources()
	if _wind != null and _wind.has_method("velocity"):
		return _wind.velocity()
	return Vector3.ZERO


func _follow_current_camera() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	follow_camera(viewport.get_camera_3d())


func _apply_profile() -> void:
	if _fog_material == null:
		return
	_fog_material.set_shader_parameter("fog_density", _density)
	_fog_material.set_shader_parameter("advection_offset", _advection_offset)
	if _profile == null:
		_fog_material.set_shader_parameter("peak_density", 0.0)
		return
	_fog_material.set_shader_parameter(
		"peak_density",
		clampf(_profile.peak_density, 0.0, WeatherFogProfile.MAX_LOCAL_DENSITY)
	)
	_fog_material.set_shader_parameter("macro_scale_m", _profile.macro_scale_m)
	_fog_material.set_shader_parameter("detail_scale_m", _profile.detail_scale_m)
	_fog_material.set_shader_parameter("detail_weight", _profile.detail_weight)
	_fog_material.set_shader_parameter("noise_contrast", _profile.noise_contrast)
	_fog_material.set_shader_parameter("near_clear_depth", _profile.near_clear_depth_m)
	_fog_material.set_shader_parameter("near_full_depth", _profile.near_full_depth_m)
	_fog_material.set_shader_parameter("far_fade_start", _profile.far_fade_start_m)
	_fog_material.set_shader_parameter("far_fade_end", _profile.far_fade_end_m)


func _set_active(value: bool) -> void:
	visible = value
	if value == _active:
		return
	_active = value
	if _bus != null and is_instance_valid(_bus) and _bus.has_method("emit_event"):
		_bus.emit_event(EVENT_ACTIVE_CHANGED, {
			"active": _active,
			"density": _density,
			"peak_density": minf(
				_profile.peak_density if _profile != null else 0.0,
				WeatherFogProfile.MAX_LOCAL_DENSITY
			),
		})


## Idempotent so tests, editor previews and scene readiness all use the same
## construction path. One shared texture feeds both shader scales.
func _build() -> void:
	shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	size = volume_size
	if _fog_material != null:
		return

	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 2

	_noise_texture = NoiseTexture3D.new()
	_noise_texture.width = NOISE_RESOLUTION
	_noise_texture.height = NOISE_RESOLUTION
	_noise_texture.depth = NOISE_RESOLUTION
	_noise_texture.normalize = true
	_noise_texture.seamless = true
	_noise_texture.seamless_blend_skirt = 0.18
	_noise_texture.noise = noise

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = load(PROCESS_SHADER_PATH) as Shader
	_fog_material.set_shader_parameter("density_noise", _noise_texture)
	var bible := load(PALETTE_PATH) as ColorBible
	if bible != null and not bible.snow_tones.is_empty():
		var tone_index := clampi(palette_snow_tone, 0, bible.snow_tones.size() - 1)
		_fog_material.set_shader_parameter("fog_albedo", bible.snow_tones[tone_index])
	material = _fog_material
	visible = _active
