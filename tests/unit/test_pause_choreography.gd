extends TestCase

const ChoreographyScript := preload("res://src/ui/pause_choreography.gd")
const ExitMenuScript := preload("res://src/ui/exit_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")
const Catalog: AccessibilityCatalog = preload("res://data/ui/accessibility_settings.tres")

const IDS: Array[StringName] = [&"status", &"line", &"caption", &"a", &"b", &"c"]

func test_stagger_derives_from_the_bloom_token() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	assert_almost_eq(schedule.stagger_seconds, Tokens.bloom_seconds * 0.35)
	assert_almost_eq(schedule.line_seconds, Tokens.bloom_seconds)

func test_lines_bloom_in_order() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	var t: float = schedule.stagger_seconds * 2.5
	assert_almost_eq(schedule.alpha_at(0, t), 1.0)
	assert_almost_eq(schedule.alpha_at(1, t), 1.0, 0.03,
		"the second line should be essentially bloomed")
	var mid: float = schedule.alpha_at(2, t)
	assert_true(mid > 0.0 and mid < 1.0, "the third line should be mid-bloom, got %f" % mid)
	assert_almost_eq(schedule.alpha_at(5, t), 0.0, 0.0001, "the last line has not started")

func test_a_line_rises_into_place_as_it_blooms() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	assert_almost_eq(schedule.offset_at(0, 0.0), 8.0)
	assert_almost_eq(schedule.offset_at(0, schedule.line_seconds), 0.0)

func test_total_covers_the_last_lines_bloom() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	var expected: float = schedule.stagger_seconds * 5.0 + schedule.line_seconds
	assert_almost_eq(schedule.total_seconds(), expected)

func test_closing_is_the_exact_reverse() -> void:
	var schedule = ChoreographyScript.closing(Tokens, IDS)
	assert_eq(schedule.lines[0], &"c", "the last line leaves first")
	assert_eq(schedule.lines[5], &"status", "the status line leaves last")
	assert_almost_eq(schedule.alpha_at(0, 0.0), 1.0)
	assert_almost_eq(schedule.alpha_at(0, schedule.line_seconds), 0.0)
	assert_true(schedule.offset_at(0, schedule.line_seconds) < 0.0,
		"closing lines drift upward")

func test_a_state_swap_is_quicker_than_an_arrival() -> void:
	# Menu -> confirm/settings re-deals the same hand; it must not make the
	# player wait for the opening ceremony again.
	var opening = ChoreographyScript.opening(Tokens, IDS)
	var transition = ChoreographyScript.transition(Tokens, IDS)
	assert_true(transition.total_seconds() < opening.total_seconds() * 0.8,
		"state swap %.2fs is too close to the opening's %.2fs" % [
			transition.total_seconds(), opening.total_seconds()])
	assert_almost_eq(transition.alpha_at(0, 0.0), 0.0)
	assert_almost_eq(transition.alpha_at(5, transition.total_seconds()), 1.0, 0.0001,
		"the last line must be fully home when the swap ends")

func test_the_settings_cascade_carries_every_track_quad() -> void:
	var menu = ExitMenuScript.new()
	menu.set_quit_action(_noop)
	menu.build()
	menu.toggle()
	menu.open_settings()
	var cascade = menu._choreography
	assert_not_null(cascade, "entering the settings state should hold a cascade schedule")
	if cascade != null:
		for setting in Catalog.entries:
			var row_id := StringName("row_%s" % setting.id)
			# The marker quad shares the value word's envelope id: the word is
			# cascaded, so the marker blooms with it. Ticks carry their own ids
			# but map to their row's envelope in SpatialPauseMenu -- the 21 quads
			# riding three envelopes is what keeps the swap under half a second.
			assert_true(cascade.lines.has(StringName("%s_value" % row_id)),
				"the %s marker must bloom with its row instead of popping" % row_id)
			assert_false(cascade.lines.has(StringName("%s_tick_0" % row_id)),
				"the %s ticks must ride their row's envelope, not cascade alone" % row_id)
			var tick_id := StringName("%s_tick_0" % row_id)
			var spatial = menu._spatial
			spatial.set_line_envelope(row_id, 0.25, 3.0)
			assert_almost_eq(spatial._envelope_alpha_for(tick_id), 0.25, 0.001,
				"a tick that does not follow its row's envelope pops in first")
			spatial.set_line_envelope(row_id, 1.0, 0.0)
	menu.close()
	menu.free()

func _noop() -> void:
	pass
