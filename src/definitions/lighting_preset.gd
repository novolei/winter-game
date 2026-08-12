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
## THE FOG'S OPACITY AT THE FAR EDGE OF ITS WINDOW -- a 0..1 blend, NOT a
## density, because the fog is in DEPTH mode. Godot computes
##
##     fog = smoothstep(fog_depth_begin, fog_depth_end, distance) * fog_density
##
## so this is the most fog the frame can ever hold. A value authored as though it
## were still an exponential density (0.0016) is invisible.
@export var fog_density := 0.35
## The colour the frame washes toward with distance. Fog is additive toward a
## colour, so it moves DARK surfaces much further than light ones -- fog toward
## the palette's lightest snow leaves distant snow where it is and turns distant
## trees blue, which is exactly what aerial perspective is. On-palette, always.
@export var fog_color := Color(0.56078434, 0.6901961, 0.84705883)
## How bright the fog burns. At 1.0 the target is exactly the palette tone, so
## distant snow is unchanged; below about 0.85 the far field goes darker than the
## near field, which is a different effect and not this one. The style document
## asks for 0.7 -- that was written for a perspective camera whose far distance
## really is far away.
@export var fog_light_energy := 1.0

## THE DEPTH WINDOW, AND WHY IT IS A NINETY-METRE NUMBER FOR A TWENTY-METRE
## FARMSTEAD.
##
## The rig is ORTHOGRAPHIC on a 90 m boom (src/rendering/camera_rig.gd), so the
## whole scene sits between about 69 m and 100 m from the camera -- not because
## anything is far away, but because the camera is. Exponential fog cannot make a
## picture out of that: 1 - exp(-density * depth) over 69..100 m is nearly a
## straight line starting well above zero, so fog enough to blue the far tree
## already greys the near one, and the near one has to stay black.
##
## A depth window can. Begin the ramp just in front of the nearest thing in the
## frame and end it past the furthest, and the near tree gets nothing while the
## far tree gets nearly all of it. The price is that these are measured FROM THE
## CAMERA and are therefore tied to `CameraRig.boom_length` --
## tests/art/test_aerial_perspective.gd is that coupling written down.
@export var fog_depth_begin := 74.0
@export var fog_depth_end := 118.0
## How much of the fog colour the sky takes. The sky is behind a 140 m ground
## plane and is not in shot at any framing the game currently uses, so this is
## nearly always 0 -- except in the storm, where the horizon has to disappear.
@export var fog_sky_affect := 0.0

@export var glow_enabled := true
@export var glow_strength := 0.3

@export_group("Sky")
## The background used to be one flat palette colour. A vertical gradient is what
## puts air above the landscape, and it is per-preset because PALE DAY and DEEP
## NIGHT cannot share one sky.
##
## Honest about its reach: at the framings the game uses today the ground plane
## fills the frame and NONE of this is on screen. It is here so that the first
## shot that tips the camera or widens the frame does not find six presets that
## all have the same sky, and so the fog has something to resolve toward.
@export var sky_zenith_color := Color(0.3647059, 0.48235294, 0.6509804)
@export var sky_horizon_color := Color(0.7176471, 0.8039216, 0.9019608)
## Where between the two the gradient turns over. Low values hold the horizon
## colour up most of the dome, which is what a low winter sun does to a sky.
@export var sky_curve := 0.15
@export var sky_energy := 1.0

## HOW MANY STARS, 0 none .. 1 a clear winter night.
##
## The sky is drawn by assets/shaders/aurora_sky.gdshader rather than by
## ProceduralSkyMaterial, and this is the one thing the custom shader adds to the
## gradient above that a preset has to have an opinion about. It crossfades like
## everything else, so dusk brings them out rather than switching them on.
##
## It earns its place for the same reason the gradient does -- nothing is above
## the horizon at any framing the game uses today -- plus one of its own: the
## aurora is drawn ADDITIVELY over this, so the stars showing THROUGH the curtain
## are what prove it is semi-transparent rather than a sheet of green.
@export var star_amount := 0.0

@export_group("Volumetric Air")
## Style document section 39, Forward+ only -- and we are Forward+. The goal is a
## little cold moisture in the air, not a player who cannot see: the document is
## emphatic that 0.01 is far too much, and its band is 0.0008 to 0.002.
##
## The froxel volume is only 64 m deep by default and the whole farmstead is
## further from the camera than that, so LightingDirector lengthens it to reach
## the end of the fog window.
@export var volumetric_fog_enabled := false
@export var volumetric_fog_density := 0.0012
@export var volumetric_fog_albedo := Color(0.7176471, 0.8039216, 0.9019608)
@export var volumetric_fog_anisotropy := 0.15
@export var volumetric_fog_ambient_inject := 0.15

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
## WIRED. LightingDirector publishes these on every write; TerrainRenderer pushes
## them into the ground's material and CelPainter broadcasts them to every solid
## in the world. 0.12 is the daylight value and is what TerrainRenderer itself is
## tuned to -- tests/unit/test_lighting_presets.gd reads it off the renderer
## rather than duplicating it, so the two cannot disagree silently.
@export var cel_band_threshold := 0.12
@export var cel_band_softness := 0.07

## THE COLOUR THE LIT CEL BAND TAKES FROM THE LIGHT.
##
## Concern 3 of the clock/lighting report: SUNRISE warmed the buildings and left
## the snow cold lavender, because fog was the world's only hue control and fog
## moves dark surfaces further than light ones. This is the other half. It is a
## LIGHT and not an albedo -- the Director's boundary is that the twelve govern
## surface colour, and that sky, fog, ambient and sun colour are atmosphere --
## and it reaches the LIT band only. The shade band stays the palette colour it
## was chosen as, which is Art Bible section 4.1 and is also just what a winter
## dawn looks like: warm sun, cold shadow.
##
## LightingDirector normalises it to unit luminance before pushing it, so
## `world_light_strength` is a hue knob and cannot quietly darken a look the
## exposure was tuned for. 0.0 is "the palette exactly as authored".
@export var world_light_color := Color.WHITE
@export var world_light_strength := 0.0

## Art Bible rule 12's warm quota: the lit windows and the firebox, the only warm
## light in a blue frame. Published by LightingDirector.warm_accent_energy() for
## whatever burns to scale itself by; nothing warm has been placed in the world
## yet, so today it is a seam rather than a value with a consumer.
@export var warm_accent_energy := 1.0
