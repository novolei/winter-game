class_name AmbienceLayer
extends Resource

## ONE VOICE OF THE VALLEY, AS DATA.
##
## The wind bed is not a loop with a volume knob on it. It is several layers,
## each of which is only present across a WINDOW of the thing that drives it --
## and the windows are what make the bed a reading rather than a backdrop.
##
## ---------------------------------------------------------------------------
## WHY A WINDOW AND NOT A CURVE
## ---------------------------------------------------------------------------
## A single loop whose gain tracks wind strength is the fastest way to make a
## large space feel small: it is always the same sound, and the only thing that
## ever changes is how loud that same sound is. A listener stops hearing it
## within a minute, exactly the way `WindProfile` says a CONSTANT wind stops
## being felt.
##
## A window is different. At 0.10 the valley is one low body of air; at 0.45 a
## second voice has entered that was not there before; at 0.80 there is a hiss
## over the top of both. Nothing crossfaded -- things ARRIVED. That is the same
## structural argument `WindProfile` makes for `gust_sharpness`, applied to the
## channel that has no picture.
##
## ---------------------------------------------------------------------------
## THE BOTTOM EDGE IS THE MOST IMPORTANT NUMBER IN THIS FILE
## ---------------------------------------------------------------------------
## `enters_at` above zero is what gives the bed its GAPS, and the gaps are the
## whole design. GDD section 9 makes audio the survival readout because there is
## no HUD; a bed with no silence in it is a bed that reports nothing, because a
## reading that is always present carries no information.
##
## It is also the entire audible half of 寒流. GDD section 7 gives the cold snap
## the tell 空气变得极静 -- the air goes utterly still -- and its `.tres` hands
## `WindSystem` the still profile, whose strength lives around 0.02..0.11. With
## `enters_at` above that band the bed does not fade down; it GOES. The most
## legible warning in the game needs no file at all, and it cannot be
## accidentally deleted by a mix change, because it is made of absence.
##
## `tests/unit/test_ambience.gd::test_the_bed_is_silent_for_most_of_a_still_night`
## is that claim as a measurement rather than as an intention.
##
## ---------------------------------------------------------------------------
## ADDING A LAYER IS ADDING A ROW
## ---------------------------------------------------------------------------
## Binding rule 4. `AmbienceDirector` builds one voice per layer in whatever map
## it is handed and knows none of their names, so a seventh weather that wants
## its own texture is a row in `tools/generate_ambience.gd` and a file on disk.

## WIND reads `WindSystem.strength()`; SNOWFALL reads `Snowfall.snowfall_rate()`.
##
## Two sources rather than one because GDD section 7 gives 冻雨 the tell
## 落雪声变脆 -- the sound of the falling snow turns brittle -- and freezing rain
## is the one shipped event that moves the SNOW without moving the wind. A bed
## that could only hear the wind would have nothing to say about it.
enum Source { WIND, SNOWFALL }

@export var layer_id: StringName = &""

@export_file("*.wav", "*.ogg", "*.mp3") var stream_path: String = ""

## Which reading this layer listens to. See `Source`.
@export var source: Source = Source.WIND

@export_group("Window")

## Below this the layer is SILENT -- not quiet, absent, with its voice stopped.
## See the header: this number is the bed's gaps.
@export_range(0.0, 1.0, 0.001) var enters_at := 0.05

## Where it reaches its authored gain. Between the two it eases in on a
## smoothstep, so nothing steps when a gust crosses the edge.
@export_range(0.0, 1.0, 0.001) var full_at := 0.30

## The upper edge of the window, for a voice that a bigger wind drowns -- a wire
## note, a branch creak. Both default above 1.0, which means "never leaves".
@export var leaves_at := 2.0
@export var gone_at := 2.0

@export_group("Voice")

## Applied on top of the window. Negative for everything here by default: this
## bed lives UNDER the footsteps and the breath, which is what
## `src/audio/music_director.gd` says the mix is for.
@export var gain_db := -12.0

## The pitch at `enters_at`, and the pitch at `full_at`. A bed that rises in
## pitch as it rises in level reads as air moving faster; one that does not reads
## as the same recording played louder, which is what it is.
@export var pitch_scale := 1.0
@export var pitch_at_full := 1.0

@export_group("Absence")

## GDD section 9, 反直觉设计：用消失吓人 -- "危险靠近时，BGM 抽走高频层，只剩低频".
##
## The scare is not a sting, it is a SUBTRACTION, and the document is specific
## about which part is subtracted: the high layers go and the low one stays. So
## this is a per-layer flag rather than a master duck. A bed that ducked as a
## whole would read as the mix getting quieter; a bed that loses its top reads as
## the world holding its breath.
@export var withdraws_near_danger := false

@export_multiline var notes := ""


## The window, as a pure function of the reading that drives it. 0 .. 1, before
## `gain_db`.
##
## Static and taking the layer, so a sweep over four minutes of weather costs
## nothing and needs no tree -- the same shape `WindSystem` gives its whole
## model, and for the same reason.
static func gain_at(layer: AmbienceLayer, reading: float) -> float:
	if layer == null:
		return 0.0
	var value := clampf(reading, 0.0, 1.0)
	if value <= layer.enters_at:
		return 0.0
	var rising := 1.0
	if layer.full_at > layer.enters_at:
		rising = smoothstep(layer.enters_at, layer.full_at, value)
	var falling := 1.0
	if layer.gone_at > layer.leaves_at and value > layer.leaves_at:
		falling = 1.0 - smoothstep(layer.leaves_at, layer.gone_at, value)
	return clampf(rising * falling, 0.0, 1.0)


## The pitch this layer wants at `reading`. Interpolated across the same window
## the gain uses, so the two arrive together.
static func pitch_at(layer: AmbienceLayer, reading: float) -> float:
	if layer == null:
		return 1.0
	if is_equal_approx(layer.pitch_scale, layer.pitch_at_full):
		return layer.pitch_scale
	var value := clampf(reading, 0.0, 1.0)
	var across := 1.0
	if layer.full_at > layer.enters_at:
		across = clampf(
			(value - layer.enters_at) / (layer.full_at - layer.enters_at), 0.0, 1.0)
	return lerpf(layer.pitch_scale, layer.pitch_at_full, across)
