class_name LightingDirector
extends WorldEnvironment

## Builds the Environment and aims the sun. Both in code, for the same reason
## the terrain material is: every colour comes out of the palette at runtime,
## so no colour literal ends up sitting in scenes/main.tscn.
##
## Art Bible rule 10 -- shadows are the subject, not a by-product:
##
##   * The sun sits about 11 degrees above the horizon. Shadow length is
##     height / tan(elevation), so at 11 degrees a 5 m tree throws a 26 m
##     shadow. That is what puts a third of the frame in shade.
##   * light_angular_distance gives the penumbra its width, so the edges stay
##     soft over that length instead of turning to a hard stencil.
##   * The shadow *colour* is not set here at all -- it is a palette uniform on
##     the cel shaders. Nothing multiplies anything.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Shadow length on flat ground is height / tan(elevation), and the derivative
## of that is savage down here: at 11 degrees a shadow ran 5.1x its caster and
## every centimetre the character moved vertically became five centimetres of
## shadow, so the walk lurched. At 21.5 it runs 2.5x -- still unmistakably a low
## raking winter sun, still long enough for rule 10 -- and halves the
## amplification of anything that moves vertically.
@export var sun_elevation_degrees := 21.5
@export var sun_azimuth_degrees := 118.0
## Penumbra width grows with distance from the caster, and these shadows are
## 25 m long. At 2.2 degrees the far half of every shadow was penumbra and the
## sheds cast fuzzy ovals; rule 10 wants a soft *edge* around a solid block.
@export var sun_angular_softness := 0.9

## Distant snow lifts slightly toward the sky, which is what stops the far edge
## of a 120 m field from reading as a wall of flat colour. Kept very low: this
## is aerial perspective, not weather.
@export var fog_density := 0.0015

## Art Bible section 1.2 is explicit that the six reference colours are screen
## pixels *after* lighting and tone mapping, and that the 12-colour table is
## albedo. A cel shader that selects a palette colour outright therefore lands
## on the albedo, which is measurably darker than the reference: sampled from
## level.jpg the open snow is #A2C5EF, and the palette's lightest snow tone is
## #8FB0D8. This is the tone-map row of the lighting panel in section 4.3, and
## at 1.3 the lit snow renders as #A1C5F4 -- within two points per channel of
## the reference. It scales every band equally, so it is not the per-band
## multiply rule 10 forbids.
@export var exposure := 1.3

## ---------------------------------------------------------------------------
## The character's fill -- and, today, nothing else's
## ---------------------------------------------------------------------------
## Both shaders in assets/shaders/ declare `ambient_light_disabled` (checked,
## and there are only two). So the Environment's ambient reaches exactly one
## thing on screen: the character, which is the only object in the game drawn
## with a stock StandardMaterial3D. These two numbers are therefore a
## **character control that happens to live on the Environment**, not a world
## shadow tint, and they should be read and tuned as such.
##
## They used to be `structure_tones[2]` at 0.35 -- the palette's darkest navy --
## with a comment saying ambient "reaches nothing that matters". It reached the
## character, and it was very nearly *all* the light on him: the sun sits at
## azimuth 118 against a camera yawed -35, which is almost behind the lens, so
## practically every surface the camera can see on any object is in shade. The
## measured result, sampled off the rendered frame at the shoulder, was
## **#02050C** -- black. The coat is painted #343E4C and the scarf #944328; the
## whole figure was a silhouette, and that is the defect this fixes.
##
## NEUTRAL RATHER THAN PALETTE-BLUE, and that is the one deliberate departure.
## The palette governs albedo; this is a light, and lights already leave it
## (the sun is snow_tones[0] because a low sun on snow is that colour). Filling
## with a snow tone was measured at four energies and does not work: the coat's
## blue channel clips while its red is still at a quarter, so the coat renders a
## saturated blue instead of the blue-grey it is painted. `fill_tint` keeps a
## little of the snow in it so the figure stays in the frame's colour family.
##
## WARNING for whoever adds the first world object that is *not* on a cel
## shader: this energy is far above a physical ambient, because it is standing
## in for a studio render's whole light rig on a model whose albedo was authored
## for one. Such an object will blow out. Give the character its own fill then
## -- an extra cull-masked light beside PlayerController's key -- and hand this
## number back to the world.
@export var character_fill_energy := 3.2

## How much of the snow's blue the neutral fill keeps, 0 = white, 1 = snow.
@export var character_fill_tint := 0.2

var _sun: DirectionalLight3D


func _ready() -> void:
	var bible: ColorBible = load(PALETTE_PATH)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bible.snow_tones[0]
	# See character_fill_energy above: this is the character's fill, because the
	# character is the only thing on screen that reads ambient at all.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE.lerp(bible.snow_tones[0], character_fill_tint)
	env.ambient_light_energy = character_fill_energy
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = exposure
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	env.fog_enabled = fog_density > 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = bible.snow_tones[0]
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0
	environment = env

	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if _sun == null:
		return
	_sun.rotation = Vector3(
		deg_to_rad(-sun_elevation_degrees),
		deg_to_rad(sun_azimuth_degrees),
		0.0
	)
	_sun.light_color = bible.snow_tones[0]
	_sun.light_energy = 1.0
	# The cel shaders read ATTENUATION, not LIGHT_COLOR, so specular from this
	# light would be the one thing on screen that ignored the palette.
	_sun.light_specular = 0.0
	_sun.shadow_enabled = true
	_sun.light_angular_distance = sun_angular_softness
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# The orthographic frame is about 18 m by 16 m of ground, so the shadow
	# cascades only have to cover the casters just outside it. 170 m spread the
	# same texels over a hundred times the area and the shadow edges crawled.
	_sun.directional_shadow_max_distance = 75.0
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.42
	# A grazing sun makes every receiver a near-parallel surface, which is the
	# worst case for shadow acne; the normal bias is what buys it off without
	# detaching the shadow from its caster.
	# Godot fades shadows out over the last stretch of their range by default,
	# which on a 25 m shadow means the tip dissolves into stipple. These are
	# the frame's subject; they get to reach their end.
	_sun.directional_shadow_fade_start = 0.98
	_sun.shadow_normal_bias = 2.0
	_sun.shadow_bias = 0.04
	_sun.shadow_blur = 1.0
