class_name WeatherTell
extends Resource

## THE WARNING A WEATHER GIVES BEFORE IT ARRIVES, AS DATA.
##
## GDD section 7's iron law, quoted rather than paraphrased:
##
##   铁律：所有事件必须先预兆再落地。天空就是天气预报 UI——玩家读天色决定
##   "再往前走一段"还是"现在掉头"。无预警的风暴不是难度，是不公平。
##
## Every event announces itself first. The sky IS the forecast UI, because this
## game has no HUD -- the player reads the weather and decides whether to press
## on or turn back, and a storm with no warning is not difficulty, it is
## unfairness.
##
## ---------------------------------------------------------------------------
## WHY THIS IS ITS OWN RESOURCE
## ---------------------------------------------------------------------------
## DEFERRED W3-4: "A weather event's tell has a duration but no sound, visual, or
## lighting hook -- and the mandatory tell is a design pillar. Not expressible in
## data yet." `WeatherEventDefinition.tell_duration_range` said HOW LONG the
## warning lasted and nothing at all about what the warning WAS, so the pillar
## was a comment rather than a mechanism.
##
## This is the missing half. A tell names four channels, and each one is a field
## rather than a magic string, so a mistyped cue is a red test and not a silent
## nothing:
##
##   LIGHT   `lighting_preset` + `lighting_lead` -- the sky starts moving toward
##           the coming weather before the weather is here.
##   AIR     `wind_map` and `wind_speed_multiplier` -- the wind rises, or drops.
##   SNOW    `snowfall_rate` -- the fall thickens, or thins to an unnatural
##           stillness.
##   LIFE    `flushes_wildlife` -- birds leaving the wire. The oldest storm
##           warning there is, and it already exists (`CrowFlock.scatter`).
##
## plus `sound`, which is a NAME and not a stream: Wave 3's audio task owns
## playback, and this file must not grow an AudioStream field that would make the
## two tasks fight over the same asset. The name is published in the
## `weather.tell_started` payload for whoever subscribes.
##
## ---------------------------------------------------------------------------
## THE ONE RULE A TELL MUST OBEY, AND WHY IT IS CHECKED
## ---------------------------------------------------------------------------
## AT LEAST ONE SILENT CHANNEL. A tell carried only by `sound` is inaudible in a
## headless capture, inaudible before the audio task lands, and inaudible to a
## player with the volume down -- and the pillar says the player must ALWAYS get
## the chance to read the sky. `has_silent_cue()` is that rule, and
## `tests/unit/test_weather.gd` runs it over every shipped event.
##
## Note what is deliberately NOT counted as a silent cue: `flushes_wildlife`.
## Crows are daylight-only by design (`CrowFlock` refuses to land at night and
## scatters at nightfall), so a tell that leaned on the birds would announce
## nothing at all after dark -- when the weather matters most. The birds are a
## bonus on top of a cue that works at midnight, never the cue itself.

## The cue an audio subscriber plays. A NAME, not a stream -- see the header.
## Empty means the tell is silent, which is allowed as long as it is visible.
@export var sound: StringName = &""

@export_group("Light")

## The look the sky leans toward during the warning. Empty leaves the light
## alone, which is allowed for an event whose tell is loud in another channel.
##
## IT MUST NOT EQUAL THE EVENT'S OWN `lighting_preset`, and that is an engine
## constraint rather than a taste: `LightingDirector.crossfade_to()` REFUSES a
## fade to the preset it is already fading to, so a tell leaning at the event's
## own look would own the arrival as well and the event's own fade duration
## would be silently ignored. Two honest shapes:
##
##   * lean at an INTERMEDIATE look during the tell, then land on the event's
##     (blizzard: `nightfall`, then `whiteout`);
##   * lean at the final look and leave the event's `lighting_preset` EMPTY,
##     which reads as "the tell owns the sky" (snow fog, freezing rain).
@export var lighting_preset: StringName = &""

## How far toward `lighting_preset` the sky has travelled when the weather
## lands, 0 .. 1. The crossfade is started at `tell_seconds / lighting_lead`, so
## 1.0 arrives exactly with the weather and 0.4 is still only two-fifths of the
## way there when it does -- the light going on changing THROUGH the arrival,
## which is what makes a front read as a thing passing over rather than a state
## being switched.
@export_range(0.05, 1.0, 0.01) var lighting_lead := 0.5

@export_group("Air")

## The wind blowing during the warning, as a `WindMap` -- one `.tres` under
## `data/weather/`.
##
## A MAP RATHER THAN A PROFILE, and the reason is a hard one.
## `WindSystem.set_profile()` SNAPS: it adopts immediately and re-settles the
## model at the same clock, so a still night forced to a gale steps roughly 0.5
## in strength in one frame. `WindSystem.set_map()` does not -- it only clears
## the system's memory of which sky it last resolved, so the next frame
## re-resolves through the map and CROSSFADES over `profile_response_seconds`.
## Same data, same one call, no step. See `WeatherEventDefinition.wind_map`.
@export var wind_map: WindMap = null

## Scales what a strength of 1.0 means in metres -- `WindSystem`'s gale
## multiplier. Above 1 the wind BITES harder without blowing more often, which
## is the half of "风声升高" a profile cannot express on its own.
@export var wind_speed_multiplier := 1.0

@export_group("Snow")

## How hard it is snowing during the warning, 0 .. 1. NEGATIVE means "leave the
## sky alone", which is the default, because most tells are not about the snow.
##
## Zero is a real and important value: 寒流's entire tell is 空气变得极静, and a
## snowfall that stops dead while the wind dies is the most legible warning in
## the game with no light change, no sound and no birds.
@export var snowfall_rate := -1.0

@export_group("Life")

## Whether the birds go up. `CrowFlock.scatter()` already takes a cause and
## already publishes `wildlife.crows_scattered`, so this costs one call and
## nothing else -- but see the header for why it never counts as the cue.
@export var flushes_wildlife := false


## Whether this tell says anything a player can SEE, with the sound muted and
## every crow asleep. The pillar, as a predicate.
func has_silent_cue() -> bool:
	return lighting_preset != &"" \
		or wind_map != null \
		or not is_equal_approx(wind_speed_multiplier, 1.0) \
		or snowfall_rate >= 0.0


## Whether this tell moves the snowfall at all. Kept as a method rather than
## read as `snowfall_rate >= 0.0` at four call sites, because the sentinel is the
## kind of convention that gets copied wrong once and then means nothing.
func changes_snowfall() -> bool:
	return snowfall_rate >= 0.0
