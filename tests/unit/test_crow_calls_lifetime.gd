extends TestCase

## What happens to a caw when the bird that made it is freed underneath it.
##
## ---------------------------------------------------------------------------
## THE CRASH THIS FILE EXISTS FOR
## ---------------------------------------------------------------------------
## From the owner's own play session, four and a half minutes in:
##
##   E 0:04:32:132  CrowCalls._follow: Trying to assign invalid previously freed
##                  instance.
##     crow_calls.gd:296 @ _follow()
##     crow_calls.gd:277 @ advance()
##     crow_calls.gd:269 @ _process()
##
## `_speak()` files `{voice, crow}` in `_following` so the emitter can track the
## bird. The bird finishes its flight, `BirdFlock._advance_birds()` sees
## `is_gone()`, removes it from the tree and `queue_free()`s it, and the free
## lands at the end of the frame. `_following` still holds the pointer.
##
## ---------------------------------------------------------------------------
## WHY THE GUARD THAT WAS ALREADY THERE DID NOT HELP
## ---------------------------------------------------------------------------
## `_follow()` read the bird into a STATICALLY TYPED local and then checked it:
##
##   var crow: Crow = pair["crow"]                       <-- line 296, the report
##   if crow == null or not is_instance_valid(crow):     <-- correct, unreachable
##
## GDScript validates the instance AT a type-checked assignment whose source is
## statically `Variant`, which a `Dictionary` value always is. So line 296 threw
## and aborted `_follow()`; line 297 never ran. The guard was right, visible, and
## dead. Measured on 4.7.1 -- see briefing trap 18 for the full table of which
## shapes throw and which do not.
##
## ---------------------------------------------------------------------------
## THE PART THAT MAKES IT WORSE THAN ONE SILENT EMITTER
## ---------------------------------------------------------------------------
## The abort takes the REST OF THE LIST with it. One freed bird at the head of
## `_following` stops every other bird's voice from being followed -- so the
## symptom is not "one caw sits still", it is "the flock's calls stop scattering
## at all", which reads as the positional audio having never worked.
##
## And because nothing ever removed the entry, the same error fired on every
## frame for the rest of the session. That is why
## `test_..._is_dropped_from_the_follow_list...` is here as well: skipping a dead
## entry forever is not the same as handling it.

const CallsScript := preload("res://src/entities/wildlife/crow_calls.gd")
const CrowScript := preload("res://src/entities/wildlife/crow.gd")

const FRAME := 1.0 / 60.0

## Far enough apart that a voice's position identifies which bird it belongs to,
## and all well inside `audible_m` of the origin, where `_player_position()`
## falls back to when no player is registered.
const SPACING := 9.0

var _calls: CrowCalls = null
var _birds: Array[Crow] = []


func before_each() -> void:
	_calls = CallsScript.new()
	_calls.random_seed = 4711
	_root().add_child(_calls)
	_calls.seed_rng()


func after_each() -> void:
	# `for crow in _birds` over a typed array yields an untyped loop variable, so
	# a slot holding a bird this test freed on purpose compares equal to null
	# rather than throwing. Measured; this is the safe half of trap 18.
	for crow in _birds:
		if crow != null and is_instance_valid(crow):
			crow.free()
	_birds.clear()
	if _calls != null:
		for voice in _calls.voices():
			voice.stop()
		_root().remove_child(_calls)
		_calls.free()
		_calls = null


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _some_birds(count: int) -> void:
	for index in range(count):
		var crow: Crow = CrowScript.new()
		crow.perch_on(Vector3(0.0, 6.0, float(index) * SPACING), Vector3(1.0, 0.0, 0.0))
		_birds.append(crow)


## Runs the whole burst out, so every scheduled call has spoken and every one of
## them has filed a follower.
func _play_the_burst_out() -> void:
	var elapsed := 0.0
	while elapsed < 3.0:
		_calls.advance(FRAME)
		elapsed += FRAME


## Which bird speaks first, and the first LATER call from a different bird.
## Read off the schedule rather than assumed, because `_speakers()` shuffles.
func _first_and_a_later_speaker() -> Array:
	var order: Array = []
	for entry in _calls.pending():
		order.append(int(entry["bird"]))
	if order.is_empty():
		return []
	var first := int(order[0])
	for index in range(1, order.size()):
		if int(order[index]) != first:
			return [first, int(order[index])]
	return []


# --- the reported crash ------------------------------------------------------


## THE ONE THE OWNER'S LOG IS ABOUT, written as behaviour rather than as "no
## error was printed" -- the runner cannot see the console, and a test that
## asserted on silence would be asserting on something it cannot observe.
##
## The observable consequence is that the freed bird's entry sits AHEAD of the
## others, so the abort robs every later bird of its tracking too.
func test_a_freed_bird_does_not_stop_the_rest_of_the_flock_being_followed() -> void:
	_calls.fewest = 4
	_calls.most = 4
	_some_birds(4)
	var scheduled := _calls.announce(_birds)
	assert_true(scheduled >= 2, "a forced four-call burst scheduled only %d" % scheduled)
	var speakers := _first_and_a_later_speaker()
	assert_true(
		speakers.size() == 2,
		"the burst never used two different birds, so there is nothing behind the freed one"
	)
	if speakers.size() != 2:
		return
	var first := int(speakers[0])
	var later := int(speakers[1])

	_play_the_burst_out()
	assert_true(
		_calls.voices().size() >= 2,
		"the burst opened only %d emitter(s)" % _calls.voices().size()
	)

	# The flock lands and BirdFlock frees the bird that spoke first, while its
	# emitter is still in `_following`.
	var doomed: Crow = _birds[first]
	_birds[first] = null
	doomed.free()

	# A bird still in the air, moved somewhere no emitter could already be.
	var moved := Vector3(0.0, 41.0, -23.0)
	var flying: Crow = _birds[later]
	flying.perch_on(moved, Vector3(1.0, 0.0, 0.0))
	_calls.advance(FRAME)

	var tracked := false
	var nearest := 1e9
	for voice in _calls.voices():
		nearest = minf(nearest, voice.global_position.distance_to(moved))
		if voice.global_position.distance_to(moved) < 0.001:
			tracked = true
	assert_true(
		tracked,
		"bird %d was moved to %s and the closest emitter is still %.3f m away -- freed bird %d sits ahead of it in the follow list and aborted _follow() before its turn" % [
			later, moved, nearest, first]
	)


## Dropped, not skipped. An entry that can never be followed again is walked
## every frame for the rest of the run otherwise, which is exactly how one
## flight's worth of caws became a permanent per-frame error in the owner's log.
func test_a_freed_bird_is_dropped_from_the_follow_list_rather_than_skipped_forever() -> void:
	_calls.fewest = 4
	_calls.most = 4
	_some_birds(4)
	_calls.announce(_birds)
	_play_the_burst_out()
	var followed := _calls.following_count()
	assert_true(followed >= 2, "a four-call burst filed only %d follower(s)" % followed)

	for crow in _birds:
		if crow != null and is_instance_valid(crow):
			crow.free()
	_birds.clear()
	_calls.advance(FRAME)

	assert_eq(
		_calls.following_count(), 0,
		"%d follower(s) outlived every bird they follow -- nothing will ever make them followable again, so they are walked for the rest of the session" % _calls.following_count()
	)


## The same defect at the other end of the system. `announce()` casts with
## `as Crow`, and `as` is type-checked too: measured on 4.7.1 it throws
## `Trying to cast a freed object` and aborts the function, so ONE freed bird in
## the list handed over costs the whole burst rather than one caw.
func test_a_flock_list_holding_a_freed_bird_can_still_be_announced() -> void:
	_some_birds(3)
	var handed: Array = []
	for crow in _birds:
		handed.append(crow)
	var doomed: Crow = _birds[1]
	_birds[1] = null
	doomed.free()

	var scheduled := _calls.announce(handed)
	assert_true(
		scheduled > 0,
		"a list of three birds with one of them freed scheduled %d calls; the two live birds were never reached" % scheduled
	)


## And the two that survived are the two that were alive -- a burst that quietly
## dropped everybody would pass the test above for the wrong reason.
func test_the_live_birds_in_that_list_are_the_ones_that_speak() -> void:
	_some_birds(3)
	var handed: Array = []
	for crow in _birds:
		handed.append(crow)
	var doomed: Crow = _birds[1]
	_birds[1] = null
	doomed.free()

	_calls.fewest = 4
	_calls.most = 4
	_calls.announce(handed)
	var spoke: Dictionary = {}
	for entry in _calls.pending():
		spoke[int(entry["bird"])] = true
	assert_true(not spoke.is_empty(), "nobody was scheduled at all")
	for index in spoke:
		assert_true(
			int(index) >= 0 and int(index) < 2,
			"a call was addressed to bird %d, but only two birds survived the cull" % int(index)
		)
