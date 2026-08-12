extends TestCase

## The dove's thirteen takes: that they are all there, all named, all the length
## the pack authored them at, and -- the one that matters -- that every one of
## them actually MOVES the skeleton.
##
## ---------------------------------------------------------------------------
## WHY "IT IMPORTED" IS NOT "IT WORKS"
## ---------------------------------------------------------------------------
## `Docs/asset-inventory-low-poly-animals.md` section 1.5 played all 217 takes in
## that package and found EIGHT that import cleanly, appear in the list, and
## leave the mesh in its bind pose. Four of them are the junk `Take 001` that
## every `*_Rig.fbx` in the pack carries -- three tracks, no motion, and a length
## the exporter invented (the wolf rig's claims 56.667 s).
##
## A still take is worse than a missing one, and that is the whole reason this
## file exists. The owner cannot author bird animation, so the take list IS the
## feature list: a missing take is a feature nobody can ever build, and a take
## that is present and dead is a feature the inventory will claim we have.
##
## So every take is played and sampled, and the assertion is on the pose rather
## than on the take list.

const PigeonAnimationsScript := preload("res://src/entities/wildlife/pigeon_animations.gd")

## How much a bone has to change for a take to count as moving. The same
## thresholds the inventory's own census used, so a take this file calls dead is
## dead by the same standard that cleared the other 209.
const MOVED_RADIANS := 0.001
const MOVED_METRES := 0.0005

## Where in each take to look. Five samples rather than the two the brief asks
## for, because a take whose first and last frames happen to match -- which is
## exactly what a LOOPING cycle is -- would read as still on two.
const SAMPLES: Array = [0.0, 0.25, 0.5, 0.75, 0.98]


func _library() -> AnimationLibrary:
	return PigeonAnimationsScript.build()


## The imported model, in the tree, with its own AnimationPlayer and skeleton.
##
## In the tree because `AnimationPlayer.seek()` writes through node paths, and a
## player outside one resolves none of them and silently poses nothing -- which
## would make every take in this file read as still. Returns null rather than
## half a rig, so the caller has one thing to check and one thing to free.
func _rig():
	if not ResourceLoader.exists(PigeonAnimationsScript.MODEL_PATH):
		return null
	var packed := ResourceLoader.load(PigeonAnimationsScript.MODEL_PATH) as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate() as Node3D
	if scene == null:
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		scene.free()
		return null
	tree.get_root().add_child(scene)
	var player: AnimationPlayer = null
	var skeleton: Skeleton3D = null
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		break
	for node in scene.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if player == null or skeleton == null:
		_drop(scene)
		return null
	if player.has_animation_library(PigeonAnimationsScript.LIBRARY):
		player.remove_animation_library(PigeonAnimationsScript.LIBRARY)
	player.add_animation_library(PigeonAnimationsScript.LIBRARY, _library())
	return {"scene": scene, "player": player, "skeleton": skeleton}


## Off the tree first, then freed. A node freed while still parented can be
## found by anything that runs in between; and a node left behind is a leaked
## ObjectDB instance, which fails the run (briefing section 2.2).
func _drop(scene: Node) -> void:
	if scene.get_parent() != null:
		scene.get_parent().remove_child(scene)
	scene.free()


## The largest change any bone shows across a take, as {rotation, position}.
func _travel(player: AnimationPlayer, skeleton: Skeleton3D, take: String) -> Dictionary:
	var poses: Array = []
	var animation := player.get_animation(take)
	if animation == null:
		return {"rotation": 0.0, "position": 0.0}
	for fraction in SAMPLES:
		player.play(take)
		player.seek(animation.length * float(fraction), true)
		var pose: Array = []
		for bone in range(skeleton.get_bone_count()):
			pose.append([skeleton.get_bone_pose_rotation(bone), skeleton.get_bone_pose_position(bone)])
		poses.append(pose)
	var turned := 0.0
	var moved := 0.0
	for index in range(1, poses.size()):
		for bone in range(skeleton.get_bone_count()):
			var first: Array = poses[0][bone]
			var later: Array = poses[index][bone]
			turned = maxf(turned, (first[0] as Quaternion).angle_to(later[0] as Quaternion))
			moved = maxf(moved, (first[1] as Vector3).distance_to(later[1] as Vector3))
	return {"rotation": turned, "position": moved}


# --- the library --------------------------------------------------------------


func test_the_library_holds_every_take_the_table_names() -> void:
	var library := _library()
	var missing := PackedStringArray()
	for row in PigeonAnimationsScript.TAKES:
		if not library.has_animation(StringName(row[1])):
			missing.append("%s (the pack's `%s`)" % [row[1], row[0]])
	assert_eq(missing.size(), 0, "; ".join(missing))


## Thirteen, and not fourteen. The pack's rig file carries a junk `Take 001` that
## every `*_Rig.fbx` in this package has, and the whole reason only the animation
## file was taken is that a phantom take inflates any census of what we own.
func test_nothing_beyond_the_thirteen_arrived() -> void:
	var library := _library()
	assert_eq(
		library.get_animation_list().size(), PigeonAnimationsScript.TAKES.size(),
		"the library holds %d takes against the %d in the table: %s" % [
			library.get_animation_list().size(), PigeonAnimationsScript.TAKES.size(),
			", ".join(Array(library.get_animation_list()))]
	)


## The lengths, against the frame ranges in the inventory.
##
## This is what catches an `animation/trimming` that has come back on. Godot
## trims leading and trailing stillness by default, and the crow's perch file
## imported 100 frames long instead of 183 that way -- silently, and every number
## that depended on it slid.
func test_every_take_is_the_length_the_pack_authored_it_at() -> void:
	var library := _library()
	var offenders := PackedStringArray()
	for row in PigeonAnimationsScript.TAKES:
		var take := library.get_animation(StringName(row[1]))
		if take == null:
			offenders.append("%s is missing" % row[1])
			continue
		if absf(take.length - float(row[3])) > 0.01:
			offenders.append("%s imports at %.3f s, the pack authored %.3f s" % [
				row[1], take.length, float(row[3])])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Every take arrives LOOP_NONE, including the idles and the flight cycle. A
## perched bird whose idle does not loop plays four seconds and then stands
## frozen for as long as it sits there.
func test_the_takes_that_should_cycle_do_and_the_ones_that_should_not_do_not() -> void:
	var library := _library()
	var offenders := PackedStringArray()
	for row in PigeonAnimationsScript.TAKES:
		var take := library.get_animation(StringName(row[1]))
		if take == null:
			continue
		var loops: bool = take.loop_mode != Animation.LOOP_NONE
		if loops != bool(row[2]):
			offenders.append("%s loops=%s, the table says %s" % [row[1], loops, row[2]])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The library must not have edited the imported asset to set those loop flags.
##
## `ResourceLoader` hands every caller the SAME Animation (briefing trap 6), so
## writing `loop_mode` onto it rather than onto a duplicate would change the file
## for everything that loads it -- including the next call to `build()`, which
## would then be asserting against its own previous run.
func test_building_the_library_does_not_edit_the_imported_takes() -> void:
	var _first := _library()
	var source := PigeonAnimationsScript.source_takes()
	var edited := PackedStringArray()
	for row in PigeonAnimationsScript.TAKES:
		if not bool(row[2]):
			continue
		var raw: Animation = source.get(row[0], null)
		if raw != null and raw.loop_mode != Animation.LOOP_NONE:
			edited.append("%s" % row[0])
	assert_eq(edited.size(), 0, "the imported take(s) %s were changed in place" % ", ".join(edited))


## The names the game asks for are the names the library answers to. A rename in
## one place and not the other is a bird that stands still because `_play()`
## fell through its `has_animation` guard, which is silent by design.
func test_every_name_the_pigeon_plays_is_in_the_library() -> void:
	var library := _library()
	var missing := PackedStringArray()
	for asked in Pigeon.TRANSLATION.values():
		if not library.has_animation(asked as StringName):
			missing.append(String(asked))
	assert_true(Pigeon.TRANSLATION.size() >= 7, "the translation table lost rows")
	assert_eq(missing.size(), 0, "the pigeon plays %s, which the library does not hold" % ", ".join(missing))


## Every one of the crow's seven take names is translated. A name that fell
## through would be played verbatim out of the pigeon library, find nothing, and
## leave the bird in whatever pose it was already in.
func test_every_take_the_crow_state_machine_plays_is_translated() -> void:
	var untranslated := PackedStringArray()
	for name in [
		CrowAnimations.PERCH, CrowAnimations.LOOK, CrowAnimations.FLAP,
		CrowAnimations.TAKE_OFF, CrowAnimations.FLY, CrowAnimations.GLIDE,
		CrowAnimations.LAND,
	]:
		if not Pigeon.TRANSLATION.has(name):
			untranslated.append(String(name))
	assert_eq(untranslated.size(), 0, "%s has no pigeon take" % ", ".join(untranslated))


func test_a_name_the_table_does_not_carry_reports_no_length() -> void:
	assert_true(PigeonAnimationsScript.length_of(&"soaring") < 0.0, "an unknown take must not report a length")
	assert_almost_eq(PigeonAnimationsScript.length_of(PigeonAnimations.FLY), 0.583, 0.001, "the flight cycle")


# --- and the one that matters -------------------------------------------------


## EVERY TAKE, PLAYED. See this file's header.
func test_every_take_moves_the_bird() -> void:
	var rig = _rig()
	assert_not_null(rig, "the pigeon model did not instantiate with a player and a skeleton")
	if rig == null:
		return
	var player: AnimationPlayer = rig["player"]
	var skeleton: Skeleton3D = rig["skeleton"]
	var still := PackedStringArray()
	var played := 0
	for row in PigeonAnimationsScript.TAKES:
		var take := "%s/%s" % [PigeonAnimationsScript.LIBRARY, row[1]]
		if not player.has_animation(take):
			still.append("%s is not in the library at all" % row[1])
			continue
		played += 1
		var travel := _travel(player, skeleton, take)
		if float(travel["rotation"]) <= MOVED_RADIANS and float(travel["position"]) <= MOVED_METRES:
			still.append("%s never leaves the bind pose (best bone: %.5f rad, %.5f m)" % [
				row[1], travel["rotation"], travel["position"]])
	_drop(rig["scene"])
	assert_eq(played, PigeonAnimationsScript.TAKES.size(), "only %d of %d takes were playable" % [
		played, PigeonAnimationsScript.TAKES.size()])
	assert_eq(still.size(), 0, "; ".join(still))


## The measurement must be able to say NO. Every take above passes, so without
## this the whole instrument could be stuck returning "moved" and nothing here
## would notice -- which is the shape of the false PASS this project has
## catalogued seven times.
func test_the_motion_test_reports_a_still_take_as_still() -> void:
	var rig = _rig()
	assert_not_null(rig, "the pigeon model did not instantiate")
	if rig == null:
		return
	var player: AnimationPlayer = rig["player"]
	var skeleton: Skeleton3D = rig["skeleton"]
	# A take of the right length whose every track holds one key: it plays, it
	# appears in the list, and it has no pose to give -- exactly the shape of the
	# four junk `Take 001` stacks the inventory found.
	var held := (player.get_animation("%s/%s" % [
		PigeonAnimationsScript.LIBRARY, PigeonAnimations.FLY]) as Animation).duplicate(true)
	for track in range(held.get_track_count()):
		while held.track_get_key_count(track) > 1:
			held.track_remove_key(track, held.track_get_key_count(track) - 1)
	var library := AnimationLibrary.new()
	library.add_animation(&"frozen", held)
	player.add_animation_library(&"probe", library)
	var travel := _travel(player, skeleton, "probe/frozen")
	_drop(rig["scene"])
	assert_true(
		float(travel["rotation"]) <= MOVED_RADIANS and float(travel["position"]) <= MOVED_METRES,
		"a take with one key per track measured %.5f rad / %.5f m of motion, so the instrument cannot tell a dead take from a live one" % [
			travel["rotation"], travel["position"]]
	)
