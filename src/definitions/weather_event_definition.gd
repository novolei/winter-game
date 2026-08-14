class_name WeatherEventDefinition
extends Resource

## One weather event, in three phases: tell, active, fade.
## The tell phase is mandatory -- an unannounced storm is unfair, not hard.
##
## ---------------------------------------------------------------------------
## THE EVENT IS A STATE; THE TELL IS AN EVENT. THEY ARE NOT INTERCHANGEABLE.
## ---------------------------------------------------------------------------
## Read this before wiring anything to the weather, because getting it backwards
## is the defect this system was designed around.
##
## `weather.tell_started` is a MOMENT: it fires once, on a crossing, and it is
## the right shape for a sound, a bird, a line of dialogue. It is the WRONG shape
## for "how bad is it right now" -- a consumer that tried to reconstruct the
## current weather by remembering past events would be rebuilding a state machine
## from its own transitions, and would be wrong for the whole of the arrival ramp.
##
## The crows found this from the other side: `CrowFlock`'s header records that it
## refused to drive its flock from `wind.gust_started`, because that fires on the
## profile's own 0.30 crossing and never again as the gust builds, so a flock
## refusing it there would sit out the 0.798 peak. The same rule holds here.
##
## So: subscribe for the tell, POLL for the weather --
## `ServiceRegistry.get_service(&"weather")` publishes `phase()`,
## `tell_progress()`, `intensity()` and `visibility()`, all continuous, all
## sampled.
##
## ---------------------------------------------------------------------------
## HOW AN EVENT REACHES THE PICTURE
## ---------------------------------------------------------------------------
## It does not drive anything itself. Every field below is read by
## `src/systems/weather_system.gd`, which owns the arithmetic, and every one of
## them lands on a hook that already existed:
##
##   `lighting_preset`         -> LightingDirector.crossfade_to()
##   `wind_map`                -> WindSystem.set_map()          (crossfaded)
##   `wind_speed_multiplier`   -> WindSystem.set_gale_multiplier()
##   `snowfall_rate`           -> Snowfall.set_snowfall_rate()
##   `vfx_profile`             -> WeatherVfxLayer (continuous service polling)
##   `fog_profile`             -> WeatherSnowFog (continuous service polling)
##   `stat_modifiers`          -> SurvivalSystem.push_modifier()
##   `tell.flushes_wildlife`   -> CrowFlock.scatter()
##
## which is why adding a weather is adding a `.tres` and nothing else (binding
## rule 4). `WeatherSystem` scans `data/weather/` for this type; it holds no list
## of ids anywhere.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Timing")
## Seconds of warning before the event lands. Spec floor: 20-40s.
##
## The FLOOR is enforced twice, deliberately. Here it is a default a designer can
## read; in `WeatherSystem.minimum_tell_seconds` it is a clamp no data can get
## under, because a tell of zero seconds is the one authoring mistake that
## silently breaks the design pillar and looks like a tuning value while it does.
@export var tell_duration_range := Vector2(20.0, 40.0)
@export var active_duration_range := Vector2(60.0, 180.0)
@export var fade_duration := 15.0

@export_group("Tell")
## THE WARNING. Null is legal in the type system and illegal in this game --
## `tests/unit/test_weather.gd` fails any shipped event without one, and
## `WeatherSystem` still runs a bare timed tell so that a missing resource is a
## quiet warning rather than a storm that appears out of nothing.
@export var tell: WeatherTell = null

@export_group("Effects")
## StatModifier, not Modifier: a bare Modifier carries no target, so a file
## with three of them could not say which stat each one hits.
##
## Pushed with the EVENT'S id as the source rather than the modifier's own, so
## that `remove_source(event.id)` takes every one of them off again when the
## weather clears. A modifier that outlived its weather would compound the next
## time the same event was drawn -- see `NightExposure._apply()`, which is the
## same hazard written down.
@export var stat_modifiers: Array[StatModifier] = []

## How far the frame can be seen through, as a multiplier on clear air. Below 1
## is a storm, above 1 is 短暂放晴's moving window. Published as state by
## `WeatherSystem.visibility()`; the fog that would make it true belongs to the
## lighting preset, so today this is a readout for whoever plans a route and a
## seam for Wave 5's threats.
@export var visibility_multiplier := 1.0

## Scales what a strength of 1.0 means in metres. Lands on
## `WindSystem.set_gale_multiplier()`, which makes the wind BITE harder rather
## than blow more often -- the profile owns how often, and `wind_map` below is
## how an event changes that.
@export var wind_speed_multiplier := 1.0

## How hard it is snowing while this weather holds, 0 .. 1. Negative means
## "leave the sky alone", so an event that is only about the wind does not have
## to have an opinion about the snow.
@export var snowfall_rate := -1.0

## The ground-depth model for this event.  WeatherSystem publishes this
## resource with its continuous applied snowfall scalar; SnowField consumes it
## at a fixed cadence.  A new weather changes ground accumulation by assigning
## a response `.tres`, never by adding an event-name branch in code.
@export var snow_response: SnowResponseDefinition = null

@export_group("Look")
## The event-specific air signature layered on top of the shared snow, wind and
## lighting. The profile is deliberately only visual: it cannot alter the
## survival model, visibility, snowfall rate or wind strength.
@export var vfx_profile: WeatherVfxProfile = null

## Optional middle-distance snow veil. It is separate from the particle accent
## because its density, world-space noise and camera depth gates are volumetric
## concerns. Null is the exact, allocation-free meaning of "this weather has no
## local mist"; adding one remains a `.tres` authoring choice.
@export var fog_profile: WeatherFogProfile = null

## Which of Art Bible section 4.2's six looks this weather wears. Empty means
## the sky is left wherever the tell put it -- see `WeatherTell.lighting_preset`,
## which explains why that is a shape and not an omission.
@export var lighting_preset: StringName = &""

## How long the sky takes to land on that look once the weather arrives.
## Matched to `LightingDirector.crossfade_seconds` by default.
@export var lighting_fade_seconds := 8.0

@export_group("Air")
## The wind this weather blows, as a `WindMap` -- one `.tres` under
## `data/weather/`. Null leaves the wind following the sky through the default
## map, which is what an event with no opinion about the wind should do.
##
## A MAP AND NOT A PROFILE. `WindSystem.set_profile()` snaps and takes the wheel
## for ever; `set_map()` crossfades and does not. The whole argument is in
## `WeatherTell.wind_map`, and it is the reason 风向突变 -- an event whose entire
## content is the heading changing -- can be expressed at all.
@export var wind_map: WindMap = null

@export_group("Beacons")
@export var extinguishes_beacons := false
@export var min_beacons_extinguished := 0


## Whether this event moves the snowfall in either of its phases. Asked before
## the weather system takes the wheel of the sky's rate, because that takeover is
## one-way (`Snowfall.set_snowfall_rate()` sets a permanent override) and should
## not happen for an event that never had anything to say about the snow.
func changes_snowfall() -> bool:
	if snowfall_rate >= 0.0:
		return true
	return tell != null and tell.changes_snowfall()


## Whether this event moves the wind's bite in either phase.
func changes_wind_bite() -> bool:
	if not is_equal_approx(wind_speed_multiplier, 1.0):
		return true
	return tell != null and not is_equal_approx(tell.wind_speed_multiplier, 1.0)
