extends SceneTree

## Brings every world model's `.import` file into line with the pipeline, so
## that adding a model is not also an exercise in remembering two undocumented
## lines.
##
##   Godot_console.exe --headless --path <project> \
##       --script res://tools/wire_model_imports.gd
##   Godot_console.exe --headless --path <project> --import
##
## Run it after exporting a model and before the reimport. It reports what it
## changed and exits; with nothing to do it says so and touches nothing.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## The props report's concern 2: `import_script/path` is a hand-added line in a
## file Godot generates, and while `tests/art/test_import_wiring.gd` now catches
## its absence by name, *nothing added it*. Nine models landed without it in one
## afternoon and the first anyone knew was 28 surfaces failing a specular check.
##
## The obvious fix -- Project Settings' Import Defaults, which writes an
## `[importer_defaults]` block into project.godot -- was considered and rejected.
## It is global to the scene importer, and this project has a deliberate
## exemption: `assets/models/characters/` must **not** be repainted from the
## palette, and `test_import_wiring.gd` asserts that in both directions. A global
## default would wire the palette script into the next character imported and
## the exemption would have to be enforced by hand-editing it back out, which is
## the same problem pointed the other way. A pass that reads the same exempt list
## the gates read cannot make that mistake.
##
## So: not automatic, but one command, single-sourced against
## `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`, and named in the failure message of
## the test that catches the omission.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

const MODEL_SUFFIXES: Array[String] = [".glb", ".gltf", ".fbx", ".dae", ".obj"]

## Every key this pass owns, and the value it must have.
##
## `import_script/path` resolves each material from the palette at import time;
## see tools/palette_import_materials.gd and Art Bible rule 8.
##
## `meshes/generate_lods` is off because these are silhouettes. The whole value
## of a 300-triangle bare tree is its outline, and an automatic decimator given
## 300 triangles of deliberately-placed twig has nothing to remove that is not
## load-bearing -- it will collapse the crown at exactly the distance the tree
## stops being anything else. Nothing in this project is dense enough for an LOD
## to save anything either: the entire farmstead is under 3,100 triangles.
const REQUIRED := {
	"import_script/path": "\"res://tools/palette_import_materials.gd\"",
	"meshes/generate_lods": "false",
}


func _initialize() -> void:
	var changed := 0
	var skipped := 0
	for path in _models():
		if AssetScannerScript.is_surface_rule_exempt(path):
			skipped += 1
			continue
		var import_path := path + ".import"
		if not FileAccess.file_exists(import_path):
			print("  no .import yet, run --import first: ", path)
			continue
		var before := FileAccess.get_file_as_string(import_path)
		var after := rewrite(before)
		if after == before:
			continue
		var file := FileAccess.open(import_path, FileAccess.WRITE)
		if file == null:
			printerr("could not write ", import_path)
			continue
		file.store_string(after)
		file.close()
		changed += 1
		print("  wired: ", import_path)
	print("wire_model_imports: %d file(s) changed, %d exempt model(s) left alone." % [changed, skipped])
	if changed > 0:
		print("wire_model_imports: run `--headless --import` now, or the change has no effect.")
	quit()


## Pure, so it can be tested without a filesystem. Replaces a key that is present
## with the wrong value and appends one that is missing; `[params]` is the last
## section of an `.import` file, so appending lands inside it.
static func rewrite(text: String) -> String:
	var out := text
	for key in REQUIRED:
		var wanted: String = "%s=%s" % [key, REQUIRED[key]]
		if out.contains(wanted + "\n") or out.ends_with(wanted):
			continue
		var lines := out.split("\n")
		var found := false
		for index in range(lines.size()):
			if lines[index].begins_with(str(key) + "="):
				lines[index] = wanted
				found = true
				break
		if found:
			out = "\n".join(lines)
		else:
			if not out.ends_with("\n"):
				out += "\n"
			out += wanted + "\n"
	return out


func _models() -> PackedStringArray:
	var found := PackedStringArray()
	for root in AssetScannerScript.SCAN_ROOTS:
		found.append_array(AssetScannerScript.find_files(root, MODEL_SUFFIXES))
	return found
