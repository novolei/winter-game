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

const SnowLoadScript := preload("res://src/entities/snow_load.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SHADER_PATH := "res://assets/shaders/snow_load.gdshader"

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

## ---------------------------------------------------------------------------
## WHAT "YOU CAN SEE SNOW ON HIM" IS, AS A NUMBER
## ---------------------------------------------------------------------------
## Two landmarks on the settled load, both DERIVED from a rendered frame rather
## than chosen. `tools/measure_crust_coverage.gd` counts the pixels the crust
## actually paints -- REAL differenced against BARE -- at the framing the game is
## played at (1280x800, the rig's own orthographic 10.5), walker at (20, -20) on
## open ground, pattern pinned so every row is the same marks:
##
##     settle 0.00  ->     0 px
##     settle 0.005 ->   240 px    <- THE FLOOR
##     settle 0.01  ->   274 px
##     settle 0.03  ->   343 px
##     settle 0.10  ->   472 px    <- twice the floor
##     settle 0.20  ->   585 px
##     settle 0.30  ->   688 px    <- more than half a fully caked man
##     settle 0.50  ->   918 px
##     settle 1.00  ->  1255 px
##
## THE FLOOR IS REAL AND IT IS NOT A DEFECT: `crease_bias` saturates the noise
## field on the most upward-facing folds, so the first flake to land on him puts
## 240 px of white in his creases and no rate anywhere can make that arrive later.
## It is the least this effect can ever show, which is what makes it the right
## thing to measure the rest against.
##
##   LEGIBLE  0.10 -- twice the floor. Below it you are looking at the frosting
##            the first flake gave him and nothing more.
##   OBVIOUS  0.30 -- 688 px, over half the 1255 a caked man carries.
const LEGIBLE_SETTLE := 0.10
const OBVIOUS_SETTLE := 0.30


func _fresh() -> Node3D:
	var legs: Node3D = SnowLoadScript.new()
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


## How long a man standing perfectly still takes to reach a given settled load,
## in seconds. Ticked a second at a time because the answer is quoted in seconds
## and because the rule is framerate-correct, so the step size cannot change it.
func _seconds_to_settle(legs: Node3D, target: float, give_up_after: int) -> float:
	var seconds := 0.0
	while legs.settled() < target and seconds < float(give_up_after):
		legs._process(1.0)
		seconds += 1.0
	return seconds


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
	var legs: Node3D = SnowLoadScript.new()
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
	assert_almost_eq(SnowLoadScript.loaded_after(0.0, 0.5), 0.5, 0.0001)
	assert_almost_eq(SnowLoadScript.loaded_after(0.5, 0.5), 0.75, 0.0001)
	assert_almost_eq(SnowLoadScript.loaded_after(1.0, 0.5), 1.0, 0.0001, "loading must saturate at a full leg")
	assert_almost_eq(SnowLoadScript.shed_by_a_step(1.0, 0.7), 0.3, 0.0001)
	assert_almost_eq(SnowLoadScript.shed_by_a_step(0.5, 0.7), 0.15, 0.0001)
	assert_almost_eq(SnowLoadScript.shed_by_a_step(0.0, 0.7), 0.0, 0.0001, "a clean leg cannot shed")


# --- the two populations -------------------------------------------------------

## Drag is the ONLY difference between the mist and the grains, and the wind
## response falls out of it rather than being decided twice. A gust must carry
## the mist and barely move a grain.
func test_the_wind_reaches_the_mist_and_hardly_touches_a_grain() -> void:
	var legs := _fresh()
	var powder: float = SnowLoadScript.wind_response(legs.mist_damping)
	var lump: float = SnowLoadScript.wind_response(legs.grain_damping)
	assert_true(
		powder > lump * 3.0,
		"mist takes %f of the wind and a grain %f: they are not separated by drag" % [powder, lump]
	)
	assert_true(lump < 0.25, "a grain takes %f of the wind; it is meant to be ballistic" % lump)
	assert_true(powder < 1.0, "no particle may outrun the air it is in")
	assert_almost_eq(SnowLoadScript.wind_response(0.0), 0.0, 0.0001, "a dragless particle cannot be blown")
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
	assert_eq(SnowLoadScript.burst_count(0.4, 0.2), 1, "a low roll must produce the particle")
	assert_eq(SnowLoadScript.burst_count(0.4, 0.9), 0, "a high roll must produce none")
	assert_eq(SnowLoadScript.burst_count(2.4, 0.9), 2, "the whole part must always be emitted")
	assert_eq(SnowLoadScript.burst_count(2.4, 0.2), 3)
	assert_eq(SnowLoadScript.burst_count(0.0, 0.0), 0, "nothing shed, nothing thrown")
	assert_eq(SnowLoadScript.burst_count(-1.0, 0.0), 0)


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


# --- how much of him it covers --------------------------------------------------

## THE ONE THE THIRD PASS EXISTS FOR, and it is a number rather than an opinion.
##
## Two rounds of tuning by eye landed the crust at 2.9% of the band it occupies at
## the load the game actually shows, against a target of a third to a half. It
## read as a scatter of sparkles on a boot rim. This pins the two knobs that were
## wrong, and the SHAPE of the fix -- a unit test cannot count pixels, so it holds
## the mechanism that the measurement in `tools/measure_crust_coverage.gd` then
## checks the result of.
func test_the_crust_covers_a_real_fraction_of_the_band_rather_than_speckling_it() -> void:
	var legs := _fresh()
	# THIS NUMBER WAS SOLVED, NOT CHOSEN. It is the coverage at the SOLE; the
	# thinning above it takes the band average down, and the crease bias and the
	# noise's own clamping move it again, so the only way to know what it produces
	# is to render it and count. `tools/measure_crust_coverage.gd` did, on the
	# shipped walker at the shipped framing:
	#
	#     load 1.00   35.0% of the band     load 0.70   43.9%     load 0.49  33.5%
	#
	# against a target of a third to a half. The bound here is wide because it is
	# guarding the ORDER OF MAGNITUDE that went wrong -- the shipped effect was at
	# 2.9% -- and the exact value belongs to the measurement, which is where anyone
	# retuning this should go.
	assert_true(
		legs.crust_coverage >= 0.30,
		"the crust covers only %f of the cloth where it is thickest, so the band "
			% legs.crust_coverage
			+ "average cannot reach the third-to-a-half the reference shows"
	)
	# And it is not solved by painting him white. Bare cloth showing BETWEEN the
	# clumps is what makes it read as snow rather than as a costume.
	assert_true(legs.crust_coverage <= 0.70, "the crust covers %f of the cloth, which is a white leg" % legs.crust_coverage)
	var crust: ShaderMaterial = legs.crust_material()
	assert_almost_eq(
		crust.get_shader_parameter(&"crust_coverage"), legs.crust_coverage, 0.0001,
		"the shader was not given the coverage the node holds"
	)
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	# THE THINNING IS MEASURED AGAINST THE BAND, NOT AGAINST THE FIGURE, and that
	# is half of why the old version collapsed: a 30 cm ramp on a 43 cm band put
	# five sixths of the crust on the falling half of it, and shortening the band
	# by shedding shortened the solid part to nothing.
	assert_true(
		text.contains("float climb = clamp(height / max(full, 0.0001), 0.0, 1.0);"),
		"%s does not measure the thinning against the crossing, so a leg that has "
			% SHADER_PATH
			+ "shed some of its crust gets sparser as well as shorter -- which is what "
			+ "took 36.4%% of the band down to 19.0%% one step out of a drift"
	)
	# And what is left of it is CLIPPED at the retreating edge rather than
	# rescaled, or the two would be the same thing again.
	assert_true(
		text.contains("float reaches = 1.0 - smoothstep(edge - 0.006, edge + 0.006, height);"),
		"%s does not clip the crust at the edge the load has retreated to" % SHADER_PATH
	)
	# And the load moves the EDGE rather than the density. Snow does not become
	# more porous as it comes off a leg; the area it occupies shrinks.
	assert_false(
		text.contains("* load;") and text.contains("smoothstep(edge - patch_scatter"),
		"%s still scales its coverage by the load on top of retreating the edge, "
			% SHADER_PATH
			+ "which is what took 30.9% of the band down to 2.9% one step out of a drift"
	)
	_free(legs)


## MANY SMALL MARKS OVER THE WHOLE FIGURE, and this test changed direction once.
##
## It used to require `patch_scale < 20` -- "clumps, not grit" -- on the reasoning
## that raising the coverage of a fine speckle gives forty per cent of noise
## rather than forty per cent of snow. That reasoning was answering the WRONG
## QUESTION. The coverage was 2.9% at the time and coarsening the noise was
## prescribed as the remedy; the actual causes were three separate arithmetic
## faults, and fixing those took the coverage to 43.9%. What the coarse noise
## then did is what low-frequency noise always does -- large connected regions of
## on and of off -- so the figure came out with a few blocky patches on the hood
## and one shoulder and bare arms, chest and thighs between them.
##
## The owner compared the two builds and prefers the FINE, BROADLY SPREAD one:
## marks on the hood, both shoulders, both arms, the chest, the thighs and the
## boots, which is what a man who has been out in it looks like.
##
## COVERAGE AND DISTRIBUTION ARE INDEPENDENT AXES and this is the whole lesson:
## the threshold decides HOW MUCH is covered and the noise scale decides HOW IT
## IS SPREAD. The measured coverage stays where it is; only the scale moves.
func test_the_marks_are_fine_grained_and_spread_over_the_whole_figure() -> void:
	var legs := _fresh()
	assert_true(
		legs.patch_scale > 20.0,
		"the patch noise runs at %f over the character's UVs, which is low enough "
			% legs.patch_scale
			+ "to give large connected regions of on and off: a few blocky patches "
			+ "with bare arms and chest between them, which is the look that was "
			+ "reported"
	)
	# And not so fine that a mark is a sub-pixel sample. Above about 42 a mark on
	# a 130 px figure at the game camera stops being a mark and starts shimmering,
	# which is the failure at the other end of the same axis.
	assert_true(
		legs.patch_scale <= 42.0,
		"at %f the marks are finer than the frame can resolve" % legs.patch_scale
	)
	assert_true(legs.patch_warp > 0.0, "the clump outlines are unwarped, so they are round blobs")
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	# KEPT FROM THE COARSE BUILD, deliberately: the complaint was about scale and
	# spread, not about edge quality. The warp is what makes an individual mark
	# read as snow rather than as a dot, and it is in the noise's OWN cells, so it
	# stays proportional at any scale.
	assert_true(
		text.contains("vec2 q = p + warp * patch_warp;"),
		"%s does not warp its noise lookup, so a clump has the round shoulder a "
			% SHADER_PATH
			+ "plain fBm threshold produces rather than fingers and inlets"
	)
	# Most of the weight in the base octave: spread evenly the field has no scale
	# of its own and the mark size stops being something `patch_scale` decides.
	assert_true(
		text.contains("snow_noise(q) * 0.72"),
		"%s spreads its octave weights, so the noise has no mark size of its own" % SHADER_PATH
	)
	_free(legs)


# --- and it is a different pattern on every wearer -------------------------------

## THE PATTERN WAS IDENTICAL EVERY TIME, and the owner asked for it not to be:
## "身上的积雪的位置和面积好像每次都是固定的 可不可以做成随机的位置".
##
## The field is a hash of the surface's own UVs, so with nothing else in it two
## runs of the game put the snow in exactly the same places. That is a small
## thing between sessions and a LOUD one within a session: the bear in Wave 4 and
## the threats in Wave 5 stand in the same blizzard as the player, and several
## creatures wearing the same snow in the same places is far more noticeable than
## one creature repeating between runs.
##
## So each wearer offsets the field by its own amount. This is the test that
## proves the randomisation does anything at all.
func test_two_wearers_do_not_wear_the_same_pattern() -> void:
	# TWELVE WEARERS, NOT TWO, AND THAT IS A CORRECTION TO THIS TEST RATHER THAN
	# TO THE FEATURE. The first version asserted that one pair landed more than a
	# cell apart in the field and it failed on its first run at 0.92 -- which is
	# not a defect, it is what two uniform draws in a square do about one time in
	# twenty. A bound on ONE pair either flakes or is too loose to catch anything.
	# The claims that actually distinguish a working roll from a broken one are
	# about the POPULATION: no two wearers alike, and the sample spread across a
	# real part of the field.
	var made: Array[Node3D] = []
	var offsets: Array[Vector2] = []
	for index in range(12):
		# No `_ready()`. The offset is rolled at CONSTRUCTION, which is the claim
		# being tested, and building twelve pairs of emitters to read one Vector2
		# each would be a lot of engine noise for nothing.
		var walker: Node3D = SnowLoadScript.new()
		made.append(walker)
		offsets.append(walker.noise_offset())
	var least := offsets[0]
	var most := offsets[0]
	for offset in offsets:
		least = Vector2(minf(least.x, offset.x), minf(least.y, offset.y))
		most = Vector2(maxf(most.x, offset.x), maxf(most.y, offset.y))
	for index in range(offsets.size()):
		for other in range(index + 1, offsets.size()):
			assert_true(
				offsets[index] != offsets[other],
				"wearers %d and %d were handed the same offset (%s), so they are "
					% [index, other, str(offsets[index])]
				+ "wearing the same snow in the same places -- which is what a "
				+ "constant, or an offset rolled once for the class rather than "
				+ "per instance, looks like"
			)
	# And they are spread over the field rather than huddled in one corner of it.
	# Twelve uniform draws confined to a quarter of the range is a one-in-350-000
	# accident and an obvious defect, so this cannot flake in any useful sense.
	var spread := most - least
	assert_true(
		spread.x > 2.0 and spread.y > 2.0,
		"twelve wearers' offsets span only %s cells of a field %f across, so the "
			% [str(spread), SnowLoadScript.NOISE_OFFSET_CELLS]
			+ "roll is not covering it"
	)
	for walker in made:
		walker.free()
	# And it reaches the material, which is the only place it can do any work.
	var first := _fresh()
	var second := _fresh()
	var one: ShaderMaterial = first.crust_material()
	var two: ShaderMaterial = second.crust_material()
	assert_true(
		one.get_shader_parameter(&"noise_offset") != two.get_shader_parameter(&"noise_offset"),
		"both crusts were handed the same offset, so the two walkers render alike "
			+ "whatever the node holds"
	)
	assert_eq(
		one.get_shader_parameter(&"noise_offset"), first.noise_offset(),
		"the crust was not given the offset its own wearer holds"
	)
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	# THE WHOLE DOMAIN MOVES, warp included. Offsetting only the base lookup and
	# leaving the warp where it was would shift the marks while leaving their
	# ragged edges behind, which is a different field rather than the same field
	# somewhere else.
	assert_true(
		text.contains("snow_patches(UV * patch_scale + noise_offset)"),
		"%s does not offset the whole lookup domain, so the warp and the octaves "
			% SHADER_PATH
			+ "do not travel with the marks they belong to"
	)
	_free(first)
	_free(second)


## AND IT IS THE WEARER'S, NOT THE MOMENT'S OR THE PLACE'S.
##
## A pattern that is re-rolled per frame crawls; a pattern seeded from where the
## walker is standing drifts across him as he walks, which is worse than a fixed
## one because it draws the eye. So the offset is taken once and never touched
## again: within one accumulation cycle a given wearer's snow appears and
## disappears in the same places, which is what makes the threshold read as snow
## going out patch by patch rather than as static.
func test_one_wearers_pattern_stays_put_while_the_load_comes_and_goes() -> void:
	var legs := _fresh()
	var body := Node3D.new()
	legs.set_subject(body)
	var born: Vector2 = legs.noise_offset()
	var crust: ShaderMaterial = legs.crust_material()
	# A whole accumulation cycle: into the drift, out of it, and time passing --
	# every input this node has, short of another wearer.
	_walk(legs, DEEP, 4)
	legs._process(0.5)
	body.position = Vector3(37.0, 0.0, -14.0)
	legs.set_snowfall_rate(1.0)
	legs._process(2.0)
	_walk(legs, THIN, 6)
	legs._process(0.5)
	# HE MUST STILL BE CARRYING SOMETHING, or this test has stopped testing
	# anything: a wearer who shakes completely clean is entitled to a new pattern
	# (see the test below), so a cycle that ended clean would make the assertion
	# beneath this one a claim about the wrong state.
	assert_true(
		legs.total_load() > legs.shed_floor,
		"this test needs a body still carrying a load at the end of the cycle, not %f"
			% legs.total_load()
	)
	assert_eq(
		legs.noise_offset(), born,
		"the pattern moved during one crossing, so the snow crawls over him "
			+ "instead of going out patch by patch"
	)
	assert_eq(
		crust.get_shader_parameter(&"noise_offset"), born,
		"the material's offset moved while the load did"
	)
	body.free()
	_free(legs)


## AND A NEW CROSSING GETS A NEW ONE. The owner's second correction, and he
## explicitly offered to accept the fixed pattern if it were a performance
## decision:
##
## > 玩家从移动到下一次静止的时候，身上的积雪位置可不可以发生随机的变化…如果这是
## > 为了游戏性能考量而设计成前后积雪位置保持不变的话，我可以接受这个设定。
##
## IT IS NOT A PERFORMANCE DECISION. The offset is one vec2 uniform and rolling
## it again costs a uniform write. The pattern was frozen because the test above
## requires it to be -- patches that jump position while snow is on him are a far
## louder artefact than a repeat -- and that constraint stays. It simply reached
## further than it had to: it froze the pattern for the whole life of the wearer
## rather than for the life of a load.
##
## So the roll is on the LOAD REACHING ZERO, and never on him merely stopping.
## The threshold matters more than it looks: both decay rules are exponential, so
## the load approaches zero and never arrives, and a re-roll waiting for a true
## zero fires never and the feature silently does nothing. Clean is `shed_floor`
## -- the number this file already uses for it -- and this test pins that rather
## than letting a second, private definition grow beside it.
func test_a_wearer_who_shakes_completely_clean_gets_a_new_pattern() -> void:
	var legs := _fresh()
	# A body with a surface on it, so the offset can be followed all the way to the
	# material the shader actually reads. `crust_material()` on its own hands back a
	# material the node is not wearing, and a re-roll that never reached the GPU
	# would pass a test written against that.
	var body := Node3D.new()
	var skin := MeshInstance3D.new()
	skin.mesh = BoxMesh.new()
	body.add_child(skin)
	legs.set_subject(body)
	legs._process(0.016)
	var crust := skin.material_overlay as ShaderMaterial
	assert_not_null(crust, "the walker was never dressed, so this test cannot see the GPU's copy")
	var born: Vector2 = legs.noise_offset()
	# Into the drift, and the pattern is his crossing's from here until it is over.
	_walk(legs, DEEP, 5)
	legs._process(0.016)
	assert_eq(legs.noise_offset(), born, "the pattern moved while he was loading up")
	# A SHORT WALK THAT KEEPS SOME OF THE LOAD KEEPS THE PATTERN. This is the half
	# that stops the fix becoming the artefact: the snow still on him has not moved,
	# so neither may its marks.
	_walk(legs, THIN, 4)
	legs._process(0.016)
	assert_true(
		legs.total_load() > legs.shed_floor,
		"this test needs him still carrying something after four strides, not %f"
			% legs.total_load()
	)
	assert_eq(
		legs.noise_offset(), born,
		"the pattern moved while he was still carrying %f of a load, so his patches "
			% legs.total_load()
			+ "jump position in front of the player -- which is worse than a repeat"
	)
	# And now all the way clean.
	_walk(legs, THIN, 12)
	legs._process(0.016)
	assert_true(
		legs.total_load() < legs.shed_floor,
		"sixteen strides out of a drift left %f on him, so this test never reached "
			% legs.total_load()
			+ "the state it is about"
	)
	var next: Vector2 = legs.noise_offset()
	assert_true(
		next != born,
		"he shook completely clean and the next crossing starts from the same offset "
			+ "%s, so the snow lands in exactly the same places every time" % str(born)
	)
	# And it reaches the material, which is the only place an offset can do work --
	# a node that holds a new number while the GPU still draws the old one is the
	# same defect with a passing accessor.
	assert_eq(
		crust.get_shader_parameter(&"noise_offset"), next,
		"the new pattern never reached the crust the shader is actually reading"
	)
	# The second crossing then holds ITS pattern for as long as it lasts.
	_walk(legs, DEEP, 5)
	legs._process(0.016)
	assert_eq(legs.noise_offset(), next, "the second crossing's pattern moved under it")
	body.free()
	_free(legs)


## A PINNED PATTERN STAYS PINNED. `set_noise_offset()` is what makes two captures
## of two builds comparable -- they are judged on the same marks or they are not
## judged at all -- and a re-roll firing in the middle of a measurement would
## quietly turn a comparison back into two unrelated samples.
func test_a_pinned_pattern_survives_him_shaking_clean() -> void:
	var legs := _fresh()
	legs.set_noise_offset(Vector2(3.1, 5.7))
	_walk(legs, DEEP, 5)
	legs._process(0.016)
	_walk(legs, THIN, 16)
	legs._process(0.016)
	assert_true(legs.total_load() < legs.shed_floor, "he never got clean")
	assert_eq(
		legs.noise_offset(), Vector2(3.1, 5.7),
		"a pinned pattern was re-rolled, so a capture cannot be compared with another"
	)
	_free(legs)


# --- the snow that falls ON him -------------------------------------------------

## It builds while he STANDS STILL, which is the whole shape of the mechanic: the
## man who shelters keeps it off and the man who waits in the open wears it.
func test_the_sky_settles_snow_on_him_while_he_stands_still() -> void:
	var legs := _fresh()
	legs.set_snowfall_rate(1.0)
	assert_almost_eq(legs.settled(), 0.0, 0.0001, "he started the storm already covered")
	for _tick in range(60):
		legs._process(1.0)
	# A THIRD OF A LOAD IN A MINUTE OF BLIZZARD, AND THIS BOUND MOVED DOWN ON
	# PURPOSE. It used to require 0.7 here, which was the old settling rate stated
	# as a test -- and that rate was the thing the owner reported as wrong. What
	# this test is for is that the sky reaches him at all and that the rate does
	# something; how FAST it reaches him is
	# `test_settling_is_slow_enough_to_be_a_process_he_can_watch`, which states it
	# in seconds against the two weathers rather than in a number here.
	assert_true(
		legs.settled() > 0.3,
		"a minute of standing in a whiteout settled %f on him" % legs.settled()
	)
	# And it saturates rather than running past a full body.
	for _tick in range(600):
		legs._process(1.0)
	assert_true(legs.settled() <= 1.0, "the settled load ran past a full body: %f" % legs.settled())
	# Half the rate must take longer to reach the same place, or the rate is not
	# doing anything.
	var slower := _fresh()
	slower.set_snowfall_rate(0.25)
	for _tick in range(60):
		slower._process(1.0)
	assert_true(
		slower.settled() < legs.settled() * 0.75,
		"a quarter-rate snowfall settled %f against a whiteout's %f: the rate is not "
			% [slower.settled(), legs.settled()]
			+ "reaching the model"
	)
	_free(legs)
	_free(slower)


## AND IT IS SLOW ENOUGH TO BE A PROCESS HE CAN WATCH -- the owner's correction:
##
## > 玩家身上的积雪速度太过于快了，需要将玩家静止时身上的积雪速度减缓至少一半，
## > 现在静止一下子身上的积雪就很明显了，我希望可以是一个真实随静止时间慢慢变化
## > 的过程
##
## THE CLAIM IS A TIME, NOT A CONSTANT, so this test is written in seconds of
## standing still at the two weathers the game actually ships -- and it reads
## both rates off `Snowfall`'s own table rather than restating them, because a
## copy would go on passing the day somebody retunes the sky and the requirement
## would quietly stop being tested.
##
## The requirement, in the landmarks derived at the top of this file: a minute of
## day-one weather leaves him under LEGIBLE, several minutes take him past
## OBVIOUS, and a blizzard does both far sooner because the settling rate scales
## with the snowfall rate. That scaling is the reason there is no second model
## for "it is snowing harder", and the last assertion here is what holds it.
func test_settling_is_slow_enough_to_be_a_process_he_can_watch() -> void:
	# `.new()` and nothing else: Snowfall builds its layers in `_ready()`, which
	# this never calls, so what is read here is the export's own table.
	var sky := Snowfall.new()
	var day_one := float(sky.storm_by_preset[&"pale_day"])
	var blizzard := float(sky.storm_by_preset[&"whiteout"])
	sky.free()
	assert_true(day_one > 0.0 and day_one < blizzard, "the sky's own two rates are not a range")

	var minute := _fresh()
	minute.set_snowfall_rate(day_one)
	for _tick in range(60):
		minute._process(1.0)
	# It is a SLOW process and not a stopped one. Both halves matter: an effect
	# that never arrives is as wrong as one that arrives at once.
	assert_true(
		minute.settled() > 0.0,
		"a minute of day-one snow settled nothing at all on him"
	)
	assert_true(
		minute.settled() < LEGIBLE_SETTLE,
		"a minute of standing still on day one left %f on him, past the %f that is "
			% [minute.settled(), LEGIBLE_SETTLE]
			+ "twice the frosting the first flake gives him -- at a minute it is meant "
			+ "to be barely perceptible, not already legible"
	)
	_free(minute)

	var day := _fresh()
	day.set_snowfall_rate(day_one)
	var day_to_obvious := _seconds_to_settle(day, OBVIOUS_SETTLE, 1800)
	assert_true(
		day_to_obvious > 180.0,
		"day-one snow became obvious after %.0f s of standing still; the owner asked "
			% day_to_obvious
			+ "for several minutes of watching it happen"
	)
	assert_true(
		day_to_obvious < 900.0,
		"day-one snow took %.0f s to become obvious, which is not a process anybody "
			% day_to_obvious
			+ "stands still long enough to see"
	)
	_free(day)

	var storm := _fresh()
	storm.set_snowfall_rate(blizzard)
	var storm_to_obvious := _seconds_to_settle(storm, OBVIOUS_SETTLE, 900)
	assert_true(
		storm_to_obvious < 90.0,
		"a blizzard took %.0f s to put an obvious load on him: standing still in a "
			% storm_to_obvious
			+ "whiteout has to be visibly different from standing still on day one"
	)
	# ONE MODEL, NOT TWO. The time to any given load is inversely proportional to
	# the snowfall rate, so the two weathers differ by exactly the ratio of their
	# rates and by nothing that was tuned separately.
	assert_almost_eq(
		day_to_obvious / storm_to_obvious, blizzard / day_one, 0.5,
		"day one took %.0f s and a blizzard %.0f s, a ratio of %.2f against the sky's "
			% [day_to_obvious, storm_to_obvious, day_to_obvious / storm_to_obvious]
			+ "own %.2f -- the settling has stopped scaling with the snowfall"
			% (blizzard / day_one)
	)
	_free(storm)


## THE OWNER'S STATED REQUIREMENT, and it is not a special case anywhere -- the
## settling rate is proportional to the snowfall rate, so at zero it is zero.
## What is left is the waded crust, which is untouched by the weather.
func test_with_no_snowfall_only_wading_marks_him() -> void:
	var legs := _fresh()
	legs.set_snowfall_rate(0.0)
	for _tick in range(600):
		legs._process(1.0)
	assert_almost_eq(
		legs.settled(), 0.0, 0.0001,
		"ten minutes of clear weather put %f of snow on his shoulders" % legs.settled()
	)
	# And the boots still mark, because that half was never about the weather.
	_walk(legs, DEEP, 4)
	assert_true(legs.carried() > 0.7, "wading a drift on a clear day left the boots at %f" % legs.carried())
	assert_almost_eq(legs.settled(), 0.0, 0.0001, "wading settled snow on his shoulders")
	_free(legs)


## Moving shakes it off, which is the other half of "standing still is what lets
## it build" -- and it comes off FASTER than the waded crust does, because it is
## loose rather than packed and refrozen.
func test_a_footfall_shakes_the_settled_snow_loose() -> void:
	var legs := _fresh()
	# The drift FIRST and the storm second, because a walk shakes the settled snow
	# off as it goes -- which is the very thing being tested, and would otherwise
	# quietly leave nothing on his shoulders to shake.
	_walk(legs, DEEP, 6)
	legs.set_snowfall_rate(1.0)
	for _tick in range(300):
		legs._process(1.0)
	var caked: float = legs.settled()
	assert_true(caked > 0.9, "the storm never covered him: %f" % caked)
	var packed: float = legs.carried()
	legs.step(Vector3.ZERO, THIN, Vector2.RIGHT)
	assert_true(legs.settled() < caked, "a footfall shook nothing off his shoulders")
	assert_true(
		(caked - legs.settled()) / caked > (packed - legs.carried()) / packed,
		"one step took %f of the settled snow and %f of the packed crust: loose snow "
			% [(caked - legs.settled()) / caked, (packed - legs.carried()) / packed]
			+ "on a shoulder must come off more easily than a crust the leg has compacted"
	)
	# Four or five strides, which is what makes shaking off at the door a thing a
	# player can actually do.
	for _step in range(5):
		legs.step(Vector3.ZERO, THIN, Vector2.RIGHT)
	assert_true(legs.settled() < 0.1, "six strides left %f on his shoulders" % legs.settled())
	_free(legs)


## THE SETTLED HALF IS ON A CLOCK AND THE WADED HALF IS NOT, and both halves of
## that have to be true at once. The opening claim of this file -- the crust
## changes on footfalls and on nothing else -- must survive a system that grows
## on a timer beside it.
func test_time_settles_snow_and_still_never_touches_the_waded_crust() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 5)
	var packed: float = legs.carried()
	legs.set_snowfall_rate(1.0)
	for _tick in range(120):
		legs._process(1.0)
	assert_true(legs.settled() > 0.5, "two minutes of whiteout settled only %f" % legs.settled())
	assert_almost_eq(
		legs.carried(), packed, 0.0001,
		"two minutes of weather moved the waded crust from %f to %f: it is on a timer"
			% [packed, legs.carried()]
	)
	_free(legs)


## Warmth takes BOTH, and takes them fast enough to watch. The owner asked for
## the snow to be gone shortly after he steps inside.
func test_warmth_melts_everything_he_is_carrying() -> void:
	var legs := _fresh()
	legs.set_snowfall_rate(1.0)
	for _tick in range(300):
		legs._process(1.0)
	_walk(legs, DEEP, 5)
	assert_true(legs.total_load() > 0.9, "he did not arrive at the door carrying anything")
	legs.set_indoors(true)
	assert_true(legs.is_thawing(), "a man indoors is not thawing")
	for _tick in range(80):
		legs._process(0.1)
	assert_true(
		legs.total_load() < 0.05,
		"eight seconds in a warm room left %f on him; it is meant to go quickly"
			% legs.total_load()
	)
	# And the crossing is forgotten with it, so the next drift marks him afresh.
	assert_almost_eq(legs.wade_line_m(), 0.0, 0.0001, "the melted crust kept its crossing's line")
	# Back out into the cold and nothing melts any more.
	legs.set_indoors(false)
	assert_false(legs.is_thawing(), "he is still thawing after stepping back outside")
	_free(legs)


## A LIT FIRE IS A WARM PLACE, and this knows that without knowing what a stove
## is: the fire announces itself on the bus with a position, and a Wave 5 beacon
## that emits the same event melts snow off a walker for free.
func test_a_lit_fire_thaws_him_and_a_dead_one_does_not() -> void:
	var legs := _fresh()
	var subject := Node3D.new()
	legs.set_subject(subject)
	assert_false(legs.is_thawing(), "he is thawing in an empty field")
	legs._on_fire_lit({"position": Vector3(1.0, 0.0, 0.0)})
	assert_true(legs.is_thawing(), "a fire a metre away is not warming him")
	# Far enough away and it is a light rather than a heat source.
	legs._on_fire_out({"position": Vector3(1.0, 0.0, 0.0)})
	legs._on_fire_lit({"position": Vector3(40.0, 0.0, 0.0)})
	assert_false(legs.is_thawing(), "a fire forty metres away is melting the snow off him")
	# And a fire that goes out stops warming him.
	legs._on_fire_lit({"position": Vector3(2.0, 0.0, 0.0)})
	assert_true(legs.is_thawing())
	legs._on_fire_out({"position": Vector3(2.0, 0.0, 0.0)})
	assert_false(legs.is_thawing(), "a fire that went out is still warm")
	# A payload this cannot read is ignored rather than fatal: it arrives off a bus
	# and must never take the publisher down with it.
	legs._on_fire_lit(null)
	legs._on_fire_lit({"position": "over there"})
	subject.free()
	_free(legs)


## A stove that was already burning, and a building he was already standing in.
## Neither ever emits its event again, so a node that only subscribes never
## learns either.
class AlreadyBurning extends Node3D:
	func is_lit() -> bool:
		return true

	func warmth_at(_point: Vector3) -> float:
		return 1.0


class AlreadyInside extends Node:
	var who: Node = null

	func is_occupant_inside() -> bool:
		return true

	func occupant() -> Node:
		return who


## THE SHAPE THAT WILL BITE AGAIN: a node that listens only for a TRANSITION can
## never learn a state that changed before it existed.
##
## `stove.lit` fires once, at ignition, and the farmhouse stove ignites at
## startup. A walker who begins the run beside it subscribes to a change that has
## already happened and stands in the warm carrying snow for the rest of the
## game. It presents as "works when I walk in, broken when I start inside", which
## reads like a wiring fault and is not one.
##
## So the state is ASKED FOR as well as subscribed to. This walks a real tree,
## because the query only means anything from inside one.
## Builds a walker inside a detached world, so the scan has something above it to
## walk. No SceneTree anywhere: `TestCase` is not a Node and has no `get_tree()`,
## and the scan deliberately starts from the topmost ancestor rather than from
## `/root` so that this is testable at all.
func _in_a_world(neighbour: Node) -> Array:
	var world := Node.new()
	world.add_child(neighbour)
	var walker := Node3D.new()
	walker.name = "Walker"
	var legs: Node3D = SnowLoadScript.new()
	legs._ready()
	walker.add_child(legs)
	world.add_child(walker)
	return [world, walker, legs]


func test_he_learns_about_a_fire_that_was_already_lit_when_he_arrived() -> void:
	var built := _in_a_world(AlreadyBurning.new())
	var world: Node = built[0]
	var legs: Node3D = built[2]

	# Nothing has been emitted and nothing ever will be: this fire lit before the
	# node existed.
	assert_false(legs.is_thawing(), "he is thawing before anything has run")
	legs._process(0.016)
	assert_true(
		legs.is_thawing(),
		"a fire that was already burning when he arrived never reached him -- the "
			+ "node subscribed to the change and never asked for the state"
	)
	# And it is asked ONCE. A second tick must not rebuild the list.
	legs._process(0.016)
	assert_eq(legs._fires.size(), 1, "the world was asked twice and the fire counted twice")
	world.free()


## The same shape for a building, and the same fix. Also pins that the query is
## SUBJECT-AWARE: a building says who its occupant is, so the bear in Wave 4 does
## not warm up because the player went inside.
func test_a_building_only_warms_the_walker_it_actually_holds() -> void:
	var room := AlreadyInside.new()
	var built := _in_a_world(room)
	var world: Node = built[0]
	var walker: Node3D = built[1]
	var legs: Node3D = built[2]

	# The room holds somebody else. He must stay cold.
	var stranger := Node3D.new()
	world.add_child(stranger)
	room.who = stranger
	legs._process(0.016)
	assert_false(
		legs.is_thawing(),
		"a building holding somebody else warmed him: every walker in the scene "
			+ "would thaw the moment the player stepped indoors"
	)
	# The event carries the same building, and must be refused for the same reason.
	legs._on_interior_entered({"building": "farmhouse", "reveal": room})
	assert_false(legs.is_thawing(), "the event ignored whose building it was")
	# And accepted when it IS his.
	room.who = walker
	legs._on_interior_entered({"building": "farmhouse", "reveal": room})
	assert_true(legs.is_thawing(), "his own building did not warm him")
	legs._on_interior_exited({"building": "farmhouse", "reveal": room})
	assert_false(legs.is_thawing(), "leaving did not cool him")
	# A payload with no building in it is still his -- unanswerable means yes, the
	# same useful default claim_radius_m documents.
	legs._on_interior_entered({"building": "farmhouse"})
	assert_true(legs.is_thawing(), "a payload with no reveal was refused rather than accepted")
	world.free()


## Loose snow does not stay on a shoulder in a gale. The packed crust does.
func test_the_wind_strips_the_settled_half_and_not_the_packed_one() -> void:
	var legs := _fresh()
	_walk(legs, DEEP, 5)
	legs.set_snowfall_rate(1.0)
	for _tick in range(300):
		legs._process(1.0)
	var caked: float = legs.settled()
	var packed: float = legs.carried()
	assert_true(caked > 0.9, "the storm never covered him: %f" % caked)
	# The snowfall has to stop, or the wind is fighting the sky rather than the
	# load: a gale that also brings snow is a different question.
	legs.set_snowfall_rate(0.0)
	legs.set_wind(Vector3(12.0, 0.0, 0.0))
	for _tick in range(30):
		legs._process(1.0)
	assert_true(legs.settled() < caked * 0.5, "half a minute of gale left %f of %f" % [legs.settled(), caked])
	assert_almost_eq(
		legs.carried(), packed, 0.0001,
		"the wind stripped the packed crust off his boots as well"
	)
	_free(legs)


# --- what it costs him ----------------------------------------------------------

## A stand-in for the SurvivalSystem autoload, recording what was pushed at it.
## A Node rather than a RefCounted because that is what the real one is, and
## `is_instance_valid()` has to mean the same thing about both.
class FakeSurvival extends Node:
	var pushed: Array = []
	var removed: Array = []

	func push_modifier(target: StringName, source: StringName, operation: int,
			value: float, _duration := -1.0) -> bool:
		pushed.append({"target": target, "source": source, "operation": operation, "value": value})
		return true

	func remove_source(source: StringName) -> int:
		removed.append(source)
		return 1

	func live() -> Dictionary:
		# What the stack would hold: every push since the last remove of that source.
		var held := {}
		for entry in pushed:
			held[entry["source"]] = entry
		return held


## SNOW ON YOUR CLOTHES MAKES YOU COLD, which is what the owner asked for by
## name. A MULTIPLY on the DRAIN channel rather than an ADD against recovery:
## snow does not remove a fixed number of degrees, it defeats the insulation, so
## it scales whatever was already taking heat out of him -- and composes with
## NightExposure's own doubling instead of arguing with it.
func test_the_snow_he_is_carrying_makes_him_lose_heat_faster() -> void:
	var legs := _fresh()
	var body := FakeSurvival.new()
	legs.set_survival_system(body)
	# Clean: nothing pushed at all. A modifier that multiplies by one is still a
	# modifier, and "there is no snow on him" should look like nothing.
	legs._process(0.1)
	assert_true(body.pushed.is_empty(), "a dry man was charged for snow he is not carrying")
	_walk(legs, DEEP, 6)
	legs._process(0.1)
	assert_false(body.pushed.is_empty(), "a man out of a full drift was charged nothing")
	var last: Dictionary = body.pushed[body.pushed.size() - 1]
	assert_eq(last["target"], &"core_temperature:drain", "the chill landed on the wrong channel")
	assert_eq(
		last["operation"], Modifier.Operation.MULTIPLY,
		"the chill was added rather than multiplied, so it does not compose with the "
			+ "night doubling and does not scale with what is already draining him"
	)
	assert_true(
		last["value"] > 1.2,
		"a full load costs him a factor of %f, which is not a cost" % last["value"]
	)
	assert_almost_eq(
		float(last["value"]), legs.chill_at_full_load, 0.02,
		"a full load did not reach the full chill"
	)
	# REMOVE THEN PUSH. A second push without the remove compounds the stack, and a
	# load that ticked up a hundred times would multiply by the hundredth power.
	assert_eq(
		body.removed.size(), body.pushed.size(),
		"%d pushes against %d removes: the stack is being compounded"
			% [body.pushed.size(), body.removed.size()]
	)
	# And it goes away when he does. Melting it off must leave nothing behind.
	legs.set_indoors(true)
	for _tick in range(80):
		legs._process(0.1)
	assert_true(
		body.removed.size() > body.pushed.size(),
		"a man who melted his snow off indoors is still being charged for it"
	)
	body.free()
	_free(legs)


## Linear from free to full, so it can be pushed unconditionally rather than
## being a special case at each end.
func test_the_chill_is_proportional_to_what_he_is_carrying() -> void:
	assert_almost_eq(SnowLoadScript.chill_multiplier(0.0, 1.6), 1.0, 0.0001, "a dry man pays something")
	assert_almost_eq(SnowLoadScript.chill_multiplier(1.0, 1.6), 1.6, 0.0001)
	assert_almost_eq(SnowLoadScript.chill_multiplier(0.5, 1.6), 1.3, 0.0001)
	assert_almost_eq(SnowLoadScript.chill_multiplier(2.0, 1.6), 1.6, 0.0001, "the load is not clamped")
	assert_almost_eq(SnowLoadScript.chill_multiplier(1.0, 0.4), 1.0, 0.0001, "a load made him warmer")


## THE TWO LOADS ARE NOT ADDED. They are loads on different parts of him: a man
## with white shoulders and white boots is not carrying twice what a man with
## only white shoulders is, and summing them would let two half-loads cost more
## than one whole one.
func test_the_two_loads_are_the_larger_of_the_two_and_never_their_sum() -> void:
	var legs := _fresh()
	# The stride first: a footfall shakes the settled half loose, so settling
	# BEFORE walking would measure a body the walk had already half cleaned.
	_walk(legs, DEEP, 1)
	var packed: float = legs.carried()
	assert_true(packed > 0.4 and packed < 0.95, "this test needs a part-packed leg, not %f" % packed)
	legs.set_snowfall_rate(1.0)
	# A hundred seconds of blizzard, where forty used to do. The soak is a
	# PRECONDITION of this test and not its subject -- what is asserted below is
	# unchanged -- and settling is now three times slower by design, so the storm
	# has to be longer to leave the part-settled body the assertion needs.
	for _tick in range(100):
		legs._process(1.0)
	var settled: float = legs.settled()
	assert_true(settled > 0.4 and settled < 0.95, "this test needs a part-settled body, not %f" % settled)
	assert_almost_eq(
		legs.total_load(), maxf(packed, settled), 0.0001,
		"two half-loads summed to %f, which is more than a man can carry" % legs.total_load()
	)
	assert_true(legs.total_load() <= 1.0)
	_free(legs)


## The arithmetic of the two clocked rules, pinned on its own and framerate-
## correct: an exponential approach integrated as `+= rate * delta` drifts with
## the frame time, and this effect is judged in captures taken at a fixed 60
## while the game runs at whatever it runs at.
func test_settling_and_melting_do_not_depend_on_the_frame_rate() -> void:
	var one_step := SnowLoadScript.settled_after(0.0, 1.0, 0.5, 4.0)
	var many := 0.0
	for _tick in range(400):
		many = SnowLoadScript.settled_after(many, 1.0, 0.5, 0.01)
	assert_almost_eq(one_step, many, 0.0005, "settling in one tick and in four hundred disagree")
	var melted_once := SnowLoadScript.decayed_after(1.0, 0.5, 4.0)
	var melted_often := 1.0
	for _tick in range(400):
		melted_often = SnowLoadScript.decayed_after(melted_often, 0.5, 0.01)
	assert_almost_eq(melted_once, melted_often, 0.0005, "melting in one tick and in four hundred disagree")
	# No snowfall settles nothing; no warmth melts nothing.
	assert_almost_eq(SnowLoadScript.settled_after(0.3, 0.0, 0.5, 10.0), 0.3, 0.0001)
	assert_almost_eq(SnowLoadScript.decayed_after(0.3, 0.0, 10.0), 0.3, 0.0001)
	assert_true(SnowLoadScript.settled_after(0.99, 1.0, 0.5, 1000.0) <= 1.0, "settling ran past a full body")


## The settled half lands on what faces the sky and the waded half lives in a
## band, and it is that difference -- not a branch anywhere -- that puts one on
## his shoulders and the other on his boots.
func test_what_falls_on_him_lands_on_what_faces_the_sky() -> void:
	var legs := _fresh()
	var crust: ShaderMaterial = legs.crust_material()
	assert_almost_eq(crust.get_shader_parameter(&"settle_coverage"), legs.settle_coverage, 0.0001)
	assert_true(
		legs.settle_facing > 0.0,
		"a surface facing dead sideways collects snow out of the sky at %f, so a shin "
			% legs.settle_facing
			+ "whitens in a blizzard the same way a shoulder does"
	)
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(
		text.contains("smoothstep(settle_facing, settle_facing + settle_falloff, upness)"),
		"%s does not gate the settled snow on which way the surface faces" % SHADER_PATH
	)
	# And it is NOT gated by the wading band, or it could not reach his hood.
	assert_true(
		text.contains("float coverage = max(waded, settled);"),
		"%s does not combine the two loads, so one of them cannot be seen" % SHADER_PATH
	)
	_free(legs)
