extends TestCase

const ChoreographyScript := preload("res://src/ui/pause_choreography.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

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
