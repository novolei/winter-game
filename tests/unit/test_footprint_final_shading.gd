extends TestCase

## Regression for the owner's actual complaint: at the shipped pale-day camera,
## a footprint must finish as a cavity in the light pass, not merely as a valid
## mask value or a mathematically deep normal field.  The CPU model below uses
## the real weakest production stamp, palette, cel thresholds and shader
## uniforms.  Missing relief controls deliberately collapse to the legacy
## flat-tint response, which makes this test red-capable for that exact defect.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const PROFILE_PATH := "res://data/tracks/human_winter_boot.tres"
const SNOW_PROFILE_PATH := "res://data/snow/valley_profile.tres"
const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"
const PALETTE_PATH := "res://data/palette/color_bible.tres"

const PALE_BAND_THRESHOLD := 0.12
const PALE_BAND_SOFTNESS := 0.07
const SUN_ELEVATION_DEGREES := 21.5
const SAMPLE_STEP_M := 0.02


func test_weakest_thin_boot_finishes_as_a_cavity_not_a_flat_stain() -> void:
	var profile: TrackProfileDefinition = load(PROFILE_PATH)
	var snow_profile = load(SNOW_PROFILE_PATH)
	var palette: ColorBible = load(PALETTE_PATH)
	var shader := FileAccess.get_file_as_string(SHADER_PATH)
	assert_not_null(profile, "the production boot profile is missing")
	assert_not_null(snow_profile, "the production snow profile is missing")
	assert_not_null(palette, "the production palette is missing")
	if profile == null or snow_profile == null or palette == null:
		return

	var mask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	var weakest_strength: float = snow_profile.max_boot_depression_m \
		* 0.70 / snow_profile.footprint_response_depth_m
	mask.call(
		&"stamp_profiled",
		Vector3.ZERO,
		0.28 * 0.74,
		weakest_strength,
		Vector2.RIGHT,
		1.5,
		0.74,
		0.0,
		17.0,
		Vector2.ZERO,
		1.0,
		1.0,
		profile
	)

	var settings := _shader_settings(shader, snow_profile.footprint_response_depth_m)
	var direct_samples: Array[Dictionary] = []
	var reverse_samples: Array[Dictionary] = []
	var shadow_samples: Array[Dictionary] = []
	var shadow_reverse_samples: Array[Dictionary] = []
	var centre := {}
	for yi in range(-18, 19):
		for xi in range(-18, 19):
			var point := Vector2(float(xi), float(yi)) * SAMPLE_STEP_M
			var value := _mask_at(mask, point)
			if value < 0.004:
				continue
			var direct := _final_light_sample(mask, point, 1.0, palette, settings)
			var reverse := _final_light_sample(
				mask, point, 1.0, palette, settings, PI
			)
			var shadow := _final_light_sample(mask, point, 0.0, palette, settings)
			var shadow_reverse := _final_light_sample(
				mask, point, 0.0, palette, settings, PI
			)
			direct_samples.append(direct)
			reverse_samples.append(reverse)
			shadow_samples.append(shadow)
			shadow_reverse_samples.append(shadow_reverse)
			if centre.is_empty() or value > float(centre.value):
				centre = shadow

	var untouched_shadow := _final_light_sample(
		mask, Vector2(0.48, 0.48), 0.0, palette, settings
	)
	assert_false(centre.is_empty(), "the weakest production boot produced no shaded samples")
	if centre.is_empty():
		mask.free()
		return

	var shadow_cavity_contrast: float = untouched_shadow.luma - float(centre.luma)
	assert_almost_eq(
		untouched_shadow.luma,
		_luminance(palette.snow_tones[3]),
		0.000001,
		"the relief response changed snow outside a dynamic footprint"
	)
	var brightest_lip := -INF
	for sample in shadow_samples:
		var sample_value: float = sample.value
		if sample_value >= 0.025 and sample_value <= float(centre.value) * 0.58:
			brightest_lip = maxf(brightest_lip, float(sample.luma))
	var lip_separation: float = brightest_lip - float(centre.luma)

	var darkest_wall := INF
	var brightest_wall := -INF
	var darkest_shadow_wall := INF
	var brightest_shadow_wall := -INF
	for sample in direct_samples:
		var sample_value: float = sample.value
		if sample_value < float(centre.value) * 0.12 \
				or sample_value > float(centre.value) * 0.82:
			continue
		darkest_wall = minf(darkest_wall, float(sample.luma))
		brightest_wall = maxf(brightest_wall, float(sample.luma))
	var directional_wall_separation: float = brightest_wall - darkest_wall
	for sample in shadow_samples:
		var sample_value: float = sample.value
		if sample_value < float(centre.value) * 0.12 \
				or sample_value > float(centre.value) * 0.82:
			continue
		darkest_shadow_wall = minf(darkest_shadow_wall, float(sample.luma))
		brightest_shadow_wall = maxf(brightest_shadow_wall, float(sample.luma))
	var shadow_wall_separation: float = brightest_shadow_wall - darkest_shadow_wall
	var reversal_pairs := 0
	var shadow_reversal_pairs := 0
	for index in direct_samples.size():
		var forward_luma: float = direct_samples[index].luma
		var reverse_luma: float = reverse_samples[index].luma
		if absf(forward_luma - reverse_luma) >= 0.030:
			reversal_pairs += 1
		var shadow_forward_luma: float = shadow_samples[index].luma
		var shadow_reverse_luma: float = shadow_reverse_samples[index].luma
		if absf(shadow_forward_luma - shadow_reverse_luma) >= 0.020:
			shadow_reversal_pairs += 1

	# These assert the final palette light output, not millimetres in a mask.
	# A tree shadow removes the direct-light normal cue, so the centre still needs
	# enough pressed-floor tone to stay distinct from untouched shaded snow.
	assert_true(shadow_cavity_contrast >= 0.045,
		"tree-shadow cavity contrast is %.4f; the print is still a flat pale stain"
			% shadow_cavity_contrast)
	assert_true(lip_separation >= 0.032,
		"the displaced-snow lip separates from the cavity by only %.4f"
			% lip_separation)
	assert_true(brightest_lip <= untouched_shadow.luma + 0.008,
		"the lip is a bright halo (%.4f above untouched snow)"
			% (brightest_lip - untouched_shadow.luma))
	assert_true(directional_wall_separation >= 0.055,
		"pale-day opposing walls separate by only %.4f"
			% directional_wall_separation)
	assert_true(shadow_wall_separation >= 0.025,
		"tree-shadow opposing walls separate by only %.4f; this still reads as a sticker"
			% shadow_wall_separation)
	assert_true(shadow_reversal_pairs >= 8,
		"tree-shadow light reversal changed only %d samples; the shade walls are not directional"
			% shadow_reversal_pairs)
	assert_true(reversal_pairs >= 8,
		"a 180-degree light reversal changed only %d cavity samples; the walls are not directional"
			% reversal_pairs)

	# Lock the math above to the shipping light pass.  These are semantic seams,
	# not formatting checks: deleting any one returns the model to the legacy
	# no-floor-depth/no-wall-amplification response and makes the visual assertions
	# above red through the parsed defaults.
	assert_true(shader.contains("v_track_cavity = smoothstep("),
		"snow_ground no longer derives a cavity core from the sampled footprint")
	assert_true(shader.contains(
		"footprint_cavity_start, footprint_cavity_full, centre_track"
	), "baked roads/furrows were routed through dynamic footprint cavity relief")
	assert_true(shader.contains("detail_delta * v_track_wall_gain"),
		"snow_ground no longer separates the two directional cavity walls")
	assert_true(shader.contains("detail_delta * footprint_shadow_wall_tone"),
		"snow_ground no longer preserves directional walls inside tree shadow")
	assert_true(shader.contains("cavity * footprint_cavity_tone"),
		"snow_ground no longer gives the pressed interior its palette depth")
	assert_true(shader.contains("lip * footprint_lip_tone_release"),
		"snow_ground no longer releases the snow lip back toward surface snow")
	var light_start := shader.find("void light()")
	var light_source := shader.substr(light_start) if light_start >= 0 else ""
	assert_false(light_source.contains("dynamic_track_at("),
		"the light loop added a per-light footprint texture fetch")
	assert_false(light_source.contains("ground_gradient("),
		"the light loop recomputes the broad normal per light")

	# Mutation guard: if the shadow-wall term is disabled, the same production
	# mark must return to the rejected flat shade response. This proves the test
	# is observing the new term rather than merely the darker cavity floor.
	var disabled_settings: Dictionary = settings.duplicate(true)
	disabled_settings.shadow_wall_tone = 0.0
	var disabled_reversal_delta := 0.0
	for yi in range(-18, 19):
		for xi in range(-18, 19):
			var point := Vector2(float(xi), float(yi)) * SAMPLE_STEP_M
			var value := _mask_at(mask, point)
			if value < float(centre.value) * 0.12 \
					or value > float(centre.value) * 0.82:
				continue
			var sample_forward := _final_light_sample(
				mask, point, 0.0, palette, disabled_settings
			)
			var sample_reverse := _final_light_sample(
				mask, point, 0.0, palette, disabled_settings, PI
			)
			disabled_reversal_delta = maxf(
				disabled_reversal_delta,
				absf(float(sample_forward.luma) - float(sample_reverse.luma))
			)
	assert_true(disabled_reversal_delta <= 0.000001,
		"disabling shadow-wall relief still leaves %.6f directional response"
			% disabled_reversal_delta)

	mask.free()


func _shader_settings(source: String, response_depth_m: float) -> Dictionary:
	return {
		"track_depth": response_depth_m,
		"track_rim": _uniform_float(source, "track_rim", 0.014),
		"track_rim_extent": _uniform_float(source, "track_rim_extent", 0.4),
		"track_rim_gate_start": _uniform_float(source, "track_rim_gate_start", 0.30),
		"track_rim_gate_full": _uniform_float(source, "track_rim_gate_full", 0.58),
		"track_thin_rim_share": _uniform_float(source, "track_thin_rim_share", 0.55),
		"track_tint": _uniform_float(source, "track_tint", 0.5),
		"track_normal_epsilon": _uniform_float(source, "track_normal_epsilon", 0.06),
		# Zero/one are the legacy response.  The initial RED run therefore models
		# the actual shader before the relief controls exist.
		"cavity_start": _uniform_float(source, "footprint_cavity_start", 1.0),
		"cavity_full": _uniform_float(source, "footprint_cavity_full", 2.0),
		"cavity_tone": _uniform_float(source, "footprint_cavity_tone", 0.0),
		"wall_gain": _uniform_float(source, "footprint_wall_gain", 1.0),
		"shadow_wall_tone": _uniform_float(source, "footprint_shadow_wall_tone", 0.0),
		"lip_start": _uniform_float(source, "footprint_lip_start", 2.0),
		"lip_full": _uniform_float(source, "footprint_lip_full", 3.0),
		"lip_tone_release": _uniform_float(source, "footprint_lip_tone_release", 0.0),
	}


func _final_light_sample(
	mask,
	point: Vector2,
	attenuation: float,
	palette: ColorBible,
	settings: Dictionary,
	azimuth_radians := 0.0
) -> Dictionary:
	var value := _mask_at(mask, point)
	var epsilon: float = settings.track_normal_epsilon
	var xr := _mask_at(mask, point + Vector2(epsilon, 0.0))
	var xl := _mask_at(mask, point - Vector2(epsilon, 0.0))
	var zr := _mask_at(mask, point + Vector2(0.0, epsilon))
	var zl := _mask_at(mask, point - Vector2(0.0, epsilon))
	var local_peak := maxf(maxf(xr, xl), maxf(zr, zl))
	var rim_gate := lerpf(
		settings.track_thin_rim_share,
		1.0,
		smoothstep(settings.track_rim_gate_start, settings.track_rim_gate_full, local_peak)
	)
	var gradient := Vector2(
		_track_height(xr, rim_gate, settings) - _track_height(xl, rim_gate, settings),
		_track_height(zr, rim_gate, settings) - _track_height(zl, rim_gate, settings)
	) / (2.0 * epsilon)
	var normal := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
	var elevation := deg_to_rad(SUN_ELEVATION_DEGREES)
	var light := Vector3(
		cos(elevation) * cos(azimuth_radians),
		sin(elevation),
		cos(elevation) * sin(azimuth_radians)
	).normalized()
	var lambert := clampf(normal.dot(light), 0.0, 1.0)
	var ground_lambert := light.y

	var cavity := smoothstep(settings.cavity_start, settings.cavity_full, value)
	var presence := smoothstep(0.01, maxf(settings.cavity_start, 0.011), value)
	var wall_gain := lerpf(1.0, settings.wall_gain, maxf(cavity, presence))
	var detail_delta := lambert - ground_lambert
	var shaped_lambert := clampf(ground_lambert + detail_delta * wall_gain, 0.0, 1.0)
	var shaded := shaped_lambert * attenuation
	var band := smoothstep(
		PALE_BAND_THRESHOLD - PALE_BAND_SOFTNESS,
		PALE_BAND_THRESHOLD + PALE_BAND_SOFTNESS,
		shaded
	)

	var skirt := clampf(value / settings.track_rim_extent, 0.0, 1.0)
	var rim := 4.0 * skirt * (1.0 - skirt)
	var lip := smoothstep(settings.lip_start, settings.lip_full, rim) * (1.0 - cavity)
	var tone := maxf(value * settings.track_tint, cavity * settings.cavity_tone)
	tone *= 1.0 - lip * settings.lip_tone_release
	var cast_shadow := 1.0 - clampf(attenuation, 0.0, 1.0)
	var shadow_wall: float = detail_delta * settings.shadow_wall_tone \
		* wall_gain * cast_shadow
	tone -= shadow_wall * maxf(cavity, lip)
	tone = clampf(tone, 0.0, 1.0)
	var lit: Color = palette.snow_tones[0].lerp(palette.snow_tones[2], tone)
	var shade: Color = palette.snow_tones[3].lerp(palette.snow_tones[4], tone)
	var output := shade.lerp(lit, band)
	return {"value": value, "luma": _luminance(output)}


func _track_height(value: float, rim_gate: float, settings: Dictionary) -> float:
	var skirt := clampf(value / settings.track_rim_extent, 0.0, 1.0)
	var rim := 4.0 * skirt * (1.0 - skirt)
	return -value * settings.track_depth + rim_gate * rim * settings.track_rim


func _mask_at(mask, point: Vector2) -> float:
	return mask.value_at(Vector3(point.x, 0.0, point.y))


func _uniform_float(source: String, uniform_name: String, fallback: float) -> float:
	var prefix := "uniform float %s = " % uniform_name
	var start := source.find(prefix)
	if start < 0:
		return fallback
	start += prefix.length()
	var finish := source.find(";", start)
	return source.substr(start, finish - start).to_float()


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
