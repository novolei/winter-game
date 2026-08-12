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
func test_the_world_value_matches_what_was_measured() -> void:
	var PresetScript := preload("res://src/definitions/lighting_preset.gd")
	var probe: LightingPreset = PresetScript.new()
	for row in [[1.5, 0.093], [2.9, 0.474], [3.2, 0.526]]:
		probe.ambient_energy = row[0]
		assert_almost_eq(VitalTone.world_value(probe), row[1], 0.03,
			"ambient %.1f no longer predicts the ground that was measured" % row[0])

func test_no_lighting_at_all_lands_in_the_middle() -> void:
	assert_almost_eq(VitalTone.world_value(null), 0.5, 0.0001)


# --- one colour, and only its opacity moves -----------------------------------

## 整个 HUD 所有的元素都使用这个单一颜色. Every state, every reading, one colour --
## the state is said in form and weight instead, which is what rule 3 left
## available and what the emphasis design already ran on.
func test_every_state_is_the_same_colour() -> void:
	for state in [VitalTone.State.STEADY, VitalTone.State.ALARM,
			VitalTone.State.CRITICAL, VitalTone.State.EMPTY]:
		assert_true(VitalTone.colour_for(_tokens, state) == VitalTone.CHARCOAL,
			"state %d reached for a second colour" % state)
		assert_true(VitalTone.colour_for(_tokens, state, true) == VitalTone.CHARCOAL,
			"the heat reading reached for a second colour in state %d" % state)

## The interface and the occluder fade are the same substance -- the game
## stepping politely out of the player's way -- so they are the same value, and
## a silent edit to either shows up here.
func test_the_interface_is_the_colour_of_the_occluder_fade() -> void:
	var fade := ResourceLoader.load("res://data/rendering/occluder_fade.tres")
	assert_not_null(fade)
	if fade == null:
		return
	var tint: Color = fade.tint
	assert_almost_eq(VitalTone.CHARCOAL.r, tint.r, 0.004)
	assert_almost_eq(VitalTone.CHARCOAL.g, tint.g, 0.004)
	assert_almost_eq(VitalTone.CHARCOAL.b, tint.b, 0.004)

## Charcoal on deep_night is dark on dark. The opacity is the only thing that
## moves, and it lifts as the world darkens -- the minimum required for ONE
## colour to survive all six presets.
func test_the_mark_strengthens_as_the_world_darkens() -> void:
	var on_night := VitalTone.adapt(VitalTone.CHARCOAL, 0.09).a
	var on_whiteout := VitalTone.adapt(VitalTone.CHARCOAL, 0.52).a
	assert_true(on_night > on_whiteout,
		"a dark frame needs a stronger mark, not a weaker one")
	assert_true(on_whiteout >= VitalTone.OPACITY_FLOOR - 0.001)
	assert_true(on_night <= VitalTone.OPACITY_CEILING + 0.001)

## Hue never moves at all now: there is only one.
func test_the_colour_itself_never_changes() -> void:
	for ground in [0.0, 0.2, 0.475, 0.52, 0.9]:
		var mark := VitalTone.adapt(VitalTone.CHARCOAL, ground)
		assert_almost_eq(mark.r, VitalTone.CHARCOAL.r, 0.0001)
		assert_almost_eq(mark.g, VitalTone.CHARCOAL.g, 0.0001)
		assert_almost_eq(mark.b, VitalTone.CHARCOAL.b, 0.0001)

## The director hands out a BLENDED preset while a crossfade runs, so the
## interface has to be a continuous function of it or there is a pop.
func test_the_opacity_moves_continuously_through_a_crossfade() -> void:
	var PresetScript := preload("res://src/definitions/lighting_preset.gd")
	var blend: LightingPreset = PresetScript.new()
	var last := -1.0
	for step in range(21):
		blend.ambient_energy = lerpf(1.5, 3.2, float(step) / 20.0)
		var alpha := VitalTone.adapt(VitalTone.CHARCOAL, VitalTone.world_value(blend)).a
		if last >= 0.0:
			assert_true(absf(alpha - last) < 0.06,
				"the mark jumped %.3f in a twentieth of a crossfade -- that is a pop"
					% absf(alpha - last))
		last = alpha

## The one warm element, and it DRAINS. Warm means heat and sunlight is heat, so
## the dial is warm while the sun is up and goes out as the light does.
func test_the_day_dial_loses_its_warmth_as_the_light_goes() -> void:
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres") as ColorBible
	assert_not_null(palette)
	if palette == null:
		return
	assert_true(palette.is_warm(Color(VitalTone.warm_for(_tokens, 1.0), 1.0)),
		"full daylight has to read as heat present")
	var noon := VitalTone.relative_luminance(VitalTone.warm_for(_tokens, 1.0))
	var dusk := VitalTone.relative_luminance(VitalTone.warm_for(_tokens, 0.5))
	var night := VitalTone.relative_luminance(VitalTone.warm_for(_tokens, 0.0))
	assert_true(noon > dusk and dusk > night,
		"the dial has to fall in value as the day runs down (%.3f %.3f %.3f)"
			% [noon, dusk, night])

## It goes OUT rather than turning cool. A warm gauge that went blue at dusk
## would be saying the fire had gone out for a different reason.
func test_the_dial_never_turns_cool_while_it_still_has_warmth() -> void:
	for world in [1.0, 0.9, 0.8, 0.7]:
		var colour := VitalTone.warm_for(_tokens, world)
		assert_true(colour.r >= colour.b,
			"at world %.2f the dial had more blue than red in it" % world)

## And it ends at the interface's own colour, so night is one HUD again.
func test_at_nightfall_the_dial_is_the_same_colour_as_everything_else() -> void:
	var night := VitalTone.warm_for(_tokens, 0.0)
	assert_almost_eq(night.r, VitalTone.CHARCOAL.r, 0.004)
	assert_almost_eq(night.g, VitalTone.CHARCOAL.g, 0.004)
	assert_almost_eq(night.b, VitalTone.CHARCOAL.b, 0.004)

## Two behaviours on ONE input, not two mechanisms: the warmth and the charcoal's
## strength both come from the same blended preset, so both inherit the
## director's crossfade and neither can pop while the other slides.
func test_the_warmth_moves_continuously_through_a_crossfade() -> void:
	var PresetScript := preload("res://src/definitions/lighting_preset.gd")
	var blend: LightingPreset = PresetScript.new()
	var last := -1.0
	for step in range(21):
		blend.ambient_energy = lerpf(1.5, 3.2, float(step) / 20.0)
		var lit := VitalTone.relative_luminance(
			VitalTone.warm_for(_tokens, VitalTone.world_value(blend)))
		if last >= 0.0:
			assert_true(absf(lit - last) < 0.09,
				"the dial jumped %.3f in a twentieth of a crossfade" % absf(lit - last))
		last = lit
