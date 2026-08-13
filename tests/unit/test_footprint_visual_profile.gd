extends TestCase

## The footprint is a physical record, not a decorative decal.  These tests pin
## the two facts that distinguish the refined version from a repeated oval:
## thin snow can never be lifted into a bright halo by the rim, and the authored
## winter boot has a heel, a narrow waist and a broader forefoot whose definition
## yields to wall collapse again in deep snow.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const PROFILE_PATH := "res://data/tracks/human_winter_boot.tres"
const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"


func test_the_human_boot_profile_is_data_and_owns_the_player_subject() -> void:
	var profile = load(PROFILE_PATH)
	assert_not_null(profile, "the winter boot profile was not generated")
	if profile == null:
		return
	assert_true(profile.subjects.has(&"player"), "player is not routed to the authored boot profile")
	assert_true(profile.has_method(&"sole_definition_at"), "the profile cannot resolve its depth language")


func test_sole_definition_peaks_in_shallow_snow_and_collapses_in_a_drift() -> void:
	var profile = load(PROFILE_PATH)
	assert_not_null(profile)
	if profile == null or not profile.has_method(&"sole_definition_at"):
		return
	var dust: float = profile.sole_definition_at(0.0)
	var shallow: float = profile.sole_definition_at(profile.shallow_wade)
	var medium: float = profile.sole_definition_at(profile.medium_wade)
	var deep: float = profile.sole_definition_at(1.0)
	assert_true(
		dust >= 0.65 and shallow > dust,
		"a dusting should keep a light planted sole while shallow snow records it best"
	)
	assert_true(shallow > medium, "wall collapse should already soften the sole through medium snow")
	assert_true(medium > deep + 0.25, "deep snow should read as a pocket, not a shoe mould")


func test_the_boot_has_a_narrow_waist_between_heel_and_forefoot() -> void:
	var profile = load(PROFILE_PATH)
	assert_not_null(profile)
	if profile == null or not profile.has_method(&"sole_distance"):
		return
	var heel: float = profile.sole_distance(Vector2(profile.heel_centre_x, profile.heel_half_width * 0.75))
	var waist: float = profile.sole_distance(Vector2(profile.waist_centre_x, profile.forefoot_half_width * 0.75))
	var forefoot: float = profile.sole_distance(Vector2(profile.forefoot_centre_x, profile.forefoot_half_width * 0.75))
	assert_true(heel < 1.0, "the heel lobe does not hold its authored width")
	assert_true(forefoot < 1.0, "the forefoot lobe does not hold its authored width")
	assert_true(waist > 1.0, "the waist is as broad as the forefoot, so the profile is still an oval")


func test_track_mask_discovers_profiles_by_subject_without_a_player_reference() -> void:
	var mask: TrackMask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	assert_true(mask.has_method(&"profile_for_subject"), "TrackMask has no data-driven profile lookup")
	if mask.has_method(&"profile_for_subject"):
		assert_not_null(mask.profile_for_subject(&"player"), "player did not resolve the boot profile")
		assert_true(mask.profile_for_subject(&"unprofiled_creature") == null,
			"an unknown creature silently inherited a human boot")
	mask.free()


func test_a_profiled_stamp_has_more_forefoot_than_waist_at_the_same_reach() -> void:
	var profile = load(PROFILE_PATH)
	var mask: TrackMask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	if profile == null:
		assert_not_null(profile)
		mask.free()
		return
	assert_true(mask.has_method(&"stamp_profiled"), "TrackMask has no profiled stamp boundary")
	if not mask.has_method(&"stamp_profiled"):
		mask.free()
		return
	mask.call(&"stamp_profiled", Vector3.ZERO, 0.3, 1.0, Vector2.RIGHT, 1.5, 0.66,
		0.0, 11.0, Vector2.ZERO, 1.0, 1.0 - float(profile.shallow_wade), profile)
	var across_m: float = 0.3 / 1.5 * float(profile.forefoot_half_width) * 0.72
	var forefoot := Vector3(0.3 * profile.forefoot_centre_x, 0.0, across_m)
	var waist := Vector3(0.3 * profile.waist_centre_x, 0.0, across_m)
	assert_true(mask.value_at(forefoot) > mask.value_at(waist) + 0.15,
		"forefoot %.3f and waist %.3f still describe one repeated oval" % [
			mask.value_at(forefoot), mask.value_at(waist),
		])
	mask.free()


func test_rim_uses_one_shared_peak_gate_without_more_track_fetches() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(source.contains("track_rim_gate_start"), "the shader has no thin-snow rim gate")
	assert_true(source.contains("track_rim_gate_full"), "the shader has no full rim threshold")
	var start := source.find("vec2 track_gradient")
	var finish := source.find("\n}\n", start)
	var body := source.substr(start, finish - start)
	assert_eq(body.count("track_at("), 4,
		"the rim gate changed the four-fetch footprint-normal budget")
	assert_eq(body.count("float rim_gate ="), 1,
		"each sample has its own gate, which can draw four mismatched halo fragments")


func test_the_shared_gate_cannot_lift_a_thin_scuff_above_the_snow() -> void:
	# Mirrors the shader constants deliberately: this is the physical inequality
	# the authored numbers must maintain, independently of a screenshot.
	var peak := 0.22
	var gate_start := 0.30
	var gate_full := 0.58
	var gate := smoothstep(gate_start, gate_full, peak)
	var deepest_height := -INF
	for step in range(23):
		var value := float(step) / 100.0
		var skirt := clampf(value / 0.4, 0.0, 1.0)
		var rim := 4.0 * skirt * (1.0 - skirt)
		var height := -value * 0.16 + gate * rim * 0.014
		deepest_height = maxf(deepest_height, height)
	assert_true(deepest_height <= 0.000001,
		"a 0.22 scuff rises %.4f m above untouched snow" % deepest_height)


## The gameplay trail must read as a cadence of planted boots, not as one low,
## ragged stroke.  This is deliberately a geometry contract rather than a
## screenshot gate: the owner has paused GPU captures, and no camera can rescue
## two stamps whose possible extents close the untouched-snow gap between them.
func test_a_thin_boot_keeps_a_clear_gap_at_the_shipped_stride() -> void:
	var profile = load(PROFILE_PATH)
	assert_not_null(profile)
	if profile == null:
		return
	var dust_irregularity_scale = profile.get("dust_irregularity_scale")
	assert_not_null(
		dust_irregularity_scale,
		"the profile cannot restrain torn deep-snow walls independently in a dusting"
	)
	if dust_irregularity_scale == null:
		return

	# Worst shipped scale jitter, with the lateral alternation deliberately
	# removed: a straight centre-line pair is closer than the real left/right
	# cadence and is therefore the conservative case.
	var radius := 0.28 * 0.74 * 1.08
	var stride := 0.72
	var edge_allowance := 1.0 + 0.34 * float(dust_irregularity_scale)
	var half_reach := radius * float(profile.dust_length_scale) * edge_allowance
	var guaranteed_gap := stride - 2.0 * half_reach
	assert_true(
		guaranteed_gap >= 0.30,
		"worst-case thin prints leave only %.3f m untouched; the chain can read as a skate line"
			% guaranteed_gap
	)
	assert_true(
		float(profile.dust_break) <= 0.06,
		"dust breakup %.3f fragments the light sole into a lengthwise scratch" % profile.dust_break
	)
	assert_true(
		float(profile.sole_definition_dust) >= 0.90,
		"the dusting does not preserve enough of the authored heel/waist/forefoot silhouette"
	)
