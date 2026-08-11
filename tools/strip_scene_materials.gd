@tool
extends EditorScenePostImport

## Leaves an imported model's surfaces bare, so the game paints them itself.
##
## Art Bible rule 8 bans normal, roughness, metallic and specular maps outright
## and rule 9 requires flat colour from the 12-entry table, so a bought or
## generated model's PBR set has nothing this project can use. The maps are
## dropped before the file ever reaches assets/models/ -- but that is not the
## end of it, because **Godot's glTF importer manufactures a
## StandardMaterial3D for any primitive that arrives without one**: white
## albedo, specular enabled. That invented material is a real offender under
## both rules, and tests/art/test_palette.gd and test_shading_features.gd
## report it as one.
##
## So the surfaces are cleared here instead. The model carries geometry and a
## rig and nothing else; the two-band cel material comes from
## data/palette/color_bible.tres at runtime, the same way every other material
## in this project does (see terrain_renderer.gd on why they are built in code).
##
## Wired up by `import_script/path` in the model's .import file.

func _post_import(scene: Node) -> Object:
	_strip(scene)
	return scene


func _strip(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		instance.material_override = null
		for slot in range(instance.get_surface_override_material_count()):
			instance.set_surface_override_material(slot, null)
		var mesh := instance.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				mesh.surface_set_material(surface, null)
	for child in node.get_children():
		_strip(child)
