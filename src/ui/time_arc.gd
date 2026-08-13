class_name TimeArc
extends Control

## UI design document section 5.10, drawn: a thin arc with a moon at its left end
## and a sun at its right, the phase and the day centred beneath it, and a mark
## at the current position.
##
## ---------------------------------------------------------------------------
## IT IS A TRACK BETWEEN TWO LABELS, NOT A PATH THROUGH TWO BODIES
## ---------------------------------------------------------------------------
## The shape is an arc and the two things at its ends are a moon and a sun, so
## there is a reading available in which one body travels a sky. That reading is
## wrong here and the element has to refuse it, because a sky with a moon pinned
## at one end and a sun pinned at the other is not a sky.
##
## Section 5.10 is unambiguous about which it is -- 两个图标固定不动：月在左，日在右。
## 变化的是标记往哪边走 -- so the moon and the sun are LABELS on the two ends of a
## track, and the only thing that travels is the mark. The track is drawn between
## them and stops short of both, which is what makes the reading legible rather
## than merely intended; see TRACK_CLEARANCE_ICONS.
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

## ---------------------------------------------------------------------------
## THE TRACK IS NOT THE WHOLE ARC, AND THAT IS AN INFORMATION FIX
## ---------------------------------------------------------------------------
## The mark used to run from `point_at(0)` to `point_at(1)` -- the same two points
## the terminals are pinned to. So at the START of a phase the mark was drawn
## exactly concentric with a 20 device pixel glyph, at 6 device pixels across, in
## the same ink. It was underneath it. And the travelled segment has zero length
## there by definition.
##
## Photographed rather than reasoned about: at 1% into a night, on `pale_day`
## snow, the whole element is a uniform hairline from one blob to another, plus
## 夜晚 1. Every part that carries information -- how far through, which way it is
## going -- is either absent or hidden. That is the frame the owner called
## 信息不够清晰, and it is reproducible on HEAD.
##
## It is not rare, either. The first prompt after every phase change lands in that
## window, so it is two of the twelve prompts a day.
##
## So the TRACK -- groove, travelled segment and mark -- is held back from each
## terminal by half a glyph plus half a grid unit, and the terminals stay pinned
## at the arc's true ends. Three things follow from one change:
##
##   1. "now" is visible at every progress, including 0 and 1, because the mark
##      can no longer reach the glyph that was covering it
##   2. the stroke stops at the glyph's edge instead of running into its middle,
##      which is the 粗糙 an owner sees as "the moon sits on the end of the line"
##   3. the element commits to ONE metaphor. An arc through two pinned bodies
##      reads as a sky path, and a sky path with two suns on it is nonsense; a
##      track between two labelled terminals reads as what section 5.10 actually
##      specifies -- 两个图标固定不动，变化的是标记往哪边走.
##
## It is a RELATIONSHIP, not a constant: change the glyph size or the grid and the
## clearance follows, and tests/unit/test_time_prompt.gd asserts it against
## `icon_design_px` rather than against a number.
const TRACK_CLEARANCE_ICONS := 0.5
const TRACK_CLEARANCE_GAPS := 0.5

## A track cannot be inset past its own middle. Reached only by an absurd glyph
## size, and it fails as a short track rather than as an inverted one.
const TRACK_INSET_CEILING := 0.45

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

## ---------------------------------------------------------------------------
## 散 · 边缘先化开 -- WHICH PART OF THIS ELEMENT LEAVES FIRST, AND WHY IT IS NOT
## A TASTE
## ---------------------------------------------------------------------------
## Section 1.1 says the dispersal is 慢的、边缘先化开的、向上飘的, and until now
## this element had two of those three: it left as one rigid picture, every part
## at one rate. Breath on cold glass does not go that way -- the thinnest film
## evaporates first and the shape comes apart in an order.
##
## The order is not chosen here. **Section 2.1's ladder is already this element's
## own statement of how much each part weighs**, so a part leads the exit by
## exactly how faintly it is drawn, and that falls out of `_at()` for free:
##
##   groove       24%  -> lead 0.76, gone 66% through the exit
##   the face of the phase that has not arrived
##                48%  -> lead 0.52, gone 77% through
##   phase word   72%  -> lead 0.28, gone 87% through
##   travelled arc, the lit face, the day, the mark
##               100%  -> lead 0.00, they ARE the element and they go with it
##
## So the prompt thins from its faintest ink inward, and the last thing on the
## snow is the dot that says where in the day you are. Nothing was added to the
## screen to get that -- it is opacity over time, so there is no plate (rule 1),
## no gradient and no shader.

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _data: TimePromptData = null

var _night := false
var _day := 1
var _progress := 0.0

var _viewport := Vector2(1920.0, 1080.0)
var _label_font: FontVariation = null

## The `Day 4` stamp's own chain. See _draw_text() for why it is not the
## instrument face, and _build_stamp_font() for why it is a second object rather
## than _label_font with a feature written onto it.
var _stamp_font: FontVariation = null

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

## The envelope UILayer is driving this element with, and how far into it we are.
## Null until it is surfaced, and only ever read during the 散.
var _breath: Breath = null
var _breath_seconds := 0.0


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
	_stamp_font = _build_stamp_font()
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


## Handed in by UILayer every frame it drives this element -- see its advance().
## Everything this does is in the 散; through the 呵 and the 持 the element draws
## exactly as it did before.
func set_envelope(breath: Breath, seconds: float) -> void:
	_breath = breath
	_breath_seconds = seconds
	# Only while it is coming apart. Redrawing through an eight second hold in
	# which nothing changes would be sixty needless draws a second.
	if breath != null and seconds >= breath.exit_begins():
		queue_redraw()


## The envelope this element is being driven by, or null. Published so a test can
## read what is ACTUALLY driving the picture.
func envelope() -> Breath:
	return _breath


## How far ahead of the element as a whole a part drawn at this rung leaves. See
## the block above OPACITY_TROUGH: the ladder is the order.
func lead_for(opacity: float) -> float:
	return clampf(1.0 - opacity, 0.0, 1.0)


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


## 夜晚 Day 4 -- the phase word and the day stamp. The only display copy this
## element has, and none of it is in this file (see TimePromptData).
func text() -> String:
	if _data == null:
		return ""
	return "%s %s" % [phase_word(), day_stamp()]


func phase_word() -> String:
	if _data == null:
		return ""
	return _data.night_label if _night else _data.day_label


## `Day 4`. The label is data and the numeral is the clock; there is no total,
## deliberately -- see TimePromptData.day_word.
func day_stamp() -> String:
	if _data == null:
		return ""
	if _data.day_word == "":
		return str(_day)
	return "%s %d" % [_data.day_word, _day]


func span_radians() -> float:
	return 0.0 if _data == null else deg_to_rad(_data.arc_degrees)


## The face the day stamp is actually drawn with. Published so a test measures the
## object that reaches the frame rather than a description of it -- the tabular
## claim in particular cannot be checked by reading a dictionary back.
func stamp_font() -> FontVariation:
	return _stamp_font


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
## element-local pixels. This is the GEOMETRY -- the terminals are pinned to its
## two ends. What moves runs on the track; see track_at().
func point_at(t: float) -> Vector2:
	var span := span_radians()
	var u := (clampf(t, 0.0, 1.0) - 0.5) * span
	return _centre + Vector2(sin(u), -cos(u)) * _radius


## How far the track is held back from each terminal, in design pixels measured
## along the arc: half a glyph so the stroke stops at its edge rather than under
## its middle, plus half a grid unit so the two are separated rather than merely
## touching. See TRACK_CLEARANCE_ICONS.
func track_clearance_design_px() -> float:
	if _data == null:
		return 0.0
	return _data.icon_design_px * TRACK_CLEARANCE_ICONS \
		+ _data.gap_design_px * TRACK_CLEARANCE_GAPS


## That clearance expressed in the arc's own 0..1 parameter, so it can be fed
## straight to point_at(). Both quantities are in screen pixels here, which is
## what makes this scale with the canvas rather than with the reference frame.
func track_inset() -> float:
	if _data == null or _radius <= 0.0:
		return 0.0
	var arc_length := _radius * span_radians()
	if arc_length <= 0.0:
		return 0.0
	return clampf(_px(track_clearance_design_px()) / arc_length, 0.0, TRACK_INSET_CEILING)


## A point on the TRACK -- the stretch of arc between the two terminals. `u` runs
## 0 at the moon end and 1 at the sun end.
func track_at(u: float) -> Vector2:
	return point_at(_track_t(u))


## Where the mark stands. See the header: it walks toward the phase that is
## coming, so the day runs the track backwards.
func mark_position() -> Vector2:
	return track_at(_progress if _night else 1.0 - _progress)


## The centre of one of the two faces. The sun is the right end, the moon the
## left, and neither ever moves.
func icon_centre(sun: bool) -> Vector2:
	return point_at(1.0 if sun else 0.0)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _tokens == null or _data == null:
		return
	var trough := maxf(_px(TROUGH_DESIGN_PX), 1.0)
	var travelled := maxf(_px(TRAVELLED_DESIGN_PX), 1.0)

	# The TRACK, as the groove: the same ink on the bottom rung of section 2.1's
	# opacity ladder rather than a second colour. It stops short of both glyphs --
	# see TRACK_CLEARANCE_ICONS.
	var inset := track_inset()
	draw_arc(_centre, _radius, _angle_at(inset), _angle_at(1.0 - inset), ARC_SEGMENTS,
		_at(OPACITY_TROUGH), trough, true)

	# And the part already walked, over it, in the primary ink. It grows out of
	# the end of the track nearest the phase the player is in, which is what makes
	# the direction legible without a label.
	var here := _track_t(_progress if _night else 1.0 - _progress)
	var from := _track_t(0.0 if _night else 1.0)
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


## The phase word and the day stamp on one baseline, centred under the arc.
##
## ---------------------------------------------------------------------------
## THE DAY LEFT THE INSTRUMENT FACE, AND A MEASUREMENT IS WHAT MOVED IT
## ---------------------------------------------------------------------------
## Section 5.10 asks for 日次 Instrument and section 5.4 makes the same split for
## 「第 四 日」. Measured through tools/measure_type_weight.tscn on `pale_day` snow,
## at the shipped Body 17 rasterised at 17 device pixels:
##
##   phase word  Noto Sans SC 600, drawn at 72%   nominal 4.36  ->  core 4.10
##   day number  IBM Plex Mono Light, at 100%     nominal 8.53  ->  core 3.81
##
## The number is drawn at FULL ink and delivers less than the word drawn at
## seventy-two percent of it. It loses more than half its own contrast to strokes
## thinner than a pixel, and 3.3% of its pixels ever reach the colour it was
## authored in. It is the least legible mark in the element, and it carries the
## one scalar the seven-day spine hangs on.
##
## Section 2.2's revision found this and recorded it as unfixable: 仪表族是
## IBMPlexMono-Light.ttf，一个静态字重文件，没有可调的轴 … 要改它需要换一个字重的文件，
## 那是资产决定. That is true of the FILE and not of the ELEMENT. The interface
## chain is already loaded, has a real weight axis, and already carries a weight
## authored for exactly this layer -- breath 500/600, because the breath layer
## stands on open snow with no plate under it.
##
## So the stamp takes the interface chain at the breath weights, and the two
## halves of the line become one deliberate pair rather than two families landing
## at two optical weights by accident.
##
## WHAT THE INSTRUMENT FACE WAS FOR IS KEPT. Section 5.4's reason is baseline
## alignment with 第/日, which this element does not have. The other reason is in
## this file's own history -- a proportional numeral changes width between 9 and
## 10, which walks a centred line sideways on the day it happens -- and that is
## answered by tabular figures rather than by monospace. See _build_stamp_font;
## tests/unit/test_time_prompt.gd MEASURES all ten digits rather than trusting the
## feature to have applied, because this is the class of defect where a setting is
## accepted, read back, and never used.
func _draw_text() -> void:
	if _label_font == null or _stamp_font == null:
		return
	var px := int(maxf(_px(_data.label_design_px), 1.0))
	var word := phase_word()
	var stamp := day_stamp()
	var space := _px(_data.gap_design_px) * 0.5
	var word_width := _label_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var stamp_width := _stamp_font.get_string_size(
		stamp, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var left := (size.x - (word_width + space + stamp_width)) * 0.5
	var baseline := size.y - _px(_data.label_design_px) * (LINE_HEIGHT_RATIO - 1.0)
	draw_string(_label_font, Vector2(left, baseline), word,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, _at(OPACITY_WORD))
	draw_string(_stamp_font, Vector2(left + word_width + space, baseline), stamp,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, _at(1.0))


# --- internals ----------------------------------------------------------------

## Godot measures an arc's angle from +X. This element's parameter runs from the
## TOP of the circle, because that is where an arc's apex is and where the
## arithmetic above is written from.
func _angle_at(t: float) -> float:
	return (clampf(t, 0.0, 1.0) - 0.5) * span_radians() - PI * 0.5


## A track parameter (0 at the moon end of the TRACK, 1 at the sun end) as an arc
## parameter (0 and 1 at the arc's true ends, where the terminals are pinned).
## One function, so the groove, the travelled segment and the mark cannot come to
## disagree about where the track is.
func _track_t(u: float) -> float:
	var inset := track_inset()
	return lerpf(inset, 1.0 - inset, clampf(u, 0.0, 1.0))


## The element's ink at one rung of section 2.1's opacity ladder -- and, during
## the 散, that rung's own place in the dispersal. Every draw call in this file
## goes through here, which is why the order costs one line and cannot be
## forgotten by whoever adds the next part.
func _at(opacity: float) -> Color:
	var colour := ink()
	colour.a = opacity * _dispersal(opacity)
	return colour


func _dispersal(opacity: float) -> float:
	if _breath == null:
		return 1.0
	return _breath.dispersal_at(_breath_seconds, lead_for(opacity))


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
## The day stamp beside it is measured apart, and it USED to be the instrument
## face -- see _draw_text() for the measurement that moved it, which is the same
## defect one family further along: one line of type can hold two very different
## legibilities, so the two halves have to be measured separately or one of them
## rides on the other's number.
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


## The same chain as the phase word, at the same weights, plus tabular figures.
##
## SAME WEIGHTS ON PURPOSE. 夜晚 and `Day 4` sit on one baseline at one size, and
## two families at one nominal size land at two optical weights unless somebody
## chooses. Section 2.2's revision already chose for this layer -- 600 CJK, 500
## Latin -- and taking both from those tokens is what makes the pair a decision
## rather than a coincidence. The phase word draws at 72% and the stamp at 100%,
## so the hierarchy is carried by the opacity ladder, which is section 2.1's
## channel for it, and not by the type.
##
## A SECOND OBJECT, not _label_font with a feature written onto it: the two are
## drawn at different rungs and will not always want the same features, and one
## shared FontVariation edited from two places is how a font ends up with a
## setting nobody remembers asking for.
##
## `opentype_features` takes a StringName key and `variation_opentype` does not --
## two neighbouring properties of one class with two different key contracts, one
## of them silent (UIFonts._variation records the measurement). Which is exactly
## why the tabular claim is checked by MEASURING all ten digits in the test rather
## than by reading this dictionary back.
func _build_stamp_font() -> FontVariation:
	if _fonts == null or _fonts.interface == null or _data == null or _tokens == null:
		return null
	var chain := _fonts.interface_at(
		_tokens.breath_latin_weight,
		_tokens.breath_cjk_weight,
		int(roundf(_data.label_tracking_em * _data.label_design_px)))
	# interface_at() degrades to the SHARED `interface` chain when a font path is
	# missing. Writing a feature onto that would re-figure the whole interface, so
	# the degraded path is left exactly as it is handed over.
	if chain != null and chain != _fonts.interface:
		chain.opentype_features = { UIFonts.TABULAR: 1 }
	return chain
