@tool
extends EditorScenePostImport

## Repaints an imported model's surfaces from data/palette/color_bible.tres,
## and gives it its collision.
##
## ---------------------------------------------------------------------------
## TWO JOBS, ONE HOOK
## ---------------------------------------------------------------------------
## A model's `.import` file can name exactly one `import_script/path`, and this
## project's is already this file: every world model carries the line, and
## `tests/art/test_import_wiring.gd` fails by name on one that does not. The
## collision pass is therefore a second call from here rather than a second
## script -- which would mean a second line in every `.import`, a second gate to
## keep it there, and a second thing to forget when a model is added.
##
## The two jobs do not touch. Repainting rewrites materials and never looks at a
## node; `tools/model_collision.gd` adds nodes and never looks at a material. A
## Shape3D has no surface, so nothing about Art Bible rules 8 and 9 or the gates
## that enforce them moves because a building became solid.
##
## ---------------------------------------------------------------------------
## WHY a model cannot simply carry its own materials
## ---------------------------------------------------------------------------
## Godot's glTF importer builds a StandardMaterial3D for every material it
## finds -- and invents a white one for every surface that arrives without one.
## Either way `specular_mode` is left at SPECULAR_SCHLICK_GGX, which Art Bible
## rule 8 bans outright, and tests/art/test_shading_features.gd reports as an
## offender. Nothing in glTF can turn it off: the format has no such concept.
##
## So the colours are not imported, they are *resolved*. The Blender build
## script names each material after a slot in the Art Bible's 12-colour table
## -- `PAL_SNOW_1`, `PAL_STRUCT_4`, `PAL_WARM_2` -- and this script looks that
## slot up in the palette resource and rebuilds the material flat: albedo from
## the table, metallic 0, specular disabled, no textures of any kind.
##
## The consequence worth stating plainly: **the .glb carries geometry, UVs and
## palette slot *names*; the palette resource carries the colours.** Retuning a
## colour is an edit to color_bible.tres and a reimport, not a trip through
## Blender. And no colour is hardcoded outside tools/, which is the rule.
##
## Wired up by `import_script/path` in the model's .import file.
##
## An unrecognised slot name is painted magenta rather than passed through.
## Magenta is not in the palette, so tests/art/test_palette.gd fails and names
## the file: a typo in a material name becomes a red test rather than a part
## that quietly keeps whatever colour the exporter happened to write.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const UNRESOLVED := Color(1.0, 0.0, 1.0)

## What each mesh name collides as, and the geometry that works it out. See that
## file's header for why the trees get a trunk cylinder rather than a hull and
## why the farmhouse's doorway has to be cut out by hand.
const CollisionScript := preload("res://tools/model_collision.gd")

var _cache: Dictionary = {}


func _post_import(scene: Node) -> Object:
	var bible: Resource = load(PALETTE_PATH)
	_repaint(scene, bible)
	CollisionScript.attach(scene)
	return scene


func _repaint(node: Node, bible: Resource) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		# An override would sit on top of the surface material rather than
		# replace it, leaving the offender underneath for the gates to find.
		instance.material_override = null
		for slot in range(instance.get_surface_override_material_count()):
			instance.set_surface_override_material(slot, null)
		var mesh := instance.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var existing := mesh.surface_get_material(surface)
				var slot_name := "" if existing == null else existing.resource_name
				mesh.surface_set_material(surface, _material_for(slot_name, bible))
	for child in node.get_children():
		_repaint(child, bible)


## One material per slot name, so a building with eight groups sharing four
## colours ends up with four materials rather than thirty-two.
func _material_for(slot_name: String, bible: Resource) -> StandardMaterial3D:
	if _cache.has(slot_name):
		return _cache[slot_name]
	var material := StandardMaterial3D.new()
	material.resource_name = slot_name
	material.albedo_color = _color_for(slot_name, bible)
	# Rule 8, the banned list, in full.
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	material.normal_enabled = false
	_cache[slot_name] = material
	return material


## The palette slot named by the .glb, or magenta when the name means nothing.
##
## Blender's exporter and Godot's importer both append a suffix to a duplicate
## material name, so the prefix is matched rather than the whole string.
func _color_for(slot_name: String, bible: Resource) -> Color:
	if bible == null:
		return UNRESOLVED
	var bands := {
		"PAL_SNOW_": bible.snow_tones,
		"PAL_STRUCT_": bible.structure_tones,
		"PAL_WARM_": bible.warm_tones,
	}
	for prefix in bands.keys():
		if not slot_name.begins_with(prefix):
			continue
		var tail := slot_name.substr(prefix.length())
		var digits := ""
		for i in range(tail.length()):
			if not tail[i].is_valid_int():
				break
			digits += tail[i]
		if digits == "":
			return UNRESOLVED
		var index := int(digits) - 1
		var tones: Array = bands[prefix]
		if index < 0 or index >= tones.size():
			return UNRESOLVED
		return tones[index]
	return UNRESOLVED
