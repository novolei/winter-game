extends TestCase

## The footprint is a physical record, not a decorative decal.  These tests pin
## the two facts that distinguish the refined version from a repeated oval:
## thin snow can never be lifted into a bright halo by the rim, and the authored
## winter boot has a heel, a narrow waist and a broader forefoot whose definition
## yields to wall collapse again in deep snow.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const PROFILE_PATH := "res://data/tracks/human_winter_boot.tres"
const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"


class ThinCoverSnowStub extends Node:
	var max_depth_m := 0.6
	var allowed_depression_m := 0.0
	var response_depth_m := 0.16

	func structural_depth_at(_world: Vector3) -> float:
		return 0.0

	func wade_factor(_world: Vector3) -> float:
		return 0.0

	func imprint_factor_at(_world: Vector3) -> float:
		return 1.0

	func allowed_boot_depression_at(_world: Vector3) -> float:
		return allowed_depression_m

	func footprint_response_depth_m() -> float:
		return response_depth_m

	func visible_depth_at(_world: Vector3) -> float:
		return 0.08

	func surface_gradient_at(_world: Vector3) -> Vector2:
		return Vector2.ZERO


class FootprintCaptureBus extends Node:
	var payload: Dictionary = {}

	func emit_event(event_name: StringName, data: Variant) -> void:
		if event_name == &"track.footprint" and data is Dictionary:
			payload = (data as Dictionary).duplicate(true)

	func unsubscribe(_event_name: StringName, _callback: Callable) -> void:
		pass


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
	assert_true(source.contains("track_thin_rim_share"),
		"the shader still turns the displaced thin-snow shoulder completely off")
	var start := source.find("vec2 track_gradient")
	var finish := source.find("\n}\n", start)
	var body := source.substr(start, finish - start)
	assert_eq(body.count("track_at("), 4,
		"the rim gate changed the four-fetch footprint-normal budget")
	assert_eq(body.count("float rim_gate ="), 1,
		"each sample has its own gate, which can draw four mismatched halo fragments")


func test_the_shared_gate_keeps_a_restrained_thin_rim_below_the_snow() -> void:
	# Mirrors the shader constants deliberately: this is the physical inequality
	# the authored numbers must maintain, independently of a screenshot. A
	# dusting still displaces a little snow at the shoulder: turning its rim all
	# the way off removes the only highlight/shadow pair that makes the depression
	# read as volume at the game camera.
	var peak := 0.22
	var gate_start := 0.30
	var gate_full := 0.58
	var thin_rim_share := 0.55
	var gate := lerpf(thin_rim_share, 1.0, smoothstep(gate_start, gate_full, peak))
	var deepest_height := -INF
	for step in range(23):
		var value := float(step) / 100.0
		var skirt := clampf(value / 0.4, 0.0, 1.0)
		var rim := 4.0 * skirt * (1.0 - skirt)
		var height := -value * 0.16 + gate * rim * 0.014
		deepest_height = maxf(deepest_height, height)
	assert_true(deepest_height <= 0.000001,
		"a 0.22 scuff rises %.4f m above untouched snow" % deepest_height)
	assert_true(gate > 0.0 and gate < 1.0,
		"the thin rim is either completely disabled or restored as a full halo")


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


## The shipped caller floors a dusting at strength 0.22 and takes at most 30%
## away through bite jitter. The old test exercised only the 1.0 bite endpoint,
## so the weakest production step could lose another 30% and still pass. Both
## endpoints have to remain a physical boot-shaped depression, not two pale dots.
func test_every_production_bite_leaves_a_readable_thin_boot_depression() -> void:
	var profile = load(PROFILE_PATH)
	assert_not_null(profile)
	if profile == null:
		return

	var weakest := _thin_boot_samples(profile, 0.22 * (1.0 - 0.30))
	var ordinary := _thin_boot_samples(profile, 0.22)
	for sample in [weakest, ordinary]:
		assert_true(sample.heel >= 0.13,
			"heel peak %.4f is a flat tonal dot, not a depression" % sample.heel)
		assert_true(sample.forefoot >= 0.15 and sample.forefoot <= 0.23,
			"forefoot peak %.4f left the readable thin-snow response" % sample.forefoot)
		assert_true(sample.waist >= sample.heel * 0.55,
			"waist %.4f disconnects heel %.4f from forefoot %.4f"
				% [sample.waist, sample.heel, sample.forefoot])

	# The 0.16 m terrain response makes even the weakest planted forefoot about
	# 25 mm deep. More importantly, its 6 cm reconstructed-normal sample crosses
	# the pale-day cel band's fully-lit boundary instead of remaining a flat tint.
	assert_true(weakest.forefoot * 0.16 >= 0.024,
		"weakest production bite is only %.1f mm deep" % (weakest.forefoot * 160.0))
	var tilt_degrees := rad_to_deg(atan(weakest.forefoot * 0.16 / (2.0 * 0.06)))
	var readable_boundary := 21.5 - rad_to_deg(asin(0.12 + 0.07))
	assert_true(tilt_degrees >= readable_boundary + 0.5,
		"weakest bite tilts %.2f degrees, only %.2f past the cel boundary"
			% [tilt_degrees, tilt_degrees - readable_boundary])


func test_mature_veneer_reaches_the_final_surface_as_a_planted_boot_cavity() -> void:
	# This is the shipping chain, not a profile sampled in isolation: the player
	# turns the snow facts into an event, TrackMask routes the player subject and
	# writes its real raster, then the same height equation as snow_ground turns
	# that raster into the final normal-derived cavity.
	var tree := Engine.get_main_loop() as SceneTree
	var player: CharacterBody3D = preload(
		"res://src/entities/player/player_controller.gd"
	).new()
	var snow := ThinCoverSnowStub.new()
	var bus := FootprintCaptureBus.new()
	var snow_profile = load("res://data/snow/valley_profile.tres")
	assert_not_null(snow_profile, "the production snow budget is missing")
	if snow_profile == null:
		player.free()
		snow.free()
		bus.free()
		return
	# Exercise the exact weakest production bite without asking a random seed to
	# approximate randf() == 1. The player still builds the shipping payload; we
	# feed it the mathematically lowest allowed depression and turn off only the
	# second, now-already-accounted-for random multiplier.
	var production_bite_jitter: float = player.get("print_bite_jitter")
	snow.allowed_depression_m = snow_profile.max_boot_depression_m \
		* (1.0 - production_bite_jitter)
	snow.response_depth_m = snow_profile.footprint_response_depth_m
	player.set("print_bite_jitter", 0.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(player)
	player.set("_snow", snow)
	player.set("_bus", bus)
	player.set("_facing", Vector3.RIGHT)
	seed(19770813)
	player.call("_place_print")
	var payload := bus.payload
	assert_false(payload.is_empty(), "the production player emitted no footprint")
	if payload.is_empty():
		tree.root.remove_child(player)
		player.free()
		snow.free()
		bus.free()
		return

	var profile: TrackProfileDefinition = load(PROFILE_PATH)
	var mask: TrackMask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	mask.call("_on_footprint", payload)
	var metrics := _production_mark_metrics(mask, payload)
	var scuff: float = payload.scuff
	assert_true(scuff >= 0.99,
		"compressible cover selected deep-snow morphology (scuff %.3f)" % scuff)
	assert_true(profile.sole_definition_at(1.0 - scuff) >= 0.90,
		"thin cover routed to a low-definition pocket instead of the planted sole")
	assert_true(metrics.along_reach <= 0.34 and metrics.across_reach >= 0.20,
		"the final %.3f x %.3f m mark is a lengthwise scratch, not a compact boot"
			% [metrics.along_reach, metrics.across_reach])

	var shader := FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(shader.contains("return -t * track_depth + rim_gate * rim * track_rim;"),
		"the test's height equation no longer matches snow_ground.gdshader")
	# TerrainRenderer overwrites the shader's fallback track_depth from this same
	# SnowField contract before drawing; using the fallback 0.05 here would model
	# a shader resource in isolation, not the shipping material.
	var renderer_source := FileAccess.get_file_as_string(
		"res://src/rendering/terrain_renderer.gd"
	)
	assert_true(renderer_source.contains("response_depth = float(_snow.call"),
		"TerrainRenderer no longer binds SnowField's footprint response")
	var track_depth: float = snow.footprint_response_depth_m()
	var track_rim := _shader_uniform_float(shader, "track_rim")
	var rim_extent := _shader_uniform_float(shader, "track_rim_extent")
	var gate_start := _shader_uniform_float(shader, "track_rim_gate_start")
	var gate_full := _shader_uniform_float(shader, "track_rim_gate_full")
	var thin_rim_share := _shader_uniform_float(shader, "track_thin_rim_share")
	var local_peak: float = metrics.peak
	var rim_gate := lerpf(
		thin_rim_share, 1.0, smoothstep(gate_start, gate_full, local_peak)
	)
	var final_cavity_m := -_shipping_track_height(
		local_peak, rim_gate, track_depth, rim_extent, track_rim
	)
	assert_true(final_cavity_m >= 0.022 and final_cavity_m <= 0.030,
		"the final surface cavity is %.1f mm; the mask value alone is not a depression"
			% (final_cavity_m * 1000.0))
	var highest := -INF
	for step in range(101):
		var value := local_peak * float(step) / 100.0
		highest = maxf(highest, _shipping_track_height(
			value, rim_gate, track_depth, rim_extent, track_rim
		))
	assert_true(highest <= 0.000001,
		"the thin-print shoulder rises %.2f mm above untouched snow"
			% (highest * 1000.0))
	var pushed_snow_shoulder_m := rim_gate \
		* (4.0 * clampf(local_peak / rim_extent, 0.0, 1.0) \
		* (1.0 - clampf(local_peak / rim_extent, 0.0, 1.0))) * track_rim
	assert_true(pushed_snow_shoulder_m >= 0.005,
		"the weakest print lost its readable pushed-snow shoulder (%.1f mm)"
			% (pushed_snow_shoulder_m * 1000.0))
	assert_true(snow_profile.max_boot_depression_m <= 0.060001,
		"the boot budget exceeds 8 cm cover minus the 2 cm residual layer")

	mask.free()
	tree.root.remove_child(player)
	player.free()
	snow.free()
	bus.free()


func _production_mark_metrics(mask: TrackMask, payload: Dictionary) -> Dictionary:
	var centre: Vector3 = payload.position
	var heading: Vector2 = payload.forward.normalized()
	var across := Vector2(-heading.y, heading.x)
	var min_along := INF
	var max_along := -INF
	var min_across := INF
	var max_across := -INF
	var peak := 0.0
	for yi in range(-25, 26):
		for xi in range(-25, 26):
			var along_m := float(xi) * 0.02
			var across_m := float(yi) * 0.02
			var xz := Vector2(centre.x, centre.z) \
				+ heading * along_m + across * across_m
			var value := mask.value_at(Vector3(xz.x, 0.0, xz.y))
			peak = maxf(peak, value)
			if value >= 0.025:
				min_along = minf(min_along, along_m)
				max_along = maxf(max_along, along_m)
				min_across = minf(min_across, across_m)
				max_across = maxf(max_across, across_m)
	return {
		"along_reach": max_along - min_along,
		"across_reach": max_across - min_across,
		"peak": peak,
	}


func _shader_uniform_float(source: String, uniform_name: String) -> float:
	var prefix := "uniform float %s = " % uniform_name
	var start := source.find(prefix)
	assert_true(start >= 0, "snow shader lost uniform %s" % uniform_name)
	if start < 0:
		return 0.0
	start += prefix.length()
	var finish := source.find(";", start)
	return source.substr(start, finish - start).to_float()


func _shipping_track_height(
	value: float, rim_gate: float, track_depth: float, rim_extent: float, track_rim: float
) -> float:
	var skirt := clampf(value / rim_extent, 0.0, 1.0)
	var rim := 4.0 * skirt * (1.0 - skirt)
	return -value * track_depth + rim_gate * rim * track_rim


func _thin_boot_samples(
	profile: TrackProfileDefinition, strength: float, scuff := 1.0
) -> Dictionary:
	var mask: TrackMask = TrackMaskScript.new()
	mask.build_at(Vector3.ZERO)
	var radius := 0.28 * 0.74
	mask.call(&"stamp_profiled", Vector3.ZERO, radius, strength, Vector2.RIGHT, 1.5,
		0.74, 0.0, 17.0, Vector2.ZERO, 1.0, scuff, profile)
	var along_scale: float = radius * float(profile.dust_length_scale)
	var result := {
		"heel": mask.value_at(Vector3(along_scale * float(profile.heel_centre_x), 0.0, 0.0)),
		"waist": mask.value_at(Vector3(along_scale * float(profile.waist_centre_x), 0.0, 0.0)),
		"forefoot": mask.value_at(Vector3(along_scale * float(profile.forefoot_centre_x), 0.0, 0.0)),
	}
	mask.free()
	return result


func test_dust_lobe_language_fades_out_completely_in_deep_snow() -> void:
	var source := FileAccess.get_file_as_string("res://src/systems/track_mask.gd")
	assert_true(source.contains(
		"var dust_separation := scrape * (1.0 - dust_waist_influence)"
	), "dust lobe separation is not gated by the continuous thin-snow fact")
	assert_true(source.contains("weight = lerpf(weight, dust_weight, scrape)"),
		"dust pressure weights can leak into the approved deep footprint")
	assert_true(source.contains(
		"var dust_readability := lerpf(1.0, dust_readability_gain, scrape)"
	), "dust readability is not gated to the continuous thin-snow endpoint")


func test_dust_readability_gain_leaves_a_deep_stamp_identical() -> void:
	var shipped: TrackProfileDefinition = load(PROFILE_PATH)
	assert_not_null(shipped)
	if shipped == null:
		return
	var neutral: TrackProfileDefinition = shipped.duplicate(true)
	neutral.dust_readability_gain = 1.0
	var shipped_mask: TrackMask = TrackMaskScript.new()
	var neutral_mask: TrackMask = TrackMaskScript.new()
	shipped_mask.build_at(Vector3.ZERO)
	neutral_mask.build_at(Vector3.ZERO)
	shipped_mask.call(
		&"stamp_profiled", Vector3.ZERO, 0.28, 1.0, Vector2.RIGHT, 1.5,
		0.66, 0.34, 31.0, Vector2.ZERO, 1.0, 0.0, shipped
	)
	neutral_mask.call(
		&"stamp_profiled", Vector3.ZERO, 0.28, 1.0, Vector2.RIGHT, 1.5,
		0.66, 0.34, 31.0, Vector2.ZERO, 1.0, 0.0, neutral
	)
	for ix in range(-5, 6):
		for iz in range(-5, 6):
			var point := Vector3(float(ix) * 0.04, 0.0, float(iz) * 0.04)
			assert_almost_eq(
				shipped_mask.value_at(point), neutral_mask.value_at(point), 0.000001,
				"dust readability altered deep-snow sample (%d, %d)" % [ix, iz]
			)
	shipped_mask.free()
	neutral_mask.free()
