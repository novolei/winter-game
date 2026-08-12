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


## The formula in assets/shaders/snow_ground.gdshader, mirrored, so the shape of
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
