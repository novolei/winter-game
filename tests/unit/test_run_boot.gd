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


# --- run seed ownership ---------------------------------------------------

## An explicit seed is the replay seam: captures, automated checks and the
## future GameState can establish it before the boot node enters the tree.
func test_an_explicit_run_seed_is_stable_for_the_whole_boot() -> void:
	var boot = _build_boot()
	boot.run_seed = 1729
	assert_eq(boot.current_run_seed(), 1729)
	assert_eq(boot.current_run_seed(), 1729, "asking for the run seed changed a replayable run")


## A normal boot owns a concrete seed even before _ready(), so a future owner
## can persist or hand it to a scene without depending on process timing.
func test_an_unset_run_seed_is_minted_once() -> void:
	var boot = _build_boot()
	var first: int = boot.current_run_seed()
	assert_true(first != 0, "a fresh boot left the run seed unset")
	assert_eq(boot.current_run_seed(), first, "a fresh boot minted a second seed")


## Unit subjects are deliberately detached.  Their lifecycle must not attempt
## an absolute /root lookup, because Godot reports that as an engine error even
## though this boot has no service registry to clean up.
func test_a_detached_boot_can_ready_and_leave_without_a_tree_lookup() -> void:
	var boot = _build_boot()
	boot.auto_start = false
	boot._ready()
	boot._exit_tree()
	assert_true(boot.current_run_seed() != 0, "detached boot did not retain its minted seed")


## The complementary live path is load-bearing: SnowField resolves this
## generic service rather than taking a direct dependency on RunBoot.
func test_a_live_boot_registers_its_seed_and_releases_it_on_exit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the test runner must provide a live SceneTree")
	if tree == null:
		return
	var registry := tree.root.get_node_or_null("ServiceRegistry")
	assert_not_null(registry, "the live ServiceRegistry autoload is required for run seed ownership")
	if registry == null:
		return
	var previous = registry.get_service(RunBootScript.RUN_SEED_SERVICE)
	var boot = _build_boot()
	boot.auto_start = false
	boot.run_seed = 1729
	tree.root.add_child(boot)
	assert_eq(registry.get_service(RunBootScript.RUN_SEED_SERVICE), boot,
		"a live boot did not expose its run seed through the generic registry")
	tree.root.remove_child(boot)
	assert_false(registry.has(RunBootScript.RUN_SEED_SERVICE),
		"a removed boot left a stale run-seed owner in the registry")
	if previous != null:
		registry.register(RunBootScript.RUN_SEED_SERVICE, previous)


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
