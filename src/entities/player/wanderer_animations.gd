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
## ALL TWENTY NOW COME OUT OF ONE FILE, and that is a build-time decision rather
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
## at all -- one rig, one file, one space.

const MODEL_PATH := "res://assets/models/characters/winter_wanderer.glb"

## Where the skeleton hangs under the character model, and therefore the prefix
## every track in the merged library has to address.
const SKELETON_PATH := "Armature/Skeleton3D"

## The three the movement code asks for by name. Named constants rather than
## string literals at the call site so a rename here is a compile-time move.
const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"

## [source file, take name in that file, name in the library, loops].
##
## LOOPS is measured, not guessed: the take loops when its last pose returns to
## its first with the root translation taken out. The numbers are in the wave
## report. Two of these are close calls and are written down there rather than
## hidden here -- walk_balance misses by 30 cm and does not loop, walk_aim_forward
## misses by 14 cm and does.
const TAKES: Array = [
	# --- what the game uses now ---
	[MODEL_PATH, "idle_neutral", "idle", true],
	[MODEL_PATH, "Walking", "walk", true],
	[MODEL_PATH, "Running", "run", true],

	# --- locomotion the game will want ---
	[MODEL_PATH, "Run_02", "run_alt", true],
	[MODEL_PATH, "Sprint_and_Sudden_Stop", "run_to_stop", false],
	[MODEL_PATH, "Injured_Walk", "walk_weary", true],
	[MODEL_PATH, "Limping_Walk_inplace", "walk_limp", true],
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
	return library


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
