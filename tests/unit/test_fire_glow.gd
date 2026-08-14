extends TestCase

## Open fire must read as a small three-dimensional pool of warmth, never as a
## broad screen-space disc painted onto the snow.  These tests guard the render
## layer boundary as well as the authored range, falloff, shadow and day/night
## response that make the burning barrel legible without exaggerating it.

const FIRE_GLOW_SCRIPT := preload("res://src/entities/fire_glow.gd")
const TERRAIN_RENDERER_SCRIPT := preload("res://src/rendering/terrain_renderer.gd")
const WINDOW_LIGHT_SCRIPT := preload("res://src/rendering/farmhouse_window_light.gd")
const EVENT_BUS_SCRIPT := preload("res://src/core/event_bus.gd")

const WORLD_PROP_RENDER_LAYER := 1
const CHARACTER_RENDER_LAYER := 2
const SNOW_RENDER_LAYER := 8
const FIRE_LIT_RENDER_LAYERS := 11
const SNOW_SHADER_PATH := "res://src/rendering/snow_ground.gdshader"

var _owned: Array[Node] = []


func after_each() -> void:
	# FireGlow unsubscribes during PREDELETE, so it must be released before the
	# bus it is listening to.
	_owned.reverse()
	for node in _owned:
		if node != null and is_instance_valid(node):
			node.free()
	_owned.clear()


func _fire_with_bus() -> OmniLight3D:
	var bus: Node = EVENT_BUS_SCRIPT.new()
	_owned.append(bus)
	var fire: OmniLight3D = FIRE_GLOW_SCRIPT.new()
	_owned.append(fire)
	if fire.has_method(&"set_event_bus"):
		fire.call(&"set_event_bus", bus)
	fire._ready()
	return fire


func test_barrel_fire_is_a_small_shadow_casting_radial_light() -> void:
	var fire := _fire_with_bus()
	var night_energy := float(fire.get(&"base_energy"))
	var day_multiplier := float(fire.get(&"day_energy_multiplier"))
	assert_true(fire.omni_range >= 1.5, "the fire has no useful 3D reach")
	assert_true(fire.omni_range <= 3.0,
		"the barrel reaches %.2f m; a local fire must not flood the yard" % fire.omni_range)
	assert_true(fire.omni_attenuation >= 1.8,
		"the barrel falloff is too flat to read as a compact radial source")
	assert_true(fire.shadow_enabled,
		"nearby props cannot ground the radial firelight without local shadows")
	assert_true(night_energy >= 2.8 and night_energy <= 3.4,
		"night energy %.2f is either unreadable or exaggerated" % night_energy)
	assert_true(day_multiplier <= 0.15,
		"daylight keeps too much of the night fire: %.2f" % day_multiplier)


func test_fire_reaches_props_character_and_the_dedicated_snow_path() -> void:
	var fire := _fire_with_bus()
	assert_eq(fire.light_cull_mask, FIRE_LIT_RENDER_LAYERS,
		"the barrel light must address props, character and its controlled snow path")
	assert_true((fire.light_cull_mask & WORLD_PROP_RENDER_LAYER) != 0,
		"nearby three-dimensional props cannot receive the radial light")
	assert_true((fire.light_cull_mask & CHARACTER_RENDER_LAYER) != 0,
		"the player cannot pick up the warm night light shown in the reference")

	var terrain: MeshInstance3D = TERRAIN_RENDERER_SCRIPT.new()
	_owned.append(terrain)
	terrain._ready()
	var local_snow_gain := float(terrain.get(&"local_light_snow_gain"))
	assert_eq(terrain.layers, SNOW_RENDER_LAYER,
		"the snow stayed on the world-prop layer and can still become a light disc")
	assert_eq(terrain.layers & fire.light_cull_mask, SNOW_RENDER_LAYER,
		"the dedicated snow-light path is not connected to the barrel")
	assert_true(local_snow_gain >= 0.85 and local_snow_gain <= 1.0,
		"snow fire gain %.2f is either invisible or overexposed" % local_snow_gain)
	var skirt := terrain.get_node_or_null("HorizonSkirt") as MeshInstance3D
	assert_not_null(skirt, "the snow continuation was not built")
	if skirt != null:
		assert_eq(skirt.layers, SNOW_RENDER_LAYER,
			"the horizon snow can still receive the barrel light")


func test_snow_handles_local_fire_as_a_soft_coloured_contribution_not_a_cel_disc() -> void:
	var source := FileAccess.get_file_as_string(SNOW_SHADER_PATH)
	assert_true(source.contains("if (!LIGHT_IS_DIRECTIONAL)"),
		"local lights still enter the directional cel-band path that made the pixel disc")
	assert_true(source.contains("LIGHT_COLOR"),
		"the snow local-light path ignores the fire's warm palette colour")
	assert_true(source.contains("local_response"),
		"the snow has no separately controlled soft radial response")


func test_window_spill_still_targets_snow_after_the_layer_split() -> void:
	var effect: Node3D = WINDOW_LIGHT_SCRIPT.new()
	_owned.append(effect)
	var texture := GradientTexture2D.new()
	effect.call(
		&"_build_spill", Transform3D.IDENTITY, texture, Vector3.UP,
		Vector3.ZERO, Vector2.ONE, 1.0, 1.0, &"TestSnowSpill"
	)
	var spill := effect.get_node_or_null("TestSnowSpill") as Decal
	assert_not_null(spill, "the controlled window spill was not built")
	if spill != null:
		assert_eq(spill.cull_mask, SNOW_RENDER_LAYER,
			"the farmhouse's authored snow reflection was lost in the layer split")


func test_night_is_visibly_stronger_than_day_without_expanding_the_radius() -> void:
	var bus: Node = EVENT_BUS_SCRIPT.new()
	_owned.append(bus)
	var fire: OmniLight3D = FIRE_GLOW_SCRIPT.new()
	_owned.append(fire)
	assert_true(fire.has_method(&"set_event_bus"),
		"the fire cannot listen to clock phase events through EventBus")
	if not fire.has_method(&"set_event_bus"):
		return
	fire.call(&"set_event_bus", bus)
	fire._ready()

	bus.call(&"emit_event", &"clock.day_started", 1)
	fire._process(0.0)
	var day_energy := fire.light_energy
	var day_range := fire.omni_range
	bus.call(&"emit_event", &"clock.night_started", 1)
	fire._process(0.0)
	var night_energy := fire.light_energy

	assert_true(day_energy > 0.0, "the flame went completely dead in daylight")
	assert_true(night_energy >= day_energy * 3.0,
		"night %.3f is not clearly stronger than day %.3f" % [night_energy, day_energy])
	assert_almost_eq(fire.omni_range, day_range, 0.0001,
		"nightfall enlarged the light pool instead of strengthening the same small fire")
