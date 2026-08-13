extends Node

## Carry ONE authored posture from the RPG-Character rig onto the wanderer, and
## bake it, so the thing the game loads is a measured artefact rather than a
## computation nobody watched.
##
##   Godot_console.exe --headless --path <project> res://tools/retarget_hunch.tscn \
##       -- [--probe] [--out res://data/animation/wanderer_hunch.tres]
##
## `--probe` writes nothing and prints the tables the map below was built from:
## both hierarchies, both anatomical frames, the per-bone rotation the source
## take actually holds, and how far the wanderer's own idle sits from its rest.
##
## ---------------------------------------------------------------------------
## WHY A BAKE AND NOT A RETARGET AT LOAD TIME
## ---------------------------------------------------------------------------
## WandererAnimations.build() allocates no Node -- the takes are lifted out of a
## PackedScene's SceneState -- and a cross-rig retarget needs two posed
## skeletons, which means two instantiated trees on every call, in every test.
##
## The stronger reason is the one this project keeps paying for: a filename is
## not evidence of contents, and neither is a transform written by code nobody
## measured. A baked `.tres` can be loaded, sampled and asserted against by the
## suite -- tests/unit/test_hunger_hunch.gd does exactly that -- where a live
## computation would only ever be checked against itself.
##
## ---------------------------------------------------------------------------
## THE MATHS, AND THE REFERENCE POSE THAT IS THE WHOLE TRICK
## ---------------------------------------------------------------------------
## Bone rests differ between packs (A-pose against T-pose, a spine chain named
## backwards), so a pose cannot be copied. What transfers is a CHANGE:
##
##     Ds(t) = Gs_injured(t) * Gs_neutral^-1     how far this bone has turned
##                                               away from a NEUTRAL STAND, in
##                                               the source rig's own space
##     Dt(t) = C * Ds(t) * C^-1                  the same turn, in target space
##     Gt(t) = Dt(t) * Rt                        applied to the target's own
##                                               neutral stand
##
## THE REFERENCE IS `UnarmedIdle`, NOT THE SOURCE RIG'S REST, and that is not a
## refinement -- it is what makes the transfer work at all. Measured (--probe),
## the RPG rig's takes sit a very long way from its rest: `UnarmedIdle`'s own
## left forearm is 212.6 degrees away from its rest bone. Its rest is a rigging
## artefact, not a pose anybody stands in, so a rest-to-rest delta would carry
## 212 degrees of it onto the wanderer and photograph a broken man.
##
## Two neutral STANDS are anatomically the same sentence, which is what a
## correspondence needs to be. And on the target side the neutral stand is
## exactly the rest: measured, every one of the wanderer's 24 bones sits 0.0
## degrees from its rest at `idle` frame 0. So `Rt` IS his neutral idle, and the
## baked take is his own stand with the authored hunch on top of it.
##
## The source reference is AVERAGED over the whole neutral take rather than
## sampled at one instant, because `UnarmedIdle` breathes through 5 to 12
## degrees and picking a frame would bake one lungful in as a constant bias.
##
## `C` maps one rig's anatomical axes onto the other's, and both are derived
## from the rests rather than assumed -- see _frame_of(). The RPG rig faces -Z
## and the wanderer +Z, so C is essentially a half turn; deriving it instead of
## writing `rotate_y(PI)` is what makes this tool survive the next pack.
##
## Conjugation is the part that is easy to get wrong. Dt has to be `C Ds C^-1`
## and not `C Ds`: a rotation of 35 degrees about the source's left axis must
## become a rotation of 35 degrees about the TARGET's left axis, and only
## conjugation maps the axis while leaving the angle alone.
##
## ---------------------------------------------------------------------------
## THE LEGS ARE NOT TRANSFERRED, AND THAT IS A DECISION
## ---------------------------------------------------------------------------
## The map below stops at the pelvis. Everything from the pelvis up is carried;
## the legs and the toes keep the target's own rest, which is where the
## wanderer's neutral idle already stands, so his feet stay where the ground is.
## The two rigs' leg proportions are not the same and the source take is a stand
## -- there is nothing in its legs worth the risk of moving his feet.
##
## ---------------------------------------------------------------------------
## AND IT KEEPS THE SOURCE TAKE'S LIFE, WHICH WAS CHECKED BEFORE IT WAS ASSUMED
## ---------------------------------------------------------------------------
## Every frame is transferred, not one. `UnarmedIdleInjured` breathes: measured,
## its torso wanders 3.1 degrees and its left upper arm 11.3 across the take's
## 1.7 s, against the wanderer's own idle wandering 6 to 29 over FOURTEEN
## seconds. Per second it is the more alive of the two, so a frozen pose would
## have been a worse idle as well as a lazier bake -- and "the idle is stiff" is
## a complaint this project has already had once.

const SOURCE_MODEL := "res://assets/rigs/rpg_character/Unarmed.glb"
const SOURCE_TAKE := "UnarmedIdleInjured"
const SOURCE_NEUTRAL := "UnarmedIdle"
const OUT_PATH := "res://data/animation/wanderer_hunch.tres"

## Sampled at the rate the pack was imported at (animation/fps=30 in its
## .import), so no key is invented between two the artist authored.
const FPS := 30.0

## Wanderer bone -> the RPG-Character bone whose orientation it takes.
##
## ---------------------------------------------------------------------------
## MAPPED BY HEIGHT UP THE BODY, NOT BY NAME. THE NAMES DO NOT CORRESPOND.
## ---------------------------------------------------------------------------
## The obvious map -- first spine bone to first spine bone -- was written,
## baked, and MEASURED, and it delivered a 10.5 degree hunch against the source
## take's 34.9. Nothing errored. Every joint angle arrived correct to a tenth of
## a degree (the bake prints them) and the silhouette still did not, because
## where a joint angle PUTS the head depends on how much body is above it.
##
## Rest offsets from the hip joint, in centimetres on the 1.88 m body, as a
## fraction of that rig's own hips-to-head height (--probe prints this):
##
##     source  B_Spine    +7.6   9.6%      target  Spine02  +14.9  29.3%
##             B_Spine1  +22.0  27.8%              Spine01  +29.9  58.9%
##             B_Spine2  +42.7  54.0%              Spine    +44.8  88.2%
##             B_Neck    +70.2  88.7%              neck     +41.3  81.3%
##             B_Head    +79.1 100.0%              Head     +50.8 100.0%
##
## The RPG rig's pelvis bone sits at the crotch, so its three "spine" bones
## span the whole torso; the wanderer's sits at the hip joint and his three span
## only 45 cm, with the neck immediately above. `B_Spine2` is a MID-BACK bone
## with 27.5 cm of body above it. `Spine` is the BASE OF THE NECK with 6 cm above
## it. Giving the wanderer's Spine the mid-back's 51 degree bend swings six
## centimetres of neck and nothing else -- which is precisely the 10.5 degrees
## that came out.
##
## Matched on the fractions instead, every pair lands within 5 points:
##
##     Spine02 29.3% <- B_Spine1  27.8%          Spine  88.2% <- B_Neck  88.7%
##     Spine01 58.9% <- B_Spine2  54.0%          neck   81.3% <- B_Neck  88.7%
##     Head   100.0% <- B_Head   100.0%          Hips    0.0% <- B_Pelvis 0.0%
##
## NOTHING IS LOST BY TWO TARGETS SHARING A SOURCE, OR BY `B_Spine` HAVING NO
## TARGET AT ALL. The transfer is of GLOBAL orientation, which is cumulative
## down the chain: `B_Spine1`'s global delta already contains `B_Spine`'s. What
## crosses is "which way the body faces at this height", not "how far this named
## joint bent", and that is the only quantity the two rigs can both express.
##
## The arms map by name because clavicles are clavicles; their global
## orientations transfer whatever their parents do.
const BONE_MAP := {
	"Hips": "B_Pelvis",
	"Spine02": "B_Spine1",
	"Spine01": "B_Spine2",
	"Spine": "B_Neck",
	"neck": "B_Neck",
	"Head": "B_Head",
	"LeftShoulder": "B_L_Clavicle",
	"LeftArm": "B_L_UpperArm",
	"LeftForeArm": "B_L_Forearm",
	"LeftHand": "B_L_Hand",
	"RightShoulder": "B_R_Clavicle",
	"RightArm": "B_R_UpperArm",
	"RightForeArm": "B_R_Forearm",
	"RightHand": "B_R_Hand",
}

var _probe := false
var _out := OUT_PATH
var _source_root: Node3D = null
var _target_root: Node3D = null
var _source: Skeleton3D = null
var _target: Skeleton3D = null
var _source_player: AnimationPlayer = null
var _target_player: AnimationPlayer = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_probe = args.has("--probe")
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
	if not _load():
		get_tree().quit(1)
		return
	if _probe:
		_report()
	else:
		_bake()
	get_tree().quit()


func _load() -> bool:
	for path in [SOURCE_MODEL, WandererAnimations.MODEL_PATH]:
		if not ResourceLoader.exists(path):
			print("retarget_hunch: %s is not in the project" % path)
			return false
	_source_root = (ResourceLoader.load(SOURCE_MODEL) as PackedScene).instantiate() as Node3D
	add_child(_source_root)
	_target_root = (ResourceLoader.load(WandererAnimations.MODEL_PATH)
		as PackedScene).instantiate() as Node3D
	add_child(_target_root)
	_source = _first(_source_root, "Skeleton3D") as Skeleton3D
	_target = _first(_target_root, "Skeleton3D") as Skeleton3D
	_source_player = _first(_source_root, "AnimationPlayer") as AnimationPlayer
	_target_player = _first(_target_root, "AnimationPlayer") as AnimationPlayer
	if _source == null or _target == null or _source_player == null or _target_player == null:
		print("retarget_hunch: one of the two models has no skeleton or no AnimationPlayer")
		return false
	if _target_player.has_animation_library(&""):
		_target_player.remove_animation_library(&"")
	_target_player.add_animation_library(&"", WandererAnimations.build())
	_source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_target_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return true


func _exit_tree() -> void:
	# Freed rather than left to the tree: this runs under a scene, but a tool that
	# leaks is a tool nobody can call from a test (briefing constraint 2.2).
	if _source_root != null and is_instance_valid(_source_root):
		_source_root.queue_free()
	if _target_root != null and is_instance_valid(_target_root):
		_target_root.queue_free()


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


## The anatomical basis of a rig, off its own rest pose: x left, y up, z forward.
##
## Identical in derivation to tools/measure_hand_gesture.gd, deliberately -- the
## hunch angle this tool has to reproduce is the one that tool measured, and two
## tools that disagree about which way is up would disagree about the answer
## while both looking right.
func _frame_of(skeleton: Skeleton3D, hips: String, head: String, foot: String,
		toe: String, thigh: String) -> Basis:
	var pelvis := skeleton.get_bone_global_rest(skeleton.find_bone(hips)).origin
	var up := (skeleton.get_bone_global_rest(skeleton.find_bone(head)).origin - pelvis).normalized()
	var forward := (skeleton.get_bone_global_rest(skeleton.find_bone(toe)).origin
		- skeleton.get_bone_global_rest(skeleton.find_bone(foot)).origin)
	forward = (forward - up * forward.dot(up)).normalized()
	var left := up.cross(forward).normalized()
	if (skeleton.get_bone_global_rest(skeleton.find_bone(thigh)).origin - pelvis).dot(left) < 0.0:
		left = -left
	return Basis(left, up, forward).orthonormalized()


func _source_frame() -> Basis:
	return _frame_of(_source, "B_Pelvis", "B_Head", "B_L_Foot", "B_L_Toe0", "B_L_Thigh")


func _target_frame() -> Basis:
	return _frame_of(_target, "Hips", "Head", "LeftFoot", "LeftToeBase", "LeftUpLeg")


## Rig units to metres, off the SKELETON's rest hull along the body's own up.
##
## Not Mesh.get_aabb(): it reports both of these characters at roughly 1/100 of
## life size (briefing trap 15.3), and a ratio taken from it would be out by two
## orders of magnitude in whichever direction the two rigs disagreed.
func _rest_height(skeleton: Skeleton3D, frame: Basis) -> float:
	var top := -INF
	var bottom := INF
	for index in range(skeleton.get_bone_count()):
		var along := skeleton.get_bone_global_rest(index).origin.dot(frame.y)
		top = maxf(top, along)
		bottom = minf(bottom, along)
	return maxf(top - bottom, 0.0001)


func _pose_source(take: String, at: float) -> void:
	_source_player.play(take)
	_source_player.seek(at, true)
	_source_player.advance(0.0)


## The source rig's NEUTRAL STAND, averaged over `UnarmedIdle`: per source bone
## index, a global basis and a global origin.
##
## Rotations are averaged as quaternions with the sign aligned to the first
## sample -- q and -q are the same rotation, and summing them unaligned cancels
## them out to nothing, which is the silent way to get an identity here and
## never notice.
func _neutral_reference() -> Dictionary:
	var length := _source_player.get_animation(SOURCE_NEUTRAL).length
	var count: int = maxi(int(length * FPS), 2)
	var sums := {}
	var origins := {}
	for step in range(count):
		_pose_source(SOURCE_NEUTRAL, length * float(step) / float(count))
		for index in range(_source.get_bone_count()):
			var pose := _source.get_bone_global_pose(index)
			var quaternion := pose.basis.orthonormalized().get_rotation_quaternion()
			if step == 0:
				sums[index] = quaternion
				origins[index] = pose.origin
				continue
			var running: Quaternion = sums[index]
			if running.dot(quaternion) < 0.0:
				quaternion = -quaternion
			sums[index] = Quaternion(
				running.x + quaternion.x, running.y + quaternion.y,
				running.z + quaternion.z, running.w + quaternion.w
			)
			origins[index] = (origins[index] as Vector3) + pose.origin
	var reference := {}
	for index in range(_source.get_bone_count()):
		reference[index] = {
			"basis": Basis((sums[index] as Quaternion).normalized()),
			"origin": (origins[index] as Vector3) / float(count),
		}
	return reference


## The whole retarget, for one instant, as target-local transforms by bone index.
##
## Returned as locals rather than written into the skeleton so the caller can
## bake them without a second pass, and so a test can ask for one frame.
func _retarget_at(at: float, reference: Dictionary, conjugate: Basis,
		metres_per_unit: float) -> Dictionary:
	_pose_source(SOURCE_TAKE, at)

	# Global target bases, filled in hierarchy order so a child can read its
	# parent. Every bone gets an entry -- unmapped ones inherit their rest local,
	# which is what keeps the legs where the wanderer authored them.
	var globals: Array[Basis] = []
	globals.resize(_target.get_bone_count())
	var locals := {}
	for index in range(_target.get_bone_count()):
		var name := _target.get_bone_name(index)
		var parent := _target.get_bone_parent(index)
		var parent_basis := Basis.IDENTITY if parent < 0 else globals[parent]
		var local := _target.get_bone_rest(index)
		var source_name := _source_name_for(name)
		if source_name != "":
			var s := _source.find_bone(source_name)
			var neutral: Dictionary = reference[s]
			var delta := (_source.get_bone_global_pose(s).basis.orthonormalized()
				* (neutral["basis"] as Basis).inverse()).orthonormalized()
			delta = (conjugate * delta * conjugate.inverse()).orthonormalized()
			var global := (delta * _target.get_bone_global_rest(index).basis).orthonormalized()
			local.basis = (parent_basis.inverse() * global).orthonormalized()
			if parent < 0:
				# The root's TRANSLATION as well as its turn: a man who bends over
				# also drops. Carried in the target's own units -- the source is
				# 229.6 rig units tall and the wanderer 157.9 -- and rotated into
				# the target's frame like everything else.
				var travel: Vector3 = (_source.get_bone_global_pose(s).origin
					- (neutral["origin"] as Vector3)) * metres_per_unit
				local.origin = _target.get_bone_rest(index).origin + conjugate * travel
		globals[index] = (parent_basis * local.basis).orthonormalized()
		locals[index] = local
	return locals


func _source_name_for(target_name: String) -> String:
	return String(BONE_MAP.get(target_name, ""))


## ---------------------------------------------------------------------------
## The bake
## ---------------------------------------------------------------------------
## Position tracks are written for every bone, not only for the hips, and that
## is not padding. An AnimationTree blends each track against the bone's own
## default for whatever weight no input supplies -- so a take carrying only
## rotations would drag every bone's position toward rest as its weight rose.
## The wanderer's own takes carry 24 position and 24 rotation tracks and no
## scale tracks at all (measured, --probe), and this take is built to the same
## shape so that a blend between them can never be a blend between two different
## sets of tracks.
func _bake() -> void:
	var length := _source_player.get_animation(SOURCE_TAKE).length
	var frames: int = maxi(int(round(length * FPS)), 2)
	var source_frame := _source_frame()
	var target_frame := _target_frame()
	# Source axes onto target axes. Both are orthonormal, so this is a pure
	# rotation and its inverse is its transpose.
	var conjugate := (target_frame * source_frame.inverse()).orthonormalized()
	var metres_per_unit := (_rest_height(_target, target_frame)
		/ _rest_height(_source, source_frame))
	var reference := _neutral_reference()

	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	animation.step = 1.0 / FPS

	var rotation_tracks := {}
	var position_tracks := {}
	for index in range(_target.get_bone_count()):
		var path := NodePath("%s:%s" % [
			WandererAnimations.SKELETON_PATH, _target.get_bone_name(index),
		])
		var position := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position, path)
		animation.track_set_interpolation_type(position, Animation.INTERPOLATION_LINEAR)
		position_tracks[index] = position
		var rotation := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation, path)
		animation.track_set_interpolation_type(rotation, Animation.INTERPOLATION_LINEAR)
		rotation_tracks[index] = rotation

	for step in range(frames):
		var at := length * float(step) / float(frames)
		var locals := _retarget_at(at, reference, conjugate, metres_per_unit)
		for index in range(_target.get_bone_count()):
			var local: Transform3D = locals[index]
			animation.rotation_track_insert_key(
				rotation_tracks[index], at, local.basis.get_rotation_quaternion()
			)
			animation.position_track_insert_key(position_tracks[index], at, local.origin)

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_out.get_base_dir())
	)
	var error := ResourceSaver.save(animation, _out)
	if error != OK:
		print("retarget_hunch: FAILED to write %s (%d)" % [_out, error])
		get_tree().quit(1)
		return
	print("retarget_hunch: wrote %s -- %.4f s, %d frames, %d tracks" % [
		_out, animation.length, frames, animation.get_track_count(),
	])
	_verify(animation)


## Measured off the baked resource, not off the maths that produced it.
##
## The lean is the same quantity tools/measure_hand_gesture.gd reports, so the
## number printed here is directly comparable with the 34.9 degrees the source
## take holds -- which is the only way to know the posture arrived.
func _verify(animation: Animation) -> void:
	var library := AnimationLibrary.new()
	library.add_animation(&"probe", animation)
	_target_player.add_animation_library(&"probe", library)
	var frame := _target_frame()
	var scale := 188.0 / _rest_height(_target, frame)
	var lean_min := INF
	var lean_max := -INF
	var head_up := INF
	var head_forward := -INF
	var count: int = maxi(int(animation.length * FPS), 2)
	for step in range(count):
		_target_player.play(&"probe/probe")
		_target_player.seek(animation.length * float(step) / float(count), true)
		_target_player.advance(0.0)
		var root := _target.get_bone_global_pose(_target.find_bone("Hips")).origin
		var head := _target.get_bone_global_pose(_target.find_bone("Head")).origin - root
		var local := Vector3(head.dot(frame.x), head.dot(frame.y), head.dot(frame.z))
		var lean := 90.0 - rad_to_deg(Vector2(Vector2(local.x, local.z).length(), local.y).angle())
		lean_min = minf(lean_min, lean)
		lean_max = maxf(lean_max, lean)
		head_up = minf(head_up, local.y * scale)
		head_forward = maxf(head_forward, local.z * scale)
	# What the bones actually ended up doing, against what the source asked for.
	# A chain can carry every joint angle faithfully and still put the head
	# somewhere else, because where the head goes depends on the segment lengths
	# as well as the angles -- so both are printed and neither is inferred.
	_target_player.play(&"probe/probe")
	_target_player.seek(animation.length * 0.5, true)
	_target_player.advance(0.0)
	var line := PackedStringArray()
	for index in range(_target.get_bone_count()):
		var delta := (_target.get_bone_global_pose(index).basis.orthonormalized()
			* _target.get_bone_global_rest(index).basis.orthonormalized().inverse()
			).orthonormalized()
		line.append("%s %.1f" % [
			_target.get_bone_name(index),
			rad_to_deg(delta.get_rotation_quaternion().get_angle()),
		])
	print("retarget_hunch: baked bones, degrees from rest at mid-take:")
	print("  " + " | ".join(line))
	var scales := PackedStringArray()
	for index in range(_target.get_bone_count()):
		var rest_scale := _target.get_bone_rest(index).basis.get_scale()
		if absf(rest_scale.x - 1.0) > 0.001 or absf(rest_scale.y - 1.0) > 0.001 \
				or absf(rest_scale.z - 1.0) > 0.001:
			scales.append("%s %s" % [_target.get_bone_name(index), rest_scale])
	print("retarget_hunch: bones whose rest carries a scale: %s" % (
		"none" if scales.is_empty() else " | ".join(scales)
	))
	var spine := PackedStringArray()
	for name in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head"]:
		var index := _target.find_bone(name)
		var offset := (_target.get_bone_global_rest(index).origin
			- _target.get_bone_global_rest(_target.find_bone("Hips")).origin)
		spine.append("%s %.1f" % [name, offset.dot(frame.y) * scale])
	print("retarget_hunch: target rest spine, cm above the hip joint: %s" % " | ".join(spine))
	var root := _target.get_bone_global_pose(_target.find_bone("Hips")).origin
	var head_now := _target.get_bone_global_pose(_target.find_bone("Head")).origin - root
	print("retarget_hunch: baked head at mid-take, cm (left %.1f, up %.1f, fwd %.1f)" % [
		head_now.dot(frame.x) * scale, head_now.dot(frame.y) * scale,
		head_now.dot(frame.z) * scale,
	])
	print("retarget_hunch: baked take leans %.1f to %.1f deg; head %.1f cm up, %.1f cm forward"
		% [lean_min, lean_max, head_up, head_forward])
	print("retarget_hunch: the source take holds 34.7 to 35.1 deg -- if these disagree,")
	print("                the posture did not arrive and the bake is not usable.")


## ---------------------------------------------------------------------------
## --probe
## ---------------------------------------------------------------------------
func _report() -> void:
	var source_frame := _source_frame()
	var target_frame := _target_frame()
	print("source  %s" % SOURCE_MODEL)
	print("  frame  left %s  up %s  fwd %s" % [
		_terse(source_frame.x), _terse(source_frame.y), _terse(source_frame.z),
	])
	print("  rest height %.3f rig units" % _rest_height(_source, source_frame))
	print("target  %s" % WandererAnimations.MODEL_PATH)
	print("  frame  left %s  up %s  fwd %s" % [
		_terse(target_frame.x), _terse(target_frame.y), _terse(target_frame.z),
	])
	print("  rest height %.3f rig units" % _rest_height(_target, target_frame))

	print("")
	print("--- target hierarchy ---")
	for index in range(_target.get_bone_count()):
		var parent := _target.get_bone_parent(index)
		print("  %2d %-14s parent %-14s %s" % [
			index, _target.get_bone_name(index),
			"-" if parent < 0 else _target.get_bone_name(parent),
			"<- " + _source_name_for(_target.get_bone_name(index))
				if _source_name_for(_target.get_bone_name(index)) != "" else "",
		])

	print("")
	print("--- what the source take actually holds, per bone, at mid-take ---")
	print("degrees away from that bone's own rest, in the source rig's space.")
	var length := _source_player.get_animation(SOURCE_TAKE).length
	for take in [SOURCE_NEUTRAL, SOURCE_TAKE]:
		_pose_source(take, _source_player.get_animation(take).length * 0.5)
		var line := PackedStringArray()
		for index in range(_source.get_bone_count()):
			var name := _source.get_bone_name(index)
			if not BONE_MAP.has(name) and not name.begins_with("B_L_Thigh") \
					and not name.begins_with("B_L_Calf") and name != "Motion":
				continue
			var delta := (_source.get_bone_global_pose(index).basis
				* _source.get_bone_global_rest(index).basis.inverse()).orthonormalized()
			line.append("%s %.1f" % [name, rad_to_deg(
				delta.get_rotation_quaternion().get_angle()
			)])
		print("  %-20s %s" % [take, " | ".join(line)])
	print("  (take length %.4f s)" % length)

	print("")
	print("--- THE DELTA THAT ACTUALLY CROSSES: injured against the neutral stand ---")
	print("angle in degrees, and the axis in the source rig's own anatomical frame")
	print("(x left, y up, z forward) -- a forward bend is a turn about +/- x.")
	var neutral := _neutral_reference()
	var source_basis := _source_frame()
	var target_basis := _target_frame()
	var conjugate := (target_basis * source_basis.inverse()).orthonormalized()
	_pose_source(SOURCE_TAKE, _source_player.get_animation(SOURCE_TAKE).length * 0.5)
	for target_name in BONE_MAP:
		var key := String(BONE_MAP[target_name])
		var s := _source.find_bone(key)
		var reference_pose: Dictionary = neutral[s]
		var delta := (_source.get_bone_global_pose(s).basis.orthonormalized()
			* (reference_pose["basis"] as Basis).inverse()).orthonormalized()
		var quaternion := delta.get_rotation_quaternion()
		var axis := quaternion.get_axis()
		var carried := (conjugate * delta * conjugate.inverse()).orthonormalized()
		print("  %-14s -> %-14s %6.1f deg  axis (%+.2f %+.2f %+.2f)  carried %6.1f deg" % [
			key, target_name, rad_to_deg(quaternion.get_angle()),
			axis.dot(source_basis.x), axis.dot(source_basis.y), axis.dot(source_basis.z),
			rad_to_deg(carried.get_rotation_quaternion().get_angle()),
		])

	print("")
	print("--- the two spines, as rest offsets from the hip joint, in cm ---")
	print("(left, up, forward) in each rig's own anatomical frame. This is the")
	print("geometry that decides where a joint angle PUTS the head.")
	_spine_geometry(_source, source_basis, "B_Pelvis",
		["B_Pelvis", "B_Spine", "B_Spine1", "B_Spine2", "B_Neck", "B_Head"])
	_spine_geometry(_target, target_basis, "Hips",
		["Hips", "Spine02", "Spine01", "Spine", "neck", "Head"])

	print("")
	print("--- and how much LIFE the source takes carry, per bone ---")
	print("degrees the bone's GLOBAL orientation wanders across the take. A held")
	print("posture with no life in it would photograph as a statue at full weight.")
	for take in [SOURCE_NEUTRAL, SOURCE_TAKE]:
		var take_length := _source_player.get_animation(take).length
		var reference_pose := {}
		var wander := {}
		for step in range(int(take_length * FPS)):
			_pose_source(take, take_length * float(step) / (take_length * FPS))
			for index in range(_source.get_bone_count()):
				var global := _source.get_bone_global_pose(index).basis.orthonormalized()
				if step == 0:
					reference_pose[index] = global
					wander[index] = 0.0
				var apart: Basis = (reference_pose[index].inverse() * global).orthonormalized()
				wander[index] = maxf(wander[index], rad_to_deg(
					apart.get_rotation_quaternion().get_angle()
				))
		var wander_line := PackedStringArray()
		for index in range(_source.get_bone_count()):
			var name := _source.get_bone_name(index)
			if not BONE_MAP.values().has(name):
				continue
			wander_line.append("%s %.1f" % [name, wander[index]])
		print("  %-20s %s" % [take, " | ".join(wander_line)])

	print("")
	print("--- the wanderer's own idle: how far from rest, and how much it MOVES ---")
	print("from rest = degrees at the reference instant; swing = degrees the bone's")
	print("GLOBAL orientation wanders across the take, which is the error term in")
	print("treating the retarget offset as a constant.")
	var idle_length := _target_player.get_animation(&"idle").length
	var from_rest := {}
	var swing := {}
	var reference := {}
	for step in range(24):
		var at := idle_length * float(step) / 24.0
		_target_player.play(&"idle")
		_target_player.seek(at, true)
		_target_player.advance(0.0)
		for index in range(_target.get_bone_count()):
			var global := _target.get_bone_global_pose(index).basis.orthonormalized()
			if step == 0:
				reference[index] = global
				var local := (_target.get_bone_rest(index).basis.inverse()
					* Basis(_target.get_bone_pose_rotation(index))).orthonormalized()
				from_rest[index] = rad_to_deg(local.get_rotation_quaternion().get_angle())
				swing[index] = 0.0
			var apart: Basis = (reference[index].inverse() * global).orthonormalized()
			swing[index] = maxf(swing[index], rad_to_deg(
				apart.get_rotation_quaternion().get_angle()
			))
	var line := PackedStringArray()
	for index in range(_target.get_bone_count()):
		line.append("%s %.1f/%.1f" % [
			_target.get_bone_name(index), from_rest[index], swing[index],
		])
	print("  " + " | ".join(line))
	print("  (take length %.4f s)" % idle_length)

	print("")
	print("--- what the wanderer's idle carries as tracks ---")
	var idle := _target_player.get_animation(&"idle")
	var kinds := {}
	for track in range(idle.get_track_count()):
		var kind := idle.track_get_type(track)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	print("  %d tracks: %s  (2 = position, 3 = rotation, 4 = scale)" % [
		idle.get_track_count(), kinds,
	])


func _spine_geometry(skeleton: Skeleton3D, frame: Basis, root: String,
		chain: Array) -> void:
	var scale := 188.0 / _rest_height(skeleton, frame)
	var origin := skeleton.get_bone_global_rest(skeleton.find_bone(root)).origin
	var line := PackedStringArray()
	for name in chain:
		var offset := skeleton.get_bone_global_rest(skeleton.find_bone(name)).origin - origin
		line.append("%s (%+.1f %+.1f %+.1f)" % [
			name, offset.dot(frame.x) * scale, offset.dot(frame.y) * scale,
			offset.dot(frame.z) * scale,
		])
	print("  " + "  ".join(line))


func _terse(v: Vector3) -> String:
	return "(%+.2f %+.2f %+.2f)" % [v.x, v.y, v.z]
