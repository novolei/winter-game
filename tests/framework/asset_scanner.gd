class_name AssetScanner
extends RefCounted

## Recursive file walk shared by the art gates.
##
## Returns an empty result for a missing root rather than erroring: the
## gates run against folders that do not exist yet in early waves.

## Shared across the three gates so their coverage cannot silently diverge.
const SCAN_ROOTS: Array[String] = ["res://assets/models", "res://scenes"]

## Files that may contain a material or a mesh, whether or not they *are* one.
##
## The two lists are identical and that is deliberate rather than lazy: every
## container format here can hold both, and the moment they diverge one gate
## starts inspecting a file the other never opens. AssetProbe sorts out what is
## actually inside; the scanner's only job is to not miss the file.
##
## The three groups:
##
##   - .tres / .res / .material / .mesh -- a resource saved on its own. The
##     only shape the gates could see before Wave 1 Task B, and the only shape
##     the asset pipeline never produces.
##   - .tscn / .scn -- a Godot scene. Meshes and materials live inside as
##     sub-resources.
##   - .glb / .gltf / .obj / .fbx / .blend / .dae / .escn -- source model
##     formats. Godot *imports* these, so ResourceLoader hands back a
##     PackedScene built from .godot/imported/, not the file's own bytes. An
##     un-imported one loads as null, which AssetProbe reports as an offender
##     rather than skipping.
##
## Deliberately the whole set rather than one canonical export format: which
## format the Blender pipeline standardises on is not decided yet, and a gate
## that covers only the guess is a gate that is blind to the answer.
##
## .dae and .escn are here for the same reason even though the Art Bible's
## pipeline (section 5) does not mention them: a file that lands in assets/models/
## and is not on this list is invisible, so the cost of listing a format
## nobody uses is nothing and the cost of omitting one is a silent pass.
##
## This list cannot be derived from the engine. Measured on 4.7.1 headless,
## ResourceLoader.get_recognized_extensions_for_type("PackedScene") returns
## only ["tscn", "res", "scn"] -- the import formats are resolved through
## .import files by the editor's importer, which does not advertise them here.
const CONTAINER_SUFFIXES: Array[String] = [
	".tres", ".res", ".material", ".mesh",
	".tscn", ".scn",
	".glb", ".gltf", ".obj", ".fbx", ".blend", ".dae", ".escn",
]
const MATERIAL_SUFFIXES: Array[String] = CONTAINER_SUFFIXES
const MESH_SUFFIXES: Array[String] = CONTAINER_SUFFIXES

static func find_files(root: String, suffixes: Array[String]) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(find_files(full, suffixes))
		else:
			for suffix in suffixes:
				if entry.ends_with(suffix):
					found.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return found
