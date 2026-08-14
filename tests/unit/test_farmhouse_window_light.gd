extends TestCase

## The farmhouse window is the first warm point in the valley.  This suite
## guards the whole chain rather than merely checking that a preset contains a
## number: two authored anchors, two independently graded emissive surfaces,
## shaped roof/deck spill, and one master value that follows both the outside
## light and the fire inside.

const SCRIPT_PATH := "res://src/rendering/farmhouse_window_light.gd"
const EFFECT_SCENE_PATH := "res://scenes/effects/farmhouse_window_light.tscn"
const MODEL_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const PANE_SHADER_PATH := "res://src/rendering/window_emission.gdshader"
const SCATTER_SHADER_PATH := "res://src/rendering/window_scatter.gdshader"
const PALETTE_PATH := "res://data/palette/color_bible.tres"

const UPPER_ANCHOR_NAME := "Warm_Window_Upper"
const LOWER_ANCHOR_NAME := "Warm_Window_Lower"
const FRONT_PART_NAME := "FH_Fade_Front"
const UPPER_WARM_SLOT := "PAL_WARM_3"
const LOWER_WARM_SLOT := "PAL_WARM_3_AUX"


class FakeLighting extends Node:
	var accent := 0.0

	func warm_accent_energy() -> float:
		return accent


class FakeFire extends Node:
	var light_energy := 2.2
	var current := 2.2
	var lit := true

	func is_lit() -> bool:
		return lit

	func light_energy_now() -> float:
		return current if lit else 0.0


class FakeReveal extends Node:
	var amount := 0.0

	func fade() -> float:
		return amount


var _owned: Array[Node] = []


func after_each() -> void:
	for node in _owned:
		if node != null and is_instance_valid(node):
			node.free()
	_owned.clear()


func _new_subject() -> Node:
	if not ResourceLoader.exists(SCRIPT_PATH):
		return null
	var script: Script = load(SCRIPT_PATH)
	if script == null:
		return null
	var subject: Node = script.new()
	_owned.append(subject)
	return subject


func _model() -> Node:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate()
	_owned.append(model)
	return model


func _surface_for(instance: MeshInstance3D, slot: String) -> int:
	if instance == null or instance.mesh == null:
		return -1
	for surface in range(instance.mesh.get_surface_count()):
		var material := instance.mesh.surface_get_material(surface)
		if material != null and (material.resource_name == slot \
				or material.resource_name.begins_with(slot + ".")):
			return surface
	return -1


func test_the_complete_window_effect_ships_as_reviewable_files() -> void:
	for path in [SCRIPT_PATH, EFFECT_SCENE_PATH, PANE_SHADER_PATH, SCATTER_SHADER_PATH]:
		assert_true(ResourceLoader.exists(path), "%s does not ship" % path)


func test_the_model_authors_high_and_low_window_anchors_for_the_game_camera() -> void:
	var model := _model()
	assert_not_null(model, "the farmhouse model did not import")
	if model == null:
		return
	var upper := model.find_child(UPPER_ANCHOR_NAME, true, false) as Node3D
	var lower := model.find_child(LOWER_ANCHOR_NAME, true, false) as Node3D
	assert_not_null(upper, "the generated model has no %s anchor" % UPPER_ANCHOR_NAME)
	assert_not_null(lower, "the generated model has no %s anchor" % LOWER_ANCHOR_NAME)
	if upper == null or lower == null:
		return
	assert_almost_eq(upper.position.x, 2.0, 0.02, "the upper hope window moved off the porch")
	assert_almost_eq(upper.position.y, 4.10, 0.02, "the upper hope window left its storey")
	assert_almost_eq(lower.position.x, -2.55, 0.02, "the lower homecoming window moved off the wing")
	assert_almost_eq(lower.position.y, 1.85, 0.02, "the lower homecoming window left its storey")
	assert_almost_eq(upper.position.z, 0.03, 0.04, "the upper window anchor left the front wall")
	assert_almost_eq(lower.position.z, 3.63, 0.04, "the lower window anchor left the wing's front wall")
	assert_true(upper.basis.x.normalized().dot(Vector3.RIGHT) > 0.99,
		"the upper anchor no longer gives the halo its horizontal axis")
	assert_true(upper.basis.z.normalized().dot(Vector3.BACK) > 0.99,
		"the upper anchor no longer faces out of the front wall")
	assert_true(lower.basis.z.normalized().dot(Vector3.BACK) > 0.99,
		"the lower anchor no longer faces out of the front wall")


func test_the_generated_house_has_exactly_two_bright_window_quads() -> void:
	var model := _model()
	assert_not_null(model, "the farmhouse model did not import")
	if model == null:
		return
	var front := model.find_child(FRONT_PART_NAME, true, false) as MeshInstance3D
	assert_not_null(front, "%s is missing" % FRONT_PART_NAME)
	if front == null:
		return
	var upper_surface := _surface_for(front, UPPER_WARM_SLOT)
	var lower_surface := _surface_for(front, LOWER_WARM_SLOT)
	assert_true(upper_surface >= 0, "%s has no %s surface" % [FRONT_PART_NAME, UPPER_WARM_SLOT])
	assert_true(lower_surface >= 0, "%s has no %s surface" % [FRONT_PART_NAME, LOWER_WARM_SLOT])
	assert_true(upper_surface != lower_surface, "the upper and lower panes cannot be graded independently")
	if upper_surface < 0 or lower_surface < 0:
		return
	for entry in [
		{"surface": upper_surface, "label": "upper"},
		{"surface": lower_surface, "label": "lower"},
	]:
		var arrays := front.mesh.surface_get_arrays(entry["surface"])
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_eq(positions.size(), 4,
			"the %s warm window is not one four-corner pane" % entry["label"])


func test_environment_and_fire_form_one_monotonic_master_value() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	var day: float = subject.call(&"target_energy", 0.5, 1.0, 0.0)
	var dusk: float = subject.call(&"target_energy", 1.6, 1.0, 0.0)
	var night: float = subject.call(&"target_energy", 2.2, 1.0, 0.0)
	var day_pane: float = subject.call(&"pane_warmth", 0.5, 1.0, 0.0)
	var dusk_pane: float = subject.call(&"pane_warmth", 1.6, 1.0, 0.0)
	var day_scatter: float = subject.call(&"target_scatter_energy", 0.5, 1.0, 0.0)
	var night_scatter: float = subject.call(&"target_scatter_energy", 2.2, 1.0, 0.0)
	assert_true(day > 0.0, "a burning window disappeared completely in daylight")
	assert_true(dusk > day, "nightfall did not strengthen the window against the darker world")
	assert_true(night > dusk, "deep night did not make the window the visual anchor")
	assert_true(day_pane > 0.0 and day_pane < dusk_pane,
		"the pane stayed a fully saturated orange sticker in the bright day")
	assert_true(dusk_pane <= 1.0, "the pane warmth escaped its material range")
	assert_true(day_scatter < day, "the pale-day haze was not suppressed behind the pane")
	assert_almost_eq(night_scatter, night, 0.0001,
		"deep-night haze no longer reaches the authored endpoint")
	assert_true(subject.call(&"lower_pane_multiplier", 0.5) \
		< subject.call(&"lower_pane_multiplier", 2.2),
		"the lower support window did not stay quieter in daylight")
	assert_almost_eq(subject.call(&"target_energy", 2.2, 0.0, 0.0), 0.0, 0.0001,
		"a dead fire left a lying warm window")
	assert_almost_eq(subject.call(&"target_energy", 2.2, 1.0, 1.0), 0.0, 0.0001,
		"the exterior beam stayed behind after its wall was revealed away")
	assert_almost_eq(subject.call(&"pane_warmth", 2.2, 0.0, 0.0), 0.0, 0.0001,
		"a dead fire left colour in the pane")


func test_non_finite_inputs_are_dark_instead_of_poisoning_the_render_state() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	for bad in [NAN, INF, -INF]:
		assert_almost_eq(subject.call(&"target_energy", bad, 1.0, 0.0), 0.0, 0.0001,
			"a non-finite lighting value reached the window")
		assert_almost_eq(subject.call(&"target_energy", 2.2, bad, 0.0), 0.0, 0.0001,
			"a non-finite fire value reached the window")


func test_the_runtime_tick_consumes_the_published_light_and_continuous_fire() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	var lighting := FakeLighting.new()
	var fire := FakeFire.new()
	var reveal := FakeReveal.new()
	_owned.append(lighting)
	_owned.append(fire)
	_owned.append(reveal)
	subject.call(&"set_lighting", lighting)
	subject.call(&"set_fire", fire)
	subject.call(&"set_reveal", reveal)
	subject.set("rise_seconds", 0.0)
	subject.set("fall_seconds", 0.0)
	lighting.accent = 0.5
	subject.call(&"advance", 0.016)
	assert_almost_eq(subject.call(&"energy"), 0.5, 0.0001,
		"the window did not consume pale_day's published accent")
	lighting.accent = 2.2
	fire.current = 1.1
	subject.call(&"advance", 0.016)
	assert_almost_eq(subject.call(&"energy"), 1.1, 0.0001,
		"the window ignored the stove's continuous half-energy state")
	reveal.amount = 1.0
	subject.call(&"advance", 0.016)
	assert_almost_eq(subject.call(&"energy"), 0.0, 0.0001,
		"the runtime tick left its exterior light inside a revealed room")


func test_the_slow_breath_never_reads_as_a_flicker_or_an_extinguish() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	var low := INF
	var high := -INF
	for step in range(241):
		var breath: float = subject.call(&"breath_multiplier", float(step) * 0.05)
		low = minf(low, breath)
		high = maxf(high, breath)
	assert_true(low >= 0.965, "the fire breath falls to %.4f and reads as a flicker" % low)
	assert_true(high <= 1.035, "the fire breath rises to %.4f and reads as a flicker" % high)
	assert_true(high - low >= 0.02, "the authored breath is too small to survive the final frame")


func test_the_spill_mask_is_warm_soft_edged_and_stronger_at_its_near_end() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	var image: Image = subject.call(&"spill_mask_image", 33)
	assert_not_null(image, "the roof spill produced no projector mask")
	if image == null:
		return
	assert_eq(image.get_width(), 33, "the spill mask width")
	assert_eq(image.get_height(), 33, "the spill mask height")
	var bible: ColorBible = load(PALETTE_PATH)
	var warm: Color = bible.warm_tones[bible.warm_tones.size() - 1]
	var near := image.get_pixel(16, 8)
	var far := image.get_pixel(16, 29)
	var edge := image.get_pixel(0, 8)
	var near_strength := near.r / warm.r
	assert_true(near_strength > 0.0, "the projected light has no warm centre")
	assert_almost_eq(near.g, warm.g * near_strength, 2.0 / 255.0,
		"the projected light left the palette's amber hue")
	assert_true(near.a > far.a, "the spill did not fall away from the window")
	assert_true(far.a > edge.a, "the spill has no readable tapered silhouette")
	assert_true(edge.a <= 0.01, "the spill mask has a hard rectangular outer edge")
	assert_true(near.r > far.r and far.r > edge.r,
		"the emission texture did not carry the soft mask in RGB")


func test_the_lower_window_casts_a_broad_soft_area_instead_of_a_small_light_disc() -> void:
	var subject := _new_subject()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	if subject == null:
		return
	var image: Image = subject.call(&"area_spill_mask_image", 65)
	assert_not_null(image, "the lower area light produced no soft mask")
	if image == null:
		return
	var near := image.get_pixel(32, 14)
	var middle := image.get_pixel(32, 34)
	var far := image.get_pixel(32, 58)
	var shoulder := image.get_pixel(12, 34)
	var edge := image.get_pixel(0, 34)
	var bible: ColorBible = load(PALETTE_PATH)
	var warm: Color = bible.warm_tones[bible.warm_tones.size() - 1]
	assert_true(near.a > middle.a and middle.a > far.a,
		"the diffuse area does not fade continuously away from the window")
	assert_true(shoulder.a > edge.a and edge.a <= 0.01,
		"the diffuse area has a hard projector edge instead of a broad feather")
	assert_true(shoulder.a > 0.02,
		"the lower reflection stayed a narrow beam instead of opening into an area")
	assert_true(near.r > middle.r and middle.r > far.r,
		"the emission RGB does not follow the area's near-to-far alpha falloff")
	assert_true(shoulder.r > edge.r and edge.r <= 1.0 / 255.0,
		"the Decal emission RGB would expose its rectangular projector edge")
	var near_strength := near.r / warm.r
	assert_almost_eq(near.g, warm.g * near_strength, 2.0 / 255.0,
		"the diffuse area left the palette's amber hue")
	assert_almost_eq(near.b, warm.b * near_strength, 2.0 / 255.0,
		"the diffuse area left the palette's amber hue")
	for boundary in [
		image.get_pixel(0, 32), image.get_pixel(64, 32),
		image.get_pixel(32, 0), image.get_pixel(32, 64),
	]:
		assert_true(boundary.r <= 1.0 / 255.0 and boundary.g <= 1.0 / 255.0 \
			and boundary.b <= 1.0 / 255.0,
			"the area-light texture emits at one of its projector boundaries")


func test_only_the_authored_window_surface_receives_the_emissive_override() -> void:
	var subject := _new_subject()
	var model := _model()
	assert_not_null(subject, "%s cannot be instantiated" % SCRIPT_PATH)
	assert_not_null(model, "the farmhouse model did not import")
	if subject == null or model == null:
		return
	model.name = "Model"
	var building := Node3D.new()
	_owned.erase(subject)
	_owned.erase(model)
	_owned.append(building)
	building.add_child(model)
	building.add_child(subject)
	subject.set("model_path", NodePath("../Model"))
	subject.set("window_part_path", NodePath("../Model/%s" % FRONT_PART_NAME))
	subject.set("anchor_path", NodePath("../Model/%s" % UPPER_ANCHOR_NAME))
	subject.set("lower_anchor_path", NodePath("../Model/%s" % LOWER_ANCHOR_NAME))
	var resolved: bool = subject.call(&"resolve")
	assert_true(resolved, "the window effect did not resolve against the generated house")
	if not resolved:
		return
	var front := model.find_child(FRONT_PART_NAME, true, false) as MeshInstance3D
	var upper_surface := _surface_for(front, UPPER_WARM_SLOT)
	var lower_surface := _surface_for(front, LOWER_WARM_SLOT)
	var pane_material: ShaderMaterial = subject.call(&"pane_material")
	var lower_pane_material: ShaderMaterial = subject.call(&"lower_pane_material")
	assert_not_null(pane_material, "the warm pane received no dedicated material")
	assert_not_null(lower_pane_material, "the lower pane received no dedicated material")
	assert_true(front.get_surface_override_material(upper_surface) == pane_material,
		"the upper warm surface did not receive the hero emission")
	assert_true(front.get_surface_override_material(lower_surface) == lower_pane_material,
		"the lower warm surface did not receive its quieter emission")
	assert_true(pane_material != lower_pane_material,
		"the two storeys share one material and cannot hold an upper/lower hierarchy")
	assert_almost_eq((pane_material.get_shader_parameter("pane_center") as Vector2).x,
		2.0, 0.02, "the upper HDR core is not centred on its pane")
	assert_almost_eq((lower_pane_material.get_shader_parameter("pane_center") as Vector2).y,
		1.85, 0.02, "the lower HDR core is not centred on its pane")
	assert_true(float(pane_material.get_shader_parameter("muntin_strength")) >= 0.8,
		"the clear upper window lost the dark structure that keeps its light legible")
	assert_true(float(lower_pane_material.get_shader_parameter("muntin_strength")) >= 0.8,
		"the clear lower window lost the dark structure that keeps its light legible")
	assert_not_null(subject.get_node_or_null("WindowHaloUpper"), "the upper window has no haze")
	assert_not_null(subject.get_node_or_null("WindowHaloLower"), "the lower window has no haze")
	assert_not_null(subject.call(&"roof_spill"), "the upper window has no porch-roof spill")
	var lower_spill: Decal = subject.call(&"lower_spill")
	assert_not_null(lower_spill, "the lower window has no soft snow spill")
	if lower_spill != null:
		assert_almost_eq(lower_spill.size.x, 4.80, 0.001,
			"the lower reflection lost its authored area width")
		assert_almost_eq(lower_spill.size.y, 0.80, 0.001,
			"the lower reflection lost its authored snow projection depth")
		assert_almost_eq(lower_spill.size.z, 5.40, 0.001,
			"the lower reflection lost its authored area reach")
		assert_not_null(lower_spill.texture_emission,
			"the diffuse area has no emission mask")
		assert_true(lower_spill.transform.basis.y.normalized().dot(Vector3.UP) > 0.99,
			"the lower reflection no longer projects down onto the snow")
	for surface in range(front.mesh.get_surface_count()):
		if surface == upper_surface or surface == lower_surface:
			continue
		assert_false(front.get_surface_override_material(surface) == pane_material \
			or front.get_surface_override_material(surface) == lower_pane_material,
			"window emission leaked onto facade surface %d" % surface)
	var silhouette := StandardMaterial3D.new()
	front.material_override = silhouette
	assert_almost_eq(subject.call(&"_geometry_visibility"), 0.0, 0.0001,
		"detached haze reappears over OccluderFader's neutral silhouette")
	front.material_override = null


func test_the_effect_scene_is_wired_into_the_real_farmhouse() -> void:
	assert_true(ResourceLoader.exists(EFFECT_SCENE_PATH), "%s does not ship" % EFFECT_SCENE_PATH)
	if not ResourceLoader.exists(EFFECT_SCENE_PATH):
		return
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed, "the real main scene did not load")
	if packed == null:
		return
	var main := packed.instantiate()
	_owned.append(main)
	var effect := main.get_node_or_null("Farmhouse/WindowLight")
	assert_not_null(effect, "the farmhouse has no WindowLight instance")
	if effect == null:
		return
	assert_eq(effect.get("fire_path"), NodePath("../Stove"), "the window is not driven by the farmhouse fire")
	assert_eq(effect.get("reveal_path"), NodePath("../InteriorReveal"),
		"the exterior spill will remain suspended after the facade fades")
