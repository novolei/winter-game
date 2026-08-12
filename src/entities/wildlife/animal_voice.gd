class_name AnimalVoice
extends Node3D

## An animal's voice: positional, data-driven, and tied to the takes it is
## standing beside.
##
## Not a dog class. It reads an `AnimalVoiceMap` and knows nothing about what
## kind of animal is above it, so the fox and the bear get one by adding a
## `.tres` and a node -- no `.gd` (briefing constraint 4). The dog is simply the
## first animal to have a file.
##
## ---------------------------------------------------------------------------
## POSITIONAL, BECAUSE THAT IS WHAT A WARNING IS
## ---------------------------------------------------------------------------
## `AudioStreamPlayer3D`, and the node rides under the animal, so a call comes
## from where the animal is and moves with it. **A growl that does not come from
## a direction cannot warn anyone about a direction** -- it is a noise the game
## makes, and the player learns nothing from it except that something happened.
## Same reason the caws are positional and the menu clicks are not.
##
## ---------------------------------------------------------------------------
## TIED TO THE TAKES, WITHOUT TOUCHING THE ANIMAL
## ---------------------------------------------------------------------------
## `Dog` has no behaviour and no events -- it is a model, a colour and a take
## library, and it is somebody else's file this wave. So the wiring runs the
## other way: this node WATCHES the `AnimationPlayer` beside it and speaks when
## the take changes. Anything that calls `dog.play(DogAnimations.GROWL)` gets the
## sound for free, today, with no edit to `dog.gd` and no signal to connect.
##
## ---------------------------------------------------------------------------
## A NODE THAT ONLY WATCHES FOR A CHANGE NEVER LEARNS A STATE THAT PREDATES IT
## ---------------------------------------------------------------------------
## This project has been bitten twice by a listener that subscribed to a
## transition and therefore never learned the state the world was already in.
## The same hole is wide open here, and by construction: **a child's `_ready()`
## runs BEFORE its parent's**, so an `AnimalVoice` under a `Dog` is ready before
## `Dog._ready()` has built the rig -- there is no `AnimationPlayer` to find yet,
## and by the time there is, nothing will report a change.
##
## Two things close it:
##
##   * the search for the player REPEATS until it succeeds, rather than happening
##     once on ready and giving up;
##   * `_seen_take` starts as "nothing seen yet" rather than as the current take,
##     so the first observation is a change whatever it finds. Attach this to a
##     dog that is already growling and it growls.
##
## ---------------------------------------------------------------------------
## `play()` RETURNING TRUE IS NOT PROOF A SOUND PLAYED
## ---------------------------------------------------------------------------
## An `AudioStreamPlayer3D` outside the scene tree refuses playback and says so
## only in the console. This project's fifth false-PASS was a test asserting 44
## successful `play()` calls the engine had refused every one of. So `say()`
## returns false when this node is not in the tree, `utter()` reports what the
## engine did rather than what it was asked, and the tests assert `is_playing()`.

## Where the emitters go. Left on Master because this project ships no custom bus
## layout; the same note is in `crow_calls.gd` and `ui_audio.gd`, and a wildlife
## bus is the right home for all three the day anything needs to duck them.
@export var bus: StringName = &"Master"

## The map this animal speaks from.
@export_file("*.tres") var map_path := ""

## Off, and nothing is scheduled or spoken at all.
@export var enabled := true

@export var random_seed := 0

## Published whenever the animal actually makes a sound, with
## `{call_id, position, stream_path}`. Nothing consumes it yet; a growl is a
## warning, and a warning nothing can hear about is half a warning.
const EVENT_SPOKE := &"wildlife.animal_spoke"

var _map: AnimalVoiceMap = null
var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer3D] = []
## `{at, call}` per queued utterance, in the burst's own clock.
var _pending: Array = []
var _clock := 0.0
var _last_at: Dictionary = {}
var _player: AnimationPlayer = null
var _watch_parent := true
## Deliberately NOT the current take: see the header. `&""` means "nothing seen".
var _seen_take: StringName = &""
var _seen_position := 0.0
var _last_asked: StringName = &""
var _since_search := 0.0
var _spoken := 0
var _trimmed := 0
var _bus_node = null


func _ready() -> void:
	seed_rng()
	if _bus_node == null:
		# Briefing trap 3: an autoload is a node under /root, never an engine
		# singleton.
		_bus_node = get_node_or_null("/root/EventBus")
	if _map == null and map_path != "":
		load_map(map_path)
	_find_player()


## Hashed and shaken out rather than assigned. On 4.7.1 the fourth `randf()`
## after seeding lands in 0.09..0.24 whatever the seed (briefing trap 14), and a
## burst draws a handful of values immediately -- which take, what pitch, how
## many, how far apart. Public so a test reseeds the same way rather than
## reaching for `_rng` and getting the unwarmed stream.
func seed_rng() -> void:
	_rng.seed = hash(random_seed) if random_seed != 0 else int(Time.get_ticks_usec())
	for _discard in range(8):
		_rng.randf()


func set_event_bus(bus_node) -> void:
	_bus_node = bus_node


## Loads the map. Returns how many calls it declares; zero means this voice is
## inert, which is a legal state -- a scene may run before the audio has landed
## and must not take the scene down with it.
func load_map(path: String) -> int:
	# Asked before loading, because ResourceLoader.load() on a path that is not
	# there logs three ERROR lines before returning null, and by this project's
	# standard a dirty console is a failed run whether or not the absence was
	# handled correctly. Here it is.
	if path == "" or not ResourceLoader.exists(path):
		return 0
	_map = ResourceLoader.load(path) as AnimalVoiceMap
	map_path = path
	return 0 if _map == null else _map.calls.size()


func set_map(map: AnimalVoiceMap) -> void:
	_map = map


func map() -> AnimalVoiceMap:
	return _map


## Watch this player's takes. Pass null to stop watching, which is what a
## capture or a test does when it wants to drive `say()` by hand.
func watch(player: AnimationPlayer) -> void:
	_player = player
	_watch_parent = false
	_seen_take = &""
	_seen_position = 0.0
	notice_take()


func watched_player() -> AnimationPlayer:
	return _player


## Say something, now. Returns whether a sound actually started -- not whether
## the call exists, and not whether `play()` was called.
##
## False here means one of: no map, no such call, the call has no file, the
## cooldown has not expired, or this node is not in the tree. All five are
## silence, and a caller that cannot tell them apart cannot debug any of them.
func say(call_id: StringName) -> bool:
	if not enabled or _map == null:
		return false
	var call := _map.call_named(call_id)
	if call == null:
		return false
	_last_asked = call_id
	# Checked BEFORE the cooldown is stamped. A call with no file and a call
	# outside the tree both make no sound, and neither should spend a cooldown
	# that would then suppress the utterance that could have worked.
	if not call.is_voiced() or not is_inside_tree():
		return false
	if _clock - float(_last_at.get(call_id, -1.0e9)) < call.cooldown_s:
		return false
	_last_at[call_id] = _clock
	_pending.clear()
	var wanted := call.repeats(_rng.randf())
	var at := 0.0
	for index in range(1, wanted):
		at += _rng.randf_range(call.gap_min, call.gap_max)
		_pending.append({"at": _clock + at, "call": call_id})
	return utter(call)


## Say whatever this take means, if it means anything. The automatic path.
func say_for_take(take: StringName) -> bool:
	if _map == null:
		return false
	var call := _map.call_for_take(take)
	if call == null:
		return false
	return say(call.call_id)


## Look at the watched player and speak if the take has changed.
##
## Public because the first look must happen the moment a player is found rather
## than on the next frame, and because a test wants to force one.
func notice_take() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var raw: String = _player.current_animation
	var take := take_name(raw)
	# GUARDED, and it cost a round to find out why. `current_animation_position`
	# is `ERR_FAIL_COND_V_MSG(!playback.current.from, ...)` inside the engine: read
	# it while nothing is playing and it prints
	#   "AnimationPlayer has no current animation"
	# to the console and returns 0. Reading it unguarded made every test in
	# `test_animal_voice.gd` PASS over an ERROR line -- exactly the shape
	# `tools/run_tests.sh` exists to catch, since the runner cannot see it.
	var position := 0.0
	if raw != "" and _player.is_playing():
		position = _player.current_animation_position
	# A one-shot replayed from the start leaves `current_animation` untouched, so
	# a dog told to bark twice would bark once. The clock going backwards is the
	# only report of it; `cooldown_s` is what stops a looping take -- `growl` and
	# `lie` both loop -- from re-firing every cycle.
	var restarted := take == _seen_take and position + 0.0001 < _seen_position
	_seen_position = position
	if take == _seen_take and not restarted:
		return false
	_seen_take = take
	if take == &"":
		return false
	return say_for_take(take)


## The take's own name, with the library prefix off and the edges trimmed.
##
## TRIMMED because a take name can carry a trailing space and still import: the
## crow pack ships `Dove_Run to Idle ` (briefing trap 15), and a name nobody can
## type is a take nobody can reach. Counted rather than warned about --
## `push_warning` would turn a third-party asset's whitespace into a red suite
## for whoever ran next, and this project fails a run on a stray `WARNING:`.
## `trimmed_names()` is how a gate asks.
func take_name(raw: String) -> StringName:
	if raw == "":
		return &""
	var name := raw
	var slash := name.rfind("/")
	if slash >= 0:
		name = name.substr(slash + 1)
	var clean := name.strip_edges()
	if clean != name:
		_trimmed += 1
	return StringName(clean)


## How many take names needed their edges trimmed. Zero on a clean asset.
func trimmed_names() -> int:
	return _trimmed


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything, the same shape as `CrowCalls.advance()`, so a
## test or a capture drives it without a tree tick.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_clock += delta
	_since_search += delta
	if _watch_parent and (_player == null or not is_instance_valid(_player)):
		# Repeated rather than once on ready: a child is ready before its parent,
		# so the rig this voice belongs to does not exist yet at that moment.
		# Throttled, because an animal that never grows an AnimationPlayer would
		# otherwise walk its whole subtree every frame for the life of the game.
		if _since_search >= 0.25:
			_since_search = 0.0
			_find_player()
	notice_take()
	if _pending.is_empty() or _map == null:
		return
	var still: Array = []
	for entry in _pending:
		if _clock < float(entry["at"]):
			still.append(entry)
			continue
		var call := _map.call_named(entry["call"])
		if call != null:
			utter(call)
	_pending = still


## One utterance of one call, straight away. Returns what the engine did.
func utter(call: AnimalCall) -> bool:
	if call == null or not enabled or not call.is_voiced():
		return false
	if not is_inside_tree():
		return false
	var path := call.stream_paths[_rng.randi_range(0, call.stream_paths.size() - 1)]
	if not ResourceLoader.exists(path):
		return false
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		return false
	var voice := _free_voice()
	voice.stream = stream
	voice.bus = bus
	voice.volume_db = call.gain_db
	voice.max_distance = call.carry_m
	voice.unit_size = call.unit_size
	var spread := absf(call.pitch_spread)
	voice.pitch_scale = call.pitch_scale
	if spread > 0.0:
		voice.pitch_scale = call.pitch_scale * _rng.randf_range(1.0 - spread, 1.0 + spread)
	voice.play()
	if not voice.is_playing():
		return false
	_spoken += 1
	if _bus_node != null:
		_bus_node.emit_event(EVENT_SPOKE, {
			"call_id": call.call_id,
			"position": global_position,
			"stream_path": path,
		})
	return true


func voices() -> Array[AudioStreamPlayer3D]:
	return _voices


## What is still queued in the current burst.
func pending() -> Array:
	return _pending.duplicate(true)


## The last call `say()` recognised -- whether or not it had a file behind it, and
## whether or not the cooldown let it through. Deliberately not "the last thing
## heard": `dog.growl` is a real request that makes no sound, and a caller
## debugging silence needs to know the difference between "asked and mute" and
## "never asked".
func last_asked() -> StringName:
	return _last_asked


## How many utterances the engine actually started. Not how many were asked for.
func spoken_count() -> int:
	return _spoken


func _find_player() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for node in parent.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	if _player != null:
		notice_take()


## Round-robin past the pool ceiling rather than growing without bound.
##
## A free-player search alone is what `ui_audio.gd` refused, and for a reason
## that applies here too: a call is a few hundred milliseconds and an emitter is
## "busy" for all of it, so a dog barking four times in one burst would allocate
## four. Four is fine; four every burst forever is not.
func _free_voice() -> AudioStreamPlayer3D:
	for voice in _voices:
		if not voice.playing:
			return voice
	if _voices.size() >= 8:
		var oldest := _voices[0]
		_voices.remove_at(0)
		_voices.append(oldest)
		return oldest
	var made := AudioStreamPlayer3D.new()
	made.name = "Voice%d" % _voices.size()
	made.bus = bus
	add_child(made)
	_voices.append(made)
	return made


func _exit_tree() -> void:
	# Quitting mid-bark otherwise leaves the AudioServer holding a playback and
	# with it the stream: "ERROR: N resources still in use at exit", which is a
	# dirty console and a failed run by this project's standard.
	for voice in _voices:
		if voice != null:
			voice.stop()
