class_name AssetScanner
extends RefCounted

## Recursive file walk shared by the art gates.
##
## Returns an empty result for a missing root rather than erroring: the
## gates run against folders that do not exist yet in early waves.

## Shared across the three gates so their coverage cannot silently diverge.
const SCAN_ROOTS: Array[String] = ["res://assets/models", "res://scenes"]

## Roots exempt from the *surface* rules, and from those only.
##
## Art Bible rules 8 and 9 -- no normal, roughness, metallic or specular maps,
## every surface flat and coloured from the 12-entry table -- are about the
## **world**: buildings, terrain, props, vegetation. Characters are exempt by the
## owner's ruling (人物的颜色不受 GDD 的影响) and ship with the photographic
## albedo, normal, roughness and metallic maps they were generated with.
##
## Nothing else is waived. Rule 6's triangle budget still applies here and
## tests/art/test_topology.gd still enforces it -- the character was decimated
## from 12,108 to 6,999 triangles to satisfy it -- and so does any gate added
## later that is not about surfaces.
##
## Written down here, and tested, for the same reason AssetProbe.EXEMPT_SHADERS
## is: an asset that passes because a gate was told to look away is fine, and an
## asset that passes because a gate quietly never saw it is the failure this
## whole framework exists to end. Adding a line here is a person deciding.
##
## Lives beside SCAN_ROOTS rather than in either gate because both gates need
## the identical answer, and a policy duplicated in two files is a policy that
## will diverge.
const SURFACE_RULE_EXEMPT_ROOTS: Array[String] = ["res://assets/models/characters"]

## These imported Synty Polygon composites deliberately retain one source
## albedo map. They are still low-poly world props, and keep their collision and
## exact triangle gates; the narrow exception is only to Rule 8's ban on colour
## maps. `tests/art/test_synty_native_materials.gd` verifies that the map is
## present, is used by CelPainter and has no surviving PBR companions.
const NATIVE_TEXTURED_MODELS: Array[String] = [
	"res://assets/models/props/synty_supply_sacks.glb",
	"res://assets/models/props/synty_wooden_barrel.glb",
	"res://assets/models/props/synty_field_crate.glb",
	"res://assets/models/props/synty_work_log.glb",
	"res://assets/models/props/synty_field_stump.glb",
	"res://assets/models/props/synty_pickaxe.glb",
	"res://assets/models/props/synty_yard_cache.glb",
	"res://assets/models/props/synty_evacuation_cache.glb",
	"res://assets/models/props/synty_woodwork_station.glb",
	"res://assets/models/props/synty_larder_chest.glb",
	"res://assets/models/props/synty_provision_stack.glb",
	"res://assets/models/props/synty_yard_table.glb",
	"res://assets/models/props/synty_tarped_cache.glb",
	"res://assets/models/props/synty_broken_gateway.glb",
	"res://assets/models/props/synty_firepit.glb",
	"res://assets/models/props/synty_generator_cache.glb",
	"res://assets/models/props/synty_field_clinic.glb",
	"res://assets/models/props/synty_fish_camp.glb",
	"res://assets/models/props/synty_fuel_depot.glb",
	"res://assets/models/props/synty_road_blockade.glb",
	"res://assets/models/props/synty_radio_relay.glb",
	"res://assets/models/props/synty_refuge_bedroll.glb",
	"res://assets/models/props/synty_rock_cluster_north.glb",
	"res://assets/models/props/synty_rock_cluster_south.glb",
	"res://assets/models/props/synty_rock_cluster_east.glb",
]


## True when `path` is under a root the surface rules do not apply to.
##
## Prefix-matched on a trailing slash, so a sibling folder that merely starts
## with the same letters -- assets/models/characters_wip -- is not swept in.
static func is_surface_rule_exempt(path: String) -> bool:
	for root in SURFACE_RULE_EXEMPT_ROOTS:
		if path == root or path.begins_with(root + "/"):
			return true
	return false


## True only for the named, source-attributable low-poly Synty composites.
## This is not a folder-wide blind spot: a newly imported prop with a texture
## remains a Rule 8 offender until it is deliberately reviewed and added here.
static func preserves_native_albedo(path: String) -> bool:
	return NATIVE_TEXTURED_MODELS.has(path)

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
