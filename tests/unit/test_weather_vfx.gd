extends TestCase

const ProfileScript := preload("res://src/definitions/weather_vfx_profile.gd")
const LayerScript := preload("res://src/rendering/weather_vfx_layer.gd")
const EVENT_IDS: Array[StringName] = [
	&"blizzard", &"wind_shift", &"clear_break", &"freezing_rain", &"cold_snap", &"snow_fog",
]


func _profile(id: StringName) -> WeatherVfxProfile:
	return ResourceLoader.load(
		"res://data/weather/vfx/%s.tres" % String(id),
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as WeatherVfxProfile


func test_every_shipped_weather_has_a_valid_air_signature() -> void:
	for id in EVENT_IDS:
		var event := ResourceLoader.load(
			"res://data/weather/event_%s.tres" % String(id),
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as WeatherEventDefinition
		assert_not_null(event, "weather '%s' is missing" % id)
		if event == null:
			continue
		assert_not_null(event.vfx_profile, "weather '%s' has no VFX profile" % id)
		if event.vfx_profile != null:
			assert_eq(event.vfx_profile.id, id, "weather '%s' points at another profile" % id)
			assert_true(event.vfx_profile.is_valid(), "weather '%s' has invalid VFX data" % id)


func test_clear_break_is_the_deliberate_visual_rest() -> void:
	var profile := _profile(&"clear_break")
	assert_not_null(profile)
	if profile != null:
		assert_true(profile.is_inert(), "the relief event added decorative air noise")


func test_freezing_rain_is_dense_fast_and_vertically_biased() -> void:
	var rain := _profile(&"freezing_rain")
	var fog := _profile(&"snow_fog")
	assert_not_null(rain)
	assert_not_null(fog)
	if rain != null and fog != null:
		assert_true(rain.active_density > fog.active_density, "freezing rain is not the denser mark field")
		assert_true(rain.speed_range.x > fog.speed_range.y, "freezing rain does not fall distinctly faster")
		assert_true(rain.mark_size.y > rain.mark_size.x * 10.0, "freezing rain is not a fine stroke")
		assert_true(rain.downward_bias > fog.downward_bias, "freezing rain does not read more vertical than fog")
		assert_true(rain.velocity_aligned, "freezing rain stopped facing along its fall")


func test_blizzard_flakes_flutter_instead_of_reading_as_meteor_streaks() -> void:
	var blizzard := _profile(&"blizzard")
	assert_not_null(blizzard)
	if blizzard != null:
		var aspect := blizzard.mark_size.y / blizzard.mark_size.x
		assert_true(aspect <= 3.0, "blizzard marks became long meteor-like strokes")
		assert_true(
			blizzard.mark_size.x >= 0.04 and blizzard.mark_size.x <= 0.055,
			"blizzard flake width %.3f m is either oversized or no longer readable"
				% blizzard.mark_size.x
		)
		assert_true(
			blizzard.mark_size.y >= 0.08 and blizzard.mark_size.y <= 0.12,
			"blizzard flake length %.3f m is either oversized or no longer readable"
				% blizzard.mark_size.y
		)
		assert_true(
			blizzard.scale_range.y / blizzard.scale_range.x >= 2.2,
			"blizzard flakes collapsed back to one repeated size"
		)
		assert_false(blizzard.velocity_aligned, "every blizzard flake is rigidly locked to its velocity")
		assert_true(
			blizzard.emission_randomness >= 0.35,
			"blizzard emission can fall back into visible marching rows"
		)
		assert_true(blizzard.active_density >= 0.30, "meteor streaks were hidden by deleting the accent field")
		assert_true(blizzard.turbulence_influence_range.y > 0.0, "blizzard air has no turbulent flutter")
		assert_true(blizzard.damping_range.x > 0.0, "blizzard flakes never shed speed")
		assert_true(
			blizzard.angular_velocity_range.x < 0.0 and blizzard.angular_velocity_range.y > 0.0,
			"blizzard flakes cannot tumble both ways"
		)
		assert_true(
			blizzard.angular_velocity_end_multiplier < 0.5,
			"blizzard tumbling never settles under rotational drag"
		)
		assert_true(
			blizzard.rock_amplitude_range.x >= 10.0
				and blizzard.rock_frequency_range.y > blizzard.rock_frequency_range.x,
			"the flake has no varied, readable rocking gesture"
		)
		assert_true(
			blizzard.flutter_amplitude_range.y > 0.0
				and blizzard.flutter_frequency_range.y > blizzard.flutter_frequency_range.x,
			"the flake edge has no independently varied flutter"
		)
		assert_true(
			blizzard.flip_probability > 0.0 and blizzard.flip_probability <= 0.25,
			"the occasional half-turn is either absent or has become a field-wide gimmick"
		)


func test_cold_snap_marks_are_sparse_and_nearly_suspended() -> void:
	var cold := _profile(&"cold_snap")
	assert_not_null(cold)
	if cold != null:
		assert_true(cold.active_density < 0.12, "cold snap became a second snowfall")
		assert_true(cold.speed_range.y <= 0.3001, "cold snap crystals move too quickly to read as still air")


func test_density_crosses_weather_phase_boundaries_without_a_step() -> void:
	var profile := ProfileScript.new() as WeatherVfxProfile
	profile.id = &"probe"
	profile.tell_density = 0.24
	profile.active_density = 0.8
	var tell_end := LayerScript.density_for(profile, &"tell", 1.0, 0.0)
	var arrival_start := LayerScript.density_for(profile, &"active", 0.0, 0.0)
	assert_almost_eq(tell_end, arrival_start, 0.0001, "the VFX pops when the warning becomes weather")
	assert_almost_eq(LayerScript.density_for(profile, &"active", 0.0, 1.0), 0.8)
	assert_almost_eq(LayerScript.density_for(profile, &"fade", 0.0, 0.0), 0.0)


func test_live_wind_changes_heading_without_erasing_the_profiles_fall() -> void:
	var profile := ProfileScript.new() as WeatherVfxProfile
	profile.id = &"probe"
	profile.downward_bias = 1.0
	profile.wind_influence = 0.5
	var direction := LayerScript.travel_direction(profile, Vector3(2.0, 0.0, 0.0))
	assert_true(direction.x > 0.0, "live wind did not reach the weather accent")
	assert_true(direction.y < 0.0, "the weather accent lost gravity")
	assert_almost_eq(direction.length(), 1.0, 0.0001)


func test_weather_turbulence_can_only_push_across_horizontal_travel() -> void:
	var direction := Vector3(2.0, -1.0, 1.0).normalized()
	var lateral := LayerScript.lateral_turbulence(Vector3(0.7, 4.0, -0.3), direction)
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	assert_almost_eq(lateral.y, 0.0, 0.0001, "curl can lift snow and leave it suspended")
	assert_almost_eq(
		lateral.dot(flat_direction),
		0.0,
		0.0001,
		"curl accelerates a flake along its meteor-like travel line"
	)


func test_angular_damping_reaches_the_authored_end_fraction() -> void:
	var duration := 2.4
	var end_fraction := 0.12
	var rate := LayerScript.angular_damping_rate(end_fraction, duration)
	assert_true(rate > 0.0)
	assert_almost_eq(exp(-rate * duration), end_fraction, 0.0001)


func test_birth_spin_yields_to_the_art_directable_rock() -> void:
	var blizzard := _profile(&"blizzard")
	assert_not_null(blizzard)
	if blizzard == null:
		return
	var travel := absf(LayerScript.damped_spin_travel_degrees(
		blizzard.angular_velocity_range.y,
		blizzard.angular_velocity_end_multiplier,
		2.4
	))
	assert_true(
		travel <= 55.0,
		"birth spin still turns %.1f degrees before settling -- the flake is motor-driven" % travel
	)


func test_the_half_turn_eases_and_recovers_its_silhouette() -> void:
	assert_almost_eq(LayerScript.flip_ease(0.0), 0.0, 0.0001)
	assert_almost_eq(LayerScript.flip_ease(0.5), 0.5, 0.0001)
	assert_almost_eq(LayerScript.flip_ease(1.0), 1.0, 0.0001)
	var edge := 0.2
	assert_almost_eq(LayerScript.flip_width_scale(0.0, edge), 1.0, 0.0001)
	assert_almost_eq(LayerScript.flip_width_scale(0.5, edge), edge, 0.0001)
	assert_almost_eq(LayerScript.flip_width_scale(1.0, edge), 1.0, 0.0001)
	var epsilon := 0.001
	assert_true(
		LayerScript.flip_ease(epsilon) < epsilon * 0.01,
		"the flip leaves its resting pose with a hard linear kick"
	)
	assert_true(
		1.0 - LayerScript.flip_ease(1.0 - epsilon) < epsilon * 0.01,
		"the flip strikes its end pose instead of settling into it"
	)


func test_runtime_density_never_reallocates_the_particle_buffer() -> void:
	var layer := LayerScript.new() as WeatherVfxLayer
	layer.particle_budget = 384
	layer._build()
	var allocated := layer.amount
	var profile := _profile(&"freezing_rain")
	layer._profile = profile
	layer._density = 0.2
	layer._apply_profile()
	layer._density = 0.9
	layer._apply_profile()
	assert_eq(layer.amount, allocated, "weather density resized the GPU particle buffer")
	assert_eq(allocated, 384)
	assert_almost_eq(layer.amount_ratio, 0.9)
	layer.free()


func test_blizzard_motion_profile_reaches_the_gpu_emitter() -> void:
	var layer := LayerScript.new() as WeatherVfxLayer
	layer._build()
	var blizzard := _profile(&"blizzard")
	assert_not_null(blizzard)
	if blizzard == null:
		layer.free()
		return
	layer._profile = blizzard
	layer._density = blizzard.active_density
	layer._apply_profile()
	var material := layer.process_material as ShaderMaterial
	var surface := (layer.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_not_null(material, "weather motion is not running through its curl shader")
	if material != null:
		assert_eq(
			material.shader.resource_path,
			"res://src/rendering/weather_flake_motion.gdshader"
		)
		var influence: Vector2 = material.get_shader_parameter("turbulence_influence_range")
		var damping: Vector2 = material.get_shader_parameter("damping_range")
		var spin: Vector2 = material.get_shader_parameter("angular_velocity_range")
		var angular_drag: float = material.get_shader_parameter("angular_damping")
		var rock_amplitude: Vector2 = material.get_shader_parameter("rock_amplitude_range")
		var rock_frequency: Vector2 = material.get_shader_parameter("rock_frequency_range")
		var flutter_amplitude: Vector2 = material.get_shader_parameter("flutter_amplitude_range")
		var flutter_frequency: Vector2 = material.get_shader_parameter("flutter_frequency_range")
		assert_eq(influence, blizzard.turbulence_influence_range, "authored curl never reached the GPU")
		assert_eq(damping, blizzard.damping_range, "authored drag never reached the GPU")
		assert_eq(spin, blizzard.angular_velocity_range, "authored two-way tumble never reached the GPU")
		assert_true(angular_drag > 0.0, "the tumble has no angular damping")
		assert_eq(rock_amplitude, blizzard.rock_amplitude_range, "rock gesture never reached the GPU")
		assert_eq(rock_frequency, blizzard.rock_frequency_range, "rock timing never reached the GPU")
		assert_eq(
			flutter_amplitude, blizzard.flutter_amplitude_range,
			"edge flutter never reached the GPU"
		)
		assert_eq(
			flutter_frequency, blizzard.flutter_frequency_range,
			"varied flutter timing never reached the GPU"
		)
		assert_almost_eq(
			float(material.get_shader_parameter("flip_probability")),
			blizzard.flip_probability,
			0.0001,
			"occasional half-turns never reached the GPU"
		)
	assert_almost_eq(layer.randomness, blizzard.emission_randomness, 0.0001)
	assert_eq(
		layer.transform_align,
		GPUParticles3D.TRANSFORM_ALIGN_DISABLED,
		"blizzard flakes are still forced into velocity streaks"
	)
	assert_eq(
		surface.billboard_mode,
		BaseMaterial3D.BILLBOARD_PARTICLES,
		"fluttering flakes do not face the camera as particle billboards"
	)
	layer.free()


func test_freezing_rain_keeps_the_one_deliberate_velocity_streak_mode() -> void:
	var layer := LayerScript.new() as WeatherVfxLayer
	layer._build()
	var rain := _profile(&"freezing_rain")
	assert_not_null(rain)
	if rain != null:
		layer._profile = rain
		layer._density = rain.active_density
		layer._apply_profile()
		var surface := (layer.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		assert_eq(
			layer.transform_align,
			GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		)
		assert_eq(surface.billboard_mode, BaseMaterial3D.BILLBOARD_DISABLED)
		assert_eq(rain.rock_amplitude_range, Vector2.ZERO)
		assert_eq(rain.flutter_amplitude_range, Vector2.ZERO)
		assert_almost_eq(rain.flip_probability, 0.0, 0.0001)
	layer.free()


func test_main_scene_instances_the_weather_vfx_layer() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("res://scenes/effects/weather_vfx.tscn"), "Main does not load the weather VFX scene")
	assert_true(source.contains("[node name=\"WeatherVfx\""), "Main does not instance the weather VFX layer")


func test_renderer_contains_no_event_id_branches() -> void:
	var source := FileAccess.get_file_as_string("res://src/rendering/weather_vfx_layer.gd")
	for id in EVENT_IDS:
		assert_false(source.contains(String(id)), "renderer contains a special case for '%s'" % id)
