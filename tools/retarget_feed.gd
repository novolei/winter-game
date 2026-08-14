extends SceneTree

## Bake the RPG pack's standing activation gesture onto the Winter Wanderer.
##
##   Godot_console.exe --headless --path <project> \
##       --script res://tools/retarget_feed.gd \
##       -- [--out res://data/animation/wanderer_feed.tres]
##
## This is deliberately an offline bake.  The two rigs have 53 and 24 bones,
## different rests, opposite facing directions, and different units.  Runtime
## retargeting would pay for two instantiated rigs and leave the result harder to
## inspect than the generated Animation resource the game actually consumes.
##
## `UnarmedActivate` was selected by measuring the donor library rather than by
## its name: it is a 1.0333 s, in-place, standing, single-arm reach.  The nearby
## `UnarmedPickup` drops the head by more than a metre and reads as picking an
## object up, not scattering food.

const Wanderer := preload("res://src/entities/player/wanderer_animations.gd")

const SOURCE_MODEL := "res://assets/rigs/rpg_character/Unarmed.glb"
const SOURCE_TAKE := &"UnarmedActivate"
const SOURCE_NEUTRAL := &"UnarmedIdle"
const OUT_PATH := "res://data/animation/wanderer_feed.tres"
const FPS := 30.0

## Wanderer bone -> donor bone.  The torso is paired by anatomical height, as in
## retarget_hunch.gd; clavicles and arms have direct anatomical counterparts.
##
## Hips is intentionally absent.  So are both leg chains.  Their local transform
## is copied from the wanderer's rest at every key, which keeps the action rooted
## and its feet in the same neutral stand throughout the one-shot.
const BONE_MAP := {
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

const NEUTRAL_BONES := [
	"Hips",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
	"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]

var _done := false
var _out := OUT_PATH
var _source_root: Node3D = null
var _target_root: Node3D = null
var _source: Skeleton3D = null
var _target: Skeleton3D = null
var _source_player: AnimationPlayer = null
var _target_player: AnimationPlayer = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]


## AnimationPlayer needs one tree tick after the imported scenes are attached.
## Running the bake in _initialize() would produce a valid-looking, motionless
## resource because neither player's skeleton has entered the tree yet.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := _load_models()
	if ok:
		ok = _bake()
	_cleanup()
	quit(0 if ok else 1)
	return true


func _load_models() -> bool:
	for path in [SOURCE_MODEL, Wanderer.MODEL_PATH]:
		if not ResourceLoader.exists(path):
			print("retarget_feed: %s is not in the project or has not been imported" % path)
			return false
	var source_resource := ResourceLoader.load(SOURCE_MODEL)
	var target_resource := ResourceLoader.load(Wanderer.MODEL_PATH)
	if not (source_resource is PackedScene) or not (target_resource is PackedScene):
		print("retarget_feed: source or target did not load as a PackedScene")
		return false
	_source_root = (source_resource as PackedScene).instantiate() as Node3D
	_target_root = (target_resource as PackedScene).instantiate() as Node3D
	if _source_root == null or _target_root == null:
		print("retarget_feed: source or target could not be instantiated as Node3D")
		return false
	root.add_child(_source_root)
	root.add_child(_target_root)
	_source = _first(_source_root, "Skeleton3D") as Skeleton3D
	_target = _first(_target_root, "Skeleton3D") as Skeleton3D
	_source_player = _first(_source_root, "AnimationPlayer") as AnimationPlayer
	_target_player = _first(_target_root, "AnimationPlayer") as AnimationPlayer
	if _source == null or _target == null or _source_player == null or _target_player == null:
		print("retarget_feed: source or target has no Skeleton3D or AnimationPlayer")
		return false
	if not _source_player.has_animation(SOURCE_TAKE):
		print("retarget_feed: %s holds no take called %s" % [SOURCE_MODEL, SOURCE_TAKE])
		return false
	if not _source_player.has_animation(SOURCE_NEUTRAL):
		print("retarget_feed: %s holds no neutral take called %s" % [SOURCE_MODEL, SOURCE_NEUTRAL])
		return false
	if _target.get_bone_count() != 24:
		print("retarget_feed: the target rig has %d bones, expected 24" % _target.get_bone_count())
		return false
	for target_name in BONE_MAP:
		if _target.find_bone(target_name) < 0 or _source.find_bone(BONE_MAP[target_name]) < 0:
			print("retarget_feed: missing mapped pair %s <- %s" % [target_name, BONE_MAP[target_name]])
			return false
	for bone in NEUTRAL_BONES:
		if _target.find_bone(bone) < 0:
			print("retarget_feed: the target rig has no neutral bone called %s" % bone)
			return false
	_source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_target_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return true


func _cleanup() -> void:
	if _source_root != null and is_instance_valid(_source_root):
		_source_root.free()
	if _target_root != null and is_instance_valid(_target_root):
		_target_root.free()


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


## Anatomical basis derived from each rest: x left, y up, z forward.  Deriving
## the half-turn between the packs is safer than assuming either import's axes.
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


func _pose_source(take: StringName, at: float) -> void:
	_source_player.play(take)
	_source_player.seek(at, true)
	_source_player.advance(0.0)


## Average the donor's whole neutral stand.  Its rest is a rigging pose: copying
## a rest-to-action delta carries more than 200 degrees of forearm setup into the
## wanderer.  The averaged authored idle removes that bias and its breathing.
func _neutral_reference() -> Dictionary:
	var animation := _source_player.get_animation(SOURCE_NEUTRAL)
	var count: int = maxi(int(round(animation.length * FPS)), 2)
	var sums := {}
	for step in range(count):
		_pose_source(SOURCE_NEUTRAL, animation.length * float(step) / float(count))
		for index in range(_source.get_bone_count()):
			var q := _source.get_bone_global_pose(index).basis.orthonormalized().get_rotation_quaternion()
			if step == 0:
				sums[index] = q
				continue
			var running: Quaternion = sums[index]
			if running.dot(q) < 0.0:
				q = -q
			sums[index] = Quaternion(
				running.x + q.x, running.y + q.y,
				running.z + q.z, running.w + q.w
			)
	var reference := {}
	for index in range(_source.get_bone_count()):
		reference[index] = Basis((sums[index] as Quaternion).normalized())
	return reference


## One sampled instant as target-local transforms.  Every target bone receives a
## transform, even when unmapped, so all 24 position and rotation tracks have the
## same shape as the wanderer's imported clips inside an AnimationTree.
func _retarget_at(at: float, reference: Dictionary, conjugate: Basis) -> Dictionary:
	_pose_source(SOURCE_TAKE, at)
	var globals: Array[Basis] = []
	globals.resize(_target.get_bone_count())
	var locals := {}
	for index in range(_target.get_bone_count()):
		var target_name := _target.get_bone_name(index)
		var parent := _target.get_bone_parent(index)
		var parent_basis := Basis.IDENTITY if parent < 0 else globals[parent]
		var local := _target.get_bone_rest(index)
		var source_name := String(BONE_MAP.get(target_name, ""))
		if source_name != "":
			var source_index := _source.find_bone(source_name)
			var delta := (_source.get_bone_global_pose(source_index).basis.orthonormalized()
				* (reference[source_index] as Basis).inverse()).orthonormalized()
			var carried := (conjugate * delta * conjugate.inverse()).orthonormalized()
			var wanted_global := (carried
				* _target.get_bone_global_rest(index).basis).orthonormalized()
			local.basis = (parent_basis.inverse() * wanted_global).orthonormalized()
		globals[index] = (parent_basis * local.basis).orthonormalized()
		locals[index] = local
	return locals


func _bake() -> bool:
	var source_animation := _source_player.get_animation(SOURCE_TAKE)
	var intervals: int = maxi(int(round(source_animation.length * FPS)), 1)
	var source_frame := _source_frame()
	var target_frame := _target_frame()
	var conjugate := (target_frame * source_frame.inverse()).orthonormalized()
	var reference := _neutral_reference()

	var animation := Animation.new()
	animation.length = source_animation.length
	animation.loop_mode = Animation.LOOP_NONE
	animation.step = 1.0 / FPS
	var rotation_tracks := {}
	var position_tracks := {}
	for index in range(_target.get_bone_count()):
		var path := NodePath("%s:%s" % [
			Wanderer.SKELETON_PATH, _target.get_bone_name(index),
		])
		var position := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position, path)
		animation.track_set_interpolation_type(position, Animation.INTERPOLATION_LINEAR)
		position_tracks[index] = position
		var rotation := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation, path)
		animation.track_set_interpolation_type(rotation, Animation.INTERPOLATION_LINEAR)
		rotation_tracks[index] = rotation

	# A one-shot keeps its authored final sample.  Unlike a loop, it must include
	# both endpoints or the last 1/30 s freezes on the penultimate donor frame.
	for frame in range(intervals + 1):
		var at := source_animation.length * float(frame) / float(intervals)
		var locals := _retarget_at(at, reference, conjugate)
		for index in range(_target.get_bone_count()):
			var local: Transform3D = locals[index]
			animation.position_track_insert_key(position_tracks[index], at, local.origin)
			animation.rotation_track_insert_key(
				rotation_tracks[index], at, local.basis.get_rotation_quaternion()
			)

	if not _verify_shape(animation) or not _verify_gesture(animation):
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	var error := ResourceSaver.save(animation, _out)
	if error != OK:
		print("retarget_feed: FAILED to write %s (%d)" % [_out, error])
		return false
	print("retarget_feed: wrote %s -- %.4f s, %d samples, %d tracks, non-loop" % [
		_out, animation.length, intervals + 1, animation.get_track_count(),
	])
	return true


## Measure the baked target, not the donor claim.  A mathematically valid
## cross-rig transfer can still lose the silhouette when the limb proportions
## differ; the action is useful only if the wanderer's own hand reaches forward.
func _verify_gesture(animation: Animation) -> bool:
	var library := AnimationLibrary.new()
	library.add_animation(&"feed", animation)
	_target_player.add_animation_library(&"feed_probe", library)
	_target_player.play(&"feed_probe/feed")
	var hips := _target.find_bone("Hips")
	var hand := _target.find_bone("LeftHand")
	var frame := _target_frame()
	var metres_per_unit := _target.global_transform.basis.get_scale().y
	var forward_min := INF
	var forward_max := -INF
	var up_min := INF
	var up_max := -INF
	var root_start := Vector3.ZERO
	var root_travel := 0.0
	for sample in range(32):
		var at := animation.length * float(sample) / 31.0
		_target_player.seek(at, true)
		_target_player.advance(0.0)
		var root_now := _target.get_bone_global_pose(hips).origin
		if sample == 0:
			root_start = root_now
		root_travel = maxf(root_travel, root_now.distance_to(root_start) * metres_per_unit)
		var offset := _target.get_bone_global_pose(hand).origin - root_now
		var forward := offset.dot(frame.z) * metres_per_unit
		var up := offset.dot(frame.y) * metres_per_unit
		forward_min = minf(forward_min, forward)
		forward_max = maxf(forward_max, forward)
		up_min = minf(up_min, up)
		up_max = maxf(up_max, up)
	_target_player.remove_animation_library(&"feed_probe")
	print("retarget_feed: baked left hand %.3f..%.3f m forward, %.3f..%.3f m above hips; root travel %.6f m"
		% [forward_min, forward_max, up_min, up_max, root_travel])
	if forward_max - forward_min < 0.20:
		print("retarget_feed: the baked hand has no readable forward scattering gesture")
		return false
	if root_travel > 0.001:
		print("retarget_feed: the baked root did not remain neutral")
		return false
	return true


## Refuse to write a bake that violates the requirements this tool exists to
## establish.  The shipping test independently checks the saved resource.
func _verify_shape(animation: Animation) -> bool:
	if animation.loop_mode != Animation.LOOP_NONE:
		print("retarget_feed: generated action unexpectedly loops")
		return false
	if animation.get_track_count() != _target.get_bone_count() * 2:
		print("retarget_feed: generated %d tracks, expected %d" % [
			animation.get_track_count(), _target.get_bone_count() * 2,
		])
		return false
	for bone in NEUTRAL_BONES:
		var bone_index := _target.find_bone(bone)
		var rest := _target.get_bone_rest(bone_index)
		for track in range(animation.get_track_count()):
			if not String(animation.track_get_path(track)).ends_with(":" + bone):
				continue
			for key in range(animation.track_get_key_count(track)):
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
					var position: Vector3 = animation.track_get_key_value(track, key)
					if not position.is_equal_approx(rest.origin):
						print("retarget_feed: %s translation left neutral at key %d" % [bone, key])
						return false
				elif animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					var rotation: Quaternion = animation.track_get_key_value(track, key)
					var rest_rotation := rest.basis.orthonormalized().get_rotation_quaternion()
					var separation := rad_to_deg(rotation.angle_to(rest_rotation))
					# Animation stores a normalized Quaternion rather than the rest
					# Basis.  Their printed components agree, while angle_to() can
					# retain about four hundredths of a degree of float noise.
					if separation > 0.1:
						print("retarget_feed: %s rotation left neutral at key %d (%.4f deg; %s vs %s)"
							% [bone, key, separation, rotation, rest_rotation])
						return false
	return true
