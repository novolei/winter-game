class_name CrowCalls
extends Node3D

## The caws, when a flock goes up.
##
## ---------------------------------------------------------------------------
## THE AUDIO IS HERE NOW -- AND THE OWNER STILL CANNOT HEAR IT
## ---------------------------------------------------------------------------
## This header used to say at length that the folder was empty and that the
## system shipped silent. That stopped being true at `7cbe595`: there are three
## caws in `CALL_FOLDER`, they are imported, and everything in this file works.
## The schedule draws, the emitters are built, `play()` is accepted, `playing`
## reports true and the voices track their birds.
##
## **And not one sample has ever reached the speakers.** Measured on the real
## scene at HEAD, on the master bus peak rather than on `play()`'s return value:
##
##     a caw at the player, max_distance = 60      ->  -200.00 dB   (silence)
##     the same caw placed ON the listener          ->    -8.60 dB
##
## The cause is NOT in this file, and this note is here so the next reader does
## not spend a day in it. `AudioStreamPlayer3D.max_distance` is a hard cutoff
## measured **from the listener**, the listener is the `Camera3D`, and the camera
## rides a 90 m boom (`src/rendering/camera_rig.gd:49`). 60 < 90.71, so the
## engine mutes every caw outright. `audible_m` below is correct as authored --
## it is a PLAYER-relative design distance, and it is right the day the listener
## sits on the player. **Do not "fix" it by raising the number**; that is
## compensating for a position error with a constant, which is briefing trap 13.
##
## The same arithmetic silences `dog.bark` (60 m), `dog.whimper` (45), `dog.whine`
## (35), `dog.growl` (14) and the hearth (24). The ambience bed survives only
## because it declares no `max_distance` at all. Written up for the owner in
## `.superpowers/sdd/wave3/task-w3-bird-system-explained.md`; the remedy is one
## `AudioListener3D` and it re-levels the whole mix, so it is his call.
##
## What this file does own, and gets right: the folder IS the data. Drop caws in
## and they play -- no `.gd` change, no `.tres` to generate, no list to keep in
## step, which is the shape briefing constraint 4 asks for.
##
## ---------------------------------------------------------------------------
## SPARSE AND IRREGULAR -- NOT A CHORUS
## ---------------------------------------------------------------------------
## The owner's note is precise about the shape and it is a shape a naive
## implementation gets wrong in the same way every time: fire one sound per bird
## on the frame the flock leaves, and five crows caw in unison, which reads as a
## single stereo event rather than as five animals.
##
## So the schedule is authored as a RHYTHM, not as a per-bird trigger:
##
##   one bird           the first call, almost at once
##   then two,          close enough to overlap, from two different birds
##   overlapping
##   then a gap         long enough to be a silence rather than a rest
##   then a last one    from whichever bird is furthest away by then, so it is
##   already distant    quiet and off to one side before the shot ends
##
## Not every burst gets all four. `_schedule()` draws how many, and a burst of
## one bird cannot overlap with itself.
##
## The emitters are POSITIONAL and each one follows its own bird, so the calls
## scatter as the flock does and recede as it climbs out. That is the half a
## non-positional implementation cannot have, and it is the half the owner asked
## for by name.

## Where a caw goes. Anything Godot can import as an AudioStream counts.
const CALL_FOLDER := "res://assets/audio/wildlife/crow"
const CALL_SUFFIXES := [".wav", ".ogg", ".mp3"]

## No custom bus layout ships with this project; the same note is in
## `src/ui/ui_audio.gd`. A wildlife bus is the right home for these the day
## anything needs to duck them.
@export var bus: StringName = &"Master"

## How many calls a burst gets. Sparse: five birds do not make five calls.
@export var fewest := 1
@export var most := 4

## The rhythm, in seconds. See the header -- these are the four slots, and each
## is drawn inside its own range so the pattern is never metrical.
@export var first_call_min := 0.05
@export var first_call_max := 0.25
## The overlapping pair: how long after the first, and how far apart the two are.
@export var answer_min := 0.18
@export var answer_max := 0.42
@export var overlap_min := 0.06
@export var overlap_max := 0.19
## The silence, and then the far one.
@export var gap_min := 0.55
@export var gap_max := 1.15

## Metres. Beyond this a caw is not worth an emitter.
@export var audible_m := 60.0

## Off, and nothing is scheduled at all.
@export var enabled := true

@export var random_seed := 0

const EVENT_SCATTERED := &"wildlife.crows_scattered"

var _rng := RandomNumberGenerator.new()
var _streams: Array[AudioStream] = []
var _looked := false
## `{at, bird, played}` per call, and the birds this burst is about.
var _pending: Array = []
var _birds: Array[Crow] = []
var _clock := 0.0
var _voices: Array[AudioStreamPlayer3D] = []
var _following: Array = []
var _bus = null
var _flock: CrowFlock = null
var _subscribed := false


func _ready() -> void:
	seed_rng()
	attach()


## Hashed and shaken out rather than assigned -- on 4.7.1 the fourth `randf()`
## after seeding lands in 0.09..0.24 whatever the seed, and a four-call burst
## draws exactly four times. Written up in full in
## `src/rendering/startle_shot.gd`. Public so a test can reseed the same way
## rather than reaching for `_rng` and getting the unwarmed stream.
func seed_rng() -> void:
	_rng.seed = hash(random_seed) if random_seed != 0 else int(Time.get_ticks_usec())
	for _discard in range(8):
		_rng.randf()


func _exit_tree() -> void:
	detach()


func set_event_bus(bus_node) -> void:
	_bus = bus_node


func set_crow_flock(flock: CrowFlock) -> void:
	_flock = flock


## Listens for the event the flock already publishes and asks the flock which
## birds went up. No edit to `crow_flock.gd`: the event carries the fact and the
## parent carries the birds, and a `CrowCalls` that is not under a flock simply
## never hears anything worth announcing.
func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			# Briefing trap 3: an autoload is a node under /root, never an engine
			# singleton.
			_bus = get_node_or_null("/root/EventBus")
		if _flock == null:
			_flock = get_parent() as CrowFlock
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_SCATTERED, _on_scattered)
	_subscribed = true


func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_SCATTERED, _on_scattered)
	_subscribed = false


func _on_scattered(_payload) -> void:
	if _flock == null or not is_instance_valid(_flock):
		return
	announce(_flock.crows())


## Every caw on disk. Empty today -- see the header.
##
## Read once and cached: a burst is not the moment to be hitting the filesystem,
## and the folder does not change while the game runs.
func calls() -> Array[AudioStream]:
	if _looked:
		return _streams
	_looked = true
	var directory := DirAccess.open(CALL_FOLDER)
	if directory == null:
		return _streams
	# Briefing trap 17: running from source, `get_files()` lists the asset AND its
	# `.import` sidecar; an exported build lists only the sidecar. Trimming makes
	# both forms name the same asset, which is what makes one line serve both
	# builds -- and is exactly why the source tree loaded every caw TWICE.
	# `call_count()` reported **6 for the 3 files on disk** until `seen` existed.
	#
	# It never errored, which is the whole reason it lasted: a uniform draw over a
	# doubled list is still uniform, so it sounded correct. The shape recurs in
	# anything that enumerates a directory -- icon sets, animation libraries,
	# weather data -- and the sidecar count is now two (`.uid` as well), so a
	# whitelist of wanted suffixes plus this set is the durable form rather than
	# a blacklist of known-bad ones.
	var seen := {}
	for name in directory.get_files():
		var file := name.trim_suffix(".import")
		var wanted := false
		for suffix in CALL_SUFFIXES:
			if file.to_lower().ends_with(suffix):
				wanted = true
				break
		if not wanted or seen.has(file):
			continue
		seen[file] = true
		var stream := ResourceLoader.load("%s/%s" % [CALL_FOLDER, file]) as AudioStream
		if stream != null:
			_streams.append(stream)
	return _streams


## How many caws are on disk. Public so the report and the gate can both say the
## honest number rather than implying one.
func call_count() -> int:
	return calls().size()


## A flock has gone up. Draw the rhythm and start the clock.
##
## Takes the birds rather than positions, because a call has to FOLLOW the crow
## that made it -- a caw fixed where the bird was when it opened its beak is a
## sound left behind by an animal that has flown thirty metres.
func announce(birds: Array) -> int:
	_pending.clear()
	_birds.clear()
	_clock = 0.0
	if not enabled or birds.is_empty():
		return 0
	for bird in birds:
		# Checked BEFORE the cast, not after it. `as` is type-checked too: on a
		# bird the caller's list still names but the flock has already freed, it
		# throws `Trying to cast a freed object` and aborts this whole function --
		# so one dead bird costs the entire burst rather than one caw, and
		# `announce()` returns 0 having scheduled nothing. `_birds` is
		# `Array[Crow]`, and pushing a freed instance into a typed array is a
		# second error of the same family a line later.
		if bird == null or not is_instance_valid(bird):
			continue
		var crow := bird as Crow
		if crow != null:
			_birds.append(crow)
	if _birds.is_empty():
		return 0
	_pending = _schedule(_birds.size())
	return _pending.size()


## The rhythm. Pure, and separate from anything that plays it, so the SHAPE can
## be asserted with no audio on disk and no tree -- which is the only part of
## this feature that can be tested today.
##
## Returns `[{at, bird}]`, ordered.
func _schedule(birds: int) -> Array:
	var wanted := mini(_rng.randi_range(maxi(fewest, 1), maxi(most, fewest)), maxi(birds, 1) + 1)
	var order := _speakers(birds)
	var found: Array = []
	var at := _rng.randf_range(first_call_min, first_call_max)
	found.append({"at": at, "bird": order[0], "played": false})
	if wanted >= 2:
		# The answer, and then its overlap. Two birds close enough that the second
		# starts before the first has finished, which is what makes it read as an
		# exchange rather than as a sequence.
		at += _rng.randf_range(answer_min, answer_max)
		found.append({"at": at, "bird": order[1 % order.size()], "played": false})
	if wanted >= 3 and birds >= 2:
		at += _rng.randf_range(overlap_min, overlap_max)
		found.append({"at": at, "bird": order[2 % order.size()], "played": false})
	if wanted >= 4:
		# The silence, then one already distant.
		at += _rng.randf_range(gap_min, gap_max)
		found.append({"at": at, "bird": order[3 % order.size()], "played": false})
	return found


## Which birds speak, in what order -- drawn without replacement while there are
## birds left, so the overlapping pair is never one crow answering itself.
func _speakers(birds: int) -> Array:
	var pool: Array = []
	for index in range(maxi(birds, 1)):
		pool.append(index)
	for index in range(pool.size() - 1, 0, -1):
		var swap := _rng.randi_range(0, index)
		var held = pool[index]
		pool[index] = pool[swap]
		pool[swap] = held
	return pool


## What is still to come. For a test, and for a capture that prints the schedule
## alongside the frames.
func pending() -> Array:
	return _pending.duplicate(true)


func voices() -> Array[AudioStreamPlayer3D]:
	return _voices


## How many emitters are still tracking a bird. Public because "the list drains"
## is an invariant that cannot be asserted from the outside otherwise, and an
## entry that is only ever skipped rather than removed is walked for the rest of
## the session -- which is a cost and an error that nothing else can see.
##
## The count, not the list: handing out `_following` would hand out the raw node
## references this file exists to stop being careless with.
func following_count() -> int:
	return _following.size()


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything, the same shape as `CrowFlock.advance()`.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_clock += delta
	_follow()
	if _pending.is_empty():
		return
	for entry in _pending:
		if entry["played"] or _clock < float(entry["at"]):
			continue
		entry["played"] = true
		_speak(int(entry["bird"]))


## Every voice tracks the bird that opened it, so the sound scatters with the
## flock and recedes as it climbs out. A bird that has been freed leaves its
## voice where it last was rather than dragging it to the origin.
##
## ---------------------------------------------------------------------------
## WHY EVERY REFERENCE IS READ AS `Variant` AND NARROWED ONLY AFTER THE CHECK
## ---------------------------------------------------------------------------
## This used to read `var crow: Crow = pair["crow"]` and check validity on the
## next line, and it threw in the owner's own play session -- `CrowCalls._follow:
## Trying to assign invalid previously freed instance`, every frame from 0:04:32
## onwards. **GDScript validates the instance AT the assignment** when the source
## expression is statically `Variant`, which a `Dictionary` value always is. So
## the assignment threw and aborted `_follow()`, and the guard on the next line
## -- correct, deliberate, and visible in review -- could never run.
##
## Worse than one silent emitter: the abort took the REST of the list with it,
## so one freed bird at the head stopped every other bird's voice from being
## followed at all.
##
## A `Variant` local takes no check, so the guard below is reachable. Measured on
## 4.7.1; briefing trap 18 carries the table of which shapes throw and which do
## not.
##
## ---------------------------------------------------------------------------
## AND THE ENTRY IS DROPPED, NOT SKIPPED
## ---------------------------------------------------------------------------
## Nothing can make a freed bird followable again, so an entry that is only
## `continue`d is walked on every frame for the rest of the run. `_following` had
## no removal path at all -- one flight's worth of caws left permanent residents,
## which is why the owner's log repeats rather than fires once.
##
## Iterated backwards so a `remove_at()` cannot shift an index this pass has not
## reached yet.
func _follow() -> void:
	for index in range(_following.size() - 1, -1, -1):
		var pair: Dictionary = _following[index]
		var raw_voice: Variant = pair["voice"]
		var raw_crow: Variant = pair["crow"]
		var voice_lost: bool = raw_voice == null or not is_instance_valid(raw_voice)
		var crow_lost: bool = raw_crow == null or not is_instance_valid(raw_crow)
		if voice_lost or crow_lost:
			_following.remove_at(index)
			continue
		var voice: AudioStreamPlayer3D = raw_voice
		var crow: Crow = raw_crow
		# Gone but not yet freed. The bird is on its last frame and the flock
		# frees it at the end of this one, so it is skipped here and removed by
		# the branch above on the next pass. Not dropped now, because GONE is a
		# state and a freed instance is a fact -- only the second cannot be undone.
		if crow.is_gone():
			continue
		voice.global_position = crow.where()


func _speak(bird: int) -> void:
	if bird < 0 or bird >= _birds.size():
		return
	# THIS ONE IS SAFE AS WRITTEN AND IT DOES NOT LOOK IT -- do not rewrite it to
	# match `_follow()`. `_birds` is `Array[Crow]`, so the subscript is ALREADY
	# statically typed and the compiler emits no instance check at all; a bird
	# freed since `announce()` filed it arrives here as `<Freed Object>`, and the
	# guard on the next line catches it exactly as written. Measured on 4.7.1.
	#
	# The rule is about the SOURCE being `Variant`, not about the destination
	# being typed -- which is why the two lines in `_follow()` threw and this one
	# never has.
	var crow := _birds[bird]
	if crow == null or not is_instance_valid(crow):
		return
	var streams := calls()
	if streams.is_empty():
		# Nothing on disk. The schedule still ran, and that is all it can do.
		return
	if not is_inside_tree():
		return
	var at := crow.where()
	if _player_position().distance_to(at) > audible_m:
		return
	var voice := _free_voice()
	voice.stream = streams[_rng.randi_range(0, streams.size() - 1)]
	voice.global_position = at
	# Each caw a little off the last. Fifteen files played at one pitch is still
	# fifteen files, and a flock is not a sample library.
	voice.pitch_scale = _rng.randf_range(0.92, 1.09)
	voice.play()
	_following.append({"voice": voice, "crow": crow})


func _free_voice() -> AudioStreamPlayer3D:
	for voice in _voices:
		if not voice.playing:
			return voice
	var made := AudioStreamPlayer3D.new()
	made.bus = bus
	made.max_distance = audible_m
	made.unit_size = 8.0
	add_child(made)
	_voices.append(made)
	return made


func _player_position() -> Vector3:
	var registry = get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return global_position
	var found := registry.get_service(&"player") as Node3D
	if found == null or not found.is_inside_tree():
		return global_position
	return found.global_position
