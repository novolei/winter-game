extends Node

## Drives the seven-day run. Registered as autoload "WorldClock".
##
## advance() is public and carries all the logic; _process only forwards to
## it. That lets the whole clock be tested without a running SceneTree,
## which matters because autoloads do not exist under --script.

const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"

var _schedules: Array = []
var _day_index := 0
var _phase_elapsed := 0.0
var _is_night := false
var _running := false
var _finished := false
var _bus = null

func set_event_bus(bus) -> void:
	_bus = bus

func _ready() -> void:
	# In a real run the autoload wires itself to the autoloaded bus.
	# Tests inject their own via set_event_bus() before calling start().
	#
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry
	# is a node under /root and never appears in the engine's singleton
	# registry, which holds only natively-registered and GDExtension
	# singletons. Engine.has_singleton("EventBus") is false always, which
	# would leave _bus null forever -- and _emit()'s null guard would then
	# swallow every clock event with no diagnostic. That failure is
	# invisible to this wave's tests, because they all inject a bus and
	# never add WorldClock to a live scene tree, so _ready() never runs.
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")

func load_schedules(schedules: Array) -> void:
	_schedules = schedules.duplicate()

func start() -> void:
	_day_index = 0
	_phase_elapsed = 0.0
	_is_night = false
	_finished = false
	_running = true
	_emit(EVENT_DAY_STARTED, current_day())

func current_day() -> int:
	return _day_index + 1

func is_night() -> bool:
	return _is_night

func is_finished() -> bool:
	return _finished

func phase_elapsed() -> float:
	return _phase_elapsed

func phase_duration() -> float:
	if _day_index >= _schedules.size():
		return 0.0
	var schedule = _schedules[_day_index]
	return schedule.night_seconds if _is_night else schedule.daylight_seconds

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _running or _finished:
		return
	var remaining := delta
	# Loop rather than subtract once: a long frame or a fast-forward may
	# cross more than one phase boundary in a single call.
	while remaining > 0.0 and not _finished:
		var duration := phase_duration()
		if duration <= 0.0:
			_finish()
			return
		var left := duration - _phase_elapsed
		if remaining < left:
			_phase_elapsed += remaining
			return
		remaining -= left
		_phase_elapsed = 0.0
		_advance_phase()

func _advance_phase() -> void:
	if _is_night:
		_is_night = false
		_day_index += 1
		if _day_index >= _schedules.size():
			_finish()
			return
		_emit(EVENT_DAY_STARTED, current_day())
	else:
		_is_night = true
		_emit(EVENT_NIGHT_STARTED, current_day())

func _finish() -> void:
	_finished = true
	_running = false
	_emit(EVENT_RUN_FINISHED, null)

func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
