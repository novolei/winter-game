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
