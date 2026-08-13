extends SceneTree

## Plays every take of a character file and reports what the BODY actually does.
##
##   Godot_console.exe --headless --path <project> \
##       --script res://tools/measure_wanderer_takes.gd -- <res://model> [...]
##
## With no arguments it measures the shipping wanderer, which is the baseline
## every new delivery is read against.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS: A FILENAME IS A CLAIM, NOT EVIDENCE
## ---------------------------------------------------------------------------
## This project has been wrong about an animation three times by reading its
## name. `Limping_Walk_inplace` does not limp -- its two feet lift 7.85 and 9.01
## units, a ratio of 0.871 and a left-against-mirrored-right correlation of
## 0.933, which is an ordinary symmetric walk. `Injured_Walk` is the one with a
## dragged leg. And the crow's pack shipped animation files carrying 121 nulls
## and no armature at all: they imported with zero errors, named their takes,
## and had no pose to give -- which is worse than a missing clip, because the
## inventory then claims we have it.
##
## So the numbers this tool prints are the ones a name cannot fake:
##
##   MOVES / STILL   -- did any bone leave the bind pose at all
##   length          -- against the delivery's own claim (briefing trap 15.2:
##                      `animation/trimming` is PER PACK, and with it wrong a
##                      take arrives carrying the preceding timeline as dead
##                      air -- measured once at 8.958 s against a true 3.958 s)
##   root travel     -- in place, or root motion the movement code must consume
##   hips / head     -- in METRES OF WORLD, so "he goes down" is a number
##   lean            -- degrees of torso pitch, comparable across takes
##
## Every height here is world-space: the bone's global pose put through the
## skeleton's own global transform. That matters because these files do NOT
## agree about units -- the shipping `.glb` carries the rig at centimetre scale
## with a 0.01 on the root, and the same rig out of an animation-only `.fbx`
## arrives in metres and still Z-up. Reading `get_bone_global_pose().origin`
## raw would report the same character at 85.07 on one path and 0.84 on the
## other, and briefing trap 15.3 is the same hazard through `Mesh.get_aabb()`,
## which reports these characters at roughly 1/100 life size.
##
## It runs from `_process` rather than `_initialize` for briefing trap 1: a node
## added during `_initialize` has not had `_ready()` yet, and an AnimationPlayer
## that has not been readied plays nothing while reporting that it is playing.

const DEFAULT_MODELS := ["res://assets/models/characters/winter_wanderer.glb"]

## Where in each take to sample for the MOVES/STILL verdict.
##
## Not at quarters, for the reason `tools/measure_dog_takes.gd` records: a take
## holding a whole number of breath cycles sampled at 0, 1/4, 1/2, 3/4, 1 lands
## on five successive zero crossings of the same sine and reports a moving take
## as still.
const SAMPLE_AT := [0.0, 0.13, 0.37, 0.61, 0.83, 0.97]

## How many points to walk a take through when tracing heights and lean.
const TRACE_STEPS := 61

## What counts as movement. 0.001 rad is about a twentieth of a degree. The
## position epsilon is in SKELETON units and these files disagree about units,
## so it is deliberately loose -- the rotation term is what actually decides.
const ROTATION_EPSILON := 0.001
const POSITION_EPSILON := 0.05

## Bones the trace reads, tried in order until one is found. Meshy's wanderer
## calls them `Hips` and `Head`; other rigs in this repository do not.
const HIP_BONES := ["Hips", "hips", "Pelvis", "B_Pelvis", "Root"]
const HEAD_BONES := ["Head", "head", "B_Head", "head_end"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var models: Array = Array(OS.get_cmdline_user_args())
	if models.is_empty():
		models = DEFAULT_MODELS
	var imported := 0
	var moving := 0
	for path in models:
		var result := _measure(String(path))
		imported += int(result["imported"])
		moving += int(result["moving"])
	print("")
	print("TOTAL takes imported : %d" % imported)
	print("TOTAL takes that move: %d" % moving)
	print("STILL                : %d" % (imported - moving))
	quit(0 if imported == moving and imported > 0 else 1)
	return true


func _measure(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		print("%s does not exist or was never imported" % path)
		return {"imported": 0, "moving": 0}
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

	var hip := _find_bone(skeleton, HIP_BONES)
	var head := _find_bone(skeleton, HEAD_BONES)
	print("")
	print("=== %s" % path)
	print("  %d bones, skeleton world scale %s, hip bone %s, head bone %s" % [
		skeleton.get_bone_count(),
		skeleton.global_transform.basis.get_scale(),
		"none" if hip < 0 else skeleton.get_bone_name(hip),
		"none" if head < 0 else skeleton.get_bone_name(head)])
	if hip >= 0:
		# The rest pose in world metres. This is the number that settles which
		# space a file arrived in, and it is the one that differs by 100x
		# between the .glb and the animation-only .fbx of the SAME rig.
		var rest := skeleton.global_transform * skeleton.get_bone_global_rest(hip).origin
		print("  hip rest, world: %s" % rest)
	# The rig's own size, in world metres, at rest. Two deliveries of "the same"
	# character can arrive at different sizes, and the only track that carries a
	# LENGTH -- the hips' translation -- is wrong by exactly that ratio when a
	# take is moved between them. Everything else is a rotation and does not care.
	var low := INF
	var high := -INF
	for index in range(skeleton.get_bone_count()):
		var y: float = (skeleton.global_transform * skeleton.get_bone_global_rest(index).origin).y
		low = minf(low, y)
		high = maxf(high, y)
	print("  rig height at rest, world: %.4f m  (%.4f to %.4f)" % [high - low, low, high])
	_compare_rig(path, skeleton)

	var takes := player.get_animation_list()
	var moving := 0
	print("  %d takes" % takes.size())
	for take in takes:
		var animation := player.get_animation(take)
		var trimmed := String(take).strip_edges()
		# Briefing trap 15.1: a trailing space in a take name silently drops it.
		# Printed inside quotes so the space is visible, and flagged so the
		# asset gets corrected rather than the code carrying a workaround.
		var flag := ""
		if trimmed != String(take):
			flag = "  <-- NAME NEEDS TRIMMING"

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
		print("  \"%s\"%s" % [take, flag])
		print("     %-5s  %7.4f s  %3d tracks  worst %s  rot %7.4f rad  pos %8.4f units" % [
			"MOVES" if moves else "STILL", animation.length, animation.get_track_count(),
			worst_bone, worst_rotation, worst_position])
		if moves and hip >= 0:
			_trace(player, skeleton, take, animation, hip, head)
	player.stop()
	rig.queue_free()
	return {"imported": takes.size(), "moving": moving}


## What the body does over the take, in metres of world.
##
## The lean is the torso axis -- hip to head -- measured against straight up, so
## it is one number that is comparable between two rigs with different spine
## chains. `.superpowers/sdd/wave3/task-w3-hunger-hunch-report.md` section 2 is
## why: a retarget delivered every joint angle correct to a tenth of a degree
## and the wrong posture, because the two rigs put their spine bones at
## different heights and the same angle on a different lever arm moves the end
## of the body differently. Verify the end effect, not the angles.
func _trace(player: AnimationPlayer, skeleton: Skeleton3D, take: StringName,
		animation: Animation, hip: int, head: int) -> void:
	var hip_first := Vector3.ZERO
	var hip_last := Vector3.ZERO
	var hip_low := INF
	var hip_high := -INF
	var head_first := 0.0
	var head_last := 0.0
	var head_low := INF
	var lean_low := INF
	var lean_high := -INF
	var travel := 0.0
	var previous := Vector3.ZERO
	var peak_drop_rate := 0.0
	var peak_ground_speed := 0.0
	var contact_at := 0.0
	var settle := 0.0
	var step_seconds := animation.length / float(TRACE_STEPS - 1)
	for step in range(TRACE_STEPS):
		var fraction := float(step) / float(TRACE_STEPS - 1)
		player.play(take)
		player.seek(animation.length * fraction, true)
		var hip_world := skeleton.global_transform * skeleton.get_bone_global_pose(hip).origin
		if step == 0:
			hip_first = hip_world
		else:
			# The SHAPE of the motion, not its duration. Two takes with the same
			# start, end and length can feel completely different, and this
			# project has already shipped a regression that every duration test
			# passed -- see AGENT-BRIEFING, "钉住时长的测试，钉不住一个运动".
			# For a fall this is also the number an impact effect needs: how
			# fast the body was going when it arrived.
			peak_drop_rate = maxf(peak_drop_rate, (previous.y - hip_world.y) / step_seconds)
			peak_ground_speed = maxf(peak_ground_speed, Vector2(
				hip_world.x - previous.x, hip_world.z - previous.z).length() / step_seconds)
			if hip_world.y < hip_low:
				contact_at = animation.length * fraction
			if fraction > 0.8:
				settle = maxf(settle, (previous - hip_world).length() / step_seconds)
		previous = hip_world
		hip_last = hip_world
		hip_low = minf(hip_low, hip_world.y)
		hip_high = maxf(hip_high, hip_world.y)
		if head >= 0:
			var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
			if step == 0:
				head_first = head_world.y
			head_last = head_world.y
			head_low = minf(head_low, head_world.y)
			var axis := head_world - hip_world
			if axis.length() > 0.0001:
				var lean := rad_to_deg(acos(clampf(axis.normalized().dot(Vector3.UP), -1.0, 1.0)))
				lean_low = minf(lean_low, lean)
				lean_high = maxf(lean_high, lean)
		travel = maxf(travel, Vector2(hip_world.x - hip_first.x, hip_world.z - hip_first.z).length())
	var net := Vector2(hip_last.x - hip_first.x, hip_last.z - hip_first.z).length()
	# In place or root motion. Every take in the shipping library is in place --
	# root travel under half a centimetre -- so a take that travels needs the
	# movement code to consume it or the character will slide.
	var kind := "IN PLACE" if travel < 0.05 else "ROOT MOTION"
	print("     %s  hip travel max %.3f m, net %.3f m" % [kind, travel, net])
	print("     hip  y %.3f -> %.3f m  (low %.3f, high %.3f, drop %.3f m)" % [
		hip_first.y, hip_last.y, hip_low, hip_high, hip_first.y - hip_low])
	if head >= 0:
		print("     head y %.3f -> %.3f m  (low %.3f, drop %.3f m)" % [
			head_first, head_last, head_low, head_first - head_low])
		print("     lean %.1f to %.1f deg" % [lean_low, lean_high])
	print("     peak drop %.3f m/s, peak ground speed %.3f m/s, lowest hip at %.3f s, last-fifth motion %.3f m/s" % [
		peak_drop_rate, peak_ground_speed, contact_at, settle])
	# A take that puts the body on the ground gets its hip height printed as a
	# timeline, because for these the question is never "how long" -- it is
	# WHEN he lands and whether he then holds still. A death that arrives at the
	# ground on its last frame has nothing to hold, and a duration test cannot
	# tell that from one that settles for a second afterwards.
	if hip_first.y - hip_low > 0.3:
		var line := ""
		for step in range(0, TRACE_STEPS, 4):
			player.play(take)
			player.seek(animation.length * float(step) / float(TRACE_STEPS - 1), true)
			var y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(hip).origin).y
			line += "%.2f " % y
		print("     hip height every %.3f s: %s" % [step_seconds * 4.0, line])


## Is this the wanderer's own rig, name for name?
##
## The question a delivery cannot answer about itself, and the one that decides
## what every future export costs. Same rig means the take drops onto the
## shipping character with nothing to retarget; a different rig means a
## retarget, and `.superpowers/sdd/wave3/task-w3-hunger-hunch-report.md` is what
## one of those costs -- a bake that carried every joint angle to a tenth of a
## degree and delivered 10.5 degrees where 26.8 was authored.
##
## Names only. Two rigs can share every bone name and still differ in where the
## bones SIT, which is exactly the defect that report found, so a matching list
## is a necessary condition and not a sufficient one -- the bone heights are
## printed too, as fractions of the character's own height, because that is the
## quantity the retarget actually has to agree about.
func _compare_rig(path: String, skeleton: Skeleton3D) -> void:
	var names := PackedStringArray()
	for index in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(index))
	names.sort()
	if path == DEFAULT_MODELS[0]:
		print("  bones: %s" % ", ".join(names))
		return
	var reference := ResourceLoader.load(DEFAULT_MODELS[0])
	if not (reference is PackedScene):
		return
	var scene := (reference as PackedScene).instantiate()
	root.add_child(scene)
	var other: Skeleton3D = null
	for node in scene.find_children("*", "Skeleton3D", true, false):
		other = node as Skeleton3D
		break
	if other == null:
		scene.free()
		return
	var theirs := PackedStringArray()
	for index in range(other.get_bone_count()):
		theirs.append(other.get_bone_name(index))
	theirs.sort()
	var only_here: Array = []
	var only_there: Array = []
	for name in names:
		if not theirs.has(name):
			only_here.append(name)
	for name in theirs:
		if not names.has(name):
			only_there.append(name)
	if only_here.is_empty() and only_there.is_empty():
		print("  RIG: identical to the wanderer's -- %d bones, name for name" % names.size())
	else:
		print("  RIG: DIFFERENT from the wanderer's -- %d bones against %d" % [
			names.size(), theirs.size()])
		print("     only in this file : %s" % ", ".join(PackedStringArray(only_here)))
		print("     only in the model : %s" % ", ".join(PackedStringArray(only_there)))
	# Heights up the body, as a fraction of hip-to-crown, on both rigs. Same
	# names is not the same skeleton; this is the number that says so.
	print("  bone heights, this file against the wanderer (fraction of rig height):")
	var mine := _height_fractions(skeleton)
	var yours := _height_fractions(other)
	var worst := 0.0
	for name in names:
		if not yours.has(name):
			continue
		var delta: float = absf(float(mine[name]) - float(yours[name]))
		worst = maxf(worst, delta)
		if delta > 0.01:
			print("     %-16s %6.3f against %6.3f   delta %.3f" % [
				name, mine[name], yours[name], delta])
	print("     worst height delta across shared bones: %.4f" % worst)
	scene.queue_free()


## Each bone's rest height as a fraction of the rig's own vertical extent.
## Unitless, so it compares two rigs that arrived in different spaces.
##
## WORLD space, and that word is load-bearing. Read raw out of the skeleton,
## `get_bone_global_rest(i).origin.y` is the height only if the file arrived
## Y-up -- and an animation-only FBX of this very rig arrives **Z-up**, so `.y`
## is its depth axis. Measured: reading it raw reported this pack's `headfront`
## at 0.103 of the body height against the shipping model's 0.770 and called an
## identical rig a different one. The skeleton's own global transform carries
## Godot's Z-up correction, so putting the origin through it is what makes the
## two comparable.
func _height_fractions(skeleton: Skeleton3D) -> Dictionary:
	var world: Array = []
	var low := INF
	var high := -INF
	for index in range(skeleton.get_bone_count()):
		var origin: Vector3 = skeleton.global_transform * skeleton.get_bone_global_rest(index).origin
		world.append(origin)
		low = minf(low, origin.y)
		high = maxf(high, origin.y)
	var span := maxf(high - low, 0.000001)
	var fractions: Dictionary = {}
	for index in range(skeleton.get_bone_count()):
		fractions[skeleton.get_bone_name(index)] = ((world[index] as Vector3).y - low) / span
	return fractions


func _find_bone(skeleton: Skeleton3D, names: Array) -> int:
	for name in names:
		var index := skeleton.find_bone(String(name))
		if index >= 0:
			return index
	return -1


## Every bone's pose, as [rotation, position].
func _pose(skeleton: Skeleton3D) -> Array:
	var pose: Array = []
	for index in range(skeleton.get_bone_count()):
		pose.append([skeleton.get_bone_pose_rotation(index), skeleton.get_bone_pose_position(index)])
	return pose
