class_name Breath
extends RefCounted

## 呵 · 持 · 散 -- the envelope every element in this interface is born, held and
## taken by. UI design document sections 1.2 and 2.4.
##
## ---------------------------------------------------------------------------
## WHY THIS IS PURE, AND NOT A TWEEN
## ---------------------------------------------------------------------------
## The envelope IS the specification, so it has to be provable. A Tween-driven
## implementation can only be checked by watching it, and "the overshoot looks
## about right" is not an assertion -- tests/unit/test_breath.gd measures the
## peak, pins both ends of both easing curves, and proves the exit never
## brightens. None of that needs a SceneTree, a Node or a frame.
##
## UILayer does the driving. This object only answers "what does it look like at
## time t", which also means a single element can be sampled by a screenshot
## harness at an exact moment rather than at whatever moment the frame landed on.
##
## ---------------------------------------------------------------------------
## THE THREE PHASES, AND WHY NOTHING MAY SKIP ONE
## ---------------------------------------------------------------------------
## GDD section 7 makes every weather event 预兆 → 持续 → 消退, on the grounds that
## a storm with no warning is unfair rather than difficult. The interface obeys
## the same law for the same reason: an element that appears instantly is an
## ambush on the player's attention.
##
##   呵 BLOOM  scale .94 -> 1.02 -> 1.00, opacity 0 -> 1, blur 4 -> 0
##   持 HOLD   still
##   散 DRIFT  opacity -> 0, blur -> 3, and it goes somewhere
##
## ---------------------------------------------------------------------------
## THE EXIT HAS TWO SHAPES
## ---------------------------------------------------------------------------
## DRIFT is the default: 8 design pixels upward, the way breath actually leaves.
##
## SCATTER is section 5.9's, for world-space inscriptions written one glyph at a
## time. The glyphs do not dissolve -- they are TAKEN, along a direction, turning
## as they go. That direction is the wind, the same wind that erases footprints
## in GDD section 8, so the narration is subject to the valley's own weather
## rather than to a screen effect. A glyph sits perfectly still until the wind
## reaches it; text that crept during its own hold would read as sliding rather
## than as written.

enum Exit { NORMAL, FAST, LONG }

## The two curves of section 2.4, as (x1, y1, x2, y2) control points -- the same
## form CSS cubic-bezier() takes, so the prototype and the game are provably the
## same motion rather than two people's idea of it.
const BLOOM_EASE := Vector4(0.16, 1.0, 0.30, 1.0)
const BLOOM_HEAVY_EASE := Vector4(0.16, 1.2, 0.30, 1.0)
const DRIFT_EASE := Vector4(0.40, 0.0, 0.70, 0.20)

## 散 · 向上飘 -- the LIFT's own curve, and it is deliberately not DRIFT_EASE.
##
## Section 1.2 hands ONE curve to all three of the exit's channels (opacity,
## blur, translateY). Measured on that curve, an exit looks like this:
##
##   40% of the exit gone  ->  alpha 0.90, risen 0.78 px of 8
##   75% gone              ->  alpha 0.53, risen 3.74 px
##   the last 15%          ->  alpha 0.35 -> 0, and 5.19 -> 8.00 px of the rise
##
## So for the first four tenths of its departure the element has not visibly
## departed, and then a third of its ink and three of its eight pixels leave
## together in the final 135 ms. That is a stall followed by a snuff. It is what
## "animates in beautifully and then simply stops existing" looks like once there
## are numbers on it, and it is the opposite of section 1.1's own three words for
## the 散 -- 慢的、边缘先化开的、向上飘的.
##
## Section 5.10 already made this exact split once, from the other side: the
## bloom's elasticity belongs on SCALE and not on a clamped alpha, because one
## curve serving two channels was wrong for one of them. This is that ruling
## applied to the exit.
##
## The FADE keeps section 2.4's curve untouched -- letting go slowly is right,
## and it is what keeps the words readable while they go. The LIFT takes an
## ease-OUT, so it begins on the frame the hold ends and decelerates into
## stillness:
##
##   25% of the exit gone  ->  alpha 0.97, risen 3.07 px of 8
##   50% gone              ->  alpha 0.83, risen 5.89 px
##   the last 25%          ->  0.45 px, which is the settle
##
## The element is therefore visibly LEAVING while it is still fully legible,
## which is the whole difference between a thing that departs and a thing that is
## switched off. Nothing overshoots and nothing bounces; the entire change is
## which end of the exit the motion lives at.
const DRIFT_LIFT_EASE := Vector4(0.39, 0.575, 0.565, 1.0)

## 散 · 边缘先化开 -- the largest share of the exit that any one part of an
## element may leave ahead of the element as a whole. See dispersal_at().
const DISPERSAL_LEAD := 0.45

## Where the bloom's keyframes sit inside its own duration. Opacity and blur
## finish at this point and the overshoot peaks here; the remaining fraction is
## the settle back to 1.0.
const BLOOM_PEAK_FRACTION := 0.60
const SCALE_FROM := 0.94
const SCALE_PEAK := 1.02
const BLUR_FROM := 4.0
const BLUR_TO := 3.0

## Section 2.4's drift, in design pixels.
const DRIFT_RISE := -8.0

## How long after the previous glyph the next one is written.
##
## SET AGAINST THE BLOOM, not chosen for feel. At 0.055 -- the first value here --
## a four character line finished writing in 0.485 s, because the stagger was a
## sixth of the 0.32 s heavy bloom and every glyph overlapped almost completely
## with its neighbours. That does not read as writing, it reads as a fade-in with
## extra steps, and the difference only shows up on a short line where there are
## not enough characters for the lag to accumulate.
##
## At 0.14 a glyph is roughly half written when the next one starts, so the line
## still flows rather than ticking out one character at a time, and a twelve
## character line takes about 1.7 s to write -- a deliberate hand, and a span
## that fits inside a montage shot alongside its hold and its exit.
const GLYPH_STAGGER := 0.14

## How far a scattered glyph may deviate from the wind, in radians. Small: the
## wind has a direction and the letters obey it. Wider than this and the line
## reads as an explosion rather than as something blown away.
## 8 degrees, written in radians because a GDScript constant may not call a
## function.
const SCATTER_SPREAD := 0.1396263

var delay := 0.0
var bloom_seconds := 0.20
var hold_seconds := 2.00
var exit_seconds := 0.90
var bloom_ease := BLOOM_EASE

## Where the exit takes it, in the caller's own units. Zero means the plain
## upward drift.
var exit_offset := Vector2(0.0, DRIFT_RISE)
var exit_spin := 0.0

## Which curve carries the exit's MOTION -- never its opacity, which is always
## section 2.4's 散.
##
## The default LIFTS (see DRIFT_LIFT_EASE). scatter() puts it back on DRIFT_EASE,
## and that is not a compatibility shim: a glyph taken by the wind is being
## CARRIED, and acceleration out of stillness is what makes that read, while an
## element letting go of the screen is LIFTING, and deceleration into stillness
## is what makes that one read. It also leaves section 5.9's approved montage
## frames exactly where they were -- 被批准的是镜头.
var motion_ease := DRIFT_LIFT_EASE

## Position in the line, used to give each glyph its own scatter without
## randomness -- a replay has to look the same twice.
var glyph_index := 0

# --- construction -----------------------------------------------------------

## The ordinary transient element: bloom, hold, drift, gone.
## `hold` below zero takes the token default.
static func surface(tokens: UITokens, hold := -1.0, heavy := false, exit := Exit.NORMAL) -> Breath:
	var b := Breath.new()
	if tokens == null:
		return b
	b.bloom_seconds = tokens.bloom_heavy_seconds if heavy else tokens.bloom_seconds
	b.bloom_ease = BLOOM_HEAVY_EASE if heavy else BLOOM_EASE
	b.hold_seconds = tokens.hold_seconds if hold < 0.0 else hold
	match exit:
		Exit.FAST: b.exit_seconds = tokens.drift_fast_seconds
		Exit.LONG: b.exit_seconds = tokens.drift_long_seconds
		_: b.exit_seconds = tokens.drift_seconds
	return b

## One glyph of a world-space inscription (section 5.9). Staggered by its
## position so the line is written rather than switched on, and held long enough
## that the whole line is readable before the first character is taken -- which
## is why the hold grows with the line's length rather than being a constant.
static func inscription(tokens: UITokens, index: int, count: int, hold := -1.0) -> Breath:
	var b := surface(tokens, hold, true, Exit.LONG)
	b.glyph_index = index
	b.delay = float(index) * GLYPH_STAGGER
	if hold < 0.0 and tokens != null:
		# The last glyph lands `stagger * (count-1)` after the first, so a
		# constant hold would leave the opening word on screen that much longer
		# than the closing one. Extending every glyph's hold by the time the
		# whole line takes to write makes them all readable for the same span.
		b.hold_seconds += float(maxi(count - 1, 0)) * GLYPH_STAGGER
	return b

## Section 5.6. The cold snap adds nothing to the screen; it slows what is
## already on it. Every phase, or the interface would go still in one place and
## not another.
func stretch(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	delay *= factor
	bloom_seconds *= factor
	hold_seconds *= factor
	exit_seconds *= factor

## Sends this glyph off along the wind instead of drifting upward.
##
## The deviation and the spin come from the glyph's index, not from randf():
## neighbouring letters must not fly off identically -- that reads as a sliding
## block rather than a word coming apart -- but the same line replayed must look
## the same, or a montage would differ between two runs of the same scene.
func scatter(wind: Vector2, distance: float, spin: float) -> void:
	# See motion_ease. Carried, not lifted -- and this is also what keeps the
	# montage's already-approved frames unchanged by the exit rework.
	motion_ease = DRIFT_EASE
	var direction := wind.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var angle := _hash_signed(glyph_index, 17) * SCATTER_SPREAD
	exit_offset = direction.rotated(angle) * distance
	# Magnitude kept clear of zero so no glyph leaves without turning at all,
	# which would make it the one letter that looks pinned.
	var magnitude: float = lerpf(0.4, 1.0, _hash_unit(glyph_index, 41))
	exit_spin = spin * magnitude * signf(_hash_signed(glyph_index, 83))

# --- reading ----------------------------------------------------------------

func total_seconds() -> float:
	return delay + bloom_seconds + hold_seconds + exit_seconds

## When the 散 begins. Published because some things have to CHANGE at that
## moment rather than be interpolated across it -- Inscription switches its
## glyphs from clean alpha blending to stochastic discard here, so the text is
## sharp while it is being read and grainy only while it is being taken.
func exit_begins() -> float:
	return delay + bloom_seconds + hold_seconds

func is_finished(t: float) -> bool:
	return t >= total_seconds()

## 0 before the bloom, 1 through the hold, 0 again once it has gone.
func opacity_at(t: float) -> float:
	var phase := _phase(t)
	match phase[0]:
		_PHASE_BEFORE: return 0.0
		_PHASE_BLOOM:
			# Opacity finishes with the overshoot, not with the settle: the
			# element is fully present while it is still coming to rest.
			#
			# CLAMPED, and that is not defensive. BLOOM_HEAVY_EASE's first
			# control point is at y = 1.2, so the curve deliberately overshoots
			# -- which is the juice on SCALE and meaningless on opacity. Measured
			# on the heavy bloom, this returned 1.0044. An alpha above 1 is
			# nonsense a Color will happily carry, and it silently defeats any
			# comparison of the form "is this fully faded in yet".
			var u: float = clampf(phase[1] / BLOOM_PEAK_FRACTION, 0.0, 1.0)
			return clampf(ease_with(bloom_ease, u), 0.0, 1.0)
		_PHASE_HOLD: return 1.0
		_PHASE_EXIT: return 1.0 - ease_with(DRIFT_EASE, phase[1])
	return 0.0

func scale_at(t: float) -> float:
	var phase := _phase(t)
	match phase[0]:
		_PHASE_BEFORE: return SCALE_FROM
		_PHASE_BLOOM:
			var p: float = phase[1]
			if p <= BLOOM_PEAK_FRACTION:
				var u: float = p / BLOOM_PEAK_FRACTION
				return lerpf(SCALE_FROM, SCALE_PEAK, ease_with(bloom_ease, u))
			var v: float = (p - BLOOM_PEAK_FRACTION) / (1.0 - BLOOM_PEAK_FRACTION)
			return lerpf(SCALE_PEAK, 1.0, ease_with(bloom_ease, v))
	return 1.0

## Where it has moved to, in the caller's units. Zero everywhere but the exit --
## an element that crept during its own hold would read as unstable.
##
## On `motion_ease`, which is NOT the fade's curve. See DRIFT_LIFT_EASE.
func offset_at(t: float) -> Vector2:
	var phase := _phase(t)
	if phase[0] == _PHASE_EXIT:
		return exit_offset * ease_with(motion_ease, phase[1])
	if phase[0] > _PHASE_EXIT:
		return exit_offset
	return Vector2.ZERO

func rotation_at(t: float) -> float:
	var phase := _phase(t)
	if phase[0] == _PHASE_EXIT:
		return exit_spin * ease_with(motion_ease, phase[1])
	if phase[0] > _PHASE_EXIT:
		return exit_spin
	return 0.0

## 散 · 边缘先化开, for one PART of an element.
##
## Section 1.1 gives the dispersal three qualities and the screen elements only
## ever built two: they were slow and they drifted upward, and they left as one
## rigid picture. Breath on cold glass does not leave that way -- the thinnest
## ink goes first and the shape comes apart in an order. That order is the half
## of this design language nobody had built.
##
## It is opacity over time and nothing else, so it needs no blur, no gradient, no
## plate and no shader.
##
## `lead` is 0 for the part that leaves LAST -- which is the element's own
## envelope, so a lead of 0 is always exactly 1.0 and costs nothing -- and 1 for
## the part that leaves first. Multiply the result into whatever alpha the part
## is already drawn at; the element's `modulate` carries the rest.
func dispersal_at(t: float, lead: float) -> float:
	var share := clampf(lead, 0.0, 1.0)
	if share <= 0.0:
		return 1.0
	var phase := _phase(t)
	if phase[0] < _PHASE_EXIT:
		return 1.0
	if phase[0] > _PHASE_EXIT:
		return 0.0
	# The same 散 curve, run in a shorter window, so a leading part disperses in
	# the language the element as a whole is dispersing in rather than in a
	# second one. At lead 1 a part is gone 55% of the way through the exit --
	# while the element itself is still at alpha 0.79 -- and that gap is what
	# makes the dispersal visible rather than merely earlier.
	var span := maxf(1.0 - share * DISPERSAL_LEAD, 0.05)
	return 1.0 - ease_with(DRIFT_EASE, minf(phase[1] / span, 1.0))

## Blur is part of the specification even though applying it needs a material:
## UILayer sets what a CanvasItem can carry directly and leaves this to whoever
## gives an element a shader. Published rather than dropped, so the element that
## does blur and the element that does not are following the same numbers.
func blur_at(t: float) -> float:
	var phase := _phase(t)
	match phase[0]:
		_PHASE_BEFORE: return BLUR_FROM
		_PHASE_BLOOM:
			var u: float = clampf(phase[1] / BLOOM_PEAK_FRACTION, 0.0, 1.0)
			return lerpf(BLUR_FROM, 0.0, ease_with(bloom_ease, u))
		_PHASE_HOLD: return 0.0
		_PHASE_EXIT: return lerpf(0.0, BLUR_TO, ease_with(DRIFT_EASE, phase[1]))
	return BLUR_TO

# --- easing -----------------------------------------------------------------

## A CSS-shaped cubic-bezier: control points (0,0), (x1,y1), (x2,y2), (1,1).
## `x` is progress along the animation, the return is progress along the value.
##
## Solved rather than approximated because the two curves are the design, and
## because an ease that missed its endpoints would leave elements permanently a
## fraction of a pixel off -- invisible one at a time, and a drifting layout in
## aggregate.
static func ease_with(curve: Vector4, x: float) -> float:
	var p := clampf(x, 0.0, 1.0)
	if p <= 0.0 or p >= 1.0:
		return p
	var t := _solve_for_x(curve.x, curve.z, p)
	return _bezier(curve.y, curve.w, t)

static func _bezier(a: float, b: float, t: float) -> float:
	var inv := 1.0 - t
	return 3.0 * inv * inv * t * a + 3.0 * inv * t * t * b + t * t * t

static func _bezier_slope(a: float, b: float, t: float) -> float:
	var inv := 1.0 - t
	return 3.0 * inv * inv * a + 6.0 * inv * t * (b - a) + 3.0 * t * t * (1.0 - b)

## Newton-Raphson from a sensible seed, with bisection as the fallback. Newton
## alone stalls where the curve is flat -- which is exactly where both of these
## curves spend their time -- and a stalled solve returns the seed, so the ease
## would silently become linear at its most important moments.
static func _solve_for_x(x1: float, x2: float, x: float) -> float:
	var t := x
	for _i in range(8):
		var error := _bezier(x1, x2, t) - x
		if absf(error) < 0.000001:
			return t
		var slope := _bezier_slope(x1, x2, t)
		if absf(slope) < 0.000001:
			break
		t -= error / slope
	var low := 0.0
	var high := 1.0
	t = x
	for _i in range(24):
		var value := _bezier(x1, x2, t)
		if absf(value - x) < 0.000001:
			return t
		if value > x:
			high = t
		else:
			low = t
		t = (low + high) * 0.5
	return t

# --- internals --------------------------------------------------------------

const _PHASE_BEFORE := 0
const _PHASE_BLOOM := 1
const _PHASE_HOLD := 2
const _PHASE_EXIT := 3
const _PHASE_AFTER := 4

## [phase, progress within it 0..1].
func _phase(t: float) -> Array:
	if not is_finite(t) or t <= delay:
		return [_PHASE_BEFORE, 0.0]
	var local := t - delay
	if local < bloom_seconds:
		return [_PHASE_BLOOM, local / maxf(bloom_seconds, 0.000001)]
	local -= bloom_seconds
	if local < hold_seconds:
		return [_PHASE_HOLD, local / maxf(hold_seconds, 0.000001)]
	local -= hold_seconds
	if local < exit_seconds:
		return [_PHASE_EXIT, local / maxf(exit_seconds, 0.000001)]
	return [_PHASE_AFTER, 1.0]

## Deterministic 0..1 from an index and a salt. The classic fract(sin(x)*k)
## hash: reproducible across runs and platforms because it touches no engine
## RNG state, which is the whole requirement -- a montage replayed must scatter
## its letters the same way.
static func _hash_unit(index: int, salt: int) -> float:
	var value: float = sin(float(index) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return value - floor(value)

static func _hash_signed(index: int, salt: int) -> float:
	return _hash_unit(index, salt) * 2.0 - 1.0
