extends SceneTree

## Generator for the art gates' binary test fixture.
## Run: godot --headless --path <project> --script res://tools/generate_gate_fixtures.gd
## Then re-import, or the file is invisible to ResourceLoader:
##      godot --headless --path <project> --import
##
## Writes res://tests/fixtures/gate_probe_model.glb -- a real glTF binary, not
## a stand-in. It exists because every other gate fixture is a .tres or a .tscn
## the engine loads directly, and the whole point of Wave 1 Task B is that the
## asset pipeline does not produce those. A .glb goes through Godot's *import*
## path instead: ResourceLoader hands back a PackedScene built from
## .godot/imported/, whose materials live on ArrayMesh surfaces rather than on
## any node. Only a real imported file proves the gates can see that.
##
## It cannot be generated during the test run. user:// is never imported
## (ResourceLoader.exists() on a .glb there is false), and a file dropped into
## res:// mid-run has no .import companion until an import pass runs. So the
## fixture is generated here, committed with its .import file, and consumed by
## the suite -- the same arrangement as the generated .tres files under data/
## (briefing section 2.7).
##
## Deliberately an offender on every axis the gates measure, so one fixture
## serves all three: off-palette albedo, a banned metallic value, and two
## triangles, which is over the 1-triangle budget the topology test hands it.
## The colour is hardcoded here on purpose -- tools/ is the documented sole
## exception to the no-hardcoded-hex rule (briefing section 2.6), and a fixture that
## read its "wrong" colour from the palette would be asserting nothing.

const FIXTURE_DIR := "res://tests/fixtures"
const FIXTURE_PATH := "res://tests/fixtures/gate_probe_model.glb"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))

	var root := Node3D.new()
	root.name = "GateProbe"
	var instance := MeshInstance3D.new()
	instance.name = "Quad"

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.resource_name = "off_palette_and_metallic"
	material.albedo_color = Color("#00FF00")
	material.metallic = 0.9
	mesh.surface_set_material(0, material)

	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var failed := false

	var append_error := document.append_from_scene(root, state)
	if append_error != OK:
		print("generate_gate_fixtures: FAILED to build the glTF scene (%d)" % append_error)
		failed = true

	var write_error := document.write_to_filesystem(state, FIXTURE_PATH)
	if write_error != OK:
		print("generate_gate_fixtures: FAILED to write %s (%d)" % [FIXTURE_PATH, write_error])
		failed = true

	# Freed on every path, before the early exit below (briefing section 2.2).
	root.free()

	if not FileAccess.file_exists(FIXTURE_PATH):
		print("generate_gate_fixtures: FAILED -- %s is not on disk after the write" % FIXTURE_PATH)
		failed = true

	if failed:
		print("generate_gate_fixtures: nothing usable was written.")
		quit(1)
		return

	print("generate_gate_fixtures: wrote %s" % FIXTURE_PATH)
	print("generate_gate_fixtures: now run --import, or the suite cannot load it.")
	quit(0)
