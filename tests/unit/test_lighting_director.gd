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

## THE AZIMUTH, WHICH WAS SOLVED AND HAD NOTHING DEFENDING IT.
##
## Elevation decides how LONG a shadow is; azimuth decides which way it runs
## across the screen, and the camera never rotates, so a ground direction has
## exactly one screen direction. 82 degrees was derived from the rake measured
## off `Refs/game ref/level.jpg` -- the farmhouse throws its shadow left and 16
## degrees down, the well house left and 13 -- and verified by screenshot against
## the painting. At the previous 118 the rake came out at 54 degrees: shadows
## that fall DOWN the frame instead of across it.
##
## It is pinned here because nothing pinned it. A value that took a screenshot
## comparison to find, and that no test defends, is one careless merge from being
## lost silently -- and a 36-degree swing in every shadow in the game is the kind
## of regression a reviewer reads as "the art changed" rather than as a defect.
##
## It stays on the director rather than on the six presets deliberately: the sun
## rises in one place over this valley, and a preset that moved it would be a
## different location rather than a different hour.
func test_the_sun_keeps_the_azimuth_the_reference_painting_was_solved_for() -> void:
	var director := _build()
	assert_almost_eq(
		director.sun_azimuth_degrees, 82.0, 0.001,
		"the azimuth was solved against Refs/game ref/level.jpg; at 118 the shadows "
			+ "rake 54 degrees down the screen instead of 20"
	)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	director.add_child(sun)
	director._ready()
	director.apply_preset(&"pale_day")
	assert_almost_eq(
		rad_to_deg(sun.rotation.y), director.sun_azimuth_degrees, 0.001,
		"the director does not actually aim the sun at the azimuth it declares"
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
