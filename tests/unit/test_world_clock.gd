extends TestCase

const WorldClockScript := preload("res://src/systems/world_clock.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const DayScheduleScript := preload("res://src/definitions/day_schedule.gd")

var _events: Array = []

## WorldClock and EventBus both extend Node, which is not reference-counted.
## Both are freed in after_each(), or the suite reports leaked ObjectDB
## instances and the output stops being pristine.
var _clock = null
var _bus = null

func before_each() -> void:
	_events = []

func after_each() -> void:
	if _clock != null:
		_clock.free()
		_clock = null
	if _bus != null:
		_bus.free()
		_bus = null

func _record_day(payload) -> void:
	_events.append(["day", payload])

func _record_night(payload) -> void:
	_events.append(["night", payload])

func _record_finish(_payload) -> void:
	_events.append(["finish", null])

func _make_schedule(day: int, daylight: float, night: float):
	var schedule = DayScheduleScript.new()
	schedule.day_number = day
	schedule.daylight_seconds = daylight
	schedule.night_seconds = night
	return schedule

func _build_clock(day_count := 2):
	_bus = EventBusScript.new()
	_bus.subscribe(&"clock.day_started", _record_day)
	_bus.subscribe(&"clock.night_started", _record_night)
	_bus.subscribe(&"clock.run_finished", _record_finish)
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	var schedules := []
	for day in range(1, day_count + 1):
		schedules.append(_make_schedule(day, 10.0, 5.0))
	_clock.load_schedules(schedules)
	return _clock

func test_starts_on_day_one_in_daylight() -> void:
	var clock = _build_clock()
	clock.start()
	assert_eq(clock.current_day(), 1, "the run starts on day 1")
	assert_false(clock.is_night(), "the run starts in daylight")

func test_start_emits_day_started() -> void:
	var clock = _build_clock()
	clock.start()
	assert_eq(_events.size(), 1, "start should emit exactly one event")
	assert_eq(_events[0][0], "day", "that event should be clock.day_started")
	assert_eq(_events[0][1], 1, "payload should be day 1")

func test_night_begins_after_daylight_elapses() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(9.0)
	assert_false(clock.is_night(), "still daylight at 9 of 10 seconds")
	clock.advance(2.0)
	assert_true(clock.is_night(), "night should have begun after 10 seconds of daylight")

func test_night_start_emits_an_event() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(11.0)
	assert_eq(_events.size(), 2, "expect day_started then night_started")
	assert_eq(_events[1][0], "night", "second event should be clock.night_started")

func test_next_day_begins_after_night_elapses() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(10.0)
	clock.advance(5.0)
	assert_eq(clock.current_day(), 2, "day should roll over after daylight + night")
	assert_false(clock.is_night(), "the new day starts in daylight")

func test_run_finishes_after_the_last_day() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(15.0)
	clock.advance(15.0)
	assert_true(clock.is_finished(), "the run ends at dawn after the final scheduled day")

func test_run_finish_emits_an_event() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(15.0)
	clock.advance(15.0)
	var saw_finish := false
	for event in _events:
		if event[0] == "finish":
			saw_finish = true
	assert_true(saw_finish, "clock.run_finished should fire at the end of the run")

func test_advancing_after_finish_is_inert() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(100.0)
	var count_before: int = _events.size()
	clock.advance(100.0)
	assert_eq(_events.size(), count_before, "a finished clock must stop emitting")

func test_a_single_large_delta_can_cross_several_phases() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(16.0)
	assert_eq(clock.current_day(), 2, "a 16s step past a 15s day should land on day 2")
	assert_false(clock.is_night(), "and 1s into its daylight")
	assert_almost_eq(clock.phase_elapsed(), 1.0, 0.0001, "the remainder should carry into the new phase")

func test_phase_duration_reports_the_active_phase() -> void:
	var clock = _build_clock()
	clock.start()
	assert_almost_eq(clock.phase_duration(), 10.0, 0.0001, "daylight phase is 10 seconds")
	clock.advance(11.0)
	assert_almost_eq(clock.phase_duration(), 5.0, 0.0001, "night phase is 5 seconds")

func test_shipped_schedule_matches_the_gdd() -> void:
	var expected := {
		1: [600.0, 300.0], 2: [600.0, 300.0], 3: [480.0, 420.0],
		4: [480.0, 420.0], 5: [420.0, 480.0], 6: [300.0, 600.0],
		7: [240.0, 660.0],
	}
	for day in expected.keys():
		var path := "res://data/schedule/day_%02d.tres" % day
		var schedule = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(schedule, "%s must exist" % path)
		assert_eq(schedule.day_number, day, "%s should declare day %d" % [path, day])
		assert_almost_eq(schedule.daylight_seconds, expected[day][0], 0.001, "%s daylight length" % path)
		assert_almost_eq(schedule.night_seconds, expected[day][1], 0.001, "%s night length" % path)
