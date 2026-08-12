class_name PigeonAnimations
extends RefCounted

## The rock dove's thirteen takes, under names that say what the motion is.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A FIFTH THE SIZE OF `crow_animations.gd`
## ---------------------------------------------------------------------------
## The crow's pack put fifteen clips END TO END inside one long take and named
## the boundaries only in a Unity `.meta`, so `CrowAnimations` had to be a
## slicer: read the frame ranges, sample the source at both ends, rebuild every
## track, flatten the root travel.
##
## **This pack does not do that.** `Docs/asset-inventory-low-poly-animals.md`
## section 1.3: fifty-five of its sixty-six animals ship each clip as its own FBX
## `AnimationStack`, and the dove is one of them. Godot's importer produces all
## thirteen already separated, already trimmed and already named. There is
## nothing to cut.
##
## Two things still have to happen here, and only two:
##
##   THE NAMES. The pack calls them `Dove_Idle Left`, `Dove_Fly to Idle` and
##   `Dove_Atttack` -- spaces, the author's own typo, and a species prefix on a
##   library that already knows what species it is. A rename layer means the
##   game asks for `pigeon/idle_left` and a re-delivery that fixes the typo is
##   one row here rather than a search through the entity code.
##
##   THE LOOP FLAGS. Every take imports as LOOP_NONE, including the two idles
##   and the flight cycle. A perched bird whose idle does not loop plays four
##   seconds of pigeon and then stands frozen for as long as it sits there.
##
## ---------------------------------------------------------------------------
## AND ONE THING THAT DOES **NOT** HAVE TO HAPPEN, WHICH IS THE BIGGER SAVING
## ---------------------------------------------------------------------------
## No take needs its root motion flattened. `CrowAnimations`' `in_place` column
## exists because `Rav_TakeOff` drives the CG bone 0.30 m up and 0.37 m forward,
## so the take and the code were two answers to one question and the bird
## travelled at twice the speed anything asked for.
##
## MEASURED here, over twenty-one samples of every take, as the full travel of
## the `Root_M` bone across the take:
##
##   Dove_Fly            0.033 m     Dove_Idle to Fly    0.032 m
##   Dove_Fly to Idle    0.026 m     Dove_Run to Idle    0.024 m
##   Dove_Walk           0.009 m     Dove_Run            0.001 m
##   Dove_Death          0.106 m   <- the bird falling over, and not played
##
## Everything the game drives moves the root by at most 33 mm, which is a
## wingbeat bob rather than travel. So the code owns every metre by default and
## nothing has to be taken away from the animator.
##
## ---------------------------------------------------------------------------
## THE TRACK PATHS ARE LEFT ALONE, DELIBERATELY
## ---------------------------------------------------------------------------
## `CrowAnimations` rewrites every track to `Skeleton3D:<bone>` because its
## animation files carry no armature at all -- 3ds Max exported the rig as a
## hierarchy of nulls -- so the tracks arrive addressed to NODES that the model
## file does not have.
##
## This file's takes come out of the same FBX as the mesh and address
## `Group/Main/DeformationSystem/Skeleton3D:<bone>`, which is exactly where the
## skeleton is. The library is hung on that file's OWN AnimationPlayer, whose
## root node is the same scene root the paths are relative to, so rewriting them
## would break the one thing that already works.
##
## ---------------------------------------------------------------------------
## `animation/trimming` HAS TO BE **ON** HERE, WHICH IS THE OPPOSITE OF THE CROW
## ---------------------------------------------------------------------------
## This one cost a red run and it is the trap a third animal will walk into.
##
## `tests/art/test_crow_model.gd` asserts `animation/trimming=false` on every
## crow file, and the reason is sound: the crow's clips are frame RANGES inside
## one long take, and trimming moves the frame numbers `CrowAnimations.FRAMES` is
## written in. Set the same value here, on the reasoning that it is the project's
## rule, and this happens -- measured, on the first run:
##
##   idle_left    3.958 s   correct, because its clip starts at frame 0
##   idle_right   8.958 s   the pack authored 3.958
##   walk        11.583 s   the pack authored 1.167
##   death       23.792 s   the pack authored 0.875
##
## Those are not corrupt lengths. 215 / 24 = 8.958, and frame 215 is where
## `Dove_Idle Right` ENDS. Every clip in this file is its own `AnimationStack`
## but they all sit on ONE shared timeline, so a stack that runs 120..215 imports
## as 0..215 with the first five seconds empty. Trimming is what cuts the dead
## lead-in off the front.
##
## The symptom, had the tests only counted takes, is a pigeon that lands on a
## wire and stands perfectly still for five seconds before its idle begins -- and
## the longer the clip's position in the file, the longer the wait, so the bird
## looks broken in a way that varies by take. It errors nothing.
##
## **So the setting is a property of how the pack laid its clips out, not a
## project convention**, and the two packs this game has taken birds from want
## opposite values. What makes it safe either way is the duration column in
## TAKES below: the lengths are asserted against the pack's own frame ranges, so
## whichever way the flag goes, a take that is not the length it should be is a
## red run rather than a slow bird.

## The one file: model, skeleton and all thirteen takes.
##
## The pack ships a separate `SKM_DoveRock_Rig.fbx` as well. It was measured and
## it is not needed: identical 832-triangle mesh, identical 45-bone skeleton,
## and no AnimationPlayer at all. Taking one file instead of two also takes the
## model and its takes off any chance of drifting apart, and costs 184 KB less.
const MODEL_PATH := "res://assets/models/characters/pigeon/pigeon.fbx"

## The library name the AnimationPlayer holds these under, so a take is asked
## for as "pigeon/idle_left".
const LIBRARY := &"pigeon"

## The rate the pack authored the dove at. Every duration below is a frame range
## divided by this, and `animation/fps` in the `.import` is set to match.
const SOURCE_FPS := 24.0

## The names the game asks for.
const IDLE_LEFT := &"idle_left"
const IDLE_RIGHT := &"idle_right"
const IDLE_TO_WALK := &"idle_to_walk"
const WALK := &"walk"
const WALK_TO_IDLE := &"walk_to_idle"
const IDLE_TO_RUN := &"idle_to_run"
const RUN := &"run"
const RUN_TO_IDLE := &"run_to_idle"
const TAKE_OFF := &"take_off"
const FLY := &"fly"
const LAND := &"land"
const PECK := &"peck"
const DEATH := &"death"

## [the pack's own name, ours, loops, the duration it must import at].
##
## The duration is here so a re-import that changes `animation/trimming` cannot
## quietly shorten a take -- which is exactly what caught the crow's perch file,
## where trimming brought 183 frames in as 100 and slid every number that
## depended on it. `tests/unit/test_pigeon_animations.gd` asserts every row.
##
## All thirteen are named even though the behaviour plays seven, because the
## owner cannot author bird animation: a take that is imported and named is a
## feature somebody can build later, and a take nobody wrote down is one that
## has to be rediscovered out of a 122 MB package.
const TAKES: Array = [
	# The perch. Two idles, and the pack's only left/right pair of them -- the
	# nearest thing in the whole package to a bird turning its head to watch you.
	["Dove_Idle Left", IDLE_LEFT, true, 3.958],
	["Dove_Idle Right", IDLE_RIGHT, true, 3.958],
	# The ground. A crow in this game never walks; a pigeon on an eave should be
	# able to. Nothing drives these yet.
	["Dove_Idle to Walk", IDLE_TO_WALK, false, 0.417],
	["Dove_Walk", WALK, true, 1.167],
	["Dove_Walk to Idle", WALK_TO_IDLE, false, 0.417],
	["Dove_Idle to Run", IDLE_TO_RUN, false, 0.292],
	["Dove_Run", RUN, true, 0.583],
	# The pack's own name for this one carries a TRAILING SPACE. It is not a
	# typo in this table: `Dove_Run to Idle ` is what the exporter wrote, and a
	# lookup without it finds nothing and drops the take silently.
	["Dove_Run to Idle ", RUN_TO_IDLE, false, 0.292],
	# The departure and the return.
	["Dove_Idle to Fly", TAKE_OFF, false, 0.375],
	["Dove_Fly", FLY, true, 0.583],
	["Dove_Fly to Idle", LAND, false, 0.417],
	# Neither is played. `Dove_Atttack` is the pack's own spelling; a pigeon
	# pecking at grit is what the take actually reads as, so it is named for that
	# rather than for what a Unity demo used it as.
	["Dove_Atttack", PECK, false, 1.667],
	["Dove_Death", DEATH, false, 0.875],
]


## One library holding every take under its own name.
##
## Deep-duplicated before the loop flag is set, because `ResourceLoader` hands
## every caller the SAME instance (briefing trap 6) and writing `loop_mode` onto
## the shared one would edit the imported asset for everything that ever loads
## it -- including the next call to this function.
static func build() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var source := source_takes()
	for row in TAKES:
		var packed_name: String = row[0]
		if not source.has(packed_name):
			continue
		var take: Animation = (source[packed_name] as Animation).duplicate(true)
		take.loop_mode = Animation.LOOP_LINEAR if bool(row[2]) else Animation.LOOP_NONE
		library.add_animation(StringName(row[1]), take)
	return library


## Every take the model file imported, by the name the pack gave it.
##
## `CrowAnimations.animations_in()` walks a `PackedScene`'s SceneState for
## AnimationLibraries without instantiating anything, and that walk is not about
## crows -- it is about how Godot stores an imported AnimationPlayer. Reused
## rather than copied: a second copy of it is a second place for the
## `libraries/<name>` storage shape to be got wrong.
static func source_takes() -> Dictionary:
	if not ResourceLoader.exists(MODEL_PATH):
		return {}
	return CrowAnimations.animations_in(MODEL_PATH)


## How long a named take is meant to be, or -1 for a name this file does not
## carry. For the gate, and for anybody timing a behaviour against a take.
static func length_of(take: StringName) -> float:
	for row in TAKES:
		if StringName(row[1]) == take:
			return float(row[3])
	return -1.0
