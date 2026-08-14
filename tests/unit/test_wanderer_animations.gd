extends TestCase

## The merged animation library is a contract in three parts, and the middle one
## is here because it has already gone wrong once, expensively and silently.
##
## 1. THE NAMES. Twenty-two takes arrived across the merged deliveries under names Meshy chose
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
	# TAKES plus the two takes that do not come out of the merged model: the
	# retargeted hunger stand and feeding gesture. Named rather than allowed for
	# by `+ 2`, so a third undeclared take still fails.
	assert_true(
		library.has_animation(Wanderer.IDLE_HUNCHED),
		"%s is baked by tools/retarget_hunch.gd and is not in the library" % Wanderer.IDLE_HUNCHED
	)
	assert_true(
		library.has_animation(Wanderer.FEED),
		"%s is baked by tools/retarget_feed.gd and is not in the library" % Wanderer.FEED
	)
	var declared: Array = [String(Wanderer.IDLE_HUNCHED), String(Wanderer.FEED)]
	for row in Wanderer.TAKES:
		declared.append(String(row[2]))
	for name in library.get_animation_list():
		assert_true(
			declared.has(String(name)),
			"the library holds %s, which is neither in TAKES nor one of the two baked actions" % name
		)
	assert_eq(
		library.get_animation_list().size(), declared.size(),
		"the library must hold exactly TAKES plus the baked hunch and feed action"
	)


## Feeding is a one-shot from another rig, baked before runtime just like the
## hunger hunch.  Its public contract starts at the merged library: callers ask
## for one semantic name and never know which donor pack authored the gesture.
func test_the_feed_action_is_baked_into_the_library() -> void:
	var library := _library()
	var present := library.has_animation(Wanderer.FEED)
	assert_true(
		present,
		"feed is baked by tools/retarget_feed.gd but WandererAnimations.build() does not expose it"
	)
	if not present:
		return
	var animation := library.get_animation(Wanderer.FEED)
	assert_eq(animation.loop_mode, Animation.LOOP_NONE,
		"feeding is one scattering gesture, not a repeating arm cycle")
	assert_almost_eq(animation.length, 1.0333, 0.002,
		"the baked action no longer has UnarmedActivate's authored duration")
	assert_eq(animation.get_track_count(), 48,
		"the 24-bone target must carry one position and one rotation track per bone")
	var positions := 0
	var rotations := 0
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			positions += 1
		elif animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			rotations += 1
	assert_eq(positions, 24, "feed does not carry every target bone's position")
	assert_eq(rotations, 24, "feed does not carry every target bone's rotation")


## This is an upper-body action.  The source pelvis drifts by several
## centimetres and its proportions do not match this rig, so carrying the donor
## root or legs would slide planted boots even though the action is played while
## the controller has stopped movement.
func test_feed_holds_the_wanderer_root_and_both_legs_at_neutral() -> void:
	var animation := _library().get_animation(Wanderer.FEED)
	assert_not_null(animation, "the neutral-track contract needs the baked feed action")
	if animation == null:
		return
	var packed := ResourceLoader.load(Wanderer.MODEL_PATH)
	assert_true(packed is PackedScene, "the target rig cannot be inspected")
	if not (packed is PackedScene):
		return
	var scene := (packed as PackedScene).instantiate()
	var skeleton: Skeleton3D = null
	for node in scene.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	assert_not_null(skeleton, "the wanderer model has no Skeleton3D")
	if skeleton == null:
		scene.free()
		return
	for bone in [
		"Hips",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
	]:
		var bone_index := skeleton.find_bone(bone)
		assert_true(bone_index >= 0, "the neutral contract names a missing target bone %s" % bone)
		if bone_index < 0:
			continue
		var rest := skeleton.get_bone_rest(bone_index)
		var path := NodePath("%s:%s" % [Wanderer.SKELETON_PATH, bone])
		var position_track := animation.find_track(path, Animation.TYPE_POSITION_3D)
		var rotation_track := animation.find_track(path, Animation.TYPE_ROTATION_3D)
		assert_true(position_track >= 0, "%s has no neutral position track" % bone)
		assert_true(rotation_track >= 0, "%s has no neutral rotation track" % bone)
		var worst_position := 0.0
		var worst_rotation := 0.0
		if position_track >= 0:
			for key in range(animation.track_get_key_count(position_track)):
				var value: Vector3 = animation.track_get_key_value(position_track, key)
				worst_position = maxf(worst_position, value.distance_to(rest.origin))
		if rotation_track >= 0:
			var rest_rotation := rest.basis.orthonormalized().get_rotation_quaternion()
			for key in range(animation.track_get_key_count(rotation_track)):
				var value: Quaternion = animation.track_get_key_value(rotation_track, key)
				worst_rotation = maxf(worst_rotation, rad_to_deg(value.angle_to(rest_rotation)))
		assert_true(worst_position <= 0.001,
			"%s travels %.5f rig units during an upper-body one-shot" % [bone, worst_position])
		assert_true(worst_rotation <= 0.1,
			"%s turns %.3f degrees away from neutral during an upper-body one-shot" % [bone, worst_rotation])
	scene.free()


## The donor name is not evidence that the pose survived a different skeleton.
## Sample what the shipping AnimationPlayer does to the wanderer and require a
## visible hand excursion while the root stays planted.
func test_feed_preserves_the_authored_reach_on_the_target_silhouette() -> void:
	var packed := ResourceLoader.load(Wanderer.MODEL_PATH)
	assert_true(packed is PackedScene, "the target rig cannot be sampled")
	if not (packed is PackedScene):
		return
	var scene := (packed as PackedScene).instantiate() as Node3D
	Engine.get_main_loop().root.add_child(scene)
	var skeleton: Skeleton3D = null
	var player: AnimationPlayer = null
	for node in scene.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		break
	assert_not_null(skeleton, "the wanderer model has no Skeleton3D")
	assert_not_null(player, "the wanderer model has no AnimationPlayer")
	if skeleton == null or player == null:
		scene.free()
		return
	for library_name in player.get_animation_library_list():
		player.remove_animation_library(library_name)
	player.add_animation_library(&"", _library())
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var animation := player.get_animation(Wanderer.FEED)
	assert_not_null(animation, "the target AnimationPlayer cannot resolve feed")
	if animation == null:
		scene.free()
		return
	var frame := _anatomical_frame(skeleton)
	var hips := skeleton.find_bone("Hips")
	var hand := skeleton.find_bone("LeftHand")
	var metres_per_unit := skeleton.global_transform.basis.get_scale().y
	var forward_min := INF
	var forward_max := -INF
	var root_start := Vector3.ZERO
	var root_travel := 0.0
	player.play(Wanderer.FEED)
	for sample in range(32):
		player.seek(animation.length * float(sample) / 31.0, true)
		player.advance(0.0)
		var root_now := skeleton.get_bone_global_pose(hips).origin
		if sample == 0:
			root_start = root_now
		root_travel = maxf(root_travel, root_now.distance_to(root_start) * metres_per_unit)
		var offset := skeleton.get_bone_global_pose(hand).origin - root_now
		var forward := offset.dot(frame.z) * metres_per_unit
		forward_min = minf(forward_min, forward)
		forward_max = maxf(forward_max, forward)
	assert_true(forward_max - forward_min >= 0.20,
		"the baked hand moves only %.3f m fore/aft; the scattering reach did not survive retargeting"
			% (forward_max - forward_min))
	assert_true(root_travel <= 0.001,
		"the feed action moves the root %.5f m while the player is supposed to stand" % root_travel)
	scene.free()


func _anatomical_frame(skeleton: Skeleton3D) -> Basis:
	var hips := skeleton.find_bone("Hips")
	var head := skeleton.find_bone("Head")
	var foot := skeleton.find_bone("LeftFoot")
	var toe := skeleton.find_bone("LeftToeBase")
	var thigh := skeleton.find_bone("LeftUpLeg")
	var pelvis := skeleton.get_bone_global_rest(hips).origin
	var up := (skeleton.get_bone_global_rest(head).origin - pelvis).normalized()
	var forward := skeleton.get_bone_global_rest(toe).origin \
		- skeleton.get_bone_global_rest(foot).origin
	forward = (forward - up * forward.dot(up)).normalized()
	var left := up.cross(forward).normalized()
	if (skeleton.get_bone_global_rest(thigh).origin - pelvis).dot(left) < 0.0:
		left = -left
	return Basis(left, up, forward).orthonormalized()


## The seven the movement code names. Separate from the test above because these
## are the ones whose absence stops the game rather than a later wave.
func test_the_clips_the_movement_code_asks_for_resolve() -> void:
	var library := _library()
	for clip in [
		Wanderer.IDLE, Wanderer.IDLE_COLD, Wanderer.IDLE_HUNCHED,
		Wanderer.WALK, Wanderer.RUN, Wanderer.WALK_GUARDED, Wanderer.WALK_DEEP,
	]:
		assert_true(library.has_animation(clip), "player_controller plays %s and it is not in the library" % clip)


## Blender's FBX importer changes the whole scene frame rate to that of the last
## imported file. The deep walk is 60 fps while the library is 30 fps; without
## the explicit retime in decimate_character.py every older take exports at
## double speed even though all names, tracks and loop flags still look valid.
func test_a_60_fps_delivery_does_not_halve_the_existing_library() -> void:
	var library := _library()
	assert_almost_eq(
		library.get_animation(Wanderer.WALK).length, 1.0667, 0.02,
		"the 30 fps walk changed duration while merging the 60 fps deep-snow take"
	)
	assert_almost_eq(
		library.get_animation(Wanderer.WALK_DEEP).length, 5.5, 0.05,
		"the 60 fps deep-snow take no longer lasts its authored 5.5 seconds"
	)


## The one the owner asked for by name, and the one claim about it that a
## screenshot cannot make.
##
## `idle` is Meshy's `Idle_4` and the owner's word for it was 僵硬 -- stiff. That
## is measurable: a shiver is a high-frequency tremor, so the direction of every
## joint reverses many times a second, where a slow warm sway reverses a handful
## of times across its whole loop. Counting those reversals is the difference
## between the two takes, it is what makes the cold idle a readout for 体温 under
## GDD section 5, and it is invisible in any still frame.
##
## Measured on the shipped library: idle 1.80 reversals/s, idle_cold 5.13.
func test_the_cold_idle_is_the_one_that_actually_shivers() -> void:
	var library := _library()
	var warm := _reversals_per_second(library.get_animation(Wanderer.IDLE))
	var cold := _reversals_per_second(library.get_animation(Wanderer.IDLE_COLD))
	assert_true(
		warm > 0.0, "the neutral idle measured %f reversals/s; the comparison below means nothing" % warm
	)
	assert_true(
		cold >= warm * 2.0,
		"idle_cold reverses %f times a second against idle's %f: these two are the "
			% [cold, warm]
			+ "same kind of stand, and the cold one is supposed to be a tremor"
	)


## A visible pop at the loop point is worse than a stiff idle, so the seam is
## pinned rather than trusted. Measured: 6.87 degrees, on RightForeArm -- against
## walk_balance's 27.76 on a planted foot, which the inventory flags as *not*
## looping. LOOP_LINEAR interpolates across the seam over one frame, so on a take
## whose whole character is high-frequency micro-motion it is not distinguishable
## from the shiver.
func test_the_cold_idle_closes_its_loop() -> void:
	var animation := _library().get_animation(Wanderer.IDLE_COLD)
	assert_eq(animation.loop_mode, Animation.LOOP_LINEAR, "idle_cold is played as a loop")
	var worst := 0.0
	for index in range(animation.get_track_count()):
		if animation.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var first: Quaternion = animation.rotation_track_interpolate(index, 0.0)
		var last: Quaternion = animation.rotation_track_interpolate(index, animation.length)
		worst = maxf(worst, rad_to_deg(first.angle_to(last)))
	assert_true(
		worst <= 12.0,
		"idle_cold's worst joint is %f degrees out at the loop seam; past about a "
			% worst
			+ "dozen the wrap reads as a twitch of its own rather than as the shiver"
	)


## Reversals per second of a take's angular motion, averaged over the bones a
## shiver actually shows in. Sampled at 30 Hz, which is the rate Meshy authors at
## -- sampling faster would only interpolate.
func _reversals_per_second(animation: Animation) -> float:
	if animation == null:
		return 0.0
	const BONES := ["Spine02", "Head", "LeftHand", "RightHand", "Hips"]
	var total := 0.0
	var counted := 0
	for index in range(animation.get_track_count()):
		if animation.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		if not BONES.has(String(animation.track_get_path(index)).get_slice(":", 1)):
			continue
		var step := 1.0 / 30.0
		var base: Quaternion = animation.rotation_track_interpolate(index, 0.0)
		var previous_delta := 0.0
		var last := 0.0
		var reversals := 0
		for frame in range(int(animation.length / step)):
			var here: Quaternion = animation.rotation_track_interpolate(index, float(frame) * step)
			var angle := base.angle_to(here)
			var delta := angle - last
			# The epsilon keeps float noise on a genuinely still bone from
			# counting as a tremor, which would make every take look like a shiver.
			if frame > 1 and absf(delta) > 0.00002 and signf(delta) != signf(previous_delta):
				reversals += 1
			if absf(delta) > 0.00002:
				previous_delta = delta
			last = angle
		total += float(reversals) / animation.length
		counted += 1
	if counted == 0:
		return 0.0
	return total / float(counted)


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
