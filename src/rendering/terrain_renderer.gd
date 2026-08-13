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
## Renderer source rather than an asset: this is executable game logic and has
## to remain versioned even when local art packs are intentionally ignored.
const SHADER_PATH := "res://src/rendering/snow_ground.gdshader"

## Wider than the 120 m heightfield on purpose: the drawn plane has to run past
## the top of the frame or the shot contains the field's own edge and the
## horizon behind it. The shader flattens the surface outside the window, which
## is what distant snow looks like anyway.
@export var ground_size := 140.0

## The dense terrain plane is deliberately finite: it needs 44 cm quads while
## the player is nearby, but carrying that density all the way to the horizon
## would spend triangles on snow the shader already makes perfectly flat. The
## horizon is a regular, normalled mesh ring made from the same material. It
## begins only after the visible field has settled to its flat continuation, so
## there is neither a geometric step nor a second snow colour. A former version
## used eight enormous triangles here; even when their shared border was exact,
## the triangles themselves could read as a map boundary in a wide shot.
##
## 640 m is not a world-map boundary: the Terrain node follows the player. It
## is enough clearance for the 100 m art capture that previously exposed the
## finite 140 m plane as a hard diamond, while the only added geometry is eight
## triangles rather than a larger high-density heightfield.
@export var horizon_size := 640.0

## The moving SnowField raster is deliberately square -- that is how a compact
## world-anchored image is updated without a full-map rebuild -- but its data
## edge is not a world feature. The rendered terrain therefore settles over a
## broad radial range. The shader adds a small world-space warp, so the visual
## transition cannot make a circle either; these pure values remain here for
## inspectors and tests to pin the size and continuity of the underlying ramp.
@export var visual_field_fade_start := 0.32
@export var visual_field_fade_end := 0.72
@export var visual_field_warp_scale := 0.018
@export var visual_field_warp_amount := 0.045

## The continuation carries only already-flat snow, but it still needs a
## regular topology and explicit upward normals. A handful of giant triangles
## gives the shadow/depth paths enough interpolation room to make visible
## diagonal fields if any future feature touches the horizon.
@export var horizon_edge_segments := 32
@export var horizon_radial_segments := 4

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
@export var grain_amount := 0.02
@export var grain_scale := 0.14

## How deep a print dents the *normal*. Never the mesh -- see the shader. This
## is the knob for "visible tracks versus subtle dents"; it trades against
## track_tint, which is the same argument in colour.
##
## 0.065 was the approved read and 0.06825 was that plus the 5% asked for
## afterwards. Both were too shallow, and the reason is arithmetic rather than
## taste:
##
##   A mark is drawn by the reconstructed normal, so what has to clear the cel
##   band is a SLOPE. The steepest slope a mark can present is its value times
##   this depth over the 12 cm the normal's central difference spans. At 0.06825
##   a ploughed furrow, buried as deep as the accumulation will ever bury it,
##   tilts its flank 21.5 degrees against a sun 21.5 degrees up -- **exactly
##   zero margin**. It arrives at the shadow band and never enters it, so the
##   frame's most important line (Art Bible rule 11) is carried by tone alone.
##   tests/unit/test_terrain_shading.gd asserts the margin now.
##
## SWEPT, at 1600x1000 under `pale_day`, counting ground pixels in the shade band
## and the mean darkness of the marked ones ("ink"):
##
##   depth     print ink   print shade   field shade   road shade
##   0.06825    7.33        0.15 %        0.32 %        7.64 %
##   0.095      8.96        1.32          0.60          7.11
##   0.115      8.98        1.31          0.83          7.41
##   0.1365    10.35        2.23          1.12          7.05
##   0.16      11.03        2.53          1.56          6.97
##   0.19      11.26        3.14          2.23          9.89
##
## 0.16 is where the marks' own darkness SATURATES -- the step to 0.19 buys 2%
## more of it -- and it is the deepest value at which the road is measurably
## unmoved. That last column is the reason the owner's "make the footprints
## deeper" could be answered globally instead of per-mark: a road is a WIDE mark
## with no gradient except at its two edges, so depth does almost nothing to it
## until 0.19, where it starts to read as a trench rather than as packed snow.
##
## The print's SHAPE is untouched by this. The outline is TrackMask's, it was
## approved as it stands, and this scales the height the same outline is read at.
@export var track_depth := 0.16
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
	# ...and the shape of a mark, which until now was pushed ONLY from _process
	# and only once the snow, the tracks and the material had all resolved. The
	# shader carries its own defaults for these, and `track_depth`'s is 0.05
	# against the 0.16 authored here -- so a frame drawn before the services
	# resolve cut every mark in the world less than half as deep, silently, and
	# no test could see it because no test looked at the material before the
	# first tick. Found by writing that test.
	_stamp_marks()
	_material.set_shader_parameter("field_extent", SnowField.EXTENT_M)
	_material.set_shader_parameter("track_extent", TrackMask.EXTENT_M)
	_material.set_shader_parameter("static_extent", TrackMask.STATIC_EXTENT_M)
	_stamp_visual_field_continuity()
	material_override = _material
	_build_horizon_skirt()

	# The plane is displaced geometry whose bounding box the engine computes
	# from the undisplaced mesh; without this it vanishes as soon as the flat
	# plane leaves the frustum.
	extra_cull_margin = ground_size
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## A low-density continuation of the terrain mesh, with a hole where the dense
## plane already draws. A second full plane would z-fight with the dense terrain;
## this ring shares the inner perimeter exactly, carries its own upward normals,
## and contains no screen-sized triangle that could become a diagonal seam.
func _build_horizon_skirt() -> void:
	var existing := get_node_or_null("HorizonSkirt") as MeshInstance3D
	if existing != null:
		existing.mesh = horizon_skirt_mesh(ground_size, horizon_size)
		existing.material_override = _material
		return
	var skirt := MeshInstance3D.new()
	skirt.name = "HorizonSkirt"
	skirt.mesh = horizon_skirt_mesh(ground_size, horizon_size)
	skirt.material_override = _material
	# The shader displaces every ring corner by the same flat outside-window
	# snow height. Keep the culling bounds generous so its edge never vanishes
	# while the parent follows the player.
	skirt.extra_cull_margin = horizon_size
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)


## The ring is intentionally exposed as pure mesh construction so the visual
## no-edge contract has a deterministic regression test without pretending a
## headless unit test can judge a rendered photograph. It is tessellated around
## the perimeter rather than as four trapezoids: a flat continuation should be
## boring topology, not four giant diagonal lighting candidates.
func horizon_skirt_mesh(inner_size: float, outer_size: float) -> ArrayMesh:
	var inner_half := maxf(inner_size, 0.0) * 0.5
	var outer_half := maxf(outer_size, inner_size + 0.001) * 0.5
	var edge_segments := maxi(horizon_edge_segments, 1)
	var radial_segments := maxi(horizon_radial_segments, 1)
	var perimeter_points := edge_segments * 4
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for radial in range(radial_segments + 1):
		var half := lerpf(inner_half, outer_half, float(radial) / float(radial_segments))
		for edge in range(perimeter_points):
			vertices.append(_square_perimeter_point(half, edge, edge_segments))
			normals.append(Vector3.UP)
	for radial in range(radial_segments):
		var inner_row := radial * perimeter_points
		var outer_row := (radial + 1) * perimeter_points
		for edge in range(perimeter_points):
			var next := (edge + 1) % perimeter_points
			var inner_a := inner_row + edge
			var inner_b := inner_row + next
			var outer_b := outer_row + next
			var outer_a := outer_row + edge
			# Godot's PlaneMesh front faces carry a negative signed Y cross product
			# in XZ. Keep this exact winding: the positive-Y order culls every
			# horizon face and exposes the sky as a giant diamond.
			indices.append_array(PackedInt32Array([
				inner_a, outer_b, inner_b,
				inner_a, outer_a, outer_b,
			]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var skirt := ArrayMesh.new()
	skirt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return skirt


## One clockwise walk around a square in XZ. The index order above is deliberate
## and is pinned against PlaneMesh's actual front-face winding in the tests.
func _square_perimeter_point(half: float, edge_index: int, edge_segments: int) -> Vector3:
	var side := edge_index / edge_segments
	var t := float(edge_index % edge_segments) / float(edge_segments)
	match side:
		0:
			return Vector3(lerpf(-half, half, t), 0.0, -half)
		1:
			return Vector3(half, 0.0, lerpf(-half, half, t))
		2:
			return Vector3(lerpf(half, -half, t), 0.0, half)
		_:
			return Vector3(-half, 0.0, lerpf(half, -half, t))


## The testable, unwarped part of the shader's visual settling profile. It is
## intentionally radial, not `min(uv, 1 - uv)`: the raster can be square
## without projecting a square or diamond into the snow. The shader adds only a
## stable, low-frequency world warp to this result; the interactive centre stays
## exactly one and the dense mesh's edge lands exactly zero.
func visual_field_weight(uv: Vector2) -> float:
	var radial_distance := (uv - Vector2(0.5, 0.5)).length() * sqrt(2.0)
	return 1.0 - _smoothstep(visual_field_fade_start, visual_field_fade_end, radial_distance)


func _smoothstep(low: float, high: float, value: float) -> float:
	var width := maxf(high - low, 0.000001)
	var t := clampf((value - low) / width, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _stamp_visual_field_continuity() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("visual_field_fade_start", visual_field_fade_start)
	_material.set_shader_parameter("visual_field_fade_end", visual_field_fade_end)
	_material.set_shader_parameter("visual_field_warp_scale", visual_field_warp_scale)
	_material.set_shader_parameter("visual_field_warp_amount", visual_field_warp_amount)


## How a mark in the snow is SHAPED -- how deep, how tinted, the rim around it,
## and the two scales the per-pixel normal is rebuilt at. None of it moves at
## runtime; it is pushed from _ready() so the first frame is right and re-pushed
## from _process() so a tuner dragging one of these in the inspector sees it.
func _stamp_marks() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("track_depth", track_depth)
	_material.set_shader_parameter("track_tint", track_tint)
	_material.set_shader_parameter("track_rim", track_rim)
	_material.set_shader_parameter("track_rim_extent", track_rim_extent)
	_material.set_shader_parameter("ground_normal_epsilon", ground_normal_epsilon)
	_material.set_shader_parameter("track_normal_epsilon", track_normal_epsilon)


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
	_stamp_marks()
	_stamp_visual_field_continuity()
	# The plane is centred on the window; the window is described by its corner.
	global_position = Vector3(
		field_origin.x + SnowField.EXTENT_M * 0.5,
		0.0,
		field_origin.y + SnowField.EXTENT_M * 0.5
	)
