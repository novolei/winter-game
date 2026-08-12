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
## everything 5.2 says is true inside it. So this file holds 6.1's, both readouts
## use it, and the permanent readouts and the note that announces a crossing can
## never disagree about what "in trouble" looks like -- which they would within
## about a week if each carried its own thresholds.
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
## `is_heat` is true for the ONE reading that is the body's own warmth. See
## heat_colour_for().
## ONE COLOUR, WHATEVER THE READING IS DOING. See CHARCOAL.
##
## The state still changes what the gauge looks like -- it changes its FORM and
## its WEIGHT, which is what rule 3 left available once colour was spent, and
## what the whole emphasis design already ran on. The colour argument survives
## only so that a look which does want a per-state colour can be dropped in
## behind the seam without every caller changing.
static func colour_for(_tokens: UITokens, _state: State, _is_heat := false) -> Color:
	return CHARCOAL


## The core-temperature gauge, and the only warm element in the interface.
##
## ---------------------------------------------------------------------------
## THIS IS NOT AN EXCEPTION TO RULE 3. IT IS RULE 3
## ---------------------------------------------------------------------------
## 暖色在 UI 里只有一个含义：热量的存在. The body's core temperature IS the presence
## of heat -- there is no reading in the game that means that more literally --
## so drawing it warm is the rule being obeyed rather than bent. Every other
## reading stays cool because none of them is heat, however urgent it gets.
##
## Made the LARGEST element as well, which is what turns the constraint into the
## design: the biggest thing on the interface is the only warm thing on it, and
## it is warmth. GDD section 2's first pillar, 暖色即生存, stated without a word.
##
## ---------------------------------------------------------------------------
## AND THE RAMP IS THE THREE WARM TONES DOING WHAT SECTION 2.1 SAYS THEY MEAN
## ---------------------------------------------------------------------------
##   life/warm   #FFB257  heat, present            -- a body that is holding
##   life/ember  #A05A35  暖色的暗档——火将熄、余烬    -- a body running out
##   alarm/blood #6E2F2E  仅伤害与死亡              -- a body being lost
##
## Same hue family, two stops apart in value, which is exactly the relationship
## section 2.1 describes between them. So the gauge does not change colour when
## it goes wrong; it goes DIM, the way a fire does.
static func heat_colour_for(tokens: UITokens, state: State) -> Color:
	if tokens == null:
		return Color.MAGENTA
	match state:
		State.CRITICAL:
			return tokens.alarm_blood
		State.ALARM:
			return tokens.life_ember
		State.EMPTY:
			return tokens.line_hairline
	return tokens.life_warm


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


# --- one colour, and the world it has to be seen against ----------------------

## THE COLOUR OF THE WHOLE INTERFACE. There is exactly one.
##
## 圆环就做成炭黑透明一种颜色就好了，整个 HUD 所有的元素都使用这个单一颜色 -- the
## owner's ruling. Every arc, every icon, every numeral. It retires the state
## colour table, the warm ramp and the adaptive-hue scheme in one line.
##
## WHAT IT COSTS, RECORDED SO THE DECISION IS FINDABLE. There is now no warm
## pixel anywhere in the interface. The day dial and the temperature gauge were
## to be warm because rule 3 gives warm exactly one meaning and those two
## readings ARE heat -- and the largest object on screen losing its warmth at
## nightfall would have said 暖色即生存 without a word. That is gone by choice.
##
## Rule 3 is not broken by this. The rule forbids warm from meaning anything but
## heat, and an interface with no warm in it cannot break that; it simply no
## longer says the thing warm was there to say.
##
## THE SAME SUBSTANCE AS THE OCCLUDER FADE. #16181C is the off-palette neutral
## already authorised for the fade -- the colour a building turns when it gets
## out of the player's way. This is deliberately the same value, so the interface
## and the fade are made of one substance, and that substance is the game
## stepping politely out of the way. test_vital_tone.gd asserts they agree.
const CHARCOAL := Color(0.08627451, 0.09411765, 0.10980392)

## How a lighting preset's ambient energy maps to the relative luminance of the
## ground it produces.
##
## EMPIRICAL AND RE-MEASURABLE. Fitted to three frames captured through
## tools/capture_vitals.tscn with `--preset`, sampling the ground the readouts
## actually stand on:
##
##   deep_night  ambient 1.5  ->  measured 0.093
##   whiteout    ambient 2.9  ->  measured 0.474   (this line predicts 0.450)
##   pale_day    ambient 3.2  ->  measured 0.526
##
## Ambient rather than sun energy because this game's frame is snow under a flat
## sky: `pale_day` has no sun term at all and is the brightest of the six. If a
## preset is retuned, re-run those captures and refit -- the harness prints what
## it measured, which is the whole reason it does.
const AMBIENT_TO_LUMINANCE := 0.2547
const AMBIENT_OFFSET := -0.289

## What the mark may fade between. The floor keeps it from becoming a black bar
## on a bright frame; the ceiling keeps it from becoming a hole on a dark one.
const OPACITY_FLOOR := 0.42
const OPACITY_CEILING := 0.92

## The contrast the mark tries to hold against the ground behind it.
##
## 3.5 rather than 4.0 because 4.0 is not reachable at BOTH ends without the mark
## going lighter than it needs to on a dark frame. Stored as a ratio and not as a
## table of six colours: a table is right today and wrong the moment a preset is
## retuned or a seventh weather is authored.
const WORLD_CONTRAST := 3.5

## Above this the light option is abandoned for the dark one. A mark pinned at
## the top of the range has no headroom left and stops tracking at all.
const LIGHT_CEILING := 0.90


## Relative luminance, the sRGB definition. Used to COMPARE the interface with
## the ground rather than to look at it, so it has to be the perceptual one.
static func relative_luminance(colour: Color) -> float:
	return 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)


static func _linear(channel: float) -> float:
	var c := clampf(channel, 0.0, 1.0)
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## How bright the world is right now, 0..1, from the blended lighting preset.
##
## The LIGHTING, not the clock. Time and brightness mostly agree and sometimes do
## not -- a whiteout at noon is bright and flat, `pale_day` at noon is bright and
## blue. LightingDirector.active_preset() returns the BLEND while a crossfade is
## running, so the interface inherits that eight-second fade for free and moves
## with the world at the world's own pace, with no pop to engineer around.
static func world_value(preset) -> float:
	if preset == null:
		return 0.5
	return clampf(
		float(preset.ambient_energy) * AMBIENT_TO_LUMINANCE + AMBIENT_OFFSET, 0.0, 1.0)


## The mark, at the value and strength today's weather needs.
##
## ---------------------------------------------------------------------------
## OPACITY ALONE CANNOT DO IT, AND THE ARITHMETIC IS WHY
## ---------------------------------------------------------------------------
## Charcoal sits at relative luminance 0.009. `deep_night`'s ground measures
## 0.093. The best contrast available between them, AT ANY OPACITY, is
##
##     (0.093 + 0.05) / (0.009 + 0.05) = 2.42 : 1
##
## so no strength setting reaches a legible mark on a dark frame. A HUD the
## player cannot read in the dark is not simple, it is absent.
##
## So the VALUE lifts too. One hue, one identity, one place in the code -- but
## not one fixed value, because "follows the world" has to mean that once the
## arithmetic is in front of you.
##
## The mark takes the dark option while it is reachable and the light one when it
## is not, which is the same rule producing opposite pictures: charcoal on the
## bright weather the game spends most of its time in, and a pale neutral of the
## same hue on `deep_night`. HUE AND SATURATION ARE NEVER TOUCHED, which is what
## keeps it recognisably one material and keeps rule 3 true through the change.
##
## THE COST, STATED: on `deep_night` the mark is no longer charcoal by value. It
## is the same hue at a much higher lightness. There is no way around that -- see
## the arithmetic above -- and it is flagged for the owner rather than absorbed.
static func adapt(_token: Color, world: float) -> Color:
	var ground := clampf(world, 0.0, 1.0)
	# THE CONTRAST IS A FLOOR, NOT A TARGET. Charcoal already gives 8.6:1 on
	# `whiteout`, and lightening it to land exactly on the floor would THROW
	# CONTRAST AWAY on the weather the game spends most of its time in -- which
	# is what the first version of this did, measured: whiteout fell from 8.65:1
	# to 2.46:1 while fixing the night. So the mark is left alone wherever it is
	# already dark enough, and only lifts where it cannot be.
	var darkest := relative_luminance(CHARCOAL)
	var wanted_dark := (ground + 0.05) / WORLD_CONTRAST - 0.05
	if darkest <= wanted_dark:
		var plain := CHARCOAL
		plain.a = opacity_for(ground)
		return plain
	# Nothing can be usefully darker than this ground, so go the other way.
	var lighter := clampf(WORLD_CONTRAST * (ground + 0.05) - 0.05, 0.0, LIGHT_CEILING)
	var mark := with_luminance(CHARCOAL, lighter)
	mark.a = opacity_for(ground)
	return mark


## The same colour at a different lightness. Hue and saturation are preserved.
##
## Solved by bisection on HSV value rather than by scaling the channels: scaling
## drags saturation with it, and a tinted neutral washes toward white as it
## brightens, which is exactly the drift that would stop it reading as one
## material across the six presets.
static func with_luminance(colour: Color, target: float) -> Color:
	var low := 0.0
	var high := 1.0
	var value := colour.v
	for _step in range(14):
		value = (low + high) * 0.5
		if relative_luminance(Color.from_hsv(colour.h, colour.s, value, colour.a)) < target:
			low = value
		else:
			high = value
	return Color.from_hsv(colour.h, colour.s, value, colour.a)


## The strength the mark is drawn at, for whatever colour it is.
static func opacity_for(world: float) -> float:
	return clampf(lerpf(OPACITY_CEILING, OPACITY_FLOOR, clampf(world, 0.0, 1.0)), 0.0, 1.0)


## THE ONE WARM THING, AND IT DRAINS.
##
## ---------------------------------------------------------------------------
## WARM HERE OBEYS RULE 3 RATHER THAN EXCEPTING IT
## ---------------------------------------------------------------------------
## 暖色在 UI 里只有一个含义：热量的存在. The day dial is warm because SUNLIGHT IS
## HEAT -- GDD section 2's first pillar is 暖色即生存 and the sun is the valley's
## only free source of it. So the largest object on the interface is warm while
## the sun is up and loses its temperature as the light goes.
##
## The ramp is the three warm tones doing exactly what section 2.1 says they
## mean, ending at the interface's own colour:
##
##   life/warm   #FFB257  heat, present          -- full daylight
##   life/ember  #A05A35  火将熄、余烬             -- the day running down
##   charcoal    #16181C  the rest of the HUD    -- night
##
## Same hue family, falling in value, so the dial does not change colour at
## nightfall -- it goes OUT, the way a fire does. And it rides the same input the
## opacity does (LightingDirector's blended preset), so it is two behaviours on
## one number rather than two mechanisms, and it inherits the eight-second
## crossfade without a step.
static func warm_for(tokens: UITokens, world: float) -> Color:
	if tokens == null:
		return Color.MAGENTA
	var day := clampf(world, 0.0, 1.0)
	# EMBER_AT is where the ramp hands over. Set above the mid-point because a
	# day that has visibly begun to cool is the information -- a dial that stayed
	# at full warmth until dusk would announce nightfall at the moment it is too
	# late to act on it, which is the failure GDD section 7's 预兆 rule exists to
	# prevent for the weather.
	const EMBER_AT := 0.62
	var colour := tokens.life_ember
	if day >= EMBER_AT:
		colour = tokens.life_ember.lerp(
			tokens.life_warm, (day - EMBER_AT) / (1.0 - EMBER_AT))
	else:
		colour = CHARCOAL.lerp(tokens.life_ember, day / EMBER_AT)
	colour.a = opacity_for(day)
	return colour
