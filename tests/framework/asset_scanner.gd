class_name AssetScanner
extends RefCounted

## Recursive file walk shared by the art gates.
##
## Returns an empty result for a missing root rather than erroring: the
## gates run against folders that do not exist yet in early waves.

## Shared across the three gates so their coverage cannot silently diverge.
const SCAN_ROOTS: Array[String] = ["res://assets/models", "res://scenes"]
const MATERIAL_SUFFIXES: Array[String] = [".tres", ".material", ".res"]
const MESH_SUFFIXES: Array[String] = [".mesh", ".res", ".tres"]

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
