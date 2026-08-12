extends TestCase

## The one state table both survival readouts read from -- the permanent stack
## in the breathing margin and section 5.2's surfacing note.
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

func test_empty_is_not_drawn_in_the_alarm_colour() -> void:
	var empty := VitalTone.colour_for(_tokens, VitalTone.State.EMPTY)
	assert_true(empty != _tokens.alarm_blood, "不是红色，是空的")
	assert_true(empty == _tokens.line_hairline, "an emptied reading IS its trough")

## Nothing is left to freeze on a stat that has bottomed out, and it is the only
## way EMPTY is distinguishable from CRITICAL at a glance.
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

# --- rule 3 ------------------------------------------------------------------

## 暖色在 UI 里只有一个含义：热量的存在.
##
## THE TOKEN TO TEST AGAINST IS NOT "IS IT IN warm_tones". `alarm/blood` is
## `warm_tones[0]` -- section 2.1 takes it from the warm family on purpose and
## then gives it a different job: 一个是"你活着"，一个是"你在失去"，两者在色相上是同
## 族，在明度上隔了两档. So the rule forbids `life/warm` and `life/ember`, the pair
## that mean heat EXISTS, and `alarm/blood` is legal for exactly what it is
## named for -- 仅伤害与死亡 -- which is what a reading in the red is.
##
## Written the naive way this assertion fails on a correct implementation, which
## is how it was found.
func test_no_state_is_ever_drawn_in_the_colour_of_heat() -> void:
	for state in [
		VitalTone.State.STEADY, VitalTone.State.ALARM,
		VitalTone.State.CRITICAL, VitalTone.State.EMPTY,
	]:
		var colour := VitalTone.colour_for(_tokens, state)
		assert_true(colour != _tokens.life_warm,
			"state %d used life/warm, which means only that heat is present" % state)
		assert_true(colour != _tokens.life_ember,
			"state %d used life/ember, which is the same meaning one stop down" % state)

## And the alarm states use the one token section 2.1 reserves for losing
## something, rather than reaching for a cool colour and losing the distinction.
func test_trouble_is_drawn_in_the_token_reserved_for_damage() -> void:
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.ALARM) == _tokens.alarm_blood)
	assert_true(VitalTone.colour_for(_tokens, VitalTone.State.CRITICAL) == _tokens.alarm_blood)

## Every colour this table can produce still has to be one of the twelve.
func test_every_state_resolves_to_a_palette_entry() -> void:
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres") as ColorBible
	assert_not_null(palette)
	for state in [
		VitalTone.State.STEADY, VitalTone.State.ALARM,
		VitalTone.State.CRITICAL, VitalTone.State.EMPTY,
	]:
		assert_true(palette.contains(VitalTone.colour_for(_tokens, state)),
			"state %d is not one of the twelve" % state)
	assert_true(palette.contains(VitalTone.trough_colour_for(_tokens)))
	assert_true(palette.contains(VitalTone.recovery_dot_colour(_tokens)))

## The single exception the design document grants, and it is granted for a
## reason: 它表示热量正在进入身体.
func test_the_recovery_mark_is_the_one_warm_thing() -> void:
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres") as ColorBible
	assert_true(palette.is_warm(VitalTone.recovery_dot_colour(_tokens)))
	assert_true(VitalTone.recovery_dot_colour(_tokens) == _tokens.life_warm)

## Rule 3's actual instruction: 选中态、hover、强调全部用冷色的明度与笔画粗细来做.
## So a reading in trouble has to be HEAVIER, or the rule has taken emphasis away
## without giving it back.
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

# --- the material's own reading ----------------------------------------------

## Frost accumulates with the cold, which is what makes the interface a property
## of the man's situation rather than a gauge attached to it.
func test_ice_thickens_as_the_body_cools() -> void:
	var warm := VitalTone.rime_for_cold(0.0)
	var freezing := VitalTone.rime_for_cold(1.0)
	assert_true(freezing > warm, "a colder body must carry more ice")
	assert_almost_eq(freezing, 1.0, 0.0001)
	assert_true(warm > 0.0, "a well man's interface is still made of ice")

func test_cold_outside_its_range_does_not_escape() -> void:
	assert_almost_eq(VitalTone.rime_for_cold(4.0), 1.0, 0.0001)
	assert_almost_eq(VitalTone.rime_for_cold(-2.0), VitalTone.rime_for_cold(0.0), 0.0001)

## Every reading of a missing token set must be impossible to miss rather than
## plausibly grey -- the same convention UITokens.colour() follows.
func test_no_tokens_is_loud_rather_than_quiet() -> void:
	assert_eq(VitalTone.colour_for(null, VitalTone.State.STEADY), Color.MAGENTA)
	assert_eq(VitalTone.recovery_dot_colour(null), Color.MAGENTA)
