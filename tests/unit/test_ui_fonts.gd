extends TestCase

## The three font families of UI design document section 2.2, and the one thing
## about them that raises no error when it is wrong.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE IS ACTUALLY GUARDING
## ---------------------------------------------------------------------------
## Noto Serif SC and Noto Sans SC ship their own Latin glyphs -- the Source Han
## families were drawn with a matching Latin. Godot resolves a font chain per
## GLYPH: base font first, then fallbacks. So a chain with Noto in the base slot
## renders Latin out of Noto and NEVER REACHES Cormorant or Inter, with nothing
## logged and nothing missing. The text is present, legible, correctly spaced,
## and in the wrong typeface -- the entire section 2.2 decision, silently undone.
##
## Reading the chain's configuration cannot catch that; a chain built the wrong
## way round is still a valid chain. So the tests below MEASURE: Latin set
## through the chain must come out the width Cormorant sets it, and must NOT come
## out the width Noto sets it. That is the only assertion that distinguishes the
## two arrangements.
##
## The same trick does not work for CJK -- every full-width glyph advances
## exactly 1em whichever family drew it, so a width comparison there returns a
## false negative. This cost a debugging cycle in the browser prototype before it
## cost one here; the CJK side is checked by coverage instead.

const UIFontsScript := preload("res://src/ui/ui_fonts.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"

const LATIN := "THE LAST LONG NIGHT"
const CJK := "长夜将尽"
const SIZE := 48

var _tokens: UITokens
var _fonts

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens
	_fonts = UIFontsScript.new()
	_fonts.build(_tokens)

func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x

# --- the chains exist -------------------------------------------------------

func test_all_three_families_build() -> void:
	assert_not_null(_fonts.display, "display family")
	assert_not_null(_fonts.interface, "interface family")
	assert_not_null(_fonts.instrument, "instrument family")

## Section 2.2's weights, on the variations rather than in the document. 200 is
## the floor of NotoSerifSC-VF's axis, not a preference.
func test_the_weights_are_set_on_the_variations() -> void:
	assert_eq(int(_fonts.display.variation_opentype.get(&"wght", 0)), 300, "Cormorant Light")
	assert_eq(int(_fonts.display_cjk.variation_opentype.get(&"wght", 0)), 200, "Noto Serif SC ExtraLight")
	assert_eq(int(_fonts.interface.variation_opentype.get(&"wght", 0)), 300, "Inter Light")
	assert_eq(int(_fonts.interface_cjk.variation_opentype.get(&"wght", 0)), 300, "Noto Sans SC Light")

func test_the_cjk_face_is_the_fallback_and_not_the_base() -> void:
	assert_true(_fonts.display.fallbacks.has(_fonts.display_cjk),
		"the display chain must fall back to Noto Serif SC")
	assert_true(_fonts.interface.fallbacks.has(_fonts.interface_cjk),
		"the interface chain must fall back to Noto Sans SC")

# --- the ordering, measured -------------------------------------------------

## THE TEST THIS FILE EXISTS FOR. Latin through the chain must measure as
## Cormorant sets it, not as Noto sets it.
func test_latin_is_set_by_the_latin_face_and_not_by_notos_own_latin() -> void:
	var through_chain := _width(_fonts.display, LATIN)
	var cormorant_alone := _width(_fonts.display_latin_only, LATIN)
	var noto_alone := _width(_fonts.display_cjk, LATIN)

	assert_true(through_chain > 0.0, "the chain set no width at all")
	assert_true(noto_alone > 0.0, "Noto Serif SC has its own Latin -- that is the whole hazard")
	# The two faces must actually differ, or this test proves nothing.
	assert_true(absf(cormorant_alone - noto_alone) > 1.0,
		"Cormorant (%.1f) and Noto (%.1f) set this string to the same width, so the measurement cannot tell them apart"
			% [cormorant_alone, noto_alone])
	assert_almost_eq(through_chain, cormorant_alone, 0.5,
		"Latin came out %.1f wide; Cormorant sets it %.1f and Noto sets it %.1f -- the chain is the wrong way round"
			% [through_chain, cormorant_alone, noto_alone])

func test_interface_latin_is_set_by_inter_and_not_by_notos_own_latin() -> void:
	var through_chain := _width(_fonts.interface, LATIN)
	var inter_alone := _width(_fonts.interface_latin_only, LATIN)
	var noto_alone := _width(_fonts.interface_cjk, LATIN)
	assert_true(absf(inter_alone - noto_alone) > 1.0,
		"Inter (%.1f) and Noto Sans (%.1f) measure the same, so this cannot discriminate"
			% [inter_alone, noto_alone])
	assert_almost_eq(through_chain, inter_alone, 0.5,
		"Latin came out %.1f; Inter sets it %.1f, Noto Sans sets it %.1f" % [through_chain, inter_alone, noto_alone])

## And the fallback must still work: Cormorant has no Chinese at all, so every
## CJK glyph has to come through to Noto or the menus render as boxes.
func test_chinese_falls_through_to_the_cjk_face() -> void:
	for chain in [_fonts.display, _fonts.interface]:
		for character in CJK:
			assert_true(chain.has_char(character.unicode_at(0)),
				"the chain cannot render %s" % character)

func test_the_latin_face_on_its_own_has_no_chinese() -> void:
	# Establishes that the previous test was actually exercising the fallback
	# rather than passing because the Latin face happened to cover CJK.
	assert_false(_fonts.display_latin_only.has_char(CJK.unicode_at(0)),
		"Cormorant is not supposed to have Chinese; if it does, the fallback test proves nothing")

# --- the instrument face ----------------------------------------------------

## Section 2.2 calls tabular figures a hard requirement rather than a
## preference: the Tab readout changes every frame, and proportional digits make
## a whole line jump sideways when 68 becomes 71.
func test_the_instrument_digits_are_all_the_same_width() -> void:
	var widths: Array[float] = []
	for digit in "0123456789":
		widths.append(_width(_fonts.instrument, digit))
	for i in range(1, widths.size()):
		assert_almost_eq(widths[i], widths[0], 0.01,
			"digit %d is %.3f wide but 0 is %.3f -- the readout will jitter" % [i, widths[i], widths[0]])

func test_a_changing_reading_keeps_the_same_width() -> void:
	assert_almost_eq(_width(_fonts.instrument, "68 %"), _width(_fonts.instrument, "71 %"), 0.01)
	assert_almost_eq(_width(_fonts.instrument, "40:00"), _width(_fonts.instrument, "03:14"), 0.01)

# --- failure behaviour ------------------------------------------------------

## A missing font file must not produce a chain that silently renders in
## whatever Godot's default face is. Building with nothing to build from returns
## nothing, so a caller has something to check.
func test_building_from_nothing_yields_nothing_rather_than_a_default_face() -> void:
	var empty = UIFontsScript.new()
	empty.build(null)
	assert_true(empty.display == null)
	assert_true(empty.interface == null)
	assert_true(empty.instrument == null)
	assert_false(empty.is_ready())

func test_a_built_set_reports_ready() -> void:
	assert_true(_fonts.is_ready())
