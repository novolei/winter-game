extends TestCase

## The snow's half of the two-band cel contract: which uniforms the ground takes
## from the lighting, and which it owns itself.
##
## ---------------------------------------------------------------------------
## THE SNOW GRAIN, AND WHY IT PERTURBS A THRESHOLD RATHER THAN A COLOUR
## ---------------------------------------------------------------------------
## Style document section 15 asks for the field to stop being
##
##     #9BC3E8  #9BC3E8  #9BC3E8  #9BC3E8
##
## and start being
##
##     #9BC3E8  #96BEE4  #A0C7E9  #93BDE3
##
## with the qualifier that you should barely be able to see it. Interpolating the
## snow colour by a noise is the obvious way and it is illegal twice over: Art
## Bible rule 8 forbids gradients, and every value in that example is outside the
## twelve.
##
## So the noise moves the BAND BOUNDARY instead. The lit band splits across a
## second, higher threshold that flat ground straddles, and a low-frequency
## world-space noise jitters that threshold about its authored value. Which of
## two adjacent palette tones a patch of snow takes then varies -- and every
## pixel is still exactly a palette entry, and it is dithering between discrete
## steps rather than a ramp between them.
##
## The amplitude is the whole risk. A threshold jitter and a real slope both
## decide which band a texel lands in, so too much of it reads as fake bumpiness
## and fights the drifts the terrain actually has.

const TerrainRendererScript := preload("res://src/rendering/terrain_renderer.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SNOW_SHADER_PATH := "res://src/rendering/snow_ground.gdshader"
const SEAM_CAPTURE_PATH := "res://tools/capture_snow_seam.tscn"
const SEAM_CAPTURE_SCRIPT_PATH := "res://tools/capture_snow_seam.gd"

var _renderer: TerrainRenderer


## _ready() builds the plane and the material without needing a tree; it only
## reaches for the ServiceRegistry from _process (briefing trap 1).
func before_each() -> void:
	_renderer = TerrainRendererScript.new()
	_renderer._ready()


## MeshInstance3D is a Node (briefing constraint 2).
func after_each() -> void:
	if _renderer != null:
		_renderer.free()
		_renderer = null


func _material() -> ShaderMaterial:
	return _renderer.material_override as ShaderMaterial


# --- what the lighting owns -------------------------------------------------

## The band the preset asks for has to arrive on the ground, or
## `cel_band_threshold` goes on being an authored value that reaches nothing --
## which is what it was for the whole of the last wave.
func test_the_ground_takes_the_band_the_lighting_hands_it() -> void:
	_renderer.apply_world_shading(0.29, 0.11, Color(1.15, 0.99, 0.83))
	var material := _material()
	assert_not_null(material, "the terrain built no material")
	if material == null:
		return
	assert_almost_eq(float(material.get_shader_parameter("band_threshold")), 0.29, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("band_softness")), 0.11, 0.0001)
	var tint: Vector3 = material.get_shader_parameter("light_tint")
	assert_almost_eq(tint.x, 1.15, 0.0001, "the warm light did not reach the snow")
	assert_almost_eq(tint.z, 0.83, 0.0001, "the warm light did not reach the snow")


## Nothing is lit yet on the first frame, and the terrain has to draw anyway.
func test_the_ground_starts_from_its_own_tuned_band() -> void:
	var material := _material()
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter("band_threshold")), _renderer.band_threshold, 0.0001,
		"the terrain does not ship with the band it was tuned to"
	)
	var tint: Vector3 = material.get_shader_parameter("light_tint")
	assert_almost_eq(
		tint.x, 1.0, 0.0001,
		"the terrain starts out tinted, so an untinted preset could never restore it"
	)


# --- what the terrain owns --------------------------------------------------

## The second band's colour, and the reason it is a palette index rather than a
## multiply: the grain dithers between two adjacent entries in the table, so
## every pixel it produces is a colour a model could have been painted with.
func test_the_grain_dithers_between_two_tones_that_are_both_in_the_table() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	var material := _material()
	if material == null or bible == null:
		return
	var lit: Color = material.get_shader_parameter("snow_lit")
	var grain: Color = material.get_shader_parameter("snow_grain_tone")
	assert_true(bible.contains(lit), "the lit band is #%s, off the table" % lit.to_html(false))
	assert_true(
		bible.contains(grain),
		"the grain tone is #%s, off the table -- which is the one thing perturbing the "
			% grain.to_html(false)
			+ "threshold rather than the colour was supposed to make impossible"
	)
	assert_true(lit != grain, "the grain tone is the lit tone, so the grain does nothing")


## Barely visible, per style document section 15. The jitter is measured against
## the spread of Lambert values the field actually produces: flat ground sits at
## sin(21.5) = 0.366 and the drift profile keeps the median slope near 4 degrees,
## which is about +/-0.06 of Lambert. A jitter far above that stops reading as
## surface and starts reading as bumpiness that is not there.
func test_the_grain_is_small_enough_to_be_a_surface_rather_than_a_texture() -> void:
	assert_true(
		_renderer.grain_amount > 0.0,
		"the snow has no grain at all, so the field is still one flat fill"
	)
	assert_true(
		_renderer.grain_amount <= 0.12,
		"the grain jitters the band by %f, which is twice the Lambert spread the terrain's "
			% _renderer.grain_amount
			+ "own slopes produce -- it will read as bumps the ground does not have"
	)


## The scale is the other half of "barely visible". A metre-scale noise on a
## 44 cm mesh is pixel grain; the document's example is adjacent patches of very
## slightly different value, which is metres across.
func test_the_grain_is_patches_rather_than_speckle() -> void:
	assert_true(
		_renderer.grain_scale > 0.0, "the grain has no scale, so it is one constant offset"
	)
	var wavelength := 1.0 / _renderer.grain_scale
	assert_true(
		wavelength >= 2.0,
		"the grain repeats every %.2f m, which is speckle rather than the soft patches "
			% wavelength
			+ "style document section 15 asks for"
	)


# --- the snow arriving on top of the baked layer ----------------------------
#
# 道路会被积雪覆盖一部分. The road and the ploughed furrows are baked once into a
# window the wind must never touch (Art Bible section 3), so what the weather
# does to them is not erase but BURY -- and the same scalar that whitens the
# roofs is what does it, because it is the same snow.


## The formula in src/rendering/snow_ground.gdshader, mirrored, so the shape of
## the burial can be asserted without a frame. `burial` is what the terrain
## pushes: cover * static_burial_share.
func _buried(value: float, burial: float, power: float) -> float:
	return pow(value, lerpf(1.0, power, clampf(burial, 0.0, 1.0)))


## The scalar has to arrive on the ground, or the road goes on being cut once at
## startup and never touched again.
func test_the_ground_takes_the_snow_that_has_settled_on_it() -> void:
	_renderer.apply_snow_cover(0.8)
	var material := _material()
	assert_not_null(material)
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter("static_burial")),
		0.8 * _renderer.static_burial_share, 0.0001,
		"the accumulation did not reach the baked layer"
	)


## Nothing is buried before anything has settled, so a scene with no
## accumulation node in it draws the road exactly as it was cut.
func test_the_ground_starts_with_the_road_exactly_as_it_was_cut() -> void:
	var material := _material()
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter("static_burial")), 0.0, 0.0001,
		"the road arrives already snowed over, so there is no bare state to bury from"
	)


## THE POINT OF THE PROFILE, and the reason the road is baked graded rather than
## flat. A power buries by weight: the faint drifted verge goes, the packed bed
## fades, and the strips the wheels wore stay. The road NARROWS. Buried by a
## flat multiply instead, the whole width would fade together and the result is
## a smudge rather than a road under snow.
func test_the_snow_fills_the_road_in_from_its_edges() -> void:
	var burial: float = _renderer.static_burial_share
	var power: float = _renderer.static_burial_power
	var verge := _buried(0.16, burial, power)
	var bed := _buried(0.44, burial, power)
	var worn := _buried(0.88, burial, power)
	assert_true(
		verge < 0.10,
		"the drifted verge is still at %.3f under a full winter, so the road never narrows"
			% verge
	)
	assert_true(
		worn > 0.55,
		"the worn strips are down to %.3f, so the road the traffic actually wore has gone "
			% worn
			+ "under with everything else"
	)
	assert_true(
		worn / maxf(verge, 0.0001) > 0.88 / 0.16,
		"the burial did not open the gap between the worn strips and the verge, so the road "
		+ "is fading evenly rather than filling in from its edges"
	)
	assert_true(bed < 0.88 and bed > verge, "the carriageway must sit between the two")


## Rule 11 is the constraint on how far this may go: the marks in the snow are
## the ONLY texture the picture has, and a winter that took the ploughed field
## away would take the frame's detail with it.
func test_the_snow_never_takes_the_ploughed_field_away() -> void:
	var deepest := _buried(0.85, 1.0, _renderer.static_burial_power)
	assert_true(
		deepest > 0.4,
		"at full burial a furrow cut at 0.85 is left at %.3f -- Art Bible rule 11 says these "
			% deepest
			+ "lines are the only detail an otherwise empty white field has"
	)


## The depth every mark on the ground is cut at -- prints, furrows, the road --
## is authored here and read by the shader, so it has to arrive there. There was
## no cover on this at all, and it is the one uniform whose value the two tests
## below reason about.
func test_the_depth_the_ground_cuts_a_mark_at_reaches_the_material() -> void:
	var material := _material()
	assert_not_null(material)
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter("track_depth")), _renderer.track_depth, 0.000001,
		"the ground draws its marks at a different depth from the one authored"
	)


## ...and surviving in the MASK is not the same as surviving on the SCREEN.
##
## The test above proves the buried furrow still has a value. This one proves it
## still has a SHADOW, which is the only thing that actually puts it in the
## picture -- the marks are drawn by the reconstructed normal, so what has to
## clear the cel band is a slope, not a number.
##
## The arithmetic is the shader's own, in four steps:
##
##   1. the deepest burial the shader will ever apply is `static_burial_share`
##      at a cover of 1, so the furrow's baked 0.85 arrives as 0.85^(that);
##   2. `track_height()` scales it by `track_depth`, and `track_gradient()`
##      reads the result by central difference over 2 * `track_normal_epsilon`
##      -- 12 cm, which is WIDER than the furrow's own 11 cm half-width, so the
##      whole drop lands inside one difference and nothing is left over to make
##      the flank steeper than this;
##   3. that gradient tilts the surface normal by atan(gradient) from vertical;
##   4. the flank facing away from the sun has N.L = sin(sun_angle - tilt), so
##      it is unlit exactly when the tilt passes the sun's own elevation.
##
## The MARGIN is the number this asserts, because a flank that arrives at the
## band with nothing to spare is a flank whose shadow is a line rather than a
## face -- and the band has `band_softness` of feathering either side of it, so
## "just past the threshold" is not yet a shadow anybody can see.
##
## Measured at 1600x1000 under `pale_day`, sweeping `track_depth` and counting
## the ground pixels that land in the shade band:
##
##     track_depth   margin   prints   ploughed field   road
##     0.06825       -0.1 deg  1.34 %   0.32 %           7.64 %
##     0.095          5.4      1.53     0.60             7.11
##     0.115         12.0      1.84     0.83             7.41
##     0.1365        16.1      1.91     1.12             7.05
##
## The road barely moves at any of them, which is the shader's own point about a
## wide mark: it has no gradient anywhere except at its two edges and is carried
## by `static_tint_boost` rather than by its depth. And past 0.115 the prints
## stop gaining (1.84 -> 1.91) while the trail visibly stops reading as a chain
## of pockets and becomes one dark ribbon. So the useful range ends there.
func test_a_buried_ploughed_furrow_still_casts_a_shadow_to_be_seen_by() -> void:
	var farmstead := Farmstead.new()
	var strength: float = farmstead.furrow_strength
	var half_width: float = farmstead.furrow_radius
	farmstead.free()

	var epsilon: float = _renderer.track_normal_epsilon
	assert_true(
		half_width <= 2.0 * epsilon,
		"the furrow is %.3f m wide against a %.3f m normal epsilon, so the drop no longer "
			% [half_width, 2.0 * epsilon]
			+ "lands inside one central difference and this test's arithmetic is wrong"
	)

	# At a cover of 1 the shader's `static_burial` is `static_burial_share`, not 1
	# -- TerrainRenderer.apply_snow_cover() multiplies them. Asking _buried() for
	# a burial of 1 would test a winter this world cannot have.
	var buried := _buried(strength, _renderer.static_burial_share, _renderer.static_burial_power)
	var gradient: float = buried * _renderer.track_depth / (2.0 * epsilon)
	var tilt := rad_to_deg(atan(gradient))
	var preset: LightingPreset = load("res://data/lighting/pale_day.tres")
	var margin := tilt - preset.sun_angle_degrees

	assert_true(
		margin > 8.0,
		"a ploughed furrow under the deepest snow this weather can lay tilts its flank "
			+ "%.1f deg against a sun %.1f deg up -- %.1f deg of margin. " % [
				tilt, preset.sun_angle_degrees, margin
			]
			+ "Art Bible rule 11 spends the frame's whole detail budget on these lines, and at "
			+ "this depth they arrive at the cel band rather than past it"
	)


## Continuous in the burial as well as in space, which is the same requirement
## the whole task carries: the accumulation walks, so the road must fill in as it
## walks rather than at some threshold along the way.
func test_the_road_fills_in_continuously_as_the_snow_arrives() -> void:
	var power: float = _renderer.static_burial_power
	var worst := 0.0
	var previous := _buried(0.44, 0.0, power)
	var burial := 0.005
	while burial <= 1.0:
		var now := _buried(0.44, burial, power)
		worst = maxf(worst, absf(now - previous))
		previous = now
		burial += 0.005
	assert_true(
		worst < 0.01,
		"the road's bed moves %.4f for half a percent of burial, which is a step" % worst
	)


## The composition rule from the brief, as a gate: the preset sets where the band
## sits and the noise jitters it around that. If the terrain wrote its own
## threshold over the preset's, wiring the presets up would have achieved
## nothing.
func test_the_grain_does_not_overwrite_the_band_the_preset_set() -> void:
	_renderer.apply_world_shading(0.29, 0.11, Color.WHITE)
	var material := _material()
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter("band_threshold")), 0.29, 0.0001,
		"the grain overwrote the preset's band"
	)
	assert_almost_eq(
		float(material.get_shader_parameter("grain_amount")), _renderer.grain_amount, 0.0001,
		"the grain is not a separate uniform, so the two cannot compose"
	)


## The playable terrain is deliberately high-density, but the camera must never
## be able to see its finite edge. The horizon skirt starts exactly where the
## dense mesh has already flattened, then continues with the same shader and
## material. A background-coloured diamond here is a visible renderer boundary,
## not an acceptable stylised snow shape.
func test_the_horizon_skirt_is_a_continuous_shared_material_extension() -> void:
	var skirt := _renderer.get_node_or_null("HorizonSkirt") as MeshInstance3D
	assert_not_null(skirt, "TerrainRenderer did not create the horizon skirt")
	if skirt == null:
		return
	assert_eq(
		skirt.material_override, _material(),
		"the horizon uses a different material, so it can reveal a colour seam at the dense terrain edge"
	)
	assert_not_null(skirt.mesh, "the horizon skirt has no mesh to cover the finite terrain plane")
	if skirt.mesh == null:
		return
	var arrays := skirt.mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var perimeter := _renderer.horizon_edge_segments * 4
	var rings := _renderer.horizon_radial_segments
	assert_eq(
		vertices.size(), perimeter * (rings + 1),
		"the horizon must be a regular ring, not four screen-sized trapezoids"
	)
	assert_eq(normals.size(), vertices.size(), "every horizon vertex needs an explicit upward normal")
	assert_eq(
		indices.size(), perimeter * rings * 6,
		"every horizon quad needs two upward-facing triangles; a missing band exposes the world background"
	)
	assert_true(indices.size() > 24, "eight giant horizon triangles can become visible diagonal fields")
	for triangle in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[triangle]]
		var b: Vector3 = vertices[indices[triangle + 1]]
		var c: Vector3 = vertices[indices[triangle + 2]]
		assert_true(
			(b - a).cross(c - a).y < 0.0,
			"horizon triangle %d is back-facing under Godot's PlaneMesh winding, exposing the sky as a diamond" % (triangle / 3)
		)


## This pins the geometry rather than a screenshot: the first ring is exactly
## the dense mesh's outer edge, and the second is far enough beyond any shipped
## framing that the player cannot turn the flat background into a hard diamond.
func test_the_horizon_skirt_begins_at_the_flat_dense_mesh_edge_and_reaches_far_beyond_it() -> void:
	assert_true(
		_renderer.has_method("horizon_skirt_mesh"),
		"TerrainRenderer needs a testable horizon ring builder rather than a hidden second plane"
	)
	if not _renderer.has_method("horizon_skirt_mesh"):
		return
	var skirt: ArrayMesh = _renderer.horizon_skirt_mesh(_renderer.ground_size, _renderer.horizon_size)
	var arrays := skirt.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var inner_half := _renderer.ground_size * 0.5
	var outer_half: float = float(_renderer.get("horizon_size")) * 0.5
	var inner_corners := 0
	var outer_corners := 0
	for vertex in vertices:
		if is_equal_approx(absf(vertex.x), inner_half) and is_equal_approx(absf(vertex.z), inner_half):
			inner_corners += 1
		if is_equal_approx(absf(vertex.x), outer_half) and is_equal_approx(absf(vertex.z), outer_half):
			outer_corners += 1
	assert_eq(inner_corners, 4, "the skirt starts away from the dense mesh, leaving a visible gap")
	assert_eq(outer_corners, 4, "the outer ring is incomplete, so an edge can still enter a wide shot")
	assert_true(
		float(_renderer.get("horizon_size")) >= _renderer.ground_size * 4.0,
		"the horizon is too close to protect the widest capture/gameplay framing from the terrain edge"
	)


## The raster field is square because it is an efficient moving data window;
## that must never become a square in the picture. The old shader faded with
## `min(uv, 1 - uv)`, so two positions on the same x coordinate received the
## identical fade regardless of z. Under the orthographic camera that became
## the unmistakable diamond in the main-scene capture.
func test_the_visual_field_fade_is_not_an_axis_aligned_square() -> void:
	assert_true(
		_renderer.has_method("visual_field_weight"),
		"TerrainRenderer needs a testable visual field profile so a square raster boundary cannot ship as a square snow boundary"
	)
	if not _renderer.has_method("visual_field_weight"):
		return
	var side: float = float(_renderer.visual_field_weight(Vector2(0.95, 0.50)))
	var cornerward: float = float(_renderer.visual_field_weight(Vector2(0.95, 0.75)))
	assert_true(
		absf(side - cornerward) > 0.05,
		"two points with the same x have the same %.3f visual weight, so the field still fades on a straight square edge" % side
	)
	var shader_code := FileAccess.get_file_as_string(SNOW_SHADER_PATH)
	assert_false(shader_code.is_empty(), "the versioned runtime snow shader is missing: %s" % SNOW_SHADER_PATH)
	assert_true(
		shader_code.contains("length(uv - vec2(0.5))"),
		"the runtime shader is not using the radial visual profile this test measured"
	)
	assert_false(
		shader_code.contains("min(to_edge.x, to_edge.y)"),
		"the runtime shader still derives its falloff from a square edge distance"
	)
	assert_true(
		shader_code.contains("vec2 bent = p + (warp - 0.5) * 2.4"),
		"the snow grain still samples a bare axis-aligned value-noise grid, so broad captures can expose square texture cells"
	)
	assert_true(
		shader_code.contains("grain_value_noise(rotated * 1.73"),
		"the snow grain needs a rotated secondary octave; a single warped square lattice can still read as a map grid"
	)


## The continuation must leave the playable centre untouched, then settle over
## tens of metres rather than forming a narrow height ramp that reads as a
## texture seam. These samples are on a radius where the pure profile is
## monotonic, avoiding any claim about the deliberately irregular world warp.
func test_the_visual_field_fade_is_broad_and_c1_at_its_flat_horizon() -> void:
	assert_true(
		_renderer.has_method("visual_field_weight"),
		"TerrainRenderer needs a testable visual field profile so a square raster boundary cannot ship as a square snow boundary"
	)
	if not _renderer.has_method("visual_field_weight"):
		return
	var centre := Vector2(0.5, 0.5)
	assert_almost_eq(
		_renderer.visual_field_weight(centre), 1.0, 0.000001,
		"the snow field is already visually altered at the player's centre"
	)
	var largest_step := 0.0
	var previous: float = float(_renderer.visual_field_weight(Vector2(0.50, 0.50)))
	for index in range(1, 51):
		var uv := Vector2(0.50 + float(index) * 0.01, 0.50)
		var current: float = float(_renderer.visual_field_weight(uv))
		largest_step = maxf(largest_step, absf(current - previous))
		previous = current
	assert_true(
		largest_step < 0.06,
		"the visual field loses %.3f weight in one percent of its width, which is a visible terrain edge rather than a broad settling" % largest_step
	)
	var dense_edge := Vector2(
		0.5 + _renderer.ground_size / (2.0 * SnowField.EXTENT_M),
		0.5
	)
	assert_almost_eq(
		_renderer.visual_field_weight(dense_edge), 0.0, 0.000001,
		"the dense mesh reaches its shared horizon edge with live displacement, so the skirt can form a geometric seam"
	)


## A camera at the normal 10.5 m gameplay stop cannot see the 120 m data
## boundary, which is why this defect escaped despite regular captures. Keep a
## real-main-scene 100 m shutter in the project and make its framing independent
## of command-line memory. This fixture did not exist at c34aa92, so checking it
## in together with the radial profile makes that former regression red.
func test_the_main_scene_has_a_deterministic_wide_snow_seam_capture() -> void:
	assert_true(
		FileAccess.file_exists(SEAM_CAPTURE_PATH),
		"missing the real-main-scene seam capture: %s" % SEAM_CAPTURE_PATH
	)
	assert_true(
		FileAccess.file_exists(SEAM_CAPTURE_SCRIPT_PATH),
		"missing the seam capture script: %s" % SEAM_CAPTURE_SCRIPT_PATH
	)
	var scene_code := FileAccess.get_file_as_string(SEAM_CAPTURE_PATH)
	var script_code := FileAccess.get_file_as_string(SEAM_CAPTURE_SCRIPT_PATH)
	assert_true(
		scene_code.contains("res://scenes/main.tscn"),
		"the seam capture must instance the actual main scene rather than a snow-only mock"
	)
	assert_true(
		script_code.contains("extends \"res://tools/capture_frame.gd\""),
		"the seam capture must exercise the shared real-route and real-shutter harness"
	)
	assert_true(
		script_code.contains("SEAM_PROBE_ORTHO := 100.0"),
		"the seam capture must force the wide view that exposed the old square field boundary"
	)
