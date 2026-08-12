class_name BirdAnimations
extends RefCounted

## Builds one bird's AnimationLibrary out of its species' take table.
##
## ---------------------------------------------------------------------------
## ONE BUILDER FOR TWO DELIVERY SHAPES
## ---------------------------------------------------------------------------
## This replaces `crow_animations.gd` and `pigeon_animations.gd`, which were the
## same job done twice because the two packs lay their clips out in opposite
## ways. `BirdTake`'s header has the two shapes in full; the short version:
##
##   FRAME RANGES  the raven pack. One long take per file, clips named only in a
##                 Unity `.meta`. `slice()` cuts them out, samples both ends,
##                 rebuilds every track against the model's own skeleton, and
##                 flattens the root travel of anything the code drives.
##   NAMED STACKS  the animal pack. Each clip is its own `AnimationStack`, so the
##                 importer produces them already separated and already named.
##                 `build()` duplicates and sets the loop flag; nothing is cut.
##
## Which path a row takes is read off the row (`BirdTake.is_sliced()`). A third
## bird from either pack -- or from a pack nobody has opened yet, as long as it
## is one of these two shapes -- is a `.tres` and no code at all.
##
## ---------------------------------------------------------------------------
## WHY THE SLICER REBUILDS TRACK PATHS AND THE RENAMER MUST NOT
## ---------------------------------------------------------------------------
## The raven's animation files carry **no armature**: 3ds Max exported the rig
## as a hierarchy of nulls, so Godot's ufbx importer reads them as node tracks
## (`CG/Pelvis/Spine`) addressed to nodes the model file does not have. Every
## track has to be readdressed to `<skeleton_path>:<bone>` and any track naming
## something that is not a bone dropped -- a track for a bone the skeleton lacks
## animates nothing while looking exactly like a track that works.
##
## The dove's takes come out of the same FBX as its mesh and already address
## `Group/Main/DeformationSystem/Skeleton3D:<bone>`, which is exactly where the
## skeleton is, and the library is hung on that file's own AnimationPlayer.
## Rewriting those would break the one thing that already works. So the rewrite
## is part of slicing, not part of building.
##
## ---------------------------------------------------------------------------
## NOTHING HERE ALLOCATES A NODE
## ---------------------------------------------------------------------------
## The animations and the bone names are both lifted out of `PackedScene`
## SceneStates rather than out of instantiated trees, so a test may call `build()`
## freely without leaking an ObjectDB instance (briefing constraint 2).
##
## Everything is deep-duplicated before it is touched, because `ResourceLoader`
## hands every caller the SAME instance (briefing trap 6): setting `length` or
## `loop_mode` on what comes back would edit the imported asset for everything
## that ever loads it, including the next call to this function.


## One library holding every take in `species.takes`, under the names the game
## asks for.
static func build(species: BirdSpecies) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	if species == null:
		return library
	var bones := bone_names(species.model_path)
	var longs: Dictionary = {}
	var nameds: Dictionary = {}
	for take in species.takes:
		if take == null or take.take_name == &"":
			continue
		var path := take.file(species.model_path)
		if take.is_sliced():
			if not longs.has(path):
				longs[path] = long_take(path)
			var source: Animation = longs[path]
			if source == null:
				push_warning("bird_animations: %s holds no animation" % path)
				continue
			library.add_animation(take.take_name, slice(
				source, take.first_frame, take.last_frame,
				take.loops, take.in_place, bones, species.source_fps, species.skeleton_path
			))
			continue
		if not nameds.has(path):
			nameds[path] = animations_in(path)
		var available: Dictionary = nameds[path]
		var matched := matching_name(available, take.source_name)
		if matched == "":
			push_warning("bird_animations: %s holds no take called '%s'" % [path, take.source_name])
			continue
		if matched != take.source_name:
			# See `BirdTake.source_name`: the dove pack's exporter wrote
			# `Dove_Run to Idle ` with a trailing space, and a lookup without it
			# drops the take in silence. A warning is the whole point -- this is
			# the one path where being helpful must still be loud.
			push_warning("bird_animations: '%s' matched '%s' only after trimming whitespace" % [
				take.source_name, matched])
		var copy: Animation = (available[matched] as Animation).duplicate(true)
		copy.loop_mode = Animation.LOOP_LINEAR if take.loops else Animation.LOOP_NONE
		library.add_animation(take.take_name, copy)
	return library


## The name in `available` that `wanted` means, or "" for none.
##
## Exact first, always. The fallback compares with leading and trailing
## whitespace stripped from both sides, which is the whole of the defect it
## exists for: `Dove_Run to Idle ` ships with a trailing space, and one take of
## thirteen went missing on the pigeon's first run because a lookup did not
## carry it. Pure and public so the rule can be exercised against a fixture
## rather than against a warning nobody may print during a test run.
static func matching_name(available: Dictionary, wanted: String) -> String:
	if wanted == "":
		return ""
	if available.has(wanted):
		return wanted
	var trimmed := wanted.strip_edges()
	for name in available.keys():
		if String(name).strip_edges() == trimmed:
			return String(name)
	return ""


## The single long take inside one imported animation file, with its length
## corrected to what its keys actually span.
##
## THE LENGTH CORRECTION IS NOT TIDINESS. Measured on 4.7.1: `crow_perch.fbx`
## imports with `length = 3.3333` while its tracks carry keys out to frame 182,
## which is 6.07 s. `slice()` samples the source with `*_track_interpolate()`,
## and those clamp to `length` -- so without this the perch take would be cut out
## of a range the sampler refuses to read and the slice would come back as one
## held pose.
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
	if path == "" or not ResourceLoader.exists(path):
		return found
	var resource := ResourceLoader.load(path)
	if not (resource is PackedScene):
		push_warning("bird_animations: %s did not load as a PackedScene" % path)
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
## Skeleton3D serialises its bones as `bones/<n>/name`, which is readable off the
## SceneState without instancing anything.
static func bone_names(path: String) -> Dictionary:
	var names: Dictionary = {}
	if path == "" or not ResourceLoader.exists(path):
		return names
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
## Boundary keys are SAMPLED rather than snapped to the nearest authored key, so
## a range whose ends fall between keys still starts and finishes on the pose the
## table names. Both packs key on every frame, so in practice they land on
## existing keys and the sample returns them unchanged -- which is the point: it
## costs nothing when the data is dense and is correct when it is not.
static func slice(
	source: Animation,
	first_frame: int,
	last_frame: int,
	loops: bool,
	in_place: bool,
	bones: Dictionary,
	fps := 30.0,
	skeleton := "Skeleton3D"
) -> Animation:
	var rate := fps if fps > 0.0 else 30.0
	var from := float(first_frame) / rate
	var to := float(last_frame) / rate
	var root := _root_of(source, bones)
	var out := Animation.new()
	out.length = maxf(to - from, 1.0 / rate)
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
		out.track_set_path(index, NodePath("%s:%s" % [skeleton, bone]))
		out.track_set_interpolation_type(index, source.track_get_interpolation_type(track))
		_insert(out, index, type, 0.0, _sample(source, track, type, from))
		# The root's travel, held at its opening value. See `BirdTake.in_place`:
		# the code owns the trajectory or the take does, never both.
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
