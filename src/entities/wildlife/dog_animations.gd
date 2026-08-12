class_name DogAnimations
extends RefCounted

## The shared vocabulary three different dogs answer to.
##
## ---------------------------------------------------------------------------
## THE PROBLEM THIS SOLVES, WHICH IS NOT "NAMING TAKES"
## ---------------------------------------------------------------------------
## The rescue scene picks ONE of the three breeds at random, so the companion
## behaviour written later has to drive whichever one turned up without knowing
## which. That is only possible if there is a set of names every dog answers to
## -- and there is not, in the delivery:
##
##   chihuahua         bark idle run sit walk          five takes
##   golden retriever  bark idle run sit walk stand     six
##   great dane        bark idle run sit walk stand     six
##
## `Docs/asset-inventory-low-poly-animals.md` section 5.1 recorded that gap and
## it is real. `lie` and `growl` are then authored on top of all three by
## `tools/blender/build_dog.py`, because the scene opens on a hurt dog in the
## snow and the package has no lying, hurt, sleep, death or growl take for any
## animal in it.
##
## So this file is a **state -> take** resolver, not a rename table. A behaviour
## asks for `DogAnimations.STAND`; the chihuahua does not have it; the answer is
## `idle`, decided here, in code, once -- not a null at the call site, and not a
## silent `play()` on a name the player does not hold, which does nothing and
## reports nothing.
##
## ---------------------------------------------------------------------------
## WHY THE FALLBACK IS `idle` AND NOT SOMETHING CLEVERER
## ---------------------------------------------------------------------------
## `stand` on the two breeds that have it is a short SETTLE -- under a second on
## the golden retriever, 1.75 s on the great dane -- that ends with the animal
## square on four feet, head up, tail up. It is not a loop and it is not a
## posture the other takes cannot reach: the chihuahua's `idle` is a standing dog
## for the whole of its 10.75 s.
##
## So the fallback loses the TRANSITION, not the pose. That is worth saying
## plainly, because "fall back to idle" usually means "do nothing and hope", and
## here it means the same silhouette arrived at without the settle.
##
## `sit` was the alternative and is worse: it is a different posture, and a dog
## that sits down when a behaviour asked it to stand up is not a degraded answer,
## it is a wrong one.
##
## ---------------------------------------------------------------------------
## FOLLOWING `WandererAnimations`, AND WHAT IS DIFFERENT
## ---------------------------------------------------------------------------
## Same shape: a `TAKES` table of rows, `build()` returning one `AnimationLibrary`
## with the loop flags set, and every take named even when nothing drives it yet.
## Two things this needs that the wanderer does not:
##
##   * THREE MODELS, not one. Every lookup is keyed by breed.
##   * A RESOLUTION STEP. The wanderer's twenty takes all exist; here a state may
##     have no take on this breed and `resolve()` is the one place that decides.
##
## What it deliberately does NOT do is retarget. The inventory's finding that the
## great dane is a different 55-bone rig -- 49 shared, plus `tempRename_M` and
## `tempRename1_M`, the author's own leftovers -- is true and costs nothing here,
## because each breed's takes were authored on its own skeleton and are played on
## its own skeleton. Retargeting would only be needed to play ONE dog's take on
## ANOTHER dog, which nothing wants.

## The three breeds, by the name of their `.glb`.
const CHIHUAHUA := &"chihuahua"
const GOLDEN_RETRIEVER := &"golden_retriever"
const GREAT_DANE := &"great_dane"

const BREEDS: Array[StringName] = [CHIHUAHUA, GOLDEN_RETRIEVER, GREAT_DANE]

const MODEL_ROOT := "res://assets/models/characters/dogs"

## The library name every take is held under, so a take is asked for as
## `dog/idle` whichever breed is wearing it. One name for all three on purpose:
## a behaviour that had to build the string from the breed would be a behaviour
## that knows which dog it got.
const LIBRARY := &"dog"

## The rate the pack authored every dog at. `animation/fps` in each `.import`
## matches, and `tests/art/test_dog_models.gd` asserts it: the package holds two
## animals at other rates (reindeer 30, pig 60) and a length computed at the
## wrong rate is off by a quarter with nothing to report it.
const SOURCE_FPS := 24.0

## ---------------------------------------------------------------------------
## THE VOCABULARY. These are STATES a behaviour asks for, not file names.
## ---------------------------------------------------------------------------
const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const SIT := &"sit"
const STAND := &"stand"
const BARK := &"bark"
## Authored here. The rescue scene's opening pose: on the flank, breathing.
const LIE := &"lie"
## Authored here. Head low and forward, weight back, tail low and slowly moving.
const GROWL := &"growl"

const STATES: Array[StringName] = [IDLE, WALK, RUN, SIT, STAND, BARK, LIE, GROWL]

## What a state falls back to when this breed has no take of its own for it.
##
## A Dictionary rather than a chain of `if`s so the whole policy is one readable
## table and `tests/unit/test_dog_animations.gd` can walk it. A state absent from
## here and absent from the breed is a hole `resolve()` reports rather than
## papering over -- there are none today and the assertion exists so there are
## none tomorrow either.
const FALLBACK := {
	STAND: IDLE,
}

## Which states hold and which run once.
##
## `lie` and `growl` loop because they are held attitudes with a slow motion in
## them -- a dog that stops breathing after six seconds is worse than one that
## never started. `stand`, `sit` and `bark` are one-shots that end on a pose the
## behaviour then holds or leaves.
const LOOPS := {
	IDLE: true,
	WALK: true,
	RUN: true,
	SIT: false,
	STAND: false,
	BARK: false,
	LIE: true,
	GROWL: true,
}

## [breed, state, seconds the take must import at].
##
## The duration is here for the same reason `PigeonAnimations` carries one: a
## re-import that changed `animation/trimming` or `animation/fps` would silently
## reshape every take, and a take that is not the length it should be is then a
## red run rather than a dog that moves at the wrong speed.
##
## MEASURED off the shipped `.glb` at 24 fps. The two authored takes are the
## lengths `build_dog.py` writes -- 6.042 s of lying (two breaths and a tail
## twitch) and 3.042 s of growl (one tail sweep) -- and both are one frame over
## their nominal length because a loop's last frame repeats its first.
const TAKES: Array = [
	[CHIHUAHUA, BARK, 0.750],
	[CHIHUAHUA, IDLE, 10.750],
	[CHIHUAHUA, RUN, 0.667],
	[CHIHUAHUA, SIT, 1.458],
	[CHIHUAHUA, WALK, 1.500],
	[CHIHUAHUA, LIE, 6.042],
	[CHIHUAHUA, GROWL, 3.042],

	[GOLDEN_RETRIEVER, BARK, 1.125],
	[GOLDEN_RETRIEVER, IDLE, 7.583],
	[GOLDEN_RETRIEVER, RUN, 0.792],
	[GOLDEN_RETRIEVER, SIT, 1.125],
	[GOLDEN_RETRIEVER, STAND, 0.917],
	[GOLDEN_RETRIEVER, WALK, 1.292],
	[GOLDEN_RETRIEVER, LIE, 6.042],
	[GOLDEN_RETRIEVER, GROWL, 3.042],

	[GREAT_DANE, BARK, 0.875],
	[GREAT_DANE, IDLE, 6.542],
	[GREAT_DANE, RUN, 0.625],
	[GREAT_DANE, SIT, 1.500],
	[GREAT_DANE, STAND, 1.750],
	[GREAT_DANE, WALK, 0.875],
	[GREAT_DANE, LIE, 6.042],
	[GREAT_DANE, GROWL, 3.042],
]


## Where a breed's model lives.
static func model_path(breed: StringName) -> String:
	return MODEL_ROOT.path_join("%s.glb" % breed)


## Whether this breed has a take of its own for `state`, before any fallback.
static func has_own(breed: StringName, state: StringName) -> bool:
	for row in TAKES:
		if StringName(row[0]) == breed and StringName(row[1]) == state:
			return true
	return false


## The state this breed actually plays when asked for `state`.
##
## The whole point of the file. Returns `state` when the breed has it, the
## fallback when it does not, and `&""` when neither -- which is a hole, and the
## caller is expected to treat it as one rather than as silence.
static func resolve(breed: StringName, state: StringName) -> StringName:
	if has_own(breed, state):
		return state
	var substitute: StringName = FALLBACK.get(state, &"")
	if substitute != &"" and has_own(breed, substitute):
		return substitute
	return &""


## How long the take a breed plays for `state` is meant to be, or -1.
static func length_of(breed: StringName, state: StringName) -> float:
	var played := resolve(breed, state)
	if played == &"":
		return -1.0
	for row in TAKES:
		if StringName(row[0]) == breed and StringName(row[1]) == played:
			return float(row[2])
	return -1.0


## Every state this breed can be asked for, with what it will play.
##
## For a behaviour that wants to know what it is driving, and for the report.
static func vocabulary(breed: StringName) -> Dictionary:
	var found: Dictionary = {}
	for state in STATES:
		found[state] = resolve(breed, state)
	return found


## One library holding every take this breed has, under its own state name.
##
## Deep-duplicated before `loop_mode` is written, because `ResourceLoader` hands
## every caller the SAME `Animation` instance (briefing trap 6) -- so setting the
## flag on the shared one would edit the imported asset for everything that ever
## loads it, including the next call to this function.
##
## The FALLBACK is NOT resolved here. The library holds only what the breed
## really has, so a census of it says what the animal can do; `resolve()` is what
## a behaviour asks. Baking `stand -> idle` into the library as a second
## animation called `stand` would make the chihuahua look, to any test that
## counted takes, exactly like a dog that has one.
static func build(breed: StringName) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var source := source_takes(breed)
	for row in TAKES:
		if StringName(row[0]) != breed:
			continue
		var state: StringName = StringName(row[1])
		if not source.has(String(state)):
			push_warning("dog_animations: %s holds no take called %s" % [model_path(breed), state])
			continue
		var take: Animation = (source[String(state)] as Animation).duplicate(true)
		take.loop_mode = Animation.LOOP_LINEAR if bool(LOOPS.get(state, false)) else Animation.LOOP_NONE
		library.add_animation(state, take)
	return library


## Every take a breed's model file imported, by the name the `.glb` holds it
## under. Allocates no Node: the animations are read off the `PackedScene`'s
## `SceneState` rather than out of an instantiated tree, so a test may call it
## freely (briefing section 2.2).
static func source_takes(breed: StringName) -> Dictionary:
	return animations_in(model_path(breed))


## An `AnimationPlayer` stores one property per library, named `libraries/<name>`
## -- `libraries/` for the unnamed default one every importer writes -- and the
## value is the `AnimationLibrary` itself rather than a dictionary of them.
## Measured on 4.7.1; there is no API that reports this.
##
## This is `WandererAnimations.animations_in()` and it is copied rather than
## reused deliberately: that class is the PLAYER's take library and reaching into
## it from an animal would tie the dog's build to the man's. The birds solved the
## same problem the other way and it cost them a refactor.
static func animations_in(path: String) -> Dictionary:
	var found: Dictionary = {}
	if not ResourceLoader.exists(path):
		return found
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		push_warning("dog_animations: %s did not load as a PackedScene" % path)
		return found
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			var value = state.get_node_property_value(node, property)
			if not (value is AnimationLibrary):
				continue
			for name in (value as AnimationLibrary).get_animation_list():
				found[String(name)] = (value as AnimationLibrary).get_animation(name)
	return found
