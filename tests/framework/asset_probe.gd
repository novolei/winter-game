class_name AssetProbe
extends RefCounted

## Opens an art asset and reports every mesh and material inside it.
##
## ---------------------------------------------------------------------------
## WHY this exists
## ---------------------------------------------------------------------------
## The three art gates used to assume the loaded resource *is* the thing being
## judged:
##
##     var resource := ResourceLoader.load(path, "", CACHE_MODE_IGNORE)
##     if resource == null or not (resource is BaseMaterial3D):
##         continue
##
## That holds for a hand-saved .tres and for nothing the asset pipeline
## produces. Godot imports .glb / .gltf / .fbx / .blend as a PackedScene, and a
## .tscn is one by definition. In both cases the meshes and materials are
## *inside*, so every one of them hit that `continue` and was silently skipped
## -- with all three gates reporting green having inspected nothing.
##
## ---------------------------------------------------------------------------
## HOW it descends
## ---------------------------------------------------------------------------
## By PackedScene.get_state(), not instantiate(). A SceneState is walked
## without building a node tree, so this file allocates no Node on any path and
## there is nothing to free (briefing section 2.2). instantiate() would have worked
## too, but it puts a free() obligation on every early return in a walk that
## recurses, and a single missed one is a leak the suite fails on.
##
## Nothing is matched by node type or by property name. Every stored property
## of every node is read, and a value is kept if it *is* a Mesh or a Material.
## Two reasons:
##
##   1. A glTF's materials are not node properties at all. Godot puts them on
##      the ArrayMesh surfaces, reachable only through
##      Mesh.surface_get_material(). Verified on 4.7.1 against a real imported
##      .glb -- see tools/generate_gate_fixtures.gd.
##   2. A walk that knew about MeshInstance3D.mesh and material_override would
##      be blind to CSGShape3D.material, GeometryInstance3D.material_overlay,
##      MultiMeshInstance3D.multimesh, and whatever the next node type calls
##      its slot. Naming the slots you know about is how a gate ends up
##      claiming coverage it does not have, which is the failure this file was
##      written to end.
##
## The same argument extends past nodes: any other Resource is descended into
## as well, over its storage properties. That is how a Mesh hanging off a
## MultiMesh is found. The failure mode of descending too far is a *loud*
## offender the reviewer can exempt; the failure mode of descending too little
## is a silent pass. Prefer the loud one.

## Shaders exempt from the material gates, by resource path.
##
## DELIBERATELY EMPTY, and the emptiness is the point.
##
## A ShaderMaterial is not a BaseMaterial3D, so neither the palette gate nor
## the banned-feature gate can read a single property off it -- and the old
## type filter therefore dropped it without a word. The Art Bible specifies a
## custom two-band light() cel shader, so ShaderMaterial is the *intended*
## material type for terrain and characters from Wave 3 on; banning it would be
## wrong. So the skip becomes an exemption instead: anything not listed here is
## an offender, and adding a line here is a person writing down that they
## looked at that shader and decided. "We never looked" becomes "someone
## decided", which is the whole point.
##
## A ShaderMaterial whose shader is embedded in a scene has no resource_path
## and can therefore never be listed. That is intended: move the shader to its
## own .gdshader file, where it can be reviewed and diffed, before exempting
## it.
const EXEMPT_SHADERS: Array[String] = []

## Atmosphere, not surfaces. These carry no albedo a palette gate could read,
## and they are judged by eye against the lighting presets. Every outdoor scene
## has a WorldEnvironment, so reporting them would make the gate cry on normal
## work.
const NON_SURFACE_MATERIALS: Array[String] = [
	"ProceduralSkyMaterial",
	"PanoramaSkyMaterial",
	"PhysicalSkyMaterial",
	"FogMaterial",
]

## Guards against a resource graph that cycles back on itself. Nothing in a
## sane asset comes close; this only has to stop a pathological file from
## hanging the suite instead of failing it.
const MAX_DEPTH := 32


## Loads `path` and returns everything the gates need to judge it:
##
##     {
##       "error":     String,   -- "" when the file loaded
##       "meshes":    Array,    -- of {"label": String, "resource": Mesh}
##       "materials": Array,    -- of {"label": String, "resource": Material}
##     }
##
## `label` names the file *and the position inside it*, so an offender in a
## 40-node scene can be found without opening it.
static func probe(path: String) -> Dictionary:
	return probe_resource(path, ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE))


## The judgement half of probe(), split out so the unloadable branch is
## reachable from a test.
##
## It cannot be reached end-to-end. Loading a corrupt file does return null --
## verified on 4.7.1 with a .tres containing junk -- but it also prints three
## ERROR: lines to the console, and a run whose console is dirty is a failed
## run (briefing section 2.1). The same reasoning, and the same resolution, as the
## note on test_discovery.test_methods().
##
## To re-verify after an engine upgrade: write "not a resource" into a .tres,
## load it, and confirm the return is null. On 4.7.1 that prints
## "Parse Error: Expected '['.", "Failed loading resource", and
## "Error loading resource", then returns null.
static func probe_resource(path: String, resource: Resource) -> Dictionary:
	var result := {"error": "", "meshes": [], "materials": []}
	if resource == null:
		result["error"] = "could not be loaded at all -- it is missing, corrupt, or has never been imported"
		return result
	_descend(path, resource, result, {}, 0)
	return result


## "" when `material` is one the gates may leave alone -- either because they
## can read it, or because someone has written down an exemption. Otherwise the
## reason they cannot read it, which is an offence rather than a skip.
##
## Lives here rather than in either gate because both gates need the identical
## answer, and a policy duplicated in two files is a policy that will diverge.
## Same reasoning as AssetScanner.SCAN_ROOTS.
##
## `exempt_shaders` defaults to the real allowlist and is a parameter only so a
## test can exercise a non-empty one. The allowlist is a const and the shipped
## value is empty, so without this the exempt branch would be unreachable from
## the suite and would first run in anger on the day someone added a line to
## it. That branch returns "" for a material that is *not* a BaseMaterial3D --
## the exact case a caller must not then cast -- so it is the one branch that
## most needs a test.
static func unreadable_reason(material: Material, exempt_shaders: Array[String] = EXEMPT_SHADERS) -> String:
	if material is BaseMaterial3D:
		return ""
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return "is a ShaderMaterial with no shader assigned, so no art gate can read anything off it"
		var shader_path := shader.resource_path
		if shader_path == "":
			return "is a ShaderMaterial whose shader is embedded rather than a .gdshader file, so it cannot be named on AssetProbe.EXEMPT_SHADERS and no art gate can read its colours or its banned features"
		if exempt_shaders.has(shader_path):
			return ""
		return "is a ShaderMaterial using %s, which is not on AssetProbe.EXEMPT_SHADERS; no art gate can read its colours or its banned features, so it is an offender until someone reviews that shader and writes it down" % shader_path
	# Sky and fog materials are not surface materials. They describe the
	# atmosphere, are judged by eye against the lighting presets, and carry no
	# albedo a palette gate could check. Reporting them would flag every scene
	# that has a WorldEnvironment -- which is every outdoor scene.
	if NON_SURFACE_MATERIALS.has(material.get_class()):
		return ""
	return "is a %s, which neither art gate knows how to read" % material.get_class()


## How big the asset at `path` actually is, in metres:
##
##     {
##       "error":  String,   -- "" when the file loaded
##       "size":   Vector3,  -- the whole asset's bind-pose bounding box
##       "meshes": int,      -- how many meshes it was measured from
##     }
##
## `size` is ZERO with no error for a file that holds no mesh at all -- an
## animation-only FBX -- which is a real answer and not a failure.
##
## ---------------------------------------------------------------------------
## WHY THIS ONE FUNCTION INSTANTIATES, WHEN NOTHING ELSE IN THIS FILE DOES
## ---------------------------------------------------------------------------
## Every other walk here reads a SceneState, because a size question is the one
## question that cannot be answered from the resources alone. A mesh's own AABB
## is in the mesh's own space; where that mesh sits inside the asset is on the
## NODES, and a model built out of nine parts placed by nine node transforms
## measures nothing like the largest of its nine boxes. Reading transforms out
## of a SceneState is possible and was written first; it silently under-measures
## any node that instances another scene, because that node stores only its
## overrides and its geometry lives somewhere this walk never goes.
##
## So this one instantiates, composes the chain by hand, and frees on every
## path. The obligation is real (briefing section 2.2) and is why it is a single
## function with a single exit rather than a recursion with early returns.
##
## The AABB is the BIND POSE for a skinned mesh -- `Mesh.get_aabb()` never
## moves, whatever take is playing. That is exactly what a scale gate wants: the
## question is how big the asset was authored, not how far it reaches mid-flap.
static func bounds(path: String) -> Dictionary:
	var result := {
		"error": "", "size": Vector3.ZERO, "meshes": 0,
		"mesh_size": Vector3.ZERO, "bone_size": Vector3.ZERO, "bones": 0,
	}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		result["error"] = "could not be loaded at all -- it is missing, corrupt, or has never been imported"
		return result
	if resource is Mesh:
		result["size"] = (resource as Mesh).get_aabb().size
		result["mesh_size"] = result["size"]
		result["meshes"] = 1
		return result
	var packed := resource as PackedScene
	if packed == null:
		return result
	var scene := packed.instantiate()
	var box := AABB()
	var seen := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var here := _placed(scene, instance) * instance.mesh.get_aabb()
		box = here if seen == 0 else box.merge(here)
		seen += 1
	var bones := AABB()
	var boned := 0
	for node in scene.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		var into := _placed(scene, skeleton)
		for bone in range(skeleton.get_bone_count()):
			var at := AABB(into * skeleton.get_bone_global_rest(bone).origin, Vector3.ZERO)
			bones = at if boned == 0 else bones.merge(at)
			boned += 1
	scene.free()
	result["mesh_size"] = box.size
	result["bone_size"] = bones.size
	result["bones"] = boned
	# THE LARGER OF THE TWO, and this is not belt and braces -- it is the whole
	# reason `bones` is measured at all. MEASURED on 4.7.1: `Mesh.get_aabb()` on
	# the four Blender-exported characters returns a box in the SKIN's bind space,
	# which the skeleton scales back up at runtime, so the bear reads 0.029 m and
	# the wanderer 0.016 m -- the exact reading a 15 mm wolf produces, on four
	# assets that are correct and shipped. The crow, which came through ufbx
	# instead, reads its true 0.96 m from the same call.
	#
	# So neither instrument is trustworthy alone, and the two fail in opposite
	# directions: a mesh box can be far too SMALL for a skinned asset, and a bone
	# hull can only be too small for an unskinned one (where it is empty). The
	# larger is therefore the honest floor -- and a floor is what this measurement
	# is for, because the failure this gate exists to catch is a model that is
	# silently too small. An over-reading trips a ceiling, which is loud and
	# reviewable; an under-reading trips nothing at all.
	result["size"] = box.size if box.size.length() >= bones.size.length() else bones.size
	result["meshes"] = seen
	return result


## The transform from `root`'s own space down to `leaf`, root's own included.
##
## Written first as a walk that stopped AT root and therefore left root's own
## transform out -- which is where an importer's `nodes/root_scale` lands, so
## the instrument would have read the same size before and after the very defect
## it exists to catch. Same mistake, and the same fix, as
## `tests/art/test_crow_model.gd::_within`.
static func _placed(root: Node, leaf: Node) -> Transform3D:
	var placed := Transform3D()
	var walk: Node = leaf
	while walk != null:
		if walk is Node3D:
			placed = (walk as Node3D).transform * placed
		if walk == root:
			break
		walk = walk.get_parent()
	return placed


static func _descend(label: String, value: Variant, result: Dictionary, seen: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	if value is Array:
		var items: Array = value
		for index in range(items.size()):
			_descend("%s[%d]" % [label, index], items[index], result, seen, depth + 1)
		return
	if not (value is Resource):
		return

	var resource: Resource = value
	# Sub-resources are shared, so the same material can be reached from many
	# nodes. Judging it once per file is enough, and the alternative is a
	# report that lists one mistake forty times.
	var id := resource.get_instance_id()
	if seen.has(id):
		return
	seen[id] = true

	if resource is PackedScene:
		_descend_scene(label, resource as PackedScene, result, seen, depth + 1)
		return
	if resource is Mesh:
		var mesh: Mesh = resource
		result["meshes"].append({"label": label, "resource": mesh})
		for surface in range(mesh.get_surface_count()):
			_descend("%s surface %d" % [label, surface], mesh.surface_get_material(surface), result, seen, depth + 1)
		return
	if resource is Material:
		var material: Material = resource
		result["materials"].append({"label": label, "resource": material})
		_descend("%s next_pass" % label, material.next_pass, result, seen, depth + 1)
		return
	_descend_resource_properties(label, resource, result, seen, depth + 1)


static func _descend_scene(label: String, scene: PackedScene, result: Dictionary, seen: Dictionary, depth: int) -> void:
	var state := scene.get_state()
	for node in range(state.get_node_count()):
		var node_path := str(state.get_node_path(node))
		for property in range(state.get_node_property_count(node)):
			var property_name := state.get_node_property_name(node, property)
			var property_value = state.get_node_property_value(node, property)
			_descend("%s::%s.%s" % [label, node_path, property_name], property_value, result, seen, depth + 1)
		# A node that is an instance of another scene stores only its overrides
		# here; everything it actually contains lives in that scene.
		var instance := state.get_node_instance(node)
		if instance != null:
			_descend("%s::%s" % [label, node_path], instance, result, seen, depth + 1)


## Only storage properties, and never `script`. Reading every exposed property
## would pull in editor-only and computed ones for no gain, and a Node's or
## Resource's script is a GDScript whose own properties are of no interest to
## an art gate.
static func _descend_resource_properties(label: String, resource: Resource, result: Dictionary, seen: Dictionary, depth: int) -> void:
	for property in resource.get_property_list():
		var property_name: String = property["name"]
		if property_name == "script":
			continue
		if int(property["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		_descend("%s.%s" % [label, property_name], resource.get(property_name), result, seen, depth + 1)
