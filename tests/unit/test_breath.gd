extends TestCase

## The 呵 / 持 / 散 envelope of UI design document sections 1.2 and 2.4.
##
## Breath is deliberately PURE -- no Node, no Tween, no SceneTree -- because the
## envelope is the specification and the specification is what has to be
## provable. A Tween-based implementation could only be checked by watching it,
## and "the overshoot looks about right" is not an assertion.
##
## The scatter exit is the same envelope at glyph granularity: section 5.9's
## world-space inscriptions are written one character at a time and taken by the
## wind, which is the 散 phase given a direction instead of a default drift.

const BreathScript := preload("res://src/ui/breath.gd")

const TOKENS_PATH := "res://data/ui/tokens.tres"

var _tokens: UITokens

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens

# --- the three phases -------------------------------------------------------

func test_the_total_is_the_three_phases_end_to_end() -> void:
	var b = BreathScript.surface(_tokens)
	assert_almost_eq(b.total_seconds(),
		_tokens.bloom_seconds + _tokens.hold_seconds + _tokens.drift_seconds, 0.0001)

## Section 1.2: no element may skip a phase. A zero-length bloom is an element
## that appears instantly, which is the thing the whole doctrine forbids.
func test_no_phase_can_be_zero_length() -> void:
	var b = BreathScript.surface(_tokens)
	assert_true(b.bloom_seconds > 0.0, "bloom")
	assert_true(b.hold_seconds > 0.0, "hold")
	assert_true(b.exit_seconds > 0.0, "exit")

func test_it_starts_invisible_and_undersized() -> void:
	var b = BreathScript.surface(_tokens)
	assert_almost_eq(b.opacity_at(0.0), 0.0, 0.0001)
	assert_almost_eq(b.scale_at(0.0), 0.94, 0.0001, "section 2.4 opens the bloom at .94")

## The juice. Scale passes ABOVE 1 during the bloom and settles exactly on 1 --
## an overshoot that never comes back is a permanently oversized element.
func test_the_bloom_overshoots_and_then_settles_on_exactly_one() -> void:
	var b = BreathScript.surface(_tokens)
	var peak := 0.0
	var steps := 200
	for i in range(steps + 1):
		var t: float = b.bloom_seconds * float(i) / float(steps)
		peak = maxf(peak, b.scale_at(t))
	assert_true(peak > 1.0, "the bloom must overshoot; peak was %.4f" % peak)
	assert_almost_eq(peak, 1.02, 0.005, "section 2.4 puts the overshoot at 1.02")
	assert_almost_eq(b.scale_at(b.bloom_seconds), 1.0, 0.0005,
		"and it must land on exactly 1.0, or the element stays the wrong size")

func test_it_is_fully_opaque_by_the_end_of_the_bloom() -> void:
	var b = BreathScript.surface(_tokens)
	assert_almost_eq(b.opacity_at(b.bloom_seconds), 1.0, 0.0001)

## The hold is STILL. Section 2.4 gives the pulse only to warm things, and it is
## a separate concern from the envelope -- an element that drifted during its
## own hold would read as unstable.
func test_the_hold_is_perfectly_still() -> void:
	var b = BreathScript.surface(_tokens)
	var mid: float = b.bloom_seconds + b.hold_seconds * 0.5
	assert_almost_eq(b.opacity_at(mid), 1.0, 0.0001)
	assert_almost_eq(b.scale_at(mid), 1.0, 0.0001)
	assert_almost_eq(b.offset_at(mid).length(), 0.0, 0.0001)

func test_it_ends_invisible_and_drifted_upward() -> void:
	var b = BreathScript.surface(_tokens)
	var end := b.total_seconds()
	assert_almost_eq(b.opacity_at(end), 0.0, 0.0001)
	assert_almost_eq(b.offset_at(end).y, -8.0, 0.001,
		"section 2.4 drifts 8 design px upward, like breath actually does")

## Fade-outs that brighten halfway through look like a flicker.
func test_the_exit_never_brightens() -> void:
	var b = BreathScript.surface(_tokens)
	var previous := 2.0
	var steps := 240
	for i in range(steps + 1):
		var t: float = b.bloom_seconds + b.hold_seconds + b.exit_seconds * float(i) / float(steps)
		var value := b.opacity_at(t)
		assert_true(value <= previous + 0.0001,
			"opacity rose from %.4f to %.4f during the exit" % [previous, value])
		previous = value

## Sampling outside the envelope must be defined. A driver that overshoots the
## last frame by a millisecond should get "finished", not a NaN.
func test_sampling_outside_the_envelope_is_clamped() -> void:
	var b = BreathScript.surface(_tokens)
	assert_almost_eq(b.opacity_at(-5.0), 0.0, 0.0001)
	assert_almost_eq(b.opacity_at(b.total_seconds() + 5.0), 0.0, 0.0001)
	assert_true(is_finite(b.scale_at(-5.0)))
	assert_true(is_finite(b.scale_at(b.total_seconds() + 5.0)))

func test_it_reports_when_it_is_over() -> void:
	var b = BreathScript.surface(_tokens)
	assert_false(b.is_finished(0.0))
	assert_false(b.is_finished(b.total_seconds() - 0.001))
	assert_true(b.is_finished(b.total_seconds()))
	assert_true(b.is_finished(b.total_seconds() + 1.0))

# --- variants ---------------------------------------------------------------

func test_the_heavy_bloom_is_the_slower_one() -> void:
	var light = BreathScript.surface(_tokens)
	var heavy = BreathScript.surface(_tokens, -1.0, true)
	assert_true(heavy.bloom_seconds > light.bloom_seconds)
	assert_almost_eq(heavy.bloom_seconds, _tokens.bloom_heavy_seconds, 0.0001)

## Section 5.1: leaving a place should be crisp, endings should be slow.
func test_the_exits_are_ordered_fast_normal_long() -> void:
	var fast = BreathScript.surface(_tokens, -1.0, false, BreathScript.Exit.FAST)
	var normal = BreathScript.surface(_tokens, -1.0, false, BreathScript.Exit.NORMAL)
	var long = BreathScript.surface(_tokens, -1.0, false, BreathScript.Exit.LONG)
	assert_true(fast.exit_seconds < normal.exit_seconds)
	assert_true(normal.exit_seconds < long.exit_seconds)

## Section 5.6: a cold snap adds nothing to the screen and slows everything that
## is already on it. The multiplier has to reach every phase, or the interface
## would go still in one place and not another.
func test_the_cold_snap_stretches_every_phase() -> void:
	var plain = BreathScript.surface(_tokens)
	var cold = BreathScript.surface(_tokens)
	cold.stretch(_tokens.cold_snap_scale)
	assert_almost_eq(cold.bloom_seconds, plain.bloom_seconds * 1.4, 0.0001)
	assert_almost_eq(cold.hold_seconds, plain.hold_seconds * 1.4, 0.0001)
	assert_almost_eq(cold.exit_seconds, plain.exit_seconds * 1.4, 0.0001)
	assert_almost_eq(cold.total_seconds(), plain.total_seconds() * 1.4, 0.0001)

# --- the stagger, and the wind ----------------------------------------------

## Section 5.9's inscriptions are WRITTEN, one character after another, so each
## glyph's envelope starts later than the one before it. Before its delay a
## glyph is not merely invisible -- it has not begun.
func test_a_delayed_breath_has_not_begun_before_its_delay() -> void:
	var b = BreathScript.surface(_tokens)
	b.delay = 0.5
	assert_almost_eq(b.opacity_at(0.4), 0.0, 0.0001)
	assert_almost_eq(b.opacity_at(0.5), 0.0, 0.0001)
	assert_true(b.opacity_at(0.5 + b.bloom_seconds * 0.5) > 0.0)
	assert_almost_eq(b.total_seconds(), 0.5 + b.bloom_seconds + b.hold_seconds + b.exit_seconds, 0.0001)

func test_glyphs_are_staggered_in_reading_order() -> void:
	var first = BreathScript.inscription(_tokens, 0, 8)
	var last = BreathScript.inscription(_tokens, 7, 8)
	assert_almost_eq(first.delay, 0.0, 0.0001, "the first glyph starts at once")
	assert_true(last.delay > first.delay, "later glyphs are written later")
	# Every glyph must finish, and they must finish in the order they were written.
	assert_true(last.total_seconds() > first.total_seconds())

## The exit that matters for section 5.9. A scattered glyph does not drift
## politely upward -- it is taken, along a direction, spinning.
func test_a_scattered_glyph_leaves_along_the_wind_and_turns() -> void:
	var wind := Vector2(1.0, -0.25).normalized()
	var b = BreathScript.inscription(_tokens, 0, 1)
	b.scatter(wind, 140.0, 0.9)
	var end := b.total_seconds()
	var landed := b.offset_at(end)
	assert_almost_eq(landed.length(), 140.0, 1.0, "it travels the distance it was given")
	assert_true(landed.normalized().dot(wind) > 0.98, "and it travels along the wind")
	assert_true(absf(b.rotation_at(end)) > 0.1, "and it turns on the way")

## It must sit still until the wind takes it. A glyph that crept during its hold
## would read as sliding text rather than as written text.
func test_a_scattered_glyph_does_not_move_until_the_exit() -> void:
	var b = BreathScript.inscription(_tokens, 0, 1)
	b.scatter(Vector2(1.0, 0.0), 140.0, 0.9)
	var mid: float = b.delay + b.bloom_seconds + b.hold_seconds * 0.5
	assert_almost_eq(b.offset_at(mid).length(), 0.0, 0.0001)
	assert_almost_eq(b.rotation_at(mid), 0.0, 0.0001)

## Two glyphs of the same word must not fly off identically -- that reads as a
## sliding block rather than as a word coming apart. The spread is deterministic
## per index so a replay looks the same twice.
func test_neighbouring_glyphs_scatter_differently_but_reproducibly() -> void:
	var wind := Vector2(1.0, -0.25).normalized()
	var a = BreathScript.inscription(_tokens, 3, 10)
	var b = BreathScript.inscription(_tokens, 4, 10)
	var again = BreathScript.inscription(_tokens, 3, 10)
	a.scatter(wind, 140.0, 0.9)
	b.scatter(wind, 140.0, 0.9)
	again.scatter(wind, 140.0, 0.9)
	var end_a := a.total_seconds()
	assert_true(a.offset_at(end_a).distance_to(b.offset_at(b.total_seconds())) > 1.0,
		"two glyphs must not land on the same vector")
	assert_almost_eq(a.offset_at(end_a).distance_to(again.offset_at(again.total_seconds())), 0.0, 0.0001,
		"the same glyph index must scatter the same way every time")

# --- the easing itself ------------------------------------------------------

## The two curves ARE the design (section 2.4), so the solver that evaluates
## them is worth its own assertions: a cubic-bezier ease must pin both ends and
## never run backwards.
func test_the_easing_solver_pins_both_ends_and_is_monotonic() -> void:
	for curve in [BreathScript.BLOOM_EASE, BreathScript.BLOOM_HEAVY_EASE, BreathScript.DRIFT_EASE]:
		assert_almost_eq(BreathScript.ease_with(curve, 0.0), 0.0, 0.0005)
		assert_almost_eq(BreathScript.ease_with(curve, 1.0), 1.0, 0.0005)
		var previous := -1.0
		for i in range(101):
			var x := float(i) / 100.0
			var y: float = BreathScript.ease_with(curve, x)
			assert_true(y >= previous - 0.0005,
				"ease ran backwards at x=%.2f (%.4f after %.4f)" % [x, y, previous])
			previous = y

## The bloom curve is an ease-OUT: most of the distance is covered early. That
## is what makes the arrival feel fast and the settle feel soft.
func test_the_bloom_curve_front_loads_its_travel() -> void:
	assert_true(BreathScript.ease_with(BreathScript.BLOOM_EASE, 0.25) > 0.6,
		"a quarter of the way through the bloom, most of the move is already done")

## The drift curve is an ease-IN: it lets go slowly. An element that vanished at
## a constant rate would read as being switched off.
func test_the_drift_curve_lets_go_slowly() -> void:
	assert_true(BreathScript.ease_with(BreathScript.DRIFT_EASE, 0.25) < 0.2,
		"a quarter of the way through the exit, it has barely started to go")
