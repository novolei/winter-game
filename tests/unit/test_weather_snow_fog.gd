extends TestCase

const ProfileScript := preload("res://src/definitions/weather_fog_profile.gd")
const FogScript := preload("res://src/rendering/weather_snow_fog.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const SHADER_PATH := "res://src/rendering/weather_snow_fog.gdshader"
const SCENE_PATH := "res://scenes/effects/weather_snow_fog.tscn"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"


class FakeEvent extends RefCounted:
	var fog_profile = null


class FakeWeather extends RefCounted:
	var current_phase: StringName = &"clear"
	var current_tell := 0.0
	var current_intensity := 0.0
	var current_event = null

	func phase() -> StringName:
		return current_phase

	func tell_progress() -> float:
		return current_tell

	func intensity() -> float:
		return current_intensity

	func active_event():
		return current_event


class FakeWind extends RefCounted:
	var current_velocity := Vector3.ZERO

	func velocity() -> Vector3:
		return current_velocity


func _profile() -> WeatherFogProfile:
	var profile := ProfileScript.new() as WeatherFogProfile
	profile.id = &"probe"
	profile.tell_density = 0.0002
	profile.active_density = 0.0012
	profile.peak_density = 0.0018
	return profile


func _shipped_profile(id: StringName) -> WeatherFogProfile:
	return ResourceLoader.load(
		"res://data/weather/fog/%s.tres" % String(id),
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as WeatherFogProfile


func test_only_weather_that_authors_a_veil_receives_one() -> void:
	for id in [&"blizzard", &"snow_fog"]:
		var event := ResourceLoader.load(
			"res://data/weather/event_%s.tres" % String(id),
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as WeatherEventDefinition
		assert_not_null(event, "weather '%s' is missing" % id)
		if event != null:
			assert_not_null(event.fog_profile, "weather '%s' has no local snow veil" % id)
			if event.fog_profile != null:
				assert_eq(event.fog_profile.id, id, "weather '%s' points at another fog" % id)
				assert_true(event.fog_profile.is_valid(), "weather '%s' has invalid fog data" % id)
	for id in [&"wind_shift", &"clear_break", &"freezing_rain", &"cold_snap"]:
		var event := ResourceLoader.load(
			"res://data/weather/event_%s.tres" % String(id),
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as WeatherEventDefinition
		assert_not_null(event, "weather '%s' is missing" % id)
		if event != null:
			assert_eq(event.fog_profile, null, "weather '%s' gained an unrelated volumetric veil" % id)


func test_blizzard_builds_a_stronger_faster_noisier_veil_than_snow_fog() -> void:
	var blizzard := _shipped_profile(&"blizzard")
	var quiet_fog := _shipped_profile(&"snow_fog")
	assert_not_null(blizzard)
	assert_not_null(quiet_fog)
	if blizzard != null and quiet_fog != null:
		assert_true(blizzard.active_density > quiet_fog.active_density)
		assert_true(blizzard.noise_contrast > quiet_fog.noise_contrast)
		assert_true(blizzard.max_advection_speed_mps > quiet_fog.max_advection_speed_mps)
		assert_true(blizzard.detail_weight > quiet_fog.detail_weight)


func test_blizzard_intensity_ladder_changes_density_continuously_and_monotonically() -> void:
	var profile := _shipped_profile(&"blizzard")
	assert_not_null(profile)
	if profile == null:
		return
	var previous := FogScript.density_for(profile, &"active", 0.0, 0.0)
	for strength in [0.25, 0.5, 0.75, 1.0]:
		var current := FogScript.density_for(profile, &"active", 0.0, strength)
		assert_true(current > previous, "blizzard %.0f%% has no distinct veil" % (strength * 100.0))
		assert_true(current <= profile.peak_density, "blizzard veil exceeds its authored peak")
		previous = current


func test_profile_is_data_driven_and_rejects_density_above_the_hard_ceiling() -> void:
	var profile := _profile()
	assert_true(profile.is_valid(), "the default local-fog profile is unusable")
	profile.peak_density = 0.06401
	assert_false(profile.is_valid(), "a profile can exceed the project's local-fog ceiling")
	profile.peak_density = 0.0010
	assert_false(profile.is_valid(), "authored active density can silently exceed its own peak")


func test_density_crosses_tell_active_and_fade_without_a_step() -> void:
	var profile := _profile()
	var tell_end := FogScript.density_for(profile, &"tell", 1.0, 0.0)
	var arrival_start := FogScript.density_for(profile, &"active", 0.0, 0.0)
	assert_almost_eq(tell_end, arrival_start, 0.000001, "snow fog pops at arrival")
	assert_almost_eq(
		FogScript.density_for(profile, &"active", 0.0, 1.0),
		profile.active_density,
		0.000001
	)
	assert_almost_eq(FogScript.density_for(profile, &"fade", 0.0, 0.0), 0.0, 0.000001)
	assert_almost_eq(FogScript.density_for(profile, &"clear", 1.0, 1.0), 0.0, 0.000001)


func test_density_is_clamped_even_when_bad_runtime_data_reaches_the_renderer() -> void:
	var profile := _profile()
	profile.active_density = 0.009
	profile.peak_density = 0.0015
	assert_almost_eq(
		FogScript.density_for(profile, &"active", 0.0, 1.0),
		0.0015,
		0.000001,
		"the shader can be fed more than the absolute local-fog ceiling"
	)


func test_advection_is_a_frame_rate_independent_integral_of_resolved_wind() -> void:
	var wind := Vector3(7.0, 5.0, -3.0)
	var offset_30 := Vector3.ZERO
	var flow_30 := Vector3.ZERO
	for _step in range(90):
		offset_30 += FogScript.flow_displacement(flow_30, wind, 1.0 / 30.0, 2.4, 0.8)
		flow_30 = FogScript.flow_after(flow_30, wind, 1.0 / 30.0, 2.4, 0.8)
	var offset_60 := Vector3.ZERO
	var flow_60 := Vector3.ZERO
	for _step in range(180):
		offset_60 += FogScript.flow_displacement(flow_60, wind, 1.0 / 60.0, 2.4, 0.8)
		flow_60 = FogScript.flow_after(flow_60, wind, 1.0 / 60.0, 2.4, 0.8)
	assert_true(offset_30.distance_to(offset_60) < 0.0001, "noise drift changes with frame rate")
	assert_almost_eq(offset_60.y, 0.0, 0.000001, "vertical wind scrolls the fog texture")
	assert_true(offset_60.dot(Vector3(wind.x, 0.0, wind.z)) > 0.0, "fog moves against the wind")


func test_depth_window_clears_the_foreground_and_feathers_both_ends() -> void:
	assert_almost_eq(FogScript.depth_gate(70.0, 76.0, 88.0, 112.0, 128.0), 0.0)
	assert_almost_eq(FogScript.depth_gate(90.0, 76.0, 88.0, 112.0, 128.0), 1.0)
	assert_true(FogScript.depth_gate(82.0, 76.0, 88.0, 112.0, 128.0) > 0.0)
	assert_true(FogScript.depth_gate(120.0, 76.0, 88.0, 112.0, 128.0) > 0.0)
	assert_almost_eq(FogScript.depth_gate(130.0, 76.0, 88.0, 112.0, 128.0), 0.0)


func test_one_box_volume_uses_one_48_cubed_noise_and_two_shader_samples() -> void:
	var fog := FogScript.new() as WeatherSnowFog
	fog._build()
	var texture := fog.noise_texture()
	assert_eq(fog.shape, RenderingServer.FOG_VOLUME_SHAPE_BOX)
	assert_eq(texture.width, 48)
	assert_eq(texture.height, 48)
	assert_eq(texture.depth, 48)
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	assert_eq(source.count("texture("), 2, "fog shader samples its volume texture more than twice")
	assert_true(source.contains("WORLD_POSITION"), "fog noise is not anchored in world space")
	assert_true(source.contains("near_clear_depth"), "the shader has no foreground safety gate")
	fog.free()


func test_camera_follow_box_starts_at_the_lens_and_extends_forward() -> void:
	var camera_transform := Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(22.0), 0.0)),
		Vector3(4.0, 12.0, -7.0)
	)
	var volume_size := Vector3(48.0, 48.0, 132.0)
	var placed := FogScript.volume_transform_for(camera_transform, volume_size)
	var expected := camera_transform.origin - camera_transform.basis.z * volume_size.z * 0.5
	assert_true(placed.origin.is_equal_approx(expected), "fog box does not follow camera depth")
	assert_true(placed.basis.is_equal_approx(camera_transform.basis), "fog box ignores camera orientation")


func test_profile_and_live_wind_reach_the_fog_shader_without_exceeding_peak() -> void:
	var fog := FogScript.new() as WeatherSnowFog
	fog._build()
	var profile := _profile()
	profile.macro_scale_m = Vector3(12.0, 5.0, 8.0)
	profile.detail_scale_m = Vector3(4.5, 2.5, 3.0)
	var event := FakeEvent.new()
	event.fog_profile = profile
	var weather := FakeWeather.new()
	weather.current_event = event
	weather.current_phase = &"active"
	weather.current_intensity = 1.0
	var wind := FakeWind.new()
	wind.current_velocity = Vector3(8.0, 2.0, -1.0)
	fog.set_weather_source(weather)
	fog.set_wind_source(wind)
	fog.advance(1.0)
	var material := fog.fog_shader_material()
	assert_true(float(material.get_shader_parameter("fog_density")) <= profile.peak_density)
	assert_eq(material.get_shader_parameter("macro_scale_m"), profile.macro_scale_m)
	assert_eq(material.get_shader_parameter("detail_scale_m"), profile.detail_scale_m)
	var offset: Vector3 = material.get_shader_parameter("advection_offset")
	assert_true(offset.x > 0.0, "live wind never advected the local fog")
	fog.free()


func test_bus_event_is_published_only_when_local_fog_switches_active_state() -> void:
	var fog := FogScript.new() as WeatherSnowFog
	fog._build()
	var bus := EventBusScript.new()
	var seen: Array = []
	bus.subscribe(FogScript.EVENT_ACTIVE_CHANGED, func(payload): seen.append(payload))
	fog.set_event_bus(bus)
	var event := FakeEvent.new()
	event.fog_profile = _profile()
	var weather := FakeWeather.new()
	weather.current_event = event
	fog.set_weather_source(weather)
	fog.advance(0.0)
	weather.current_phase = &"tell"
	weather.current_tell = 0.5
	fog.advance(0.1)
	weather.current_tell = 0.8
	fog.advance(0.1)
	weather.current_phase = &"active"
	weather.current_intensity = 0.8
	fog.advance(0.1)
	assert_eq(seen.size(), 1, "density updates publish as if they were state changes")
	assert_true(bool(seen[0]["active"]))
	weather.current_phase = &"clear"
	fog.advance(0.1)
	fog.advance(0.1)
	assert_eq(seen.size(), 2, "one on/off cycle did not publish exactly two edges")
	assert_false(bool(seen[1]["active"]))
	fog.free()
	bus.free()


func test_scene_is_one_fog_volume_and_renderer_has_no_weather_id_branches() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	assert_not_null(scene, "local weather fog scene is missing")
	if scene != null:
		var instance := scene.instantiate()
		assert_true(instance is WeatherSnowFog, "scene root is not the local fog volume")
		instance.free()
	assert_eq(FogScript.EVENT_ACTIVE_CHANGED, &"rendering.local_volumetric_fog_changed")
	var source := FileAccess.get_file_as_string("res://src/rendering/weather_snow_fog.gd")
	for event_id in ["blizzard", "snow_fog", "freezing_rain", "cold_snap", "wind_shift"]:
		assert_false(source.contains(event_id), "local fog renderer branches on '%s'" % event_id)
	var main_source := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	assert_true(
		main_source.contains("[node name=\"WeatherSnowFog\""),
		"Main does not instance the local weather fog"
	)
