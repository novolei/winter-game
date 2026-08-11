extends TestCase

## Every world model must have `tools/palette_import_materials.gd` wired into
## its `.import` file, and the character models must not.
##
## ---------------------------------------------------------------------------
## WHY THIS TEST EXISTS
## ---------------------------------------------------------------------------
## Godot's glTF importer leaves `specular_mode` at SPECULAR_SCHLICK_GGX on every
## material it makes -- both the ones it parses out of a file and the white one
## it invents for a surface arriving without one. Art Bible rule 8 bans specular
## outright, and glTF has no concept that maps to SPECULAR_DISABLED, so no
## exporter setting can fix it. The project's answer is
## `tools/palette_import_materials.gd`, an `EditorScenePostImport` that rebuilds
## every material flat from `data/palette/color_bible.tres`.
##
## It is wired up by **one hand-added line in a generated file**:
##
##     import_script/path="res://tools/palette_import_materials.gd"
##
## Godot writes `.import` files itself. It does preserve `[params]` across
## reimports, but nothing guaranteed that line was ever added in the first
## place, and this wave proved the failure mode is real rather than theoretical:
## nine models were exported, imported, and landed with the line missing, and
## the first anyone knew was 28 surfaces failing `test_shading_features.gd` with
## a message about specular that says nothing about `.import` files. The
## farmhouse agent flagged the hole in its report; this closes it.
##
## The two gates are complementary and both are wanted. `test_shading_features`
## says *what* is wrong with the material. This says *why*, and it says it
## against the file you have to edit.
##
## ---------------------------------------------------------------------------
## CHARACTERS ARE THE OTHER HALF OF THE CONTRACT
## ---------------------------------------------------------------------------
## Characters are exempt from rules 8 and 9 by the owner's ruling and ship with
## the photographic albedo, normal, roughness and metallic maps they were
## generated with. Wiring the palette script into a character would strip all of
## that and repaint it from the 12-colour table -- and because the result would
## be *on* palette and flat, every other art gate would go green over it. So the
## exemption is asserted in both directions: a character with the line is a
## failure here, exactly as a building without it is.
##
## The exempt list is `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`, the same one the
## other two surface gates read, so the three cannot drift apart.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

const IMPORT_SCRIPT := "res://tools/palette_import_materials.gd"
const WIRING_LINE := "import_script/path=\"res://tools/palette_import_materials.gd\""

## Model containers only. A `.tres` mesh or a `.tscn` has no `.import` file and
## no importer to fight with; this is about what the scene importer does to a
## file it parses.
const IMPORTED_MODEL_SUFFIXES: Array[String] = [".glb", ".gltf", ".fbx", ".dae", ".obj"]


func _models() -> PackedStringArray:
	var found := PackedStringArray()
	for root in AssetScannerScript.SCAN_ROOTS:
		found.append_array(AssetScannerScript.find_files(root, IMPORTED_MODEL_SUFFIXES))
	return found


## The `.import` file's text, or "" when there is none.
func _import_text(model_path: String) -> String:
	var path := model_path + ".import"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## The decision, factored out so it can be tested against a wired and an unwired
## case. Inlined in the scan it would be unreachable from a test, and a reversed
## comparison would pass forever.
func _is_wired(import_text: String) -> bool:
	return import_text.contains(WIRING_LINE)


func test_the_check_accepts_a_wired_import_file() -> void:
	assert_true(
		_is_wired("nodes/root_scale=1.0\n%s\nmaterials/extract=0\n" % WIRING_LINE),
		"an .import carrying the line must read as wired"
	)


func test_the_check_rejects_an_unwired_import_file() -> void:
	assert_false(
		_is_wired("nodes/root_scale=1.0\nimport_script/path=\"\"\nmaterials/extract=0\n"),
		"the empty path Godot writes by default must read as unwired"
	)


## The script the line points at has to be there, or every model silently falls
## back to Godot's specular materials and this whole file is checking a string.
func test_the_import_script_exists() -> void:
	assert_true(
		ResourceLoader.exists(IMPORT_SCRIPT),
		"%s is what every model's .import points at, and it is not on disk" % IMPORT_SCRIPT
	)


## Guards the scan itself. Every gate in this suite can pass by inspecting
## nothing, and this one would if the suffix list or the roots ever stopped
## matching what the pipeline produces.
func test_the_scan_finds_the_models_on_disk() -> void:
	assert_true(
		_models().size() >= 10,
		"the scan found %d models under %s, which is fewer than this project is known to hold -- the suffix list or the scan roots have gone stale" % [_models().size(), ", ".join(AssetScannerScript.SCAN_ROOTS)]
	)


func test_every_world_model_resolves_its_materials_from_the_palette() -> void:
	var offenders := PackedStringArray()
	for path in _models():
		if AssetScannerScript.is_surface_rule_exempt(path):
			continue
		var text := _import_text(path)
		if text == "":
			offenders.append("%s has no .import file at all, so it has never been imported" % path)
		elif not _is_wired(text):
			offenders.append("%s does not carry `%s`, so Godot's importer will give it specular materials and rule 8 will fail on it" % [path, WIRING_LINE])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


func test_no_exempt_model_is_repainted_from_the_palette() -> void:
	var offenders := PackedStringArray()
	var seen := 0
	for path in _models():
		if not AssetScannerScript.is_surface_rule_exempt(path):
			continue
		seen += 1
		if _is_wired(_import_text(path)):
			offenders.append("%s is exempt from the surface rules and must keep its own maps, but its .import carries `%s`, which would repaint it from the 12-colour table -- and the result would pass every other art gate" % [path, WIRING_LINE])
	# Without this, an empty exempt folder makes the assertion above vacuous and
	# the test reports "verified" having looked at nothing.
	assert_true(seen > 0, "no exempt model was found under %s, so this test checked nothing" % ", ".join(AssetScannerScript.SURFACE_RULE_EXEMPT_ROOTS))
	assert_eq(offenders.size(), 0, "; ".join(offenders))
