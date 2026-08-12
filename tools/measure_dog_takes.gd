extends SceneTree

## Plays every take of every dog and reports which ones MOVE.
##
##   Godot_console.exe --headless --path <project> \
##       --script res://tools/measure_dog_takes.gd
##
## ---------------------------------------------------------------------------
## WHY "IT IMPORTED" IS NOT "IT WORKS"
## ---------------------------------------------------------------------------
## `Docs/asset-inventory-low-poly-animals.md` section 1.5 measured 217 takes out
## of this package: **209 moved and 8 did not**, and the eight imported without a
## single error. Four of them were the junk `Take 001` that every `*_Rig.fbx` in
## the pack carries -- three tracks, no skeleton motion, a length of 56 seconds
## that means nothing. The crow's package was worse: its animation FBXs held 121
## nulls and no armature at all, imported clean, and had no pose to give.
##
## A take that arrives and leaves the mesh in its bind pose is worse than a
## missing one, because the take census counts it and the library names it. So
## the number this project quotes is not "takes imported"; it is
## **takes imported / takes that move**, and this is what measures the second
## number.
##
## It runs from `_process` rather than `_initialize` for briefing trap 1: a node
## added during `_initialize` has not had `_ready()` yet, and an AnimationPlayer
## that has not been readied plays nothing while reporting that it is playing.
##
## The gate that keeps this true on every run is `tests/art/test_dog_models.gd`,
## which asks the same question of the Animation resources without a tree. This
## tool is the instrument the wave report quotes, and the one to reach for when
## a re-delivery arrives.

const MODELS := [
	"res://assets/models/characters/dogs/chihuahua.glb",
	"res://assets/models/characters/dogs/golden_retriever.glb",
	"res://assets/models/characters/dogs/great_dane.glb",
]

## Where in each take to sample.
##
## Six points, and NOT at quarters. This cost a wrong reading: `lie` holds two
## breath cycles, so sampling at 0, ¼, ½, ¾ and 1 lands on five successive ZERO
## CROSSINGS of the same sine and the take reported 0.15 degrees of motion --
## interpolation noise -- on an animation whose ribs swing 2.4 degrees. An
## instrument whose sample points are commensurate with the thing it measures
## reports the aliased value with no sign that anything is wrong, and the answer
## it gives is "this take is nearly still", which is precisely the verdict this
## tool exists to be trusted about.
##
## These fractions share no small common factor with 1, 2, 3 or 4 cycles per
## take, which is the whole range an authored loop is likely to hold.
const SAMPLE_AT := [0.0, 0.13, 0.37, 0.61, 0.83, 0.97]

## What counts as movement. A quaternion delta of 0.001 rad is about a twentieth
## of a degree; the position epsilon is in SKELETON units, and this pack is
## authored a hundred times life size, so 0.05 units is half a millimetre of dog.
## Both are far below anything anyone could see and far above float noise.
const ROTATION_EPSILON := 0.001
const POSITION_EPSILON := 0.05

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var imported := 0
	var moving := 0
	for path in MODELS:
		var result := _measure(path)
		imported += int(result["imported"])
		moving += int(result["moving"])
	print("")
	print("TOTAL takes imported : %d" % imported)
	print("TOTAL takes that move: %d" % moving)
	print("STILL                : %d" % (imported - moving))
	quit(0 if imported == moving else 1)
	return true


func _measure(path: String) -> Dictionary:
	var packed := ResourceLoader.load(path)
	if not (packed is PackedScene):
		print("%s did not load as a PackedScene" % path)
		return {"imported": 0, "moving": 0}
	var rig := (packed as PackedScene).instantiate()
	root.add_child(rig)

	var player: AnimationPlayer = null
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		break
	var skeleton: Skeleton3D = null
	for node in rig.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if player == null or skeleton == null:
		print("%s has no AnimationPlayer or no Skeleton3D" % path)
		rig.queue_free()
		return {"imported": 0, "moving": 0}

	var takes := player.get_animation_list()
	var moving := 0
	print("%s  %d bones, %d takes" % [path.get_file(), skeleton.get_bone_count(), takes.size()])
	for take in takes:
		var animation := player.get_animation(take)
		var first: Array = []
		var worst_rotation := 0.0
		var worst_position := 0.0
		var worst_bone := ""
		for fraction in SAMPLE_AT:
			player.play(take)
			player.seek(animation.length * fraction, true)
			var pose := _pose(skeleton)
			if first.is_empty():
				first = pose
				continue
			for index in range(skeleton.get_bone_count()):
				var rotation: float = (pose[index][0] as Quaternion).angle_to(first[index][0] as Quaternion)
				var position: float = ((pose[index][1] as Vector3) - (first[index][1] as Vector3)).length()
				if rotation > worst_rotation or position > worst_position:
					worst_bone = skeleton.get_bone_name(index)
				worst_rotation = maxf(worst_rotation, rotation)
				worst_position = maxf(worst_position, position)
		var moves := worst_rotation > ROTATION_EPSILON or worst_position > POSITION_EPSILON
		if moves:
			moving += 1
		# Position is in the skeleton's own units, which on this pack are
		# centimetres -- the rigs are authored a hundred times life size and the
		# Skeleton3D node carries the 0.01. Printed unconverted rather than
		# divided by a constant nobody can check.
		print("  %-8s %-5s %6.3f s  %3d tracks  worst bone %-14s rot %8.5f rad  pos %8.4f units" % [
			take, "MOVES" if moves else "STILL", animation.length, animation.get_track_count(),
			worst_bone, worst_rotation, worst_position])
	player.stop()
	rig.queue_free()
	return {"imported": takes.size(), "moving": moving}


## Every bone's pose, as [rotation, position].
func _pose(skeleton: Skeleton3D) -> Array:
	var pose: Array = []
	for index in range(skeleton.get_bone_count()):
		pose.append([skeleton.get_bone_pose_rotation(index), skeleton.get_bone_pose_position(index)])
	return pose
