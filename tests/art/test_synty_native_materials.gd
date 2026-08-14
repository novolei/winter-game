extends TestCase

## The source-quality contract for the approved Polygon library migration.
##
## These objects are not a broad texture exception. They are a named set of
## source-attributable low-poly props whose one painted albedo map is retained
## below the winter snow. The checks make all three parts explicit: copied
## source files exist, every runtime object embeds exactly that allowed kind of
## material, and the runtime CelPainter still owns its snow layer.

const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")
const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const CEL_SHADER := "res://assets/shaders/cel_flat.gdshader"
const MAX_TOTAL_TRIANGLES := 48000

const BATCH_SOURCE_MODELS: Array[String] = [
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Chest_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Crate_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Crate_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Barrel_Wood_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Barrel_Metal_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Sack_Stack_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Sack_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Rope_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Rope_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Table_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Chair_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Pot_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Wep_Axe_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Log_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Stump_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_FirePit_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Crate_Stack_Cover_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Fence_Damaged_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Fence_Gate_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Sack_Large_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_04.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_05.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_06.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_07.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_08.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_09.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_10.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Env_Rock_Pebbles_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Barrel_Metal_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Bottle_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Pot_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Sack_04.fbx",
	"res://assets/source/external/mybros/synty_polygon_generic/models/SM_Gen_Prop_Rope_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Generator_Small_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_GasCan_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_AmmoBox_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Pallet_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_BarrelPile_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Fuel_Bladder_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_FirePit_Fish_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_MedicalBox_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Sign_Medical_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Road_Barrier_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Cone_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_WireSpool_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Bed_SleepingBag_Roll_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Bed_Stretcher_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_RadioPhone_01.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Radio_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Lamp_02.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Sack_06.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Prop_Crate_Wood_03.fbx",
	"res://assets/source/external/mybros/synty_polygon_military/models/SM_Bld_Tent_Refugee_Damaged_01.fbx",
]

const REQUIRED_SOURCE_SUPPORT: Array[String] = [
	"res://assets/source/external/mybros/synty_polygon_generic/materials/Generic_01_A.mat",
	"res://assets/source/external/mybros/synty_polygon_generic/textures/alts/Generic_01_A.png",
	"res://assets/source/external/mybros/synty_polygon_generic/textures/emissive/Generic_Emissive_01_A.png",
	"res://assets/source/external/mybros/synty_polygon_generic/textures/Generic_Normals_01.png",
	"res://assets/source/external/mybros/synty_polygon_military/materials/PolygonMilitary_01_A.mat",
	"res://assets/source/external/mybros/synty_polygon_military/textures/alts/PolygonMilitary_01_A.png",
	"res://assets/source/external/mybros/synty_polygon_military/textures/PolygonMilitary_01_A_Normals.png",
	"res://assets/source/external/mybros/synty_polygon_military/textures/Mesh_Cover_01.tga",
	"res://assets/source/external/mybros/synty_polygon_military/textures/Mesh_Cover_02.tga",
	"res://assets/source/external/mybros/synty_polygon_military/textures/Fence_01_Alpha.tga",
]


func test_the_approved_source_batch_and_material_support_are_copied() -> void:
	for path in BATCH_SOURCE_MODELS + REQUIRED_SOURCE_SUPPORT:
		assert_true(FileAccess.file_exists(path), "%s is missing; no runtime asset may claim to preserve a source it did not copy" % path)
		assert_true(FileAccess.file_exists(path + ".meta"), "%s is missing its Unity provenance metadata" % path)


func test_every_native_runtime_prop_has_one_sanitised_source_albedo() -> void:
	for path in AssetScannerScript.NATIVE_TEXTURED_MODELS:
		var probe := AssetProbeScript.probe(path)
		assert_eq(probe["error"], "", "%s could not be read: %s" % [path, probe["error"]])
		var materials: Array = probe["materials"]
		assert_eq(materials.size(), 1, "%s must keep one composite surface material, got %d" % [path, materials.size()])
		if materials.size() != 1:
			continue
		var material: Material = materials[0]["resource"]
		assert_true(material is StandardMaterial3D, "%s must arrive as a sanitised StandardMaterial3D, got %s" % [path, material])
		if not (material is StandardMaterial3D):
			continue
		var standard := material as StandardMaterial3D
		assert_true(standard.resource_name.begins_with("SYNTY_TEX_"), "%s lost its native-texture marker: %s" % [path, standard.resource_name])
		assert_not_null(standard.albedo_texture, "%s lost its copied source albedo map" % path)
		assert_false(standard.normal_enabled, "%s re-enabled a source normal map" % path)
		assert_eq(standard.metallic, 0.0, "%s kept metallic PBR data" % path)
		assert_eq(standard.specular_mode, BaseMaterial3D.SPECULAR_DISABLED, "%s kept specular PBR data" % path)


func test_native_source_detail_stays_inside_the_aggregate_budget() -> void:
	var total := 0
	for path in AssetScannerScript.NATIVE_TEXTURED_MODELS:
		var probe := AssetProbeScript.probe(path)
		for entry in probe["meshes"]:
			var mesh: Mesh = entry["resource"]
			total += mesh.get_faces().size() / 3
	assert_true(total > 0, "the native low-poly set has no triangles, so this budget checked nothing")
	assert_true(total <= MAX_TOTAL_TRIANGLES, "the native low-poly set is %d triangles, above its %d aggregate cap" % [total, MAX_TOTAL_TRIANGLES])


func test_cel_painter_uses_the_source_map_below_the_shared_snow_layer() -> void:
	var packed := load(AssetScannerScript.NATIVE_TEXTURED_MODELS[0]) as PackedScene
	assert_not_null(packed, "a representative native prop must load")
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var instance := _first_mesh(root)
	assert_not_null(instance, "the representative native prop contains no mesh")
	if instance == null:
		root.free()
		return
	var painter: CelPainter = CelPainterScript.new()
	painter.paint(root)
	var worn := instance.get_surface_override_material(0) as ShaderMaterial
	assert_not_null(worn, "CelPainter must replace the imported material")
	if worn != null:
		assert_eq(worn.shader.resource_path, CEL_SHADER)
		assert_true(bool(worn.get_shader_parameter("use_source_albedo")), "the original map was not handed to the cel shader")
		assert_not_null(worn.get_shader_parameter("source_albedo_texture"), "the cel shader received no original albedo map")
		assert_true(float(worn.get_shader_parameter("snow_receptivity")) > 0.0, "the textured prop escaped the shared snow layer")
	root.free()


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null
