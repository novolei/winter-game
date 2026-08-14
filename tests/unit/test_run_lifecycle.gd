extends TestCase

const RunLifecycleScript := preload("res://src/systems/run_lifecycle.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const EVENT_RUN_START_REQUESTED := &"game.run_start_requested"

var _lifecycle = null
var _bus = null
var _events: Array = []


func before_each() -> void:
	_events = []


func after_each() -> void:
	if _lifecycle != null:
		_lifecycle.free()
		_lifecycle = null
	if _bus != null:
		_bus.free()
		_bus = null


func _record(payload) -> void:
	_events.append(payload)


func test_the_world_waits_one_active_frame_then_requests_exactly_one_value_run() -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(EVENT_RUN_START_REQUESTED, _record)
	_lifecycle = RunLifecycleScript.new()
	_lifecycle.start_seed = 1729
	_lifecycle.set_event_bus(_bus)
	_lifecycle._ready()
	_lifecycle._process(0.0)
	assert_true(_events.is_empty(), "the lifecycle skipped the sibling-attachment frame")
	assert_eq(_lifecycle.active_frames(), 1)
	_lifecycle._process(0.0)
	_lifecycle._process(0.0)
	assert_eq(_events.size(), 1, "the lifecycle requested the first attempt more than once")
	if not _events.is_empty():
		assert_eq(_events[0], {"seed": 1729})
		for value in (_events[0] as Dictionary).values():
			assert_false(value is Object, "the start request leaked a live scene object")
	assert_true(_lifecycle.has_requested())
	assert_false(_lifecycle.is_processing(), "a completed lifecycle kept polling")


func test_main_places_the_lifecycle_before_delayed_systems() -> void:
	var main := MAIN_SCENE.instantiate()
	assert_not_null(main)
	if main == null:
		return
	var lifecycle := main.get_node_or_null("RunLifecycle")
	var weather := main.get_node_or_null("Weather")
	assert_not_null(lifecycle, "Main lost its production start boundary")
	assert_not_null(weather, "Main lost the system whose delayed attach needs the barrier")
	if lifecycle != null and weather != null:
		assert_true(lifecycle.get_index() < weather.get_index(), "the lifecycle is no longer an explicit Main boundary")
	main.free()
