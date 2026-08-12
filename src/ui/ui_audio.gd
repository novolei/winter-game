class_name UIAudio
extends Node

## Plays UI design document section 8's cues. Rule 6: every 呵 has a sound, and
## the visual and the audio are born on the same frame.
##
## ---------------------------------------------------------------------------
## THE POOL IS ROUND-ROBIN, NOT "FIND A FREE PLAYER"
## ---------------------------------------------------------------------------
## The obvious implementation looks for a player whose is_playing() is false. It
## does not survive contact with real assets: the supplied click.mp3 is 0.813 s
## long and the audible part of a UI click is a few tens of milliseconds. The
## rest is tail and silence, and a free-player search counts every one of those
## voices as busy for most of a second.
##
## A player moving quickly down a menu would then find the whole pool occupied by
## SILENCE and hear nothing at all -- the failure being that the menu goes mute
## exactly when it is being used hardest, which reads as a broken build rather
## than as a pool that is too small.
##
## Round-robin cannot do that. Cutting off an inaudible tail costs nothing;
## dropping the click costs the feel of the entire menu.
##
## ---------------------------------------------------------------------------
## NON-POSITIONAL
## ---------------------------------------------------------------------------
## AudioStreamPlayer rather than AudioStreamPlayer3D. These sounds are not coming
## from anywhere in the valley -- they are the interface, and the interface is
## where the player is. The diegetic sounds that DO come from somewhere are
## stove.gd's and the beacons', and they are 3D for exactly that reason.

const DEFAULT_MAP_PATH := "res://data/audio/ui_sounds.tres"

## Eight voices. A menu move is a few tens of milliseconds of audible sound, so
## eight is well past any speed a person can move a selection -- the pool exists
## to stop clicks cutting each other off, not to mix a texture.
const POOL_SIZE := 8

## Left on Master because this project ships no custom bus layout. A dedicated UI
## bus is the right home for these -- section 8 wants them ducked under the
## ambient rather than mixed into it -- and this is the one line that moves them
## once a layout exists.
@export var bus: StringName = &"Master"

var _map: UISoundMap = null
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last: AudioStreamPlayer = null

func _ready() -> void:
	if _map == null:
		load_map()

## Loads the map and builds the pool. Returns how many cues were accepted; zero
## means it is inert, which is a legal state -- a scene may run before the audio
## has landed, and it must not take the scene down with it.
func load_map(path := DEFAULT_MAP_PATH) -> int:
	_map = ResourceLoader.load(path) as UISoundMap
	if _map == null:
		return 0
	_build_pool()
	return _map.cues.size()

func set_map(map: UISoundMap) -> void:
	_map = map
	_build_pool()

## Plays a cue. False when there is no such cue, so a typo is distinguishable
## from a sound that played -- silence alone is not.
func play(cue_id: StringName) -> bool:
	if _map == null or cue_id == &"":
		return false
	var cue := _map.cue(cue_id)
	if cue == null or cue.stream_path == "":
		return false
	var stream := ResourceLoader.load(cue.stream_path) as AudioStream
	if stream == null:
		return false
	if _pool.is_empty():
		_build_pool()
	if _pool.is_empty():
		return false

	var player := _pool[_next]
	# Advance first, so an early return further down cannot leave two
	# consecutive plays on the same voice.
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = cue.gain_db
	var spread := absf(cue.pitch_spread)
	player.pitch_scale = cue.pitch_scale
	if spread > 0.0:
		player.pitch_scale = cue.pitch_scale * randf_range(1.0 - spread, 1.0 + spread)
	player.bus = bus
	player.play()
	_last = player
	return true

func cue_count() -> int:
	return 0 if _map == null else _map.cues.size()

func pool_size() -> int:
	return _pool.size()

## The voice the last play() used. For tests and for anything that wants to stop
## a sound it just started.
func last_player() -> AudioStreamPlayer:
	return _last

func _build_pool() -> void:
	if not _pool.is_empty():
		return
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		player.bus = bus
		add_child(player)
		_pool.append(player)

func _exit_tree() -> void:
	# Quitting mid-click otherwise leaves the AudioServer holding a playback and
	# with it the stream: "ERROR: N resources still in use at exit", which is a
	# dirty console and a failed run by this project's standard.
	for player in _pool:
		if player != null:
			player.stop()
