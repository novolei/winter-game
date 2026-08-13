extends TestCase

## A footprint fills from its shallow perimeter toward its deeper core.  The
## remaining core therefore passes through the same scalar mask values that a
## fresh print's pushed-snow shoulder uses.  Mask value alone cannot tell those
## two surfaces apart: the visual seam is spatial edge evidence.  This test
## models the shader's existing four-neighbour central difference and locks the
## final lip weight to that evidence without changing TrackMask decay.

const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"
const TRACK_NORMAL_EPSILON := 0.06


func test_flat_weathered_core_never_becomes_a_new_snow_lip() -> void:
	var settings := _shader_settings()
	var weathered_core := _lip_sample(0.10, 0.10, 0.10, 0.10, 0.10, settings)
	assert_true(float(weathered_core.legacy_lip) >= 0.50,
		"fixture no longer reproduces the legacy false-lip peak")
	assert_true(float(weathered_core.edge_slope) <= 0.000001,
		"the flat-core fixture accidentally contains an edge")
	assert_true(float(weathered_core.lip) <= 0.000001,
		"a flat 0.10 weathered core still becomes %.3f snow lip" % weathered_core.lip)


func test_snow_lip_recedes_before_the_cavity_core_finishes_filling() -> void:
	var settings := _shader_settings()
	# Worked samples of one wall as subtractive fill and neighbour slump make it
	# shallower.  Legacy value-only lip grows 0.20 -> 0.55 -> 0.49; the spatially
	# gated lip must instead recede with the wall that physically supports it.
	var fresh := _lip_sample(0.12, 0.15, 0.09, 0.12, 0.12, settings)
	var filling := _lip_sample(0.10, 0.115, 0.085, 0.10, 0.10, settings)
	var old := _lip_sample(0.08, 0.088, 0.072, 0.08, 0.08, settings)
	assert_true(float(fresh.lip) >= 0.15,
		"the real fresh outer wall lost its restrained displaced-snow lip")
	assert_true(float(filling.lip) < float(fresh.lip) * 0.35,
		"the lip grew while filling: fresh %.3f, filling %.3f"
			% [fresh.lip, filling.lip])
	assert_true(float(old.lip) <= 0.01,
		"an almost-flat old core still carries %.3f of a fresh snow lip" % old.lip)


func test_dynamic_cavity_area_is_monotonic_while_the_print_weathers() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	var cavity_start := _uniform_float(source, "footprint_cavity_start", 0.07)
	var cavity_full := _uniform_float(source, "footprint_cavity_full", 0.14)
	var fresh_values := PackedFloat32Array([
		0.00, 0.04, 0.08, 0.11, 0.08, 0.04, 0.00,
		0.03, 0.08, 0.13, 0.17, 0.13, 0.08, 0.03,
		0.05, 0.11, 0.17, 0.20, 0.17, 0.11, 0.05,
		0.03, 0.08, 0.13, 0.17, 0.13, 0.08, 0.03,
		0.00, 0.04, 0.08, 0.11, 0.08, 0.04, 0.00,
	])
	var previous_area := fresh_values.size() + 1
	for fill in [0.00, 0.025, 0.05, 0.075, 0.10, 0.125]:
		var cavity_area := 0
		for fresh_value in fresh_values:
			var remaining := maxf(fresh_value - fill, 0.0)
			if smoothstep(cavity_start, cavity_full, remaining) >= 0.5:
				cavity_area += 1
		assert_true(cavity_area <= previous_area,
			"cavity area grew from %d to %d while depth was removed"
				% [previous_area, cavity_area])
		previous_area = cavity_area


func test_weathering_gate_reuses_fragment_neighbours_without_more_fetches() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	var gradient_body := _function_body(source, "vec2 track_gradient")
	var fragment_body := _function_body(source, "void fragment")
	var light_body := _function_body(source, "void light")
	assert_eq(_occurrences(gradient_body, "track_at("), 4,
		"track_gradient no longer has the four-neighbour sampling budget")
	assert_eq(_occurrences(fragment_body, "dynamic_track_at("), 1,
		"fragment added another dynamic TrackMask centre fetch")
	assert_eq(_occurrences(fragment_body, "baked_at("), 1,
		"fragment added another baked-track fetch")
	assert_eq(_occurrences(light_body, "dynamic_track_at("), 0,
		"light() added a per-light TrackMask fetch")
	assert_true(fragment_body.contains("length(track_slope)"),
		"lip weight is not gated by the already-computed spatial edge")
	assert_true(fragment_body.contains("footprint_lip_edge"),
		"the spatial edge evidence is not routed into the lip")


func test_snow_shader_compiles_with_the_weathering_gate() -> void:
	var shader: Shader = ResourceLoader.load(
		SHADER_PATH, "Shader", ResourceLoader.CACHE_MODE_IGNORE
	)
	assert_not_null(shader, "snow_ground did not load as a Shader")
	if shader == null:
		return
	assert_true(shader.get_shader_uniform_list().size() > 0,
		"snow_ground declares uniforms but reports none; shader compilation failed")


func _lip_sample(
	centre: float,
	x_right: float,
	x_left: float,
	z_right: float,
	z_left: float,
	settings: Dictionary
) -> Dictionary:
	var local_peak := maxf(maxf(x_right, x_left), maxf(z_right, z_left))
	var rim_gate := lerpf(
		settings.thin_rim_share,
		1.0,
		smoothstep(settings.rim_gate_start, settings.rim_gate_full, local_peak)
	)
	var track_slope := Vector2(
		_track_height(x_right, rim_gate, settings)
			- _track_height(x_left, rim_gate, settings),
		_track_height(z_right, rim_gate, settings)
			- _track_height(z_left, rim_gate, settings)
	) / (2.0 * TRACK_NORMAL_EPSILON)
	var cavity := smoothstep(settings.cavity_start, settings.cavity_full, centre)
	var skirt := clampf(centre / settings.rim_extent, 0.0, 1.0)
	var rim := 4.0 * skirt * (1.0 - skirt)
	var legacy_lip := smoothstep(settings.lip_start, settings.lip_full, rim) \
		* (1.0 - cavity)
	var edge_evidence := smoothstep(
		settings.lip_edge_start, settings.lip_edge_full, track_slope.length()
	)
	return {
		"legacy_lip": legacy_lip,
		"edge_slope": track_slope.length(),
		"lip": legacy_lip * edge_evidence,
	}


func _track_height(value: float, rim_gate: float, settings: Dictionary) -> float:
	var skirt := clampf(value / settings.rim_extent, 0.0, 1.0)
	var rim := 4.0 * skirt * (1.0 - skirt)
	return -value * settings.track_depth + rim_gate * rim * settings.track_rim


func _shader_settings() -> Dictionary:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	return {
		"track_depth": _uniform_float(source, "track_depth", 0.05),
		"track_rim": _uniform_float(source, "track_rim", 0.014),
		"rim_extent": _uniform_float(source, "track_rim_extent", 0.4),
		"rim_gate_start": _uniform_float(source, "track_rim_gate_start", 0.30),
		"rim_gate_full": _uniform_float(source, "track_rim_gate_full", 0.58),
		"thin_rim_share": _uniform_float(source, "track_thin_rim_share", 0.55),
		"cavity_start": _uniform_float(source, "footprint_cavity_start", 0.07),
		"cavity_full": _uniform_float(source, "footprint_cavity_full", 0.14),
		"lip_start": _uniform_float(source, "footprint_lip_start", 0.45),
		"lip_full": _uniform_float(source, "footprint_lip_full", 0.82),
		# Missing edge controls deliberately reproduce the rejected value-only lip.
		"lip_edge_start": _uniform_float(source, "footprint_lip_edge_start", -1.0),
		"lip_edge_full": _uniform_float(source, "footprint_lip_edge_full", -0.5),
	}


func _uniform_float(source: String, uniform_name: String, fallback: float) -> float:
	var prefix := "uniform float %s = " % uniform_name
	var start := source.find(prefix)
	if start < 0:
		return fallback
	start += prefix.length()
	var finish := source.find(";", start)
	return source.substr(start, finish - start).to_float()


func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next_function := source.find("\n}\n", start)
	if next_function < 0:
		return source.substr(start)
	return source.substr(start, next_function + 3 - start)


func _occurrences(source: String, needle: String) -> int:
	var count := 0
	var cursor := 0
	while true:
		cursor = source.find(needle, cursor)
		if cursor < 0:
			return count
		count += 1
		cursor += needle.length()
	return count
