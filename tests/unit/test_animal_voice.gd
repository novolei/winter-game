extends TestCase

## The dog's voice: the map, the emitters, and the wiring to the takes.
##
## ---------------------------------------------------------------------------
## EVERY PLAYBACK ASSERTION HERE IS `is_playing()`, IN THE TREE
## ---------------------------------------------------------------------------
## This project's fifth false-PASS was a test that asserted 44 successful
## `play()` calls while the engine refused every one of them, because an
## AudioStreamPlayer outside the scene tree cannot play and says so only in the
## console. So the voice goes under `/root` in `before_each`, comes out and is
## freed in `after_each`, and no test here believes a return value about sound.
##
## ---------------------------------------------------------------------------
## WHAT SIMULATED TIME CAN AND CANNOT SHOW
## ---------------------------------------------------------------------------
## `advance(delta)` moves this node's own clock; the AudioServer moves on the
## wall clock. So a tight loop can prove a sound STARTED -- starting is
## synchronous -- and cannot prove one FINISHED. Nothing here asserts the second;
## `test_wildlife_calls.gd` carries the same note and the reasoning.

const VoiceScript := preload("res://src/entities/wildlife/animal_voice.gd")

const MAP_PATH := "res://data/audio/dog_voice.tres"
const FRAME := 1.0 / 60.0

var _voice: AnimalVoice = null
var _animal: Node3D = null
var _player: AnimationPlayer = null
var _map: AnimalVoiceMap = null
var _heard: Array = []


func before_each() -> void:
	# CACHE_MODE_IGNORE: `ResourceLoader` hands every caller the same instance
	# (briefing trap 6), and a test that wrote to a call would edit the shipped
	# resource for every test after it.
	_map = ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimalVoiceMap
	_heard = []
	_animal = Node3D.new()
	_animal.name = "Animal"
	_root().add_child(_animal)
	_voice = VoiceScript.new()
	_voice.random_seed = 4711
	_voice.map_path = MAP_PATH
	# Before add_child, so `_ready()` finds a bus already set and does not reach
	# for the live autoload -- which would leave this test's subscriptions in a
	# singleton every later test shares.
	_voice.set_event_bus(_Bus.new(self))
	_animal.add_child(_voice)


func after_each() -> void:
	if _voice != null:
		for emitter in _voice.voices():
			emitter.stop()
	_voice = null
	_player = null
	if _animal != null:
		_root().remove_child(_animal)
		# Frees the voice, its emitters and the AnimationPlayer with it.
		_animal.free()
		_animal = null


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## A stand-in for the autoload. `emit_event` is the whole contract.
class _Bus:
	extends RefCounted
	var _test

	func _init(test) -> void:
		_test = test

	func emit_event(event: StringName, payload = null) -> void:
		_test._heard.append({"event": event, "payload": payload})


## An AnimationPlayer holding one take under the name a `Dog` would use --
## library `dog`, take named for the STATE, which is how `DogAnimations.build()`
## stores them and therefore what `current_animation` reads back as.
func _give_animal_a_take(state: String) -> AnimationPlayer:
	var take := Animation.new()
	take.length = 1.0
	var library := AnimationLibrary.new()
	library.add_animation(state, take)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("dog", library)
	_animal.add_child(player)
	_player = player
	return player


# --- the map -----------------------------------------------------------------


func test_the_map_ships() -> void:
	assert_not_null(_map, "%s must exist -- run tools/generate_dog_voice.gd" % MAP_PATH)
	if _map == null:
		return
	assert_true(_map.calls.size() >= 4, "the map declares only %d call(s)" % _map.calls.size())


## A call whose file is missing plays nothing and says nothing, and silence is
## indistinguishable from "this animal has no sound for that yet". A DANGLING
## path has to fail here; an EMPTY list is a different thing and is legal.
func test_no_call_points_at_a_file_that_is_not_there() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for call in _map.calls:
		for path in call.stream_paths:
			assert_true(
				ResourceLoader.exists(path),
				"%s names %s, which is not on disk" % [call.call_id, path]
			)


## The growl is the whole of the warning mechanic, and it shipped one commit
## declared-and-silent because the first supplied take had no growl in it. The
## gate was written then to keep passing on the day one landed; this is that day,
## so it now also asserts the entry is VOICED. Going back to silent would be a
## regression, not a state to tolerate.
func test_the_growl_is_wired_to_its_take_and_has_a_voice() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var growl := _map.call_named(&"dog.growl")
	assert_not_null(growl, "dog.growl is not in the map at all")
	if growl == null:
		return
	assert_true(
		growl.takes.has(&"growl"),
		"dog.growl is not wired to the `growl` take, so the animation would play mute"
	)
	assert_true(
		growl.is_voiced(),
		"dog.growl has no file; a dog growling at something unseen is the best warning the roster has"
	)
	assert_eq(
		_map.voiced_count(), _map.calls.size(),
		"%d of %d calls still have no file" % [
			_map.calls.size() - _map.voiced_count(), _map.calls.size()]
	)


## THE DEFECT THAT ARRIVED WITH THE FILE, AND COULD NOT EXIST BEFORE IT.
##
## `growl` is a LOOPING take of 3.042 s, so `notice_take()` sees the animation
## clock go backwards every 3.042 s and asks to speak again. The cooldown was
## 3.2 s -- written as "just over the loop, so a held growl re-voices once per
## cycle", which is exactly backwards: 3.042 < 3.2, so every restart was refused
## and only every SECOND one got through. A held growl would have voiced every
## 6.084 s from clips averaging 2.64 s, leaving three and a half seconds of
## silence in the middle of a dog that is visibly still growling.
##
## Nothing errors either way. It was invisible while the call had no file.
func test_a_held_growl_re_voices_every_cycle_of_its_own_take() -> void:
	var growl := _map.call_named(&"dog.growl")
	assert_not_null(growl)
	if growl == null:
		return
	var loop := DogAnimations.length_of(DogAnimations.GOLDEN_RETRIEVER, DogAnimations.GROWL)
	assert_true(loop > 0.0, "the golden retriever has no growl take to measure against")
	assert_true(
		growl.cooldown_s < loop,
		"the growl cooldown is %.2f s against a %.2f s looping take -- every other cycle is refused and the dog falls silent while still growling" % [
			growl.cooldown_s, loop]
	)
	# And not so short that a behaviour calling say() every frame can stutter it.
	assert_true(
		growl.cooldown_s > 1.0,
		"a %.2f s cooldown lets a held growl retrigger over itself" % growl.cooldown_s
	)


## Measured against the real take rather than asserted: play the looping growl,
## drive it past two loop boundaries, and count what the dog actually said.
func test_a_looping_take_speaks_again_when_it_comes_round() -> void:
	var take := Animation.new()
	take.length = 3.042
	take.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation("growl", take)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("dog", library)
	_animal.add_child(player)
	_player = player

	_voice.watch(player)
	player.play("dog/growl")
	_voice.advance(FRAME)
	assert_eq(_voice.last_asked(), &"dog.growl", "the growl take did not reach the voice")
	var first := _voice.spoken_count()
	assert_true(first > 0, "a growling dog made no sound")

	# Two full cycles of the take, driven the way the tree would drive it.
	var elapsed := 0.0
	while elapsed < 3.042 * 2.0 + 0.2:
		player.advance(FRAME)
		_voice.advance(FRAME)
		elapsed += FRAME
	assert_true(
		_voice.spoken_count() >= first + 2,
		"two loops of a %.3f s take produced %d utterance(s) in total; a held growl goes quiet between cycles" % [
			take.length, _voice.spoken_count()]
	)


## A growl carries a fraction of a bark's distance, and that is the design rather
## than a mixing accident: a growl heard across the valley is not a warning about
## a place. `AnimalCall`'s own header makes the same argument.
func test_the_growl_is_the_shortest_ranged_thing_the_dog_says() -> void:
	var growl := _map.call_named(&"dog.growl")
	assert_not_null(growl)
	if growl == null:
		return
	for other in _map.calls:
		if other == null or other.call_id == &"dog.growl":
			continue
		assert_true(
			growl.carry_m < other.carry_m,
			"the growl carries %.1f m and %s carries %.1f m" % [
				growl.carry_m, other.call_id, other.carry_m]
		)
		# Not just cut off sooner -- quieter at every distance inside its range,
		# which is what `unit_size` controls. Cutting off at 14 m while being the
		# loudest thing within 14 m would still read as a bark.
		assert_true(
			growl.unit_size < other.unit_size,
			"the growl falls off like %s (unit %.1f vs %.1f)" % [
				other.call_id, growl.unit_size, other.unit_size]
		)


## Two calls claiming one take is an authoring mistake that would let the order
## of an array decide what the dog says.
func test_no_two_calls_claim_the_same_take() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var claimed: Dictionary = {}
	for call in _map.calls:
		for take in call.takes:
			assert_false(
				claimed.has(take),
				"the take `%s` is claimed by both %s and %s" % [
					take, claimed.get(take, &""), call.call_id]
			)
			claimed[take] = call.call_id


# --- it actually makes a sound ------------------------------------------------


func test_a_bark_actually_plays() -> void:
	assert_true(_voice.say(&"dog.bark"), "say(dog.bark) reported no sound")
	var emitters := _voice.voices()
	assert_true(not emitters.is_empty(), "a bark opened no emitter")
	if emitters.is_empty():
		return
	# is_playing(), not the return of play().
	assert_true(emitters[0].is_playing(), "the emitter was opened and is not playing")
	assert_not_null(emitters[0].stream, "the emitter was opened with no stream")
	assert_eq(_voice.spoken_count(), 1, "the engine started %d utterance(s)" % _voice.spoken_count())


## Positional, which is the half that makes a growl a warning about a DIRECTION.
func test_the_emitters_are_positional_and_ride_the_animal() -> void:
	_animal.global_position = Vector3(12.0, 0.0, -7.0)
	assert_true(_voice.say(&"dog.bark"))
	var emitters := _voice.voices()
	assert_true(not emitters.is_empty(), "no emitter")
	if emitters.is_empty():
		return
	assert_true(
		emitters[0] is AudioStreamPlayer3D,
		"the emitter is a %s, which has no position at all" % emitters[0].get_class()
	)
	assert_almost_eq(
		emitters[0].global_position.distance_to(Vector3(12.0, 0.0, -7.0)), 0.0, 0.001,
		"the emitter is at %s and the animal is at %s" % [
			emitters[0].global_position, _animal.global_position]
	)
	# And it MOVES with the animal, rather than being placed once where it stood.
	_animal.global_position = Vector3(40.0, 0.0, 3.0)
	assert_almost_eq(
		emitters[0].global_position.distance_to(Vector3(40.0, 0.0, 3.0)), 0.0, 0.001,
		"the animal walked away and left its bark behind at %s" % emitters[0].global_position
	)


## A declared-but-silent call reports honestly instead of pretending.
##
## Built here rather than borrowed from the shipped map, and that is the point:
## this test used to reach for `dog.growl`, which was the map's only unvoiced
## call. When the owner supplied a growl the test went red -- not because the
## behaviour had broken, but because the test was measuring the DATA when it
## meant to measure the CODE. A declared-and-silent call is a legal state of
## `AnimalCall` whether or not any shipped animal is currently in it.
func test_a_call_with_no_file_makes_no_sound_and_admits_it() -> void:
	var silent := AnimalCall.new()
	silent.call_id = &"test.silent"
	# Typed-array locals annotated (briefing trap 4): an untyped `[]` is rejected
	# by the typed setter and the VM leaves the function without a word.
	var no_streams: Array[String] = []
	silent.stream_paths = no_streams
	var map := AnimalVoiceMap.new()
	var calls: Array[AnimalCall] = [silent]
	map.calls = calls
	_voice.set_map(map)

	assert_false(_voice.say(&"test.silent"), "a call with no file claimed a sound")
	assert_true(_voice.voices().is_empty(), "a silent call opened an emitter anyway")
	assert_eq(_voice.spoken_count(), 0)
	# It was still a real request, and a caller debugging silence needs to be able
	# to tell "asked and mute" from "never asked".
	assert_eq(_voice.last_asked(), &"test.silent")


func test_a_call_nobody_declared_is_not_silently_swallowed() -> void:
	assert_false(_voice.say(&"dog.purr"), "the dog purred")
	assert_eq(_voice.last_asked(), &"", "an undeclared call was recorded as asked")


# --- the data decides, not the code -------------------------------------------


## How far it carries is the design, and it reaches the emitter.
func test_how_far_a_call_carries_comes_from_the_map() -> void:
	var bark := _map.call_named(&"dog.bark")
	var whimper := _map.call_named(&"dog.whimper")
	var growl := _map.call_named(&"dog.growl")
	assert_not_null(bark)
	assert_not_null(whimper)
	assert_not_null(growl)
	if bark == null or whimper == null or growl == null:
		return
	# A growl heard across the valley is not a warning about a place.
	assert_true(
		growl.carry_m < bark.carry_m,
		"the growl carries %.1f m against the bark's %.1f m" % [growl.carry_m, bark.carry_m]
	)
	assert_true(_voice.say(&"dog.bark"))
	var emitters := _voice.voices()
	assert_true(not emitters.is_empty())
	if emitters.is_empty():
		return
	assert_almost_eq(
		emitters[0].max_distance, bark.carry_m, 0.001,
		"the emitter carries %.1f m and the data says %.1f m" % [
			emitters[0].max_distance, bark.carry_m]
	)
	assert_almost_eq(emitters[0].unit_size, bark.unit_size, 0.001)


## A dog does not bark once, and a whimper is not a bark's rhythm slowed down.
func test_how_often_comes_from_the_map_too() -> void:
	assert_true(_voice.say(&"dog.bark"))
	var queued := _voice.pending().size()
	var bark := _map.call_named(&"dog.bark")
	assert_true(
		queued + 1 >= bark.repeat_min and queued + 1 <= bark.repeat_max,
		"a bark burst is %d utterance(s); the data says %d..%d" % [
			queued + 1, bark.repeat_min, bark.repeat_max]
	)
	assert_true(queued >= 1, "the bark was a single sound, not a burst")


## A state that re-enters every frame must not make the animal stutter.
func test_the_cooldown_holds_a_repeat_off() -> void:
	assert_true(_voice.say(&"dog.bark"), "the first bark did not play")
	assert_false(_voice.say(&"dog.bark"), "a second bark went through on the same frame")
	var bark := _map.call_named(&"dog.bark")
	var elapsed := 0.0
	while elapsed < bark.cooldown_s + 0.5:
		_voice.advance(FRAME)
		elapsed += FRAME
	assert_true(
		_voice.say(&"dog.bark"),
		"the bark was still held off %.2f s after a %.2f s cooldown" % [elapsed, bark.cooldown_s]
	)


## Four identical barks a third of a second apart is one file being retriggered,
## and the ear catches it immediately.
func test_the_utterances_in_a_burst_are_not_all_the_same() -> void:
	assert_true(_voice.say(&"dog.bark"))
	var elapsed := 0.0
	while elapsed < 3.0:
		_voice.advance(FRAME)
		elapsed += FRAME
	var emitters := _voice.voices()
	assert_true(emitters.size() >= 2, "the burst opened only %d emitter(s)" % emitters.size())
	if emitters.size() < 2:
		return
	var pitches: Dictionary = {}
	var streams: Dictionary = {}
	for emitter in emitters:
		pitches[emitter.pitch_scale] = true
		if emitter.stream != null:
			streams[emitter.stream.resource_path] = true
	assert_true(
		pitches.size() >= 2,
		"%d utterances all at pitch %.4f" % [emitters.size(), emitters[0].pitch_scale]
	)
	assert_true(streams.size() >= 1, "no utterance carried a stream")


# --- tied to the takes ---------------------------------------------------------


func test_it_speaks_when_the_take_it_is_watching_changes() -> void:
	var player := _give_animal_a_take("bark")
	_voice.watch(player)
	assert_eq(_voice.last_asked(), &"", "it spoke before anything was playing")
	player.play("dog/bark")
	_voice.advance(FRAME)
	assert_eq(_voice.last_asked(), &"dog.bark", "the bark take did not reach the voice")
	assert_true(_voice.spoken_count() > 0, "the take changed and nothing played")


## THE TRAP, WHICH THIS PROJECT HAS PAID FOR TWICE. A node that only watches for
## a CHANGE can never learn a state that changed before it existed -- and here it
## is guaranteed to, because a child is ready before its parent and the rig does
## not exist yet when this node's `_ready()` runs.
func test_it_hears_a_take_that_was_already_playing_before_it_existed() -> void:
	var player := _give_animal_a_take("bark")
	# Already going. Nothing will ever report this as a change.
	player.play("dog/bark")
	_voice.watch(player)
	assert_eq(
		_voice.last_asked(), &"dog.bark",
		"the animal was already barking and the voice waited for it to start again"
	)
	assert_true(_voice.spoken_count() > 0, "it noticed the take and still made no sound")


## And it finds the player by itself, which is the path a real `Dog` takes: the
## rig is built in the PARENT's `_ready()`, after this node's has already run.
func test_it_finds_a_player_that_did_not_exist_when_it_was_ready() -> void:
	assert_true(_voice.watched_player() == null, "there was a player at ready after all")
	var player := _give_animal_a_take("bark")
	player.play("dog/bark")
	var elapsed := 0.0
	while elapsed < 0.6 and _voice.watched_player() == null:
		_voice.advance(FRAME)
		elapsed += FRAME
	assert_true(
		_voice.watched_player() == player,
		"the voice never found the AnimationPlayer that appeared after it"
	)
	assert_eq(_voice.last_asked(), &"dog.bark", "it found the player and ignored what it was playing")


## A take with a trailing space imports fine and is then unreachable by the name
## anybody would write -- the crow pack ships `Dove_Run to Idle ` (briefing trap
## 15). Trimmed on read, and counted, so the ASSET gets corrected rather than the
## code carrying the workaround for ever.
func test_a_take_name_with_a_trailing_space_still_resolves() -> void:
	assert_eq(_voice.take_name("dog/bark "), &"bark")
	assert_eq(_voice.trimmed_names(), 1, "the trim was not recorded")
	assert_eq(_voice.take_name("dog/bark"), &"bark")
	assert_eq(_voice.trimmed_names(), 1, "a clean name was counted as trimmed")
	assert_eq(_voice.take_name(""), &"")


func test_a_take_nothing_is_wired_to_makes_no_sound() -> void:
	var player := _give_animal_a_take("walk")
	_voice.watch(player)
	player.play("dog/walk")
	_voice.advance(FRAME)
	assert_eq(_voice.last_asked(), &"", "walking made a noise")
	assert_eq(_voice.spoken_count(), 0)


# --- the rest of the world -----------------------------------------------------


## A growl is a warning, and a warning nothing can hear about is half a warning.
func test_it_publishes_what_it_said() -> void:
	assert_true(_voice.say(&"dog.bark"))
	assert_true(not _heard.is_empty(), "the voice spoke and published nothing")
	if _heard.is_empty():
		return
	assert_eq(_heard[0]["event"], AnimalVoice.EVENT_SPOKE)
	var payload = _heard[0]["payload"]
	assert_eq(payload["call_id"], &"dog.bark")
	assert_true(payload.has("position"), "the event does not say where the animal was")


func test_a_voice_with_no_map_is_inert_rather_than_broken() -> void:
	var bare: AnimalVoice = VoiceScript.new()
	_animal.add_child(bare)
	assert_false(bare.say(&"dog.bark"), "a voice with no map claimed to bark")
	assert_true(bare.voices().is_empty())
	assert_eq(bare.load_map("res://data/audio/there_is_no_such_map.tres"), 0)
	_animal.remove_child(bare)
	bare.free()
