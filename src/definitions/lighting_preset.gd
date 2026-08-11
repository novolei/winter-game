class_name LightingPreset
extends Resource

## One of the six looks. Each is a dramatic beat as much as a light setup.
##
## ---------------------------------------------------------------------------
## THERE ARE TWO LIGHTING RIGS ON SCREEN, AND THIS RESOURCE CARRIES BOTH
## ---------------------------------------------------------------------------
## Read this before authoring or tuning a preset. It is the single most
## surprising thing about lighting this project, and the field groups below are
## laid out around it.
##
##   THE WORLD is drawn by the two cel shaders in assets/shaders/. Their light()
##   SELECTS a palette colour outright -- `DIFFUSE_LIGHT += mix(shade, lit,
##   band)` -- and the only thing they read from a light is ATTENUATION, the
##   shadow term. LIGHT_COLOR and light energy reach the world NOT AT ALL, and
##   neither does ambient, because both shaders declare `ambient_light_disabled`.
##   What does reach it: the tonemap exposure, the fog, the glow, and whether the
##   sun casts a shadow.
##
##   THE CHARACTER is the one object in the game on a stock StandardMaterial3D.
##   He is lit by ordinary PBR: the sun's energy and colour, his own cull-masked
##   key light, and the Environment's ambient -- which, per the above, reaches
##   nothing else in the frame.
##
## So `sun_energy`, `sun_color` and the whole Ambient group are a CHARACTER
## control that happens to live on an Environment and a DirectionalLight3D, and
## `tonemap_exposure` is a WORLD control the character rides along with. A preset
## that darkens one without the other moves half the picture -- and with no HUD
## to contradict it, a man glowing in a dark frame reads as art direction rather
## than as a bug.
##
## The two controls that move world and character TOGETHER are the exposure and
## the fog. Everything else is one rig or the other, and
## tests/unit/test_lighting_presets.gd is the gate that keeps the pair in step.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Key Light")
## Reaches the CHARACTER only -- see the header.
@export var sun_energy := 1.0
## Deliberately neutral, and deliberately NOT a palette tone: this is the
## colour of a light source, not of a surface. The palette constrains what
## the player sees on a material; tinting the key light instead shifts every
## surface off-palette at once. Leave it white unless a preset means to tint.
##
## Reaches the CHARACTER only, for the same reason as sun_energy.
@export var sun_color := Color.WHITE

## THE SUN'S ELEVATION, AND THE ONE NUMBER A PRESET SHOULD NOT HAVE AN OPINION
## ABOUT.
##
## Shadow length on flat ground is height / tan(elevation), and the derivative of
## that is savage down here: at 11 degrees a shadow ran 5.1x its caster and every
## centimetre the character moved vertically became five centimetres of shadow,
## so the walk lurched. At 21.5 it runs 2.5x -- still unmistakably a low raking
## winter sun, still long enough for Art Bible rule 10 -- and halves the
## amplification of anything that moves vertically.
##
## It is a per-preset field because the six have to be readable side by side and
## a value hidden in code is a value nobody checks. All six ship at 21.5 and a
## test pins them there against LightingDirector's own reference. Vary colour,
## energy, fog and ambient freely; if a preset genuinely needs a different sun
## height, that is a conversation and not a tweak.
@export var sun_angle_degrees := 21.5
@export var shadows_enabled := true

@export_group("Ambient")
## THE CHARACTER'S FILL. Every world shader declares `ambient_light_disabled`,
## so this lands on the character and on nothing else in the frame.
##
## The palette's darkest structure tone, #131C30, to 6 decimal places, as the
## script default. Ambient light lands on every surface it is allowed to reach,
## so an off-palette default would pull whatever it touches off-palette in every
## preset a designer creates -- and no gate would see it, since the art gates
## scan materials and meshes, not presets. Keep this exactly equal to a colour in
## data/palette/color_bible.tres: ColorBible.contains() allows only 0.004 per
## channel, and the previous rounded value (0.08, 0.11, 0.19) was 0.00549 off on
## red and failed it.
##
## The six shipped presets deliberately depart from that and fill with a NEUTRAL
## mix instead -- see tools/generate_lighting_presets.gd, which derives it from
## the palette rather than inventing it. Measured at four energies: filling with
## a snow tone clips the coat's blue channel while its red is still at a quarter,
## and the coat renders saturated blue instead of the blue-grey it is painted.
@export var ambient_color := Color(0.074510, 0.109804, 0.188235)
@export var ambient_energy := 1.0

@export_group("Air")
@export var fog_enabled := true
@export var fog_density := 0.01
## The colour the whole frame washes toward. The camera is orthographic on a 90 m
## boom, so every fragment is at very nearly the same depth and the fog is close
## to a flat, full-screen tint whose strength is the density -- which makes this
## the only control in the preset that moves the WORLD's hue at all, the cel
## bands being palette colours chosen outright. On-palette, therefore, always.
@export var fog_color := Color(0.56078434, 0.6901961, 0.84705883)
@export var glow_enabled := true
@export var glow_strength := 0.3

@export_group("Shading")
## Art Bible section 4.2 lists the tonemap among a preset's contents, and it
## earns its place: it is the only brightness control that reaches the WORLD.
##
## It scales both cel bands equally, so it is not the per-band multiply rule 9
## forbids -- an exposure change cannot take the shadow band off-palette,
## because it moves the lit band by exactly as much.
@export var tonemap_exposure := 1.3

## How much of the world falls into the shadow band, and how soft the border is.
##
## AUTHORED BUT NOT YET WIRED. These belong to the cel shaders' `band_threshold`
## and `band_softness` uniforms, which TerrainRenderer and CelPainter set once at
## startup from their own exports. Driving them per preset needs a setter on each
## and a way for the director to find them; both files were another agent's
## live work when these presets were authored, so the values ship as the
## authored intent and the wiring is a named, single-commit job.
@export var cel_band_threshold := 0.12
@export var cel_band_softness := 0.07

## Art Bible rule 12's warm quota: the lit windows and the firebox, the only warm
## light in a blue frame. Published by LightingDirector.warm_accent_energy() for
## whatever burns to scale itself by; nothing warm has been placed in the world
## yet, so today it is a seam rather than a value with a consumer.
@export var warm_accent_energy := 1.0
