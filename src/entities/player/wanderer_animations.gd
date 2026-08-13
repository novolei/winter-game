class_name WandererAnimations
extends RefCounted

## Every take the Winter Wanderer has, in one AnimationLibrary, under names that
## say what the motion is.
##
## The takes arrived in three files and none of them was authoritative about
## what it held. The character file carried eighteen under Meshy's own names;
## two more came later as animation-only FBXs, one of them named after a UUID.
## Each one below was identified by rendering it and watching the motion, not by
## reading its filename -- and the renamings are recorded in TAKES so the
## cross-reference back to Meshy survives the next delivery.
##
## ALL TWENTY-ONE COME OUT OF ONE FILE, and that is a build-time decision rather
## than a convenience. The two later takes are merged into the character `.glb`
## by tools/decimate_character.py, through the same Blender round trip that
## produced the model. Reading them out of their own `.fbx` instead does not
## work: Godot's FBX importer lands the identical rig in a different space from
## the glTF one -- metres against the model's centimetres, and the idle still
## Z-up -- so the same Hips rest measures 85.07 on one path and 0.84 on the
## other. A track copied across that gap scales the skeleton by a hundred, and
## what you see is not an error but a character who has disappeared, his bones
## flung tens of metres apart. test_wanderer_animations.gd pins the units for
## exactly this reason.
##
## What is left here is naming, loop flags, and one path fix, and no retargeting
## at all for those twenty-one -- one rig, one file, one space.
##
## THE TWENTY-SECOND IS THE EXCEPTION AND IT IS DELIBERATE. `idle_hunched` comes
## out of a `.tres` baked by tools/retarget_hunch.gd from another pack's rig,
## because the posture 饥饿 needed does not exist in this library and was
## measured not to exist rather than assumed. See IDLE_HUNCHED below.

const MODEL_PATH := "res://assets/models/characters/winter_wanderer.glb"

## Where the skeleton hangs under the character model, and therefore the prefix
## every track in the merged library has to address.
const SKELETON_PATH := "Armature/Skeleton3D"

## The four the movement code asks for by name. Named constants rather than
## string literals at the call site so a rename here is a compile-time move.
const IDLE := &"idle"
const IDLE_COLD := &"idle_cold"
const WALK := &"walk"
const RUN := &"run"

## The fifth: what a man walks like when his feet have gone.
##
## ---------------------------------------------------------------------------
## THE TAKE NAMED `Limping_Walk_inplace` DOES NOT LIMP. MEASURED, NOT READ.
## ---------------------------------------------------------------------------
## A limp is an ASYMMETRY -- one leg lifts less, or stays down longer, or the hip
## drops onto it -- so that is what was measured, with
## tools/measure_body_readouts.gd, over one gait cycle of each candidate:
##
##     take          foot lift L/R   ratio   left-against-right-mirrored
##     walk           13.70 / 13.69   0.999   0.934      symmetric, as expected
##     walk_limp       7.85 /  9.01   0.871   0.933      SYMMETRIC. Not a limp.
##     walk_weary      8.51 /  2.02   0.238  -0.047      one foot barely leaves
##                                                       the ground. THIS limps.
##
## So the names are swapped, in the third instance of briefing trap 15 on this
## project: `Limping_Walk_inplace` is a low, guarded, short-stepped walk with
## both feet doing the same thing, and `Injured_Walk` is the one with a dragged
## leg.
##
## ---------------------------------------------------------------------------
## AND THE ONE THAT LIMPS IS THE ONE WE CANNOT USE
## ---------------------------------------------------------------------------
## Every take here is IN PLACE -- root travel is under half a centimetre per
## cycle -- so the speed a clip was authored for is the rate its STANCE foot
## slides backwards under the hips. Measured the same way, calibrated against
## anim_walk_speed = 1.35 (itself the speed at which the walk's feet plant), and
## corroborated by the run coming out at 4.29 against the shipped 4.6:
##
##     walk        1.350 m/s        walk_limp   0.924 m/s
##     run         4.293 m/s        walk_weary  0.523 m/s
##
## `walk_weary` is authored for a man moving at 0.52 m/s. The standing ruling is
## that the body GATES movement and never scales it, so a man with ruined feet
## still walks at 1.35 on bare ground -- and playing walk_weary there means
## running the clip at 2.58x, a hobble at 214 steps a minute. The only ways out
## are to blur the take or to let the body scale a speed, and the second is a
## ruling nobody here gets to change.
##
## `walk_limp` at 0.924 m/s needs 1.46x on bare ground -- inside the shipped
## anim_max_pace guard of 1.5 -- and almost exactly 1.0x at the 0.88-1.09 m/s
## the snow actually gives him, which is where a man with ruined feet spends most
## of his time.
##
## ---------------------------------------------------------------------------
## ...AND BILATERAL IS THE RIGHT READING ANYWAY
## ---------------------------------------------------------------------------
## Worth saying plainly, because it turns a compromise into the correct choice:
## GDD section 5's 足部冻伤 is BOTH feet. A limp is what a man does when ONE leg
## is hurt and the other can carry him. Frostbite has no good leg, and what it
## produces is a short, low, careful, bilateral gait -- which is what walk_limp
## measures as: both feet lifting 40% less than the walk's and staying down
## longer.
const WALK_GUARDED := &"walk_guarded"

## How many gait cycles are inside the guarded walk's take.
##
## The take is 3.5667 s where the walk is 1.0667, and the difference is not a
## slower cycle -- it is THREE of them. Autocorrelating the foot height trace
## puts the cycle at 1.19 s. Dropping the take onto the graph as though its
## LENGTH were its period would step three strides per stride and photograph a
## man vibrating.
##
## A count rather than a period, so the period is derived from the clip's own
## length and a re-export at a different length retimes itself -- the same
## discipline _build_animation() applies to the walk and the run.
const WALK_GUARDED_CYCLES := 3

## Ground speed the guarded walk's feet plant at, in m/s. Measured; see the block
## above. tests/unit/test_body_readouts.gd re-derives the relationship rather
## than trusting this number, because a constant that must agree with another
## value is a relationship and not a constant.
const WALK_GUARDED_SPEED := 0.924

## The sixth, and the only one that is not in the character file: what a starving
## man's stand looks like.
##
## ---------------------------------------------------------------------------
## IT IS NOT MESHY'S, AND IT WAS MEASURED BEFORE IT WAS WANTED
## ---------------------------------------------------------------------------
## 饥饿 had no single-frame reading at all. Its whole visible expression was a
## pace -- and a pace is RELATIVE, legible only against a second man the game
## does not contain, where a posture is ABSOLUTE and legible in one frame. Two
## agents measured that and reached the same conclusion independently.
##
## The gesture the design wanted -- a hand to the stomach -- does not exist:
## 85 takes across this rig and the RPG-Character rig were sampled off the
## SKELETON, not read off names, and nothing holds a hand at the belly except
## `idle_cold`, which the cold readout already owns.
##
## What does exist is `UnarmedIdleInjured` in the RPG-Character pack: a HELD
## standing hunch, 34.9 degrees for the whole of a 1.7 s looping idle with 0.4
## degrees of variation. It is on the wrong rig, so it is retargeted by
## tools/retarget_hunch.gd and baked to the `.tres` below.
##
## ---------------------------------------------------------------------------
## 26.8 DEGREES, NOT 34.9, AND THE DIFFERENCE IS NOT A LOSS
## ---------------------------------------------------------------------------
## The 34.9 is that rig's ABSOLUTE lean, and it includes the 8.1 degrees its own
## neutral idle already slouches. What is authored -- and what is the only thing
## a retarget can carry -- is the DIFFERENCE between its neutral stand and its
## injured one, which is 26.8 degrees. Measured on the baked take: 26.5 to 26.9.
##
## For scale, on this rig and this metric: `idle` leans 1.9 degrees and
## `idle_cold` 14.6. The hunch is roughly twice the cold huddle's lean and it
## changes the figure's HEIGHT, which is what makes it readable with no
## reference beside it.
const IDLE_HUNCHED := &"idle_hunched"

## Where that bake lands. Generated, never hand-authored (briefing constraint 7);
## re-run tools/retarget_hunch.gd to rebuild it.
##
## It lives under data/ rather than beside the model because assets/models is the
## art gates' root -- everything under it is scanned for a triangle budget, a
## scale band and a collision policy, and this is an animation, not a thing that
## appears in the world.
const HUNCH_PATH := "res://data/animation/wanderer_hunch.tres"

## [source file, take name in that file, name in the library, loops].
##
## LOOPS is measured, not guessed: the take loops when its last pose returns to
## its first with the root translation taken out. The numbers are in the wave
## report. Two of these are close calls and are written down there rather than
## hidden here -- walk_balance misses by 30 cm and does not loop, walk_aim_forward
## misses by 14 cm and does.
const TAKES: Array = [
	# --- what the game uses now ---
	[MODEL_PATH, "idle_cold_shiver", "idle_cold", true],
	[MODEL_PATH, "idle_neutral", "idle", true],
	[MODEL_PATH, "Walking", "walk", true],
	[MODEL_PATH, "Running", "run", true],
	# Named for what it is rather than for what Meshy called it -- see
	# WALK_GUARDED above for the measurements that renamed it.
	[MODEL_PATH, "Limping_Walk_inplace", "walk_guarded", true],

	# --- locomotion the game will want ---
	[MODEL_PATH, "Run_02", "run_alt", true],
	[MODEL_PATH, "Sprint_and_Sudden_Stop", "run_to_stop", false],
	[MODEL_PATH, "Injured_Walk", "walk_weary", true],
	[MODEL_PATH, "Spear_Walk", "walk_carry", true],
	[MODEL_PATH, "Tightrope_Walk_inplace", "walk_balance", false],

	# --- crouched ---
	[MODEL_PATH, "Sneaky_Walk", "crouch_creep", true],
	[MODEL_PATH, "Cautious_Crouch_Walk_Forward_inplace", "crouch_walk_forward", true],
	[MODEL_PATH, "Cautious_Crouch_Walk_Backward", "crouch_walk_back", true],
	[MODEL_PATH, "Cautious_Crouch_Walk_Left", "crouch_walk_left", true],

	# --- hands busy: the closest thing the file has to aiming a tool ---
	[MODEL_PATH, "Walk_Forward_While_Shooting", "walk_aim_forward", true],
	[MODEL_PATH, "Walk_Backward_While_Shooting", "walk_aim_back", true],
	[MODEL_PATH, "Rifle_Turn_Left", "aim_turn_left", false],
	[MODEL_PATH, "Rifle_Aim_Turn_Right", "aim_turn_right", false],

	# --- going down ---
	[MODEL_PATH, "knockdown_and_recover", "knockdown_recover", false],
	[MODEL_PATH, "dying_backwards", "death_collapse_back", false],
	[MODEL_PATH, "Shot_and_Slow_Fall_Backward", "death_slow_back", false],
]


## One library holding every take under its library name.
##
## Allocates no Node: the animations are lifted out of each PackedScene's
## SceneState rather than out of an instantiated tree, so nothing here has to be
## freed and a test may call it freely (briefing section 2.2).
static func build() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var cache: Dictionary = {}
	for row in TAKES:
		var source: String = row[0]
		if not cache.has(source):
			cache[source] = animations_in(source)
		var found: Dictionary = cache[source]
		var take: String = row[1]
		if not found.has(take):
			push_warning("wanderer_animations: %s holds no take called %s" % [source, take])
			continue
		# Trap 6: ResourceLoader hands every caller the same instance, so the
		# animation inside the imported scene is shared. Retargeting or setting a
		# loop mode on it would edit the asset for everything that ever loads it.
		var animation: Animation = (found[take] as Animation).duplicate(true)
		_retarget(animation)
		animation.loop_mode = Animation.LOOP_LINEAR if bool(row[3]) else Animation.LOOP_NONE
		library.add_animation(StringName(row[2]), animation)
	_add_hunch(library)
	return library


## The one take that comes out of a `.tres` instead of out of the model.
##
## Warns rather than fails when the bake is absent: every other take still
## works, and a library that refuses to build would take the whole character
## down over one readout. PlayerController checks for the clip by name and says
## so if it is missing, which is the place that can actually do something about
## it.
static func _add_hunch(library: AnimationLibrary) -> void:
	if not ResourceLoader.exists(HUNCH_PATH):
		push_warning("wanderer_animations: %s is missing; the hunger hunch will not play"
			% HUNCH_PATH)
		return
	var resource := ResourceLoader.load(HUNCH_PATH)
	if not (resource is Animation):
		push_warning("wanderer_animations: %s did not load as an Animation" % HUNCH_PATH)
		return
	# Trap 6 again: ResourceLoader hands every caller the same instance, so this
	# is duplicated before its loop mode is touched -- otherwise the second
	# library built in a run would be editing the first one's take.
	var animation: Animation = (resource as Animation).duplicate(true)
	animation.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(IDLE_HUNCHED, animation)


## Every animation in an imported scene, by the name its AnimationPlayer knows.
##
## Read off PackedScene.get_state() rather than instantiate(): a SceneState is
## walked without building a node tree, so nothing here allocates a Node and
## nothing has to be freed. An AnimationPlayer stores one property per library,
## named `libraries/<name>` -- `libraries/` for the unnamed default one every
## importer writes -- and the value is the AnimationLibrary itself rather than a
## dictionary of them. Measured on 4.7.1; there is no API that reports this.
static func animations_in(path: String) -> Dictionary:
	var found: Dictionary = {}
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		push_warning("wanderer_animations: %s did not load as a PackedScene" % path)
		return found
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			var value = state.get_node_property_value(node, property)
			if not (value is AnimationLibrary):
				continue
			var library := value as AnimationLibrary
			for name in library.get_animation_list():
				found[String(name)] = library.get_animation(name)
	return found


## Bone names in an imported scene's skeleton, sorted. The evidence behind the
## claim that these files share a rig.
static func bone_names(path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		return names
	var scene := (resource as PackedScene).instantiate()
	for node in scene.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for index in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(index))
	scene.free()
	names.sort()
	return names


## Point every skeleton track at the character model's own skeleton node.
##
## A no-op today, and kept deliberately: every take now comes out of one file
## and every track already addresses `Armature/Skeleton3D`. It is here for the
## delivery that does not -- Meshy has already shipped one rig under a node
## called `target_character` -- because a track whose path resolves to nothing
## does not error, it just quietly animates no bone, and the character stands in
## his bind pose with the console clean. test_wanderer_animations.gd asserts the
## paths rather than trusting this to have been run.
##
## Only the node half of the path is touched, and only when it already ends in
## Skeleton3D -- a track addressing something else (a mesh's blend shape, a
## visibility toggle) is left exactly as it was rather than being swept into the
## skeleton by a blanket rewrite.
static func _retarget(animation: Animation) -> void:
	for index in range(animation.get_track_count()):
		var path := String(animation.track_get_path(index))
		var colon := path.find(":")
		if colon <= 0:
			continue
		var node_part := path.substr(0, colon)
		if node_part == SKELETON_PATH or not node_part.ends_with("Skeleton3D"):
			continue
		animation.track_set_path(index, NodePath(SKELETON_PATH + path.substr(colon)))
