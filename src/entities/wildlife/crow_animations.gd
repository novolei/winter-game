class_name CrowAnimations
extends RefCounted

## The six takes a crow on a wire needs, in one AnimationLibrary, under names
## that say what the motion is.
##
## ---------------------------------------------------------------------------
## WHERE THEY COME FROM, AND WHY THEY ARE SLICED HERE RATHER THAN SPLIT ON DISK
## ---------------------------------------------------------------------------
## The delivery is a Unity package (Malbers "Poly Art Ravens & Crows" v4.1) and
## Unity's animation model is not Godot's: an `.FBX` there holds **one long
## take**, and the fifty-five clips the pack advertises are *frame ranges* named
## in the companion `.meta` file. `Raven Fly.FBX` is a single 512-frame take
## carrying fifteen clips end to end.
##
## So there is nothing on disk to import as "the glide". FRAMES is that `.meta`
## file's table, for the six ranges this feature plays, and `build()` cuts them
## out. Everything else in the pack -- the attacks, the deaths, the eating and
## drinking, the walk -- is deliberately not imported: the crow lands on a wire
## and leaves, and fifty-five takes for that is fifty-five things to keep in
## step with a rig nobody is going to touch again.
##
## ---------------------------------------------------------------------------
## WHY NOTHING HERE GOES THROUGH BLENDER, WHICH IS THE OPPOSITE OF THE WANDERER
## ---------------------------------------------------------------------------
## `tools/decimate_character.py` exists because Godot's FBX importer lands a rig
## in a *different space* from a Blender glTF export of the same rig -- metres
## against centimetres, and one of them still Z-up -- so the wanderer's extra
## takes had to come through the same Blender round trip as his mesh or the
## skeleton was flung apart by a factor of a hundred.
##
## The same rule, applied here, says the opposite: **the crow's mesh and all
## four of its animation files go through Godot's own FBX importer and nothing
## else.** One importer, one space, by construction. Measured: the model's root
## bone `CG` rests at y = 0.139042 out of Godot, and Blender reads the same node
## at z = 13.9042 cm out of the same file -- the identical number, which is what
## says the two paths agree about this delivery and that only one of them needs
## to be used.
##
## Blender is also no help with these files even if it were wanted. The four
## animation `.FBX`s carry **no armature at all** -- 3ds Max exported the rig as
## a hierarchy of nulls -- so both of Blender's importers bring them in as 121
## Empties with object-level f-curves, and there is no pose to retarget. Godot's
## ufbx importer reads the same hierarchy as node tracks (`CG/Pelvis/Spine`),
## which is one rename away from a skeleton track. That rename is `_bone_track`.
##
## ---------------------------------------------------------------------------
## THREE IMPORT SETTINGS THAT ARE PART OF THE ASSET, NOT PREFERENCES
## ---------------------------------------------------------------------------
##   animation/trimming=false          Godot trims leading and trailing stillness
##                                     by default, which slides every frame number
##                                     in FRAMES by an amount nothing records.
##   animation/remove_immutable_tracks=false
##                                     Default true drops a bone whose value never
##                                     leaves its rest. Playing take A then take B
##                                     then A again would leave every bone B moved
##                                     and A does not exactly where B left it --
##                                     a perched crow with its wings still spread.
##                                     363 tracks per take instead of 51 to 154
##                                     is the price of a clean switch.
##   meshes/generate_lods=false        Art Bible rule 7's reason, at a bird's
##                                     size: there is nothing to remove that is
##                                     not the silhouette.
##
## `tests/art/test_crow_model.gd` asserts all three against the `.import` files.

const MODEL_PATH := "res://assets/models/characters/crow/crow.fbx"

const PERCH_FILE := "res://assets/models/characters/crow/crow_perch.fbx"
const TURN_FILE := "res://assets/models/characters/crow/crow_turn.fbx"
const FLY_FILE := "res://assets/models/characters/crow/crow_fly.fbx"
const TAKEOFF_FILE := "res://assets/models/characters/crow/crow_takeoff.fbx"

## Where the skeleton hangs under the imported model, and therefore the node
## half of every track path this builds.
const SKELETON_PATH := "Skeleton3D"

## The library name the AnimationPlayer holds these under, so a take is asked
## for as "crow/perch".
const LIBRARY := &"crow"

## The rate the pack was authored at. Every number in FRAMES is a frame index in
## a take sampled at this rate, which is also what `animation/fps` in each
## `.import` is set to -- so a frame index divided by this is a time in seconds.
const SOURCE_FPS := 30.0

## The names the game asks for. Named constants rather than string literals at
## the call site so a rename here is a compile-time move.
const PERCH := &"perch"
const LOOK := &"look"
const FLAP := &"flap"
const TAKE_OFF := &"take_off"
const FLY := &"fly"
const GLIDE := &"glide"

## [source file, first frame, last frame, name in the library, loops, in place].
##
## The frame numbers are Malbers' own, read out of each `.FBX.meta`'s
## `clipAnimations` block, and the Unity clip each row came from is named in the
## comment so the cross-reference back to the pack survives the next delivery.
##
## IN PLACE is the column worth reading twice. `Rav_TakeOff` carries **baked root
## motion** -- the CG bone climbs 0.30 m and travels 0.37 m forward across its 29
## frames -- and so do the two flight cycles. A take that moves the bird *and*
## code that moves the bird are two answers to one question, and the visible
## result is a crow travelling at twice the speed anything asked for. So the
## three takes the game drives are flattened to a single root key and
## `src/entities/wildlife/crow.gd` owns every metre. The two perched takes keep
## theirs: it is 2 mm of sway, and it is the difference between a bird and a
## decal.
const FRAMES: Array = [
	# Rav_Perch -- the whole point of the asset: feet closed round something thin.
	[PERCH_FILE, 123, 182, PERCH, true, false],
	# Rav_Turn_Right -- the look. Malbers marks it looping, which would be a bird
	# spinning on the spot; it is played once here and the perch take's own root
	# track puts the bird back the way it was.
	[TURN_FILE, 0, 24, LOOK, false, false],
	# Rav_Fly_Stand -- wings worked without leaving the perch. The fidget.
	[FLY_FILE, 1, 25, FLAP, true, true],
	# Rav_TakeOff -- the launch.
	[TAKEOFF_FILE, 1, 29, TAKE_OFF, false, true],
	# Rav_Fly_Forward -- flapping flight.
	[FLY_FILE, 82, 106, FLY, true, true],
	# Rav_Fly_Glide -- wings out, no beat.
	[FLY_FILE, 163, 195, GLIDE, true, true],
]


## One library holding every take under its library name.
##
## Allocates no Node in the common path: the animations and the bone names are
## both lifted out of PackedScene SceneStates rather than out of instantiated
## trees, so nothing here has to be freed and a test may call it freely.
static func build() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var bones := bone_names(MODEL_PATH)
	var cache: Dictionary = {}
	for row in FRAMES:
		var source: String = row[0]
		if not cache.has(source):
			cache[source] = long_take(source)
		var take: Animation = cache[source]
		if take == null:
			push_warning("crow_animations: %s holds no animation" % source)
			continue
		var sliced := slice(take, int(row[1]), int(row[2]), bool(row[4]), bool(row[5]), bones)
		library.add_animation(StringName(row[3]), sliced)
	return library


## The single long take inside one imported animation file, with its length
## corrected to what its keys actually span.
##
## THE LENGTH CORRECTION IS NOT TIDINESS. Measured on 4.7.1: `crow_perch.fbx`
## imports with `length = 3.3333` while its tracks carry keys out to frame 182,
## which is 6.07 s. Everything below samples the source with
## `*_track_interpolate()`, and those clamp to `length` -- so without this the
## perch take would be cut out of a range the sampler refuses to read and the
## slice would come back as one held pose.
##
## Duplicated deeply first, because `ResourceLoader` hands every caller the same
## instance (briefing trap 6) and setting `length` on the shared one would edit
## the asset for everything that ever loads it.
static func long_take(path: String) -> Animation:
	var found := animations_in(path)
	if found.is_empty():
		return null
	var names := found.keys()
	names.sort()
	var animation: Animation = (found[names[0]] as Animation).duplicate(true)
	animation.length = maxf(animation.length, _last_key_time(animation))
	return animation


## Every animation in an imported scene, by the name its AnimationPlayer knows.
##
## Read off `PackedScene.get_state()` rather than `instantiate()`: a SceneState
## is walked without building a node tree, so nothing here allocates a Node.
## An AnimationPlayer stores one property per library, named `libraries/<name>`,
## and the value is the AnimationLibrary itself.
static func animations_in(path: String) -> Dictionary:
	var found: Dictionary = {}
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		push_warning("crow_animations: %s did not load as a PackedScene" % path)
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


## The bones the model's skeleton actually has, as a Dictionary used as a set.
##
## A track is only kept when its leaf name is one of these. The animation files
## carry one node the model does not -- a `Root` null above `CG` -- and a track
## addressing a bone that is not there animates nothing while looking exactly
## like a track that works.
##
## Skeleton3D serialises its bones as `bones/<n>/name`, which is readable off the
## SceneState without instancing anything.
static func bone_names(path: String) -> Dictionary:
	var names: Dictionary = {}
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		return names
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			var key := String(state.get_node_property_name(node, property))
			if not (key.begins_with("bones/") and key.ends_with("/name")):
				continue
			names[String(state.get_node_property_value(node, property))] = true
	return names


## One named take, cut out of the long one.
##
## Boundary keys are sampled rather than snapped to the nearest authored key, so
## a range whose ends fall between keys still starts and finishes on the pose the
## table names. The pack keys on every frame, so in practice they land on
## existing keys and the sample returns them unchanged -- which is the point:
## it costs nothing when the data is dense and is correct when it is not.
static func slice(
	source: Animation,
	first_frame: int,
	last_frame: int,
	loops: bool,
	in_place: bool,
	bones: Dictionary
) -> Animation:
	var from := float(first_frame) / SOURCE_FPS
	var to := float(last_frame) / SOURCE_FPS
	var root := _root_of(source, bones)
	var out := Animation.new()
	out.length = maxf(to - from, 1.0 / SOURCE_FPS)
	out.step = source.step
	out.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	for track in range(source.get_track_count()):
		var type := source.track_get_type(track)
		if type != Animation.TYPE_POSITION_3D \
				and type != Animation.TYPE_ROTATION_3D \
				and type != Animation.TYPE_SCALE_3D:
			continue
		var bone := _leaf(String(source.track_get_path(track)))
		if not bones.has(bone):
			continue
		var index := out.add_track(type)
		out.track_set_path(index, NodePath("%s:%s" % [SKELETON_PATH, bone]))
		out.track_set_interpolation_type(index, source.track_get_interpolation_type(track))
		_insert(out, index, type, 0.0, _sample(source, track, type, from))
		# The root's travel, held at its opening value. See FRAMES' `in place`
		# column: the code owns the trajectory or the take does, never both.
		if in_place and type == Animation.TYPE_POSITION_3D and bone == root:
			continue
		for key in range(source.track_get_key_count(track)):
			var at := source.track_get_key_time(track, key)
			if at <= from + 0.0001 or at >= to - 0.0001:
				continue
			_insert(out, index, type, at - from, source.track_get_key_value(track, key))
		_insert(out, index, type, to - from, _sample(source, track, type, to))
	return out


## The take's root bone -- the leaf of the shortest track path in it, which is
## the one node with no parent above it inside the rig. Read from the data
## rather than written down, so a delivery that renames `CG` does not silently
## stop having its root motion flattened.
static func _root_of(source: Animation, bones: Dictionary) -> String:
	var shortest := ""
	for track in range(source.get_track_count()):
		var path := String(source.track_get_path(track))
		if not bones.has(_leaf(path)):
			continue
		if shortest == "" or path.length() < shortest.length():
			shortest = path
	return _leaf(shortest)


static func _leaf(path: String) -> String:
	var colon := path.find(":")
	var node_part := path if colon < 0 else path.substr(0, colon)
	var slash := node_part.rfind("/")
	return node_part if slash < 0 else node_part.substr(slash + 1)


static func _sample(source: Animation, track: int, type: int, at: float):
	match type:
		Animation.TYPE_POSITION_3D:
			return source.position_track_interpolate(track, at)
		Animation.TYPE_ROTATION_3D:
			return source.rotation_track_interpolate(track, at)
		_:
			return source.scale_track_interpolate(track, at)


static func _insert(out: Animation, track: int, type: int, at: float, value) -> void:
	match type:
		Animation.TYPE_POSITION_3D:
			out.position_track_insert_key(track, at, value)
		Animation.TYPE_ROTATION_3D:
			out.rotation_track_insert_key(track, at, value)
		_:
			out.scale_track_insert_key(track, at, value)


static func _last_key_time(animation: Animation) -> float:
	var last := 0.0
	for track in range(animation.get_track_count()):
		var count := animation.track_get_key_count(track)
		if count > 0:
			last = maxf(last, animation.track_get_key_time(track, count - 1))
	return last
