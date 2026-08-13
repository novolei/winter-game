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

## WHAT THIS TEST USED TO BE, AND WHY IT MOVED
##
## It read `assert_almost_eq(hold_seconds, 4.0)`, and it was pinning a VALUE --
## "the .tres agrees with the figure printed in section 5.10" -- not a
## requirement. The owner asked for the dwell to double, so the figure moved and
## the pin moves with it. The REQUIREMENT this element has to meet is pinned
## elsewhere and did not need touching: test_it_dies_four_seconds_later... derives
## the whole envelope from the data and asserts the element is gone at the end of
## it, which is rule 4 and is what actually matters.
##
## `hours_between` is a different animal and stays at 4: it is section 5.10's
## cadence, the owner said nothing about it, and it is a relationship the schedule
## is measured against (see test_four_hours_is_four_twenty_fourths...).
func test_the_hold_is_the_documented_eight_seconds() -> void:
	assert_almost_eq(_prompt.data().hold_seconds, 8.0, 0.0001)
	assert_almost_eq(_prompt.data().hours_between, 4.0, 0.0001)

## THE INTERFACE HAS ONE DWELL, NOT TWO -- and that is the relationship, where the
## line above is only the number.
##
## Section 5.2's note and section 5.10's prompt are the two TIMED elements in the
## breath layer: born on an event, held, and killed by a clock the player cannot
## extend. They are read the same way, by the same person, in the same margin of
## the same frame. Two different dwells would be two different reading speeds
## being asked of one reader.
##
## Written as a comparison rather than as two 8.0s so that moving one and
## forgetting the other is what turns this red -- which is the failure a pair of
## value pins cannot catch.
func test_the_two_timed_prompts_share_one_dwell() -> void:
	assert_almost_eq(_prompt.data().hold_seconds, ThresholdSurfacing.HOLD_SECONDS, 0.0001,
		"section 5.2 holds for %.2f s and section 5.10 for %.2f s; one reader, one dwell"
			% [ThresholdSurfacing.HOLD_SECONDS, _prompt.data().hold_seconds])

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

## 夜晚 Day 4: the phase, the label and the day, all three out of data so none of
## them is a string in a .gd file.
func test_it_reads_the_phase_and_the_day() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	var data := _prompt.data()
	arc.set_phase(true, 4, 0.5)
	assert_eq(arc.text(), "%s %s 4" % [data.night_label, data.day_word])
	arc.set_phase(false, 2, 0.5)
	assert_eq(arc.text(), "%s %s 2" % [data.day_label, data.day_word])
	arc.free()

## THE NUMBER IS LABELLED, and this is the owner's own ruling: 最好加上 Day
## 不需要说第几天. Shipped bare the line read 夜晚 1, and nothing in it says whether
## that 1 is the day or an index of the night.
func test_the_day_number_is_labelled() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.set_phase(true, 3, 0.5)
	assert_true(_prompt.data().day_word != "",
		"the day number went back to being a bare numeral")
	assert_true(arc.day_stamp().contains(_prompt.data().day_word),
		"the stamp reads '%s' and does not carry the label" % arc.day_stamp())
	arc.free()

## AND IT HAS NO TOTAL, deliberately. `Day 3 / 7` is a countdown, and the owner
## declined it: the seven days are endured, not counted down. This is a test that
## something must NOT appear -- the same shape as section 4.4's abandoned ending,
## and it exists because "add the denominator" is the obvious next idea and the
## reason not to is a design decision nobody will find in the code.
func test_the_day_stamp_carries_no_denominator() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	for day in range(1, 8):
		arc.set_phase(false, day, 0.5)
		var stamp := arc.day_stamp()
		for mark in ["/", "of", "共", "7"]:
			if mark == "7" and day == 7:
				continue
			assert_false(stamp.contains(mark),
				"the day stamp reads '%s' and has grown a total" % stamp)
	arc.free()

## TABULAR FIGURES, MEASURED RATHER THAN CONFIGURED.
##
## The stamp left the monospaced instrument face (see TimeArc._draw_text for the
## contrast measurement that moved it), and the one thing that face was buying is
## a numeral whose width does not change between 9 and 10 -- because this line is
## CENTRED, so a numeral that changes width walks the whole line sideways on the
## day it happens.
##
## `opentype_features` is asked for `tnum`. This project's own record is that a
## neighbouring property accepts a key, reads it back, and never applies it, so
## reading the dictionary back would prove nothing. Every digit is measured.
func test_the_day_stamp_holds_its_width_across_every_digit() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	var font: FontVariation = arc.stamp_font()
	assert_not_null(font)
	if font == null:
		return
	var px := 17
	var first := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	assert_true(first > 0.0, "the stamp face measured every digit at zero width")
	for digit in range(10):
		var width := font.get_string_size(str(digit), HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		assert_almost_eq(width, first, 0.01,
			"digit %d is %.3f px wide against %.3f for 0 -- the figures are not "
				% [digit, width, first]
				+ "tabular, so the centred line will shift when the day rolls over")
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
	assert_true(dusk.x < arc.point_at(0.5).x and dawn.x > arc.point_at(0.5).x,
		"the night should start on the moon's side and end on the sun's")
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
	assert_true(dawn.x > arc.point_at(0.5).x and dusk.x < arc.point_at(0.5).x,
		"the day should start on the sun's side and end on the moon's")
	arc.free()

# --- 散 · 边缘先化开 ----------------------------------------------------------

## THE LAST THING ON THE SNOW IS THE DOT THAT SAYS WHERE IN THE DAY YOU ARE.
##
## The dispersal order is not chosen twice: section 2.1's opacity ladder is
## already this element's statement of how much each part weighs, so a part leads
## the exit by exactly how faintly it is drawn. Pinned as the RELATIONSHIP -- a
## fainter rung leaves earlier -- so that adding a part at a new rung cannot get
## the order wrong, and re-authoring the ladder cannot silently invert it.
func test_the_faintest_ink_leaves_the_prompt_first() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	var rungs := [1.0, TimeArc.OPACITY_WORD, TimeArc.OPACITY_DIM_FACE, TimeArc.OPACITY_TROUGH]
	var previous := -1.0
	for rung in rungs:
		var lead: float = arc.lead_for(rung)
		assert_true(lead > previous,
			"the rung at %.2f leads by %.2f, no more than the brighter rung above it"
				% [rung, lead])
		previous = lead
	assert_almost_eq(arc.lead_for(1.0), 0.0, 0.0001,
		"what is drawn at full strength IS the element and must leave with it")
	arc.free()

## And the order reaches the pixels: driven through a real exit, the groove is
## gone while the mark is still there.
func test_the_prompt_comes_apart_in_that_order_on_the_way_out() -> void:
	_run(_prompt.seconds_between() + 0.5)
	var arc := _prompt.live()
	assert_not_null(arc)
	if arc == null:
		return
	var breath: Breath = _prompt.breath()
	assert_not_null(breath)
	if breath == null:
		return
	# Two thirds of the way through the exit.
	var t: float = breath.exit_begins() + breath.exit_seconds * 0.66
	var groove: float = breath.dispersal_at(t, arc.lead_for(TimeArc.OPACITY_TROUGH))
	var mark: float = breath.dispersal_at(t, arc.lead_for(1.0))
	assert_true(groove < mark,
		"two thirds through the exit the groove has %.3f left and the mark %.3f -- "
			% [groove, mark] + "the element is leaving as one rigid picture")
	assert_almost_eq(mark, 1.0, 0.0001)

# --- the mark has somewhere to stand at both ends ----------------------------

## THESE TWO TESTS USED TO ASSERT THE DEFECT.
##
## They read `assert_almost_eq(dusk.x, arc.icon_centre(false).x, 1.0)` -- the mark
## reaches the moon's centre at the start of a night. It did, and that was the
## bug: the mark is 3 design pixels of radius and the glyph is 20 across, in the
## same ink, drawn after it. The mark was UNDERNEATH the moon, so at the start of
## every phase the element showed no "now" at all, and the travelled segment has
## zero length there by definition. Photographed on `pale_day` snow at 1% into a
## night: a uniform hairline between two blobs.
##
## So the assertion above was a VALUE that happened to be true, describing a
## picture nobody had looked at. What replaces it is the requirement: wherever the
## mark is, it can be seen.
func test_the_mark_never_hides_under_a_terminal() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	var data := _prompt.data()
	# Half a glyph plus half the mark: below this the two overlap on screen.
	var touching := (data.icon_design_px + TimeArc.MARK_DESIGN_PX * 2.0) * 0.5
	for phase in [true, false]:
		for progress in [0.0, 0.001, 0.5, 0.999, 1.0]:
			arc.set_phase(phase, 4, progress)
			var mark: Vector2 = arc.mark_position()
			for sun in [true, false]:
				var gap := mark.distance_to(arc.icon_centre(sun))
				assert_true(gap >= touching,
					"at %s progress %.3f the mark is %.2f px from the %s, and they "
						% ["night" if phase else "day", progress, gap,
							"sun" if sun else "moon"]
						+ "overlap below %.2f px" % touching)
	arc.free()

## The clearance is a RELATIONSHIP -- half a glyph plus half a grid unit -- so
## redrawing the icons bigger moves the track back rather than burying the mark
## again. Pinned against the data's own numbers, never against 14.
func test_the_track_is_held_back_by_half_a_glyph_and_half_a_gap() -> void:
	var arc: TimeArc = TimeArcScript.new()
	assert_true(arc.build(_layer.tokens(), _layer.fonts(), _prompt.data()))
	arc.layout_for(Vector2(1920, 1080))
	var data := _prompt.data()
	assert_almost_eq(arc.track_clearance_design_px(),
		data.icon_design_px * 0.5 + data.gap_design_px * 0.5, 0.0001)
	# And it is a real inset, not a rounding artefact that happens to be positive.
	assert_true(arc.track_inset() > 0.02,
		"the track is inset by %.4f of the arc, which is not a gap anybody can see"
			% arc.track_inset())
	assert_true(arc.track_inset() < 0.25,
		"the track has been inset by %.4f of the arc -- the mark has nowhere to go"
			% arc.track_inset())
	# The terminals stay pinned to the arc's true ends. The inset moved the TRACK,
	# not the labels.
	assert_almost_eq(arc.icon_centre(false).x, arc.point_at(0.0).x, 0.0001)
	assert_almost_eq(arc.icon_centre(true).x, arc.point_at(1.0).x, 0.0001)
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
