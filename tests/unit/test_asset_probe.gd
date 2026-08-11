extends TestCase

## The art gates are only as real as this descent. Before it existed, all three
## judged whatever ResourceLoader handed back and skipped it if the type was
## wrong -- which is every shape the asset pipeline produces. These tests build
## each of those shapes in memory and demand the probe find what is inside.
##
## The gates' own end-to-end tests cover the same ground through a real file on
## disk. These cover the descent directly, so a failure says which shape broke
## rather than which gate noticed.

const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

## Every Node this file allocates is freed by _pack(), which is the only place
## one is created (briefing section 2.2).
func _pack(root: Node) -> PackedScene:
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _triangle() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _labels(entries: Array) -> String:
	var names := PackedStringArray()
	for entry in entries:
		names.append(entry["label"])
	return "; ".join(names)

## W1-B6. The branch that used to be `continue`.
##
## Reached through probe_resource() rather than probe() because loading a
## corrupt file, while it does return null, prints three ERROR: lines and a run
## whose console is dirty is a failed run (briefing section 2.1). probe_resource() is
## the same production code path -- probe() is a one-line wrapper that supplies
## the ResourceLoader call -- so nothing here is a stand-in for the logic under
## test, only for the way the null arrives.
func test_an_unloadable_asset_is_an_error_not_an_empty_result() -> void:
	var result := AssetProbeScript.probe_resource("res://assets/models/props/corrupt.tres", null)
	assert_true(result["error"] != "", "a null resource must produce an error, got: %s" % result)
	assert_eq(result["materials"].size(), 0, "and no materials")
	assert_eq(result["meshes"].size(), 0, "and no meshes")

func test_a_loose_material_is_found() -> void:
	var material := StandardMaterial3D.new()
	var result := AssetProbeScript.probe_resource("res://x.tres", material)
	assert_eq(result["error"], "", "a material loads fine")
	assert_eq(result["materials"].size(), 1, "the material itself must be reported, got: %s" % _labels(result["materials"]))

func test_a_loose_mesh_is_found() -> void:
	var result := AssetProbeScript.probe_resource("res://x.tres", BoxMesh.new())
	assert_eq(result["meshes"].size(), 1, "the mesh itself must be reported, got: %s" % _labels(result["meshes"]))

## The shape a glTF import produces: the material is on the mesh surface, not on
## any node. A walk over node properties alone finds the mesh and misses the
## material entirely.
func test_a_material_on_a_mesh_surface_is_found() -> void:
	var mesh := _triangle()
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var result := AssetProbeScript.probe_resource("res://x.tres", mesh)
	assert_eq(result["meshes"].size(), 1, "the mesh, got: %s" % _labels(result["meshes"]))
	assert_eq(result["materials"].size(), 1, "and the material on its surface, got: %s" % _labels(result["materials"]))

## W1-B2, at the level of the descent rather than the gate.
func test_a_scene_yields_the_mesh_and_material_inside_it() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	var mesh := _triangle()
	mesh.surface_set_material(0, StandardMaterial3D.new())
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var result := AssetProbeScript.probe_resource("res://x.tscn", _pack(root))
	assert_eq(result["meshes"].size(), 1, "the mesh inside the scene, got: %s" % _labels(result["meshes"]))
	assert_eq(result["materials"].size(), 1, "and its surface material, got: %s" % _labels(result["materials"]))

## The label has to say where inside the file the offender is, or a 40-node
## scene reports "this scene is wrong" and leaves the reader to find it.
func test_a_label_names_the_node_it_came_from() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MeshInstance3D.new()
	instance.name = "Chimney"
	instance.mesh = _triangle()
	root.add_child(instance)
	instance.owner = root
	var result := AssetProbeScript.probe_resource("res://farmhouse.tscn", _pack(root))
	var labels := _labels(result["meshes"])
	assert_true(labels.contains("res://farmhouse.tscn"), "the label must name the file, got: %s" % labels)
	assert_true(labels.contains("Chimney"), "and the node inside it, got: %s" % labels)

## Both of the other two places a MeshInstance3D can carry a material. Neither
## is the surface material, and a descent that only knew about one of them
## would pass the test above and still be blind here.
func test_node_level_material_overrides_are_found() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = _triangle()
	instance.material_override = StandardMaterial3D.new()
	instance.set_surface_override_material(0, StandardMaterial3D.new())
	root.add_child(instance)
	instance.owner = root
	var result := AssetProbeScript.probe_resource("res://x.tscn", _pack(root))
	assert_eq(result["materials"].size(), 2, "material_override and surface_material_override/0, got: %s" % _labels(result["materials"]))

## A node type that is not a MeshInstance3D and a slot that is not called
## "mesh". Nothing in the descent matches on either, which is the point: it
## keeps a value because of what the value *is*.
func test_a_mesh_reached_through_another_resource_is_found() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees"
	var multi := MultiMesh.new()
	multi.mesh = _triangle()
	instance.multimesh = multi
	root.add_child(instance)
	instance.owner = root
	var result := AssetProbeScript.probe_resource("res://x.tscn", _pack(root))
	assert_eq(result["meshes"].size(), 1, "the mesh hanging off the MultiMesh, got: %s" % _labels(result["meshes"]))

## An instanced sub-scene stores only its overrides in the outer scene; whatever
## it actually contains lives in the inner PackedScene.
func test_an_instanced_sub_scene_is_descended_into() -> void:
	var inner_root := MeshInstance3D.new()
	inner_root.name = "Inner"
	var mesh := _triangle()
	mesh.surface_set_material(0, StandardMaterial3D.new())
	inner_root.mesh = mesh
	var inner := _pack(inner_root)

	var outer_root := Node3D.new()
	outer_root.name = "Outer"
	var child := inner.instantiate()
	child.name = "Child"
	outer_root.add_child(child)
	child.owner = outer_root
	var outer := _pack(outer_root)

	var result := AssetProbeScript.probe_resource("res://outer.tscn", outer)
	assert_true(result["meshes"].size() >= 1, "the mesh inside the instanced scene, got: %s" % _labels(result["meshes"]))
	assert_true(result["materials"].size() >= 1, "and its material, got: %s" % _labels(result["materials"]))

## A material shared by two nodes is one mistake, not two. Without the
## already-seen guard the report lists it once per reference.
func test_a_shared_material_is_reported_once() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var shared := StandardMaterial3D.new()
	for index in range(3):
		var instance := MeshInstance3D.new()
		instance.name = "Body%d" % index
		instance.mesh = _triangle()
		instance.material_override = shared
		root.add_child(instance)
		instance.owner = root
	var result := AssetProbeScript.probe_resource("res://x.tscn", _pack(root))
	assert_eq(result["materials"].size(), 1, "one shared material, one report, got: %s" % _labels(result["materials"]))

## W1-B3. The allowlist policy lives in AssetProbe so the two material gates
## cannot answer this question differently.
func test_a_base_material_is_readable() -> void:
	assert_eq(AssetProbeScript.unreadable_reason(StandardMaterial3D.new()), "", "a StandardMaterial3D is what the gates read")

func test_a_shader_material_with_an_unlisted_shader_is_not_readable() -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;"
	material.shader = shader
	var reason := AssetProbeScript.unreadable_reason(material)
	assert_true(reason != "", "an unlisted ShaderMaterial must be named, not skipped")
	assert_true(reason.contains("EXEMPT_SHADERS"), "and the reason must say where to write the exemption down, got: %s" % reason)

func test_a_shader_material_on_the_allowlist_is_readable() -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;"
	shader.resource_path = "res://src/rendering/two_band_cel.gdshader"
	material.shader = shader
	var exempt := ["res://src/rendering/two_band_cel.gdshader"] as Array[String]
	assert_eq(AssetProbeScript.unreadable_reason(material, exempt), "", "a written-down shader is exempt")
	# ...and only that one. An exemption is per shader, not per material type.
	var other := ShaderMaterial.new()
	var other_shader := Shader.new()
	other_shader.code = "shader_type spatial;"
	other_shader.resource_path = "res://src/rendering/something_else.gdshader"
	other.shader = other_shader
	assert_true(AssetProbeScript.unreadable_reason(other, exempt) != "", "a different shader is not")

func test_the_allowlist_starts_empty() -> void:
	# Nothing is exempt until someone writes it down. If a later wave adds the
	# cel shader here, this becomes an assertion about that decision -- change
	# it deliberately, with the shader named in the commit message.
	assert_eq(AssetProbeScript.EXEMPT_SHADERS.size(), 0, "the ShaderMaterial allowlist must start empty")

func test_a_shader_material_with_no_shader_is_not_readable() -> void:
	assert_true(AssetProbeScript.unreadable_reason(ShaderMaterial.new()) != "", "a ShaderMaterial with no shader must be named too")

## A Material subclass that is neither BaseMaterial3D nor ShaderMaterial. There
## is no gate for it, and "no gate for it" must read as an offence rather than
## as a pass.
func test_an_unknown_material_type_is_not_readable() -> void:
	var reason := AssetProbeScript.unreadable_reason(ParticleProcessMaterial.new())
	assert_true(reason != "", "a material type no gate covers must be named")
	assert_true(reason.contains("ParticleProcessMaterial"), "and named by class, got: %s" % reason)

## Sky and fog materials are atmosphere, not surfaces. They are judged by eye
## against the lighting presets, so a surface gate reporting them would fire on
## every outdoor scene.
func test_a_sky_material_is_exempt_rather_than_unreadable() -> void:
	assert_eq(AssetProbeScript.unreadable_reason(ProceduralSkyMaterial.new()), "", "sky materials are out of a surface gate's scope")
