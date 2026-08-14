extends TestCase

const GAME_STATE_PATH := "res://src/systems/game_state.gd"
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const BeaconNetworkScript := preload("res://src/systems/beacon_network.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

const EVENT_RUN_ENDED := &"game.run_ended"
const OUTCOME_RESCUED := &"rescued"
const OUTCOME_ABANDONED := &"abandoned"
const OUTCOME_DEAD := &"dead"


class FakeSurvival extends RefCounted:
	var running := false
	var start_count := 0
	var stop_count := 0

	func start() -> void:
		running = true
		start_count += 1

	func stop() -> void:
		running = false
		stop_count += 1

	func is_running() -> bool:
		return running


class FakeClock extends RefCounted:
	var running := false
	var finished := false
	var schedules := 0
	var calls: Array[StringName] = []

	func schedule_count() -> int:
		return schedules

	func load_schedules_from_directory() -> int:
		calls.append(&"load")
		schedules = 7
		return schedules

	func start() -> bool:
		calls.append(&"start")
		if schedules == 0:
			return false
		running = true
		finished = false
		return true

	func stop() -> void:
		calls.append(&"stop")
		running = false

	func is_running() -> bool:
		return running

	func is_finished() -> bool:
		return finished

	func current_day() -> int:
		return 1


var _game = null
var _clock = null
var _network = null
var _bus = null
var _events: Array = []


func before_each() -> void:
	_events = []


func after_each() -> void:
	if _game != null:
		_game.free()
		_game = null
	if _clock != null:
		_clock.free()
		_clock = null
	if _network != null:
		_network.free()
		_network = null
	if _bus != null:
		_bus.free()
		_bus = null


func _new_game():
	var script := load(GAME_STATE_PATH)
	assert_not_null(script, "the seven-day run still has no GameState owner")
	if script == null:
		return null
	_game = script.new()
	return _game


func _record(payload) -> void:
	_events.append(payload)


func test_a_run_starts_the_body_and_loaded_clock_as_one_transition() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival := FakeSurvival.new()
	var clock := FakeClock.new()
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	game.run_seed = 1729
	assert_true(game.begin_run())
	assert_true(survival.running, "the calendar started without the player's body")
	assert_true(clock.running, "the body started on a calendar that stayed still")
	assert_eq(clock.calls, [&"load", &"start"], "the clock started before its seven schedules loaded")
	assert_eq(game.current_run_seed(), 1729)


func test_an_explicit_seed_is_stable_for_the_whole_attempt() -> void:
	var game = _new_game()
	if game == null:
		return
	game.run_seed = 1729
	assert_eq(game.current_run_seed(), 1729)
	assert_eq(game.current_run_seed(), 1729, "asking for the replay seed changed the attempt")


func test_an_unset_seed_is_minted_once() -> void:
	var game = _new_game()
	if game == null:
		return
	var first: int = game.current_run_seed()
	assert_true(first != 0)
	assert_eq(game.current_run_seed(), first, "the attempt minted a second seed")


func test_a_detached_game_state_can_ready_and_leave_without_root_lookups() -> void:
	var game = _new_game()
	if game == null:
		return
	game.auto_start = false
	game._ready()
	game._exit_tree()
	assert_true(game.current_run_seed() != 0)
	assert_false(game.is_processing())


func test_a_live_game_state_owns_the_generic_run_services() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree)
	if tree == null:
		return
	var registry = tree.root.get_node_or_null("ServiceRegistry")
	assert_not_null(registry)
	if registry == null:
		return
	var previous_game = registry.get_service(&"game_state")
	var previous_seed = registry.get_service(&"run_seed")
	var game = _new_game()
	if game == null:
		return
	game.auto_start = false
	game.run_seed = 1729
	tree.root.add_child(game)
	assert_eq(registry.get_service(&"game_state"), game)
	assert_eq(registry.get_service(&"run_seed"), game)
	tree.root.remove_child(game)
	assert_false(registry.has(&"game_state"), "a removed run owner stayed registered")
	assert_false(registry.has(&"run_seed"), "a removed seed owner stayed registered")
	if previous_game != null:
		registry.register(&"game_state", previous_game)
	if previous_seed != null:
		registry.register(&"run_seed", previous_seed)


func test_begin_run_cannot_heal_or_rewind_an_attempt_already_under_way() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival := FakeSurvival.new()
	var clock := FakeClock.new()
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	assert_true(game.begin_run())
	assert_false(game.begin_run(), "a second begin rewound the running attempt")
	assert_eq(survival.start_count, 1, "a second begin fully healed the body")
	assert_eq(clock.calls.count(&"start"), 1, "a second begin rewound the calendar")


func test_begin_run_starts_the_shipped_survival_model() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival = SurvivalSystemScript.new()
	survival.load_from_directory()
	var clock := FakeClock.new()
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	assert_true(game.begin_run())
	assert_true(survival.is_running(), "the real survival body stayed inert in play")
	survival.free()


func test_a_second_begin_does_not_heal_the_real_body() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival = SurvivalSystemScript.new()
	survival.load_from_directory()
	var clock := FakeClock.new()
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	assert_true(game.begin_run())
	survival.advance(600.0)
	var half_day: float = survival.value_of(&"core_temperature")
	assert_true(half_day < 1.0)
	assert_false(game.begin_run())
	assert_almost_eq(survival.value_of(&"core_temperature"), half_day, 0.0001)
	survival.free()


func test_auto_start_fires_on_the_first_frame_and_disarms() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival := FakeSurvival.new()
	var clock := FakeClock.new()
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	game._ready()
	assert_true(game.is_processing(), "auto start did not arm")
	game._process(0.0)
	assert_true(game.is_running(), "the first frame did not begin the attempt")
	assert_false(game.is_processing(), "the run owner kept polling after startup")


func test_missing_run_half_is_refused_without_partially_starting_the_other() -> void:
	var game = _new_game()
	if game == null:
		return
	var survival := FakeSurvival.new()
	game.set_survival_system(survival)
	assert_false(game.begin_run(), "a run with no calendar claimed to begin")
	assert_false(survival.running, "the player began freezing in a run with no calendar")


func test_survival_death_stops_the_calendar_and_publishes_one_terminal_result() -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(EVENT_RUN_ENDED, _record)
	var game = _new_game()
	if game == null:
		return
	var survival := FakeSurvival.new()
	var clock := FakeClock.new()
	game.set_event_bus(_bus)
	game.set_survival_system(survival)
	game.set_world_clock(clock)
	assert_true(game.begin_run())
	_bus.emit_event(&"survival.died", {"stat": &"core_temperature"})
	_bus.emit_event(&"survival.died", {"stat": &"hunger"})
	assert_false(clock.running, "death left the seven-day clock advancing")
	assert_false(survival.running, "death left the survival model ticking")
	assert_eq(game.outcome(), OUTCOME_DEAD)
	assert_eq(_events.size(), 1, "one death settled the run more than once")
	if not _events.is_empty():
		assert_eq(_events[0].get("outcome"), OUTCOME_DEAD)
		assert_eq(_events[0].get("cause"), &"core_temperature")


func test_all_five_lit_at_final_state_is_rescue() -> void:
	_bus = EventBusScript.new()
	var game = _new_game()
	if game == null:
		return
	game.set_event_bus(_bus)
	game.set_survival_system(FakeSurvival.new())
	game.set_world_clock(FakeClock.new())
	assert_true(game.begin_run())
	_bus.emit_event(&"beacons.final_state", {"lit": 5, "total": 5, "all_lit": true})
	assert_eq(game.outcome(), OUTCOME_RESCUED)


func test_any_dark_beacon_at_final_state_is_abandonment_not_death() -> void:
	_bus = EventBusScript.new()
	var game = _new_game()
	if game == null:
		return
	game.set_event_bus(_bus)
	game.set_survival_system(FakeSurvival.new())
	game.set_world_clock(FakeClock.new())
	assert_true(game.begin_run())
	_bus.emit_event(&"beacons.final_state", {"lit": 4, "total": 5, "all_lit": false})
	assert_eq(game.outcome(), OUTCOME_ABANDONED)
	assert_false(game.outcome() == OUTCOME_DEAD, "being unseen was collapsed into dying")


func test_the_shipped_seven_days_can_reach_the_rescue_exit_deterministically() -> void:
	_bus = EventBusScript.new()
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	_network = BeaconNetworkScript.new()
	_network.set_event_bus(_bus)
	_network.load_from_directory()
	_network.spawn_missing()
	var game = _new_game()
	if game == null:
		return
	game.set_event_bus(_bus)
	game.set_survival_system(FakeSurvival.new())
	game.set_world_clock(_clock)
	game.run_seed = 1729
	assert_true(game.begin_run())
	_clock.advance(3600.0)
	assert_eq(_clock.current_day(), 5)
	for lamp in _network.beacons():
		lamp.add_fuel_seconds(2701.0)
		assert_true(lamp.light(), "an unlocked day-five beacon refused the deterministic route")
	_clock.advance(2700.0)
	assert_true(_clock.is_finished())
	assert_eq(game.outcome(), OUTCOME_RESCUED)


func test_project_replaces_temporary_run_boot_with_game_state() -> void:
	var source := FileAccess.get_file_as_string("res://project.godot")
	assert_true(source.contains("GameState=\"*res://src/systems/game_state.gd\""))
	assert_false(source.contains("RunBoot="), "the temporary run owner still starts beside GameState")
