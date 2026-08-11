extends RefCounted

## Test file discovery and introspection.
## Extracted from test_runner.gd so both halves of "what counts as a test"
## can be exercised directly instead of only indirectly through a
## SceneTree subclass driven by --script.

static func find_test_scripts(root: String) -> PackedStringArray:
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
			found.append_array(find_test_scripts(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

static func test_methods(script: GDScript) -> PackedStringArray:
	var methods := PackedStringArray()
	if script == null:
		return methods
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if method_name.begins_with("test_"):
			methods.append(method_name)
	return methods
