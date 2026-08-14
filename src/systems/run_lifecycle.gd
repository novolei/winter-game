class_name RunLifecycle
extends Node

## Scene-local owner of the first attempt's start boundary.
##
## GameState is an autoload and therefore exists while the boot splash is still
## loading the world.  Starting there made the calendar and body advance behind
## the splash.  This node lives inside Main, whose processing Boot explicitly
## disables during graphics preparation.  One active frame is intentionally
## left for siblings such as WeatherSystem to resolve and attach; the request is
## sent on the following frame and never polled again.

const EVENT_RUN_START_REQUESTED := &"game.run_start_requested"
const SETTLE_FRAMES := 1

@export var start_seed := 0

var _bus = null
var _active_frames := 0
var _requested := false


func _ready() -> void:
	_resolve()
	set_process(true)


func _process(_delta: float) -> void:
	if _requested:
		set_process(false)
		return
	_resolve()
	if _bus == null:
		return
	if _active_frames < SETTLE_FRAMES:
		_active_frames += 1
		return
	_requested = true
	set_process(false)
	_bus.emit_event(EVENT_RUN_START_REQUESTED, {"seed": start_seed})


func set_event_bus(bus) -> void:
	_bus = bus


func has_requested() -> bool:
	return _requested


func active_frames() -> int:
	return _active_frames


func _resolve() -> void:
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
