extends TestCase

## UI design document section 5.10: the periodic time prompt. Bottom centre,
## every four hours of world time, four seconds, gone.
##
## ---------------------------------------------------------------------------
## WHAT THIS ELEMENT REPLACES, AND WHY THE TESTS LOOK DIFFERENT
## ---------------------------------------------------------------------------
## The deleted corner cluster carried a day dial: the largest thing on the
## interface, on screen at every moment of the run. Its tests were about anchors
## and overlap and legibility against six weathers, because a thing that never
## leaves has to survive everything.
##
## This one is about WHEN it exists and for how long. Rule 4 is satisfied by
## construction rather than by exemption -- 每个元素诞生时就带着自己的死期 -- so the
## interesting assertions are the cadence, the death, and the fact that it can
## answer a question about the world on the frame it is born.

const TimePromptScript := preload("res://src/ui/time_prompt.gd")
const TimeArcScript := preload("res://src/ui/time_arc.gd")
const UILayerScript := preload("res://src/ui/ui_layer.gd")
const ClockScript := preload("res://src/systems/world_clock.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _prompt: TimePrompt = null
var _layer: UILayer = null
var _clock: Node = null
var _bus: Node = null

func before_each() -> void:
	_layer = UILayerScript.new()
	_layer.build()
	_bus = EventBusScript.new()
	_clock = ClockScript.new()
	_clock.set_event_bus(_bus)
	_clock.load_schedules_from_directory()
	_clock.start()
	_prompt = TimePromptScript.new()
	_prompt.set_layer(_layer)
	_prompt.set_clock(_clock)
	_prompt.build()
	_prompt.set_event_bus(_bus)

func after_each() -> void:
	# Order matters, the same way it does for ThresholdSurfacing: the prompt owns
	# nothing the layer has already been handed, and the layer frees what it holds
	# (briefing constraint 2).
	if _prompt != null:
		_prompt.free()
		_prompt = null
	if _layer != null:
		_layer.free()
		_layer = null
	if _clock != null:
		_clock.free()
		_clock = null
	if _bus != null:
		_bus.free()
		_bus = null

## Runs the clock and the prompt together, the way the scene tree does.
func _run(seconds: float, step := 0.5) -> void:
	var left := seconds
	while left > 0.0:
		var slice := minf(step, left)
		_clock.advance(slice)
		_prompt.advance(slice)
		_layer.advance(slice)
		left -= slice

# --- the cadence -------------------------------------------------------------

## THE FOUR HOURS ARE A RELATIONSHIP, NOT A CONSTANT.
##
## An hour is a twenty-fourth of the day the schedule authored, so the prompt
## keeps step with the run's own pacing rather than with a number somebody typed
## once. Retune a day and the cadence follows it; write it as 150 seconds and it
## silently does not.
func test_four_hours_is_four_twenty_fourths_of_the_authored_day() -> void:
	var schedule = _clock.current_schedule()
	assert_not_null(schedule)
	if schedule == null:
		return
	var day_seconds: float = schedule.daylight_seconds + schedule.night_seconds
	assert_almost_eq(_prompt.hour_seconds(), day_seconds / 24.0, 0.0001,
		"an hour is not a twenty-fourth of this day")
	assert_almost_eq(_prompt.seconds_between(),
		day_seconds / 24.0 * _prompt.data().hours_between, 0.0001)

func test_it_says_nothing_before_its_first_four_hours() -> void:
	_run(_prompt.seconds_between() * 0.9)
	assert_eq(_prompt.surfaced_count(), 0,
		"the prompt arrived early, so it is not on the clock's schedule")
	assert_eq(_layer.live_count(), 0)

func test_it_arrives_on_the_fourth_hour() -> void:
	_run(_prompt.seconds_between() + 0.5)
	assert_eq(_prompt.surfaced_count(), 1)
	assert_eq(_layer.live_count(), 1, "the arc was never handed to the layer")

func test_it_comes_back_every_four_hours() -> void:
	_run(_prompt.seconds_between() * 3.0 + 0.5)
	assert_eq(_prompt.surfaced_count(), 3,
		"three lots of four hours should have produced three prompts")

## Rule 4, by construction rather than by exemption. It is born carrying its own
## death and the layer carries out the sentence.
func test_it_dies_four_seconds_later_and_the_layer_frees_it() -> void:
	_run(_prompt.seconds_between() + 0.5)
	assert_eq(_layer.live_count(), 1)
	var tokens := _layer.tokens()
	var whole := tokens.bloom_heavy_seconds + _prompt.data().hold_seconds \
		+ tokens.drift_seconds + 0.05
	_layer.advance(whole)
	assert_eq(_layer.live_count(), 0, "the prompt outlived its own breath")
	assert_true(_prompt.live() == null, "the prompt kept a reference to a freed element")

func test_the_hold_is_the_documented_four_seconds() -> void:
	assert_almost_eq(_prompt.data().hold_seconds, 4.0, 0.0001)
	assert_almost_eq(_prompt.data().hours_between, 4.0, 0.0001)

## A stopped clock is not a slow clock. Nothing should appear before the run
## begins or after it ends.
func test_a_clock_that_is_not_running_produces_nothing() -> void:
	var idle: Node = ClockScript.new()
	var prompt: TimePrompt = TimePromptScript.new()
	prompt.set_layer(_layer)
	prompt.set_clock(idle)
	prompt.build()
	prompt.advance(100000.0)
	assert_eq(prompt.surfaced_count(), 0)
	prompt.free()
	idle.free()

func test_it_survives_having_no_clock_at_all() -> void:
	var bare: TimePrompt = TimePromptScript.new()
	bare.set_layer(_layer)
	bare.build()
	bare.advance(10000.0)
	assert_eq(bare.surfaced_count(), 0, "a prompt with no clock invented a time")
	bare.free()

# --- it asks the clock, as well as listening to it ---------------------------

## ASKED ON BUILD, not only subscribed. `clock.night_started` has already fired
## by the time a scene reloads after dark, and a node that only ever hears
## transitions can never learn the state it was born into. Found three times on
## this project.
func test_a_prompt_built_after_dark_knows_it_is_dark() -> void:
	var clock: Node = ClockScript.new()
	clock.set_event_bus(null)
	clock.load_schedules_from_directory()
	clock.start()
	clock.advance(clock.phase_duration() + 1.0)
	assert_true(clock.is_night(), "the fixture has to actually reach night")

	var late: TimePrompt = TimePromptScript.new()
	late.set_layer(_layer)
	late.set_clock(clock)
	late.build()
	assert_true(late.is_night(),
		"the prompt learned nothing from a phase that changed before it existed")
	late.free()
	clock.free()

func test_nightfall_turns_the_prompt_over() -> void:
	assert_false(_prompt.is_night())
	_bus.emit_event(&"clock.night_started", 3)
	assert_true(_prompt.is_night())
	_bus.emit_event(&"clock.day_started", 4)
	assert_false(_prompt.is_night())

func test_it_lets_go_of_the_bus_when_it_is_handed_another() -> void:
	var second: Node = EventBusScript.new()
	_prompt.set_event_bus(second)
	assert_eq(_bus.subscriber_count(&"clock.night_started"), 0,
		"a prompt that never unsubscribes leaks a callback into the old bus")
	assert_eq(second.subscriber_count(&"clock.night_started"), 1)
	second.free()

## The phase and the day come off the clock at the moment of surfacing, so a
## prompt cannot be showing yesterday.
func test_the_arc_is_stamped_with_the_phase_it_was_born_in() -> void:
	# The clock is walked into the night WITHOUT the prompt, so the prompt's own
	# stopwatch starts from there and the surfacing lands somewhere the test
	# controls -- rather than on whatever coincidence the schedule's numbers
	# happen to produce between a phase length and a four-hour period.
	_clock.advance(_clock.phase_duration() + 1.0)
	assert_true(_clock.is_night(), "the fixture has to actually reach night")
	_run(_prompt.seconds_between() + 0.5)
	var arc := _prompt.live()
	assert_not_null(arc)
	if arc == null:
		return
	assert_true(arc.is_night(), "the prompt surfaced after dark and said it was day")
	assert_eq(arc.day(), _clock.current_day())

# --- what it says ------------------------------------------------------------

## His example reads 夜晚 4: the phase and the day, and both come out of data so
## neither is a string in a .gd file.
func test_it_reads_the_phase_and_the_day() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_phase(true, 4, 0.5)
	assert_eq(arc.text(), "%s 4" % _prompt.data().night_label)
	arc.set_phase(false, 2, 0.5)
	assert_eq(arc.text(), "%s 2" % _prompt.data().day_label)
	arc.free()

func test_both_faces_are_on_disk_and_neither_is_drawn_in_code() -> void:
	var data := _prompt.data()
	for glyph in [data.day_glyph, data.night_glyph]:
		assert_true(ResourceLoader.exists("res://assets/ui/icons/%s.png" % glyph),
			"%s.png is missing, and the prompt has no fallback drawing" % glyph)

# --- rule 2: the middle is the world -----------------------------------------

## 中心 85% 永远是世界. Bottom centre means inside the bottom breathing border, at
## every window shape the game runs at -- the project stretches `canvas_items` /
## `expand`, so extra screen area is revealed rather than letterboxed.
func test_it_lives_inside_the_bottom_breathing_border_at_every_shape() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_phase(true, 4, 0.5)
	var tokens := _layer.tokens()
	for canvas in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(2560, 1080),
			Vector2(3440, 1440), Vector2(1080, 1920)]:
		var size: Vector2 = arc.layout_for(canvas)
		var edge := tokens.edge_pixels(canvas)
		assert_true(size.y <= edge + 0.001,
			"at %s the prompt is %.0f px tall and the border is %.0f" % [canvas, size.y, edge])
		assert_true(arc.position.y >= canvas.y - edge - 0.001,
			"at %s the prompt reaches up to %.0f px, into the world" % [canvas, arc.position.y])
		assert_true(arc.position.y + size.y <= canvas.y + 0.001,
			"at %s the prompt hangs off the bottom of the screen" % canvas)
		var centre := arc.position.x + size.x * 0.5
		assert_almost_eq(centre, canvas.x * 0.5, 0.5,
			"at %s the prompt is not centred" % canvas)
	arc.free()

# --- the mark travels toward what is coming ----------------------------------

## The two icons are fixed -- moon at the left end, sun at the right -- so the
## DIRECTION of travel is what says which phase it is. At night the mark walks
## from the moon toward the sun: dawn is at the far end. In the day it walks the
## other way, toward the night that is coming, which is GDD section 3's whole
## deadline said without a word.
func test_at_night_the_mark_walks_from_the_moon_toward_the_sun() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	arc.set_phase(true, 4, 0.0)
	var dusk: Vector2 = arc.mark_position()
	arc.set_phase(true, 4, 1.0)
	var dawn: Vector2 = arc.mark_position()
	assert_true(dawn.x > dusk.x, "the night ran backwards")
	assert_almost_eq(dusk.x, arc.icon_centre(false).x, 1.0,
		"the night should begin at the moon")
	assert_almost_eq(dawn.x, arc.icon_centre(true).x, 1.0,
		"the night should end at the sun")
	arc.free()

func test_in_the_day_the_mark_walks_toward_the_night_that_is_coming() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	arc.set_phase(false, 4, 0.0)
	var dawn: Vector2 = arc.mark_position()
	arc.set_phase(false, 4, 1.0)
	var dusk: Vector2 = arc.mark_position()
	assert_true(dusk.x < dawn.x,
		"in the day the mark must walk toward the moon, not away from it")
	assert_almost_eq(dawn.x, arc.icon_centre(true).x, 1.0, "the day should begin at the sun")
	assert_almost_eq(dusk.x, arc.icon_centre(false).x, 1.0, "the day should end at the moon")
	arc.free()

## An arc, not a line: the mark rises and falls across it the way a body crosses
## a sky. If the sagitta were ever zero this would be a bar, and rule 1 would
## have been broken by arithmetic rather than by decision.
func test_the_mark_rides_a_real_arc() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	arc.set_phase(true, 4, 0.5)
	var apex: Vector2 = arc.mark_position()
	arc.set_phase(true, 4, 0.0)
	var start: Vector2 = arc.mark_position()
	assert_true(apex.y < start.y - 4.0,
		"the middle of the arc is level with its ends -- that is a bar, not an arc")
	assert_almost_eq(arc.span_radians(), deg_to_rad(_prompt.data().arc_degrees), 0.0001)
	arc.free()

# --- the elastic is in the motion, never in the opacity ----------------------

## MEASURED ON THIS PROJECT, and the reason this test exists: an elastic curve on
## a CLAMPED value arrives early, holds at the clamp, and then pulses back, which
## reads as a fault rather than as bounce. Breath.opacity_at() clamps for exactly
## that reason -- the heavy bloom's control point is at y = 1.2 and it measured
## 1.0044 on an alpha.
##
## So the 弹性 lives in the SCALE, which overshoots to 1.02 and settles, and in
## the exit's upward drift. The opacity only ever climbs.
func test_the_opacity_never_overshoots_and_never_goes_backwards() -> void:
	var breath := Breath.surface(_layer.tokens(), _prompt.data().hold_seconds, true)
	var last := -1.0
	var steps := 40
	for step in range(steps + 1):
		var t := breath.bloom_seconds * float(step) / float(steps)
		var alpha := breath.opacity_at(t)
		assert_true(alpha <= 1.0, "the fade in reached %.4f, which is not an opacity" % alpha)
		assert_true(alpha >= last - 0.0001,
			"the fade in went backwards at t=%.3f -- that reads as a fault" % t)
		last = alpha

func test_the_overshoot_is_in_the_scale_where_it_belongs() -> void:
	var breath := Breath.surface(_layer.tokens(), _prompt.data().hold_seconds, true)
	var peak := 0.0
	var steps := 60
	for step in range(steps + 1):
		peak = maxf(peak, breath.scale_at(breath.bloom_seconds * float(step) / float(steps)))
	# AT LEAST the authored peak, and a hair past it. The heavy curve's first
	# control point is at y = 1.2, so the ease itself crests above 1 and the lerp
	# to SCALE_PEAK crests with it -- measured 1.02100 against an authored 1.02.
	# That extra thousandth is the elasticity, and it is here rather than on the
	# opacity precisely because scale is not a clamped quantity.
	assert_true(peak >= Breath.SCALE_PEAK, "the bloom lost its overshoot (%.5f)" % peak)
	assert_almost_eq(peak, 1.021, 0.0005,
		"the overshoot moved -- it was measured at 1.02100 on the heavy bloom")
	assert_almost_eq(breath.scale_at(breath.bloom_seconds), 1.0, 0.001,
		"the overshoot has to come back to 1")

## 呵·重, because section 2.4 gives the heavy bloom to 昼夜更替 and this is the
## clock talking. It is also the curve with the larger control point, which is
## where the elasticity actually comes from.
func test_it_arrives_on_the_heavy_bloom() -> void:
	_run(_prompt.seconds_between() + 0.5)
	var arc := _prompt.live()
	assert_not_null(arc)
	if arc == null:
		return
	assert_almost_eq(_prompt.breath().bloom_seconds, _layer.tokens().bloom_heavy_seconds, 0.0001)


# --- one ink, and the ground chooses it --------------------------------------

## MEASURED, and the reason this mechanism exists at all. The first capture of
## this element had a good night frame and a day frame whose drawn segment was
## simply absent: `ink/primary` is `snow_tones[0]`, so against the snow of
## `pale_day` it measured **1.00 : 1** -- not dim, identical.
func test_on_bright_snow_the_ink_is_the_dark_one() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_ground(0.577)
	assert_true(arc.ink() == _layer.tokens().line_deep,
		"on snow at 0.577 the light ink is the colour of the snow")
	arc.free()

func test_on_a_dark_frame_the_ink_is_the_light_one() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_ground(0.148)
	assert_true(arc.ink() == _layer.tokens().ink_primary)
	arc.free()

## THE GROUND, NEVER THE PHASE, and the difference is not hypothetical. Day 6 is
## authored `nightfall -> whiteout`: its DAY is the darker of its two phases and
## its NIGHT is the brighter. An element that picked its ink from the phase would
## be wrong on exactly the day GDD section 4 calls the emotional peak.
func test_a_bright_night_still_takes_the_dark_ink() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_phase(true, 6, 0.5)
	arc.set_ground(0.501)
	assert_true(arc.ink() == _layer.tokens().line_deep,
		"a whiteout at night is still a whiteout")
	arc.free()

## The two presets the mapping was fitted to, re-measured from this element's own
## position in the frame. Refit if a preset is retuned -- the harness prints what
## it measured, which is the whole reason it does.
func test_the_ground_mapping_is_the_one_that_was_measured() -> void:
	var PresetScript := preload("res://src/definitions/lighting_preset.gd")
	var probe: LightingPreset = PresetScript.new()
	for row in [[1.5, 0.148], [3.2, 0.577]]:
		probe.ambient_energy = row[0]
		assert_almost_eq(TimeArc.ground_for(probe), row[1], 0.01,
			"ambient %.1f no longer predicts the snow that was measured" % row[0])
	assert_almost_eq(TimeArc.ground_for(null), 0.5, 0.0001,
		"no lighting at all should land in the middle, not at an extreme")

## ONE MATERIAL. The groove, the dim face and the phase word are the same ink at
## lower strength -- and only at strengths section 2.1's ladder names
## (100 / 72 / 48 / 24 / 12). A value between the rungs is a second colour by
## another route.
func test_every_strength_is_a_rung_of_the_documented_ladder() -> void:
	var steps := _layer.tokens().opacity_steps
	assert_true(steps.size() > 0, "the tokens carry no opacity ladder")
	for used in [TimeArc.OPACITY_TROUGH, TimeArc.OPACITY_DIM_FACE, TimeArc.OPACITY_WORD]:
		var found := false
		for rung in steps:
			if absf(float(rung) - used) < 0.001:
				found = true
		assert_true(found, "%.2f is not a rung of the ladder" % used)

func test_a_prompt_with_no_tokens_is_impossible_to_miss() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_false(arc.build(null, null, _prompt.data()),
		"an element with no design tokens must refuse to build rather than guess")
	assert_true(arc.ink() == Color.MAGENTA)
	arc.free()
