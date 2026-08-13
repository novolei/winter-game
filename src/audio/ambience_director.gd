class_name AmbienceDirector
extends Node3D

## THE VOICE OF THE VALLEY. GDD section 9's other half.
##
## `src/audio/music_director.gd` owns the music and states the design in one
## line: "this game has no HUD, its most important sounds are a footstep in snow
## and the wind before a storm, and so the music is quiet, intermittent, and --
## when something is near -- absent."
##
## This file owns the wind before the storm. It does not contradict that line; it
## is the reason the line can be true. Music can afford to leave because
## something else is carrying the world.
##
## ---------------------------------------------------------------------------
## FOUR CLAIMS, AND WHERE EACH ONE IS ENFORCED
## ---------------------------------------------------------------------------
## 1. THE WIND IS NOT A LOOP. It is a bed of layers, each present only across a
##    window of the wind's actual strength (`AmbienceLayer`), positioned UPWIND
##    of the listener and moving round him as the heading veers. A loop with a
##    volume knob is the fastest way to make a large space feel small.
##
## 2. THE BED IS AHEAD OF THE WORLD. `WindSystem`'s model is a pure function of
##    time -- its header says outright that a capture tool can sample the future
##    -- so the bed asks what the wind will be doing in `lead_seconds` and plays
##    that. The tyre swing and the smoke column LAG by construction, because a
##    cue is believed when it arrives late (briefing, "A cue and a tell need
##    opposite properties"). Sound leading and mass lagging is the whole of
##    "heard before it is felt", and it costs one addition.
##
## 3. ABSENCE IS A SIGNAL, SO THE BED HAS GAPS. Every layer's `enters_at` is
##    above zero, so a lull is silent rather than quiet, and 寒流's 空气变得极静
##    is carried by the bed GOING rather than by any file. And when a threat is
##    near, the layers marked `withdraws_near_danger` leave -- GDD section 9's
##    抽走高频层，只剩低频, which is a subtraction and not a sting.
##
## 4. A ROOM IS A DIFFERENT ACOUSTIC, NOT A LOWER VOLUME. Crossing the threshold
##    moves four things at once: a low-pass closes on the bed's bus, the emitters
##    move OUT past the walls, the panning localises, and the level trims. The
##    trim is deliberately the smallest of the four. See `AmbienceMap`.
##
## ---------------------------------------------------------------------------
## IT ASKS AS WELL AS SUBSCRIBING
## ---------------------------------------------------------------------------
## A node that only subscribes to a TRANSITION can never learn a state that
## changed before it existed. This project has paid for that twice already -- the
## stove and the day/night phase -- so `ask_the_world()` runs on ready and is
## public: the fires are read off the group, and the interiors are asked whether
## the occupant is already inside.
##
## The wind needs no such call because it is POLLED, which is the other half of
## the same lesson. `wind.gust_started` fires once at a 0.30 crossing and never
## again while the gust climbs to 0.798; a bed driven by that event would sit out
## the peak of every gust in the game. Events are for onsets. Levels are sampled.
##
## Danger is the one state with nothing to ask: no threat system exists yet, so
## `set_danger()` is public and `EVENT_THREAT_DETECTED` is the wire Wave 5 lands
## on. Recorded rather than hidden -- `MusicDirector` has the same gap.
##
## ---------------------------------------------------------------------------
## IT HOLDS NO REFERENCE TO ANY SYSTEM
## ---------------------------------------------------------------------------
## The wind, the snowfall and the player are resolved through `ServiceRegistry`
## and used duck-typed; the fires are read off a group whose name is spelled out
## here rather than imported. Delete any of them and this still compiles and
## still passes its tests, which is system-map principle 2 and the reason
## everything below takes an injectable collaborator.

## Spelled out rather than read off `src/entities/fires.gd`, so this file holds
## no reference to that one -- the same call `WindSystem` makes for the snowfall
## layer group, and for the same reason. Wave 4's beacons join the same group and
## get their own voice with no edit here.
const FIRE_GROUP := &"fires"

const WIND_SERVICE := &"wind"
const SNOW_SERVICE := &"snowfall"
const PLAYER_SERVICE := &"player"

const DEFAULT_MAP_PATH := "res://data/audio/ambience.tres"

## Below this a voice is stopped rather than played silently. Same figure and
## same reason as `MusicDirector.MIN_AUDIBLE`.
const MIN_AUDIBLE := 0.0015

## What a weather's warning arrives on. The payload's `sound` is a `StringName`
## authored in `data/weather/*.tres` -- no weather's name appears in this file.
const EVENT_TELL_STARTED := &"weather.tell_started"

## Wave 5's wires. Named as constants so retargeting them is an edit here and
## nowhere else, the shape `MusicDirector` already uses.
const EVENT_THREAT_DETECTED := &"threat.detected_player"
const EVENT_THREAT_LOST := &"threat.lost_player"

## `InteriorReveal` publishes these; its payload carries `reveal`, which answers
## `is_occupant_inside()`.
const EVENT_INTERIOR_ENTERED := &"interior.entered"
const EVENT_INTERIOR_EXITED := &"interior.exited"

@export var map_path := DEFAULT_MAP_PATH

## Off, and the whole thing is inert -- no voices, no bus, no sound. For a
## capture that wants a silent frame.
@export var enabled := true

## Whether this node may create its own audio bus. See `AmbienceMap`: the
## low-pass that makes a room a room needs somewhere to live, and an
## `AudioBusLayout` would mean a fourth agent writing `project.godot`. A test
## that does not want global audio state touched turns this off.
@export var manage_buses := true

## How often the fires group is re-read. A fire going out is an event nobody
## publishes yet, so this is a poll -- and a cheap one, since the group is
## normally two entries long.
@export var fire_rescan_seconds := 1.0

## Whether `ask_the_world()` runs itself on the first frame.
##
## ON in the game, because a director built after the stove was already lit, or
## after the player was already indoors, would otherwise never find out -- that
## is the trap this project has paid for twice. OFF for a test or a capture that
## is driving the state by hand and does not want the scene overruling it.
@export var ask_on_first_frame := true

var _map: AmbienceMap = null
var _bus = null
var _wind = null
var _snow = null

var _voices: Array[AudioStreamPlayer3D] = []
var _gains: Array[float] = []
## Where each bed layer's recording had got to when its window last closed.
var _resume_at: Array[float] = []
var _cue_voices: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}

var _inside := false
var _insideness := 0.0
var _danger := false
var _hush := 0.0
var _hold_remaining := 0.0

var _interiors: Array = []
var _fire_voices: Dictionary = {}
var _since_fire_scan := 0.0

var _bus_index := -1
var _filter: AudioEffectLowPassFilter = null
var _made_bus := false
var _subscribed := false
var _asked := false


# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	if _map == null:
		_map = _load_map_resource(map_path)
	if _bus == null:
		# Briefing trap 3: a project [autoload] entry is a node under /root and
		# never enters the engine's singleton registry. Getting this wrong leaves
		# `_bus` null forever and every event is swallowed with no diagnostic.
		set_event_bus(get_node_or_null("/root/EventBus"))
	_resolve_services()
	_ensure_bus()
	_build_voices()
	# The world is asked on the FIRST FRAME rather than here: a sibling that has
	# not had its own `_ready()` yet is not in its group and has not registered
	# its service, so a stove lit in `Stove._ready()` is invisible to a scan run
	# from this one. `WindSystem` and `SnowAccumulation` both arm themselves the
	# same way and for the same reason.


func _exit_tree() -> void:
	detach()
	# Quitting mid-gust otherwise leaves the AudioServer holding a playback and
	# with it the stream: "ERROR: N resources still in use at exit", which is a
	# dirty console and a failed run by this project's standard.
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
	for voice in _cue_voices:
		if is_instance_valid(voice):
			voice.stop()
	for key in _fire_voices:
		var voice = _fire_voices[key]
		if is_instance_valid(voice):
			voice.stop()
	_release_bus()


func _process(delta: float) -> void:
	advance(delta)


# --- wiring ------------------------------------------------------------------

## Returns how many layers were accepted. Zero means inert, which is a LEGAL
## state -- a scene may run before the audio has landed and it must not take the
## scene down with it.
func load_map(path := DEFAULT_MAP_PATH) -> int:
	var loaded := _load_map_resource(path)
	if loaded == null:
		return 0
	set_map(loaded)
	return _map.layers.size()


func _load_map_resource(path: String) -> AmbienceMap:
	# Asked before loading, because `ResourceLoader.load()` on a path that is not
	# there logs three ERROR lines before returning null -- and a dirty console is
	# a failed run whether or not the absence was handled correctly.
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AmbienceMap


func set_map(map: AmbienceMap) -> void:
	_map = map
	_build_gains()
	if is_inside_tree():
		_ensure_bus()
		_build_voices()


func map() -> AmbienceMap:
	return _map


func set_event_bus(bus) -> void:
	detach()
	_bus = bus
	attach()


func attach() -> void:
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_TELL_STARTED, _on_tell_started)
	_bus.subscribe(EVENT_THREAT_DETECTED, _on_threat_detected)
	_bus.subscribe(EVENT_THREAT_LOST, _on_threat_lost)
	_bus.subscribe(EVENT_INTERIOR_ENTERED, _on_interior_entered)
	_bus.subscribe(EVENT_INTERIOR_EXITED, _on_interior_exited)
	_subscribed = true


func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_TELL_STARTED, _on_tell_started)
	_bus.unsubscribe(EVENT_THREAT_DETECTED, _on_threat_detected)
	_bus.unsubscribe(EVENT_THREAT_LOST, _on_threat_lost)
	_bus.unsubscribe(EVENT_INTERIOR_ENTERED, _on_interior_entered)
	_bus.unsubscribe(EVENT_INTERIOR_EXITED, _on_interior_exited)
	_subscribed = false


func has_event_bus() -> bool:
	return _bus != null


## Duck-typed on the hooks, never on the types: this file must survive the
## deletion of any system it listens to.
##
## ---------------------------------------------------------------------------
## THIS IS NOT CALLED `set_wind()`, AND THAT IS NOT A STYLE CHOICE
## ---------------------------------------------------------------------------
## `set_wind` is a CLAIMED NAME in this project. `WindSystem._collect()` sweeps
## the whole tree for nodes that answer `set_wind` or `set_wind_strength` and
## drives every one of them with `consumer.set_wind(velocity())` -- a Vector3, in
## m/s^2 -- sixty times a second.
##
## So the first version of this file, whose injector WAS called `set_wind()`, was
## silently adopted as a wind consumer: the wind system overwrote `_wind` with a
## Vector3 on the first frame and every frame after, and since
## `is_instance_valid()` is false for a non-Object, `look_ahead_strength()` then
## returned 0.0 for the rest of the run. No error, no warning, and the whole bed
## simply never sounded.
##
## It was found by running the real scene and printing what the director had
## actually resolved -- the unit tests could not see it, because they inject the
## wind by hand and no `WindSystem` is anywhere near them. `set_wind_system` is
## the name `WeatherSystem` already uses for the same injection.
func set_wind_system(wind) -> void:
	_wind = wind


func set_snowfall(snow) -> void:
	_snow = snow


func _resolve_services() -> void:
	var registry := _registry()
	if registry == null:
		return
	if _wind == null:
		_wind = registry.get_service(WIND_SERVICE)
	if _snow == null:
		_snow = registry.get_service(SNOW_SERVICE)


## Trap 3 again, and the second half of it: an absolute path asked for from
## OUTSIDE the tree is an engine ERROR rather than a null.
func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


# --- asking, rather than only listening --------------------------------------

## The state that already existed before this node did.
##
## A node that only subscribes to a transition can never learn it, and this
## project has been bitten twice. Public so a test and a capture harness can both
## re-ask after building a scene.
func ask_the_world() -> void:
	_resolve_services()
	refresh_interiors()
	refresh_fires()


## Every building that can say whether the occupant is standing in it. Duck-typed
## on `is_occupant_inside()` rather than on `InteriorReveal`, so a later kind of
## shelter -- a cellar, a truck cab -- joins by answering the question.
func refresh_interiors() -> void:
	_interiors.clear()
	if not is_inside_tree():
		return
	_collect_interiors(get_tree().root)
	var inside := false
	for reveal in _interiors:
		if is_instance_valid(reveal) and bool(reveal.call(&"is_occupant_inside")):
			inside = true
			break
	set_inside(inside)


func _collect_interiors(node: Node) -> void:
	if node.has_method(&"is_occupant_inside"):
		_interiors.append(node)
	for child in node.get_children():
		_collect_interiors(child)


func interior_count() -> int:
	return _interiors.size()


## Whether the occupant is still inside ANY of them.
##
## Asked rather than assumed on the way out. Two buildings overlapping, or a
## reveal firing for somebody who is not the occupant, would otherwise put the
## listener outdoors while he is still standing in a room -- and the symptom
## would be the wind coming back on for no reason the player can see.
func reconsider() -> void:
	var still_inside := false
	for reveal in _interiors:
		if is_instance_valid(reveal) and bool(reveal.call(&"is_occupant_inside")):
			still_inside = true
			break
	set_inside(still_inside)


# --- state coming in ---------------------------------------------------------

func set_inside(inside: bool) -> void:
	_inside = inside


func is_inside() -> bool:
	return _inside


func insideness() -> float:
	return _insideness


## Wave 5's hook. Public rather than event-only so the threat system can seed it
## on ready the way this file seeds its own state -- the trap cuts both ways.
func set_danger(present: bool) -> void:
	if _danger == present:
		return
	_danger = present
	if not present:
		_hold_remaining = _map.danger_hold_seconds if _map != null else 0.0


func in_danger() -> bool:
	return _danger


## 0 the world is whole, 1 the top of it has gone.
func hush() -> float:
	return _hush


# --- the readings ------------------------------------------------------------

## What the wind will be doing in `lead_seconds`, which is what the bed plays.
##
## The look-ahead is taken against the ACTIVE profile rather than against the
## crossfade: mid-handover the model is a blend of two winds and the future of
## the outgoing one is not a thing anybody wants to hear. The incoming wind is
## the one that is arriving, which is the honest answer for a signal whose whole
## job is to be early.
##
## Falls back to the present reading whenever the future cannot be asked for --
## no wind, no profile, no `strength_at` -- so a stand-in with two methods on it
## still drives the whole bed.
func look_ahead_strength() -> float:
	if _wind == null or not is_instance_valid(_wind):
		return 0.0
	var now := float(_wind.call(&"strength"))
	var lead := _map.lead_seconds if _map != null else 0.0
	if lead <= 0.0:
		return now
	if not _wind.has_method(&"strength_at") or not _wind.has_method(&"active_profile"):
		return now
	var profile = _wind.call(&"active_profile")
	if profile == null:
		return now
	var at := 0.0
	if _wind.has_method(&"elapsed"):
		at = float(_wind.call(&"elapsed"))
	var ahead = _wind.call(&"strength_at", profile, at + lead)
	return float(ahead) if ahead is float or ahead is int else now


func snowfall_rate() -> float:
	if _snow == null or not is_instance_valid(_snow):
		return 0.0
	if not _snow.has_method(&"snowfall_rate"):
		return 0.0
	return float(_snow.call(&"snowfall_rate"))


## Which number a layer listens to. The two sources are the reason 冻雨 has an
## audible half at all -- see `AmbienceLayer.Source`.
func reading_for(layer: AmbienceLayer) -> float:
	if layer == null:
		return 0.0
	if layer.source == AmbienceLayer.Source.SNOWFALL:
		return snowfall_rate()
	return look_ahead_strength()


## Degrees about +Y that the wind BLOWS TO -- `WindProfile.prevailing_degrees`'
## convention, kept rather than flipped.
func heading_degrees() -> float:
	if _wind == null or not is_instance_valid(_wind) or not _wind.has_method(&"heading_degrees"):
		return 0.0
	return float(_wind.call(&"heading_degrees"))


## Where the bed sounds from: UPWIND, which is the opposite of where the wind is
## going. Static and pure so the geometry can be asserted with no tree, no
## camera and no audio device.
static func upwind_of(listener: Vector3, heading: float, radius: float) -> Vector3:
	var radians := deg_to_rad(heading)
	var travel := Vector3(cos(radians), 0.0, sin(radians))
	return listener - travel * radius


## The ear. The active camera when there is one, because that is what Godot
## actually mixes against; the player when there is not; this node when there is
## neither.
func listener_position() -> Vector3:
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			return camera.global_position
	var registry := _registry()
	if registry != null:
		var body := registry.get_service(PLAYER_SERVICE) as Node3D
		if body != null and body.is_inside_tree():
			return body.global_position
	return global_position if is_inside_tree() else position


func emitter_position() -> Vector3:
	var radius := _map.radius_for(_insideness) if _map != null else 0.0
	return upwind_of(listener_position(), heading_degrees(), radius)


# --- the loop ----------------------------------------------------------------

## One step. Public and carrying all of it, so the whole thing is drivable with
## no SceneTree -- the shape `WindSystem.advance()` and `CrowCalls.advance()`
## already use.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	if not _asked:
		_asked = true
		if ask_on_first_frame:
			ask_the_world()
	_advance_insideness(delta)
	_advance_hush(delta)
	_advance_bed(delta)
	_advance_fires(delta)
	_apply_filter()


func _advance_insideness(delta: float) -> void:
	var target := 1.0 if _inside else 0.0
	var tau := _map.interior_response_seconds if _map != null else 0.0
	_insideness = _eased(_insideness, target, tau, delta)


func _advance_hush(delta: float) -> void:
	var target := 1.0 if _danger else 0.0
	if not _danger and _hold_remaining > 0.0:
		# The bear wandering off is not the same moment as being safe.
		_hold_remaining = maxf(_hold_remaining - delta, 0.0)
		target = 1.0
	var tau := _map.danger_response_seconds if _map != null else 0.0
	_hush = _eased(_hush, target, tau, delta)


## Exponential ease, frame-rate independent: what is fixed is the fraction of the
## gap closed per second, not per frame. The same form the wind, the snow and the
## camera all use, so everything in the world arrives together.
static func _eased(value: float, target: float, tau: float, delta: float) -> float:
	if tau <= 0.0 or delta <= 0.0:
		return target
	return value + (target - value) * (1.0 - exp(-delta / tau))


func _advance_bed(delta: float) -> void:
	if _map == null:
		return
	var tau := _map.bed_response_seconds
	for index in range(_map.layers.size()):
		var layer := _map.layers[index]
		if layer == null:
			continue
		var target := AmbienceLayer.gain_at(layer, reading_for(layer))
		if layer.withdraws_near_danger:
			target *= 1.0 - _hush
		if index >= _gains.size():
			continue
		_gains[index] = _eased(_gains[index], target, tau, delta)
		_apply_voice(index, layer, delta)


func _apply_voice(index: int, layer: AmbienceLayer, delta: float) -> void:
	if index >= _voices.size():
		return
	var voice := _voices[index]
	if voice == null or not is_instance_valid(voice):
		return
	var gain := _gains[index]
	if not enabled or gain <= MIN_AUDIBLE:
		if voice.playing:
			_resume_at[index] = voice.get_playback_position()
			voice.stop()
		# The air did not stop while nobody was listening to it. Kept running
		# behind the silence so the layer is REVEALED rather than restarted -- see
		# `_advance_clock()`.
		_advance_clock(index, voice, delta)
		return
	voice.global_position = emitter_position()
	voice.panning_strength = _map.panning_for(_insideness)
	voice.unit_size = _map.unit_size
	voice.pitch_scale = AmbienceLayer.pitch_at(layer, reading_for(layer))
	voice.volume_db = linear_to_db(gain) + layer.gain_db + _map.trim_db_for(_insideness)
	if not voice.playing and voice.stream != null:
		voice.play(_resume_at[index])


## THE ARTEFACT THIS EXISTS TO PREVENT, measured in the real scene: over thirty
## seconds of the shipped valley wind the low bed crosses its own entry eight
## times. Every crossing stops a voice and starts it again -- and a `play()` with
## no argument restarts the recording at its first sample, so the player would
## hear the SAME two hundred milliseconds of wind eight times in half a minute.
## That is the fastest way to make a bed sound like a bed.
##
## So the position is remembered on the way out, and it keeps advancing while the
## layer is silent. The wind is then one continuous stream that the window
## reveals and hides, which is also what is physically true: the air did not stop
## because it fell below a threshold.
func _advance_clock(index: int, voice: AudioStreamPlayer3D, delta: float) -> void:
	if voice.stream == null or delta <= 0.0:
		return
	var length := voice.stream.get_length()
	if length <= 0.0:
		return
	_resume_at[index] = fposmod(_resume_at[index] + delta, length)


# --- fires -------------------------------------------------------------------

## One positional voice per member of the `&"fires"` group, while it is alight.
##
## Polled rather than subscribed because nothing publishes a fire going out --
## and because the group's membership ALREADY means "burning", so reading it is
## reading the state rather than remembering an event.
func _advance_fires(delta: float) -> void:
	_since_fire_scan += delta
	if _since_fire_scan < fire_rescan_seconds:
		_drive_fires()
		return
	_since_fire_scan = 0.0
	refresh_fires()


func refresh_fires() -> void:
	if not is_inside_tree() or _map == null or _map.fire_stream() == "":
		return
	var seen := {}
	for fire in get_tree().get_nodes_in_group(FIRE_GROUP):
		if not _is_alight(fire):
			continue
		seen[fire.get_instance_id()] = fire
		if not _fire_voices.has(fire.get_instance_id()):
			var voice := _new_fire_voice()
			if voice == null:
				continue
			_fire_voices[fire.get_instance_id()] = voice
	for key in _fire_voices.keys():
		if seen.has(key):
			continue
		# Untyped, then checked -- the shape `_stop_everything()` above already
		# uses on this same dictionary, and briefing trap 18. A typed local
		# validates the instance AT the assignment, so it would throw on exactly
		# the freed voice this `is_instance_valid()` exists to catch, and abort
		# the function before the guard could run.
		var voice = _fire_voices[key]
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
		_fire_voices.erase(key)
	_drive_fires()


func _is_alight(fire) -> bool:
	if fire == null or not is_instance_valid(fire):
		return false
	if not fire.has_method(&"is_lit") or not fire.has_method(&"fire_position"):
		return false
	return bool(fire.call(&"is_lit"))


func _drive_fires() -> void:
	if _map == null:
		return
	for key in _fire_voices:
		# Checked before it is narrowed, briefing trap 18. The typed local is
		# kept, but only on the far side of the guard.
		var raw = _fire_voices[key]
		if raw == null or not is_instance_valid(raw):
			continue
		var voice: AudioStreamPlayer3D = raw
		var fire = instance_from_id(key)
		if not _is_alight(fire):
			voice.stop()
			continue
		var at = fire.call(&"fire_position")
		if at is Vector3:
			voice.global_position = at
		voice.volume_db = _map.fire_gain_db
		if not enabled:
			voice.stop()
		elif not voice.playing and voice.stream != null:
			voice.play()


func _new_fire_voice() -> AudioStreamPlayer3D:
	var stream := _stream(_map.fire_stream())
	if stream == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.name = "Fire%d" % _fire_voices.size()
	voice.stream = stream
	voice.bus = _bus_name(_map.fire_bus)
	voice.unit_size = _map.fire_unit_size
	voice.max_distance = _map.fire_audible_m
	voice.volume_db = _map.fire_gain_db
	add_child(voice)
	return voice


func fire_voice_count() -> int:
	return _fire_voices.size()


# --- one-shots ---------------------------------------------------------------

## A weather's warning, arriving on the id its own `.tres` authored.
##
## Positional, at the same upwind point the bed sounds from. A HUD-less game
## gets to say WHICH WAY the weather is coming from for free, and a storm that
## arrives from a direction is a storm in a place rather than a state change.
##
## False when there is nothing to play, so a missing file is distinguishable from
## a cue that fired -- silence alone is not.
func play_cue(cue_id: StringName) -> bool:
	if not enabled or _map == null or cue_id == &"":
		return false
	# An AudioStreamPlayer cannot play outside the tree: the engine refuses with
	# "Playback can only happen when a node is inside the scene tree", and saying
	# yes here would be this project's fifth false-PASS all over again.
	if not is_inside_tree():
		return false
	var path := _map.stream_for(cue_id)
	if path == "":
		return false
	var stream := _stream(path)
	if stream == null:
		return false
	var voice := _free_cue_voice()
	voice.stream = stream
	voice.global_position = emitter_position()
	voice.panning_strength = _map.panning_for(_insideness)
	voice.unit_size = _map.unit_size
	var declared := _map.cue(cue_id)
	var gain := declared.gain_db if declared != null else 0.0
	var pitch := declared.pitch_scale if declared != null else 1.0
	var spread := absf(declared.pitch_spread) if declared != null else 0.0
	voice.volume_db = gain + _map.trim_db_for(_insideness)
	voice.pitch_scale = pitch * (randf_range(1.0 - spread, 1.0 + spread) if spread > 0.0 else 1.0)
	voice.play()
	return true


func _free_cue_voice() -> AudioStreamPlayer3D:
	for voice in _cue_voices:
		if not voice.playing:
			return voice
	var made := AudioStreamPlayer3D.new()
	made.name = "Cue%d" % _cue_voices.size()
	made.bus = _bus_name(_map.bus)
	made.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(made)
	_cue_voices.append(made)
	return made


func cue_voice_count() -> int:
	return _cue_voices.size()


# --- voices ------------------------------------------------------------------

## The DECISIONS, separated from the output.
##
## `MusicDirector` makes the same split and gives the same reason: a headless run
## has no audio device, and the deciding still has to happen and still has to be
## testable. Here it also means a director outside the tree -- which is every
## unit test that is not about playback -- still computes a whole bed, and the
## only thing missing is the sound.
func _build_gains() -> void:
	_gains.clear()
	_resume_at.clear()
	if _map == null:
		return
	for _index in range(_map.layers.size()):
		_gains.append(0.0)
		_resume_at.append(0.0)


func _build_voices() -> void:
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_voices.clear()
	if _map == null:
		return
	if _gains.size() != _map.layers.size():
		_build_gains()
	for index in range(_map.layers.size()):
		var layer := _map.layers[index]
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Bed_%s" % (layer.layer_id if layer != null else index)
		voice.bus = _bus_name(_map.bus)
		voice.unit_size = _map.unit_size
		voice.panning_strength = _map.panning
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.volume_db = -80.0
		if layer != null:
			voice.stream = _stream(_map.stream_for_layer(layer))
		add_child(voice)
		_voices.append(voice)


func voice(index: int) -> AudioStreamPlayer3D:
	return _voices[index] if index >= 0 and index < _voices.size() else null


func voice_count() -> int:
	return _voices.size()


## Where a layer's recording has got to. For the test that pins the resume.
func resume_position(index: int) -> float:
	return _resume_at[index] if index >= 0 and index < _resume_at.size() else 0.0


func bed_gain(index: int) -> float:
	return _gains[index] if index >= 0 and index < _gains.size() else 0.0


## The whole bed, as one number -- the loudest layer sounding. For a test and for
## a capture that wants to print what the frame sounded like beside what it
## looked like.
func bed_level() -> float:
	var most := 0.0
	for gain in _gains:
		most = maxf(most, gain)
	return most


func is_silent() -> bool:
	return bed_level() <= MIN_AUDIBLE


## A bed layer has to LOOP or it is a one-shot that happens to be long, and the
## gap when it ends is the most audible mistake this system could make.
##
## Loaded with CACHE_MODE_IGNORE so the loop flag is set on THIS copy: briefing
## trap 6 -- `ResourceLoader` caches by path and hands every caller the same
## instance, so setting it on a shared one would be setting it for everybody,
## including a footstep that must not loop.
func _stream(path: String) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _streams.has(path):
		return _streams[path]
	var stream := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	if stream == null:
		return null
	_make_it_loop(stream)
	_streams[path] = stream
	return stream


## Forced here rather than left to the `.import` file, and that is a decision
## rather than a convenience: the importer's default is loop OFF for every format
## this project accepts, and the failure it causes -- a bed that stops thirty
## seconds into a run and never comes back -- is silent, is not reproducible in a
## screenshot, and is attributed to the wrong system by everybody who hears it.
##
## Safe to do because `_stream()` loads with CACHE_MODE_IGNORE. Setting a loop on
## a SHARED instance would be setting it for every other caller of the same path,
## including a footstep that must not loop (briefing trap 6).
static func _make_it_loop(stream: AudioStream) -> void:
	if stream.has_method(&"set_loop"):
		stream.call(&"set_loop", true)
		return
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	# In FRAMES, which `data.size()` is not -- that is bytes, and handing it over
	# would ask the playback to loop past the end of the sample.
	#
	# And `frames - 1`, which is what the WAV importer itself produces for
	# `edit/loop_end=-1`: printed back off an imported bed at 16.000 s / 44100 Hz
	# it reads 705599, not 705600. The convention is the INDEX OF THE LAST SAMPLE
	# PLAYED, and being one out is exactly the kind of thing that ticks.
	var frames := int(wav.get_length() * float(wav.mix_rate))
	if frames <= 1:
		return
	wav.loop_begin = 0
	wav.loop_end = frames - 1
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


# --- the bus -----------------------------------------------------------------

## Built here rather than shipped as an `AudioBusLayout`, because a layout needs
## `audio/buses/default_bus_layout` in `project.godot` -- the most contested file
## in this repository after `scenes/main.tscn`.
##
## Idempotent by name, and removed again on the way out only if this node was the
## one that made it. Two directors in one process share the bus rather than
## fighting over it, which is what a test suite does.
func _ensure_bus() -> void:
	_bus_index = -1
	_filter = null
	if not manage_buses or _map == null:
		return
	var wanted := String(_map.bus)
	if wanted == "" or wanted == "Master":
		return
	var index := AudioServer.get_bus_index(wanted)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, wanted)
		_made_bus = true
	_bus_index = AudioServer.get_bus_index(wanted)
	if _bus_index == -1:
		return
	for slot in range(AudioServer.get_bus_effect_count(_bus_index)):
		var effect := AudioServer.get_bus_effect(_bus_index, slot)
		if effect is AudioEffectLowPassFilter:
			_filter = effect as AudioEffectLowPassFilter
			break
	if _filter == null:
		_filter = AudioEffectLowPassFilter.new()
		_filter.cutoff_hz = _map.exterior_cutoff_hz
		AudioServer.add_bus_effect(_bus_index, _filter)


func _release_bus() -> void:
	if not _made_bus or _map == null:
		return
	var index := AudioServer.get_bus_index(String(_map.bus))
	if index != -1:
		AudioServer.remove_bus(index)
	_made_bus = false
	_bus_index = -1
	_filter = null


## The wall, as one number. Public so a test can read the acoustic rather than
## infer it from a volume.
## The bus a voice may actually be put on.
##
## A player assigned to a bus that does not exist is an engine ERROR, and by this
## project's standard a stray ERROR is a failed run whatever the assertions said.
## `manage_buses` off -- a test, a capture -- means the bed's bus was never
## created, and Master is the honest place for the sound to come out.
func _bus_name(wanted: StringName) -> StringName:
	if wanted == &"" or AudioServer.get_bus_index(String(wanted)) == -1:
		return &"Master"
	return wanted


func cutoff_hz() -> float:
	if _filter != null:
		return _filter.cutoff_hz
	return _map.cutoff_for(_insideness) if _map != null else 0.0


func _apply_filter() -> void:
	if _filter == null or _map == null:
		return
	_filter.cutoff_hz = _map.cutoff_for(_insideness)


# --- event adapters ----------------------------------------------------------
#
# EventBus dispatches with exactly one argument, always. Zero or two parameters
# here is a runtime argument-count error at dispatch, not a parse error.

func _on_tell_started(payload) -> void:
	if not (payload is Dictionary):
		return
	var sound = payload.get("sound", &"")
	play_cue(sound if sound is StringName else StringName(str(sound)))


func _on_threat_detected(_payload) -> void:
	set_danger(true)


func _on_threat_lost(_payload) -> void:
	set_danger(false)


func _on_interior_entered(_payload) -> void:
	set_inside(true)


func _on_interior_exited(_payload) -> void:
	reconsider()
