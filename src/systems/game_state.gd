extends Node

## Owns one complete seven-day attempt.
##
## The clock, body and five visible beacon lights already knew how to run, but
## nothing owned their shared lifecycle.  This node is that missing boundary:
## it begins the body and calendar atomically, records one replay seed, and
## settles exactly once when the body dies or the beacon network reports the
## eighth-dawn state.  Ending presentation is deliberately outside this file;
## consumers subscribe to the value-only `game.run_ended` event.

const SERVICE := &"game_state"
const RUN_SEED_SERVICE := &"run_seed"

const EVENT_RUN_STARTED := &"game.run_started"
const EVENT_RUN_ENDED := &"game.run_ended"
const EVENT_SURVIVAL_DIED := &"survival.died"
const EVENT_BEACONS_FINAL_STATE := &"beacons.final_state"

const STATE_IDLE := &"idle"
const STATE_RUNNING := &"running"
const STATE_ENDED := &"ended"

const OUTCOME_RESCUED := &"rescued"
const OUTCOME_ABANDONED := &"abandoned"
const OUTCOME_DEAD := &"dead"

@export var auto_start := true
@export var run_seed := 0

var _state: StringName = STATE_IDLE
var _outcome: StringName = &""
var _survival = null
var _clock = null
var _bus = null
var _registry = null
var _subscribed := false


func _ready() -> void:
	_resolve()
	_ensure_run_seed()
	_register_services()
	_subscribe()
	set_process(auto_start)


func _exit_tree() -> void:
	_unsubscribe()
	if _registry == null or not is_instance_valid(_registry):
		return
	if _registry.get_service(SERVICE) == self:
		_registry.unregister(SERVICE)
	if _registry.get_service(RUN_SEED_SERVICE) == self:
		_registry.unregister(RUN_SEED_SERVICE)


func _process(_delta: float) -> void:
	set_process(false)
	begin_run()


func set_event_bus(bus) -> void:
	_unsubscribe()
	_bus = bus
	_subscribe()


func set_survival_system(system) -> void:
	_survival = system


func set_world_clock(clock) -> void:
	_clock = clock


func current_run_seed() -> int:
	_ensure_run_seed()
	return run_seed


func state() -> StringName:
	return _state


func outcome() -> StringName:
	return _outcome


func is_running() -> bool:
	return _state == STATE_RUNNING


## Starts the player body and the seven-day calendar as one transition.
##
## A missing half refuses before touching the other.  This is stricter than the
## temporary RunBoot bridge: once a real owner exists, a player freezing in a
## calendar that never moves is not a useful partial success.  Restart is also
## intentionally refused after an ending until the next slice can reset fuel,
## route pickups and beacon tanks together rather than only healing the body.
func begin_run(seed := 0) -> bool:
	if _state != STATE_IDLE:
		return false
	_resolve()
	if _survival == null or _clock == null:
		return false
	if _survival.is_running() or _clock.is_running():
		return false
	if _clock.schedule_count() == 0:
		_clock.load_schedules_from_directory()
	if _clock.schedule_count() == 0:
		return false
	if seed != 0:
		run_seed = seed
	_ensure_run_seed()
	_survival.start()
	if not _clock.start():
		_survival.stop()
		return false
	_state = STATE_RUNNING
	_outcome = &""
	_emit(EVENT_RUN_STARTED, {
		"seed": run_seed,
		"day": _clock.current_day(),
	})
	return true


func _on_survival_died(payload) -> void:
	if _state != STATE_RUNNING:
		return
	var cause := &"unknown"
	if payload is Dictionary:
		cause = StringName(payload.get("stat", &"unknown"))
	_finish(OUTCOME_DEAD, {"cause": cause})


func _on_beacons_final_state(payload) -> void:
	if _state != STATE_RUNNING or not (payload is Dictionary):
		return
	var final_state := (payload as Dictionary).duplicate(true)
	var rescued := bool(final_state.get("all_lit", false)) \
		and int(final_state.get("total", 0)) > 0 \
		and int(final_state.get("lit", 0)) == int(final_state.get("total", 0))
	_finish(OUTCOME_RESCUED if rescued else OUTCOME_ABANDONED, final_state)


func _finish(result: StringName, details: Dictionary) -> void:
	if _state != STATE_RUNNING:
		return
	_state = STATE_ENDED
	_outcome = result
	if _survival != null:
		_survival.stop()
	if _clock != null:
		_clock.stop()
	var payload := details.duplicate(true)
	payload["outcome"] = result
	payload["seed"] = run_seed
	_emit(EVENT_RUN_ENDED, payload)


func _ensure_run_seed() -> void:
	if run_seed != 0:
		return
	run_seed = int(Time.get_ticks_usec() % 2147483646) + 1


func _resolve() -> void:
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
	if _clock == null:
		_clock = get_node_or_null("/root/WorldClock")
	if _survival == null:
		_survival = get_node_or_null("/root/SurvivalSystem")


func _register_services() -> void:
	if _registry == null:
		return
	_registry.register(SERVICE, self)
	_registry.register(RUN_SEED_SERVICE, self)


func _subscribe() -> void:
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_SURVIVAL_DIED, _on_survival_died)
	_bus.subscribe(EVENT_BEACONS_FINAL_STATE, _on_beacons_final_state)
	_subscribed = true


func _unsubscribe() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_SURVIVAL_DIED, _on_survival_died)
	_bus.unsubscribe(EVENT_BEACONS_FINAL_STATE, _on_beacons_final_state)
	_subscribed = false


func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
