extends RefCounted

## Plays a whole seven-day run through MusicDirector with no audio device and
## no SceneTree, and records what a player would have heard.
##
## This is a measuring instrument, not a test helper, which is why it lives in
## tools/: tools/measure_music_density.gd runs hundreds of runs through it to
## settle how often music should arrive, and tests/unit/test_music_density.gd
## runs a handful to keep that settled answer from drifting. Both have to use
## the SAME instrument, or the gate is guarding a number the measurement never
## produced.
##
## WHAT IT MODELS
##
##   * The seven DaySchedule files, so a run is the real 6300 seconds rather
##     than a round number somebody picked.
##
##   * Track endings. This is the part that cannot be left out. The shipped
##     director only learns a track ended from AudioStreamPlayer.finished,
##     which needs an audio device -- so headless, nothing ever finishes, no
##     gap ever starts, and a naive simulation reports wall-to-wall music.
##     MusicCue.duration_seconds stands in for the device here.
##
##   * Threats and shelter visits, as an arrival process. Wave 5 owns the
##     systems that will really emit those events; until they exist, any
##     number that comes out of this has to say which arrival model produced
##     it, so the rates are ARGUMENTS and they are echoed back in the result.
##
## WHAT IT DOES NOT MODEL
##
##   * Endings. A run that ends in silence is the common case and the endings
##     are oneshots outside the gap system entirely.
##   * Weather, wind, ambience. None of them reach MusicDirector.

const DirectorScript := preload("res://src/audio/music_director.gd")
const SelectorScript := preload("res://src/audio/music_selection.gd")
const SCHEDULE_DIRECTORY := "res://data/schedule"

## Sampling step. Small enough that a 3 s fade is resolved, coarse enough that
## a few hundred runs finish in seconds. Checked against 1/60 in
## tools/measure_music_density.gd rather than assumed -- a measurement whose
## answer depends on its own timestep is not a measurement.
const DEFAULT_STEP_SECONDS := 0.25

## Defaults for the arrival process. Stated here once, echoed into every
## result, and overridable per call.
const DEFAULT_OPTIONS := {
	"step_seconds": DEFAULT_STEP_SECONDS,
	"threat_mean_gap_seconds": 0.0,  # 0 disables threats entirely
	"threat_dwell_min_seconds": 20.0,
	"threat_dwell_max_seconds": 70.0,
	"shelter_mean_gap_seconds": 0.0,  # 0 disables shelter visits entirely
	"shelter_dwell_min_seconds": 120.0,
	"shelter_dwell_max_seconds": 360.0,
}

## [[daylight_seconds, night_seconds], ...] for the seven authored days.
static func load_day_lengths(directory := SCHEDULE_DIRECTORY) -> Array:
	var out: Array = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for entry in names:
		var file_name := entry
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var schedule = ResourceLoader.load(directory.path_join(file_name))
		if schedule is DaySchedule:
			out.append([schedule.daylight_seconds, schedule.night_seconds])
	return out

var _map: MusicMap = null
var _director = null
var _rng := RandomNumberGenerator.new()
var _step := DEFAULT_STEP_SECONDS
var _options: Dictionary = {}

var _durations: Dictionary = {}
var _playing: StringName = &""
var _remaining := 0.0

var _danger := false
var _danger_until := 0.0
var _next_threat := 0.0
var _in_shelter := false
var _shelter_until := 0.0
var _next_shelter := 0.0

var _now := 0.0
var _music_seconds := 0.0
var _situation_seconds: Dictionary = {}
var _situation_music_seconds: Dictionary = {}

var _silences: Array = []
var _silence_started := -1.0
var _silence_saw_danger := false
var _phase_start_delays: Array = []
var _pending_phase_start := -1.0

## One run. `seed_value` fixes both the arrival process and the track draws, so
## a run is reproducible and a surprising number can be re-opened.
func run(map: MusicMap, seed_value: int, options: Dictionary = {}) -> Dictionary:
	_map = map
	_options = DEFAULT_OPTIONS.duplicate()
	for key in options:
		_options[key] = options[key]
	_step = maxf(0.001, float(_options["step_seconds"]))
	_rng.seed = seed_value

	_durations.clear()
	for cue in map.cues:
		if cue != null:
			_durations[cue.cue_id] = cue.duration_seconds

	_director = DirectorScript.new()
	_director.set_map(map)
	# A different stream from the arrival process, so that changing how often
	# a bear turns up does not also change which track plays at dawn.
	_director.set_selector(SelectorScript.new(seed_value * 7919 + 104729))

	_playing = &""
	_remaining = 0.0
	_danger = false
	_in_shelter = false
	_now = 0.0
	_music_seconds = 0.0
	_situation_seconds.clear()
	_situation_music_seconds.clear()
	_silences.clear()
	_silence_started = -1.0
	_silence_saw_danger = false
	_phase_start_delays.clear()
	_pending_phase_start = -1.0
	_next_threat = _draw_arrival(float(_options["threat_mean_gap_seconds"]))
	_next_shelter = _draw_arrival(float(_options["shelter_mean_gap_seconds"]))

	var days := load_day_lengths()
	for i in days.size():
		_director.on_day_started(i + 1)
		_mark_phase_start()
		_walk(float(days[i][0]))
		_director.on_night_started(i + 1)
		_mark_phase_start()
		_walk(float(days[i][1]))
	if _pending_phase_start >= 0.0:
		_phase_start_delays.append(_now - _pending_phase_start)
		_pending_phase_start = -1.0
	_director.on_run_finished(null)

	# The run ended; whatever silence was open at that moment was cut short by
	# the clock rather than by the design, so it is censored, not a sample.
	var result := {
		"seed": seed_value,
		"options": _options.duplicate(),
		"seconds": _now,
		"music_seconds": _music_seconds,
		"share": (_music_seconds / _now) if _now > 0.0 else 0.0,
		"situation_seconds": _situation_seconds.duplicate(),
		"situation_music_seconds": _situation_music_seconds.duplicate(),
		"silences": _silences.duplicate(),
		"phase_start_delays": _phase_start_delays.duplicate(),
	}

	# MusicDirector extends Node, which is not reference counted (briefing 2.2).
	_director.free()
	_director = null
	return result

func _draw_arrival(mean_gap: float) -> float:
	if mean_gap <= 0.0:
		return INF
	# Exponential inter-arrival: the memoryless one, so a threat is no more
	# likely just because none has happened for a while.
	return _now - mean_gap * log(maxf(1e-9, 1.0 - _rng.randf()))

## A phase begins. If the previous one never got music at all, record that as
## a delay rather than dropping it -- a phase that passed in silence is exactly
## what this measurement exists to notice.
func _mark_phase_start() -> void:
	if _pending_phase_start >= 0.0:
		_phase_start_delays.append(_now - _pending_phase_start)
	_pending_phase_start = _now

func _walk(seconds: float) -> void:
	var target := _now + seconds
	while _now < target - 1e-6:
		var dt := minf(_step, target - _now)
		_drive_arrivals()
		_director.advance(dt)
		_now += dt
		_settle_track(dt)
		_sample(dt)

func _drive_arrivals() -> void:
	if _danger and _now >= _danger_until:
		_danger = false
		_director.set_danger(false)
		_next_threat = _draw_arrival(float(_options["threat_mean_gap_seconds"]))
	elif not _danger and _now >= _next_threat:
		_danger = true
		_danger_until = _now + _rng.randf_range(
			float(_options["threat_dwell_min_seconds"]),
			float(_options["threat_dwell_max_seconds"]))
		_director.set_danger(true)

	if _in_shelter and _now >= _shelter_until:
		_in_shelter = false
		_director.set_in_shelter(false)
		_next_shelter = _draw_arrival(float(_options["shelter_mean_gap_seconds"]))
	elif not _in_shelter and _now >= _next_shelter:
		_in_shelter = true
		_shelter_until = _now + _rng.randf_range(
			float(_options["shelter_dwell_min_seconds"]),
			float(_options["shelter_dwell_max_seconds"]))
		_director.set_in_shelter(true)

## Stand in for AudioStreamPlayer.finished, which needs a device this has not
## got. A cue that is still the one the mixer is heading towards is the one
## sounding; when its measured length runs out, tell the director so -- which
## is what arms the gap that follows.
func _settle_track(dt: float) -> void:
	var active: StringName = _director.active_cue_id()
	if active != _playing:
		_playing = active
		_remaining = float(_durations.get(active, 0.0))
		return
	if _playing == &"":
		return
	_remaining -= dt
	if _remaining <= 0.0:
		_director.notify_cue_finished(_playing)
		_playing = &""

func _sample(dt: float) -> void:
	var situation: StringName = _director.current_situation()
	var sounding: bool = not _director.is_silent()
	_situation_seconds[situation] = float(_situation_seconds.get(situation, 0.0)) + dt
	if sounding:
		_music_seconds += dt
		_situation_music_seconds[situation] = \
			float(_situation_music_seconds.get(situation, 0.0)) + dt
		if _pending_phase_start >= 0.0:
			_phase_start_delays.append(_now - _pending_phase_start)
			_pending_phase_start = -1.0
		if _silence_started >= 0.0:
			_silences.append({
				"length": _now - dt - _silence_started,
				"danger": _silence_saw_danger,
			})
			_silence_started = -1.0
			_silence_saw_danger = false
		return
	if _silence_started < 0.0:
		_silence_started = _now - dt
		_silence_saw_danger = false
	if _danger or situation == DirectorScript.SITUATION_DANGER:
		_silence_saw_danger = true
