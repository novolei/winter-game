class_name TimeArc
extends Control

## UI design document section 5.10, drawn: a thin arc with a moon at its left end
## and a sun at its right, the phase and the day centred beneath it, and a mark
## at the current position.
##
## ---------------------------------------------------------------------------
## THE DIRECTION OF TRAVEL IS THE INFORMATION
## ---------------------------------------------------------------------------
## The two faces never move: 月 at the left end, 日 at the right. What changes is
## which way the mark walks, and it always walks toward the phase that is COMING.
##
##   night   moon -> sun    the night is running out, dawn is at the far end
##   day     sun -> moon    the day is running out, and GDD section 3 makes
##                          NIGHTFALL = GO HOME a literal deadline
##
## The alternative -- always left to right -- reads correctly at night and
## backwards in the day, which is the half of the run where being wrong costs the
## player something. The bright part of the arc grows out of the face of the
## phase he is in, so the picture answers "which phase" and "how far through"
## with one shape.
##
## ---------------------------------------------------------------------------
## RULE 1: NO RECTANGLES
## ---------------------------------------------------------------------------
## An arc, two tinted glyphs, a dot and a line of text. No panel, no card, no
## background, no border. The element's own `size` is a layout rectangle and
## nothing is ever drawn in it.
##
## Rule 2 holds too: it lives entirely inside the bottom breathing border, which
## is 7.5% of the short edge, and everything below is proportioned so that it
## still does at every window shape the game runs at.

const ICON_DIRECTORY := "res://assets/ui/icons"

## The mark's radius, in design pixels. Section 6.1's recovery dot is 3 px and
## this is the same size deliberately: a small solid dot on a stroke means "you
## are here" in both places.
const MARK_DESIGN_PX := 3.0

## The stroke weights, in design pixels. The trough is section 4.2's slider
## track -- one pixel, the thinnest thing the interface owns -- and the part
## already travelled is drawn over it heavier.
const TROUGH_DESIGN_PX := 1.0
const TRAVELLED_DESIGN_PX := 2.0

## Section 2.2's Body line height. Used as the text's box rather than the font's
## own metrics so the element's height is the same number in a test, in a capture
## and on screen, whatever font chain happens to be loaded.
const LINE_HEIGHT_RATIO := 1.6

## How many segments the arc is drawn with. Enough that a 60 degree curve has no
## visible facets at the sizes this renders at.
const ARC_SEGMENTS := 48

## ---------------------------------------------------------------------------
## ONE INK, TWO CANDIDATES, AND THE GROUND CHOOSES
## ---------------------------------------------------------------------------
## MEASURED FROM THIS ELEMENT'S OWN POSITION IN THE FRAME, not reasoned about.
## Captured through tools/capture_time_prompt.tscn, sampling the snow the prompt
## actually stands on:
##
##   deep_night  ambient 1.5  ->  ground relative luminance 0.148
##   pale_day    ambient 3.2  ->  ground relative luminance 0.577
##
## Against a ground at 0.577, `ink/primary` (#8FB0D8) measures **1.00 : 1**. Not
## dim -- IDENTICAL. It is `snow_tones[0]`, so on this game's bright weather it is
## literally the colour of the snow, and the first capture of this element showed
## exactly that: a good night frame and a day frame whose drawn segment was not
## there at all.
##
## No single token clears even 2:1 at both ends -- the arithmetic closes at about
## 1.7:1, which is not enough for something that is on screen for four seconds.
## So the ink is CHOSEN between two palette entries rather than synthesised:
## `line/deep` on a bright ground, `ink/primary` on a dark one. Section 2.1
## already sanctions this shape of conditional -- `line/deep` is listed there as
## the groove's dark-scene variant.
##
## THIS IS NOT THE DELETED NIGHT LIFT. That was a continuous solve producing
## off-token colours by bisecting HSV value, and it existed because a PERMANENT
## readout had to survive every hour. This is a choice between two of the twelve,
## with the groove drawn as the same ink on section 2.1's opacity ladder.
##
## THE RULE ITSELF NOW LIVES IN UIInk, and these are aliases onto it. Section
## 5.2's note turned out to have the identical problem for the identical reason,
## and two copies of a crossover are two elements that agree until the day one of
## them is edited -- which is the failure this project has recorded three times.
## The numbers below have not changed; only their address has.
const GROUND_TO_LUMINANCE := UIInk.GROUND_TO_LUMINANCE
const GROUND_LUMINANCE_OFFSET := UIInk.GROUND_LUMINANCE_OFFSET
const DARK_GROUND_BELOW := UIInk.DARK_GROUND_BELOW

## Section 2.1's opacity ladder: 100 / 72 / 48 / 24 / 12, and no values between the
## rungs. One ink at four strengths is what keeps this one material.
const OPACITY_TROUGH := 0.24
const OPACITY_DIM_FACE := 0.48
const OPACITY_WORD := 0.72

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _data: TimePromptData = null

var _night := false
var _day := 1
var _progress := 0.0

var _viewport := Vector2(1920.0, 1080.0)
var _label_font: FontVariation = null

## LOADED ONCE, IN build(). A ResourceLoader.load() inside _draw() runs during the
## render callback, and this project has already seen what that costs: the two
## faces rendered as SOLID TINTED SQUARES -- the canvas falling back to its 1x1
## white texture -- while every check of the file, the import and the loaded
## Texture2D came back correct. Nothing errors; the shape is simply not there.
var _day_face: Texture2D = null
var _night_face: Texture2D = null

## Resolved in layout_for(): the circle the arc is a piece of, in element-local
## pixels.
var _centre := Vector2.ZERO
var _radius := 1.0

## How bright the snow behind this element is, 0..1. Half until the lighting says
## otherwise, so a prompt built before the world is lit is neither black nor
## white.
var _ground := 0.5


func build(tokens: UITokens, fonts: UIFonts, data: TimePromptData) -> bool:
	_tokens = tokens
	_fonts = fonts
	_data = data
	# Nothing here reacts to the mouse. Left as STOP -- the Control default -- an
	# element in the bottom margin eats clicks for as long as it is on screen, and
	# the symptom is "the game stops responding for a few seconds every so often",
	# which reads as anything but a time prompt.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tokens == null or _data == null:
		return false
	_label_font = _build_label_font()
	_day_face = _load_face(_data.day_glyph)
	_night_face = _load_face(_data.night_glyph)
	return true


## `night` and `day` come off WorldClock; `progress` is 0 at the start of the
## current phase and 1 at its end.
func set_phase(night: bool, day: int, progress: float) -> void:
	_night = night
	_day = day
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


## How bright the ground behind the element is, 0..1. See GROUND_TO_LUMINANCE.
func set_ground(value: float) -> void:
	_ground = clampf(value, 0.0, 1.0)
	queue_redraw()


func ground() -> float:
	return _ground


## The one ink this element is drawn in, at full strength. See the header.
func ink() -> Color:
	return UIInk.mark_for(_tokens, _ground)


## A lighting preset's ambient energy as the relative luminance of the ground it
## produces. Empirical and re-measurable: re-run the two captures named in the
## header and refit if a preset is retuned.
static func ground_for(preset) -> float:
	return UIInk.ground_for(preset)


func is_night() -> bool:
	return _night


func day() -> int:
	return _day


func progress() -> float:
	return _progress


## 夜晚 4 -- the phase word and the day, from data. The only display copy this
## element has, and it is not in this file (see TimePromptData).
func text() -> String:
	if _data == null:
		return ""
	return "%s %d" % [_data.night_label if _night else _data.day_label, _day]


func span_radians() -> float:
	return 0.0 if _data == null else deg_to_rad(_data.arc_degrees)


# --- layout -------------------------------------------------------------------

## Sizes the element, works out the circle its arc belongs to, and stands it in
## the middle of the bottom breathing border. Returns the size.
##
## CENTRED IN THE BORDER, computed from the canvas every time rather than from a
## remembered position. The project stretches `canvas_items` / `expand`, which
## reveals extra screen area instead of letterboxing it, so anything placed by
## fixed coordinates walks off the edge of every window shape but the one it was
## authored at.
func layout_for(viewport_size: Vector2) -> Vector2:
	if _tokens == null or _data == null:
		return size
	_viewport = viewport_size
	var chord := _px(_data.arc_width_design_px)
	var icon := _px(_data.icon_design_px)
	var gap := _px(_data.gap_design_px)
	var mark := _px(MARK_DESIGN_PX)
	var line := _px(_data.label_design_px) * LINE_HEIGHT_RATIO

	var half := span_radians() * 0.5
	# A chord and its span give the circle. At 60 degrees the chord happens to
	# equal the radius, which is a coincidence of that angle and not something to
	# rely on -- authoring the angle in data means the arithmetic has to be real.
	_radius = chord / maxf(2.0 * sin(half), 0.0001)
	var sagitta := _radius * (1.0 - cos(half))

	# The apex sits one mark radius down so a mark at the top of the arc is not
	# clipped by the element's own bounds.
	var apex_y := mark
	var ends_y := apex_y + sagitta
	size = Vector2(chord + icon, ends_y + icon * 0.5 + gap + line)
	_centre = Vector2(size.x * 0.5, apex_y + _radius)

	var edge := _tokens.edge_pixels(viewport_size)
	# Centred in the bottom border rather than pinned to either of its edges: it
	# is the one element that stands away from every corner, which is what makes
	# it read as belonging to the frame instead of to a panel.
	var top := viewport_size.y - edge + maxf(edge - size.y, 0.0) * 0.5
	position = Vector2(roundf((viewport_size.x - size.x) * 0.5), roundf(top))
	pivot_offset = size * 0.5
	queue_redraw()
	return size


## A point on the arc, `t` running 0 at the left end to 1 at the right, in
## element-local pixels.
func point_at(t: float) -> Vector2:
	var span := span_radians()
	var u := (clampf(t, 0.0, 1.0) - 0.5) * span
	return _centre + Vector2(sin(u), -cos(u)) * _radius


## Where the mark stands. See the header: it walks toward the phase that is
## coming, so the day runs the arc backwards.
func mark_position() -> Vector2:
	return point_at(_progress if _night else 1.0 - _progress)


## The centre of one of the two faces. The sun is the right end, the moon the
## left, and neither ever moves.
func icon_centre(sun: bool) -> Vector2:
	return point_at(1.0 if sun else 0.0)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _tokens == null or _data == null:
		return
	var span := span_radians()
	var trough := maxf(_px(TROUGH_DESIGN_PX), 1.0)
	var travelled := maxf(_px(TRAVELLED_DESIGN_PX), 1.0)

	# The whole arc, as the groove: the same ink on the bottom rung of section
	# 2.1's opacity ladder rather than a second colour.
	draw_arc(_centre, _radius, _angle_at(0.0), _angle_at(1.0), ARC_SEGMENTS,
		_at(OPACITY_TROUGH), trough, true)

	# And the part already walked, over it, in the primary ink. It grows out of
	# the face of the phase the player is in, which is what makes the direction
	# legible without a label.
	var here := _progress if _night else 1.0 - _progress
	var from := 0.0 if _night else 1.0
	if not is_equal_approx(here, from):
		draw_arc(_centre, _radius, _angle_at(from), _angle_at(here), ARC_SEGMENTS,
			_at(1.0), travelled, true)

	# The face of the phase the player is in is at full strength; the one that is
	# coming sits halfway down the ladder.
	_draw_face(false, _at(1.0 if _night else OPACITY_DIM_FACE))
	_draw_face(true, _at(OPACITY_DIM_FACE if _night else 1.0))

	draw_circle(mark_position(), maxf(_px(MARK_DESIGN_PX), 1.0), _at(1.0))
	_draw_text()


## Tinted here, never recoloured in the file: the two PNGs are white on
## transparent, so a file that arrives carrying its own colour is a defect rather
## than something to compensate for in code.
func _draw_face(sun: bool, colour: Color) -> void:
	var texture := _face(sun)
	if texture == null:
		return
	var icon := _px(_data.icon_design_px)
	var centre := icon_centre(sun)
	draw_texture_rect(
		texture,
		Rect2(centre - Vector2(icon, icon) * 0.5, Vector2(icon, icon)),
		false, colour)


## The phase word in the interface face and the day in the instrument face, on
## one baseline, centred under the arc.
##
## Section 5.4 makes the same split for 「第 四 日」: 日次数字用仪表字. A numeral in
## a proportional face would also change width between 9 and 10, which moves the
## whole centred line sideways on the day it happens.
func _draw_text() -> void:
	if _label_font == null or _fonts == null or _fonts.instrument == null:
		return
	var px := int(maxf(_px(_data.label_design_px), 1.0))
	var word := _data.night_label if _night else _data.day_label
	var number := str(_day)
	var space := _px(_data.gap_design_px) * 0.5
	var word_width := _label_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var number_width := _fonts.instrument.get_string_size(
		number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var left := (size.x - (word_width + space + number_width)) * 0.5
	var baseline := size.y - _px(_data.label_design_px) * (LINE_HEIGHT_RATIO - 1.0)
	draw_string(_label_font, Vector2(left, baseline), word,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, _at(OPACITY_WORD))
	draw_string(_fonts.instrument, Vector2(left + word_width + space, baseline), number,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, _at(1.0))


# --- internals ----------------------------------------------------------------

## Godot measures an arc's angle from +X. This element's parameter runs from the
## TOP of the circle, because that is where an arc's apex is and where the
## arithmetic above is written from.
func _angle_at(t: float) -> float:
	return (clampf(t, 0.0, 1.0) - 0.5) * span_radians() - PI * 0.5


## The element's ink at one rung of section 2.1's opacity ladder.
func _at(opacity: float) -> Color:
	var colour := ink()
	colour.a = opacity
	return colour


func _px(design_px: float) -> float:
	if _tokens == null:
		return design_px
	return _tokens.design_px(design_px, _viewport)


func _face(sun: bool) -> Texture2D:
	return _day_face if sun else _night_face


func _load_face(glyph: StringName) -> Texture2D:
	if glyph == &"":
		return null
	var path := "%s/%s.png" % [ICON_DIRECTORY, glyph]
	# Asked before loading: load() on a path that is not there prints three ERROR
	# lines, and a dirty console is a failed run by this project's standard.
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## The interface chain at the BREATH LAYER'S weight, with section 2.2's tracking
## on it.
##
## Not UIFonts.interface, for the reason UITokens.breath_cjk_weight records at
## length: section 2.2's 300 Light assumes the interface owns the background, and
## this element stands in the bottom margin over open snow with no plate allowed
## under it. This word is the WORST specimen in the game for it -- it is Body 17
## like the threshold note's sentence AND it is drawn one rung down section 2.1's
## opacity ladder, so measured on lit `pale_day` snow at 300 it delivered
## 1.77 : 1 at the stroke core against a nominal 4.36 : 1, with not one pixel
## reaching its own ink.
##
## The day number beside it is NOT affected and does not need to be: it is the
## instrument face at full strength, and the same capture measured it at
## 4.71 : 1. A monospaced Latin digit has a stem several times the width of a CJK
## hairline at the same size, which is why one line of type can hold two very
## different legibilities and why they are measured apart.
##
## A CHAIN OF ITS OWN, not UIFonts.interface with spacing written onto it: that
## object is shared by the whole interface and spacing is per-size, so writing to
## it here would silently re-space the menus. The tracking is asked of UIFonts
## rather than applied to what it hands back, because a FontVariation wrapped
## around another one drops the inner one's weight axis -- see
## UIFonts._variation().
func _build_label_font() -> FontVariation:
	if _fonts == null or _fonts.interface == null or _data == null or _tokens == null:
		return null
	return _fonts.interface_at(
		_tokens.breath_latin_weight,
		_tokens.breath_cjk_weight,
		int(roundf(_data.label_tracking_em * _data.label_design_px)))
