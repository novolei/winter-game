class_name TerrainRenderer
extends MeshInstance3D

## Draws the snow field. Owns the plane, the shader material, and the job of
## keeping the two windows (snow field, track mask) under the player.
##
## Every colour on this surface is read out of data/palette/color_bible.tres at
## runtime and pushed into the shader as a uniform. Nothing here, and nothing
## in scenes/main.tscn, holds a colour literal -- which is also why the material
## is built in code instead of saved as a .tres beside the scene.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SHADER_PATH := "res://assets/shaders/snow_ground.gdshader"

## Wider than the 120 m heightfield on purpose: the drawn plane has to run past
## the top of the frame or the shot contains the field's own edge and the
## horizon behind it. The shader flattens the surface outside the window, which
## is what distant snow looks like anyway.
@export var ground_size := 140.0

## 140 m at 320 subdivisions is a 44 cm quad. That is set by the terrain, which
## is what the mesh draws: swells 28 m across need roughly half-metre quads
## before the silhouette stops looking polygonal. Footprints are deliberately
## *not* a consideration here -- they are 29 cm long, no affordable mesh
## resolves them, and trying is what produced the shards. They live in the
## normal instead.
@export var subdivisions := 320

## Flat ground sits at N.L = sin(sun elevation) = 0.37, and the field's slopes
## swing it either side of that. The threshold has to sit inside the swing or the
## terrain has no shading at all -- at 0.09 (which suited the old 11-degree sun)
## only the very steepest face went dark and the dunes disappeared.
##
## **This number and SnowField.drift_flatten are a pair, and they were retuned
## together.** The threshold is the slope at which the ground turns dark:
## sin(elevation - slope) = threshold, so 0.22 shades everything past 8.8 degrees
## and 0.12 everything past 14.6. When the relief was proportional to the noise
## the field's median slope was 11 degrees, so 0.22 put half of every away-facing
## swell into shade and the 70 m frame read as rolling dunes. The drift profile
## drops the median to 4 degrees and keeps the steep ground for the drifts, and a
## threshold left at 0.22 would have thrown that away by shading the gentle part
## anyway. Measured over the establishing frame: 79% of it lit before, 97% after.
##
## It moves the *cast* shadows not at all. A texel inside one has ATTENUATION 0,
## so its band value is 0 whatever the threshold is; this only ever decides how
## much of its own slope the snow shades itself with.
##
## **DRIVEN PER PRESET SINCE THE ATMOSPHERE WAVE.** This is now the *fallback*,
## and the value the daylight presets are pinned to -- LightingDirector pushes
## `LightingPreset.cel_band_threshold` through `apply_world_shading()` every
## frame, so more of the field falls into the shadow band as the light goes.
## tests/unit/test_lighting_presets.gd reads this export rather than duplicating
## it, so the two cannot disagree without going red.
@export var band_threshold := 0.12
@export var band_softness := 0.07

## THE SNOW GRAIN -- style document section 15.
##
## The field was one flat fill: #9BC3E8 #9BC3E8 #9BC3E8. The document asks for it
## to vary slightly and says in as many words that you should barely be able to
## see it. It cannot be done by interpolating the colour -- Art Bible rule 8
## forbids gradients and rule 9 forbids anything off the twelve -- so the noise
## jitters a *band boundary* instead and every pixel stays exactly a palette
## entry. The reasoning is in the shader; these are the knobs.
##
## `grain_threshold` is in Lambert terms and flat ground sits at
## sin(21.5) = 0.366, so 0.38 puts the flat field just below the boundary and the
## jitter is what carries patches of it over. `grain_amount` is measured against
## the +/-0.06 of Lambert the drift profile's own slopes produce: much more than
## half of that and the dither stops reading as surface and starts reading as
## bumps the ground does not have.
##
## `grain_scale` is 1/wavelength: 0.14 is a 7 m patch, which is the soft
## variation the document's example shows rather than speckle.
@export var grain_threshold := 0.345
@export var grain_softness := 0.03
@export var grain_amount := 0.05
@export var grain_scale := 0.14

## How deep a print dents the *normal*. Never the mesh -- see the shader. This
## is the knob for "visible tracks versus subtle dents"; it trades against
## track_tint, which is the same argument in colour.
##
## 0.065 was the approved read; this is that plus the 5% asked for afterwards.
@export var track_depth := 0.06825
@export var track_tint := 0.5

## Snow pushed out around a print. See track_height() in the shader.
@export var track_rim := 0.014
@export var track_rim_extent := 0.4

## The two scales the per-pixel normal is rebuilt at, in metres.
@export var ground_normal_epsilon := 0.8
@export var track_normal_epsilon := 0.06

## How much of the accumulation reaches the BAKED layer. The road and the
## ploughed field fill in with the same weather that whitens the roofs, but not
## as completely: Art Bible rule 11 says every line in the picture comes from
## the marks in the snow, and a road that vanished on day 4 would take the
## strongest line the frame has with it.
##
## The shader raises the baked value to 1 + this * cover * (power - 1), so at
## 0.75 a whiteout leaves a worn strip at three quarters of its cut depth while
## the verge beside it is gone. Zero here switches the burial off entirely and
## is what the frame looked like before this landed.
@export var static_burial_share := 0.75

## The exponent at full burial. See the shader, which carries the arithmetic.
@export var static_burial_power := 2.7

## How much more tone the baked layer carries than a footprint does. A road is
## compacted snow rather than a dent, and -- more to the point -- it is a WIDE
## mark, so the shading has no gradient to draw the middle of it with and the
## colour has to. Applied to the baked layer alone: no footprint in the game
## changes. See the shader.
@export var static_tint_boost := 1.35

var _material: ShaderMaterial
var _snow: Node
var _tracks: Node
var _lighting: Node
var _accumulation: Node


## The two-band contract's world side, pushed in from the lighting. The preset
## owns where the shadow band starts and what colour the light is; the grain
## above is the ground's own and composes with both.
func apply_world_shading(threshold: float, softness: float, tint: Color) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("band_threshold", threshold)
	_material.set_shader_parameter("band_softness", softness)
	_material.set_shader_parameter("light_tint", Vector3(tint.r, tint.g, tint.b))


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane

	var bible: ColorBible = load(PALETTE_PATH)
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	# Four palette entries, one per (band x track) combination. Rule 10's
	# "one step darker from the table" taken literally: the shadow band is
	# snow tone 4 to the lit band's tone 1, and a print is another step down
	# again within whichever band it falls in. Nothing is multiplied.
	_material.set_shader_parameter("snow_lit", bible.snow_tones[0])
	_material.set_shader_parameter("snow_shade", bible.snow_tones[3])
	_material.set_shader_parameter("track_lit", bible.snow_tones[2])
	_material.set_shader_parameter("track_shade", bible.snow_tones[4])
	# The grain's second tone: one step down the same family from the lit band,
	# so the field dithers between two adjacent entries of the twelve and never
	# produces a colour that is not one of them.
	_material.set_shader_parameter("snow_grain_tone", bible.snow_tones[1])
	_material.set_shader_parameter("grain_threshold", grain_threshold)
	_material.set_shader_parameter("grain_softness", grain_softness)
	_material.set_shader_parameter("grain_amount", grain_amount)
	_material.set_shader_parameter("grain_scale", grain_scale)
	# The fallback light, until a preset says otherwise on the first frame.
	apply_world_shading(band_threshold, band_softness, Color.WHITE)
	# ...and the fallback weather. A scene with no accumulation node in it draws
	# the road exactly as it was cut, which is what this one drew before the snow
	# started arriving.
	_material.set_shader_parameter("static_burial", 0.0)
	_material.set_shader_parameter("static_burial_power", static_burial_power)
	_material.set_shader_parameter("static_tint_boost", static_tint_boost)
	_material.set_shader_parameter("field_extent", SnowField.EXTENT_M)
	_material.set_shader_parameter("track_extent", TrackMask.EXTENT_M)
	_material.set_shader_parameter("static_extent", TrackMask.STATIC_EXTENT_M)
	material_override = _material

	# The plane is displaced geometry whose bounding box the engine computes
	# from the undisplaced mesh; without this it vanishes as soon as the flat
	# plane leaves the frustum.
	extra_cull_margin = ground_size
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The world's snow, from bare to as covered as this weather gets, on both the
## ground's baked layer and every solid standing on it.
##
## THIS IS WHERE THE ONE SCALAR FANS OUT, and it is here rather than inside
## SnowAccumulation for the same reason the lighting's band is: the systems
## under src/systems/ own facts and nothing about how the facts are drawn, and
## this node is already the one place in the world holding a per-frame tick, a
## handle on the ground material and a licence to reach for the paint shop.
## Deleting the whole rendering layer must leave the accumulation compiling.
##
## Pushed every frame rather than on change. The cover moves continuously for
## the whole run by design; there is no event to subscribe to and there must not
## be one, because an event is a step and a step is what this feature exists to
## make impossible.
func apply_snow_cover(cover: float) -> void:
	var settled := clampf(cover, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("static_burial", settled * static_burial_share)
		_material.set_shader_parameter("static_burial_power", static_burial_power)
	CelPainter.set_snow_cover(settled)


func _resolve() -> void:
	if _snow != null and _tracks != null and _lighting != null and _accumulation != null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	if _snow == null:
		_snow = registry.get_service(&"snow_field") as Node
	if _tracks == null:
		_tracks = registry.get_service(&"track_mask") as Node
	# The director registers itself as `lighting`. Absent -- in a test, or in a
	# scene with no WorldEnvironment -- the ground keeps its own exports, which is
	# what makes the pair above a fallback rather than a duplicate.
	if _lighting == null:
		_lighting = registry.get_service(&"lighting") as Node
	# Absent, the world stays at whatever cover it was last given, which on a
	# scene with no accumulation node in it is zero -- a bare world, which is
	# what this scene drew before the feature landed.
	if _accumulation == null:
		_accumulation = registry.get_service(&"snow_accumulation") as Node


func _process(_delta: float) -> void:
	_resolve()
	if _lighting != null and _material != null:
		# Pushed every frame rather than on change, because a crossfade moves all
		# three for eight seconds twice a day and there is nothing to subscribe to.
		apply_world_shading(
			_lighting.cel_band_threshold(),
			_lighting.cel_band_softness(),
			_lighting.world_light_tint()
		)
	if _accumulation != null and _accumulation.has_method("cover"):
		apply_snow_cover(_accumulation.cover())
	if _snow == null or _tracks == null or _material == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	var player: Node3D = null
	if registry != null:
		player = registry.get_service(&"player") as Node3D
	if player != null:
		_snow.follow(player.global_position)
		_tracks.follow(player.global_position)
	_snow.flush()
	_tracks.flush()

	var field_origin: Vector2 = _snow.origin()
	var track_origin: Vector2 = _tracks.origin()
	_material.set_shader_parameter("snow_terrain", _snow.terrain_texture())
	_material.set_shader_parameter("snow_packed", _snow.packed_texture())
	_material.set_shader_parameter("track_mask", _tracks.texture())
	_material.set_shader_parameter("field_origin", field_origin)
	_material.set_shader_parameter("track_origin", track_origin)
	# The baked layer's window never moves, so this pair never changes after the
	# first frame. Pushed every frame anyway rather than cached, because the one
	# thing that must not happen is the shader reading a stale origin against a
	# freshly rebaked image -- the furrows would be somewhere else in the world.
	_material.set_shader_parameter("static_mask", _tracks.static_texture())
	_material.set_shader_parameter("static_origin", _tracks.static_origin())
	# Pushed from the field rather than duplicated here: the shader and
	# SnowField.depth_at() have to be the same formula with the same numbers, or
	# the drift you see is not the drift you walk in.
	_material.set_shader_parameter("terrain_amplitude", _snow.terrain_amplitude_m)
	_material.set_shader_parameter("terrain_contrast", _snow.terrain_contrast)
	_material.set_shader_parameter("drift_flatten", _snow.drift_flatten)
	_material.set_shader_parameter("drift_sharpness", _snow.drift_sharpness)
	_material.set_shader_parameter("max_depth", _snow.max_depth_m)
	_material.set_shader_parameter("scour_hollow", _snow.scour_hollow)
	_material.set_shader_parameter("scour_crest", _snow.scour_crest)
	_material.set_shader_parameter("track_depth", track_depth)
	_material.set_shader_parameter("track_tint", track_tint)
	_material.set_shader_parameter("track_rim", track_rim)
	_material.set_shader_parameter("track_rim_extent", track_rim_extent)
	_material.set_shader_parameter("ground_normal_epsilon", ground_normal_epsilon)
	_material.set_shader_parameter("track_normal_epsilon", track_normal_epsilon)
	# The plane is centred on the window; the window is described by its corner.
	global_position = Vector3(
		field_origin.x + SnowField.EXTENT_M * 0.5,
		0.0,
		field_origin.y + SnowField.EXTENT_M * 0.5
	)
