extends TestCase

## Performance work is allowed to remove redundant CPU/GPU submissions, never
## to thin the picture.  These tests count work at the three visual-runtime
## boundaries without changing a single authored rendering value.

const TerrainRendererScript := preload("res://src/rendering/terrain_renderer.gd")
const SpindriftScript := preload("res://src/rendering/spindrift.gd")
const OccluderFaderScript := preload("res://src/rendering/occluder_fader.gd")
const WeatherVfxScript := preload("res://src/rendering/weather_vfx_layer.gd")

const FRAME := 1.0 / 60.0


func test_terrain_uniforms_are_submitted_only_when_the_value_changes() -> void:
	var terrain: TerrainRenderer = TerrainRendererScript.new()
	terrain._ready()
	terrain.reset_material_parameter_write_count()

	# The fallback lighting and mark shape were already stamped by _ready().
	terrain.apply_world_shading(
		terrain.band_threshold, terrain.band_softness, Color.WHITE)
	terrain._stamp_marks()
	assert_eq(terrain.material_parameter_write_count(), 0,
		"an unchanged frame resubmitted terrain uniforms")

	terrain.apply_world_shading(0.19, 0.08, Color(0.92, 0.96, 1.0))
	assert_eq(terrain.material_parameter_write_count(), 3,
		"a lighting transition did not submit exactly its three changed values")
	terrain.apply_world_shading(0.19, 0.08, Color(0.92, 0.96, 1.0))
	assert_eq(terrain.material_parameter_write_count(), 3,
		"a settled lighting preset kept resubmitting the same values")

	terrain.track_depth += 0.001
	terrain._stamp_marks()
	assert_eq(terrain.material_parameter_write_count(), 4,
		"an inspector edit did not update exactly the changed mark parameter")
	terrain.free()


func test_terrain_texture_and_window_bindings_reuse_their_existing_rids() -> void:
	var terrain: TerrainRenderer = TerrainRendererScript.new()
	terrain._ready()
	terrain.reset_material_parameter_write_count()
	var texture := ImageTexture.new()
	assert_true(terrain._set_material_parameter(&"track_mask", texture))
	assert_true(terrain._set_material_parameter(&"track_origin", Vector2(-32.0, -32.0)))
	assert_false(terrain._set_material_parameter(&"track_mask", texture),
		"the same texture RID was rebound on an unchanged frame")
	assert_false(terrain._set_material_parameter(&"track_origin", Vector2(-32.0, -32.0)),
		"the same track window origin was resubmitted on an unchanged frame")
	assert_eq(terrain.material_parameter_write_count(), 2)
	assert_true(terrain._set_material_parameter(&"track_origin", Vector2(-24.0, -32.0)),
		"a recentered track window did not reach the shader")
	assert_eq(terrain.material_parameter_write_count(), 3)
	terrain.free()


func test_spindrift_rebakes_only_while_the_sheet_exists() -> void:
	var drift: Spindrift = SpindriftScript.new()
	drift._build()
	drift.reset_bake_count()
	for _frame in 600:
		drift._process(FRAME)
	assert_eq(drift.bake_count(), 0,
		"ten seconds of still air rebuilt the 4096-point spindrift cloud")

	drift.set_wind(Vector3(1.0, 0.0, 0.0))
	drift.set_wind_strength(drift.stream_onset + 0.1)
	drift._process(0.0)
	assert_eq(drift.bake_count(), 1,
		"the first active frame did not bake the wind-aligned sheet immediately")
	for _frame in 15:
		drift._process(FRAME)
	assert_eq(drift.bake_count(), 2,
		"an active sheet lost its authored quarter-second pattern refresh")
	drift.free()


func test_weather_accents_share_one_fixed_low_frequency_gpu_budget() -> void:
	var layer: WeatherVfxLayer = WeatherVfxScript.new()
	layer._build()
	assert_true(layer.amount <= 640,
		"weather accents allocated %d particles instead of the shared 640 budget" % layer.amount)
	assert_eq(layer.fixed_fps, 30, "weather accents simulate above the authored 30 Hz budget")
	assert_eq(layer.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"weather accents entered the 8192 shadow map")
	assert_eq(layer.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
		"weather accents entered global illumination")
	layer.free()


func test_occlusion_sampling_is_bounded_and_still_reacts_to_teleports() -> void:
	var fader: Node = OccluderFaderScript.new()
	fader.reset_occlusion_sampling()
	var samples := 0
	var camera := Transform3D(Basis.IDENTITY, Vector3(0.0, 12.0, 10.0))
	var aim := Vector3(0.0, 1.4, 0.0)
	for _frame in 60:
		if fader.occlusion_sample_due(FRAME, camera, aim):
			samples += 1
	assert_eq(samples, 1,
		"a still camera and subject should reuse the first exact ray result")

	fader.reset_occlusion_sampling()
	samples = 0
	for _frame in 60:
		aim.x += 3.0 * FRAME
		if fader.occlusion_sample_due(FRAME, camera, aim):
			samples += 1
	assert_true(samples >= 19 and samples <= 21,
		"one second of motion issued %d samples instead of the 20 Hz budget" % samples)

	fader.reset_occlusion_sampling()
	assert_true(fader.occlusion_sample_due(0.0, camera, aim))
	var teleported := Transform3D(camera.basis, camera.origin + Vector3(2.0, 0.0, 0.0))
	assert_true(fader.occlusion_sample_due(0.0, teleported, aim),
		"a camera teleport waited for the fixed-rate sample")
	fader.reset_occlusion_sampling()
	assert_true(fader.occlusion_sample_due(0.0, camera, aim))
	var turned := Transform3D(Basis(Vector3.UP, 0.1), camera.origin)
	assert_false(fader.occlusion_sample_due(FRAME, turned, aim),
		"ordinary orthographic camera rotation escaped the fixed-rate budget")
	assert_true(fader.occlusion_sample_due(1.0 / fader.occlusion_sample_hz, turned, aim),
		"orthographic camera rotation did not refresh the projected ray")
	fader.free()
