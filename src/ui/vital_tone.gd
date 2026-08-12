class_name VitalTone
extends RefCounted

## How a survival reading LOOKS, given only what it is worth.
##
## ---------------------------------------------------------------------------
## ONE TABLE, TWO READOUTS
## ---------------------------------------------------------------------------
## The UI design document states the state table twice -- once in section 5.2 for
## the surfacing note and once in section 6.1 for the Tab ring -- and the two
## statements are not identical. 5.2 turns to alarm at 濒危（<0.15）; 6.1 turns at
## <0.25 and adds the shiver and the guttering at <0.15.
##
## They are the same table seen at two resolutions, and 6.1's is the finer one:
## everything 5.2 says is true inside it. So this file holds 6.1's and every
## readout uses it, and the note that announces a crossing, the Tab ring that
## answers a request for it, and anything in the world that reacts to the man's
## condition can never disagree about what "in trouble" means -- which they would
## within about a week if each carried its own thresholds.
##
## state_for() is the whole of that agreement, and it is the only thing in this
## file that is not about appearance. VitalReadings is what puts it together with
## a value; if the threshold table is ever needed outside src/ui -- a creature
## reacting to the player, say -- it is state_for() and these two constants that
## have to travel, not the colours below them.
##
## ---------------------------------------------------------------------------
## WHY THERE IS NO WARM STATE
## ---------------------------------------------------------------------------
## Rule 3: 暖色在 UI 里只有一个含义：热量的存在. A stat being important, or being
## selected, or being the one the player should look at, is NOT heat -- so none of
## those may reach for `life/warm`. The one warm thing this file will hand out is
## recovery_dot_colour(), because a reserve coming back up IS heat entering the
## body, and section 5.2 names that as the single legal warm use in the breath
## layer.
##
## Emphasis is therefore done the way rule 3 requires: with cool VALUE and STROKE
## WEIGHT. A stat in trouble is not warmer, it is heavier and it moves.

enum State {
	## Nothing to say. `ink/primary`, still.
	STEADY,
	## Section 6.1's < 0.25. `alarm/blood`.
	ALARM,
	## Section 6.1's < 0.15. Alarm, plus 颤 and the guttering of a fire going out.
	CRITICAL,
	## The floor. Section 6.1: 弧变成一段 1px 的空槽。**不是红色，是空的**.
	EMPTY,
}

const ALARM_BELOW := 0.25
const CRITICAL_BELOW := 0.15

## Section 6.1: 像将熄的火一样明灭（0.7 Hz，振幅 40%）.
const GUTTER_HERTZ := 0.7
const GUTTER_AMPLITUDE := 0.4

## Section 2.4's 呼吸: warm elements at 0.25 Hz, amplitude ±14%. Read off the
## tokens rather than written here, so the cold snap and the design document stay
## in charge of it; these are only the fallbacks for a caller with no tokens.
const BREATHE_SECONDS := 4.0
const BREATHE_AMPLITUDE := 0.14

## Design pixels. The trough is section 4.2's slider track -- one pixel, the
## thinnest thing the interface owns -- and the reserve is drawn over it heavier.
const TROUGH_DESIGN_PX := 1.0
const FILL_DESIGN_PX := 3.0

## What EMPTY collapses to. Not a thinner red line: no line at all beyond the
## trough, because the trough is the shape of what is gone.
const EMPTY_FILL_DESIGN_PX := 1.0

## STEADY is deliberately not the heaviest weight available. A stat in trouble
## has to be able to gain weight, and it cannot if the calm state already spent
## it.
const ALARM_FILL_DESIGN_PX := 4.0


static func state_for(fraction: float, depleted := false) -> State:
	if depleted or fraction <= 0.0:
		return State.EMPTY
	if fraction < CRITICAL_BELOW:
		return State.CRITICAL
	if fraction < ALARM_BELOW:
		return State.ALARM
	return State.STEADY


## Magenta with no tokens, matching UITokens.colour()'s own convention: a
## readout drawn with no design tokens loaded should be impossible to miss
## rather than plausibly grey.
##
## ---------------------------------------------------------------------------
## THIS IS SECTION 5.2'S OWN TABLE, RESTORED
## ---------------------------------------------------------------------------
## It briefly returned a single charcoal for everything, under a ruling the owner
## made about the permanent corner readouts -- 整个 HUD 所有的元素都使用这个单一
## 颜色. Those readouts have been deleted, so that ruling has no subject left, and
## an orphaned decision quietly governing the elements that outlived it is how a
## look drifts away from the document nobody re-read.
##
## Section 5.2: 恶化 -- 图标与弧 `ink/primary`; 濒危（<0.15）-- 转 `alarm/blood`.
## Section 6.1 states the same table one step finer -- alarm at <0.25 -- and adds
## 已归零：弧变成一段 1px 的空槽。**不是红色，是空的**, which is why EMPTY is the
## trough's own hairline rather than a dimmer red.
##
## Rule 3 survives it: none of these is warm. The one legal warm mark in the
## breath layer is recovery_dot_colour(), because heat entering the body IS
## 热量的存在.
static func colour_for(tokens: UITokens, state: State) -> Color:
	if tokens == null:
		return Color.MAGENTA
	match state:
		State.ALARM, State.CRITICAL:
			return tokens.alarm_blood
		State.EMPTY:
			return tokens.line_hairline
	return tokens.ink_primary


## The groove the reserve runs in. Always the hairline: it is the one part of the
## readout that does not change with the news.
static func trough_colour_for(tokens: UITokens) -> Color:
	return Color.MAGENTA if tokens == null else tokens.line_hairline


## Section 5.2: 弧反向收拢，`life/warm` 的点从末端走回——这是暖色在呼吸层唯一的合法
## 用途，因为它表示热量正在进入身体.
static func recovery_dot_colour(tokens: UITokens) -> Color:
	return Color.MAGENTA if tokens == null else tokens.life_warm


## Rule 3 done properly: emphasis is WEIGHT, not warmth.
static func fill_design_px(state: State) -> float:
	match state:
		State.ALARM, State.CRITICAL:
			return ALARM_FILL_DESIGN_PX
		State.EMPTY:
			return EMPTY_FILL_DESIGN_PX
	return FILL_DESIGN_PX


static func trough_design_px() -> float:
	return TROUGH_DESIGN_PX


## How much of whatever texture the look has belongs on this reading, 0..1.
##
## A RATIO, not a length, and that is the seam doing its job: this file decides
## what a value MEANS and a VitalPaint decides what that looks like. Naming a
## pixel count here tied the meaning layer to one visual language -- it did,
## briefly -- and that is the leak that turns a change of look into a rewrite.
##
## Zero at EMPTY, and that is the state doing its own talking. Section 6.1: 已归零
## -- 弧变成一段 1px 的空槽。**不是红色，是空的**. A reading with texture still
## on it is not empty; it is a reading in trouble. Taking it away entirely is the
## only way the two are distinguishable at a glance.
static func texture_ratio(state: State) -> float:
	return 0.0 if state == State.EMPTY else 1.0


static func shivers(state: State) -> bool:
	return state == State.CRITICAL


## Section 2.4's 颤: 83 ms 循环 · steps(2) · 1px · 12 Hz. A two-step square wave,
## not a sine -- `steps(2)` is in the specification and it is the difference
## between a tremble and a wobble.
##
## HORIZONTAL, and that is a decision rather than an axis picked at random. These
## readouts are a vertical stack; a vertical jitter on one of them reads as the
## stack re-laying itself out, which is a layout bug. Sideways reads as the
## element itself shaking, which is what it is.
static func shiver_offset(
	tokens: UITokens, viewport_size: Vector2, elapsed: float, state: State
) -> Vector2:
	if not shivers(state) or tokens == null or not is_finite(elapsed):
		return Vector2.ZERO
	var phase := fposmod(elapsed * tokens.shiver_hertz, 1.0)
	if phase < 0.5:
		return Vector2.ZERO
	return Vector2(tokens.design_px(tokens.shiver_pixels, viewport_size), 0.0)


## Section 6.1's 明灭 for a stat about to go: the brightness of a fire running
## out. Returns a multiplier in [1 - amplitude, 1], starting at 1 so the element
## never appears already dimmed on the frame it turns critical.
static func gutter(elapsed: float, state: State) -> float:
	if state != State.CRITICAL or not is_finite(elapsed):
		return 1.0
	var wave := 0.5 - 0.5 * cos(TAU * GUTTER_HERTZ * elapsed)
	return 1.0 - GUTTER_AMPLITUDE * wave


## Section 2.4's 呼吸, for the one warm thing in the interface. Same shape as
## gutter(): starts at 1 and dips, so a warm mark does not blink on.
static func breathe(tokens: UITokens, elapsed: float) -> float:
	if not is_finite(elapsed):
		return 1.0
	var period := BREATHE_SECONDS
	var amplitude := BREATHE_AMPLITUDE
	if tokens != null:
		period = maxf(tokens.breathe_seconds, 0.0001)
		amplitude = tokens.breathe_amplitude
	var wave := 0.5 - 0.5 * cos(TAU * elapsed / period)
	return 1.0 - amplitude * wave


## ---------------------------------------------------------------------------
## WHAT USED TO BE HERE, AND WHY IT IS NOT
## ---------------------------------------------------------------------------
## A single charcoal for the whole interface, a world-brightness adaptation that
## lifted the mark's lightness on a dark frame, and a warm ramp for the day dial.
## All three existed for ONE element: the permanent corner cluster, which had to
## stay legible against every weather at every hour because it was always there.
##
## The owner deleted that element. A note that lives three and a half seconds and
## announces itself does not need to survive the whole lighting range, and the
## adaptation's own cost -- on `deep_night` the mark was no longer charcoal by
## value, only by hue -- was a price paid for permanence and nothing else.
##
## The measurements are not lost: they are in
## .superpowers/sdd/wave3/task-w3-hud-report.md section 3, with the arithmetic
## that showed no opacity value could reach 4:1 against a ground at luminance
## 0.093. If a permanent mark is ever wanted again, that is where the work is.
