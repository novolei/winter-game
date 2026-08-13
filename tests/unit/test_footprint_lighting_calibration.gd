extends TestCase

## The directional cavity pass is deliberately strong enough to survive a tree
## shadow.  These checks make sure that strength is not applied unchanged to the
## two looks at the other end of the game: deep night (where exposure is already
## low) and whiteout (where fog/soft cel light would turn it into a dark decal).
##
## This is a final-light CPU contract.  It consumes the shipped palette and the
## shipped preset band inputs, then reads the calibration defaults from the real
## shader.  Missing controls fall back to the old uncalibrated value of 1.0, so
## the test demonstrably fails on the pre-calibration shader.

const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const LIGHTING_ROOT := "res://data/lighting/"
const SUN_ELEVATION_DEGREES := 21.5


func test_cavity_tone_is_stable_across_signed_off_lighting_extremes() -> void:
	var shader := FileAccess.get_file_as_string(SHADER_PATH)
	var palette: ColorBible = load(PALETTE_PATH)
	assert_not_null(palette, "the production palette is missing")
	if palette == null:
		return

	var pale: LightingPreset = _load_preset(&"pale_day")
	var night: LightingPreset = _load_preset(&"deep_night")
	var whiteout: LightingPreset = _load_preset(&"whiteout")
	if pale == null or night == null or whiteout == null:
		return

	var settings := _settings(shader)
	var pale_contrast := _centre_contrast(pale, 1.0, palette, settings)
	var tree_shadow_contrast := _centre_contrast(pale, 0.0, palette, settings)
	var night_contrast := _centre_contrast(night, 1.0, palette, settings)
	var whiteout_contrast := _centre_contrast(whiteout, 1.0, palette, settings)

	# Pale day is the owner-approved result and remains the reference.  The tree
	# shadow floor is the exact regression ad54b3c fixed; neither may be weakened.
	assert_true(pale_contrast >= 0.090 and pale_contrast <= 0.112,
		"pale-day cavity contrast %.4f moved away from the signed-off look" % pale_contrast)
	assert_true(tree_shadow_contrast >= 0.045 and tree_shadow_contrast <= 0.065,
		"tree-shadow cavity contrast %.4f no longer preserves the approved depth" % tree_shadow_contrast)

	# At 0.42 exposure deep night must keep a readable depression without using
	# the full daylight ink load.  Whiteout is softer again: still visible, but
	# below the contrast at which the mark reads as a dark sticker in pale fog.
	assert_true(night_contrast >= 0.055 and night_contrast <= 0.075,
		"deep-night cavity contrast %.4f is dead-black or has disappeared" % night_contrast)
	assert_true(whiteout_contrast >= 0.025 and whiteout_contrast <= 0.045,
		"whiteout cavity contrast %.4f reads as a high-contrast decal" % whiteout_contrast)


func test_wall_calibration_keeps_tree_shadow_but_restrains_whiteout() -> void:
	var shader := FileAccess.get_file_as_string(SHADER_PATH)
	var pale: LightingPreset = _load_preset(&"pale_day")
	var night: LightingPreset = _load_preset(&"deep_night")
	var whiteout: LightingPreset = _load_preset(&"whiteout")
	if pale == null or night == null or whiteout == null:
		return
	var settings := _settings(shader)
	var pale_scale := _wall_scale(pale, settings)
	var night_scale := _wall_scale(night, settings)
	var whiteout_scale := _wall_scale(whiteout, settings)

	assert_almost_eq(pale_scale, 1.0, 0.0001,
		"pale-day and tree-shadow directional relief must remain unchanged")
	assert_true(night_scale >= 0.68 and night_scale <= 0.90,
		"deep-night wall scale %.3f is outside the restrained readable range" % night_scale)
	assert_true(whiteout_scale >= 0.25 and whiteout_scale <= 0.45,
		"whiteout wall scale %.3f is still too graphic for fog" % whiteout_scale)

	# Calibration must stay in the already-paid arithmetic path.  No footprint
	# texture lookup, draw, upload or preset-name branch is introduced.
	var light_start := shader.find("void light()")
	var light_source := shader.substr(light_start) if light_start >= 0 else ""
	assert_true(light_source.contains("footprint_tone_scale"),
		"the final light pass does not consume the lighting calibration")
	assert_true(light_source.contains("footprint_wall_scale"),
		"the final light pass does not restrain directional walls by lighting look")
	assert_true(light_source.contains("LIGHT_IS_DIRECTIONAL ? 1.0 : 0.0"),
		"Omni/Spot distance attenuation can be mistaken for a directional cast shadow")
	assert_true(light_source.contains("* directional_light"),
		"the shade-wall recovery is not gated to the directional sun")
	assert_false(light_source.contains("dynamic_track_at("),
		"lighting calibration added a per-light footprint texture fetch")
	assert_false(light_source.contains("baked_at("),
		"lighting calibration added a per-light baked-track texture fetch")


func _load_preset(id: StringName) -> LightingPreset:
	var preset: LightingPreset = load(LIGHTING_ROOT + String(id) + ".tres")
	assert_not_null(preset, "missing lighting preset %s" % id)
	return preset


func _settings(source: String) -> Dictionary:
	return {
		"cavity_tone": _uniform_float(source, "footprint_cavity_tone", 0.82),
		"night_start": _uniform_float(source, "footprint_night_threshold_start", 1.0),
		"night_full": _uniform_float(source, "footprint_night_threshold_full", 2.0),
		"night_tone": _uniform_float(source, "footprint_night_tone_scale", 1.0),
		"night_wall": _uniform_float(source, "footprint_night_wall_scale", 1.0),
		"whiteout_start": _uniform_float(source, "footprint_whiteout_softness_start", 1.0),
		"whiteout_full": _uniform_float(source, "footprint_whiteout_softness_full", 2.0),
		"whiteout_tone": _uniform_float(source, "footprint_whiteout_tone_scale", 1.0),
		"whiteout_wall": _uniform_float(source, "footprint_whiteout_wall_scale", 1.0),
	}


func _centre_contrast(preset, attenuation: float, palette: ColorBible, settings: Dictionary) -> float:
	var band := smoothstep(
		preset.cel_band_threshold - preset.cel_band_softness,
		preset.cel_band_threshold + preset.cel_band_softness,
		sin(deg_to_rad(SUN_ELEVATION_DEGREES)) * attenuation
	)
	var tone: float = settings.cavity_tone * _tone_scale(preset, settings)
	var untouched_lit: Color = palette.snow_tones[0]
	var untouched_shade: Color = palette.snow_tones[3]
	var cavity_lit: Color = untouched_lit.lerp(palette.snow_tones[2], tone)
	var cavity_shade: Color = untouched_shade.lerp(palette.snow_tones[4], tone)
	var untouched := untouched_shade.lerp(untouched_lit, band)
	var cavity := cavity_shade.lerp(cavity_lit, band)
	return _luminance(untouched) - _luminance(cavity)


func _tone_scale(preset, settings: Dictionary) -> float:
	var factors := _look_factors(preset, settings)
	var result := lerpf(1.0, settings.night_tone, factors.night)
	return lerpf(result, settings.whiteout_tone, factors.whiteout)


func _wall_scale(preset, settings: Dictionary) -> float:
	var factors := _look_factors(preset, settings)
	var result := lerpf(1.0, settings.night_wall, factors.night)
	return lerpf(result, settings.whiteout_wall, factors.whiteout)


func _look_factors(preset, settings: Dictionary) -> Dictionary:
	var whiteout := smoothstep(
		settings.whiteout_start, settings.whiteout_full, preset.cel_band_softness
	)
	var night := smoothstep(
		settings.night_start, settings.night_full, preset.cel_band_threshold
	) * (1.0 - whiteout)
	return {"night": night, "whiteout": whiteout}


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
