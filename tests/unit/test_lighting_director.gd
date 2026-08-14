extends TestCase

## The director: which of the six is on screen, and how it gets there.
##
## The clock says "day 4 has begun" and the director has to turn that into a
## light rig without either system knowing the other exists -- so everything here
## goes through the EventBus, and the director loads GDD section 4's day table
## itself rather than asking WorldClock for it.
##
## CROSSFADING RATHER THAN CUTTING is the whole reason this is a director and not
## a lookup table. A cut between two of these presets is a lightning flash: the
## exposure on DEEP NIGHT is a third of PALE DAY's, and dropping it in one frame
## in a game with no HUD reads as a rendering fault.

const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const LightingPresetScript := preload("res://src/definitions/lighting_preset.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _director: LightingDirector = null
var _bus = null

## WorldEnvironment and EventBus both extend Node (briefing constraint 2).
func after_each() -> void:
	if _director != null:
		_director.free()
		_director = null
	if _bus != null:
		_bus.free()
		_bus = null

## _ready() is called by hand because nothing is in a tree (briefing trap 1).
## It resolves the bus only when it IS in one, so these get a bus injected.
func _build() -> LightingDirector:
	_bus = EventBusScript.new()
	_director = LightingDirectorScript.new()
	_director._ready()
	_director.set_event_bus(_bus)
	return _director

func _preset(exposure: float, fog: float) -> LightingPreset:
	var preset := LightingPresetScript.new()
	preset.tonemap_exposure = exposure
	preset.fog_density = fog
	return preset

# --- the six load -----------------------------------------------------------

func test_the_director_finds_all_six_presets() -> void:
	var director := _build()
	assert_eq(director.preset_ids().size(), 6, "Art Bible section 4.2 names six")
	for id in [&"flat", &"nightfall", &"deep_night", &"whiteout", &"sunrise", &"pale_day"]:
		assert_not_null(director.preset(id), "no preset '%s'" % id)

func test_asking_for_a_preset_that_does_not_exist_yields_nothing() -> void:
	var director := _build()
	assert_true(director.preset(&"golden_hour") == null, "it invented a preset")
	assert_false(director.apply_preset(&"golden_hour"), "it claimed to apply one that does not exist")


## F3 now opens the developer performance slate. Deep-night inspection remains
## available, but only with Shift so no two debug surfaces answer one key.
func test_shift_f3_preserves_the_deep_night_lighting_preview() -> void:
	var director := _build()
	director.debug_controls_enabled = true
	var event := InputEventKey.new()
	event.keycode = KEY_F3
	event.physical_keycode = KEY_F3
	event.shift_pressed = true
	event.pressed = true
	director._unhandled_key_input(event)
	assert_eq(director.active_preset().id, &"deep_night")

## The frame the game opens on. Day 1 is PALE DAY -- 无事挂心, nothing at stake --
## and it has to be on screen before the clock has said anything, or the first
## seconds of the run render with whatever the engine defaults to.
func test_the_first_frame_is_already_lit() -> void:
	var director := _build()
	assert_not_null(director.environment, "no Environment was built")
	assert_not_null(director.active_preset(), "the director booted with no preset applied")
	if director.active_preset() != null:
		assert_eq(director.active_preset().id, &"pale_day", "day 1 opens in PALE DAY")

# --- what applying one actually writes --------------------------------------

func test_applying_a_preset_writes_the_environment() -> void:
	var director := _build()
	director.apply_preset(&"whiteout")
	var whiteout := director.preset(&"whiteout")
	var env := director.environment
	assert_not_null(env, "no Environment")
	if env == null or whiteout == null:
		return
	assert_almost_eq(env.tonemap_exposure, whiteout.tonemap_exposure, 0.0001, "exposure")
	assert_almost_eq(env.fog_density, whiteout.fog_density, 0.0001, "fog density")
	assert_eq(env.fog_enabled, whiteout.fog_enabled, "fog switch")
	assert_eq(env.glow_enabled, whiteout.glow_enabled, "glow switch")
	assert_almost_eq(env.ambient_light_energy, whiteout.ambient_energy, 0.0001, "the character's fill")

func test_applying_a_preset_aims_and_dims_the_sun() -> void:
	var director := _build()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	director.add_child(sun)
	director._ready()
	director.apply_preset(&"deep_night")
	var deep := director.preset(&"deep_night")
	if deep == null:
		return
	assert_almost_eq(sun.light_energy, deep.sun_energy, 0.0001, "sun energy")
	assert_eq(sun.shadow_enabled, deep.shadows_enabled, "shadow switch")
	assert_almost_eq(
		rad_to_deg(-sun.rotation.x), deep.sun_angle_degrees, 0.001,
		"the sun's elevation should come from the preset"
	)

## The elevation the whole shadow language is tuned around. The director's own
## export is the reference value; every preset must agree with it, so that
## neither can drift without the other.
func test_every_preset_agrees_with_the_tuned_elevation() -> void:
	var director := _build()
	for id in director.preset_ids():
		assert_almost_eq(
			director.preset(id).sun_angle_degrees, director.sun_elevation_degrees, 0.001,
			"preset '%s' disagrees with the director's tuned elevation" % id
		)

# --- the arc ----------------------------------------------------------------
#
# WHAT THIS SECTION REPLACED, AND WHY IT IS NOT THE SAME TEST WITH A NEW NUMBER.
#
# There used to be one test here --
# `test_the_sun_keeps_the_azimuth_the_reference_painting_was_solved_for` -- and
# it asserted `director.sun_azimuth_degrees == 82.0` plus "the sun is aimed at
# whatever that export says". Its own comment gave the reason: *"the sun rises in
# one place over this valley, and a preset that moved it would be a different
# location rather than a different hour."*
#
# THE REASONING WAS RIGHT AND IT DID NOT DEFEND THE NUMBER IT PINNED. It argues
# the azimuth is not a PRESET's business, which is still true and still enforced
# -- no preset carries an azimuth field and none may. It says nothing about
# whether the azimuth may move with the HOUR, which is the one thing 82 was never
# asked about: 82 was a director export default, unchanged since the day the
# project started, specified by no design document, and describing an hour nobody
# chose. **A test asserting an accidental constant is asserting an implementation
# detail.** (Director's ruling, recorded in the sun-arc task brief.)
#
# Worse, and this is the part that decided it: with the arc implemented, the OLD
# TEST STILL PASSES UNCHANGED. It builds a director with no clock, and a director
# with no clock sits at the arc's centre -- which is 82. The test could not see
# the feature at all, in either direction. It was pinning the resting value of a
# thing whose whole subject is that it moves.
#
# So the spirit survives and the instrument changes. The sun's direction is still
# deliberate and still must not drift by accident; what is pinned now is the ARC
# -- its centre, its span, and the fact that the light actually travels it.
# Anyone moving the centre still trips a red test, and the test still names whose
# decision that is.


## The two questions the director asks a clock, and nothing else. RefCounted, so
## it frees itself (briefing constraint 2), and duck-typed, so this file names no
## system's type.
class StubClock extends RefCounted:
	var elapsed := 0.0
	var duration := 600.0
	var night := false

	func phase_elapsed() -> float:
		return elapsed

	func phase_duration() -> float:
		return duration

	func is_night() -> bool:
		return night


## A director with a sun under it and a clock in its hand. The sun has to be a
## real child named "Sun" because that is how _resolve_sun() finds it.
func _build_with_sun() -> Array:
	var director := _build()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	director.add_child(sun)
	director._ready()
	var clock := StubClock.new()
	director.set_world_clock(clock)
	director.apply_preset(&"pale_day")
	return [director, sun, clock]


## Aims the sun at a moment in the phase and reports where it actually ended up,
## read off the LIGHT rather than off any number the director holds.
func _sun_azimuth_at(director, sun: DirectionalLight3D, clock, at: float, night: bool) -> float:
	clock.elapsed = at * clock.duration
	clock.night = night
	director._process(0.0)
	return rad_to_deg(sun.rotation.y)


## THE ARC IS CENTRED ON THE SOLVED VALUE AND THIS IS WHOSE DECISION THAT IS.
##
## 82 degrees was derived from the rake measured off `Refs/game ref/level.jpg` --
## the farmhouse throws its shadow left and 16 degrees down, the well house left
## and 13 -- and verified by screenshot against the painting. At the previous 118
## the rake came out at 54 degrees: shadows that fall DOWN the frame instead of
## across it. That solved value is now the MIDDLE OF THE DAY rather than the whole
## day, and it is still the only azimuth in this project anybody solved for
## anything.
##
## 13 degrees of half-span is narrow deliberately: the reference's shadows rake
## 13-20 degrees below horizontal, so the arc keeps the approved look at midday
## and spends its budget at the two ends.
##
## **Both numbers are the Director's, not an implementer's.** Widening the arc is
## a taste call somebody may well make -- the 40-degree and 125-degree captures in
## `.superpowers/sdd/wave3/living-light/` are what that would look like -- but it
## is a call, and it goes red here first so that it is made rather than drifted
## into. Moving the CENTRE is a bigger claim than that: it says the valley is
## somewhere else.
func test_the_suns_arc_is_centred_on_the_azimuth_the_reference_painting_was_solved_for() -> void:
	var director := _build()
	assert_almost_eq(
		director.sun_azimuth_degrees, 82.0, 0.001,
		"the arc's centre was solved against Refs/game ref/level.jpg; at 118 the "
			+ "shadows rake 54 degrees down the screen instead of 20"
	)
	assert_almost_eq(
		director.sun_azimuth_arc_degrees, 13.0, 0.001,
		"the arc's half-span is 13 degrees, so the sun travels 69 -> 95 across a "
			+ "phase. Widening it is a Director's taste call, not an edit."
	)
	assert_almost_eq(
		LightingDirectorScript.azimuth_at(82.0, 13.0, 0.0), 69.0, 0.001, "the arc's morning end")
	assert_almost_eq(
		LightingDirectorScript.azimuth_at(82.0, 13.0, 0.5), 82.0, 0.001, "the arc's middle")
	assert_almost_eq(
		LightingDirectorScript.azimuth_at(82.0, 13.0, 1.0), 95.0, 0.001, "the arc's evening end")


## A DIRECTOR WITH NO CLOCK SITS AT THE SOLVED CENTRE.
##
## Which is what keeps every capture that forces a preset, and every other test
## in this file, looking at exactly the frame they were written against. The arc
## is what a RUN adds; it is not a new resting place.
func test_a_director_with_no_clock_aims_at_the_solved_centre() -> void:
	var director := _build()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	director.add_child(sun)
	director._ready()
	director.apply_preset(&"pale_day")
	director._process(0.5)
	assert_almost_eq(
		rad_to_deg(sun.rotation.y), 82.0, 0.001,
		"with no clock to ask, the sun must sit at the arc's centre"
	)


## THE SUN ACTUALLY TRAVELS IT -- read off the light, not off the director.
##
## This is the assertion the old test could not make, and it is the one this
## project keeps discovering it needs: **a value being set is not the same claim
## as a value being applied.** Every number below comes back from
## `DirectionalLight3D.rotation`, which is the thing the renderer reads.
func test_the_sun_travels_the_arc_across_a_daylight_phase() -> void:
	var built := _build_with_sun()
	var director = built[0]
	var sun: DirectionalLight3D = built[1]
	var clock = built[2]
	assert_almost_eq(
		_sun_azimuth_at(director, sun, clock, 0.0, false), 69.0, 0.001, "dawn")
	assert_almost_eq(
		_sun_azimuth_at(director, sun, clock, 0.5, false), 82.0, 0.001, "midday")
	assert_almost_eq(
		_sun_azimuth_at(director, sun, clock, 1.0, false), 95.0, 0.001, "dusk")
	# Monotone, because a sun that took a step backwards would read as the world
	# glitching rather than as the hour passing.
	var previous := -999.0
	for step in range(21):
		var here := _sun_azimuth_at(director, sun, clock, float(step) / 20.0, false)
		assert_true(
			here > previous,
			"the sun went backwards at %d%% of the phase: %.3f after %.3f"
				% [step * 5, here, previous]
		)
		previous = here


## ELEVATION MUST NOT MOVE WHILE AZIMUTH DOES, and that is the whole reason this
## is the affordable change.
##
## Shadow LENGTH is height / tan(elevation), and the derivative of that is savage
## down here -- at 11 degrees a shadow ran 5.1x its caster and the walk lurched.
## Azimuth costs nothing in length: a shadow that turns keeps its mass. If a
## future arc ever reached for the elevation instead, this is what would catch it.
func test_the_arc_turns_the_shadows_without_lengthening_them() -> void:
	var built := _build_with_sun()
	var director = built[0]
	var sun: DirectionalLight3D = built[1]
	var clock = built[2]
	var elevation := 0.0
	for step in range(11):
		_sun_azimuth_at(director, sun, clock, float(step) / 10.0, false)
		var here := rad_to_deg(-sun.rotation.x)
		if step == 0:
			elevation = here
		assert_almost_eq(
			here, 21.5, 0.001,
			"the arc moved the sun's ELEVATION to %.3f at %d%% of the phase" % [here, step * 10]
		)
		assert_almost_eq(here, elevation, 0.0001, "the elevation drifted across the arc")


## THE NIGHT RETURNS THE SUN TO WHERE THE NEXT DAWN OPENS.
##
## Two things fall out of that and both are the point. There is no jump at a phase
## boundary -- a 26-degree step in one frame is a 20-degree step in every shadow
## on screen, which is exactly the pop the eight-second crossfade exists to
## prevent, and far more visible than the exposure fade laid over it. And **every
## one of the seven days opens on the same light**, so day 1's dawn and day 7's
## dawn differ only by the story.
func test_the_night_runs_the_arc_back_so_every_dawn_opens_the_same() -> void:
	var built := _build_with_sun()
	var director = built[0]
	var sun: DirectionalLight3D = built[1]
	var clock = built[2]
	var dusk := _sun_azimuth_at(director, sun, clock, 1.0, false)
	assert_almost_eq(
		_sun_azimuth_at(director, sun, clock, 0.0, true), dusk, 0.001,
		"the night started somewhere the day had not left the sun -- that is a "
			+ "20-degree jump in every shadow in the frame, in one tick"
	)
	assert_almost_eq(
		_sun_azimuth_at(director, sun, clock, 1.0, true), 69.0, 0.001,
		"the night did not hand the next dawn the azimuth the last one opened on"
	)


## THE ARC NEVER LEAVES ITS OWN BAND, at any hour of either phase, however the
## clock is read. A clamp that only holds for well-formed input is not a clamp:
## `WorldClock.advance()` can overshoot a phase boundary inside one frame, and a
## capture harness may hand this a scrubbed time of its own.
func test_the_arc_never_leaves_the_band_it_was_solved_in() -> void:
	var built := _build_with_sun()
	var director = built[0]
	var sun: DirectionalLight3D = built[1]
	var clock = built[2]
	for night in [false, true]:
		for step in range(-4, 25):
			var here := _sun_azimuth_at(director, sun, clock, float(step) / 20.0, night)
			assert_true(
				here >= 69.0 - 0.001 and here <= 95.0 + 0.001,
				"the sun reached %.3f degrees at position %.2f (night=%s), outside 69..95"
					% [here, float(step) / 20.0, str(night)]
			)


## A phase of no length must not divide by it. The clock reports zero duration
## before the schedules are loaded, and RunBoot loads them on the first frame --
## so this is the state the director is genuinely in for one tick of every run.
func test_a_phase_with_no_length_leaves_the_sun_where_it_was() -> void:
	var built := _build_with_sun()
	var director = built[0]
	var sun: DirectionalLight3D = built[1]
	var clock = built[2]
	_sun_azimuth_at(director, sun, clock, 0.25, false)
	var before := rad_to_deg(sun.rotation.y)
	clock.duration = 0.0
	director._process(0.0)
	assert_almost_eq(
		rad_to_deg(sun.rotation.y), before, 0.001,
		"a zero-length phase moved the sun"
	)

# --- blending ---------------------------------------------------------------

func test_a_blend_at_zero_is_the_preset_it_started_from() -> void:
	var blended := LightingDirectorScript.blend(_preset(1.3, 0.001), _preset(0.5, 0.04), 0.0)
	assert_almost_eq(blended.tonemap_exposure, 1.3, 0.0001, "exposure at t=0")
	assert_almost_eq(blended.fog_density, 0.001, 0.0001, "fog at t=0")

func test_a_blend_at_one_is_the_preset_it_is_going_to() -> void:
	var blended := LightingDirectorScript.blend(_preset(1.3, 0.001), _preset(0.5, 0.04), 1.0)
	assert_almost_eq(blended.tonemap_exposure, 0.5, 0.0001, "exposure at t=1")
	assert_almost_eq(blended.fog_density, 0.04, 0.0001, "fog at t=1")

func test_a_blend_halfway_is_halfway() -> void:
	var blended := LightingDirectorScript.blend(_preset(1.0, 0.0), _preset(0.0, 0.10), 0.5)
	assert_almost_eq(blended.tonemap_exposure, 0.5, 0.0001, "exposure halfway")
	assert_almost_eq(blended.fog_density, 0.05, 0.0001, "fog halfway")

## Fog is the one switch that must NOT flip at the midpoint. Fog off is fog at
## density zero, so a fade into fog runs the density up from nothing with the
## switch already on -- flip it halfway instead and the haze appears all at once,
## at half strength, which is the pop the crossfade exists to prevent.
func test_fading_into_fog_turns_it_on_at_once_and_ramps_the_density() -> void:
	var clear := _preset(1.0, 0.02)
	clear.fog_enabled = false
	var thick := _preset(1.0, 0.02)
	thick.fog_enabled = true
	var early := LightingDirectorScript.blend(clear, thick, 0.1)
	assert_true(early.fog_enabled, "the fog switch waited for the midpoint")
	assert_true(
		early.fog_density < thick.fog_density * 0.5,
		"the density did not start from nothing: got %f" % early.fog_density
	)

func test_fading_out_of_fog_ramps_the_density_back_to_nothing() -> void:
	var thick := _preset(1.0, 0.02)
	thick.fog_enabled = true
	var clear := _preset(1.0, 0.02)
	clear.fog_enabled = false
	var late := LightingDirectorScript.blend(thick, clear, 0.9)
	assert_true(
		late.fog_density < thick.fog_density * 0.5,
		"the density did not fall as the fog left: got %f" % late.fog_density
	)

## Shadows have no continuous parameter to ramp -- a shadow is cast or it is not
## -- so this one does flip, and it flips at the midpoint where it is least
## visible rather than at either end where it would land against a full-strength
## look.
func test_the_shadow_switch_flips_at_the_midpoint() -> void:
	var casting := _preset(1.0, 0.0)
	casting.shadows_enabled = true
	var flat := _preset(1.0, 0.0)
	flat.shadows_enabled = false
	assert_true(LightingDirectorScript.blend(casting, flat, 0.4).shadows_enabled, "flipped early")
	assert_false(LightingDirectorScript.blend(casting, flat, 0.6).shadows_enabled, "flipped late")

func test_a_blend_carries_the_identity_of_where_it_is_going() -> void:
	var from := _preset(1.0, 0.0)
	from.id = &"pale_day"
	var to := _preset(0.5, 0.0)
	to.id = &"deep_night"
	assert_eq(
		LightingDirectorScript.blend(from, to, 0.5).id, &"deep_night",
		"a blend should report the preset it is becoming"
	)

# --- crossfading ------------------------------------------------------------

func test_a_crossfade_arrives_after_exactly_its_own_duration() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	director.crossfade_to(&"deep_night", 4.0)
	assert_true(director.is_crossfading(), "it did not start fading")
	director._process(2.0)
	assert_true(director.is_crossfading(), "it arrived at halfway")
	var midway: float = director.environment.tonemap_exposure
	director._process(2.0)
	assert_false(director.is_crossfading(), "it did not arrive")
	assert_almost_eq(
		director.environment.tonemap_exposure,
		director.preset(&"deep_night").tonemap_exposure, 0.0001,
		"it did not land on the preset it was going to"
	)
	var start: float = director.preset(&"pale_day").tonemap_exposure
	var finish: float = director.preset(&"deep_night").tonemap_exposure
	assert_true(
		midway < start and midway > finish,
		"halfway through it was at %f, outside the range %f..%f" % [midway, finish, start]
	)

## The point of the whole mechanism, as one assertion: the frame must never
## change by the whole distance in a single tick.
func test_a_crossfade_never_cuts() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	var before: float = director.environment.tonemap_exposure
	director.crossfade_to(&"deep_night", 6.0)
	director._process(0.016)
	var after: float = director.environment.tonemap_exposure
	var whole: float = absf(director.preset(&"deep_night").tonemap_exposure - before)
	assert_true(
		absf(after - before) < whole * 0.25,
		"one frame moved the exposure %f of the way" % (absf(after - before) / maxf(whole, 0.0001))
	)

func test_crossfading_to_where_it_already_is_does_nothing() -> void:
	var director := _build()
	director.apply_preset(&"nightfall")
	assert_false(director.crossfade_to(&"nightfall", 4.0), "it faded to itself")
	assert_false(director.is_crossfading(), "it started a fade to where it already was")

func test_a_second_crossfade_starts_from_where_the_frame_actually_is() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	director.crossfade_to(&"deep_night", 4.0)
	director._process(2.0)
	var interrupted: float = director.environment.tonemap_exposure
	director.crossfade_to(&"whiteout", 4.0)
	director._process(0.0)
	assert_almost_eq(
		director.environment.tonemap_exposure, interrupted, 0.0001,
		"interrupting a fade jumped the frame back to where the first one started"
	)

func test_applying_a_preset_outright_abandons_a_fade() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	director.crossfade_to(&"deep_night", 10.0)
	director.apply_preset(&"whiteout")
	assert_false(director.is_crossfading(), "a snap left the fade running underneath it")
	assert_almost_eq(
		director.environment.tonemap_exposure,
		director.preset(&"whiteout").tonemap_exposure, 0.0001,
		"the snap did not land"
	)

# --- the clock drives it ----------------------------------------------------

func test_the_clock_advancing_a_day_changes_the_light() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	_bus.emit_event(&"clock.day_started", 5)
	assert_true(director.is_crossfading(), "day 5 dawned and the light did not move")
	assert_eq(director.target_preset_id(), &"sunrise", "day 5 is SUNRISE -- twenty warm minutes")

func test_nightfall_changes_the_light_to_the_days_own_night() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	_bus.emit_event(&"clock.night_started", 6)
	assert_eq(
		director.target_preset_id(), &"whiteout",
		"GDD section 4 day 6 is NIGHTFALL -> WHITEOUT: the storm arrives with the dark"
	)

func test_a_day_outside_the_run_leaves_the_light_where_it_is() -> void:
	var director := _build()
	director.apply_preset(&"nightfall")
	_bus.emit_event(&"clock.day_started", 99)
	assert_eq(director.target_preset_id(), &"nightfall", "a day that does not exist moved the light")

func test_dropping_the_bus_stops_the_clock_driving_it() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	director.set_event_bus(null)
	assert_eq(_bus.subscriber_count(&"clock.day_started"), 0, "it is still subscribed")
	_bus.emit_event(&"clock.day_started", 7)
	assert_false(director.is_crossfading(), "a detached director still heard the clock")

# --- the air ----------------------------------------------------------------

## DEPTH FOG, NOT EXPONENTIAL, AND THE REASON IS THE BOOM.
##
## The rig is orthographic 90 m back, so the whole farmstead sits between about
## 69 m and 100 m from the camera. Over that stretch 1 - exp(-density * depth) is
## nearly a straight line that starts well above zero -- fog enough to blue the
## far tree already greys the near one, and the near one is the one that has to
## stay black. A depth window can begin its ramp in front of the nearest thing in
## the frame and end it past the furthest, which is what aerial perspective is.
func test_the_air_is_a_window_rather_than_a_curve() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	var env := director.environment
	var preset := director.preset(&"pale_day")
	assert_not_null(env, "no Environment")
	if env == null or preset == null:
		return
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH, "the fog is not in depth mode")
	assert_almost_eq(env.fog_depth_begin, preset.fog_depth_begin, 0.0001, "fog begins")
	assert_almost_eq(env.fog_depth_end, preset.fog_depth_end, 0.0001, "fog ends")
	assert_almost_eq(env.fog_light_energy, preset.fog_light_energy, 0.0001, "fog brightness")


## The sky is per-preset because PALE DAY and DEEP NIGHT cannot share one, and it
## is built in code for the same reason everything else here is: no colour
## literal may end up in scenes/main.tscn.
func test_the_director_builds_a_gradient_sky_out_of_the_preset() -> void:
	var director := _build()
	director.apply_preset(&"deep_night")
	var env := director.environment
	var preset := director.preset(&"deep_night")
	assert_not_null(env, "no Environment")
	if env == null or preset == null:
		return
	assert_eq(env.background_mode, Environment.BG_SKY, "the background is not a sky")
	assert_not_null(env.sky, "no Sky resource was built")
	if env.sky == null:
		return
	# A ShaderMaterial rather than a ProceduralSkyMaterial SINCE THE AURORA: the
	# stock material cannot carry stars or a curtain, and a sky is the only thing
	# in the engine that is genuinely at infinity, enormous and free of parallax.
	# The assertion below is unchanged in what it demands -- the preset's own
	# zenith and horizon must reach the sky -- only in where it reads them from.
	# See assets/shaders/aurora_sky.gdshader, which reproduces this material's
	# gradient formula so that none of the six moved.
	var material := env.sky.sky_material as ShaderMaterial
	assert_not_null(material, "the Sky carries no ShaderMaterial")
	if material == null:
		return
	assert_eq(
		material.shader.resource_path, "res://assets/shaders/aurora_sky.gdshader",
		"the Sky is not on the project's own sky shader"
	)
	assert_eq(
		material.get_shader_parameter("sky_top_color"), preset.sky_zenith_color,
		"the zenith is not the preset's")
	assert_eq(
		material.get_shader_parameter("sky_horizon_color"), preset.sky_horizon_color,
		"the horizon is not the preset's")


## The sky must not start lighting the world. Every world shader declares
## `ambient_light_disabled` and the character's fill is an authored colour, so
## switching the background from a flat colour to a sky has to leave the ambient
## source exactly where it was -- otherwise the figure is lit by the sky and the
## whole of tests/art/test_character_lighting.gd is measuring the wrong number.
func test_the_new_sky_does_not_take_over_the_characters_fill() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	var env := director.environment
	assert_not_null(env, "no Environment")
	if env == null:
		return
	assert_eq(
		env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR,
		"the ambient now comes from the sky, so the character's authored fill is inert"
	)
	assert_almost_eq(
		env.ambient_light_sky_contribution, 0.0, 0.0001,
		"the sky contributes to the ambient, which reaches the character and nothing else"
	)


## Style document section 39, Forward+ only, and the number it is emphatic
## about. The froxel volume is only 64 m deep by default -- the entire farmstead
## is further away than that -- so the length is the difference between a little
## cold moisture in the air and nothing at all.
func test_the_volumetric_air_reaches_as_far_as_the_camera_can_see() -> void:
	var director := _build()
	director.apply_preset(&"whiteout")
	var env := director.environment
	var preset := director.preset(&"whiteout")
	if env == null or preset == null:
		return
	assert_eq(env.volumetric_fog_enabled, preset.volumetric_fog_enabled, "the volumetric switch")
	# The length is asserted whether or not the switch is on. All six ship with it
	# OFF -- it lifts the nearest tree in the frame out of black, which is the one
	# thing the depth fog exists to preserve -- so the day someone turns it on, the
	# volume has to already reach the scene rather than sit entirely in front of it.
	assert_true(
		env.volumetric_fog_length >= preset.fog_depth_end,
		"the volumetric air is %.0f m deep against a fog window that ends at %.0f m, so "
			% [env.volumetric_fog_length, preset.fog_depth_end]
			+ "the far half of the frame is outside it"
	)
	assert_almost_eq(
		env.volumetric_fog_density,
		preset.volumetric_fog_density if preset.volumetric_fog_enabled else 0.0,
		0.000001,
		"disabled global volumetric density"
	)


func test_local_snow_fog_opens_only_the_froxel_buffer_not_global_haze() -> void:
	var director := _build()
	director.apply_preset(&"whiteout")
	var env := director.environment
	var preset := director.preset(&"whiteout")
	if env == null or preset == null:
		return
	assert_false(preset.volumetric_fog_enabled, "the fixture no longer proves local-only air")
	_bus.emit_event(&"rendering.local_volumetric_fog_changed", {"active": true})
	assert_true(env.volumetric_fog_enabled, "local snow fog did not open the froxel buffer")
	assert_almost_eq(
		env.volumetric_fog_density,
		0.0,
		0.000001,
		"opening a local volume also revived the preset's whole-world haze"
	)
	_bus.emit_event(&"rendering.local_volumetric_fog_changed", {"active": false})
	assert_false(env.volumetric_fog_enabled, "the volumetric pass stayed on after local snow fog cleared")


func test_a_blend_carries_the_air_and_the_sky_with_it() -> void:
	var from := _preset(1.0, 0.0)
	from.fog_depth_begin = 60.0
	from.fog_depth_end = 100.0
	from.fog_light_energy = 1.0
	from.sky_zenith_color = Color(0.0, 0.0, 0.0)
	from.sky_horizon_color = Color(0.0, 0.0, 0.0)
	from.volumetric_fog_enabled = true
	from.volumetric_fog_density = 0.0
	var to := _preset(1.0, 0.0)
	to.volumetric_fog_enabled = true
	to.fog_depth_begin = 80.0
	to.fog_depth_end = 140.0
	to.fog_light_energy = 0.9
	to.sky_zenith_color = Color(1.0, 1.0, 1.0)
	to.sky_horizon_color = Color(1.0, 1.0, 1.0)
	to.volumetric_fog_density = 0.002
	var halfway := LightingDirectorScript.blend(from, to, 0.5)
	assert_almost_eq(halfway.fog_depth_begin, 70.0, 0.0001, "the fog window's near edge")
	assert_almost_eq(halfway.fog_depth_end, 120.0, 0.0001, "the fog window's far edge")
	assert_almost_eq(halfway.fog_light_energy, 0.95, 0.0001, "the fog's brightness")
	assert_almost_eq(halfway.sky_zenith_color.r, 0.5, 0.0001, "the zenith")
	assert_almost_eq(halfway.sky_horizon_color.b, 0.5, 0.0001, "the horizon")
	assert_almost_eq(halfway.volumetric_fog_density, 0.001, 0.000001, "the volumetric air")


# --- the light the world takes ----------------------------------------------

## CONCERN 3 OF THE CLOCK/LIGHTING REPORT, WIRED.
##
## `cel_band_threshold` and `cel_band_softness` were authored on all six presets
## and reached nothing: TerrainRenderer and CelPainter set the uniforms once at
## startup from their own exports. The director now publishes them, and publishes
## a third value with them -- the colour the LIT band is multiplied by, which is
## the only way warm light reaches the snow.
func test_the_director_publishes_the_band_the_preset_asks_for() -> void:
	var director := _build()
	director.apply_preset(&"whiteout")
	var whiteout := director.preset(&"whiteout")
	if whiteout == null:
		return
	assert_almost_eq(
		director.cel_band_threshold(), whiteout.cel_band_threshold, 0.0001, "the band threshold"
	)
	assert_almost_eq(
		director.cel_band_softness(), whiteout.cel_band_softness, 0.0001, "the band softness"
	)


## The tint is LUMINANCE-PRESERVING, and that is the whole of why it is safe.
##
## A raw multiply by an amber light darkens snow as much as it warms it, and the
## exposure would have to be re-tuned to pay for it. Normalising the light colour
## to unit luminance first means the tint rotates the hue of the lit band and
## leaves its brightness exactly where the preset put it -- so `world_light_
## strength` is a hue knob and nothing else, and it cannot quietly darken a look.
func test_an_untinted_preset_leaves_the_palette_exactly_where_it_is() -> void:
	var director := _build()
	director.apply_preset(&"pale_day")
	var tint := director.world_light_tint()
	assert_almost_eq(tint.r, 1.0, 0.0001, "red")
	assert_almost_eq(tint.g, 1.0, 0.0001, "green")
	assert_almost_eq(tint.b, 1.0, 0.0001, "blue")


func test_the_warm_light_warms_without_dimming() -> void:
	var director := _build()
	director.apply_preset(&"sunrise")
	var tint := director.world_light_tint()
	assert_true(
		tint.r > 1.0 and tint.b < 1.0,
		"SUNRISE's world light is #%s, which is not warmer than white" % tint.to_html(false)
	)
	var luma := 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b
	assert_almost_eq(
		luma, 1.0, 0.002,
		"the warm tint carries a luminance of %f, so it does not only shift the hue -- it "
			% luma
			+ "changes the brightness the preset's exposure was tuned against"
	)


## The push. `set_shader_parameter` on a uniform nothing reads is silent, so the
## only honest gate is the one that reads the value back off a material.
func test_applying_a_preset_reaches_every_solid_in_the_world() -> void:
	var director := _build()
	director.apply_preset(&"sunrise")
	var sunrise := director.preset(&"sunrise")
	if sunrise == null:
		return
	var painter := CelPainter.new()
	var material := painter.material_for(load(LightingDirectorScript.PALETTE_PATH).snow_tones[0])
	assert_almost_eq(
		float(material.get_shader_parameter("band_threshold")),
		sunrise.cel_band_threshold + CelPainter.SOLID_BAND_OFFSET, 0.0001,
		"a material built after the preset landed still carries the shader's own default"
	)
	var tint: Vector3 = material.get_shader_parameter("light_tint")
	assert_true(tint.x > 1.0, "the warm light did not reach a solid: got %s" % tint)


# --- the warm accent --------------------------------------------------------

## Art Bible section 4.2 puts the warm OmniLight's strength on the preset,
## because a lit window is worth nothing at noon and everything at midnight.
## Nothing warm has been placed in the world yet, so this is the seam a stove or
## a window reads rather than a value with a consumer.
func test_the_warm_accent_is_published_for_whatever_burns() -> void:
	var director := _build()
	director.apply_preset(&"deep_night")
	assert_almost_eq(
		director.warm_accent_energy(), director.preset(&"deep_night").warm_accent_energy, 0.0001,
		"the director does not publish the warm accent the preset asks for"
	)
