extends TestCase

## Snow comes off a leg by IMPACT, not by the passage of time.
##
## That is the whole claim this file protects, and it is the one that cannot be
## checked in a screenshot: a shed driven by a timer and a shed driven by
## footfalls look identical in a still, and differ completely in play. So the
## tests below walk a body through a drift and out of it, footfall by footfall,
## with no scene, no bus and no clock anywhere in sight -- if any of this needed
## a `delta` to happen, none of it would run at all.
##
## The second claim is the curve. Each step takes the same FRACTION of what is
## left, so the sheds fall away geometrically -- two or three bursts as he clears
## the drift and progressively less after. A linear drain would give the same
## total and the wrong picture: four identical bursts and then nothing.

const LegSnowScript := preload("res://src/entities/leg_snow.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SHADER_PATH := "res://assets/shaders/leg_snow.gdshader"

## LightingDirector's `glow_hdr_threshold`, copied rather than read, for the
## reason tests/unit/test_snowfall.gd gives at greater length: building a
## LightingDirector to ask it costs engine noise that has nothing to do with
## snow, and a test that adds noise to the console is worse than one that names
## its number.
const GLOW_HDR_THRESHOLD := 0.95

## Deep enough to load a leg, and not. Both sides of SnowField.deep_depth_m.
const DEEP := 0.5
const THIN := 0.1


func _fresh() -> Node3D:
	var legs: Node3D = LegSnowScript.new()
	# _ready() by hand: nothing has been added to a tree (briefing trap 1).
	legs._ready()
	# A real field rather than a number, because the gate must be ITS number.
	# Resource-free: nothing here calls build_at(), so no image is generated.
	var field: SnowField = SnowFieldScript.new()
	legs.set_snow_field(field)
	return legs


func _free(legs: Node3D) -> void:
	var field = legs._snow
	# Node, not RefCounted, both of them (briefing section 2.2).
	if field != null:
		field.free()
	legs.free()


func _walk(legs: Node3D, depth: float, steps: int) -> void:
	for index in range(steps):
		legs.step(Vector3(float(index), 0.0, 0.0), depth, Vector2(1.0, 0.0))


# --- the model ----------------------------------------------------------------

## THE ONE THAT MATTERS. Nothing here is given a delta, and everything happens.
func test_the_load_changes_on_footfalls_and_on_nothing_else() -> void:
	var legs := _fresh()
	assert_almost_eq(legs.carried(), 0.0, 0.0001, "a leg starts clean")
	legs.step(Vector3.ZERO, DEEP, Vector2.RIGHT)
	var after_one: float = legs.carried()
	assert_true(after_one > 0.0, "a footfall in deep snow put nothing on the leg")
	# Time passing must do nothing at all. _process is the only per-frame entry
	# point on this node and it is allowed to touch the material, never the load.
	legs._process(10.0)
	legs._process(10.0)
	assert_almost_eq(
		legs.carried(), after_one, 0.0001,
		"ten seconds of process changed the load: something here is on a timer"
	)
	_free(legs)


## Exponential, in the loading direction: the first stride into a drift packs on
## the most and no number of strides packs past full.
func test_wading_loads_the_legs_quickly_and_saturates() -> void:
	var legs := _fresh()
	var previous := 0.0
	var gains: Array[float] = []
	for _step in range(8):
		legs.step(Vector3.ZERO, DEEP, Vector2.RIGHT)
		gains.append(legs.carried() - previous)
		previous = legs.carried()
	assert_true(legs.carried() <= 1.0, "the load ran past a full leg: %f" % legs.carried())
	assert_true(legs.carried() > 0.98, "eight strides through a drift left the legs at %f" % legs.carried())
	for index in range(1, gains.size()):
		assert_true(
			gains[index] < gains[index - 1],
			"stride %d packed on %f against the one before it at %f -- loading must "
				% [index, gains[index], gains[index - 1]]
				+ "take a fraction of what is BARE, so it slows as the leg fills"
		)
	_free(legs)


## Exponential, in the shedding direction, which is the whole look: the first
## steps out of a drift burst and the later ones do not.
func test_each_step_out_sheds_less_than_the_one_before() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 6)
	var loaded: float = legs.carried()
	var sheds: Array[float] = []
	for _step in range(6):
		legs.step(Vector3.ZERO, THIN, Vector2.RIGHT)
		sheds.append(legs.last_shed())
	assert_true(sheds[0] > 0.0, "the first step onto clear ground shed nothing")
	for index in range(1, sheds.size()):
		assert_true(
			sheds[index] < sheds[index - 1],
			"step %d shed %f against %f before it: the bursts must fall away"
				% [index, sheds[index], sheds[index - 1]]
		)
	# Geometric and not merely decreasing -- the ratio is what makes the first two
	# or three bursts visible and the rest a trace.
	var ratio_one: float = sheds[1] / sheds[0]
	var ratio_four: float = sheds[4] / sheds[3]
	assert_almost_eq(ratio_one, ratio_four, 0.01, "the decay is not a constant fraction per step")
	# And it never quite arrives, which is the last trace on the boot.
	assert_true(legs.carried() > 0.0, "six steps took the load to exactly zero; that is a switch, not a decay")
	assert_true(
		legs.carried() < loaded * 0.2,
		"six steps left %f of the %f he came out with -- the legs are not cleaning up"
			% [legs.carried(), loaded]
	)
	_free(legs)


## The gate is SnowField's own number and not a fourth copy of it. Proven by
## moving the field's number and watching the behaviour move with it, which a
## copied constant could not do.
func test_the_depth_that_loads_a_leg_is_the_field_s_own_deep_depth() -> void:
	var legs := _fresh()
	var field = legs._snow
	assert_almost_eq(field.deep_depth_m, 0.42, 0.0001, "the shipped gate moved; this test's numbers assume it")
	# Just under the gate: nothing loads.
	legs.step(Vector3.ZERO, field.deep_depth_m - 0.01, Vector2.RIGHT)
	assert_almost_eq(legs.carried(), 0.0, 0.0001, "snow below the wading depth loaded the legs")
	# Just over it: it does.
	legs.step(Vector3.ZERO, field.deep_depth_m + 0.01, Vector2.RIGHT)
	assert_true(legs.carried() > 0.0, "snow at the wading depth left nothing on the legs")

	# Now move the field's gate and the behaviour must move with it.
	field.deep_depth_m = 0.9
	var before: float = legs.carried()
	legs.step(Vector3.ZERO, 0.5, Vector2.RIGHT)
	assert_true(
		legs.carried() < before,
		"the field says 0.9 m is wading depth and 0.5 m still loaded the legs, so "
			+ "the threshold is a copy rather than the field's own number"
	)
	_free(legs)


## A walker with no snow field is a walker with no snow. Silence is the right
## behaviour here and it is worth pinning, because the alternative -- a fallback
## constant -- would be the fourth threshold this design exists to avoid.
func test_with_no_field_nothing_ever_loads() -> void:
	var legs: Node3D = LegSnowScript.new()
	legs._ready()
	legs.step(Vector3.ZERO, 5.0, Vector2.RIGHT)
	assert_almost_eq(legs.carried(), 0.0, 0.0001, "a leg took on snow from a field that does not exist")
	legs.free()


## Loading and shedding are one rule read in two directions, so a walk back into
## a drift reloads. The owner asked for the loop to be checked.
func test_walking_back_into_a_drift_reloads_the_legs() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 6)
	_walk(legs, THIN, 6)
	var cleaned: float = legs.carried()
	_walk(legs, DEEP, 3)
	assert_true(
		legs.carried() > cleaned + 0.5,
		"three strides back into the drift took the legs from %f to %f" % [cleaned, legs.carried()]
	)
	_free(legs)


## The pure arithmetic, pinned on its own. Both directions are the same rule.
func test_the_two_directions_are_the_same_fraction_rule() -> void:
	assert_almost_eq(LegSnowScript.loaded_after(0.0, 0.5), 0.5, 0.0001)
	assert_almost_eq(LegSnowScript.loaded_after(0.5, 0.5), 0.75, 0.0001)
	assert_almost_eq(LegSnowScript.loaded_after(1.0, 0.5), 1.0, 0.0001, "loading must saturate at a full leg")
	assert_almost_eq(LegSnowScript.shed_by_a_step(1.0, 0.7), 0.3, 0.0001)
	assert_almost_eq(LegSnowScript.shed_by_a_step(0.5, 0.7), 0.15, 0.0001)
	assert_almost_eq(LegSnowScript.shed_by_a_step(0.0, 0.7), 0.0, 0.0001, "a clean leg cannot shed")


# --- the two populations -------------------------------------------------------

## Drag is the ONLY difference between the mist and the clumps, and the wind
## response falls out of it rather than being decided twice. A gust must carry
## the powder and barely move a clump.
func test_the_wind_reaches_the_powder_and_hardly_touches_a_clump() -> void:
	var legs := _fresh()
	var powder: float = LegSnowScript.wind_response(legs.mist_damping)
	var lump: float = LegSnowScript.wind_response(legs.clump_damping)
	assert_true(
		powder > lump * 3.0,
		"powder takes %f of the wind and a clump %f: they are not separated by drag" % [powder, lump]
	)
	assert_true(lump < 0.25, "a clump takes %f of the wind; it is meant to be ballistic" % lump)
	assert_true(powder < 1.0, "no particle may outrun the air it is in")
	assert_almost_eq(LegSnowScript.wind_response(0.0), 0.0, 0.0001, "a dragless particle cannot be blown")
	_free(legs)


## The mist and the clumps are two populations and not one, and the clumps are
## the rare half. The whole point of `burst_count` is that a fractional
## expectation becomes an OCCASIONAL whole clump rather than a permanent dribble.
func test_a_fraction_of_a_clump_is_a_chance_of_one_not_a_fraction_of_one() -> void:
	assert_eq(LegSnowScript.burst_count(0.4, 0.2), 1, "a low roll must produce the clump")
	assert_eq(LegSnowScript.burst_count(0.4, 0.9), 0, "a high roll must produce none")
	assert_eq(LegSnowScript.burst_count(2.4, 0.9), 2, "the whole part must always be emitted")
	assert_eq(LegSnowScript.burst_count(2.4, 0.2), 3)
	assert_eq(LegSnowScript.burst_count(0.0, 0.0), 0, "nothing shed, nothing thrown")
	assert_eq(LegSnowScript.burst_count(-1.0, 0.0), 0)


## The powder floats and the clumps fall, and the emitters have to say so.
func test_the_powder_hangs_and_the_clumps_drop() -> void:
	var legs := _fresh()
	var mist: GPUParticles3D = legs._mist
	var clumps: GPUParticles3D = legs._clumps
	assert_not_null(mist)
	assert_not_null(clumps)
	assert_true(
		absf(legs._clump_material.gravity.y) > absf(legs._mist_material.gravity.y) * 4.0,
		"a clump falls at %f against the powder's %f; they are the same particle"
			% [legs._clump_material.gravity.y, legs._mist_material.gravity.y]
	)
	assert_true(
		legs._mist_material.damping_min > legs._clump_material.damping_min * 4.0,
		"the powder is not draggier than the clumps, so nothing separates them"
	)
	assert_true(mist.lifetime > clumps.lifetime, "the mist must outlive the clumps that land")
	_free(legs)


## WORLD SPACE IS THE EFFECT. A puff knocked off a boot stays where it was
## knocked off and the walker leaves it behind him; in local space every puff
## drags along with the leg and the shed reads as a smear on his shins.
func test_the_shed_is_left_behind_in_world_space() -> void:
	var legs := _fresh()
	assert_false(legs._mist.local_coords, "the powder follows the leg instead of being left behind")
	assert_false(legs._clumps.local_coords, "the clumps follow the leg instead of landing")
	# And the automatic rate is off: every particle arrives on a footfall.
	assert_false(legs._mist.emitting, "the powder emitter runs a rate of its own, so the shed is on a clock")
	assert_false(legs._clumps.emitting, "the clump emitter runs a rate of its own")
	_free(legs)


## The wind hook, in the vocabulary BreathFog and SnowfallLayer already use.
func test_the_wind_hook_moves_both_populations_by_their_own_drag() -> void:
	var legs := _fresh()
	var still_mist: Vector3 = legs._mist_material.gravity
	var still_clump: Vector3 = legs._clump_material.gravity
	legs.set_wind(Vector3(4.0, 0.0, 0.0))
	var blown_mist: Vector3 = legs._mist_material.gravity - still_mist
	var blown_clump: Vector3 = legs._clump_material.gravity - still_clump
	assert_true(blown_mist.x > 0.0, "the wind hook did not reach the powder")
	assert_true(
		blown_mist.x > blown_clump.x * 3.0,
		"the wind moved the powder by %f and a clump by %f" % [blown_mist.x, blown_clump.x]
	)
	assert_eq(legs.wind(), Vector3(4.0, 0.0, 0.0))
	_free(legs)


## Colder air, drier powder, less clinging. Inert at its default, which is the
## point: nothing drives it until Wave 3's weather does.
func test_the_air_temperature_hook_is_inert_until_something_drives_it() -> void:
	var legs := _fresh()
	assert_almost_eq(
		legs.retention_now(), legs.shed_retention, 0.0001,
		"the undriven hook already changed the tuning"
	)
	legs.set_air_chill(1.0)
	assert_true(
		legs.retention_now() < legs.shed_retention,
		"hard cold must shed faster: dry powder does not stick"
	)
	_free(legs)


# --- the look ------------------------------------------------------------------

## Art Bible rule 12 reserves the warm pixels for the fire, the windows, the
## beacon, the truck and the scarf. Snow off a boot is none of those, and it sits
## right next to the scarf.
func test_every_part_of_the_shed_is_a_cool_colour_from_the_palette() -> void:
	var legs := _fresh()
	var bible = load(PALETTE_PATH)
	assert_not_null(bible, "the palette must load for this test to mean anything")
	for entry in [
		["powder", legs._mist.draw_pass_1.material],
		["clump", legs._clumps.draw_pass_1.material],
	]:
		var surface: StandardMaterial3D = entry[1]
		var tone: Color = surface.albedo_color
		assert_false(bible.is_warm(Color(tone.r, tone.g, tone.b)), "%s is a warm tone" % entry[0])
		assert_true(
			tone.b > tone.r + 0.05,
			"%s is %s -- rule 12 keeps the warm pixels, and that is not cool" % [entry[0], tone.to_html(false)]
		)
	var crust: ShaderMaterial = legs.crust_material()
	var snow: Color = crust.get_shader_parameter(&"snow_color")
	assert_true(snow.b > snow.r + 0.05, "the crust on his legs is not a cool white: %s" % snow.to_html(false))
	# Not white either: white is off the palette in the other direction.
	assert_true(snow.r < 1.0 and snow.g < 1.0, "the crust is pure white rather than a palette snow tone")
	_free(legs)


## Bloom belongs to the fire and the windows. A boot-height puff backlit by a
## 21.5-degree sun is the easiest thing in the frame to bloom by accident.
func test_the_shed_cannot_reach_the_bloom_threshold() -> void:
	var legs := _fresh()
	for entry in [
		["powder", legs._mist.draw_pass_1.material],
		["clump", legs._clumps.draw_pass_1.material],
	]:
		var surface: StandardMaterial3D = entry[1]
		var linear: Color = surface.albedo_color.srgb_to_linear()
		var peak: float = maxf(maxf(linear.r, linear.g), linear.b) * surface.albedo_color.a
		assert_true(
			peak < GLOW_HDR_THRESHOLD,
			"%s peaks at %f against a threshold of %f: the shed will glow"
				% [entry[0], peak, GLOW_HDR_THRESHOLD]
		)
		assert_eq(
			surface.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
			"%s blends additively, which is a glow by another name" % entry[0]
		)
		assert_eq(
			surface.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
			"%s is lit, so Art Bible rule 8's banned list has something to switch off" % entry[0]
		)
	_free(legs)


## Briefing trap 7, and the gate tests/art/test_character_lighting.gd holds shut.
## Read off the file rather than off a compiled shader, the same way that gate
## does, so this fails for the same reason and in the same words.
func test_the_crust_shader_refuses_ambient_like_every_other_shader() -> void:
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(text != "", "%s could not be read" % SHADER_PATH)
	assert_true(
		text.contains("ambient_light_disabled"),
		"%s does not declare ambient_light_disabled (briefing trap 7)" % SHADER_PATH
	)
	# And the other half of the same decision: having refused the fill, it has to
	# put the fill back on this one material, or the crust renders far darker than
	# the leg it is drawn on and the whole readout disappears.
	assert_true(
		text.contains("EMISSION = snow_color * fill"),
		"%s refuses ambient without adding the character fill back, so the crust "
			% SHADER_PATH
			+ "will render as a dark patch on the boot rather than as snow"
	)
	# One colour, written once. Trap 7's other half: a colour written into both
	# ALBEDO and a light() reaches the screen squared.
	assert_false(text.contains("void light("), "the crust must not write its colour a second time in light()")


## The crust is driven by the same scalar the shedding drains, and it reaches
## further up the leg the more there is. That rise is what reads as cleaning up
## rather than switching off.
func test_the_crust_line_rises_with_the_load_and_stops_below_the_knee() -> void:
	var legs := _fresh()
	# Measured off the shipped rig: the knee sits at 25.7% of the figure.
	const KNEE := 0.257
	assert_true(legs.boot_line < legs.shin_line, "the crust cannot reach lower when there is more of it")
	assert_true(
		legs.shin_line < KNEE,
		"a full load reaches %f of the figure and the knee is at %f" % [legs.shin_line, KNEE]
	)
	var crust: ShaderMaterial = legs.crust_material()
	assert_almost_eq(crust.get_shader_parameter(&"boot_line"), legs.boot_line, 0.0001)
	assert_almost_eq(crust.get_shader_parameter(&"shin_line"), legs.shin_line, 0.0001)
	assert_almost_eq(
		crust.get_shader_parameter(&"load"), 0.0, 0.0001,
		"a clean leg starts out already wearing snow"
	)
	_free(legs)
