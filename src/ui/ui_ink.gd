class_name UIInk
extends RefCounted

## WHICH of the twelve an element in the breath layer is drawn in, given how
## bright the frame behind it is.
##
## Not what a value means -- that is VitalTone, and it is a different question
## with a different answer. This file only ever CHOOSES between palette entries;
## it never makes one. There is no arithmetic on a colour anywhere in it, and
## that is the line between it and the night lift that was deleted (see the foot
## of vital_tone.gd): that solved for a lightness by bisecting HSV and produced a
## thirteenth colour, because a PERMANENT readout had to survive every hour.
## Nothing here is permanent and nothing here is synthesised.
##
## ---------------------------------------------------------------------------
## WHY THIS IS ONE FILE AND NOT TWO IDENTICAL ONES
## ---------------------------------------------------------------------------
## The time prompt (section 5.10) found this first and solved it in TimeArc. The
## threshold note (section 5.2) has exactly the same problem for exactly the same
## reason, and a second copy of the rule would be two crossovers that agree today
## -- which is the failure threshold_note.gd's own header warns about for the
## thresholds, and which this project has since paid for twice more.
##
## So the rule is here, once, and both elements read it.
##
## ---------------------------------------------------------------------------
## THE PALETTE HAS NO LIGHT COLOUR. ITS LIGHT HALF *IS* THE SNOW.
## ---------------------------------------------------------------------------
## Measured three times now, independently: against lit snow, `snow_tones[0]`
## through `snow_tones[4]` run 1.00 to 2.00 : 1, and the brightest warm entry
## `#FFB257` is 1.13 : 1 -- almost exactly snow's own luminance, as well as being
## forbidden by rule 3 for anything but heat.
##
## So an element does not separate from snow by being brighter or more saturated.
## It separates by being DARK. And on a night ground the reverse holds, so the
## ink is chosen rather than fixed.
##
##   ground                        steady mark        in trouble
##   ------------------------------------------------------------------
##   dark   (< DARK_GROUND_BELOW)  ink/primary        ink/primary  *
##   bright (>=)                   line/deep          alarm/blood
##
## `*` is the one place section 5.2 cannot be followed, and it is stated rather
## than hidden. 濒危 asks for `alarm/blood`; that entry is `#6E2F2E` at luminance
## 0.055, which measures **1.57 : 1** against the night ground under the note.
## On the one ground where a man is most likely to be freezing, the document's
## alarm colour is the least visible ink in the element. There is no light red in
## these twelve and rule 3 forbids reaching for a warm one, so at night urgency
## is carried by the two channels section 5.2 already gives it -- WEIGHT
## (VitalTone.fill_design_px) and 颤 -- and the colour resumes the moment the
## ground is bright enough to show it.

## A lighting preset's ambient energy as the relative luminance of the ground it
## produces. Empirical, fitted on two captures, and NOT accurate in between: at
## `nightfall` it predicts 0.350 where the frame under the note measures 0.227.
##
## That error is survivable and it is survivable for a stated reason -- the
## crossover below sits far enough above the ground at which the two inks are
## equally legible (0.135) that a fit off by 0.12 still lands on the right side.
## tests/unit/test_threshold_ink.gd pins that margin as a relationship, so a
## palette change fails there rather than in a frame nobody captured.
const GROUND_TO_LUMINANCE := 0.2524
const GROUND_LUMINANCE_OFFSET := -0.2306

## Where the light ink gives way to the dark one. THREE MEASUREMENTS BOUND IT,
## and it is written here as the number that satisfies all three rather than as a
## number that looked about right:
##
##   > 0.135   the ground at which the two inks are equally legible by contrast
##             arithmetic. Above it the dark ink wins outright, so a crossover
##             below this would hand a dark frame an ink that reads worse.
##   > 0.148   what ground_for() ESTIMATES for `deep_night`, whose frame really
##             measures 0.1156. The band between the two absorbs the estimator's
##             error, so a genuinely dark frame cannot be pushed onto the dark ink
##             by a fit that is off.
##   < 0.2269  the darkest ground measured in a real frame -- `nightfall`, under
##             the threshold note -- that reads BETTER in the dark ink: 3.78 : 1
##             against the light ink's 1.69 : 1.
##
## It was 0.25 when only the time prompt used it, which is above that last bound.
## Nothing shipped was wrong, because ground_for() estimates `nightfall` at 0.350
## and so never asked the question -- but a value that is only correct because a
## known-inaccurate estimate never probes it is a trap with a fuse in it, and
## tests/unit/test_threshold_ink.gd is what found it by feeding the rule the
## MEASURED grounds instead of the fitted ones.
const DARK_GROUND_BELOW := 0.19

## What an element assumes before the lighting has told it anything. Bright, so
## an unlit harness draws the dark ink: of the two wrong answers that is the mild
## one (2.26 : 1 on a night ground), where the other is 1.34 : 1 on snow.
const UNKNOWN_GROUND := 0.5


## True when the frame is dark enough that a light ink separates better than a
## dark one.
static func is_dark_ground(ground: float) -> bool:
	return ground < DARK_GROUND_BELOW


static func ground_for(preset) -> float:
	if preset == null:
		return UNKNOWN_GROUND
	return clampf(
		float(preset.ambient_energy) * GROUND_TO_LUMINANCE + GROUND_LUMINANCE_OFFSET, 0.0, 1.0)


## The mark's ink with nothing wrong: section 2.1's `ink/primary`, or its
## dark-scene counterpart where `ink/primary` is the colour of the snow.
static func mark_for(tokens: UITokens, ground: float) -> Color:
	if tokens == null:
		# Magenta with no tokens, matching UITokens.colour()'s convention: an
		# element drawn with no design tokens loaded should be impossible to miss
		# rather than plausibly grey.
		return Color.MAGENTA
	return tokens.ink_primary if is_dark_ground(ground) else tokens.line_deep


## The same mark, told what the reading is worth. See the table in the header for
## the one cell where this departs from section 5.2.
static func for_state(tokens: UITokens, state: VitalTone.State, ground: float) -> Color:
	if tokens == null:
		return Color.MAGENTA
	if state == VitalTone.State.EMPTY:
		# Section 6.1: 已归零 -- 弧变成一段 1px 的空槽。**不是红色，是空的**. The
		# groove, unchanged: it is not drawn by section 5.2's note at all (an empty
		# reading sweeps nothing), and it belongs to the ring that is still unbuilt.
		return VitalTone.colour_for(tokens, state)
	if state != VitalTone.State.STEADY and not is_dark_ground(ground):
		return tokens.alarm_blood
	return mark_for(tokens, ground)
