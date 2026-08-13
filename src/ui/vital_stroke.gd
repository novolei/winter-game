class_name VitalStroke
extends Control

## One survival reading: where it stands, what it is worth, and what state that
## puts it in. NOT what it looks like.
##
## ---------------------------------------------------------------------------
## THE SEAM IS PAINT_SCRIPT, AND IT IS ONE LINE
## ---------------------------------------------------------------------------
## That constant is the only place in the readouts that names a visual language.
## Everything else here is geometry and meaning: a ring of a given radius in a
## given place, a reserve at a given fraction, the state that follows from it,
## the thresholds the model itself authored, and section 2.4's 颤 and 明灭 when
## things are bad. A new look is that constant and a new VitalPaint subclass.
##
## It earned its keep within a day: the frost language was built, verified on
## screen, and then withdrawn by the owner as more than he wanted. Nothing in
## front of the seam had to change.
##
## ---------------------------------------------------------------------------
## RADIAL, AND FALLING
## ---------------------------------------------------------------------------
## The reserve runs around the gauge from the top, so a reading in trouble has
## receded back toward its start. Every survival stat is a reserve that falls
## (survival_system.gd's polarity note), so one direction serves all of them and
## a reading never has to be inverted by whoever looks at it.
##
## ---------------------------------------------------------------------------
## WHY THE ELEMENT MOVES ITSELF RATHER THAN BEING MOVED
## ---------------------------------------------------------------------------
## UILayer drives the elements it holds -- opacity, scale, position -- and it
## holds the NOTE, not the arc inside it. So the shiver of a critical reading is
## applied here, to this element alone, and cannot fight the note's own envelope.

## THE SEAM. See the header. 「刻度」Engraved is the look the owner settled on;
## src/ui/frost.gd is the withdrawn one, parked behind the same interface.
const PAINT_SCRIPT := preload("res://src/ui/engraved.gd")

## How far the look may reach outside the substrate, in design pixels. The
## element's clear space is sized from this, so anything longer is clipped by the
## element's own bounds.
const TEXTURE_DESIGN_PX := 9.0

## How far a threshold mark stands off the gauge, in design pixels.
const MARKER_DESIGN_PX := 5.0

## Design pixels of clear space around the substrate, so a needle at full rime
## has room and is not clipped by the element's own bounds. Needle reach plus
## the heaviest stroke, plus the outline outside that.
const PAD_DESIGN_PX := 13.0

## How much thicker the ice goes for a moment when a threshold breaks under this
## reading. Emphasis by MATERIAL, not by warmth -- rule 3.
const SURGE_RIME := 1.0

## The gauge is open at the bottom rather than closed. A full circle reads as a
## dial -- a thing with a needle in it -- and this is an arc that ice grows
## along. Section 6.1's ring is 断弧 for the same reason.
const RING_OPENING := PI / 3.0
const RING_SPAN := TAU - RING_OPENING

var _paint: VitalPaint = null
var _tokens: UITokens = null
var _row: VitalReadout = null

var _fraction := 1.0
var _depleted := false
var _recovering := false
var _state := VitalTone.State.STEADY

var _elapsed := 0.0
var _home := Vector2.ZERO
var _viewport := Vector2(1920.0, 1080.0)
var _track_px := 0.0

## How bright the frame behind this stroke is, 0..1. See UIInk: the light half of
## this palette IS the snow, so which entry a reading is drawn in depends on what
## it is standing on. Set by whoever owns the stroke, at the moment it goes on
## screen.
var _ground := UIInk.UNKNOWN_GROUND


func build(tokens: UITokens, row: VitalReadout, seed := 0.0) -> bool:
	_tokens = tokens
	_row = row
	# Nothing here reacts to the mouse. Left as STOP -- the Control default --
	# this sits over the valley eating clicks for the whole run, and the symptom
	# is "the game stopped responding in the top left", which reads as anything
	# but a readout.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint = PAINT_SCRIPT.new()
	if not _paint.build(tokens):
		return false
	_paint.set_seed(seed)
	# A look that paints over the element's own bounds supplies a material; one
	# that draws with plain canvas calls returns null, and that is legal.
	material = _paint.material_for_element()
	return true


func is_ready() -> bool:
	return _paint != null and _paint.is_ready()


func stat() -> StringName:
	return &"" if _row == null else _row.stat


## The look, so a test can prove the seam is actually being driven. Nothing in
## the game reaches through this.
func paint() -> VitalPaint:
	return _paint


func state() -> int:
	return _state


## The colour this reading is being drawn in, so the icon beside it is tinted
## with exactly what the arc is using and the two cannot disagree.
##
## VitalTone says what the value MEANS; UIInk says which of the twelve carries
## that meaning on the ground this stroke is standing on. Both, in that order,
## and neither is the other's job.
func reading_colour() -> Color:
	return UIInk.for_state(_tokens, _state, _ground)


## How bright the frame behind this stroke is, 0..1.
func set_ground(value: float) -> void:
	_ground = clampf(value, 0.0, 1.0)
	_apply_reading_colour()
	queue_redraw()


func ground() -> float:
	return _ground


## Where this stroke stands and how long it is, in SCREEN pixels. The caller owns
## the layout; this owns everything inside its own bounds.
##
## Horizontal with a bow is section 5.2's 52px 短弧; the vertical form is here
## because place_ring() and this are two lengths of one element, and a second
## implementation of "a survival value as a stroke" would be a second set of
## thresholds waiting to disagree.
func place(
	home: Vector2,
	track_px: float,
	viewport_size: Vector2,
	vertical := true,
	bow_px := 0.0
) -> void:
	_home = home
	_track_px = maxf(track_px, 1.0)
	_viewport = viewport_size
	var pad := _pad_px()
	var from_px := Vector2.ZERO
	var to_px := Vector2.ZERO
	if vertical:
		size = Vector2(pad * 2.0, _track_px + pad * 2.0)
		# Bottom to top: s = 0 is the ground, so a reserve that falls recedes
		# toward it.
		from_px = Vector2(pad, size.y - pad)
		to_px = Vector2(pad, pad)
	else:
		# The bow lifts the middle, so the element has to be tall enough to hold
		# the arc AND the ice on the outside of it.
		size = Vector2(_track_px + pad * 2.0, pad * 2.0 + absf(bow_px))
		var mid := size.y - pad
		from_px = Vector2(pad, mid)
		to_px = Vector2(size.x - pad, mid)
	position = _home
	if _paint != null:
		_paint.set_substrate(size, from_px, to_px, bow_px)
	_apply_weights()
	queue_redraw()


## The reading. `recovering` is the net rate being positive -- heat, water or
## food actually going back in -- and it is the only thing in this element that
## may be warm (rule 3, section 5.2).
func set_reading(fraction: float, depleted: bool, recovering: bool) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	_depleted = depleted
	_recovering = recovering
	_state = VitalTone.state_for(_fraction, _depleted)
	if _paint != null:
		_paint.set_fill(_fraction)
		# EMPHASIS FOLLOWS THIS READING'S OWN STATE. In 「刻度」Engraved that is
		# what makes the ticks give way to a single continuous arc when a stat
		# crosses -- a change of FORM, which is the only emphasis channel left
		# once rule 3 has spent colour on one meaning.
		#
		# It used to be bound to how cold the BODY was, which belonged to the
		# withdrawn frost language: ice thickening everywhere as the man froze.
		# Under the settled look that would turn every gauge solid at once and
		# destroy the one thing the solid arc is for.
		_paint.set_target_emphasis(
			0.0 if _state == VitalTone.State.STEADY else 1.0)
		_apply_reading_colour()
		_paint.set_mark(
			_recovering and not _depleted,
			VitalTone.recovery_dot_colour(_tokens))
	_apply_weights()


## A threshold broke under this reading. The ice thickens, and then clears again
## on its own -- the material's own accumulate-and-clear doing the emphasis, so
## nothing has to be added to the screen and nothing has to be taken away.
func surge() -> void:
	if _paint != null:
		_paint.surge(SURGE_RIME)


## How frosted this reading settles at. Bound by the caller to how cold the body
## is, so the interface is made of the thing that is killing him.
func set_target_emphasis(value: float) -> void:
	if _paint != null:
		_paint.set_target_emphasis(value)


## Sets the ice AND the value it is settling at, at once.
##
## For an element that will not live long enough to accumulate. Rime chases over
## nine seconds and section 5.2's note is on screen for three and a half, so a
## note that started bare would spend its whole life bare -- which is exactly
## what the first capture of the two systems together showed: six smooth grey
## curves next to six frosted readings, in an interface whose material is ice.
func set_rime_now(value: float) -> void:
	if _paint == null:
		return
	_paint.set_target_emphasis(value)
	_paint.surge(value)


func set_time_scale(scale: float) -> void:
	if _paint != null:
		_paint.set_time_scale(scale)


## Dims this reading so another one can be the loud one. The cluster decides
## which; this only carries it.
func set_attenuation(amount: float) -> void:
	if _paint != null:
		_paint.set_attenuation(amount)
	queue_redraw()


## Public and carrying the driving, so a whole crystallisation is playable in a
## test with no frames.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _paint != null:
		_paint.advance(delta)
	# 颤, and the guttering of a fire going out. Both are section 2.4's, both
	# only at CRITICAL, and both are cool -- weight and motion, never warmth.
	position = _home + VitalTone.shiver_offset(_tokens, _viewport, _elapsed, _state)
	modulate.a = VitalTone.gutter(_elapsed, _state)
	queue_redraw()


## For a screenshot harness, which has to photograph a readout that is fully
## grown rather than one caught mid-crystallisation.
func finish_growth() -> void:
	if _paint != null:
		_paint.finish()
	queue_redraw()


## NO _process(). Whoever owns a stroke drives it from their own advance() -- a
## note from ThresholdSurfacing, the way MontageDirector drives its shots -- and
## a stroke that also ticked itself would run at DOUBLE SPEED whenever it
## happened to be inside a tree -- growing in
## half the authored time, shivering at 24 Hz, and doing all of it only in the
## running game, never in a test or a capture. That is the shape of defect this
## project keeps paying for: correct where it is measured, wrong where it is
## played.


func _draw() -> void:
	if _paint == null or not _paint.is_ready():
		return
	# Both paths, unconditionally. A look that paints over the element's bounds
	# supplies a texture and does nothing in draw_into(); a look made of strokes
	# supplies no texture and does all its work there. Neither has to know which
	# kind the other is.
	var canvas := _paint.canvas()
	if canvas != null:
		draw_texture_rect(canvas, Rect2(Vector2.ZERO, size), false)
	_paint.draw_into(self, size)


# --- internals ---------------------------------------------------------------

## A radial gauge: the same reading, wrapped.
##
## SECTION 6.1'S, and nothing else's now. The permanent corner cluster was the
## only caller and it has been deleted; this is kept because 6.1 -- Tab
## 「看一眼自己」, the game's one place numbers appear -- is 断弧 around the
## character and this is the element it will be made of. The layout data it needs
## is already authored and tested (ring spans, the 14 degree gaps, the opening
## that closes at the bottom).
##
## The reserve creeps around the ring from the top rather than a wedge sweeping
## round it. `markers` are where the model's own thresholds sit along the gauge,
## 0..1 -- so the player can see the next place his body changes before he
## reaches it, which is the one thing a bare level cannot say.
func place_ring(
	home: Vector2,
	radius_px: float,
	viewport_size: Vector2,
	markers := Vector4(-1.0, -1.0, -1.0, -1.0)
) -> void:
	_home = home
	_track_px = maxf(radius_px, 1.0) * RING_SPAN
	_viewport = viewport_size
	var pad := _pad_px()
	var extent := radius_px + pad
	size = Vector2(extent * 2.0, extent * 2.0)
	position = _home
	if _paint != null:
		# From the top, clockwise. The opening is at the bottom so the gauge
		# reads as an arc rather than as a closed dial -- the same reason section
		# 6.1's ring is 断弧.
		_paint.set_ring(
			size, Vector2(extent, extent), radius_px,
			-PI * 0.5 + RING_OPENING * 0.5, RING_SPAN
		)
		_paint.set_markers(markers, _tokens.design_px(MARKER_DESIGN_PX, _viewport)
			if _tokens != null else MARKER_DESIGN_PX)
	_apply_weights()
	queue_redraw()


## Where the gauge's centre sits inside this element, for whoever draws the
## glyph that stands in it.
func centre() -> Vector2:
	return size * 0.5


func _apply_reading_colour() -> void:
	if _paint == null:
		return
	# The TOKEN says what the reading means; the ground says which of the twelve
	# can carry it here. What used to be in this line was a different thing and is
	# not coming back: a continuous solve that bisected HSV value to LIFT the
	# mark's lightness on a dark frame, producing a thirteenth colour, for a
	# readout that was on screen at every hour. See the note at the foot of
	# VitalTone, and UIInk's header for the line between them.
	_paint.set_reserve_colour(reading_colour())


func _pad_px() -> float:
	if _tokens == null:
		return PAD_DESIGN_PX
	return _tokens.design_px(PAD_DESIGN_PX, _viewport)


func _apply_weights() -> void:
	if _paint == null or _tokens == null:
		return
	# Stroke weights come from the look's own system, scaled by what the state
	# calls for -- a reading in trouble is heavier, which is the only emphasis
	# channel rule 3 leaves open.
	var trough := _tokens.design_px(Engraved.RAIL_STROKE, _viewport)
	var heavy: float = Engraved.SMALL_STROKE
	var fill := _tokens.design_px(
		heavy * VitalTone.fill_design_px(_state) / VitalTone.FILL_DESIGN_PX, _viewport)
	# Needles scale with the interface, not with the world: the frame's scale
	# changes when the player cycles the camera's framing stops and the ice must
	# not, or the readout would be a different weight at every stop.
	var texture := _tokens.design_px(
		TEXTURE_DESIGN_PX * VitalTone.texture_ratio(_state), _viewport)
	_paint.set_weights(trough, fill, texture)
	# One design pixel, scaled, and never allowed to round to nothing: the
	# outline is what makes a hairline legible against lit snow, and a hairline
	# with no outline is invisible exactly where the frame is brightest.
	_paint.set_outline(maxf(_tokens.design_px(1.0, _viewport), 1.0))
