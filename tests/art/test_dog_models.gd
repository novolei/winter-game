extends TestCase

## The three dogs, held to the things the project-wide gates cannot see.
##
## Same reason `test_pigeon_model.gd` and `test_crow_model.gd` exist: the dogs
## live under `assets/models/characters/`, which is
## `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`, so the palette and shading gates
## deliberately look away from them. A gate told to skip something cannot also be
## the thing that proves the skip was right.
##
## What is NOT here is the size, which `tests/art/test_asset_scale.gd` and
## `data/scale/dog_*.tres` own for every model in the project. The dogs are the
## reason that gate exists: the pack shipped them at two different import scales
## and the wrong one does not error.
##
## ---------------------------------------------------------------------------
## THE ONE THIS FILE IS REALLY FOR: **DOES THE TAKE MOVE**
## ---------------------------------------------------------------------------
## `Docs/asset-inventory-low-poly-animals.md` section 1.5 played 217 takes out of
## this package and eight of them never left the bind pose, having imported
## without a single error. The crow's package was worse -- its animation files
## carried 121 nulls and no armature at all. **A take that arrives and gives no
## pose is worse than a missing one**, because the library names it and the
## census counts it.
##
## So `test_every_take_moves_a_bone` reads the shipped `Animation` resources and
## refuses any whose keys never change, and
## `test_every_animation_track_addresses_a_bone_that_exists` refuses any whose
## tracks point at nothing -- which is the crow's failure, and is invisible to the
## first check because an animation full of keys that drive no bone is still full
## of keys.
##
## Both work off the resources rather than by playing them, so nothing here
## allocates an AnimationPlayer or needs a tree. `tools/measure_dog_takes.gd` is
## the other half: it PLAYS every take through a real player and reports
## imported-versus-moving, which is the number the wave report quotes.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const DogScript := preload("res://src/entities/wildlife/dog.gd")
const DogAnimationsScript := preload("res://src/entities/wildlife/dog_animations.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Art Bible rule 6's creature tier. Not waived by the character exception box,
## which waives rules 8 and 9 and says in as many words that the budget stands.
const CREATURE_BUDGET := 8000

## Measured on the shipped `.glb` and cross-checked against the inventory's own
## FBX parse, which counted the same three numbers out of the package.
const TRIANGLES := {
	&"chihuahua": 872,
	&"golden_retriever": 928,
	&"great_dane": 988,
}

## The bone count each rig ships with, which is the pack's own plus the `Root_M`
## that `build_dog.py` puts back. The inventory measured 56 / 56 / 55 in the
## source; Blender folds several leaf tips into empties on the way through, and
## those carry no vertex weight on any of the three -- so what is asserted is what
## the `.glb` really holds rather than what the FBX did.
const BONES := {
	&"chihuahua": 49,
	&"golden_retriever": 51,
	&"great_dane": 55,
}

## A key that differs from the first by more than this is motion. A quaternion
## delta of 0.001 is about a twentieth of a degree; positions are in the
## skeleton's own units, which on this pack are a hundred times life size.
const ROTATION_EPSILON := 0.001
const POSITION_EPSILON := 0.05


func _import_text(breed: StringName) -> String:
	var path := DogAnimationsScript.model_path(breed) + ".import"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _rig(breed: StringName) -> Node3D:
	var packed := ResourceLoader.load(DogAnimationsScript.model_path(breed))
	if not (packed is PackedScene):
		return null
	return (packed as PackedScene).instantiate() as Node3D


## The transform from `root`'s parent space down to `leaf`, root's own included.
##
## Root's own is where a yaw would live, so a walk that stopped AT root would
## read identical numbers whichever way the model faced. Same instrument, and the
## same trap, as `test_pigeon_model.gd::_within`.
func _within(root: Node3D, leaf: Node3D) -> Transform3D:
	var placed := Transform3D()
	var walk: Node = leaf
	while walk != null:
		if walk is Node3D:
			placed = (walk as Node3D).transform * placed
		if walk == root:
			break
		walk = walk.get_parent()
	return placed


func _meshes(rig: Node3D) -> Array:
	var found: Array = []
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			found.append(instance)
	return found


func _skeleton(rig: Node3D) -> Skeleton3D:
	for node in rig.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


# --- the delivery ------------------------------------------------------------


func test_all_three_dogs_are_on_disk() -> void:
	var missing := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if not ResourceLoader.exists(DogAnimationsScript.model_path(breed)):
			missing.append(String(breed))
	assert_eq(missing.size(), 0, "not in the project: %s" % ", ".join(missing))


## Whole asset, which is the number rule 6 is about, and the exact count as well
## so a re-export that changed the mesh is a red run rather than a surprise.
func test_every_dog_is_inside_the_creature_budget() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			offenders.append("%s did not instantiate" % breed)
			continue
		var total := 0
		for instance in _meshes(rig):
			total += (instance as MeshInstance3D).mesh.get_faces().size() / 3
		rig.free()
		if total > CREATURE_BUDGET:
			offenders.append("%s ships %d triangles, over rule 6's %d" % [breed, total, CREATURE_BUDGET])
		elif total != int(TRIANGLES[breed]):
			offenders.append("%s now measures %d triangles rather than the %d recorded here" % [
				breed, total, int(TRIANGLES[breed])])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## ONE DOG PER FILE. Seventeen FBXs arrived, each carrying a full copy of the
## mesh; `build_dog.py` takes the mesh from one of them and nothing but the take
## from the rest. A merge that dragged a second skeleton through would show up
## here and nowhere else -- it is `build_scavenger.py`'s own hazard, where five
## Mixamo files hold five identical 47,000-triangle meshes.
func test_only_one_dog_ships_in_each_file() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		var meshes := _meshes(rig).size()
		var skeletons := rig.find_children("*", "Skeleton3D", true, false).size()
		rig.free()
		if meshes != 1:
			offenders.append("%d meshes came out of %s" % [meshes, breed])
		if skeletons != 1:
			offenders.append("%d skeletons came out of %s" % [skeletons, breed])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The root bone Blender loses, put back.
##
## The FBX hierarchy hangs the whole skeleton under a bone called `Root_M`, and
## Blender's importer turns exactly that bone into the ARMATURE OBJECT -- leaving
## the mesh's `Root_M` vertex group pointing at a bone that no longer exists.
## MEASURED: 23.29 of the chihuahua's 438 total skin weight, 14.49 of the golden
## retriever's 466 and 21.79 of the great dane's 496, across 48 to 64 vertices
## each. Nothing errors; the armature modifier renormalises and those vertices
## are driven by the wrong bones.
func test_every_rig_still_has_its_root_bone() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		var skeleton := _skeleton(rig)
		if skeleton == null:
			offenders.append("%s carries no Skeleton3D" % breed)
		else:
			if skeleton.find_bone("Root_M") < 0:
				offenders.append("%s has no Root_M bone; its `Root_M` vertex group drives nothing" % breed)
			if skeleton.get_bone_count() != int(BONES[breed]):
				offenders.append("%s has %d bones rather than the %d recorded here" % [
					breed, skeleton.get_bone_count(), int(BONES[breed])])
		rig.free()
	assert_eq(offenders.size(), 0, "; ".join(offenders))


# --- the takes ----------------------------------------------------------------


func _takes(breed: StringName) -> Dictionary:
	return DogAnimationsScript.source_takes(breed)


func test_every_breed_ships_the_takes_the_library_names() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var shipped := _takes(breed)
		for row in DogAnimationsScript.TAKES:
			if StringName(row[0]) != breed:
				continue
			if not shipped.has(String(row[1])):
				offenders.append("%s has no take called %s; it has %s" % [
					breed, row[1], str(shipped.keys())])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## No take the library does not name, either. A `.glb` that grew an extra take
## would otherwise sit there un-named and un-played, which is how the pack's junk
## `Take 001` gets counted as a real animation.
func test_no_breed_ships_a_take_the_library_does_not_name() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		for name in _takes(breed).keys():
			if not DogAnimationsScript.has_own(breed, StringName(name)):
				offenders.append("%s ships an unnamed take %s" % [breed, name])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## THE ONE. Every take must change a bone, or it is a name over an empty box.
func test_every_take_moves_a_bone() -> void:
	var offenders := PackedStringArray()
	var moving := 0
	var total := 0
	for breed in DogAnimationsScript.BREEDS:
		for name in _takes(breed).keys():
			total += 1
			var animation: Animation = _takes(breed)[name]
			if _largest_change(animation) <= 0.0:
				offenders.append("%s/%s never leaves its first key" % [breed, name])
			else:
				moving += 1
	assert_true(total > 0, "no takes were read at all, so this gate measured nothing")
	assert_eq(offenders.size(), 0, "%d of %d takes move. %s" % [moving, total, "; ".join(offenders)])


## How far the largest-moving key of any track gets from that track's first key,
## as a fraction of the epsilon for its type. Zero when nothing anywhere moves.
##
## Read through `track_get_key_value`, which is generic over the track type.
## There is no `Animation.position_track_get_key` -- the typed accessors are
## `*_track_interpolate`, which sample the CURVE, and a curve sampled at a point
## between two identical keys reports the same value as a curve with one key.
## Reading the keys themselves is what distinguishes a still take from a still
## moment in a moving one.
func _largest_change(animation: Animation) -> float:
	var worst := 0.0
	for track in range(animation.get_track_count()):
		var kind := animation.track_get_type(track)
		var keys := animation.track_get_key_count(track)
		if keys < 2:
			continue
		if kind == Animation.TYPE_ROTATION_3D:
			var first: Quaternion = animation.track_get_key_value(track, 0)
			for key in range(1, keys):
				var value: Quaternion = animation.track_get_key_value(track, key)
				worst = maxf(worst, first.angle_to(value) / ROTATION_EPSILON)
		elif kind == Animation.TYPE_POSITION_3D:
			var origin: Vector3 = animation.track_get_key_value(track, 0)
			for key in range(1, keys):
				var value: Vector3 = animation.track_get_key_value(track, key)
				worst = maxf(worst, (value - origin).length() / POSITION_EPSILON)
	return worst if worst > 1.0 else 0.0


## AND THE TRACKS HAVE TO REACH A BONE.
##
## This is the crow's failure, and it is invisible to the check above: an
## animation whose tracks address nodes the model does not have is still full of
## keys that change. It plays, it reports a length, and the mesh stands in its
## bind pose with the console clean.
func test_every_animation_track_addresses_a_bone_that_exists() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		var skeleton := _skeleton(rig)
		if skeleton == null:
			rig.free()
			continue
		var bones := {}
		for index in range(skeleton.get_bone_count()):
			bones[skeleton.get_bone_name(index)] = true
		for name in _takes(breed).keys():
			var animation: Animation = _takes(breed)[name]
			for track in range(animation.get_track_count()):
				var path := String(animation.track_get_path(track))
				var colon := path.find(":")
				if colon < 0:
					continue
				var bone := path.substr(colon + 1)
				if not bones.has(bone):
					offenders.append("%s/%s drives %s, which is not a bone in the rig" % [breed, name, bone])
		rig.free()
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The lengths the library says they are. A re-import that changed
## `animation/fps` or `animation/trimming` reshapes every take silently, and the
## symptom is a dog that moves at the wrong speed rather than an error.
func test_every_take_is_the_length_the_library_records() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var shipped := _takes(breed)
		for row in DogAnimationsScript.TAKES:
			if StringName(row[0]) != breed or not shipped.has(String(row[1])):
				continue
			var length: float = (shipped[String(row[1])] as Animation).length
			if absf(length - float(row[2])) > 0.02:
				offenders.append("%s/%s imports at %.3f s, the library says %.3f" % [
					breed, row[1], length, float(row[2])])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


# --- which way the dogs point -------------------------------------------------
#
# THE DEFECT THIS EXISTS FOR. These came out of a Unity package; Unity is
# left-handed and its models face +Z, Godot is right-handed and `look_at()` aims
# -Z. The crow shipped a whole wave flying tail-first for exactly this, and the
# owner caught it rather than the suite.
#
# NO CONSTANT IS CONSULTED. `Bird` carries `species.model_yaw` because its models
# are third-party files this project cannot rewrite; the dogs go through a
# Blender build this project owns, so the turn is baked into the `.glb` and what
# is measured here is the shipped asset. A gate that read a constant could only
# tell you the constant had not changed.
#
# Two instruments, bones and geometry, because they are the two halves of the
# delivery and a rig turned round while its mesh was not must not pass.


func test_every_dog_is_built_facing_the_way_look_at_points_it() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		var skeleton := _skeleton(rig)
		if skeleton == null:
			rig.free()
			continue
		var into := _within(rig, skeleton)
		var head := skeleton.find_bone("Head_M")
		var tail := skeleton.find_bone("Tail0_M")
		if head < 0 or tail < 0:
			offenders.append("%s has no Head_M / Tail0_M to measure against" % breed)
			rig.free()
			continue
		var head_at: Vector3 = (into * skeleton.get_bone_global_rest(head)).origin
		var tail_at: Vector3 = (into * skeleton.get_bone_global_rest(tail)).origin
		rig.free()
		if head_at.z >= tail_at.z:
			offenders.append(("%s is built tail-first: skull z = %+.4f, tail root z = %+.4f in the "
				+ "model's own space. look_at() aims -Z, so a companion asked to follow would walk "
				+ "backwards") % [breed, head_at.z, tail_at.z])
			continue
		# Along the axis, not merely on the right side of zero. A rig whose head
		# was a millimetre forward of its tail would pass a sign test and still
		# read as an animal moving sideways.
		var axis := head_at - tail_at
		if -axis.z <= absf(axis.x):
			offenders.append("%s's body axis is %s -- more across the rig than along it" % [
				breed, str(axis.snappedf(0.001))])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The same question of the GEOMETRY, with no bone consulted.
##
## The test asks a question about the ANIMAL rather than about the file: the
## highest tenth of a standing dog is its skull, and a skull is in front of the
## body it sits on. `test_crow_model.gd` decides which end is the beak by asking
## which reaches further from the origin, and that reasoning is false here for
## the same reason it was false for the pigeon -- these origins sit between the
## feet, not at the tail.
func test_every_dogs_geometry_points_the_same_way_its_skeleton_does() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		var points := PackedVector3Array()
		for instance in _meshes(rig):
			var placed := _within(rig, instance as MeshInstance3D)
			var mesh: Mesh = (instance as MeshInstance3D).mesh
			for surface in range(mesh.get_surface_count()):
				# Trap 5: an unused slot comes back null, and assigning null into
				# a typed PackedVector3Array aborts the caller rather than erroring.
				var raw = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				if raw == null:
					continue
				for vertex in (raw as PackedVector3Array):
					points.append(placed * vertex)
		rig.free()
		if points.is_empty():
			offenders.append("no vertices were read out of %s" % breed)
			continue
		var highest := -1e9
		var lowest := 1e9
		for point in points:
			highest = maxf(highest, point.y)
			lowest = minf(lowest, point.y)
		var head_line := lowest + (highest - lowest) * 0.9
		var skull_z := 0.0
		var skull_count := 0
		var body_z := 0.0
		for point in points:
			body_z += point.z
			if point.y >= head_line:
				skull_z += point.z
				skull_count += 1
		if skull_count == 0:
			offenders.append("no vertices fell in the top tenth of %s" % breed)
			continue
		skull_z /= float(skull_count)
		body_z /= float(points.size())
		if skull_z >= body_z:
			offenders.append(("%s's skull sits at z = %+.4f and its body at z = %+.4f: the head is "
				+ "BEHIND the body, which is Unity's +Z forward left uncorrected") % [
				breed, skull_z, body_z])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


# --- the exemption, asserted in both directions -------------------------------


func test_the_dogs_are_covered_by_the_character_exemption_on_purpose() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if not AssetScannerScript.is_surface_rule_exempt(DogAnimationsScript.model_path(breed)):
			offenders.append("%s is outside SURFACE_RULE_EXEMPT_ROOTS" % breed)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
	# The negative control. Without it this passes just as happily against an
	# exemption widened to the whole project.
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/props/power_pole.glb"),
		"a prop must not be exempt from the surface rules"
	)


# --- the import settings that are part of the asset ---------------------------


func test_the_dogs_are_not_wired_to_the_palette_import_script() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if _import_text(breed).contains("import_script/path=\"res://tools/palette_import_materials.gd\""):
			offenders.append("%s is exempt and must not carry the palette import script" % breed)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


func test_auto_lod_is_off_on_every_dog() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if not _import_text(breed).contains("meshes/generate_lods=false"):
			offenders.append("%s: the importer will decimate a 900-triangle animal whose whole "
				% breed + "value is its outline")
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Default true drops any bone whose value never leaves its rest. Playing `run`
## and then `lie` would then leave every bone `lie` does not touch exactly where
## the run left it -- a dog lying in the snow with its legs mid-stride. It errors
## nothing and it is invisible until two takes are played in a row.
func test_immutable_tracks_are_kept_on_every_dog() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if not _import_text(breed).contains("animation/remove_immutable_tracks=false"):
			offenders.append("%s drops immutable tracks, so switching takes leaves untouched bones "
				% breed + "wherever the previous take left them")
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The pack authored every dog at 24 fps. Two animals in this package are not --
## reindeer at 30 and pig at 60 -- and computing a length at the wrong rate is off
## by 25% or 150% with nothing to report it.
func test_the_import_is_set_to_the_rate_the_pack_authored() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		if not _import_text(breed).contains("animation/fps=%d" % int(DogAnimationsScript.SOURCE_FPS)):
			offenders.append("%s's import rate does not match DogAnimations.SOURCE_FPS" % breed)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The pack's 1024 colour map is dropped at BUILD time, not extracted at import.
## See `Dog`'s header for what that cost.
##
## The assertion is on MAPS, not on materials, and the first version got that
## wrong. `export_materials="NONE"` writes a `.glb` with no material at all and
## Godot's glTF importer then invents a plain `StandardMaterial3D` per surface --
## so "no material" is not a state this pipeline can produce, and a gate asking
## for it fails on a file that is exactly right. `Dog._paint()` overrides those
## defaults with the cel material anyway; what must never arrive is a texture,
## because a texture is a surface no gate in this project judges.
const MAP_PROPERTIES := [
	"albedo_texture", "normal_texture", "roughness_texture", "metallic_texture",
	"emission_texture", "ao_texture",
]


func test_no_dog_ships_a_texture() -> void:
	var offenders := PackedStringArray()
	for breed in DogAnimationsScript.BREEDS:
		var rig := _rig(breed)
		if rig == null:
			continue
		for instance in _meshes(rig):
			var mesh: Mesh = (instance as MeshInstance3D).mesh
			for surface in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface)
				if material == null:
					continue
				for property in MAP_PROPERTIES:
					if material.get(property) != null:
						offenders.append("%s surface %d carries a %s" % [breed, surface, property])
		rig.free()
	var folder := DirAccess.open(DogAnimationsScript.MODEL_ROOT)
	if folder != null:
		for entry in folder.get_files():
			if entry.ends_with(".png") or entry.ends_with(".jpg"):
				offenders.append("%s is on disk beside the models" % entry)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


# --- the colour ---------------------------------------------------------------


func test_the_dog_is_painted_from_the_palette() -> void:
	var bible: Resource = load(PALETTE_PATH)
	assert_not_null(bible, "the palette is missing, so nothing can be resolved from it")
	if bible == null:
		return
	var dog: Dog = DogScript.new()
	var tone: Color = dog.palette_tone()
	dog.free()
	assert_true(bible.contains(tone), "the dog's colour %s is not in the 12-colour table" % tone.to_html(false))
	assert_true(
		bible.structure_tones.has(tone),
		"the dog is painted %s, which is not a structure tone" % tone.to_html(false)
	)


## Art Bible rule 12. Warm is reserved for windows, fire, beacons, the truck and
## the scarf, and it does not list animals.
func test_no_part_of_the_dog_is_warm() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return
	var dog: Dog = DogScript.new()
	var tone: Color = dog.palette_tone()
	dog.free()
	assert_false(bible.warm_tones.has(tone), "the dog is painted a warm tone")


## Not the farmhouse's own siding, and not the crow's near-black. A dog found in
## the snow beside the buildings has to have a silhouette against both.
func test_the_dog_is_not_the_colour_of_the_wall_or_of_the_crow() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return
	var dog: Dog = DogScript.new()
	var tone: Color = dog.palette_tone()
	dog.free()
	assert_true(
		tone != bible.structure_tones[0],
		"the dog is painted the siding's own tone, so a dog against the farmhouse disappears into it"
	)
	assert_true(
		tone != bible.structure_tones[bible.structure_tones.size() - 1],
		"the dog is painted the crow's near-black"
	)


## A living animal carries no settled snow -- and the refusal has to go through
## the painter's own cache key rather than being written onto the material
## afterwards. `CelPainter` caches one material per colour, so the moment anybody
## hands the dog the world's painter through the public `set_painter()`, a write
## would reach everything else painted the same colour and no gate could see it.
func test_the_dog_refuses_snow_through_the_painters_key_and_not_by_writing_on_it() -> void:
	var painter := CelPainter.new()
	var dog: Dog = DogScript.new()
	var tone: Color = dog.palette_tone()
	var a_wall := painter.material_for(tone)
	dog.set_painter(painter)
	var worn := dog.material()
	assert_not_null(worn, "the dog resolved no material at all")
	assert_true(worn != a_wall, "the dog and the world are sharing one material, so one decides for both")
	assert_almost_eq(
		float(worn.get_shader_parameter("snow_receptivity")), 0.0, 0.0001,
		"snow settles on the dog, and by day six the companion is white"
	)
	assert_true(
		float(a_wall.get_shader_parameter("snow_receptivity")) > 0.0,
		"painting the dog turned the snow off for everything that shares its colour"
	)
	dog.free()
