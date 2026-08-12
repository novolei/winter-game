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
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SHADER_PATH := "res://assets/shaders/leg_snow.gdshader"

## LightingDirector's `glow_hdr_threshold`, copied rather than read, for the
## reason tests/unit/test_snowfall.gd gives at greater length: building a
## LightingDirector to ask it costs engine noise that has nothing to do with
## snow, and a test that adds noise to the console is worse than one that names
## its number.
const GLOW_HDR_THRESHOLD := 0.95

## SnowfallLayer.min_flake_pixels, copied for exactly the reason above: building
## a SnowfallLayer to read one number costs a GPUParticles3D and its noise, and
## the figure itself is derived at length in that file's header. Under about this
## a particle stops being an object and becomes a shimmering sub-pixel sample.
const MIN_GRAIN_PIXELS := 2.5

## The frame height the shipped captures and the judged frames are taken at.
## Trap 10: this is `Window.size`, the number that describes the PICTURE, not the
## canvas rect or the render target.
const FRAME_PIXELS := 800.0

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

## Drag is the ONLY difference between the mist and the grains, and the wind
## response falls out of it rather than being decided twice. A gust must carry
## the mist and barely move a grain.
func test_the_wind_reaches_the_mist_and_hardly_touches_a_grain() -> void:
	var legs := _fresh()
	var powder: float = LegSnowScript.wind_response(legs.mist_damping)
	var lump: float = LegSnowScript.wind_response(legs.grain_damping)
	assert_true(
		powder > lump * 3.0,
		"mist takes %f of the wind and a grain %f: they are not separated by drag" % [powder, lump]
	)
	assert_true(lump < 0.25, "a grain takes %f of the wind; it is meant to be ballistic" % lump)
	assert_true(powder < 1.0, "no particle may outrun the air it is in")
	assert_almost_eq(LegSnowScript.wind_response(0.0), 0.0, 0.0001, "a dragless particle cannot be blown")
	_free(legs)


## THE MIX. Snow packed onto a leg by wading is compacted crystal, and a footfall
## breaks it into grains -- only the finest fraction of it ever goes airborne. So
## the grains lead and the mist accompanies, and the first version of this had it
## the other way round, which read as steam off a boot.
func test_the_shed_is_mostly_grains_and_only_a_little_mist() -> void:
	var legs := _fresh()
	assert_true(
		legs.grains_per_shed > legs.mist_per_shed * 2.5,
		"a full shed throws %f grains against %f puffs of mist: mist in the majority "
			% [legs.grains_per_shed, legs.mist_per_shed]
			+ "reads as steam off a boot rather than as snow breaking off it"
	)
	# And the mist is not deleted. It softens the leading edge of the burst and it
	# is the part that catches a low sun; a shed of bare dots has nothing behind it.
	assert_true(legs.mist_per_shed > 0.0, "the mist fraction was removed rather than reduced")
	_free(legs)


## A fractional expectation is a CHANCE of a particle, which is what keeps the
## tail of a shed honest: by the twelfth stride out of a drift both populations
## expect well under one, and rounding would give either one every step or none
## ever.
func test_a_fraction_of_a_particle_is_a_chance_of_one_not_a_fraction_of_one() -> void:
	assert_eq(LegSnowScript.burst_count(0.4, 0.2), 1, "a low roll must produce the particle")
	assert_eq(LegSnowScript.burst_count(0.4, 0.9), 0, "a high roll must produce none")
	assert_eq(LegSnowScript.burst_count(2.4, 0.9), 2, "the whole part must always be emitted")
	assert_eq(LegSnowScript.burst_count(2.4, 0.2), 3)
	assert_eq(LegSnowScript.burst_count(0.0, 0.0), 0, "nothing shed, nothing thrown")
	assert_eq(LegSnowScript.burst_count(-1.0, 0.0), 0)


## The mist floats and the grains fall, and the emitters have to say so.
func test_the_mist_hangs_and_the_grains_drop() -> void:
	var legs := _fresh()
	var mist: GPUParticles3D = legs._mist
	var grains: GPUParticles3D = legs._grains
	assert_not_null(mist)
	assert_not_null(grains)
	assert_true(
		absf(legs._grain_material.gravity.y) > absf(legs._mist_material.gravity.y) * 4.0,
		"a grain falls at %f against the mist's %f; they are the same particle"
			% [legs._grain_material.gravity.y, legs._mist_material.gravity.y]
	)
	assert_true(
		legs._mist_material.damping_min > legs._grain_material.damping_min * 4.0,
		"the mist is not draggier than the grains, so nothing separates them"
	)
	assert_true(mist.lifetime > grains.lifetime, "the mist must outlive the grains that land")
	_free(legs)


## THEY ARE THROWN, NOT RELEASED, and that trajectory is most of what separates
## grit off a boot from fog out of one. Every grain leaves with real speed, over
## a wide cone about the way he is walking -- so no two of a hundred go the same
## way, and none of them merely drops.
func test_the_grains_spray_rather_than_drift() -> void:
	var legs := _fresh()
	var heading := Vector2(1.0, 0.0)
	var slowest := INF
	var widest := 0.0
	var lowest_rise := INF
	for _index in range(200):
		var velocity: Vector3 = legs._grain_velocity(heading)
		var flat := Vector2(velocity.x, velocity.z)
		slowest = minf(slowest, flat.length())
		widest = maxf(widest, absf(flat.angle_to(heading)))
		lowest_rise = minf(lowest_rise, velocity.y)
	assert_true(
		slowest > 0.5,
		"the slowest of two hundred grains left the boot at %f m/s: an impact throws "
			% slowest
			+ "what it breaks off, and anything this slow is being released rather than thrown"
	)
	assert_true(
		widest > deg_to_rad(45.0),
		"two hundred grains spread only %f degrees either side of the walk: a narrow "
			% rad_to_deg(widest)
			+ "cone reads as a jet rather than as a crust breaking"
	)
	# EVERY GRAIN LEAVES UPWARD, and that is a correction rather than a stylistic
	# choice. The ground it has to land on is the snow SURFACE, which is drawn
	# above the walker's own origin -- so a grain thrown level or downward is under
	# the mesh within a frame or two and is never seen at all. Ten a step were
	# being emitted, flying correctly and rendering nothing until gravity was
	# switched off to find them. The arc is what makes them visible; gravity below
	# is what brings them back.
	assert_true(
		lowest_rise > 0.0,
		"the flattest of two hundred grains left at %f m/s vertically: a grain thrown "
			% lowest_rise
			+ "level is under the snow surface before it has been drawn twice"
	)
	assert_true(
		legs._grain_material.gravity.y < -3.0,
		"a grain falls at only %f: it has to come back down, or it is not a grain"
			% legs._grain_material.gravity.y
	)
	_free(legs)


## WORLD SPACE IS THE EFFECT. A grain knocked off a boot stays where it was
## knocked off and the walker leaves it behind him; in local space every particle
## drags along with the leg and the shed reads as a smear on his shins.
func test_the_shed_is_left_behind_in_world_space() -> void:
	var legs := _fresh()
	assert_false(legs._mist.local_coords, "the mist follows the leg instead of being left behind")
	assert_false(legs._grains.local_coords, "the grains follow the leg instead of landing")
	# And the automatic rate is off: every particle arrives on a footfall.
	assert_false(legs._mist.emitting, "the mist emitter runs a rate of its own, so the shed is on a clock")
	assert_false(legs._grains.emitting, "the grain emitter runs a rate of its own")
	_free(legs)


## The wind hook, in the vocabulary BreathFog and SnowfallLayer already use.
func test_the_wind_hook_moves_both_populations_by_their_own_drag() -> void:
	var legs := _fresh()
	var still_mist: Vector3 = legs._mist_material.gravity
	var still_grain: Vector3 = legs._grain_material.gravity
	legs.set_wind(Vector3(4.0, 0.0, 0.0))
	var blown_mist: Vector3 = legs._mist_material.gravity - still_mist
	var blown_grain: Vector3 = legs._grain_material.gravity - still_grain
	assert_true(blown_mist.x > 0.0, "the wind hook did not reach the mist")
	assert_true(
		blown_mist.x > blown_grain.x * 3.0,
		"the wind moved the mist by %f and a grain by %f" % [blown_mist.x, blown_grain.x]
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

## THE SHED IS NEAR-WHITE, AND THAT IS A CORRECTION.
##
## The first version drew it from the palette's snow entry barely taken toward
## white, and on the character it read as a blue film. The palette's blue
## describes the snow FIELD -- a huge area at distance under a blue sky, through
## the aerial perspective this project builds on purpose -- and a patch of snow
## on a dark coat a metre from the lens is a different lighting situation that
## scatters white. The owner reported the blue outright.
##
## So this pins the corrected requirement rather than the old one: nearly
## neutral, never warm, and still derived from the palette rather than typed in.
func test_every_part_of_the_shed_is_a_near_white_and_never_a_warm_one() -> void:
	var legs := _fresh()
	var bible = load(PALETTE_PATH)
	assert_not_null(bible, "the palette must load for this test to mean anything")
	var crust: ShaderMaterial = legs.crust_material()
	for entry in [
		["mist", (legs._mist.draw_pass_1.material as StandardMaterial3D).albedo_color],
		["grain", (legs._grains.draw_pass_1.material as StandardMaterial3D).albedo_color],
		["crust", crust.get_shader_parameter(&"snow_color") as Color],
	]:
		var tone: Color = entry[1]
		var rgb := Color(tone.r, tone.g, tone.b)
		assert_false(bible.is_warm(rgb), "%s is a warm tone" % entry[0])
		# Near-neutral: a faint cool cast is right, a blue cast is the defect. The
		# palette's own snow_tones[0] spans 1.51 between its red and its blue,
		# which is exactly what this must NOT be.
		var high := maxf(tone.r, maxf(tone.g, tone.b))
		var low := minf(tone.r, minf(tone.g, tone.b))
		assert_true(
			high / maxf(low, 0.0001) < 1.10,
			"%s is %s -- its brightest channel is %f times its dimmest, which reads as "
				% [entry[0], rgb.to_html(false), high / maxf(low, 0.0001)]
				+ "blue snow rather than as snow"
		)
		assert_true(tone.b >= tone.r, "%s is not even faintly cool" % entry[0])
	# And the premise of that check: the palette entry it is mixed FROM really is
	# blue enough for the mix to have done the work.
	var source: Color = bible.snow_tones[0]
	assert_true(source.b / source.r > 1.4, "snow_tones[0] is not blue, so this test proves nothing")
	_free(legs)


## OPAQUE WHERE IT EXISTS. The crust used to scale its ALPHA by the load, and
## pale snow at half alpha over a dark navy coat is a wash -- a blue transparent
## film painted over his legs, which is exactly how it was reported. What varies
## now is coverage, and every patch that carries snow is solid.
func test_the_crust_varies_its_coverage_rather_than_its_transparency() -> void:
	var legs := _fresh()
	var crust: ShaderMaterial = legs.crust_material()
	assert_almost_eq(
		crust.get_shader_parameter(&"max_opacity"), 1.0, 0.0001,
		"the crust is drawn part-transparent, so pale snow over dark cloth is a wash"
	)
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	# The mechanism, not just the number: a threshold on a noise field is what
	# makes patches appear and go out one at a time instead of the whole crust
	# dimming, and it is the only thing that can produce a patchy silhouette.
	assert_true(
		text.contains("smoothstep(threshold - width, threshold + width, field)")
			and text.contains("mix(1.0 + width, -width, coverage)"),
		"%s does not threshold its noise against the coverage, so the crust cannot "
			% SHADER_PATH
			+ "break up into patches -- it can only fade"
	)
	assert_true(
		text.contains("crease_map"),
		"%s does not read the character's own normal map, so the snow cannot collect "
			% SHADER_PATH
			+ "in the folds and seams that make it read as caught in cloth"
	)
	_free(legs)


## The grains are the crisp half and the mist is the soft half, and that is not
## decoration: a small blob with a soft falloff reads as fog whatever size it is
## drawn at, so soft edges belong to the mist fraction alone.
func test_a_grain_has_an_edge_on_it_and_a_puff_does_not() -> void:
	var legs := _fresh()
	var grain: GradientTexture2D = (legs._grains.draw_pass_1.material as StandardMaterial3D).albedo_texture
	var mist: GradientTexture2D = (legs._mist.draw_pass_1.material as StandardMaterial3D).albedo_texture
	# Alpha at 60% of the way out from the centre. A hard-edged disc is still
	# solid there; a bell is well down its slope.
	var grain_mid: float = grain.gradient.sample(0.6).a
	var mist_mid: float = mist.gradient.sample(0.6).a
	assert_true(
		grain_mid > 0.95,
		"a grain is already down to %f alpha at 60 percent of its radius, which is "
			% grain_mid
			+ "a smudge rather than a fleck"
	)
	assert_true(
		mist_mid < 0.6,
		"the mist is %f alpha at 60 percent of its radius, so it has a shoulder and "
			% mist_mid
			+ "reads as a disc rather than as vapour"
	)
	_free(legs)


## Under about 2.5 px a particle stops being an object and starts being a
## shimmering sub-pixel sample -- SnowfallLayer.min_flake_pixels is this
## project's own figure, copied here for the reason GLOW_HDR_THRESHOLD above is
## copied. A grain under the floor does not read as grit, it reads as haze, which
## is the one thing this population exists not to be.
##
## Checked against the SMALLEST grain in the spread, because a floor only the
## average clears is not a floor.
func test_the_smallest_grain_is_still_big_enough_to_be_seen() -> void:
	var rig: Node3D = CameraRigScript.new()
	var framing: float = rig.orthographic_size
	# Node, not RefCounted (briefing section 2.2).
	rig.free()
	var legs := _fresh()
	var smallest: float = legs._grain_material.scale_min
	var pixels: float = smallest * (FRAME_PIXELS / framing)
	assert_true(
		pixels >= MIN_GRAIN_PIXELS,
		"the smallest grain is %f m, which at the %f m game framing over a %d px frame "
			% [smallest, framing, int(FRAME_PIXELS)]
			+ "is %f px against a floor of %f" % [pixels, MIN_GRAIN_PIXELS]
	)
	# And it is not solved by making them boulders.
	assert_true(legs.grain_size_m < 0.09, "a grain %f m across is a snowball" % legs.grain_size_m)
	_free(legs)


## Bloom belongs to the fire and the windows. A boot-height particle backlit by a
## 21.5-degree sun is the easiest thing in the frame to bloom by accident.
##
## THE EXPOSURE IS IN THIS SUM NOW, and it was not before, which made the old
## version of this check pass a value that would have bloomed. Both populations
## are unshaded, so their albedo goes to the HDR buffer untouched by any light --
## and the buffer the glow is extracted from is post-exposure. PALE DAY is the
## brightest of the six at 1.38, so it is the one that has to clear.
func test_the_shed_cannot_reach_the_bloom_threshold() -> void:
	var legs := _fresh()
	var brightest = load("res://data/lighting/pale_day.tres")
	assert_not_null(brightest, "the brightest preset must load for this test to mean anything")
	var exposure: float = brightest.tonemap_exposure
	assert_true(exposure > 1.0, "pale_day's exposure is %f; this test assumes it is the brightest" % exposure)
	for entry in [
		["mist", legs._mist.draw_pass_1.material],
		["grain", legs._grains.draw_pass_1.material],
	]:
		var surface: StandardMaterial3D = entry[1]
		var linear: Color = surface.albedo_color.srgb_to_linear()
		var peak: float = maxf(maxf(linear.r, linear.g), linear.b) \
			* surface.albedo_color.a * exposure
		assert_true(
			peak < GLOW_HDR_THRESHOLD,
			"%s reaches the HDR buffer at %f against a threshold of %f: the shed will glow"
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


# --- the crust line is the depth he waded ---------------------------------------

## THE ONE THIS CHANGE IS ABOUT. A shallow crossing must mark him a little and a
## deep one a lot -- and it is that DIFFERENCE, not the crust itself, that an eye
## at the game camera can catch. A fixed band said nothing: a man out of a full
## drift came out with a crust at his ankle, exactly like a man out of a puddle.
##
## The two depths are 0.43 and 0.48 rather than the field's own 0.42 and 0.60,
## and that is not dodging. With no body to ask, `snow_line_on_the_leg()` falls
## back to the raw depth -- there is no sink to subtract -- so these two stand in
## for the lines the game actually produces: 0.42 m and 0.60 m of snow, minus the
## three quarters of it the body sinks through, is 0.32 m to 0.45 m on the leg.
## Feeding the raw depths here would instead test the knee cap, which
## test_the_crust_can_never_climb_past_the_knee already does on its own.
func test_a_deeper_crossing_leaves_a_higher_crust_line() -> void:
	var shallow := _fresh()
	_walk(shallow, 0.43, 4)
	var deep := _fresh()
	_walk(deep, 0.48, 4)
	assert_almost_eq(
		shallow.carried(), deep.carried(), 0.0001,
		"the two crossings must load the same, or this is measuring the load"
	)
	assert_true(
		deep.crust_top_fraction() > shallow.crust_top_fraction() + 0.02,
		"a 0.48 m crossing reached %f of the figure and a 0.43 m one reached %f: the "
			% [deep.crust_top_fraction(), shallow.crust_top_fraction()]
			+ "crust is not recording how deep he waded"
	)
	# And it IS the depth, not a curve fitted to it.
	assert_almost_eq(deep.wade_line_m(), 0.48, 0.0001, "the recorded line is not the depth he waded")
	assert_almost_eq(shallow.wade_line_m(), 0.43, 0.0001)
	# Both under the knee, so this is measuring the measurement and not the cap.
	assert_true(
		deep.crust_top_fraction() < deep.knee_line,
		"the deep crossing is sitting on the cap, so this test is checking the cap"
	)
	_free(shallow)
	_free(deep)


## The deepest part of the crossing, not the last part of it. A man who crosses
## the shoulder of a drift and then a hollow comes out wearing the hollow: snow
## does not leave a leg because the next step was shallower, it leaves when the
## leg hits the ground, and that is the other branch entirely.
func test_the_line_records_the_deepest_step_of_the_crossing() -> void:
	var legs := _fresh()
	legs.step(Vector3.ZERO, 0.58, Vector2.RIGHT)
	legs.step(Vector3.ZERO, 0.44, Vector2.RIGHT)
	assert_almost_eq(
		legs.wade_line_m(), 0.58, 0.0001,
		"a shallower step in the same drift pulled the crust line down with it"
	)
	legs.step(Vector3.ZERO, 0.60, Vector2.RIGHT)
	assert_almost_eq(legs.wade_line_m(), 0.60, 0.0001, "a deeper step did not raise the line")
	_free(legs)


## And it is forgotten when the crossing is over. Once his legs are clean the
## next drift gets to leave its own mark rather than inheriting the last one's.
func test_the_line_is_forgotten_once_the_legs_are_clean() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 5)
	assert_true(legs.wade_line_m() > 0.0, "the deep crossing recorded nothing")
	_walk(legs, THIN, 30)
	assert_almost_eq(
		legs.wade_line_m(), 0.0, 0.0001,
		"thirty clean strides left the crossing's line still on the legs"
	)
	# The next crossing is its own.
	_walk(legs, 0.45, 4)
	assert_almost_eq(legs.wade_line_m(), 0.45, 0.0001, "the new crossing inherited the old one's line")
	_free(legs)


## The crust retreats to the boot as he sheds, and stops there. That retreat is
## most of what reads as cleaning up -- an edge that stayed put and only faded
## would read as the effect being switched off.
func test_the_crust_edge_retreats_to_the_boot_as_he_sheds() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 6)
	var loaded: float = legs.crust_top_fraction()
	var previous := loaded
	for _step in range(8):
		legs.step(Vector3.ZERO, THIN, Vector2.RIGHT)
		var now: float = legs.crust_top_fraction()
		assert_true(now <= previous, "the crust climbed his leg while he was shedding")
		previous = now
	assert_true(previous < loaded, "eight clean strides did not lower the crust line at all")
	assert_true(
		previous >= legs.boot_line - 0.0001,
		"the line retreated past the boot to %f; the last of it clings to the boot" % previous
	)
	_free(legs)


## A cap at the measured knee, so the field can be retuned deeper without this
## having to be re-checked by eye. A crust over the knee is not snow off a drift.
func test_the_crust_can_never_climb_past_the_knee() -> void:
	var legs := _fresh()
	# Absurd on purpose: three metres of snow is not a thing this field can hold,
	# and the point is that the cap does not depend on it not being.
	_walk(legs, 3.0, 6)
	assert_true(
		legs.crust_top_fraction() <= legs.knee_line + 0.0001,
		"three metres of snow put the crust at %f of the figure, past the knee at %f"
			% [legs.crust_top_fraction(), legs.knee_line]
	)
	# Measured off the shipped rig: the knee sits at 25.7% of the figure.
	assert_almost_eq(legs.knee_line, 0.257, 0.0001, "the cap moved off the measured knee")
	assert_true(legs.boot_line < legs.knee_line, "the crust cannot reach lower when there is more of it")
	_free(legs)


## The shader is handed both ends and the measured line, and starts clean.
func test_the_crust_material_carries_the_line_the_node_measured() -> void:
	var legs := _fresh()
	_walk(legs, 0.55, 5)
	var crust: ShaderMaterial = legs.crust_material()
	assert_almost_eq(crust.get_shader_parameter(&"boot_line"), legs.boot_line, 0.0001)
	assert_almost_eq(
		crust.get_shader_parameter(&"wade_line"), legs.wade_fraction(), 0.0001,
		"the shader was not given the line the node measured"
	)
	assert_true(
		float(crust.get_shader_parameter(&"wade_line")) > legs.boot_line,
		"a 0.55 m crossing handed the shader a line no higher than a clean boot"
	)
	_free(legs)


## The spray comes off the band the crust is actually occupying, so the particles
## and the crust are one statement rather than two.
func test_the_spray_leaves_from_the_band_the_crust_is_on() -> void:
	var legs := _fresh()
	_walk(legs, 0.60, 6)
	var deep_top: float = legs._leg_top_m()
	var shallow := _fresh()
	_walk(shallow, 0.45, 6)
	assert_true(
		deep_top > shallow._leg_top_m(),
		"the deep crossing throws its snow off the same height as the shallow one: %f against %f"
			% [deep_top, shallow._leg_top_m()]
	)
	assert_almost_eq(
		deep_top, legs.crust_top_fraction() * legs._subject_height(), 0.0001,
		"the spray does not leave from where the crust reaches"
	)
	_free(legs)
	_free(shallow)
