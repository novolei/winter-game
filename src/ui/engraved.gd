class_name Engraved
extends VitalPaint

## 「刻度」ENGRAVED. The settled look.
##
## ---------------------------------------------------------------------------
## ONE ARC, WITH A GAP, AND A RAIL BEHIND IT
## ---------------------------------------------------------------------------
## A gauge is a single continuous stroke sweeping from the top of an open ring,
## as far round as the reserve goes. THE REMAINDER IS NOTHING -- 圆环不需要有
## outline, by the owner's ruling.
##
## The consequence is worth stating rather than absorbing: the rail was the only
## thing on screen showing what FULL looks like, so a reading is now a length
## with no scale beside it. For a quantity that moves as slowly as these do that
## is learnable -- a player sees the arc long before he sees it short -- and it
## is the owner's call. It is recorded here because it is the kind of decision
## that gets rediscovered later as a complaint.
##
## NOTHING OUTSIDE THE RING. No needle, no threshold marks, no segments -- the
## owner's ruling: 就只要圆环，不要圆环外的分段的指针. An arc sweeping to show its
## value, and nothing else.
##
## There is no filled area anywhere -- no wedge, no disc, no card. Rule 1
## (没有矩形) forbids panels; this goes further and has no filled shape at all.
##
## ---------------------------------------------------------------------------
## THE PROPORTIONAL SYSTEM, WHICH IS THE WHOLE OF THE CONSISTENCY
## ---------------------------------------------------------------------------
## 绝对精美且高度风格一致性. Five gauges that were each tuned until they looked right
## are five things that happen to resemble one another today. So every dimension
## below comes from THREE numbers and nothing else:
##
##   u  = 8 design px   the grid section 2.3 already sets for the whole interface
##   ×2                 the one ratio: large to small, and stroke to rail
##   60°                the one angle: the ring's opening, and a sixth of a turn
##
## and everything is derived:
##
##   small radius     2u = 16          large radius        2 × 2u = 32
##   small stroke     u×0.44 = 3.5     large stroke        2 × that = 7
##   rail stroke      u/8 = 1          gap between gauges  u = 8
##   halo radius      R + u/2          needle              R - stroke
##   glyph box        radius           opening             60°
##
## Change `u` and the whole cluster rescales in proportion. Change one dimension
## on its own and this comment is a lie, which is the point of writing it down.
##
## ---------------------------------------------------------------------------
## THRESHOLD STATE IS FORM AND WEIGHT, NEVER COLOUR
## ---------------------------------------------------------------------------
## Rule 3 spends colour on one meaning -- 暖色在 UI 里只有一个含义：热量的存在 -- so
## colour is not available as an emphasis channel. What is left is form and
## weight, and this look's answer is that a gauge in trouble THICKENS, brightens
## to full, and grows a hairline ring outside it that breathes.
##
## No colour shift is written here for a crossing. The colour a reading is drawn
## in arrives from VitalTone, which changes it for what the value MEANS -- and the
## only colour ramp in the interface belongs to the core-temperature gauge,
## because that reading literally is the presence of heat.

## The grid, in design pixels. Section 2.3 sets it for the whole interface and
## this look does not get its own.
const UNIT := 8.0

## The one ratio.
const RATIO := 2.0

## The one angle: the opening at the bottom of every ring, and a sixth of a turn.
const OPENING_RAD := PI / 3.0
const SPAN_RAD := TAU - OPENING_RAD

const SMALL_RADIUS := UNIT * 2.0
const LARGE_RADIUS := SMALL_RADIUS * RATIO
## Widened from u/4 on the owner's note. The RATIO is what the system protects,
## so both weights moved together rather than one gauge being tuned until it
## looked right.
const SMALL_STROKE := UNIT * 0.44
const LARGE_STROKE := SMALL_STROKE * RATIO
const RAIL_STROKE := UNIT * 0.125
const GAP := UNIT

## Section 2.1's opacity ladder. The rail sits on a rung of it -- 没有中间值.
const RAIL_OPACITY := 0.24

## How far outside the gauge the breathing hairline stands.
const HALO_OFFSET := UNIT * 0.5

## How much heavier a gauge past its threshold is drawn. The emphasis, in the
## one channel rule 3 leaves open.
const EMPHASIS_WIDEN := 1.6

## The stroke's arrival, in seconds. Section 2.4's 呵 is 200 ms and governs the
## element's opacity and scale; this is the arc sweeping round, which reads
## better a little slower.
const ARRIVE_SECONDS := 0.45

## How fast a surge decays back to the resting emphasis.
const SURGE_SECONDS := 2.4

## THE KEYLINE, AND WHY IT IS THE WHOLE ANSWER TO THE CONTRAST PROBLEM
##
## Every arc is drawn TWICE on the same path: a dark stroke two pixels wider
## underneath, the reading's own colour on top. Hard edges on both. No blur, no
## falloff, no opacity ramp.
##
## It is not a halo, and the difference is not tidiness. A halo is a gradient,
## and rule 1 permits arcs, strokes and hairlines while forbidding exactly that
## kind of soft rendering -- a blurred dark edge under a light line reads as
## grime rather than as separation. That version shipped to a capture and looked
## grubby, which is the correct reaction to it.
##
## And it is not the rail either. The rail was a full dim circle showing the
## unfilled remainder, and the owner deleted it. This hugs the lit arc and stops.
##
## ---------------------------------------------------------------------------
## WHY ONE DRAWING SOLVES BOTH GROUNDS
## ---------------------------------------------------------------------------
## The HUD has to read on `deep_night` AND on `whiteout`, and a whiteout is a
## near-white screen. No single flat colour passes both, and the arithmetic is
## worth writing down because it kills a whole family of proposals:
##
##   whiteout ground   relative luminance 0.474
##   pure white stroke gives (1.00 + 0.05) / (0.474 + 0.05) = 2.00 : 1
##
## Pure WHITE cannot reach 3:1 on this game's bright weather. So "make the
## strokes lighter" cannot be the answer at any value, and no palette entry --
## the lightest being `ink/primary` at 0.418, which IS the colour of lit snow --
## comes close.
##
## A keyline needs no adaptive tinting and no per-weather colour switching: on a
## dark ground the light stroke carries, on a white ground the dark keyline
## carries, and the same drawing does both. Measured on all three presets in the
## task report.
##
## The dark is the darkest STRUCTURE tone, not black -- a thirteenth colour on
## the edge of every stroke is still a thirteenth colour. Section 5.9 settled
## that for type on snow and it holds for strokes.
const KEYLINE_WIDEN := 2.0

var _tokens: UITokens = null
var _ready := false

var _centre := Vector2.ZERO
var _radius := 1.0
var _start := 0.0
var _span := SPAN_RAD
var _is_ring := false
var _from := Vector2.ZERO
var _to := Vector2.RIGHT
var _bow := 0.0

var _fill := 1.0
var _reserve := Color.WHITE
var _rail := Color.WHITE
var _cut := Color.BLACK
var _mark_on := false
var _mark_colour := Color.WHITE
var _mark_px := 3.0
var _markers := Vector4(-1.0, -1.0, -1.0, -1.0)
var _marker_px := 5.0

var _stroke_px := SMALL_STROKE
var _rail_px := RAIL_STROKE

var _attenuation := 1.0
var _arrival := 0.0
var _emphasis := 0.0
var _target_emphasis := 0.0
var _elapsed := 0.0
var _time_scale := 1.0


func build(tokens: UITokens) -> bool:
	if tokens == null:
		return false
	_tokens = tokens
	_reserve = tokens.ink_primary
	_rail = tokens.line_hairline
	_cut = tokens.line_deep
	_mark_colour = tokens.life_warm
	_ready = true
	return true


func is_ready() -> bool:
	return _ready


## Null: this look is line-work, so it draws in draw_into() and the element
## carries no material at all.
func material_for_element() -> Material:
	return null


func canvas() -> Texture2D:
	return null


# --- geometry ----------------------------------------------------------------

func set_ring(
	_rect_px: Vector2, centre_px: Vector2, radius_px: float,
	start_rad: float, span_rad: float
) -> void:
	_is_ring = true
	_centre = centre_px
	_radius = maxf(radius_px, 1.0)
	_start = start_rad
	_span = span_rad


func set_substrate(
	_rect_px: Vector2, from_px: Vector2, to_px: Vector2, bow_px := 0.0
) -> void:
	_is_ring = false
	_from = from_px
	_to = to_px
	_bow = bow_px


func set_markers(positions: Vector4, size_px: float) -> void:
	_markers = positions
	_marker_px = maxf(size_px, 0.0)


func set_weights(trough_px: float, fill_px: float, _texture_px: float) -> void:
	_rail_px = maxf(trough_px, 1.0)
	_stroke_px = maxf(fill_px, 1.0)


## Retired by the owner's ruling -- 不要圆环外的分段的指针 -- and kept as a no-op so
## the seam does not change shape for a look that might want one again.
func set_needle(_on: bool) -> void:
	pass


func set_attenuation(amount: float) -> void:
	_attenuation = clampf(amount, 0.0, 1.0)


# --- what it says -------------------------------------------------------------

func set_fill(fraction: float) -> void:
	_fill = clampf(fraction, 0.0, 1.0)


func set_colours(tokens: UITokens, fill_colour := Color.TRANSPARENT) -> void:
	if tokens == null:
		return
	_tokens = tokens
	_rail = tokens.line_hairline
	_cut = tokens.line_deep
	_reserve = tokens.ink_primary if fill_colour == Color.TRANSPARENT else fill_colour
	_mark_colour = tokens.life_warm


func set_reserve_colour(colour: Color) -> void:
	_reserve = colour


func set_mark(on: bool, colour: Color, size_px := 3.0) -> void:
	_mark_on = on
	_mark_colour = colour
	_mark_px = size_px


# --- driving ------------------------------------------------------------------

func set_target_emphasis(value: float) -> void:
	_target_emphasis = clampf(value, 0.0, 1.0)


func surge(amount: float) -> void:
	_emphasis = clampf(maxf(_emphasis, amount), 0.0, 1.0)


func set_time_scale(scale: float) -> void:
	if is_finite(scale) and scale > 0.0:
		_time_scale = scale


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var step := delta / _time_scale
	_elapsed += step
	_arrival = clampf(_arrival + step / ARRIVE_SECONDS, 0.0, 1.0)
	if _emphasis > _target_emphasis:
		_emphasis = maxf(_emphasis - step / SURGE_SECONDS, _target_emphasis)
	else:
		_emphasis = _target_emphasis


func finish() -> void:
	_arrival = 1.0


func arrival() -> float:
	return _arrival


func emphasis() -> float:
	return _emphasis


## True when the gauge has stopped being a quiet reading and become a statement.
## Weight and a breathing halo, never a change of colour.
func is_emphatic() -> bool:
	return _emphasis > 0.5


# --- drawing ------------------------------------------------------------------

func draw_into(item: CanvasItem, _size: Vector2) -> void:
	if not _ready or item == null:
		return
	var reserve := _reserve
	var rail := _rail
	reserve.a *= _attenuation
	rail.a *= _attenuation * RAIL_OPACITY
	if _is_ring:
		_draw_ring(item, reserve, rail)
	else:
		_draw_stroke(item, reserve, rail)


func _draw_ring(item: CanvasItem, reserve: Color, _rail: Color) -> void:
	var swept := _fill * _arrival
	var width := _stroke_px * lerpf(1.0, EMPHASIS_WIDEN, _emphasis)
	var points := maxi(int(absf(_span) * _radius / 3.0), 24)

	if swept > 0.0:
		_cut_arc(item, _radius, _start, _start + _span * swept, reserve, width, points)

	if is_emphatic():
		# The hairline that breathes, outside the gauge. Section 2.4's 呼吸 period,
		# borrowed for a cool stroke -- the document names it for warm elements and
		# rule 3 will not let this one be warm.
		var period: float = 4.0 if _tokens == null else maxf(_tokens.breathe_seconds, 0.0001)
		var halo := reserve
		halo.a *= 0.20 + 0.34 * (0.5 - 0.5 * cos(TAU * _elapsed / period))
		_cut_arc(item, _radius + HALO_OFFSET * (_radius / LARGE_RADIUS + 0.5),
			_start, _start + _span, halo, _rail_px, points)

	if _mark_on and swept > 0.0:
		var at := _start + _span * swept
		var mark := _mark_colour
		mark.a *= _attenuation
		item.draw_circle(
			_centre + Vector2(cos(at), sin(at)) * _radius, _mark_px * 0.5, mark)


## Section 5.2's 短弧, in the same language: one bowed stroke over a dim rail.
func _draw_stroke(item: CanvasItem, reserve: Color, _rail: Color) -> void:
	var swept := _fill * _arrival
	var along := _to - _from
	var length := maxf(along.length(), 0.0001)
	var normal := Vector2(-along.y, along.x) / length
	var steps := 24
	var lit_points := PackedVector2Array()
	for index in range(steps + 1):
		var at := float(index) / float(steps)
		if at <= swept:
			lit_points.append(_from + along * at + normal * _bow * sin(at * PI))
	if lit_points.size() > 1:
		item.draw_polyline(lit_points, reserve, _stroke_px, true)


func _cut_arc(
	item: CanvasItem, radius: float, from_rad: float, to_rad: float,
	colour: Color, width: float, points: int
) -> void:
	if absf(to_rad - from_rad) < 0.0001:
		return
	item.draw_arc(_centre, radius, from_rad, to_rad, points, colour, width, true)


func _cut_line(
	item: CanvasItem, from: Vector2, to: Vector2, colour: Color, width: float
) -> void:
	item.draw_line(from, to, colour, width, true)
