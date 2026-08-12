extends TestCase

## The gate on res://data/ui/tokens.tres -- the design tokens of UI design
## document sections 2.1 through 2.4.
##
## The colour half of this file exists because of one failure mode that nothing
## else would catch. UI rule 3 gives warm exactly one meaning, and constraint 6
## forbids a hex literal outside tools/ -- but a GENERATED resource satisfies
## both while still being able to drift: edit color_bible.tres, forget to re-run
## tools/generate_ui_tokens.gd, and the interface is off-palette with nothing
## anywhere complaining. So every token is asserted to be the palette entry the
## design document names it as, and the assertion reads the palette rather than
## a hex constant. That is not circular: it tests the RELATIONSHIP -- "ink/primary
## is the brightest snow" -- which is the thing the document actually specifies.

const TOKENS_PATH := "res://data/ui/tokens.tres"
const PALETTE_PATH := "res://data/palette/color_bible.tres"

var _tokens: UITokens
var _bible: ColorBible

func before_each() -> void:
	# CACHE_MODE_IGNORE: trap 6 -- ResourceLoader hands every caller the same
	# instance, so a test that mutated one would poison every later test.
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens
	_bible = ResourceLoader.load(PALETTE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ColorBible

func test_the_resource_ships_and_is_a_ui_tokens() -> void:
	assert_not_null(_tokens, "%s must exist -- run tools/generate_ui_tokens.gd" % TOKENS_PATH)
	assert_not_null(_bible, "%s must exist" % PALETTE_PATH)

# --- colour -----------------------------------------------------------------

## Every token is one of the twelve. This is the constraint-6 gate: a token that
## drifted off the palette fails here even though no .gd file holds a literal.
func test_every_colour_token_is_in_the_palette() -> void:
	assert_not_null(_tokens)
	assert_not_null(_bible)
	if _tokens == null or _bible == null:
		return
	for name in _tokens.colour_token_names():
		var colour: Color = _tokens.colour(name)
		assert_true(
			_bible.contains(colour),
			"token %s is %s, which is not one of the twelve in the colour bible" % [name, colour.to_html(false)]
		)

## The specific mapping of design document section 2.1. Read out of the palette,
## never written down here.
func test_the_tokens_map_where_the_design_says_they_map() -> void:
	assert_not_null(_tokens)
	assert_not_null(_bible)
	if _tokens == null or _bible == null:
		return
	assert_eq(_tokens.ink_primary, _bible.snow_tones[0], "ink/primary is the brightest snow")
	assert_eq(_tokens.ink_secondary, _bible.snow_tones[2], "ink/secondary is mid snow")
	assert_eq(_tokens.ink_muted, _bible.snow_tones[4], "ink/muted is the darkest snow")
	assert_eq(_tokens.line_hairline, _bible.structure_tones[0], "line/hairline is the lightest structure")
	assert_eq(_tokens.line_deep, _bible.structure_tones[2], "line/deep is dark structure")
	assert_eq(_tokens.scrim_veil, _bible.structure_tones[3], "scrim/veil is the darkest structure")
	assert_eq(_tokens.life_warm, _bible.warm_tones[2], "life/warm is the bright amber")
	assert_eq(_tokens.life_ember, _bible.warm_tones[1], "life/ember is rust orange")
	assert_eq(_tokens.alarm_blood, _bible.warm_tones[0], "alarm/blood is the deep red")

## UI rule 3 -- warm carries exactly one meaning -- has a corollary that can be
## checked mechanically: the three tokens allowed to be warm are the only ones
## that are, and every other token is a cold one.
func test_only_the_three_warm_tokens_are_warm() -> void:
	assert_not_null(_tokens)
	assert_not_null(_bible)
	if _tokens == null or _bible == null:
		return
	var allowed := [&"life/warm", &"life/ember", &"alarm/blood"]
	for name in _tokens.colour_token_names():
		var warm := _bible.is_warm(_tokens.colour(name))
		if name in allowed:
			assert_true(warm, "%s must be one of the three warm tones" % name)
		else:
			assert_false(warm, "%s is warm, but only life/* and alarm/blood may be" % name)

## alarm/blood and life/warm are both warm and must never be confusable: one
## says you are alive, the other says you are losing. Section 2.1 leans on them
## being two steps apart in lightness.
func test_the_alarm_is_far_darker_than_the_life() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	var alarm := _tokens.alarm_blood.get_luminance()
	var life := _tokens.life_warm.get_luminance()
	assert_true(life > alarm * 2.0,
		"life/warm (%.3f) must be far brighter than alarm/blood (%.3f)" % [life, alarm])

func test_the_opacity_ladder_is_the_five_documented_steps() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	var steps := _tokens.opacity_steps
	assert_eq(steps.size(), 5, "section 2.1 gives five steps and no intermediates")
	var expected := [1.0, 0.72, 0.48, 0.24, 0.12]
	for i in mini(steps.size(), expected.size()):
		assert_almost_eq(steps[i], expected[i], 0.001, "opacity step %d" % i)

# --- geometry ---------------------------------------------------------------

func test_the_reference_space_is_1080p_on_an_eight_pixel_grid() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_eq(_tokens.reference_height, 1080)
	assert_eq(_tokens.grid_unit, 8)
	assert_almost_eq(_tokens.edge_fraction, 0.075, 0.0001)

## Section 2.3 takes the breathing border off the SHORT edge, so that under the
## project's `expand` stretch a 21:9 window and a 4:3 window show a border of the
## same visual width. Measuring each edge against its own axis would make the
## left margin balloon on a wide monitor.
func test_the_breathing_border_comes_off_the_short_edge() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_almost_eq(_tokens.edge_pixels(Vector2(1920, 1080)), 81.0, 0.001)
	# Ultrawide: the border must not grow with the extra width.
	assert_almost_eq(_tokens.edge_pixels(Vector2(2560, 1080)), 81.0, 0.001)
	# Portrait, for completeness -- the short edge is now the width.
	assert_almost_eq(_tokens.edge_pixels(Vector2(1080, 1920)), 81.0, 0.001)

## Design pixels are authored against 1080 and scale with the short edge, which
## is the same rule the border follows -- so a layout cannot drift apart from its
## own margins at another resolution.
func test_design_pixels_scale_off_the_short_edge() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_almost_eq(_tokens.scale_for(Vector2(1920, 1080)), 1.0, 0.0001)
	assert_almost_eq(_tokens.scale_for(Vector2(2560, 1440)), 1440.0 / 1080.0, 0.0001)
	assert_almost_eq(_tokens.scale_for(Vector2(3440, 1440)), 1440.0 / 1080.0, 0.0001)
	assert_almost_eq(_tokens.design_px(96.0, Vector2(1920, 1080)), 96.0, 0.001)
	assert_almost_eq(_tokens.design_px(96.0, Vector2(2560, 1440)), 128.0, 0.001)

# --- motion -----------------------------------------------------------------

## Section 2.4, and section 1.2's rule that no element may skip a phase: every
## duration must be positive, or an element could be born or die instantly.
func test_every_motion_duration_is_positive() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	var durations := {
		"bloom": _tokens.bloom_seconds,
		"bloom_heavy": _tokens.bloom_heavy_seconds,
		"hold": _tokens.hold_seconds,
		"drift": _tokens.drift_seconds,
		"drift_fast": _tokens.drift_fast_seconds,
		"drift_long": _tokens.drift_long_seconds,
		"breathe": _tokens.breathe_seconds,
		"ripple": _tokens.ripple_seconds,
	}
	for name in durations:
		assert_true(float(durations[name]) > 0.0,
			"%s is %.3f -- a phase of zero length is an element that appears or vanishes instantly, which section 1.2 forbids"
				% [name, durations[name]])

func test_the_durations_are_the_documented_ones() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_almost_eq(_tokens.bloom_seconds, 0.20, 0.0001)
	assert_almost_eq(_tokens.bloom_heavy_seconds, 0.32, 0.0001)
	assert_almost_eq(_tokens.hold_seconds, 2.00, 0.0001)
	assert_almost_eq(_tokens.drift_seconds, 0.90, 0.0001)
	assert_almost_eq(_tokens.drift_fast_seconds, 0.40, 0.0001)
	assert_almost_eq(_tokens.drift_long_seconds, 1.60, 0.0001)
	assert_almost_eq(_tokens.breathe_seconds, 4.00, 0.0001)
	assert_almost_eq(_tokens.ripple_seconds, 0.30, 0.0001)
	assert_almost_eq(_tokens.cold_snap_scale, 1.40, 0.0001)

## Leaving is crisper than arriving everywhere except the deliberate slow exits.
## Section 5.1: "离开一个地方应该干脆".
func test_the_fast_exit_is_faster_than_the_normal_one() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_true(_tokens.drift_fast_seconds < _tokens.drift_seconds)
	assert_true(_tokens.drift_long_seconds > _tokens.drift_seconds)

## 0.25 Hz is named in section 2.4 as the rate warm things breathe at, and the
## period is what the code actually uses. They have to agree.
func test_the_warm_breath_is_a_quarter_hertz() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_almost_eq(1.0 / _tokens.breathe_seconds, 0.25, 0.0001)

# --- fonts ------------------------------------------------------------------

## Section 2.2. Every path must resolve, or the interface silently falls back to
## whatever Godot's default face is -- which looks like a design decision rather
## than a missing file.
func test_every_font_file_ships() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	for entry in _tokens.font_paths():
		assert_true(ResourceLoader.exists(entry),
			"font %s is missing -- see assets/fonts/README.md" % entry)

## The weights of section 2.2, and the one that is a trap: NotoSerifSC-VF's
## weight axis bottoms out at 200, so the display CJK weight cannot be lowered
## even though every other family here could go to 100.
func test_the_font_weights_are_the_documented_ones() -> void:
	assert_not_null(_tokens)
	if _tokens == null:
		return
	assert_eq(_tokens.display_latin_weight, 300, "Cormorant Garamond Light")
	assert_eq(_tokens.display_cjk_weight, 200, "Noto Serif SC ExtraLight -- the floor of its axis")
	assert_eq(_tokens.interface_latin_weight, 300, "Inter Light")
	assert_eq(_tokens.interface_cjk_weight, 300, "Noto Sans SC Light")
