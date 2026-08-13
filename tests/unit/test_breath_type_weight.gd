extends TestCase

## The weight the breath layer's type is drawn at, and the defect that made it
## necessary: a weight can be set, stored, read back correctly, and never applied.
##
## ---------------------------------------------------------------------------
## WHAT WAS MEASURED
## ---------------------------------------------------------------------------
## Section 5.2's threshold note and section 5.10's time prompt are the only two
## places in the game that draw CJK at section 2.2's Body rung, and after the
## corner HUD was deleted they are also the only two places a number appears.
## Both stand on open snow with no plate, because rule 1 forbids one.
##
## The ink was corrected first (see task-w3-threshold-ink-report.md) and the text
## was still hard to read, because NOMINAL contrast -- what a colour is worth if a
## stroke covers a pixel -- is not DELIVERED contrast. A stroke thinner than a
## pixel never receives the full ink; antialiasing hands the player a blend of ink
## and snow. Measured in the real scene through tools/measure_type_weight.tscn, at
## 1920x1080 where Body 17 rasterises at exactly 17 device pixels, on lit
## `pale_day` snow:
##
##   element                        nominal   peak    core    px at full ink
##   the note's sentence  before      8.10     4.41    2.23    0 of 711
##   the note's sentence  after       8.09     8.10    6.27    93 of 963
##   the prompt's word    before      4.36     2.96    1.77    0 of 212
##   the prompt's word    after       4.36     4.37    3.93    46 of 348
##
## `core` is the tenth percentile of ink pixels -- the value the strongest tenth
## of the strokes clears -- and it is the verdict. `px at full ink` is the count
## that names the defect: before, NOT ONE PIXEL of either string was ever the
## colour it was authored in.
##
## ---------------------------------------------------------------------------
## AND THE CAUSE WAS NOT THE WEIGHT IN THE DOCUMENT
## ---------------------------------------------------------------------------
## `FontVariation.variation_opentype` keys the axis by its INTEGER tag code. A
## String or StringName key is stored, reads back identically, and is silently
## never applied. UIFonts shipped with `{ &"wght": weight }`, so every weight in
## section 2.2 was inert and each face rendered at its own file's default -- which
## for NotoSansSC-VF is 100 THIN, where the document asks for 300 Light.
##
## So the fix is not a heavier cut than the document specifies. It is section
## 2.2's own 300 finally arriving, plus one step for the layer that has no
## background of its own. THE TYPE SCALE IS NOT TOUCHED, and the last test here
## is what says so.
##
## The tests below assert the weight the text server REPORTS, never the
## dictionary that requested it. Asserting the request is what let this ship.

const UIFontsScript := preload("res://src/ui/ui_fonts.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"
const LAYOUT_PATH := "res://data/ui/vital_layout.tres"
const COPY_PATH := "res://data/ui/threshold_copy.tres"
const PROMPT_PATH := "res://data/ui/time_prompt.tres"

## Section 2.2's Body rung. Written here rather than read from the subject: this
## file's last test exists to fail if the scale moves, and reading the number out
## of the thing under test would make it agree with any move.
const BODY_DESIGN_PX := 17.0

var _tokens: UITokens = null
var _layout: VitalLayout = null
var _copy: ThresholdCopyMap = null
var _prompt: TimePromptData = null
var _fonts = null


func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout
	_copy = ResourceLoader.load(COPY_PATH) as ThresholdCopyMap
	_prompt = ResourceLoader.load(PROMPT_PATH) as TimePromptData
	_fonts = UIFontsScript.new()
	_fonts.build(_tokens)


## The weight a chain will actually RENDER at, asked of the text server.
##
## Godot omits a variation coordinate that equals the font file's own default, so
## an absent coordinate is not "no weight" -- it is the default, and the default
## is what will be drawn. Resolved to it here, which is the only way this returns
## the number a player would see.
func _applied_weight(font: Font, index: int) -> int:
	if font == null:
		return -1
	var ts := TextServerManager.get_primary_interface()
	var rids := font.get_rids()
	if index >= rids.size():
		return -1
	var tag := ts.name_to_tag("wght")
	var coordinates: Dictionary = ts.font_get_variation_coordinates(rids[index])
	if coordinates.has(tag):
		return int(coordinates[tag])
	# `font_supported_variation_list`, not `font_get_supported_variation_list`:
	# the getter spelling exists on FontFile and NOT on the text server, and
	# calling it aborts the function rather than returning null -- so every
	# assertion after it would silently never run.
	var axes: Dictionary = ts.font_supported_variation_list(rids[index])
	if axes.has(tag):
		return int((axes[tag] as Vector3i).z)
	return 0


## The axis a face really has, as (min, max, default).
func _axis(path: String) -> Vector3i:
	var file := ResourceLoader.load(path) as FontFile
	if file == null:
		return Vector3i(-1, -1, -1)
	var ts := TextServerManager.get_primary_interface()
	var axes := file.get_supported_variation_list()
	return axes.get(ts.name_to_tag("wght"), Vector3i(-1, -1, -1))


## Every line the game can actually surface at Body 17, out of the data rather
## than invented here. A specimen nobody ships proves nothing about the game.
func _live_strings() -> Array[String]:
	var strings: Array[String] = []
	if _copy != null:
		for entry in _copy.entries:
			if entry != null and entry.text != "":
				strings.append(entry.text)
	if _prompt != null:
		strings.append(_prompt.day_label)
		strings.append(_prompt.night_label)
	return strings


# --- the defect -----------------------------------------------------------------

## THE TEST THIS FILE EXISTS FOR. A weight that is requested must be rendered.
##
## Before the fix this failed on both interface faces and passed on both display
## faces -- because those two happen to ask for their font's own default, which is
## exactly why nobody saw it.
func test_every_weight_the_document_asks_for_is_the_weight_that_renders() -> void:
	var expected := [
		[_fonts.display, 0, _tokens.display_latin_weight, "display Latin (Cormorant)"],
		[_fonts.display, 1, _tokens.display_cjk_weight, "display CJK (Noto Serif SC)"],
		[_fonts.interface, 0, _tokens.interface_latin_weight, "interface Latin (Inter)"],
		[_fonts.interface, 1, _tokens.interface_cjk_weight, "interface CJK (Noto Sans SC)"],
	]
	for row in expected:
		var applied := _applied_weight(row[0], int(row[1]))
		assert_eq(applied, int(row[2]),
			"%s: the document asks for %d and the text server will render %d"
				% [row[3], int(row[2]), applied])


## And the same for the arbitrary-weight chains, which is where section 5.9's
## spatial typography and this task's breath layer both live. A weight that is
## only correct at the value the file already defaults to is not a working axis.
##
## THE WEIGHTS TESTED COME FROM THE FACES, not from a list written here. A face
## clamps an out-of-range weight silently -- Cormorant Garamond's axis starts at
## 300, so display_at(200, 200) renders 300 and reports 300, with nothing logged.
## Asking each chain only for weights both of its faces can actually reach is
## what keeps this test about the plumbing instead of about the clamp; the clamp
## itself is guarded by test_every_weight_asked_for_is_inside_the_faces_own_axis.
func test_an_arbitrary_weight_reaches_both_faces_of_a_chain() -> void:
	var chains := [
		["display", _tokens.display_latin_path, _tokens.display_cjk_path],
		["interface", _tokens.interface_latin_path, _tokens.interface_cjk_path],
	]
	for chain in chains:
		var latin := _axis(chain[1])
		var cjk := _axis(chain[2])
		assert_true(latin.x >= 0 and cjk.x >= 0, "%s: a face has no weight axis" % chain[0])
		if latin.x < 0 or cjk.x < 0:
			continue
		var low := maxi(latin.x, cjk.x)
		var high := mini(latin.y, cjk.y)
		assert_true(high > low, "%s: the two faces share no usable range" % chain[0])
		for weight in [low, (low + high) / 2, high]:
			var font: Font = (_fonts.display_at(weight, weight) if chain[0] == "display"
				else _fonts.interface_at(weight, weight))
			for index in [0, 1]:
				assert_eq(_applied_weight(font, index), weight,
					"%s chain, face %d: asked %d, got %d"
						% [chain[0], index, weight, _applied_weight(font, index)])


## A FontVariation wrapped around another FontVariation drops the inner one's
## weight for the base face while keeping it for the fallbacks -- measured on
## 4.7.1. That is the shape every caller reaches for when it wants to add
## tracking, and it reads as harmless, so it is pinned here rather than only
## described in a comment.
func test_wrapping_a_chain_to_add_tracking_would_lose_the_weight() -> void:
	var chain: Font = _fonts.interface_at(900, 900)
	assert_eq(_applied_weight(chain, 0), 900, "the chain itself must carry it")
	var wrapped := FontVariation.new()
	wrapped.base_font = chain
	wrapped.spacing_glyph = 1
	assert_false(_applied_weight(wrapped, 0) == 900,
		"wrapping no longer loses the base face's weight -- if the engine has been fixed, the spacing argument on interface_at() can go, and this test with it")


# --- the breath layer -----------------------------------------------------------

## Section 3's breath layer owns no background and may have no plate under it.
## Section 5.9 already made this call for the same layer's world-space form,
## moving its type from 200/300 to 600/500; this is the screen-space half of the
## same finding.
func test_the_breath_layer_is_heavier_than_type_on_a_background_it_owns() -> void:
	assert_true(_tokens.breath_cjk_weight > _tokens.interface_cjk_weight,
		"the breath layer draws on open snow and must not be lighter than a menu (%d vs %d)"
			% [_tokens.breath_cjk_weight, _tokens.interface_cjk_weight])
	assert_true(_tokens.breath_latin_weight >= _tokens.interface_latin_weight,
		"breath Latin %d is lighter than interface Latin %d"
			% [_tokens.breath_latin_weight, _tokens.interface_latin_weight])


## A weight outside the face's own axis is clamped by the rasteriser, silently, so
## the token would read 900 while the glyphs stopped getting heavier. Asserted
## against the FILE rather than a remembered range, so replacing a font file
## fails here and names the bound it broke.
func test_every_weight_asked_for_is_inside_the_faces_own_axis() -> void:
	var wanted := [
		[_tokens.interface_cjk_path, _tokens.breath_cjk_weight, "breath CJK"],
		[_tokens.interface_latin_path, _tokens.breath_latin_weight, "breath Latin"],
		[_tokens.interface_cjk_path, _tokens.interface_cjk_weight, "interface CJK"],
		[_tokens.interface_latin_path, _tokens.interface_latin_weight, "interface Latin"],
		[_tokens.display_cjk_path, _tokens.display_cjk_weight, "display CJK"],
		[_tokens.display_latin_path, _tokens.display_latin_weight, "display Latin"],
	]
	for row in wanted:
		var axis := _axis(row[0])
		assert_true(axis.x >= 0, "%s: %s has no weight axis at all" % [row[2], row[0]])
		if axis.x < 0:
			continue
		assert_true(int(row[1]) >= axis.x and int(row[1]) <= axis.y,
			"%s asks for %d and the face only goes %d..%d"
				% [row[2], int(row[1]), axis.x, axis.y])


# --- the two elements -----------------------------------------------------------

## Both Body 17 sites must draw through the breath weight, on BOTH faces. Reading
## the font object each element built is the only headless check available: the
## suite cannot rasterise, so what can be proved is which face the element will
## draw with.
func test_both_body_17_elements_draw_at_the_breath_weight() -> void:
	var note := ThresholdNote.new()
	note.build(_tokens, _fonts, _layout.row_for(&"core_temperature"),
		"呼吸变快了", 0.5, false, false)
	var arc := TimeArc.new()
	arc.build(_tokens, _fonts, _prompt)
	for row in [[note.get(&"_body"), "the threshold note"], [arc.get(&"_label_font"), "the time prompt"]]:
		assert_not_null(row[0], "%s built no font at all" % row[1])
		assert_eq(_applied_weight(row[0], 0), _tokens.breath_latin_weight,
			"%s draws Latin at %d, not the breath weight %d"
				% [row[1], _applied_weight(row[0], 0), _tokens.breath_latin_weight])
		assert_eq(_applied_weight(row[0], 1), _tokens.breath_cjk_weight,
			"%s draws CJK at %d, not the breath weight %d"
				% [row[1], _applied_weight(row[0], 1), _tokens.breath_cjk_weight])
	note.free()
	arc.free()


## Section 2.2's tracking survives the change. It is the first thing a font
## refactor drops, and 字距是「空灵」的真正来源，比字号重要.
func test_the_tracking_is_still_on_both_elements() -> void:
	var note := ThresholdNote.new()
	note.build(_tokens, _fonts, _layout.row_for(&"core_temperature"),
		"呼吸变快了", 0.5, false, false)
	var arc := TimeArc.new()
	arc.build(_tokens, _fonts, _prompt)
	var body: FontVariation = note.get(&"_body")
	var label: FontVariation = arc.get(&"_label_font")
	assert_eq(body.spacing_glyph, int(roundf(ThresholdNote.BODY_TRACKING_EM * BODY_DESIGN_PX)))
	assert_eq(label.spacing_glyph, int(roundf(_prompt.label_tracking_em * _prompt.label_design_px)))
	note.free()
	arc.free()


## Neither element may add its tracking by wrapping the chain UIFonts hands back.
## The behavioural test above catches it today; this catches it at the moment
## somebody writes it, and names the line.
func test_neither_element_wraps_the_chain_in_a_second_variation() -> void:
	for path in ["res://src/ui/threshold_note.gd", "res://src/ui/time_arc.gd"]:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, path)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		assert_true(source.contains("interface_at("),
			"%s no longer asks UIFonts for its chain" % path)
		assert_false(source.contains("base_font = _fonts.interface"),
			"%s wraps the shared interface chain, which drops the weight on the base face" % path)
		assert_false(source.contains("FontVariation.new()"),
			"%s builds its own FontVariation over the chain, which drops the weight on the base face" % path)


# --- what the fix cost ----------------------------------------------------------

## WEIGHT WAS AFFORDABLE BECAUSE IT MOVES NOTHING. Every line the game can
## surface at Body 17 sets to the same width at the interface weight and at the
## breath weight, so no element resizes, restacks or recentres.
##
## This is only true because every one of those strings is CJK, where a glyph
## advances one em whatever its weight. A Latin string in the breath layer WOULD
## reflow, and this test will say so on the day one is added rather than leaving
## it to a screenshot.
func test_the_heavier_cut_moved_no_glyph() -> void:
	var base: Font = _fonts.interface_at(
		_tokens.interface_latin_weight, _tokens.interface_cjk_weight)
	var breath: Font = _fonts.interface_at(
		_tokens.breath_latin_weight, _tokens.breath_cjk_weight)
	var strings := _live_strings()
	assert_true(strings.size() > 0, "no live copy was found to measure")
	for text in strings:
		var was := base.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(BODY_DESIGN_PX)).x
		var now := breath.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(BODY_DESIGN_PX)).x
		assert_almost_eq(now, was, 0.01,
			"\"%s\" is %.2f px at the breath weight and %.2f at the interface weight -- the layout moves"
				% [text, now, was])


## AND THE TYPE SCALE DID NOT MOVE. The lever chosen was weight; the size ladder
## in section 2.2 belongs to the document's owner. If a later change to this
## element reaches for the size instead, this fails and says where the decision
## has to be taken.
func test_the_type_scale_was_not_moved() -> void:
	assert_almost_eq(ThresholdNote.BODY_DESIGN_PX, BODY_DESIGN_PX, 0.001,
		"section 5.2's copy is no longer Body 17 -- moving the ladder is the owner's call, not a fix")
	assert_almost_eq(_prompt.label_design_px, BODY_DESIGN_PX, 0.001,
		"section 5.10's phase word is no longer Body 17 -- same")
