extends Node

## Autoload "MusicDirector". The music side of GDD section 9.
##
## Reads state, never reaches for it. Everything it knows arrives as an
## EventBus event or a public setter; it holds no reference to WorldClock, to
## a threat, or to the player, and deleting any of those leaves it compiling
## and passing its tests (system map principle 2).
##
## The design it serves, in one line: this game has no HUD, its most important
## sounds are a footstep in snow and the wind before a storm, and so the music
## is quiet, intermittent, and -- when something is near -- absent.
##
## HOW THIS FALLS SHORT OF GDD SECTION 9, stated plainly so nobody later
## believes otherwise: section 9 specifies FOUR SIMULTANEOUS LAYERS -- base,
## solitude, warmth, dread -- crossfading against each other so the mix itself
## reports the player's state continuously. That needs stems. What exists is
## nine finished, fully mixed tracks. So this crossfades whole TRACKS by
## situation instead: one thing sounding at a time, changing by fade. The
## states of section 9 survive; the simultaneity does not. A player cannot
## hear "alone AND cold" here, only "alone", and no amount of work on this
## file changes that -- it needs different source material.
##
## What does survive intact is the part section 9 calls the point: when a
## threat is present the music does not sting, it leaves. See SITUATION_DANGER.

const SITUATION_DAWN := &"dawn"
const SITUATION_DAY := &"day"
const SITUATION_DUSK := &"dusk"
const SITUATION_NIGHT := &"night"
const SITUATION_SHELTER := &"shelter"
const SITUATION_DANGER := &"danger"
const SITUATION_NONE := &""

const ENDING_PREFIX := "ending_"
const DEFAULT_MAP_PATH := "res://data/audio/music_map.tres"

## Events this director listens for.
##
## The first three exist today, emitted by WorldClock. The rest are the
## contract the systems that do not exist yet must meet. If Wave 5 names its
## threat events differently, that is an edit to these constants and to
## nothing else -- the handlers below only translate an event into a call on
## the public API, which is also how the tests drive it.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"
const EVENT_THREAT_DETECTED := &"threat.detected_player"
const EVENT_THREAT_LOST := &"threat.lost_player"
const EVENT_SHELTER_ENTERED := &"interior.entered"
const EVENT_SHELTER_EXITED := &"interior.exited"
const EVENT_RUN_ENDED := &"game.run_ended"
const EVENT_RUN_RESET := &"game.run_reset"

const OUTCOME_RESCUED := &"rescued"
const OUTCOME_DEAD := &"dead"
const OUTCOME_ABANDONED := &"abandoned"
const RUN_END_SILENCE_SECONDS := 0.8

enum Phase { NONE, DAY, NIGHT }

## Below this gain a voice is stopped rather than played silently.
const MIN_AUDIBLE := 0.001

var _map: MusicMap = null
var _selector: MusicSelector = null
var _mixer: MusicMixer = MusicMixer.new()
var _bus = null

var _phase: Phase = Phase.NONE
var _phase_elapsed := 0.0

var _danger := false
var _in_shelter := false
var _ending: StringName = SITUATION_NONE

var _situation: StringName = SITUATION_NONE
var _gap_remaining := 0.0
var _gap_armed := false

## True while the running gap carries post_silence_hold_seconds on top -- the
## quiet that follows a threat. Ordinary gaps get re-rolled by a situation
## beginning; this one must not be, and without somewhere to write that down
## there is no way to tell the two apart when the re-roll comes.
##
## Found by measurement, not by reading: with entry_chance at 1.0 a dawn or a
## nightfall lands inside a threat's quiet often enough that 44.6% of them were
## being cut short, some to under 80 s -- shorter than an ordinary gap. The
## behaviour that silence after a threat outlasts everything else is the point
## of this system (GDD section 9), and it was being undone by the mechanism
## that exists to make dawn reliable.
var _gap_holds_after_threat := false

var _volume_db := 0.0
var _volume_overridden := false

var _output_enabled := false
var _players: Array[AudioStreamPlayer] = []
var _player_cue: Array[StringName] = []
var _streams: Dictionary = {}

func _init() -> void:
	_selector = MusicSelector.new()

func _ready() -> void:
	if _map == null:
		_map = ResourceLoader.load(DEFAULT_MAP_PATH) as MusicMap
	if _bus == null:
		# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry
		# is a node under /root and never enters the engine's singleton
		# registry (briefing trap 3). Getting this wrong leaves _bus null
		# forever and every event is swallowed with no diagnostic.
		set_event_bus(get_node_or_null("/root/EventBus"))
	# A headless run has no audio device, so opening streams there would
	# decode ~50 MB to feed a dummy driver. The decisions still run; only the
	# output is withheld. set_output_enabled(true) forces it on for a
	# diagnostic that wants to prove the playback wiring.
	if DisplayServer.get_name() != "headless":
		set_output_enabled(true)

func _process(delta: float) -> void:
	advance(delta)

# --- wiring ---------------------------------------------------------------

func set_event_bus(bus) -> void:
	if _bus == bus:
		return
	if _bus != null:
		_bus.unsubscribe(EVENT_DAY_STARTED, on_day_started)
		_bus.unsubscribe(EVENT_NIGHT_STARTED, on_night_started)
		_bus.unsubscribe(EVENT_RUN_FINISHED, on_run_finished)
		_bus.unsubscribe(EVENT_THREAT_DETECTED, _on_threat_detected)
		_bus.unsubscribe(EVENT_THREAT_LOST, _on_threat_lost)
		_bus.unsubscribe(EVENT_SHELTER_ENTERED, _on_shelter_entered)
		_bus.unsubscribe(EVENT_SHELTER_EXITED, _on_shelter_exited)
		_bus.unsubscribe(EVENT_RUN_ENDED, _on_run_ended)
		_bus.unsubscribe(EVENT_RUN_RESET, _on_run_reset)
	_bus = bus
	if _bus != null:
		_bus.subscribe(EVENT_DAY_STARTED, on_day_started)
		_bus.subscribe(EVENT_NIGHT_STARTED, on_night_started)
		_bus.subscribe(EVENT_RUN_FINISHED, on_run_finished)
		_bus.subscribe(EVENT_THREAT_DETECTED, _on_threat_detected)
		_bus.subscribe(EVENT_THREAT_LOST, _on_threat_lost)
		_bus.subscribe(EVENT_SHELTER_ENTERED, _on_shelter_entered)
		_bus.subscribe(EVENT_SHELTER_EXITED, _on_shelter_exited)
		_bus.subscribe(EVENT_RUN_ENDED, _on_run_ended)
		_bus.subscribe(EVENT_RUN_RESET, _on_run_reset)

func set_map(map: MusicMap) -> void:
	_map = map

func set_selector(selector: MusicSelector) -> void:
	if selector != null:
		_selector = selector

# --- state coming in ------------------------------------------------------

func set_danger(present: bool) -> void:
	if _danger == present:
		return
	_danger = present
	_sync_situation(true)

func set_in_shelter(inside: bool) -> void:
	if _in_shelter == inside:
		return
	_in_shelter = inside
	_sync_situation(true)

## `outcome` is a GDD section 10 ending -- &"rescue", &"death", &"unseen" --
## or the full situation id. &"" clears it.
func set_ending(outcome: StringName) -> void:
	var next := SITUATION_NONE
	if outcome != SITUATION_NONE:
		var text := String(outcome)
		next = outcome if text.begins_with(ENDING_PREFIX) else StringName(ENDING_PREFIX + text)
	if _ending == next:
		return
	_ending = next
	_sync_situation(true)

func on_day_started(_payload = null) -> void:
	_phase = Phase.DAY
	_phase_elapsed = 0.0
	_sync_situation(true)

func on_night_started(_payload = null) -> void:
	_phase = Phase.NIGHT
	_phase_elapsed = 0.0
	_sync_situation(true)

func on_run_finished(_payload = null) -> void:
	_phase = Phase.NONE
	_phase_elapsed = 0.0
	_sync_situation(true)

## A stream reached its end on its own. This is what makes silence the norm:
## a track that finishes is followed by a gap, not by another track.
func notify_cue_finished(cue_id: StringName) -> void:
	if _map == null or cue_id == &"":
		return
	var was_active := _mixer.active_cue_id() == cue_id
	_mixer.notify_finished(cue_id)
	if not was_active:
		return
	if _is_silent_situation(_situation) or _map.is_oneshot_situation(_situation):
		_gap_armed = false
		_gap_holds_after_threat = false
		return
	_gap_remaining = _selector.next_gap_seconds(_map)
	_gap_armed = true
	_gap_holds_after_threat = false

# --- the loop -------------------------------------------------------------

func advance(delta: float) -> void:
	if _map == null:
		return
	if _phase != Phase.NONE:
		_phase_elapsed += delta
		# Drift, not entry: dawn quietly becoming daylight is a continuation of
		# the same phase, so it must not restart a gap that is already running.
		# Without that distinction a threat's silence could be cut short by the
		# sun coming up mid-hold.
		_sync_situation(false)
	_tick_gap(delta)
	_mixer.advance(delta)
	_apply()

func _tick_gap(delta: float) -> void:
	if not _gap_armed or _map == null:
		return
	if _is_silent_situation(_situation):
		return
	if not _mixer.is_silent():
		return
	_gap_remaining -= delta
	if _gap_remaining <= 0.0:
		_start_cue()

func _sync_situation(is_entry: bool) -> void:
	if _map == null:
		return
	var next := _resolve()
	if next == _situation:
		return
	var previous := _situation
	_situation = next

	if _is_silent_situation(next):
		_mixer.fade_to_silence(_map.silence_fade_seconds)
		_gap_armed = false
		_gap_holds_after_threat = false
		return

	if _map.is_oneshot_situation(next):
		_start_cue()
		return

	if not _mixer.is_silent():
		var active := _mixer.active_cue_id()
		var cue := _map.cue_by_id(active)
		if cue != null and cue.plays_in(next):
			return  # the same track still fits; changing it would be churn
		_start_cue()
		return

	if not is_entry:
		if not _gap_armed:
			_gap_remaining = _selector.next_gap_seconds(_map)
			_gap_armed = true
			_gap_holds_after_threat = false
		return

	if previous != SITUATION_NONE and _map.is_silent_situation(previous):
		# Coming out of danger. A full gap plus a hold on top: snapping back to
		# music the moment the bear wanders off would undo the scene.
		_gap_remaining = _selector.next_gap_seconds(_map) + _map.post_silence_hold_seconds
		_gap_holds_after_threat = true
		_gap_armed = true
		return

	if _gap_armed and _gap_holds_after_threat:
		# That quiet is still running, and a dawn arriving in the middle of it
		# does not end it. What follows exists so that a situation beginning
		# gets music soon; letting it fire here would sound the all-clear while
		# the bear is still fifty metres off, and would leave the one silence in
		# this game that carries information looking like the ones that do not.
		return

	var next_wait := _selector.next_entry_gap_seconds(_map) if _selector.roll_entry(_map) \
		else _selector.next_gap_seconds(_map)
	# A SITUATION BEGINNING BRINGS MUSIC FORWARD; IT NEVER POSTPONES IT. Without
	# the minf, a nightfall landing near the end of a gap throws away the few
	# seconds left and starts a fresh one -- so an ordinary silence could run to
	# gap_max PLUS entry_gap_max, measured at 213.8 s against a 182.7 s ceiling.
	# Two things break there: the gap the density derivation drew is not the gap
	# served, and an ordinary silence reaches lengths that are supposed to mean
	# a threat.
	_gap_remaining = minf(_gap_remaining, next_wait) if _gap_armed else next_wait
	_gap_holds_after_threat = false
	_gap_armed = true

func _start_cue() -> void:
	_gap_armed = false
	_gap_holds_after_threat = false
	var cue := _selector.pick(_map, _situation)
	if cue == null:
		_mixer.fade_to_silence(_map.silence_fade_seconds)
		return
	_mixer.play(cue.cue_id, _map.crossfade_seconds)

func _resolve() -> StringName:
	if _ending != SITUATION_NONE:
		return _ending
	if _danger:
		return SITUATION_DANGER
	if _in_shelter:
		return SITUATION_SHELTER
	match _phase:
		Phase.DAY:
			return SITUATION_DAWN if _phase_elapsed < _map.dawn_seconds else SITUATION_DAY
		Phase.NIGHT:
			return SITUATION_DUSK if _phase_elapsed < _map.dusk_seconds else SITUATION_NIGHT
		_:
			return SITUATION_NONE

## Three ways to be silent, and all three must behave identically: declared
## silent (danger), cast for nothing, or no situation at all.
func _is_silent_situation(situation: StringName) -> bool:
	if situation == SITUATION_NONE:
		return true
	if _map == null:
		return true
	return _map.is_silent_situation(situation) or _map.cues_for(situation).is_empty()

# --- introspection --------------------------------------------------------

func current_situation() -> StringName:
	return _situation

func active_cue_id() -> StringName:
	return _mixer.active_cue_id()

func is_silent() -> bool:
	return _mixer.is_silent()

func gap_remaining() -> float:
	return _gap_remaining if _gap_armed else 0.0

func voice_gain(index: int) -> float:
	return _mixer.voice_gain(index)

func music_volume_db() -> float:
	if _volume_overridden:
		return _volume_db
	return _map.base_volume_db if _map != null else 0.0

## What an options slider moves. The authored default lives in the map, which
## is inspector-editable, so tuning by ear needs no code either way.
func set_music_volume_db(db: float) -> void:
	_volume_db = db
	_volume_overridden = true

func is_output_ready() -> bool:
	return _output_enabled and not _players.is_empty()

# --- output ---------------------------------------------------------------

func set_output_enabled(enabled: bool) -> void:
	_output_enabled = enabled
	if enabled and _players.is_empty():
		_build_players()

func _build_players() -> void:
	for i in MusicMixer.VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "MusicVoice%d" % i
		player.volume_db = -80.0
		add_child(player)
		player.finished.connect(_on_voice_finished.bind(i))
		_players.append(player)
		_player_cue.append(&"")

func _on_voice_finished(index: int) -> void:
	if index < 0 or index >= _player_cue.size():
		return
	notify_cue_finished(_player_cue[index])

func _apply() -> void:
	if not _output_enabled or _players.is_empty() or _map == null:
		return
	for i in MusicMixer.VOICE_COUNT:
		var player: AudioStreamPlayer = _players[i]
		var cue_id := _mixer.voice_cue_id(i)
		var gain := _mixer.voice_gain(i)
		if cue_id == &"" or gain <= MIN_AUDIBLE:
			if player.playing:
				player.stop()
			_player_cue[i] = &""
			continue
		var cue := _map.cue_by_id(cue_id)
		if cue == null:
			continue
		if _player_cue[i] != cue_id:
			var stream := _stream_for(cue)
			if stream == null:
				continue
			player.stream = stream
			player.bus = _map.bus
			player.volume_db = linear_to_db(gain) + cue.gain_db + music_volume_db()
			player.play()
			_player_cue[i] = cue_id
		else:
			player.volume_db = linear_to_db(gain) + cue.gain_db + music_volume_db()

## Loaded on first use rather than with the map, so booting the game does not
## pull all nine files into memory. Cached because a cue recurs.
##
## The stream is NOT mutated here. Loop is off in the .import files, and
## ResourceLoader hands every caller the same cached instance (briefing trap
## 6), so setting it on this one would be setting it for everybody.
func _stream_for(cue: MusicCue) -> AudioStream:
	if _streams.has(cue.cue_id):
		return _streams[cue.cue_id]
	if cue.stream_path == "" or not ResourceLoader.exists(cue.stream_path):
		return null
	var stream := ResourceLoader.load(cue.stream_path) as AudioStream
	_streams[cue.cue_id] = stream
	return stream

# --- event adapters -------------------------------------------------------
#
# EventBus always dispatches with exactly one argument, so every callback here
# declares exactly one parameter. Zero or two is a runtime argument-count
# error at dispatch, not a parse error.

func _on_threat_detected(_payload) -> void:
	set_danger(true)

func _on_threat_lost(_payload) -> void:
	set_danger(false)

func _on_shelter_entered(_payload) -> void:
	set_in_shelter(true)

func _on_shelter_exited(_payload) -> void:
	set_in_shelter(false)

func _on_run_ended(payload) -> void:
	if not (payload is Dictionary):
		return
	match StringName((payload as Dictionary).get("outcome", &"")):
		OUTCOME_RESCUED:
			set_ending(&"rescue")
		OUTCOME_DEAD, OUTCOME_ABANDONED:
			# The ending design is explicit here: death loses every voice within
			# 800 ms, while abandonment is carried by the helicopter and wind.
			# Neither outcome starts a UI-owned music cue.
			_ending = SITUATION_NONE
			_phase = Phase.NONE
			_phase_elapsed = 0.0
			_situation = SITUATION_NONE
			_gap_remaining = 0.0
			_gap_armed = false
			_gap_holds_after_threat = false
			_mixer.fade_to_silence(RUN_END_SILENCE_SECONDS)


func _on_run_reset(payload) -> void:
	var seed := 0
	if payload is Dictionary:
		seed = int((payload as Dictionary).get("seed", 0))
	_selector.reset(seed)
	_phase = Phase.NONE
	_phase_elapsed = 0.0
	_danger = false
	_in_shelter = false
	_ending = SITUATION_NONE
	_situation = SITUATION_NONE
	_gap_remaining = 0.0
	_gap_armed = false
	_gap_holds_after_threat = false
	_mixer = MusicMixer.new()
	_apply()
