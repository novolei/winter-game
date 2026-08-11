extends TestCase

## RunBoot's other half: the seven-day clock.
##
## The survival model's start was covered by test_survival_channels.gd when the
## fuel wave wired it. WorldClock was deliberately left alone in that wave and
## the reason was written down: a clock with no schedules loaded finishes the run
## on its first frame and fires clock.run_finished, which MusicDirector hears as
## an ending. So starting it is two things, not one -- load the seven days, THEN
## start -- and the order is the whole test.
##
## The shape of the failure these guard against is the same one that hid the
## survival model for a wave: nothing on screen says what day it is, so a clock
## that never ran and a clock that ran wrong look identical.

const RunBootScript := preload("res://src/systems/run_boot.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _boot = null
var _clock = null
var _survival = null
var _bus = null
var _events: Array = []

func before_each() -> void:
	_events = []

## All four extend Node, which is not reference counted (briefing constraint 2).
func after_each() -> void:
	if _boot != null:
		_boot.free()
		_boot = null
	if _clock != null:
		_clock.free()
		_clock = null
	if _survival != null:
		_survival.free()
		_survival = null
	if _bus != null:
		_bus.free()
		_bus = null

func _record(payload) -> void:
	_events.append(payload)

func _build_clock():
	_bus = EventBusScript.new()
	_bus.subscribe(WorldClockScript.EVENT_DAY_STARTED, _record)
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	return _clock

func _build_boot():
	_boot = RunBootScript.new()
	return _boot

# --- the clock starts ------------------------------------------------------

func test_the_boot_loads_the_seven_days_and_starts_the_clock() -> void:
	var clock = _build_clock()
	var boot = _build_boot()
	boot.set_world_clock(clock)
	assert_true(boot.begin_run(), "begin_run() reported that it started nothing")
	assert_eq(clock.schedule_count(), 7, "the seven shipped days should have been loaded")
	assert_true(clock.is_running(), "the clock was loaded and then not started")
	assert_false(clock.is_finished(), "the run finished on the frame it began")
	assert_eq(clock.current_day(), 1, "the run should begin on day 1")

## The defect the previous wave declined to risk, as a test. A clock started
## with nothing loaded finishes immediately and emits clock.run_finished, which
## MusicDirector plays as an ending -- the game over before the first frame is
## drawn, from one line in the wrong order.
func test_the_schedules_are_loaded_before_the_clock_is_started() -> void:
	var clock = _build_clock()
	var boot = _build_boot()
	boot.set_world_clock(clock)
	boot.begin_run()
	assert_eq(_events.size(), 1, "starting the run should emit exactly one clock.day_started")
	if _events.is_empty():
		return
	assert_eq(_events[0], 1, "and it should announce day 1")

func test_the_boot_does_not_restart_a_clock_that_is_already_running() -> void:
	var clock = _build_clock()
	clock.load_schedules_from_directory()
	clock.start()
	clock.advance(700.0)
	var day_before: int = clock.current_day()
	var boot = _build_boot()
	boot.set_world_clock(clock)
	assert_false(boot.begin_run(), "it restarted a run that was already going")
	assert_eq(clock.current_day(), day_before, "the run was rewound to day 1 under way")

func test_the_boot_starts_the_body_and_the_clock_together() -> void:
	var clock = _build_clock()
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	var boot = _build_boot()
	boot.set_world_clock(clock)
	boot.set_survival_system(_survival)
	assert_true(boot.begin_run(), "begin_run() reported that it started nothing")
	assert_true(_survival.is_running(), "the body was not started")
	assert_true(clock.is_running(), "the clock was not started")

## The seam GameState inherits. It must be able to land in either order without
## either half being restarted -- and a restarted SurvivalSystem is a full heal,
## while a restarted WorldClock is day 7 becoming day 1 again.
func test_a_boot_told_not_to_start_leaves_the_clock_alone() -> void:
	var clock = _build_clock()
	var boot = _build_boot()
	boot.set_world_clock(clock)
	boot.auto_start = false
	boot._ready()
	assert_false(boot.is_processing(), "auto_start is off and it armed anyway")
	assert_false(clock.is_running(), "it started the clock with auto_start off")

func test_a_boot_with_no_clock_still_starts_the_body() -> void:
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	var boot = _build_boot()
	boot.set_survival_system(_survival)
	assert_true(boot.begin_run(), "one half missing must not stop the other")
	assert_true(_survival.is_running(), "the body was not started")
