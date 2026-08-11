class_name LightingPreset
extends Resource

## One of the six looks. Each is a dramatic beat as much as a light setup.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Key Light")
@export var sun_energy := 1.0
## Deliberately neutral, and deliberately NOT a palette tone: this is the
## colour of a light source, not of a surface. The palette constrains what
## the player sees on a material; tinting the key light instead shifts every
## surface off-palette at once. Leave it white unless a preset means to tint.
@export var sun_color := Color.WHITE
@export var sun_angle_degrees := 15.0
@export var shadows_enabled := true

@export_group("Ambient")
## The palette's darkest structure tone, #131C30, to 6 decimal places. Ambient
## light lands on every surface, so an off-palette default would pull the whole
## frame off-palette in every preset a designer creates -- and no gate would
## see it, since the art gates scan materials and meshes, not presets. Keep
## this exactly equal to a colour in data/palette/color_bible.tres:
## ColorBible.contains() allows only 0.004 per channel, and the previous
## rounded value (0.08, 0.11, 0.19) was 0.00549 off on red and failed it.
@export var ambient_color := Color(0.074510, 0.109804, 0.188235)
@export var ambient_energy := 1.0

@export_group("Air")
@export var fog_enabled := true
@export var fog_density := 0.01
@export var glow_enabled := true
@export var glow_strength := 0.3

@export_group("Shading")
@export var cel_band_threshold := 0.5
@export var cel_band_softness := 0.05
@export var warm_accent_energy := 1.0
