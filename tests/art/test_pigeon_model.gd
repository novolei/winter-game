extends TestCase

## The pigeon delivery, held to the things the project-wide gates cannot see.
##
## Same reason `test_crow_model.gd` and `test_threat_models.gd` exist, and it is
## worth repeating because it is the shape of every art gate here: the pigeon
## lives under `assets/models/characters/`, which is
## `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`, so the palette and shading gates
## deliberately look away from it. A gate told to skip something cannot also be
## the thing that proves the skip was right.
##
##     美术门禁必须显式豁免 assets/models/characters/，而不是靠碰巧扫不到它而放行。
##     因错误原因保持沉默的门禁，比会报错的门禁更糟。
##
## What is NOT here is the size, which `tests/art/test_asset_scale.gd` and
## `data/scale/pigeon.tres` own for every model in the project rather than for
## this one -- because the defect that gate closes arrived with this package and
## the next nine animals out of it will arrive the same way.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const PigeonScript := preload("res://src/entities/wildlife/pigeon.gd")
## What the pigeon IS. `pigeon_animations.gd` and the `DOVE_*` constants are
## gone: the take table, the source rate and the yaw are all fields here.
const SPECIES := preload("res://data/wildlife/pigeon.tres")
const PALETTE_PATH := "res://data/palette/color_bible.tres"

const PIGEON := "res://assets/models/characters/pigeon/pigeon.fbx"
const PIGEON_ALBEDO := "res://assets/models/characters/pigeon/Dove-rock_COL_2k.png"

## Art Bible rule 6's creature tier. Not waived by the character exception box,
## which waives rules 8 and 9 and says in as many words that the budget stands.
const CREATURE_BUDGET := 8000

## Measured on the shipped import, and cross-checked against the inventory's own
## FBX parse, which counted 832 for this animal out of the package.
const PIGEON_TRIANGLES := 832


func _import_text() -> String:
	var path := PIGEON + ".import"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## The model instanced and yawed exactly as `Pigeon._build_rig()` does it, so
## everything below measures the shipped constant rather than a copy of it.
func _posed_rig() -> Node3D:
	var packed := ResourceLoader.load(PIGEON)
	if not (packed is PackedScene):
		return null
	var rig := (packed as PackedScene).instantiate() as Node3D
	if rig == null:
		return null
	if absf(SPECIES.model_yaw) > 0.0001:
		rig.rotate_y(SPECIES.model_yaw)
	return rig


## The transform from `root`'s parent space down to `leaf`, root's own included.
##
## Root's own is where the yaw lives, so a walk that stopped AT root would read
## identical numbers before and after the fix and report the fix had not worked.
## Same instrument, and the same trap, as `test_crow_model.gd::_within`.
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


# --- the asset ----------------------------------------------------------------


func test_the_delivery_is_on_disk() -> void:
	assert_true(ResourceLoader.exists(PIGEON), "%s is not in the project" % PIGEON)


## Whole asset, which is the number rule 6 is about.
func test_the_pigeon_is_inside_the_creature_budget() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the pigeon model did not instantiate")
	if rig == null:
		return
	var total := 0
	for instance in _meshes(rig):
		total += (instance as MeshInstance3D).mesh.get_faces().size() / 3
	rig.free()
	assert_true(total <= CREATURE_BUDGET, "the pigeon ships %d triangles, over rule 6's %d" % [total, CREATURE_BUDGET])
	assert_eq(
		total, PIGEON_TRIANGLES,
		"the pigeon now measures %d triangles rather than the %d recorded here -- the import changed under this gate" % [
			total, PIGEON_TRIANGLES]
	)


## One bird, one mesh. The crow's file shipped the same bird SIX times over --
## five alternate heads and beaks outside the skeleton -- and imported naively
## that was 31,116 triangles that every per-mesh gate passed. This delivery does
## not do that, and this is the assertion that says so rather than the reading of
## it that happened to be true once.
func test_only_one_bird_ships_in_the_file() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the pigeon model did not instantiate")
	if rig == null:
		return
	var count := _meshes(rig).size()
	rig.free()
	assert_eq(count, 1, "%d meshes came out of pigeon.fbx" % count)


## ONE FILE, NOT TWO. The pack ships a rig FBX as well and it is deliberately not
## here: identical mesh, identical skeleton, no animation, and a `*_Rig.fbx` in
## this package is the one thing the inventory names as a trap -- each carries a
## junk `Take 001` that a take census counts as real.
func test_the_pack_s_rig_file_was_not_taken_as_well() -> void:
	assert_false(
		ResourceLoader.exists("res://assets/models/characters/pigeon/pigeon_rig.fbx"),
		"the pack's rig file has been added; it carries a junk Take 001 that inflates every take census"
	)


# --- the exemption, asserted in both directions -------------------------------


func test_the_pigeon_is_covered_by_the_character_exemption_on_purpose() -> void:
	assert_true(
		AssetScannerScript.is_surface_rule_exempt(PIGEON),
		"%s is outside SURFACE_RULE_EXEMPT_ROOTS, so the palette and shading gates now judge a model that resolves its colour at runtime" % PIGEON
	)
	# The negative control. Without it this passes just as happily against an
	# exemption widened to the whole project.
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/props/power_pole.glb"),
		"a prop must not be exempt from the surface rules"
	)


func test_the_pigeon_is_not_wired_to_the_palette_import_script() -> void:
	assert_false(
		_import_text().contains("import_script/path=\"res://tools/palette_import_materials.gd\""),
		"%s is exempt and must not carry the palette import script" % PIGEON
	)


# --- the import settings that are part of the asset ---------------------------


func test_auto_lod_is_off() -> void:
	assert_true(
		_import_text().contains("meshes/generate_lods=false"),
		"the importer will decimate the bird, and at a bird's size the only thing an LOD can take away is the silhouette"
	)


## TRIMMING IS ON HERE AND OFF ON THE CROW, AND BOTH ARE CORRECT.
##
## `test_crow_model.gd` asserts `animation/trimming=false`, because the crow's
## clips are frame ranges inside one long take and trimming slides the numbers
## the slicer is written in. This pack lays its clips out the other way: each is
## its own `AnimationStack`, but all thirteen share ONE timeline, so
## `Dove_Idle Right` runs frames 120..215 and imports as 0..215 with five empty
## seconds on the front unless trimming takes them off.
##
## MEASURED with it off: `idle_right` 8.958 s against the pack's 3.958,
## `death` 23.792 s against 0.875. Nothing errors. The bird lands on the wire and
## stands still for five seconds before its idle starts.
func test_the_takes_are_trimmed_to_their_own_range_on_import() -> void:
	assert_true(
		_import_text().contains("animation/trimming=true"),
		"trimming is off, so every take after the first imports with the whole timeline before it as dead air"
	)


## Default true drops any bone whose value never leaves its rest. Playing the
## flight cycle and then the idle would then leave every bone the idle does not
## touch exactly where the flight left it -- a pigeon sitting on a wire with its
## wings out.
func test_immutable_tracks_are_kept() -> void:
	assert_true(
		_import_text().contains("animation/remove_immutable_tracks=false"),
		"immutable tracks are dropped, so switching takes leaves untouched bones wherever the previous take left them"
	)


## The pack authored the dove at 24 fps. Two animals in this package are not --
## Reindeer at 30 and Pig at 60 -- and computing a length at the wrong rate is
## off by 25% or 150% with nothing to report it.
func test_the_import_is_set_to_the_rate_the_pack_authored() -> void:
	assert_true(
		_import_text().contains("animation/fps=%d" % int(SPECIES.source_fps)),
		"the import rate does not match the species' source_fps"
	)


## The source FBX asks for `Dove-rock`, while the Unity package ships
## `Dove_rock`. The correctly named sibling is therefore part of the delivery,
## not an optional extracted file: without it Godot imports the geometry but the
## runtime painter can only turn the whole bird into one flat silhouette.
func test_the_original_two_k_plumage_map_ships_beside_the_fbx() -> void:
	assert_true(
		ResourceLoader.exists(PIGEON_ALBEDO, "Texture2D"),
		"the source DoveRock colour map is missing, so beak, breast, wing and feet detail cannot render"
	)
	var texture := load(PIGEON_ALBEDO) as Texture2D
	assert_not_null(texture, "the source DoveRock colour map did not import as Texture2D")
	if texture == null:
		return
	assert_eq(texture.get_width(), 2048, "the source DoveRock map is no longer the authored 2k texture")
	assert_eq(texture.get_height(), 2048, "the source DoveRock map is no longer the authored 2k texture")


## The winter cel material may shade and tint the map, but it must continue to
## sample it. A plain lit_color here is the exact regression the owner saw: all
## authored part colours collapse into one pigeon-shaped blob.
func test_the_runtime_pigeon_material_preserves_source_texture_detail() -> void:
	var pigeon: Pigeon = PigeonScript.new()
	pigeon.set_plumage_variant(Pigeon.Plumage.GREY_BROWN)
	var worn := pigeon.material()
	assert_not_null(worn, "the pigeon resolved no runtime material")
	if worn == null:
		pigeon.free()
		return
	assert_true(
		bool(worn.get_shader_parameter("use_source_albedo")),
		"the runtime material ignores the original DoveRock map and collapses the bird to one colour"
	)
	assert_not_null(
		worn.get_shader_parameter("source_albedo_texture") as Texture2D,
		"use_source_albedo is enabled without the original DoveRock texture"
	)
	assert_true(
		float(worn.get_shader_parameter("source_albedo_tint_strength")) > 0.0,
		"the selected plumage variant does not colour-grade the restored source map"
	)
	pigeon.free()


# --- the colour ---------------------------------------------------------------


func test_the_pigeon_is_painted_from_the_palette() -> void:
	var bible: Resource = load(PALETTE_PATH)
	assert_not_null(bible, "the palette is missing, so nothing can be resolved from it")
	if bible == null:
		return
	var tone: Color = SPECIES.tone()
	assert_true(bible.contains(tone), "the pigeon's colour %s is not in the 12-colour table" % tone.to_html(false))
	assert_true(
		bible.structure_tones.has(tone),
		"the pigeon is painted %s, which is not a structure tone" % tone.to_html(false)
	)


## A pigeon is a GREY bird and a crow is a black one, and at sixteen pixels the
## only thing that separates two dark birds against snow is their value. Sharing
## the crow's near-black would make the second species indistinguishable from the
## first, which is the whole reason for adding it.
func test_the_pigeon_is_a_lighter_bird_than_the_crow() -> void:
	var pigeon: Color = SPECIES.tone()
	var crow: Color = Crow.SPECIES.tone()
	assert_true(
		pigeon != crow,
		"the pigeon and the crow are both %s, so nobody can tell them apart" % pigeon.to_html(false)
	)
	assert_true(
		pigeon.get_luminance() > crow.get_luminance(),
		"the pigeon (%s) is darker than the crow (%s); a rock dove is the grey one" % [
			pigeon.to_html(false), crow.to_html(false)]
	)


## Not the farmhouse's own siding. One of the four things this bird perches on is
## the farmhouse eave, and a bird the colour of the wall behind it has no
## silhouette at all -- which is the argument the inventory used to refuse the
## polar bear.
func test_the_pigeon_is_not_the_colour_of_the_wall_it_sits_on() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return
	assert_true(
		SPECIES.tone() != bible.structure_tones[0],
		"the pigeon is painted the siding's own tone, so a bird on the eave disappears into the wall"
	)


## Art Bible rule 12. Warm is reserved for windows, fire, beacons, the truck and
## the scarf, and it does not list birds.
func test_no_part_of_the_pigeon_is_warm() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return
	assert_false(bible.warm_tones.has(SPECIES.tone()), "the pigeon is painted a warm tone")


## A living bird carries no settled snow -- and the refusal has to go through the
## painter's own cache key rather than being written onto the material
## afterwards. `CelPainter` caches one material per colour, so the moment anybody
## hands the flock the world's painter through the public `set_painter()`, a
## write would reach everything else painted `#2A3854` and no gate in this
## project could see it.
func test_the_pigeon_refuses_snow_through_the_painters_key_and_not_by_writing_on_it() -> void:
	var painter := CelPainter.new()
	var tone: Color = SPECIES.tone()
	# What anything else painted the same colour already holds.
	var a_wall := painter.material_for(tone)
	var pigeon: Pigeon = PigeonScript.new()
	pigeon.set_painter(painter)
	var worn := pigeon.material()
	assert_not_null(worn, "the pigeon resolved no material at all")
	assert_true(worn != a_wall, "the pigeon and the world are sharing one material, so one of them decides for both")
	assert_almost_eq(
		float(worn.get_shader_parameter("snow_receptivity")), 0.0, 0.0001,
		"snow settles on the pigeon, and by day six the flock is white"
	)
	assert_true(
		float(a_wall.get_shader_parameter("snow_receptivity")) > 0.0,
		"painting the pigeon turned the snow off for everything that shares its colour"
	)
	pigeon.free()


# --- which way the bird points ------------------------------------------------
#
# THE DEFECT THIS EXISTS FOR, AND WHY IT IS NOT THE CROW'S TEST COPIED.
#
# This bird arrived in a Unity `.unitypackage`. Unity is left-handed and its
# models face +Z; Godot is right-handed and `look_at()` aims -Z. The crow shipped
# a whole wave flying tail-first for exactly this reason, and the owner caught it
# rather than the suite.
#
# `test_crow_model.gd` settles it by asking which end of the bird reaches FURTHER
# from the origin, on the reasoning that the long end is the beak. MEASURED on
# the dove, that reasoning is false: its origin sits under its feet, so the tail
# reaches 0.185 m back and the beak only 0.078 m forward. The crow's own test
# applied here would call a correctly-built pigeon backwards.
#
# So the geometry half asks a question about the ANIMAL instead: the highest
# tenth of the bird is its skull, and a skull is in front of the body it sits on.
# Two instruments still, bones and mesh, because they are the two halves of the
# delivery and a rig that was turned round while its geometry was not must not
# pass.


func test_the_bird_is_built_facing_the_way_look_at_points_it() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the pigeon model did not instantiate")
	if rig == null:
		return
	var skeleton: Skeleton3D = null
	for node in rig.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	assert_not_null(skeleton, "the pigeon model carries no Skeleton3D")
	if skeleton == null:
		rig.free()
		return
	var into := _within(rig, skeleton)
	var beak := skeleton.find_bone("JawEnd_M")
	var tail := skeleton.find_bone("Tail3_M")
	assert_true(beak >= 0 and tail >= 0, "the rig has no JawEnd_M / Tail3_M to measure against")
	if beak < 0 or tail < 0:
		rig.free()
		return
	var beak_at: Vector3 = (into * skeleton.get_bone_global_rest(beak)).origin
	var tail_at: Vector3 = (into * skeleton.get_bone_global_rest(tail)).origin
	rig.free()
	assert_true(
		beak_at.z < tail_at.z,
		("the pigeon is built tail-first: beak z = %+.4f, tail z = %+.4f in the rig's own space. "
			+ "look_at() aims -Z, so every departure flies backwards and every perched bird faces "
			+ "the wrong way along its eave. pigeon.tres's model_yaw is %.4f rad.") % [
			beak_at.z, tail_at.z, SPECIES.model_yaw]
	)
	# Along the axis, not merely on the right side of zero. A rig whose beak was a
	# millimetre forward of its tail would pass a sign test and still read as a
	# bird flying sideways.
	var axis := beak_at - tail_at
	assert_true(
		-axis.z > absf(axis.x),
		"the pigeon's body axis is %s -- more across the rig than along it" % str(axis.snappedf(0.001))
	)


## The same question of the GEOMETRY, with no bone consulted.
func test_the_birds_geometry_points_the_same_way_its_skeleton_does() -> void:
	var rig := _posed_rig()
	assert_not_null(rig, "the pigeon model did not instantiate")
	if rig == null:
		return
	var points := PackedVector3Array()
	for instance in _meshes(rig):
		var placed := _within(rig, instance as MeshInstance3D)
		var mesh: Mesh = (instance as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			# Trap 5: an unused slot comes back null, and assigning null into a
			# typed PackedVector3Array aborts the caller rather than erroring.
			var raw = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			if raw == null:
				continue
			for vertex in (raw as PackedVector3Array):
				points.append(placed * vertex)
	rig.free()
	assert_true(points.size() > 0, "no vertices were read out of the pigeon mesh")
	if points.is_empty():
		return
	var highest := -1e9
	var lowest := 1e9
	for point in points:
		highest = maxf(highest, point.y)
		lowest = minf(lowest, point.y)
	var head_line := lowest + (highest - lowest) * 0.9
	var head_z := 0.0
	var head_count := 0
	var body_z := 0.0
	for point in points:
		body_z += point.z
		if point.y >= head_line:
			head_z += point.z
			head_count += 1
	assert_true(head_count > 0, "no vertices fell in the top tenth of the bird")
	if head_count == 0:
		return
	head_z /= float(head_count)
	body_z /= float(points.size())
	assert_true(
		head_z < body_z,
		("the pigeon's head sits at z = %+.4f and its body at z = %+.4f: the skull is BEHIND the body, "
			+ "which is Unity's +Z forward left uncorrected") % [head_z, body_z]
	)
