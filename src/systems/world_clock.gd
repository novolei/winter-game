extends Node

## Drives the seven-day run. Registered as autoload "WorldClock".
##
## advance() is public and carries all the logic; _process only forwards to
## it. That lets the whole clock be tested without a running SceneTree,
## which matters because autoloads do not exist under --script.

const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"

## Where the seven days live. GDD section 4 is the whole shape of the game and
## every number in it is in these files, not here.
const DEFAULT_SCHEDULE_DIRECTORY := "res://data/schedule"

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

## Loads every DaySchedule in a directory, in filename order so a run is
## reproducible -- day_01.tres .. day_07.tres sort into the order they are
## played. Returns how many were accepted.
##
## This is the call that did not exist. The seven .tres files had been on disk
## since Wave 0 and the only loader took an Array somebody else had already
## built, so nothing ever built one and the seven-day structure -- the entire
## shape of the game per GDD section 4 -- had never run.
func load_schedules_from_directory(directory_path := DEFAULT_SCHEDULE_DIRECTORY) -> int:
	var loaded: Array = []
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return 0
	var file_names := dir.get_files()
	file_names.sort()
	for entry in file_names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(directory_path.path_join(file_name))
		if resource is DaySchedule:
			loaded.append(resource)
	load_schedules(loaded)
	return _schedules.size()

## Begins the run. Returns whether it actually began one.
##
## IT REFUSES AN EMPTY CLOCK, and that guard is the reason this call could not
## simply be added when the rest of the file was written. start() used to
## announce day 1 of a run with no days in it, and the first advance() then
## found a zero-length phase and fired EVENT_RUN_FINISHED -- which MusicDirector
## plays as an ending. The whole game over, silently, before the first frame was
## drawn, from one line in the wrong order. Load the schedules first; this is
## what happens if you do not.
func start() -> bool:
	if _schedules.is_empty():
		return false
	_day_index = 0
	_phase_elapsed = 0.0
	_is_night = false
	_finished = false
	_running = true
	_emit(EVENT_DAY_STARTED, current_day())
	return true

func is_running() -> bool:
	return _running

## Stops time without declaring the seventh night complete. GameState uses this
## on death; a dead player must not keep advancing weather and day events while
## the ending presentation is running. start() remains the one reset boundary.
func stop() -> void:
	_running = false

func schedule_count() -> int:
	return _schedules.size()

## The authored day, by its number rather than its index -- days are 1-based
## everywhere the player and the GDD can see them. Null outside the run, so a
## caller asking about day 8 gets nothing rather than a wrapped day 1.
func schedule_for_day(day: int):
	var index := day - 1
	if index < 0 or index >= _schedules.size():
		return null
	return _schedules[index]

## The day currently being played, or null before start()/after the end.
func current_schedule():
	return schedule_for_day(current_day())

## How long the whole run lasts, in seconds. What a pacing decision is measured
## against, and cheap enough that nothing needs to cache it.
func total_run_seconds() -> float:
	var total := 0.0
	for schedule in _schedules:
		total += schedule.daylight_seconds + schedule.night_seconds
	return total

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
