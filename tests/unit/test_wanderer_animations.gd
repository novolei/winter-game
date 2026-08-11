extends TestCase

## The merged animation library is a contract in three parts, and the middle one
## is here because it has already gone wrong once, expensively and silently.
##
## 1. THE NAMES. Twenty takes arrived across three files under names Meshy chose
##    -- `Run_02`, `Spear_Walk`, and two called `Scene`. The game addresses them
##    by what the motion is. A source take that disappears or gets renamed
##    upstream must fail here rather than in a blend tree that quietly plays
##    nothing.
##
## 2. THE UNITS. The character model's skeleton is in centimetres: its Hips rest
##    sits at y = 85.07. The same rig read out of Godot's *FBX* importer instead
##    is in metres, and one of the two animation-only deliveries is still Z-up
##    on top of that -- Hips rest z = 0.84. Copying a track across that gap puts
##    the skeleton through a hundredfold scale, and the symptom is not an error
##    of any kind: the character simply is not in the frame any more, his bones
##    flung tens of metres apart, with a clean console and a green suite. That
##    is why every take is now merged in Blender by tools/decimate_character.py
##    and why test_every_take_is_in_the_model_s_own_units exists.
##
## 3. THE LOOP FLAGS. A cycle that does not loop stops dead at its last frame; a
##    one-shot that does loops the character back to standing out of a death.
##    Both are silent. The table is measured -- see the wave report -- and this
##    pins the library to it.

const Wanderer := preload("res://src/entities/player/wanderer_animations.gd")

## The Hips rest height in the model's own units, and the tolerance the unit
## check allows around it. Half is enormously generous for a biped -- the
## deepest crouch in the file drops the hips to 66 -- and still leaves a
## metres-for-centimetres mistake off by a factor of fifty.
const HIPS_REST_TOLERANCE := 0.5


func _library() -> AnimationLibrary:
	return Wanderer.build()


func _hips_rest_height() -> float:
	var resource := ResourceLoader.load(Wanderer.MODEL_PATH)
	if not (resource is PackedScene):
		return 0.0
	var scene := (resource as PackedScene).instantiate()
	var height := 0.0
	for node in scene.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for index in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(index) == "Hips":
				height = skeleton.get_bone_rest(index).origin.y
	# Node is not reference counted (briefing section 2.2).
	scene.free()
	return height


func test_every_take_is_in_the_library() -> void:
	var library := _library()
	for row in Wanderer.TAKES:
		assert_true(
			library.has_animation(StringName(row[2])),
			"%s was merged from %s / %s and is not in the library" % [row[2], String(row[0]).get_file(), row[1]]
		)
	assert_eq(
		library.get_animation_list().size(), Wanderer.TAKES.size(),
		"the library must hold exactly the takes in TAKES and nothing else"
	)


## The three the movement code names. Separate from the test above because these
## are the ones whose absence stops the game rather than a later wave.
func test_the_clips_the_movement_code_asks_for_resolve() -> void:
	var library := _library()
	for clip in [Wanderer.IDLE, Wanderer.WALK, Wanderer.RUN]:
		assert_true(library.has_animation(clip), "player_controller plays %s and it is not in the library" % clip)


func test_no_take_keeps_the_name_meshy_gave_it() -> void:
	var library := _library()
	for row in Wanderer.TAKES:
		assert_true(
			String(row[1]) != String(row[2]) or String(row[1]) == String(row[1]).to_lower(),
			"%s is still Meshy's own name; the library is named for what the motion is" % row[2]
		)


## Every track has to address the character model's own skeleton node. A path
## that resolves to nothing does not error -- it animates no bone, and the
## character stands in his bind pose with the console clean.
func test_every_track_addresses_the_character_skeleton() -> void:
	var library := _library()
	var prefix := Wanderer.SKELETON_PATH + ":"
	for name in library.get_animation_list():
		var animation := library.get_animation(name)
		assert_true(animation.get_track_count() > 0, "%s holds no tracks at all" % name)
		for index in range(animation.get_track_count()):
			var path := String(animation.track_get_path(index))
			assert_true(path.begins_with(prefix), "%s track %d addresses %s, not %s" % [name, index, path, prefix])


## The one with teeth. See the note at the top of this file: reading the two
## later takes out of their own .fbx instead of out of the merged model puts
## this at 0.84 against a rest of 85.07, and nothing else anywhere reports it.
func test_every_take_is_in_the_model_s_own_units() -> void:
	var rest := _hips_rest_height()
	assert_true(rest > 1.0, "the model's Hips rest height read as %f; the check below means nothing without it" % rest)
	var library := _library()
	for name in library.get_animation_list():
		var animation := library.get_animation(name)
		var found := false
		for index in range(animation.get_track_count()):
			if animation.track_get_type(index) != Animation.TYPE_POSITION_3D:
				continue
			if not String(animation.track_get_path(index)).ends_with(":Hips"):
				continue
			found = true
			var first: Vector3 = animation.track_get_key_value(index, 0)
			assert_true(
				absf(first.y - rest) <= rest * HIPS_REST_TOLERANCE,
				"%s starts with its hips at y = %f against a rest of %f: this take is not in the model's units"
					% [name, first.y, rest]
			)
		assert_true(found, "%s has no Hips position track, so its units cannot be checked" % name)


func test_the_loop_flags_match_the_measured_table() -> void:
	var library := _library()
	for row in Wanderer.TAKES:
		var animation := library.get_animation(StringName(row[2]))
		if animation == null:
			continue
		var wanted := Animation.LOOP_LINEAR if bool(row[3]) else Animation.LOOP_NONE
		assert_eq(animation.loop_mode, wanted, "%s should loop=%s" % [row[2], row[3]])


## The rig claim, checked rather than assumed: every bone any take drives has to
## exist on the character. A future delivery on a different rig fails here
## instead of animating nothing.
func test_every_animated_bone_exists_on_the_rig() -> void:
	var bones := Wanderer.bone_names(Wanderer.MODEL_PATH)
	assert_eq(bones.size(), 24, "the Winter Wanderer rig is 24 bones; this read %d" % bones.size())
	var library := _library()
	var seen: Dictionary = {}
	for name in library.get_animation_list():
		var animation := library.get_animation(name)
		for index in range(animation.get_track_count()):
			var bone := String(animation.track_get_path(index)).get_slice(":", 1)
			if bone == "" or seen.has(bone):
				continue
			seen[bone] = true
			assert_true(bones.has(bone), "%s drives a bone called %s and the rig has no such bone" % [name, bone])
	assert_true(seen.size() >= 20, "only %d distinct bones are driven by any take" % seen.size())
