extends TestCase

const RunResultScript := preload("res://src/ui/run_result_surfacing.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _tree: SceneTree = null
var _was_paused := false
var _bus = null
var _result = null
var _restart_payload: Dictionary = {}
var _active_after_reset := false
var _reload_calls := 0
var _restart_requests := 0


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_was_paused = _tree.paused
	_tree.paused = false
	_restart_payload = {}
	_active_after_reset = false
	_reload_calls = 0
	_restart_requests = 0
	_bus = EventBusScript.new()
	_result = RunResultScript.new()
	_result.set_event_bus(_bus)
	_result.set_reload_action(_record_reload)
	_tree.root.add_child(_result)


func after_each() -> void:
	if _result != null:
		_result.free()
		_result = null
	if _bus != null:
		_bus.free()
		_bus = null
	_tree.paused = _was_paused
	_tree = null


func _record_reload() -> int:
	_reload_calls += 1
	return OK


func _record_failed_reload() -> int:
	_reload_calls += 1
	return ERR_CANT_OPEN


func _restart_the_run(payload) -> void:
	_restart_requests += 1
	_restart_payload = (payload as Dictionary).duplicate(true) if payload is Dictionary else {}
	_bus.emit_event(&"game.run_reset", {"seed": 202})
	_active_after_reset = _result.is_active()
	_bus.emit_event(&"game.run_started", {"seed": 202, "day": 1})


func test_death_stops_the_world_and_reports_only_the_day_before_retry() -> void:
	_bus.emit_event(&"game.run_ended", {
		"outcome": &"dead", "cause": &"thirst", "day": 4, "seed": 101,
	})
	assert_true(_result.is_active())
	assert_true(_result.has_visible_result())
	assert_true(_tree.paused, "death left the player and calendar controllable")
	assert_eq(_result.day_text(), "第 四 日。")
	assert_false(_result.is_restart_ready(), "retry appeared before the death line settled")
	_result.advance(RunResultScript.RESTART_READY_SECONDS)
	assert_true(_result.is_restart_ready())
	assert_eq(_result.get_child_count(), 1,
		"death added buttons or explanatory copy beside its one line")
	assert_eq(_result.find_children("*", "Label", true, false).size(), 1,
		"death added explanatory text beside the authored day line")
	assert_eq(_result.find_children("*", "Button", true, false).size(), 0,
		"death exposed a menu instead of the single terminal line")


func test_abandonment_adds_no_visible_control_or_pause() -> void:
	_bus.emit_event(&"game.run_ended", {
		"outcome": &"abandoned", "day": 7, "seed": 101,
	})
	assert_false(_result.is_active())
	assert_false(_result.has_visible_result(),
		"the ending whose UI is absence put a result on screen")
	assert_eq(_result.get_child_count(), 0,
		"abandonment created hidden Controls instead of remaining absent")
	assert_false(_tree.paused, "the invisible abandonment consumer captured the world")


func test_retry_waits_for_a_real_run_started_then_reloads_once() -> void:
	_bus.subscribe(&"game.restart_requested", _restart_the_run)
	_bus.emit_event(&"game.run_ended", {
		"outcome": &"dead", "day": 6, "seed": 101,
	})
	_result.advance(RunResultScript.RESTART_READY_SECONDS)
	_bus.emit_event(&"game.run_reset", {"seed": 202})
	assert_true(_result.is_active(), "run_reset alone exposed the settled scene")
	assert_true(_result.request_restart())
	assert_eq(_restart_payload, {"seed": 0}, "retry sent a live node or stale run state")
	assert_true(_active_after_reset, "the result closed before begin_run succeeded")
	assert_true(_result.is_reload_pending())
	assert_true(_tree.paused, "the old scene resumed before it was replaced")
	assert_true(_result.flush_reload())
	assert_eq(_reload_calls, 1)
	assert_false(_result.is_active())
	assert_false(_result.has_visible_result())
	assert_false(_tree.paused)
	assert_false(_result.flush_reload(), "one successful restart reloaded twice")


func test_reload_failure_keeps_the_terminal_pause_and_e_retries_only_the_scene() -> void:
	_bus.subscribe(&"game.restart_requested", _restart_the_run)
	_result.set_reload_action(_record_failed_reload)
	_bus.emit_event(&"game.run_ended", {
		"outcome": &"dead", "day": 3, "seed": 101,
	})
	_result.advance(RunResultScript.RESTART_READY_SECONDS)
	assert_true(_result.request_restart())
	assert_false(_result.flush_reload())
	assert_eq(_reload_calls, 1)
	assert_eq(_restart_requests, 1)
	assert_true(_result.is_active(), "reload failure exposed the settled old scene")
	assert_true(_result.has_visible_result(), "reload failure removed the only recovery surface")
	assert_true(_tree.paused, "reload failure returned control to the dead attempt")
	assert_false(_result.is_reload_pending())

	_result.set_reload_action(_record_reload)
	assert_true(_result.request_restart(), "E could not retry the failed scene replacement")
	assert_eq(_restart_requests, 1,
		"scene retry repeated the already-successful domain reset")
	assert_true(_result.flush_reload())
	assert_eq(_reload_calls, 2)
	assert_false(_result.is_active())
	assert_false(_tree.paused)
