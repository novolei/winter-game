extends TestCase

## The shared vocabulary: does every state resolve, on every breed?
##
## This is the gate on the thing the rescue scene needs and cannot check for
## itself. It picks ONE of three dogs at random, so a companion behaviour asking
## for `DogAnimations.STAND` must get an answer whichever one turned up -- and
## the chihuahua does not have that take. What must never happen is the silent
## version: `AnimationPlayer.play()` on a name the library does not hold does
## nothing, reports nothing, and looks exactly like a dog deciding not to move.
##
## `tests/art/test_dog_models.gd` asserts the takes are really in the files.
## This asserts the table over them is complete and honest.

const DogScript := preload("res://src/entities/wildlife/dog.gd")
const DogAnimationsScript := preload("res://src/entities/wildlife/dog_animations.gd")


# --- the vocabulary is total --------------------------------------------------


func test_every_state_resolves_on_every_breed() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		for state in DogAnimationsScript.STATES:
			if DogAnimationsScript.resolve(breed, state) == &"":
				offenders.append("%s cannot answer %s at all" % [breed, state])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Whatever a state resolves to must be a take that breed really has, not another
## state that also falls back. A one-step fallback is the whole policy and a
## chain would be a place for a cycle to hide.
func test_what_a_state_resolves_to_is_always_a_take_the_breed_owns() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		for state in DogAnimationsScript.STATES:
			var played := DogAnimationsScript.resolve(breed, state)
			if played != &"" and not DogAnimationsScript.has_own(breed, played):
				offenders.append("%s resolves %s to %s, which it does not have" % [breed, state, played])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## THE GAP, NAMED. The chihuahua really has no `stand`, and this asserts both
## halves of the decision: that the hole is there, and what was decided about it.
## Without the first half the test would pass just as well against a chihuahua
## that had grown a `stand` take, and the fallback would stop being exercised
## with nothing to say so.
func test_the_chihuahua_has_no_stand_and_answers_with_its_idle() -> void:
	assert_false(
		DogAnimationsScript.has_own(DogAnimationsScript.CHIHUAHUA, DogAnimationsScript.STAND),
		"the chihuahua now has its own `stand`, so the fallback below is no longer exercised"
	)
	assert_eq(
		DogAnimationsScript.resolve(DogAnimationsScript.CHIHUAHUA, DogAnimationsScript.STAND),
		DogAnimationsScript.IDLE,
		"a chihuahua asked to stand must fall through to its idle, which IS a standing dog"
	)
	# ...and the other two answer with their own, so the fallback is not a
	# blanket that quietly swallows a take somebody did deliver.
	for breed in [DogAnimationsScript.GOLDEN_RETRIEVER, DogAnimationsScript.GREAT_DANE]:
		assert_eq(
			DogAnimationsScript.resolve(breed, DogAnimationsScript.STAND),
			DogAnimationsScript.STAND,
			"%s has its own stand and must play it" % breed
		)


## Every fallback names a state the vocabulary knows. A typo here would make the
## substitution resolve to nothing, which reads in `resolve()` exactly like a
## breed that has no answer.
func test_every_fallback_points_at_a_real_state() -> void:
	var offenders := PackedStringArray()
	for state in DogAnimationsScript.FALLBACK.keys():
		if not DogAnimationsScript.STATES.has(state):
			offenders.append("%s is a fallback key but not a state" % state)
		var substitute = DogAnimationsScript.FALLBACK[state]
		if not DogAnimationsScript.STATES.has(substitute):
			offenders.append("%s falls back to %s, which is not a state" % [state, substitute])
		if substitute == state:
			offenders.append("%s falls back to itself" % state)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Nothing falls back that does not need to. A fallback for a state every breed
## has is dead policy, and dead policy is how the wrong take starts being played
## the day somebody adds a breed.
func test_no_fallback_exists_for_a_state_every_breed_already_has() -> void:
	var offenders := PackedStringArray()
	for state in DogAnimationsScript.FALLBACK.keys():
		var missing := false
		for breed in DogAnimationsScript.BREEDS:
			if not DogAnimationsScript.has_own(breed, state):
				missing = true
		if not missing:
			offenders.append("every breed has %s, so its fallback is dead" % state)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The two takes the package does not have, on all three. This is the deliverable
## the rescue scene is blocked on and it is asserted by name rather than left to
## the count.
func test_every_breed_can_lie_down_and_growl() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		for state in [DogAnimationsScript.LIE, DogAnimationsScript.GROWL]:
			if not DogAnimationsScript.has_own(breed, state):
				offenders.append("%s has no %s of its own" % [breed, state])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


# --- the table itself ---------------------------------------------------------


func test_every_state_has_a_loop_flag() -> void:
	var offenders := PackedStringArray()
	for state in DogAnimationsScript.STATES:
		if not DogAnimationsScript.LOOPS.has(state):
			offenders.append("%s has no loop flag, so it would import as LOOP_NONE by accident" % state)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## A held attitude that stops is worse than one that never started: a dog that
## stops breathing after six seconds reads as dead, and a growl that ends leaves
## the animal frozen mid-sway.
func test_the_held_attitudes_loop_and_the_one_shots_do_not() -> void:
	assert_true(bool(DogAnimationsScript.LOOPS[DogAnimationsScript.LIE]), "the lying dog stops breathing")
	assert_true(bool(DogAnimationsScript.LOOPS[DogAnimationsScript.GROWL]), "the growl freezes mid-sway")
	assert_true(bool(DogAnimationsScript.LOOPS[DogAnimationsScript.IDLE]), "the idle stops")
	assert_false(bool(DogAnimationsScript.LOOPS[DogAnimationsScript.BARK]), "a bark that loops is a barking dog")
	assert_false(bool(DogAnimationsScript.LOOPS[DogAnimationsScript.STAND]), "stand is a settle, not a cycle")


func test_every_row_in_the_table_names_a_known_breed_and_state() -> void:
	var offenders := PackedStringArray()
	for row in DogAnimationsScript.TAKES:
		if not DogAnimationsScript.BREEDS.has(StringName(row[0])):
			offenders.append("%s is not a breed" % row[0])
		if not DogAnimationsScript.STATES.has(StringName(row[1])):
			offenders.append("%s is not a state" % row[1])
		if float(row[2]) <= 0.0:
			offenders.append("%s/%s has no duration" % [row[0], row[1]])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


func test_length_of_follows_the_fallback() -> void:
	assert_almost_eq(
		DogAnimationsScript.length_of(DogAnimationsScript.CHIHUAHUA, DogAnimationsScript.STAND),
		DogAnimationsScript.length_of(DogAnimationsScript.CHIHUAHUA, DogAnimationsScript.IDLE),
		0.0001,
		"a behaviour timing itself against `stand` on a chihuahua must be told the idle's length"
	)
	assert_true(
		DogAnimationsScript.length_of(DogAnimationsScript.CHIHUAHUA, &"nonsense") < 0.0,
		"an unknown state must report -1 rather than a plausible-looking zero"
	)


func test_the_vocabulary_reports_every_state() -> void:
	for breed in DogAnimationsScript.BREEDS:
		var found := DogAnimationsScript.vocabulary(breed)
		assert_eq(found.size(), DogAnimationsScript.STATES.size(),
			"%s's vocabulary has %d entries for %d states" % [
				breed, found.size(), DogAnimationsScript.STATES.size()])


# --- the library that is actually built ---------------------------------------


func test_the_library_holds_what_the_breed_owns_and_nothing_else() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var library := DogAnimationsScript.build(breed)
		var built := {}
		for name in library.get_animation_list():
			built[String(name)] = true
		for state in DogAnimationsScript.STATES:
			var owned := DogAnimationsScript.has_own(breed, state)
			if owned and not built.has(String(state)):
				offenders.append("%s's library is missing %s" % [breed, state])
			if not owned and built.has(String(state)):
				offenders.append("%s's library invented %s" % [breed, state])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The chihuahua's library must NOT contain a `stand`. Baking the fallback into
## the library as a second copy of the idle would make the animal look, to any
## test that counted takes, exactly like a dog that has one -- and the gap this
## whole file exists to keep visible would stop being visible.
func test_the_fallback_is_not_baked_into_the_library() -> void:
	var library := DogAnimationsScript.build(DogAnimationsScript.CHIHUAHUA)
	assert_false(
		library.has_animation(DogAnimationsScript.STAND),
		"the chihuahua's library holds a `stand`, so a take census can no longer see the gap"
	)


func test_the_loop_flags_reach_the_built_library() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var library := DogAnimationsScript.build(breed)
		for name in library.get_animation_list():
			var wanted: bool = bool(DogAnimationsScript.LOOPS.get(name, false))
			var got: bool = library.get_animation(name).loop_mode == Animation.LOOP_LINEAR
			if wanted != got:
				offenders.append("%s/%s loops=%s, the table says %s" % [breed, name, got, wanted])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Trap 6: `ResourceLoader` hands every caller the same `Animation` instance, so
## setting `loop_mode` on the imported one would edit the asset for everything
## that ever loads it -- including the next call to `build()`. The library must be
## working on a duplicate.
func test_building_the_library_does_not_edit_the_imported_asset() -> void:
	var breed: StringName = DogAnimationsScript.GOLDEN_RETRIEVER
	var source := DogAnimationsScript.source_takes(breed)
	assert_true(source.has(String(DogAnimationsScript.IDLE)), "no idle to check against")
	if not source.has(String(DogAnimationsScript.IDLE)):
		return
	var before: int = (source[String(DogAnimationsScript.IDLE)] as Animation).loop_mode
	var library := DogAnimationsScript.build(breed)
	assert_eq(
		library.get_animation(DogAnimationsScript.IDLE).loop_mode, Animation.LOOP_LINEAR,
		"the library's idle does not loop"
	)
	assert_eq(
		(DogAnimationsScript.source_takes(breed)[String(DogAnimationsScript.IDLE)] as Animation).loop_mode,
		before,
		"build() wrote the loop flag onto the shared imported Animation"
	)


# --- the node -----------------------------------------------------------------


func test_a_dog_builds_its_rig_and_answers_every_state() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var dog: Dog = DogScript.new()
		dog.breed = breed
		if not dog.build_rig():
			offenders.append("%s did not build a rig" % breed)
			dog.free()
			continue
		var player := dog.player()
		if player == null:
			offenders.append("%s has no AnimationPlayer" % breed)
		else:
			for state in DogAnimationsScript.STATES:
				var played := dog.play(state)
				if played == &"":
					offenders.append("%s played nothing for %s" % [breed, state])
				elif not player.has_animation("%s/%s" % [DogAnimationsScript.LIBRARY, played]):
					offenders.append("%s resolved %s to %s, which its player does not hold" % [
						breed, state, played])
			player.stop()
		dog.free()
	assert_eq(offenders.size(), 0, "; ".join(offenders))
