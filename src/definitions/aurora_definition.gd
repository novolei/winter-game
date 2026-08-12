class_name AuroraDefinition
extends Resource

## One aurora, as data. When it may appear, how often, how long it lasts, what
## the curtain looks like, and how much of its colour reaches the ground.
##
## Binding rule 4: adding or retuning an aurora is a `.tres` under `data/aurora/`
## and no `.gd` change. `AuroraSystem` scans that directory BY TYPE and holds no
## list of ids anywhere, the same way `WeatherSystem` scans `data/weather/`.
##
## ---------------------------------------------------------------------------
## IT ANNOUNCES ITSELF ON THE GROUND, AND THAT IS THE POINT
## ---------------------------------------------------------------------------
## The camera never looks up. It is a fixed orthographic 45-degree rig showing
## the ground, and under a parallel projection a sky shader can only ever produce
## one flat colour anyway -- so a curtain that lived only in the sky would be a
## feature nobody ever saw.
##
## So the design is in two halves and this resource carries both:
##
##   THE TELL is on the ground. An aurora does not merely sit in the sky, it
##     LIGHTS THE WORLD BENEATH IT. `ground_cast_color` and
##     `ground_cast_strength` rotate the hue of the world's LIT cel band -- the
##     same channel SUNRISE already uses for its amber -- so the snow goes teal
##     at the ordinary game framing with no camera move at all. That is what the
##     player notices.
##
##   THE PAYOFF is in the sky. Everything in the `Curtain` group below drives
##     assets/shaders/aurora_sky.gdshader, for the moment he does look up.
##
## ---------------------------------------------------------------------------
## THE CAST IS LIGHT, NOT ALBEDO
## ---------------------------------------------------------------------------
## Green and teal are in neither the 12-colour table nor Art Bible rule 12's warm
## allowance. Neither table governs them: the twelve govern the colour of a
## SURFACE, and sky, fog, ambient and light colour are atmosphere -- the boundary
## the Director recorded against `Docs/style optimization.md`. An aurora is sky
## and is its own light source.
##
## The ground cast obeys the same boundary from the other side.
## `LightingDirector` normalises it to unit luminance before it reaches any
## shader, so it is a pure hue rotation: it cannot brighten the snow, it cannot
## darken it, and it cannot push the frame past the bloom threshold. It reaches
## the LIT band only; the shade band stays the palette colour it was chosen as,
## which is Art Bible section 4.1 and is also what a cold night under a green sky
## actually looks like.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Rarity")
## THE CHANCE, DRAWN ONCE PER ELIGIBLE NIGHT.
##
## The run is seven days and only three of its nights are dark enough to qualify
## (see `allowed_night_presets`), so this is not the probability of seeing one --
## it is the probability per opportunity. At the shipped 0.20 with `once_per_run`
## on, a run contains an aurora a little under half the time and never twice.
##
## It has to be rare or it is not a surprise, and it has to be possible or it is
## content nobody experiences. This is the dial for that argument and it is one
## line of one file.
@export var chance_per_night := 0.20

## At most one showing in a seven-day run. The second one would not be a
## surprise, and it would make the first one read as weather.
@export var once_per_run := true

## WHICH NIGHTS CAN CARRY ONE, by the lighting preset the day schedule names for
## that night rather than by the night number. A schedule edit that makes another
## night dark therefore makes it eligible with no change here.
##
## `deep_night` only, as shipped: nights 1 and 2 wear NIGHTFALL, which is a dusk
## and is too bright to hold a curtain, and nights 6 and 7 are WHITEOUT, where
## the sky is the storm.
@export var allowed_night_presets: Array[StringName] = [&"deep_night"]

## Refuse a night that already has weather on it, and fade if weather arrives.
## An aurora inside a snow fog is a green smear; more to the point, the sky is
## the game's forecast UI (GDD section 7) and a curtain painted over a tell would
## be lying to the player about what is coming.
@export var requires_clear_weather := true

## Where in the night it begins, as a fraction of the night's own length. Never
## at the top of the night: the player has just been driven indoors by
## NIGHTFALL, and something that is already there when the dark arrives reads as
## part of the preset rather than as an event.
@export var start_window := Vector2(0.18, 0.46)

@export_group("Arc")
## THE RISE IS LONG ON PURPOSE. It is the whole of 惊喜地瞥见: the snow has to go
## green slowly enough that noticing it is the player's own act rather than a
## thing that happened to the screen. A cast that snapped on would read as a
## lighting fault, which is the same argument LightingDirector makes for
## crossfading the six presets rather than cutting between them.
@export var rise_seconds := 34.0
## How long it holds, drawn per showing. Against a 420-second night the shipped
## range plus the ramps is between two and three minutes -- a visit, not the
## weather for the evening.
@export var hold_seconds := Vector2(70.0, 130.0)
@export var fall_seconds := 42.0

@export_group("Curtain")
## WHERE IT HANGS, as a world compass bearing in degrees measured from -Z toward
## +X -- the same convention `CameraRig.yaw_degrees` uses. The fixed rig looks
## along +35 degrees, so this range brackets the direction an upward lean would
## find while still varying between showings.
##
## `AuroraSystem.bearing_degrees()` publishes whichever was drawn, so a look-up
## cue can aim at the curtain that is actually there rather than at a constant.
@export var bearing_degrees := Vector2(8.0, 62.0)

## The half-width of the curtain, in degrees of horizon. 55 spans 110 degrees --
## most of the visible half of the sky, which is what 巨幕 asks for.
@export var span_degrees := 55.0

## Its lower hem and its upper reach, in degrees of elevation. LOW AND SHALLOW:
## 挂在远远天际 puts it on the horizon at a great distance, never overhead.
@export var base_elevation_degrees := 6.0
@export var top_elevation_degrees := 32.0

## The three overlapping curtains, brightest first. Not one sheet -- the
## reference frame is several bands at different brightnesses and depths, and one
## band with a gradient in it is a coloured fog.
@export var band_colors: Array[Color] = []
@export var band_opacity := Vector3(1.0, 0.72, 0.45)
## How far up each band is lifted, as a fraction of the first band's own depth,
## and how far it is offset along the horizon. Together these are what makes the
## three read as different distances rather than as one sheet drawn three times.
@export var band_lift := Vector3(0.0, 0.25, 0.50)
@export var band_offset := Vector3(0.0, -0.31, 0.47)

## How much of the sky the whole thing is allowed to take at full strength.
@export var sky_opacity := 1.0

## THE STRIATIONS, WHICH ARE THE SIGNATURE. See the shader: brightness is a
## function of the HORIZONTAL angle alone, which is what makes the rays vertical
## and coherent from hem to crown.
@export var ray_frequency := 5.4
@export var ray_sharpness := 2.2
@export var ray_shear := 0.55
## How fast the ray field slides along the horizon. Slow: the three bands drift
## at this times 1, 1.618 and 0.577, and the ratios are irrational so the figure
## has no period a session could contain.
@export var drift_speed := 0.035

@export_group("Ground cast")
## THE COLOUR THE SNOW TAKES. Luminance-normalised by `LightingDirector` before
## it reaches any shader, so this is a HUE and its brightness is ignored -- a
## dark teal and a bright one of the same hue produce the same cast.
@export var ground_cast_color := Color(0.5, 0.84, 0.75, 1.0)

## How far toward it the lit band goes at the aurora's peak, 0..1. Measured
## rather than guessed: see tools/capture_aurora.gd, which prints the rendered
## snow hex with the cast off and on.
@export var ground_cast_strength := 0.30

## How much of that rotation the CHARACTER's ambient fill takes.
##
## The two lighting rigs are the most surprising thing about this project --
## `LightingPreset`'s header is the long version. The world is drawn by cel
## shaders that read nothing from a light but its shadow term; the character is
## the one stock PBR material in the game and is lit by the sun and the ambient.
## A cast that greened the snow and left the man untouched would move half the
## picture, and with no HUD to contradict it that reads as art direction.
##
## Below 1.0 because he is a body under the sky rather than the snow beneath it,
## and because his coat is the frame's only blue-grey and should not go teal.
@export var character_fill_share := 0.55


## The curtain's three colours, always three, whatever the resource holds. A
## definition authored with fewer repeats its last; one authored with none is a
## curtain with no colour, so it falls back to the ground cast's own hue rather
## than drawing black.
func band_color(index: int) -> Color:
	if band_colors.is_empty():
		return ground_cast_color
	return band_colors[clampi(index, 0, band_colors.size() - 1)]


## Whether this aurora may appear on a night wearing `preset`. An empty list
## means "any night", which is a legal thing to author and is not what ships.
func allows_night(preset: StringName) -> bool:
	if allowed_night_presets.is_empty():
		return true
	return allowed_night_presets.has(preset)


## The whole arc, in seconds, for a given hold. What a caller needs to know
## whether the showing fits inside the night it was drawn for.
func total_seconds(hold: float) -> float:
	return maxf(rise_seconds, 0.0) + maxf(hold, 0.0) + maxf(fall_seconds, 0.0)
