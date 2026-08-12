extends TestCase

## The crow delivery, held to the things the project-wide gates cannot see.
##
## ---------------------------------------------------------------------------
## WHY A FILE OF ITS OWN
## ---------------------------------------------------------------------------
## Same reason `test_threat_models.gd` exists, and the reasoning is worth
## repeating because it is the whole shape of this project's art gating: the
## crow lives under `assets/models/characters/`, which is
## `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`, so `test_palette.gd`,
## `test_shading_features.gd` and half of `test_import_wiring.gd` deliberately
## look away from it. **A gate that has been told to skip something cannot also
## be the thing that proves the skip was right.**
##
## The Art Bible's own warning, on the character exemption:
##
##     美术门禁必须显式豁免 assets/models/characters/，而不是靠碰巧扫不到它而放行。
##     因错误原因保持沉默的门禁，比会报错的门禁更糟。
##
## So: the exemption is asserted by name, the budget the exemption does NOT waive
## is measured whole-asset, the colour the exemption lets the crow choose for
## itself is checked against the palette, and the three import settings that are
## part of the asset rather than preferences are checked against the `.import`
## files.
##
## ---------------------------------------------------------------------------
## WHY A CREATURE IS FILED WITH THE CHARACTERS
## ---------------------------------------------------------------------------
## Because the bear already is. Art Bible rule 6's creature tier is ~8,000
## triangles and its exception box names 主角 · 饿汉 · 熊 -- a bear is an animal,
## and `assets/models/characters/` is where this project has put rigged living
## things since Wave 1. A crow is 5,186 triangles: over the prop tier by a factor
## of twenty-five and over the tree tier by nine, and no amount of decimation
## makes a skinned bird into a 200-triangle prop.
##
## What the exemption is NOT used for here is the surfaces. The crow does not
## keep the pack's own materials -- Unity's Poly Art shader is sixteen colour
## slots selected by a mask texture, none of which survives an FBX import
## anyway -- it is painted at runtime from `color_bible.tres`, flat, on the same
## two-band cel shader as the trees. See `src/entities/wildlife/crow.gd`.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const CrowScript := preload("res://src/entities/wildlife/crow.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"

const CROW := "res://assets/models/characters/crow/crow.fbx"
const TAKE_FILES := [
	"res://assets/models/characters/crow/crow_perch.fbx",
	"res://assets/models/characters/crow/crow_turn.fbx",
	"res://assets/models/characters/crow/crow_fly.fbx",
	"res://assets/models/characters/crow/crow_takeoff.fbx",
]

## Art Bible rule 6's creature tier. Not waived by the exception box, which
## waives rules 8 and 9 and says in as many words that the budget still applies.
const CREATURE_BUDGET := 8000

## Measured on the shipped import. The pack delivers 2,760 quads, which is 5,186
## triangles, and it delivers them SIX TIMES OVER: the model file carries five
## alternate head and beak variants, each a complete 5,186-triangle bird. All
## five are skipped at import (see `_subresources` in crow.fbx.import), which is
## the only reduction this asset needed and is a 26,000-triangle one.
const CROW_TRIANGLES := 5186


func _import_text(path: String) -> String:
	var import_path := path + ".import"
	if not FileAccess.file_exists(import_path):
		return ""
	return FileAccess.get_file_as_string(import_path)


func _meshes(path: String) -> Array:
	var found: Array = []
	var packed := ResourceLoader.load(path)
	if not (packed is PackedScene):
		return found
	var scene := (packed as PackedScene).instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			found.append(instance.mesh)
	scene.free()
	return found


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		# Trap 5: an unused slot comes back null, and assigning null into a typed
		# PackedInt32Array aborts the caller rather than erroring visibly.
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


# --- the asset ----------------------------------------------------------------


func test_the_delivery_is_on_disk() -> void:
	assert_true(ResourceLoader.exists(CROW), "%s is not in the project" % CROW)
	for path in TAKE_FILES:
		assert_true(ResourceLoader.exists(path), "%s is not in the project" % path)


## Whole-asset, which is the number rule 6 is about and the number no per-mesh
## gate can produce.
func test_the_crow_is_inside_the_creature_budget() -> void:
	var meshes := _meshes(CROW)
	var total := 0
	for mesh in meshes:
		total += _triangles(mesh)
	assert_true(
		total <= CREATURE_BUDGET,
		"the crow ships %d triangles, over rule 6's %d" % [total, CREATURE_BUDGET]
	)
	assert_eq(
		total, CROW_TRIANGLES,
		"the crow now measures %d triangles rather than the %d recorded here -- the import changed under this gate" % [
			total, CROW_TRIANGLES]
	)


## The pack ships the bird six times over, once per head and beak variant. If the
## skip ever came out of the `.import`, the count above would still be per-mesh
## inside budget and thirty-one thousand triangles would ship.
func test_only_one_bird_ships_out_of_the_six_in_the_file() -> void:
	assert_eq(
		_meshes(CROW).size(), 1,
		"%d meshes came out of crow.fbx -- the five alternate heads and beaks are no longer being skipped at import" % _meshes(CROW).size()
	)


func test_the_animation_files_carry_no_geometry() -> void:
	for path in TAKE_FILES:
		assert_eq(_meshes(path).size(), 0, "%s brought a mesh in with it" % path)


# --- the exemption, asserted in both directions --------------------------------


func test_the_crow_is_covered_by_the_character_exemption_on_purpose() -> void:
	assert_true(
		AssetScannerScript.is_surface_rule_exempt(CROW),
		"%s is outside SURFACE_RULE_EXEMPT_ROOTS, so the palette and shading gates now judge a model that resolves its colour at runtime" % CROW
	)


## The other half of `test_import_wiring.gd`'s contract. Wiring the palette
## import script into an exempt model would repaint it from the 12-colour table
## and every other gate would go green over the result.
func test_the_crow_is_not_wired_to_the_palette_import_script() -> void:
	for path in [CROW] + TAKE_FILES:
		assert_false(
			_import_text(path).contains("import_script/path=\"res://tools/palette_import_materials.gd\""),
			"%s is exempt and must not carry the palette import script" % path
		)


func test_auto_lod_is_off_on_every_crow_file() -> void:
	for path in [CROW] + TAKE_FILES:
		assert_true(
			_import_text(path).contains("meshes/generate_lods=false"),
			"%s will be decimated by the importer, and at a bird's size the only thing an LOD can take away is the silhouette" % path
		)


# --- the three import settings that are part of the asset ----------------------


## Godot trims leading and trailing stillness by default. `Raven Sleep.FBX` has
## a still stretch in it, and with trimming on the file imports 100 frames long
## instead of 183 -- which slides every frame number in `CrowAnimations.FRAMES`
## by an amount nothing records, and the perch take comes out of the wrong part
## of the file.
func test_no_animation_file_is_trimmed_on_import() -> void:
	for path in TAKE_FILES:
		assert_true(
			_import_text(path).contains("animation/trimming=false"),
			"%s is imported with trimming on, which slides the frame numbers CrowAnimations.FRAMES is written in" % path
		)


## Default true drops any bone whose value never leaves its rest. Playing the
## glide and then the perch would then leave every bone the perch does not touch
## exactly where the glide left it -- a crow sitting on a wire with its wings out.
func test_no_animation_file_drops_its_immutable_tracks() -> void:
	for path in TAKE_FILES:
		assert_true(
			_import_text(path).contains("animation/remove_immutable_tracks=false"),
			"%s drops immutable tracks, so switching takes leaves untouched bones wherever the previous take left them" % path
		)


# --- the colour ---------------------------------------------------------------


## The exemption lets the crow choose its own colour. This is that choice being
## checked rather than described.
func test_the_crow_is_painted_from_the_palette() -> void:
	var bible: Resource = load(PALETTE_PATH)
	assert_not_null(bible, "the palette is missing, so nothing can be resolved from it")
	if bible == null:
		return
	var tone: Color = CrowScript.palette_tone()
	assert_true(bible.contains(tone), "the crow's colour %s is not in the 12-colour table" % tone.to_html(false))
	assert_true(
		bible.structure_tones.has(tone),
		"the crow is painted %s, which is not a structure tone -- rule 7's near-black is what a silhouette against snow is made of" % tone.to_html(false)
	)


## A living bird does not carry a week of settled snow, and the crow is the
## palette's darkest structure tone -- which is also the trees, the wires and the
## roof planes.
##
## THE MECHANISM MATTERS AND THAT IS THE WHOLE OF THIS TEST. Written first as
## `material_for(tone)` followed by `set_shader_parameter("snow_receptivity", 0)`,
## which was safe only because the bird kept a private painter. `CelPainter`
## caches one material per colour, so the moment anybody passes the world's
## painter through `Crow.set_painter()` -- public, and exactly what a scene that
## wanted one material for the whole valley would do -- that write reaches every
## tree sharing the colour, and no gate in this project could see it. The roof
## work's `bare` argument is part of the cache key and cannot: the trees and the
## crow become two materials.
func test_the_crow_refuses_snow_through_the_painters_key_and_not_by_writing_on_it() -> void:
	var painter := CelPainter.new()
	var tone: Color = CrowScript.palette_tone()
	# What a tree painted the same colour already holds.
	var a_tree := painter.material_for(tone)
	var crow: Crow = CrowScript.new()
	crow.set_painter(painter)
	var worn := crow.material()
	assert_not_null(worn, "the crow resolved no material at all")
	assert_true(worn != a_tree, "the crow and the trees are sharing one material, so one of them decides for both")
	assert_almost_eq(
		float(worn.get_shader_parameter("snow_receptivity")), 0.0, 0.0001,
		"snow settles on the crow, and by day six the flock is white"
	)
	assert_true(
		float(a_tree.get_shader_parameter("snow_receptivity")) > 0.0,
		"painting the crow turned the snow off for every tree that shares its colour"
	)
	crow.free()


# --- which way the bird points ------------------------------------------------
#
# THE GATE THAT WAS MISSING, AND THE DEFECT IT WOULD HAVE CAUGHT.
#
# This crow arrived in a Unity `.unitypackage`. Unity is left-handed and its
# models face +Z; Godot is right-handed and `look_at()` aims a node's -Z. A model
# authored for Unity therefore points exactly backwards in Godot, and every
# consumer that aims it from a velocity puts its tail where its beak should be.
#
# Wave 2 shipped `MODEL_YAW = 0.0` on a reading of the pose that came out with
# the sign inverted, and rationalised the take's own +Z root travel away as "the
# importer gives the Skeleton3D a half-turn of its own". Measured on 4.7.1: the
# Skeleton3D sits at IDENTITY inside the Crow node -- no half-turn exists -- and
# every instrument says +Z:
#
#   bind pose      BeakTop z = +0.1722, Tail Center z = -0.1389
#   mesh vertices  the whole bird occupies z = -0.0035 .. +0.2902; the beak tip
#                  is the furthest +Z vertex at z = +0.2794
#   every take     (beak - tail).z is positive at every sample of perch, flap,
#                  take_off, fly and glide
#   root motion    Rav_TakeOff's CG climbs +0.30 m and travels +0.37 m ALONG +Z
#
# The facing axis and the take's own travel AGREE with each other. They agree on
# Unity's forward. So this is the asset's orientation, not a consumer aiming it
# wrongly, and the correction belongs once at the rig rather than at each use
# site -- which is what `Crow.MODEL_YAW` is and always was for.
#
# Two instruments here rather than one, deliberately: bones and mesh are the two
# halves of the delivery and a gate that read only one could be satisfied by an
# asset whose skeleton was fixed and whose geometry was not.


## Composes the transform from the model's own root down to its Skeleton3D by
## hand. Out of a tree there is nobody to compose it for you and
## `global_transform` silently answers with the identity -- the same trap
## `PerchPoints.placement()` and `Crow._where()` are written around.
func _skeleton_within(root: Node3D):
	var found: Skeleton3D = null
	for node in root.find_children("*", "Skeleton3D", true, false):
		found = node as Skeleton3D
		break
	if found == null:
		return null
	return {"skeleton": found, "at": _within(root, found)}


## The transform from `root`'s parent space down to `leaf`, INCLUDING root's own.
##
## Written first as a walk that stopped AT root and therefore left root's own
## transform out -- which is precisely where MODEL_YAW lives, so the gate read
## the same numbers before and after the fix and reported the fix had not worked.
## An instrument that ignores the one transform under test is worse than no
## instrument: it fails identically whatever you do.
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


## The rig as `Crow._build_rig()` actually assembles it: the model instanced and
## then yawed by MODEL_YAW. Everything below measures through this, so the gate
## is testing the shipped constant and not a hand-written duplicate of it.
func _posed_rig() -> Node3D:
	var packed := ResourceLoader.load(CROW)
	if not (packed is PackedScene):
		return null
	var rig := (packed as PackedScene).instantiate() as Node3D
	if rig == null:
		return null
	if absf(CrowScript.MODEL_YAW) > 0.0001:
		rig.rotate_y(CrowScript.MODEL_YAW)
	return rig


## The bind pose, with no take applied. The asset's own orientation, and the
## reading that decides where the fix belongs.
func test_the_bird_is_built_facing_the_way_look_at_points_it() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the crow model did not instantiate")
	if rig == null:
		return
	var held = _skeleton_within(rig)
	assert_not_null(held, "the crow model carries no Skeleton3D")
	if held == null:
		rig.free()
		return
	var skeleton: Skeleton3D = held["skeleton"]
	var into: Transform3D = held["at"]
	var beak := skeleton.find_bone("BeakTop")
	var tail := skeleton.find_bone("Tail Center")
	assert_true(beak >= 0 and tail >= 0, "the rig has no BeakTop / Tail Center to measure against")
	if beak < 0 or tail < 0:
		rig.free()
		return
	var beak_at: Vector3 = (into * skeleton.get_bone_global_rest(beak)).origin
	var tail_at: Vector3 = (into * skeleton.get_bone_global_rest(tail)).origin
	assert_true(
		beak_at.z < tail_at.z,
		("the crow is built tail-first: beak z = %+.4f, tail z = %+.4f in the rig's own space. "
			+ "look_at() aims -Z, so every departure flies backwards and every perched bird "
			+ "faces the wrong way along its wire. MODEL_YAW is %.4f rad.") % [
			beak_at.z, tail_at.z, CrowScript.MODEL_YAW]
	)
	# Not merely on the correct side of zero -- along the axis. A rig whose beak
	# was a millimetre forward of its tail would pass a sign test and still read
	# as a bird flying sideways.
	var axis := (beak_at - tail_at)
	assert_true(
		-axis.z > absf(axis.x),
		"the crow's body axis is %s -- more across the rig than along it" % str(axis.snappedf(0.001))
	)
	rig.free()


## The same question asked of the GEOMETRY, with no bone consulted. The beak is
## the furthest point along the bird's own length, so the extreme vertex on the
## forward axis has to be at -Z once the rig is yawed.
func test_the_birds_geometry_points_the_same_way_its_skeleton_does() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the crow model did not instantiate")
	if rig == null:
		return
	var most_forward := 1e9
	var most_back := -1e9
	var seen := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var placed := _within(rig, instance)
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			# Trap 5: an unused slot comes back null.
			var raw = arrays[Mesh.ARRAY_VERTEX]
			if raw == null:
				continue
			for vertex in (raw as PackedVector3Array):
				var at: Vector3 = placed * vertex
				most_forward = minf(most_forward, at.z)
				most_back = maxf(most_back, at.z)
				seen += 1
	assert_true(seen > 0, "no vertices were read out of the crow mesh")
	if seen == 0:
		rig.free()
		return
	assert_true(
		absf(most_forward) > absf(most_back),
		("the crow's geometry reaches %+.4f forward and %+.4f back: the long end of the bird "
			+ "is behind the origin, which is Unity's +Z forward left uncorrected") % [
			most_forward, most_back]
	)
	rig.free()


## Art Bible rule 12. The pack ships a yellow-beak variant and two near-white
## ones; the yellow would be the only warm thing in the sky, and warm is
## reserved for windows, fire, beacons, the truck and the scarf.
func test_no_part_of_the_crow_is_warm() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return
	var tone: Color = CrowScript.palette_tone()
	assert_false(
		bible.warm_tones.has(tone),
		"the crow is painted a warm tone, and rule 12 does not list birds"
	)
