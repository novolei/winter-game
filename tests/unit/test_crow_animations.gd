extends TestCase

## The seven takes a crow plays, and the slicer that cuts them out of the pack's
## long ones.
##
## Split in two on purpose. The first half is arithmetic on a hand-built
## Animation and needs no asset at all, so a slicing bug is reported as a slicing
## bug; the second half opens the real delivery, so a re-import that changed what
## is in the file is reported against the file.
##
## ---------------------------------------------------------------------------
## WHAT MOVED, AND WHY THIS FILE STILL HAS THE SAME TWELVE TESTS
## ---------------------------------------------------------------------------
## `crow_animations.gd` is gone. The slicer is `BirdAnimations`, which is not
## about crows -- it is about a pack that ships one long take per file -- and the
## frame table is `data/wildlife/crow.tres`, which is. Every assertion below is
## the one it was; only where it reads the table from has changed, from a `const
## FRAMES` in a `.gd` to `Crow.SPECIES.takes`.

const BirdAnimationsScript := preload("res://src/entities/wildlife/bird_animations.gd")

const FPS := 30.0


## A take with one bone, keyed every frame from 0 to 100, whose value is its own
## frame number -- so a sliced key says which source frame it came from.
func _authored() -> Animation:
	var animation := Animation.new()
	animation.length = 100.0 / FPS
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("CG"))
	for frame in range(101):
		animation.position_track_insert_key(track, float(frame) / FPS, Vector3(0.0, float(frame), 0.0))
	var spine := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(spine, NodePath("CG/Pelvis/Spine"))
	for frame in range(101):
		animation.rotation_track_insert_key(spine, float(frame) / FPS, Quaternion.IDENTITY)
	# The rig's odd node out: the animation files carry a `Root` null the model's
	# skeleton does not have.
	var root := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(root, NodePath("Root"))
	animation.position_track_insert_key(root, 0.0, Vector3.ZERO)
	return animation


func _bones() -> Dictionary:
	return {"CG": true, "Spine": true}


# --- the slicer ---------------------------------------------------------------


func test_a_slice_is_as_long_as_the_frames_it_names() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 20, 50, true, false, _bones())
	assert_almost_eq(sliced.length, 30.0 / FPS, 0.0001, "a 20..50 slice is thirty frames long")
	assert_eq(sliced.loop_mode, Animation.LOOP_LINEAR, "the slice was asked to loop and does not")


func test_a_slice_starts_at_the_frame_it_names_and_is_rebased_to_zero() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 20, 50, false, false, _bones())
	var track := _track_for(sliced, "Skeleton3D:CG", Animation.TYPE_POSITION_3D)
	assert_true(track >= 0, "the sliced take has no CG position track")
	if track < 0:
		return
	assert_almost_eq(sliced.track_get_key_time(track, 0), 0.0, 0.0001, "the slice does not start at zero")
	var first: Vector3 = sliced.position_track_interpolate(track, 0.0)
	var last: Vector3 = sliced.position_track_interpolate(track, sliced.length)
	assert_almost_eq(first.y, 20.0, 0.001, "the slice opens on source frame %.1f, not frame 20" % first.y)
	assert_almost_eq(last.y, 50.0, 0.001, "the slice ends on source frame %.1f, not frame 50" % last.y)
	assert_eq(sliced.loop_mode, Animation.LOOP_NONE, "the slice was asked not to loop and does")


func test_a_slice_carries_every_frame_between_its_ends() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 20, 50, false, false, _bones())
	var track := _track_for(sliced, "Skeleton3D:CG", Animation.TYPE_POSITION_3D)
	assert_eq(
		sliced.track_get_key_count(track), 31,
		"a 20..50 slice of a take keyed every frame should hold 31 keys, not %d" % sliced.track_get_key_count(track)
	)


## The `in_place` column of the species' take table. A take that moves the bird
## and code that moves the bird are two answers to one question.
func test_an_in_place_slice_holds_the_root_still_and_leaves_the_rest_alone() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 20, 50, false, true, _bones())
	var track := _track_for(sliced, "Skeleton3D:CG", Animation.TYPE_POSITION_3D)
	assert_eq(sliced.track_get_key_count(track), 1, "an in-place slice must leave the root one key")
	var held: Vector3 = sliced.position_track_interpolate(track, sliced.length)
	assert_almost_eq(held.y, 20.0, 0.001, "the held root is not the pose the slice opens on")
	assert_true(
		_track_for(sliced, "Skeleton3D:Spine", Animation.TYPE_ROTATION_3D) >= 0,
		"flattening the root took the rest of the skeleton with it"
	)


func test_every_track_is_addressed_to_the_models_skeleton() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 0, 100, true, false, _bones())
	for track in range(sliced.get_track_count()):
		var path := String(sliced.track_get_path(track))
		assert_true(
			path.begins_with("Skeleton3D:"),
			"track %d addresses %s -- an imported node path animates nothing once the take is on the model" % [track, path]
		)


## A track naming a bone the skeleton does not have animates nothing while
## looking exactly like a track that works.
func test_a_track_for_something_that_is_not_a_bone_is_dropped() -> void:
	var sliced := BirdAnimationsScript.slice(_authored(), 0, 100, true, false, _bones())
	for track in range(sliced.get_track_count()):
		assert_false(
			String(sliced.track_get_path(track)).ends_with(":Root"),
			"the animation files' `Root` null was carried through onto a skeleton that has no such bone"
		)


func _track_for(animation: Animation, path: String, type: int) -> int:
	for track in range(animation.get_track_count()):
		if String(animation.track_get_path(track)) == path and animation.track_get_type(track) == type:
			return track
	return -1


# --- the delivery -------------------------------------------------------------


func test_the_model_and_all_four_animation_files_are_on_disk() -> void:
	var wanted := PackedStringArray([Crow.SPECIES.model_path])
	wanted.append_array(Crow.SPECIES.source_files())
	assert_eq(wanted.size(), 5, "the crow is one model and four animation files; the species names %d" % wanted.size())
	for path in wanted:
		assert_true(ResourceLoader.exists(path), "%s is not in the project" % path)


func test_the_library_holds_the_six_takes_this_feature_plays() -> void:
	var library := BirdAnimationsScript.build(Crow.SPECIES)
	for role in [
		BirdSpecies.PERCH, BirdSpecies.LOOK, BirdSpecies.FLAP,
		BirdSpecies.TAKE_OFF, BirdSpecies.FLY, BirdSpecies.GLIDE,
	]:
		var take := Crow.SPECIES.take_for(role)
		assert_true(take != &"", "the crow has no take for the %s role" % role)
		assert_true(library.has_animation(take), "the library has no take called %s" % take)
	assert_eq(
		library.get_animation_list().size(), Crow.SPECIES.takes.size(),
		"the library holds %d takes and the species names %d" % [
			library.get_animation_list().size(), Crow.SPECIES.takes.size()]
	)


## Fifty-five clips were delivered. Seven were imported. A test that only checked
## the seven were present would go on passing if an eighth arrived by accident,
## and the cost of the extra is memory in every crow in the flock.
func test_nothing_beyond_the_six_was_imported() -> void:
	var library := BirdAnimationsScript.build(Crow.SPECIES)
	var wanted := {}
	for take in Crow.SPECIES.takes:
		wanted[take.take_name] = true
	for name in library.get_animation_list():
		assert_true(wanted.has(name), "the library holds an unasked-for take: %s" % name)


func test_every_take_is_as_long_as_its_frame_range() -> void:
	var library := BirdAnimationsScript.build(Crow.SPECIES)
	for take in Crow.SPECIES.takes:
		if not library.has_animation(take.take_name):
			continue
		var expected := float(take.last_frame - take.first_frame) / Crow.SPECIES.source_fps
		assert_almost_eq(
			library.get_animation(take.take_name).length, expected, 0.001,
			"%s is %.3f s but frames %d..%d are %.3f s -- the source was trimmed on import" % [
				take.take_name, library.get_animation(take.take_name).length,
				take.first_frame, take.last_frame, expected]
		)


func test_the_perched_takes_loop_and_the_one_shots_do_not() -> void:
	var library := BirdAnimationsScript.build(Crow.SPECIES)
	for take in Crow.SPECIES.takes:
		if not library.has_animation(take.take_name):
			continue
		var expected := Animation.LOOP_LINEAR if take.loops else Animation.LOOP_NONE
		assert_eq(
			library.get_animation(take.take_name).loop_mode, expected,
			"%s's loop mode is not what the species says it is" % take.take_name
		)


## Every bone in every take, or a switch between takes leaves the bones one of
## them does not touch wherever the other left them -- a perched crow with its
## wings still spread.
func test_every_take_addresses_the_whole_skeleton() -> void:
	var bones := BirdAnimationsScript.bone_names(Crow.SPECIES.model_path)
	assert_true(bones.size() > 100, "the model reports %d bones; the delivered rig has 121" % bones.size())
	var library := BirdAnimationsScript.build(Crow.SPECIES)
	for name in library.get_animation_list():
		var animation := library.get_animation(name)
		var moved: Dictionary = {}
		for track in range(animation.get_track_count()):
			moved[String(animation.track_get_path(track)).split(":")[1]] = true
		assert_eq(
			moved.size(), bones.size(),
			"%s moves %d of the skeleton's %d bones -- the rest keep whatever the previous take left them at (animation/remove_immutable_tracks must be false)" % [
				name, moved.size(), bones.size()]
		)
