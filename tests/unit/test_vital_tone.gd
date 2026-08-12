extends TestCase

## The one state table every survival readout reads from -- section 5.2's
## surfacing note today, section 6.1's Tab ring next, and anything in the world
## that reacts to the man's condition after that.
##
## The design document states it twice, in 5.2 and in 6.1, and the two
## statements differ: 5.2 turns to alarm at 濒危（<0.15）, 6.1 turns at <0.25 and
## adds 颤 and 明灭 at <0.15. VitalTone holds 6.1's, which is the finer of the two
## and contains everything 5.2 says. These tests pin that choice so it cannot
## drift back into two tables.

const TOKENS_PATH := "res://data/ui/tokens.tres"

var _tokens: UITokens = null

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens

# --- the thresholds ----------------------------------------------------------

func test_a_healthy_reading_is_steady() -> void:
	assert_eq(VitalTone.state_for(1.0), VitalTone.State.STEADY)
	assert_eq(VitalTone.state_for(0.26), VitalTone.State.STEADY)

func test_alarm_begins_at_a_quarter() -> void:
	assert_eq(VitalTone.state_for(0.24), VitalTone.State.ALARM)
	assert_eq(VitalTone.state_for(0.16), VitalTone.State.ALARM)

func test_critical_begins_below_fifteen_hundredths() -> void:
	assert_eq(VitalTone.state_for(0.149), VitalTone.State.CRITICAL)
	assert_eq(VitalTone.state_for(0.01), VitalTone.State.CRITICAL)

## The floor is its own state and not the worst shade of alarm. Section 6.1:
## 已归零 -- 弧变成一段 1px 的空槽。**不是红色，是空的**.
func test_a_depleted_reading_is_empty_not_alarming() -> void:
	assert_eq(VitalTone.state_for(0.0), VitalTone.State.EMPTY)
	assert_eq(VitalTone.state_for(0.4, true), VitalTone.State.EMPTY,
		"the model saying depleted must win over the value")
func test_an_empty_reading_carries_no_texture() -> void:
	assert_almost_eq(VitalTone.texture_ratio(VitalTone.State.EMPTY), 0.0, 0.0001)
	assert_true(VitalTone.texture_ratio(VitalTone.State.CRITICAL) > 0.0)

## A RATIO and not a pixel count, because this file decides what a value means
## and a VitalPaint decides what that looks like. A length here would tie the
## meaning layer to one visual language -- which it did, and the language was
## then withdrawn.
func test_the_meaning_layer_never_names_a_length() -> void:
	assert_true(VitalTone.texture_ratio(VitalTone.State.STEADY) <= 1.0,
		"texture_ratio must be a 0..1 ratio, not a size in pixels")
func test_trouble_is_emphasised_by_weight() -> void:
	assert_true(
		VitalTone.fill_design_px(VitalTone.State.ALARM)
			> VitalTone.fill_design_px(VitalTone.State.STEADY),
		"emphasis must be available in weight, since it is forbidden in warmth")

# --- the motion --------------------------------------------------------------

## Section 2.4's 颤 is `steps(2)`, not a sine: two states, 12 Hz, one design
## pixel. A wobble is a different thing from a tremble.
func test_the_shiver_is_a_two_step_square_wave() -> void:
	var size := Vector2(1920.0, 1080.0)
	var period := 1.0 / _tokens.shiver_hertz
	var low := VitalTone.shiver_offset(_tokens, size, period * 0.25, VitalTone.State.CRITICAL)
	var high := VitalTone.shiver_offset(_tokens, size, period * 0.75, VitalTone.State.CRITICAL)
	assert_almost_eq(low.x, 0.0, 0.0001)
	assert_almost_eq(high.x, _tokens.shiver_pixels, 0.0001)
	# Two values and nothing between them: a third sample inside the same half
	# must equal its neighbour exactly.
	var also_high := VitalTone.shiver_offset(
		_tokens, size, period * 0.9, VitalTone.State.CRITICAL)
	assert_almost_eq(also_high.x, high.x, 0.0001)

## Sideways. These readings are a vertical stack, and a vertical jitter on one of
## them reads as the stack re-laying itself out rather than as a body shaking.
func test_the_shiver_never_moves_a_reading_vertically() -> void:
	var size := Vector2(1920.0, 1080.0)
	for step in range(12):
		var offset := VitalTone.shiver_offset(
			_tokens, size, float(step) * 0.017, VitalTone.State.CRITICAL)
		assert_almost_eq(offset.y, 0.0, 0.0001)

func test_only_a_critical_reading_shivers() -> void:
	var size := Vector2(1920.0, 1080.0)
	for state in [VitalTone.State.STEADY, VitalTone.State.ALARM, VitalTone.State.EMPTY]:
		assert_eq(
			VitalTone.shiver_offset(_tokens, size, 0.06, state), Vector2.ZERO,
			"state %d must be still" % state)

## Both cyclic effects start at full and dip. One that started at its trough
## would blink ON at the moment the reading turned critical, which reads as a
## flash rather than as a fire going out.
func test_the_guttering_starts_at_full_and_only_dims() -> void:
	assert_almost_eq(VitalTone.gutter(0.0, VitalTone.State.CRITICAL), 1.0, 0.0001)
	var lowest := 1.0
	for step in range(200):
		var value := VitalTone.gutter(float(step) * 0.01, VitalTone.State.CRITICAL)
		assert_true(value <= 1.0001, "the guttering must never brighten past full")
		lowest = minf(lowest, value)
	assert_almost_eq(lowest, 1.0 - VitalTone.GUTTER_AMPLITUDE, 0.01,
		"section 6.1 asks for 振幅 40%")

func test_nothing_gutters_unless_it_is_critical() -> void:
	assert_almost_eq(VitalTone.gutter(0.7, VitalTone.State.ALARM), 1.0, 0.0001)
	assert_almost_eq(VitalTone.gutter(0.7, VitalTone.State.STEADY), 1.0, 0.0001)

func test_the_breathe_matches_the_tokens_amplitude() -> void:
	assert_almost_eq(VitalTone.breathe(_tokens, 0.0), 1.0, 0.0001)
	# Half a period is the trough of a raised cosine.
	assert_almost_eq(
		VitalTone.breathe(_tokens, _tokens.breathe_seconds * 0.5),
		1.0 - _tokens.breathe_amplitude, 0.0001)
## Section 5.2's own table, restored. It briefly returned one charcoal for
## everything, under a ruling the owner made about the permanent corner readouts
## -- 整个 HUD 所有的元素都使用这个单一颜色. Those readouts were deleted, so the
## ruling has no subject left, and these tests are what stop it drifting back in.
func test_a_steady_reading_is_the_primary_ink() -> void:
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.STEADY) == _tokens.ink_primary)

## 濒危 -- 转 `alarm/blood`. Section 6.1 turns one step earlier than 5.2 and this
## file holds the finer table, so ALARM turns too.
func test_a_reading_in_trouble_turns_to_alarm_blood() -> void:
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.ALARM) == _tokens.alarm_blood)
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.CRITICAL) == _tokens.alarm_blood)

## Section 6.1: 已归零 -- 弧变成一段 1px 的空槽。**不是红色，是空的**. So the
## floor is the trough's own hairline rather than a dimmer red.
func test_an_empty_reading_is_the_trough_and_not_a_dimmer_red() -> void:
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.EMPTY)
		== VitalTone.trough_colour_for(_tokens))
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.EMPTY) != _tokens.alarm_blood)

## RULE 3. 暖色在 UI 里只有一个含义：热量的存在. A reading being urgent is not
## heat, however urgent it is, so no state may reach for a warm token.
func test_no_state_is_ever_warm() -> void:
	for state in [VitalTone.State.STEADY, VitalTone.State.ALARM,
			VitalTone.State.CRITICAL, VitalTone.State.EMPTY]:
		var colour := VitalTone.colour_for(_tokens, state)
		assert_true(colour != _tokens.life_warm and colour != _tokens.life_ember,
			"state %d reached for the colour of heat" % state)

## And the one thing that IS allowed to be warm, because heat entering the body
## is literally 热量的存在 (section 5.2).
func test_the_recovery_mark_is_the_one_legal_warm_use() -> void:
	assert_true(VitalTone.recovery_dot_colour(_tokens) == _tokens.life_warm)

## Magenta with no tokens, matching UITokens.colour()'s convention: a readout
## drawn with no design tokens loaded should be impossible to miss rather than
## plausibly grey.
func test_a_readout_with_no_tokens_is_impossible_to_miss() -> void:
	assert_true(VitalTone.colour_for(null, VitalTone.State.STEADY) == Color.MAGENTA)
	assert_true(VitalTone.recovery_dot_colour(null) == Color.MAGENTA)

## THE NIGHT LIFT IS GONE, AND THIS IS THE GUARD ON THAT.
##
## A world-brightness adaptation used to lift the mark's lightness on a dark
## frame, and a warm ramp used to drain the day dial. Both existed for ONE
## element -- the permanent corner cluster, which had to survive every hour
## because it was always there -- and both went with it. The measurements are
## kept in .superpowers/sdd/wave3/task-w3-hud-report.md section 3.
##
## Asserted rather than merely deleted, because the cost of the adaptation was
## that on `deep_night` the mark was no longer charcoal by value; anything
## reintroducing it should have to say so out loud.
func test_nothing_here_adapts_a_colour_to_the_weather() -> void:
	# Read off disk rather than asked of the class: has_method() does not see a
	# GDScript's static functions, so a version of this written the obvious way
	# would pass whether they were there or not.
	var file := FileAccess.open("res://src/ui/vital_tone.gd", FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var source := file.get_as_text()
	file.close()
	for gone in ["func adapt(", "func world_value(", "func warm_for(",
			"func heat_colour_for(", "func opacity_for(", "func with_luminance(",
			"func relative_luminance(", "CHARCOAL :="]:
		assert_false(source.contains(gone),
			"`%s` is back -- every readout is transient now and none of them needs it" % gone)
