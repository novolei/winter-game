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

## The regression test for briefing trap 3, the defect that cost this wave
## the most and had no test until now.
##
## _ready() resolves the bus with get_node_or_null("/root/EventBus"). Written
## the plausible-looking wrong way -- Engine.get_singleton / has_singleton --
## it returns null forever, because a project [autoload] entry is a node
## under /root and never enters the engine's singleton registry. _emit()'s
## null guard would then swallow every clock event, silently, with no
## diagnostic. Every other test in this file injects a bus via
## set_event_bus() and never puts the clock in a tree, so _ready() never runs
## and not one of them can see this.
##
## This one deliberately does NOT call set_event_bus(). It uses the real
## arrangement: the actual EventBus autoload at /root/EventBus, resolved by
## the actual _ready(), proven by an event actually arriving.
##
## Two measured facts about --script make this possible, and correct one the
## briefing gets wrong. First, project autoloads ARE instantiated under
## --script on 4.7.1: /root's children are exactly EventBus, ServiceRegistry
## and WorldClock. Second, they are nonetheless unreachable during the
## SceneTree's _initialize(), because the root Window is not in the tree yet;
## the runner therefore runs the suite from _process(), where it is. See the
## comment on test_runner.gd's _process().
func test_ready_resolves_the_autoloaded_bus_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		# Return rather than fall through. Dereferencing a null tree would
		# abort this method, and with one assertion already counted the
		# runner's zero-assertion guard would let it print PASS -- the exact
		# false-PASS shape this wave fixed in test_definitions.gd.
		return

	# Untyped on purpose: statically this is a Node, and a Node has no
	# subscribe(). Left untyped, the call dispatches dynamically.
	var bus = tree.root.get_node_or_null("EventBus")
	assert_not_null(bus, "the EventBus autoload must be present at /root/EventBus")
	if bus == null:
		return

	# NOT assigned to _bus: after_each() frees _bus, and this one is the
	# live autoload, not ours to free.
	bus.subscribe(&"clock.day_started", _record_day)

	_clock = WorldClockScript.new()
	# No set_event_bus() on purpose. Entering the tree fires _ready(), which
	# is the code path under test.
	tree.root.add_child(_clock)
	_clock.load_schedules([_make_schedule(1, 10.0, 5.0)])
	_clock.start()

	# Unwind before asserting, not after: the bus is global state shared with
	# every later test, and the clock is a Node under /root, which leaks at
	# exit if it is still there (briefing constraint 2). Assertions record and
	# continue, so putting them last costs nothing.
	bus.unsubscribe(&"clock.day_started", _record_day)
	tree.root.remove_child(_clock)

	assert_eq(_events.size(), 1, "start() must reach the bus that _ready() resolved from /root")
	if _events.is_empty():
		# The failure is already recorded above. Stop rather than index into
		# an empty array: that aborts the method with a SCRIPT ERROR, which
		# is noise on top of a failure the reader already has.
		return
	assert_eq(_events[0][0], "day", "the event that arrived should be clock.day_started")
	assert_eq(_events[0][1], 1, "payload should be day 1")

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

func test_stopping_for_death_halts_time_without_claiming_the_run_finished() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(3.0)
	var count_before: int = _events.size()
	clock.stop()
	clock.advance(1000.0)
	assert_false(clock.is_running())
	assert_false(clock.is_finished(), "death was reported as reaching eighth dawn")
	assert_almost_eq(clock.phase_elapsed(), 3.0, 0.0001)
	assert_eq(_events.size(), count_before, "a stopped clock kept publishing phase events")

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

## Nothing had ever loaded the seven .tres files that had been sitting in
## data/schedule since Wave 0, because there was no call that could: the only
## loader took an Array a caller had already built. This is that call.
func test_the_shipped_days_load_off_disk_in_order() -> void:
	_bus = EventBusScript.new()
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	assert_eq(_clock.load_schedules_from_directory(), 7, "seven days ship in res://data/schedule")
	assert_eq(_clock.schedule_count(), 7, "and all seven should be held")
	for day in range(1, 8):
		var schedule = _clock.schedule_for_day(day)
		assert_not_null(schedule, "day %d should be reachable by its number" % day)
		if schedule != null:
			assert_eq(schedule.day_number, day, "day %d is out of order" % day)

func test_asking_for_a_day_outside_the_run_yields_nothing_rather_than_an_error() -> void:
	_bus = EventBusScript.new()
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	_clock.load_schedules_from_directory()
	assert_true(_clock.schedule_for_day(0) == null, "there is no day 0")
	assert_true(_clock.schedule_for_day(8) == null, "the run is seven days long")

## THE REASON THE PREVIOUS WAVE LEFT THE CLOCK ALONE, as a test.
##
## start() on an empty clock used to emit clock.day_started for a day that does
## not exist, and the first advance() then found a zero-length phase and fired
## clock.run_finished -- which MusicDirector plays as an ending. The whole game
## over, silently, before the first frame was drawn. Refusing is not politeness;
## it is the difference between a bug and a diagnosis.
func test_a_clock_with_nothing_scheduled_refuses_to_start() -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(&"clock.day_started", _record_day)
	_bus.subscribe(&"clock.run_finished", _record_finish)
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	assert_false(_clock.start(), "an empty clock claimed to have started a run")
	assert_false(_clock.is_running(), "an empty clock started anyway")
	_clock.advance(1000.0)
	assert_eq(_events.size(), 0, "an empty clock emitted events for a run that cannot exist")
	assert_false(_clock.is_finished(), "an empty clock finished a run it never began")

func test_a_loaded_clock_reports_that_it_started() -> void:
	var clock = _build_clock()
	assert_true(clock.start(), "a clock with days on it should report that it started")
	assert_true(clock.is_running(), "and it should be running")

## GDD section 4's seven days are the shape of the whole game, and the numbers
## on the seven files add up to a fixed budget: every day is 900 seconds, the
## daylight shortens every day after the second and the night lengthens to match.
func test_the_shipped_run_is_seven_equal_days_of_shortening_daylight() -> void:
	_bus = EventBusScript.new()
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	_clock.load_schedules_from_directory()
	var previous_daylight := INF
	for day in range(1, 8):
		var schedule = _clock.schedule_for_day(day)
		if schedule == null:
			continue
		assert_almost_eq(
			schedule.daylight_seconds + schedule.night_seconds, 900.0, 0.001,
			"day %d is not 900 seconds long" % day
		)
		assert_true(
			schedule.daylight_seconds <= previous_daylight,
			"day %d has more daylight than the day before it" % day
		)
		previous_daylight = schedule.daylight_seconds
	assert_almost_eq(_clock.total_run_seconds(), 6300.0, 0.001, "seven 900-second days")

func test_shipped_schedule_matches_the_gdd() -> void:
	## [daylight, night, forced_weather_event, beacon_unlocked], from GDD section 4.
	## primary_lighting_preset and allowed_weather_events are deliberately left
	## unguarded here -- those are Wave 3's to pin down.
	##
	## DAY 1 NOW FORCES 短暂放晴, and this row was changed rather than relaxed.
	## Section 7's 编排层 is 每天的天气预算与强制节拍, and it names day 7's
	## blizzard as an example of a forced beat rather than as the only one
	## permitted. Day 1 forced nothing, which meant `plan_phase()` queued nothing,
	## which meant the first lighting change of a new game was the dusk crossfade
	## at t = 600 s -- measured 601.0 s on five seeds, with the ten samples before
	## it inside 0.57 % of each other. The owner read that as a lighting system
	## that was never wired.
	##
	## It is the FORCED column and not the allowed column because
	## `allowed_weather_events` is drawn in both phases: with 短暂放晴 in it,
	## night 1 measured running NIGHTFALL -> PALE DAY -> SUNRISE, exposure 0.780
	## climbing to 1.100 in the middle of the dark. `plan_phase()` adds the forced
	## beat only when `not night`.
	##
	## The assertion is still exact on all seven days, so a schedule that drifts
	## from what the table says still turns this red.
	var expected := {
		1: [600.0, 300.0, &"clear_break", &"farmhouse_chimney"],
		2: [600.0, 300.0, &"", &"gas_station"],
		3: [480.0, 420.0, &"", &"church_tower"],
		4: [480.0, 420.0, &"", &"logging_camp"],
		5: [420.0, 480.0, &"", &"transmission_tower"],
		6: [300.0, 600.0, &"", &""],
		7: [240.0, 660.0, &"blizzard", &""],
	}
	for day in expected.keys():
		var path := "res://data/schedule/day_%02d.tres" % day
		var schedule = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(schedule, "%s must exist" % path)
		assert_eq(schedule.day_number, day, "%s should declare day %d" % [path, day])
		assert_almost_eq(schedule.daylight_seconds, expected[day][0], 0.001, "%s daylight length" % path)
		assert_almost_eq(schedule.night_seconds, expected[day][1], 0.001, "%s night length" % path)
		assert_eq(schedule.forced_weather_event, expected[day][2], "%s forced weather event" % path)
		assert_eq(schedule.beacon_unlocked, expected[day][3], "%s beacon unlocked" % path)
