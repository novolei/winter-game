extends TestCase

## The farmstead props and the five bare trees, held to the numbers the
## task brief set rather than to the numbers the folder they live in allows.
##
## Three things here are contracts rather than art choices, and none of them is
## checked anywhere else.
##
## 1. EVERY ONE OF THESE IS EXACTLY ONE MESH. tests/art/test_topology.gd is a
##    *per-mesh* gate, so an asset split across several meshes can be far over
##    its class budget while every mesh in it passes -- the farmhouse needed a
##    test of its own to add itself up, and that hole is general. A prop that is
##    one mesh does not have the hole at all, because per-mesh and per-asset are
##    then the same number. That property is worth asserting, because it is one
##    line in a build script away from silently going away, and the day it does
##    the budget stops being enforced with nothing anywhere saying so.
##
## 2. THE BRIEF'S BUDGETS, WHICH ARE AT OR TIGHTER THAN THE GATE'S. The tire
##    swing is allowed 100 where its folder allows 200, and the well house 300
##    where its folder allows 500. **No budget was raised to make an asset fit.**
##
##    The trees moved from 300 to 600 and that is the one exception, so it is
##    worth being precise about the direction the change came from: Art Bible
##    rule 6 was rewritten to say 600, with its own paragraph explaining why
##    (300 bought about 35 twig tips against the reference's hundred-plus), and
##    this number follows the spec. It was not raised because a tree came out
##    over. The trees were rebuilt denser afterwards and land at 588, 580, 516,
##    379 and 169 -- every one of them under the new number with room to spare,
##    which is what a budget that leads rather than follows looks like.
##    Every asset is filed by what it is -- the tool shed and the well house are
##    small buildings and live under buildings/ at 500 -- so the folder's number
##    is already the right one and no gate was edited to make an asset fit. This
##    test is the tighter of the two, so moving a file into a roomier folder
##    cannot quietly relax it.
##
## 3. THE FILES EXIST AND IMPORT. A model that never imported loads as null,
##    and a null passes every gate in this suite by being invisible to it.

const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

## path -> triangles allowed. The numbers are the task brief's, and each is at
## or below what tests/art/test_topology.gd allows the folder.
const PROPS := {
	"res://assets/models/vegetation/tree_bare_a.glb": 600,
	"res://assets/models/vegetation/tree_bare_b.glb": 600,
	"res://assets/models/vegetation/tree_bare_c.glb": 600,
	"res://assets/models/vegetation/tree_bare_d.glb": 600,
	"res://assets/models/vegetation/tree_bare_e.glb": 600,
	"res://assets/models/props/pickup_truck.glb": 200,
	"res://assets/models/props/flatbed_truck.glb": 200,
	"res://assets/models/props/fence_segment.glb": 200,
	"res://assets/models/props/power_pole.glb": 200,
	"res://assets/models/props/power_wire.glb": 200,
	"res://assets/models/buildings/well_house/well_house.glb": 300,
	"res://assets/models/props/tire_swing.glb": 100,
	"res://assets/models/props/woodpile.glb": 200,
	"res://assets/models/props/supply_cache.glb": 200,
	"res://assets/models/props/field_marker.glb": 200,
	"res://assets/models/props/fallen_limb.glb": 200,
	"res://assets/models/props/emergency_sled.glb": 200,
	"res://assets/models/props/departure_pack.glb": 200,
	"res://assets/models/props/chopping_block.glb": 200,
	"res://assets/models/props/evacuation_cart.glb": 200,
	"res://assets/models/props/water_well.glb": 200,
	"res://assets/models/props/burning_barrel.glb": 200,
	"res://assets/models/props/campfire.glb": 200,
	# Native Synty Polygon models preserve their deliberately authored low-poly
	# topology. Each remains one mesh/one material and has an exact cap below;
	# the aggregate cap lives beside the general topology gate.
	"res://assets/models/props/synty_supply_sacks.glb": 1500,
	"res://assets/models/props/synty_wooden_barrel.glb": 1550,
	"res://assets/models/props/synty_field_crate.glb": 300,
	"res://assets/models/props/synty_work_log.glb": 350,
	"res://assets/models/props/synty_field_stump.glb": 150,
	"res://assets/models/props/synty_pickaxe.glb": 200,
	"res://assets/models/props/synty_yard_cache.glb": 3500,
	"res://assets/models/props/synty_evacuation_cache.glb": 2100,
	"res://assets/models/props/synty_woodwork_station.glb": 2600,
	"res://assets/models/props/synty_larder_chest.glb": 1300,
	"res://assets/models/props/synty_provision_stack.glb": 3000,
	"res://assets/models/props/synty_yard_table.glb": 450,
	"res://assets/models/props/synty_tarped_cache.glb": 1200,
	"res://assets/models/props/synty_broken_gateway.glb": 1200,
	"res://assets/models/props/synty_firepit.glb": 1350,
	"res://assets/models/props/synty_generator_cache.glb": 2600,
	"res://assets/models/props/synty_field_clinic.glb": 850,
	"res://assets/models/props/synty_fish_camp.glb": 1100,
	"res://assets/models/props/synty_fuel_depot.glb": 13400,
	"res://assets/models/props/synty_road_blockade.glb": 850,
	"res://assets/models/props/synty_radio_relay.glb": 850,
	"res://assets/models/props/synty_refuge_bedroll.glb": 3400,
	"res://assets/models/props/synty_rock_cluster_north.glb": 750,
	"res://assets/models/props/synty_rock_cluster_south.glb": 500,
	"res://assets/models/props/synty_rock_cluster_east.glb": 900,
	"res://assets/models/buildings/tool_shed/tool_shed.glb": 500,
}

## The node name each file must hold its mesh under. Not decoration: the scene
## that places these addresses them by name, and a renamed object in a build
## script is a rename nothing else would report.
const MESH_NAMES := {
	"res://assets/models/vegetation/tree_bare_a.glb": "Tree_Bare_A",
	"res://assets/models/vegetation/tree_bare_b.glb": "Tree_Bare_B",
	"res://assets/models/vegetation/tree_bare_c.glb": "Tree_Bare_C",
	"res://assets/models/vegetation/tree_bare_d.glb": "Tree_Bare_D",
	"res://assets/models/vegetation/tree_bare_e.glb": "Tree_Bare_E",
	"res://assets/models/props/pickup_truck.glb": "Pickup_Truck",
	"res://assets/models/props/flatbed_truck.glb": "Flatbed_Truck",
	"res://assets/models/props/fence_segment.glb": "Fence_Segment",
	"res://assets/models/props/power_pole.glb": "Power_Pole",
	"res://assets/models/props/power_wire.glb": "Power_Wire",
	"res://assets/models/buildings/well_house/well_house.glb": "Well_House",
	"res://assets/models/props/tire_swing.glb": "Tire_Swing",
	"res://assets/models/props/woodpile.glb": "Woodpile",
	"res://assets/models/props/supply_cache.glb": "Supply_Cache",
	"res://assets/models/props/field_marker.glb": "Field_Marker",
	"res://assets/models/props/fallen_limb.glb": "Fallen_Limb",
	"res://assets/models/props/emergency_sled.glb": "Emergency_Sled",
	"res://assets/models/props/departure_pack.glb": "Departure_Pack",
	"res://assets/models/props/chopping_block.glb": "Chopping_Block",
	"res://assets/models/props/evacuation_cart.glb": "Evacuation_Cart",
	"res://assets/models/props/water_well.glb": "Water_Well",
	"res://assets/models/props/burning_barrel.glb": "Burning_Barrel",
	"res://assets/models/props/campfire.glb": "Campfire",
	"res://assets/models/props/synty_supply_sacks.glb": "Synty_Supply_Sacks",
	"res://assets/models/props/synty_wooden_barrel.glb": "Synty_Wooden_Barrel",
	"res://assets/models/props/synty_field_crate.glb": "Synty_Field_Crate",
	"res://assets/models/props/synty_work_log.glb": "Synty_Work_Log",
	"res://assets/models/props/synty_field_stump.glb": "Synty_Field_Stump",
	"res://assets/models/props/synty_pickaxe.glb": "Synty_Pickaxe",
	"res://assets/models/props/synty_yard_cache.glb": "Synty_Yard_Cache",
	"res://assets/models/props/synty_evacuation_cache.glb": "Synty_Evacuation_Cache",
	"res://assets/models/props/synty_woodwork_station.glb": "Synty_Woodwork_Station",
	"res://assets/models/props/synty_larder_chest.glb": "Synty_Larder_Chest",
	"res://assets/models/props/synty_provision_stack.glb": "Synty_Provision_Stack",
	"res://assets/models/props/synty_yard_table.glb": "Synty_Yard_Table",
	"res://assets/models/props/synty_tarped_cache.glb": "Synty_Tarped_Cache",
	"res://assets/models/props/synty_broken_gateway.glb": "Synty_Broken_Gateway",
	"res://assets/models/props/synty_firepit.glb": "Synty_Firepit",
	"res://assets/models/props/synty_generator_cache.glb": "Synty_Generator_Cache",
	"res://assets/models/props/synty_field_clinic.glb": "Synty_Field_Clinic",
	"res://assets/models/props/synty_fish_camp.glb": "Synty_Fish_Camp",
	"res://assets/models/props/synty_fuel_depot.glb": "Synty_Fuel_Depot",
	"res://assets/models/props/synty_road_blockade.glb": "Synty_Road_Blockade",
	"res://assets/models/props/synty_radio_relay.glb": "Synty_Radio_Relay",
	"res://assets/models/props/synty_refuge_bedroll.glb": "Synty_Refuge_Bedroll",
	"res://assets/models/props/synty_rock_cluster_north.glb": "Synty_Rock_Cluster_North",
	"res://assets/models/props/synty_rock_cluster_south.glb": "Synty_Rock_Cluster_South",
	"res://assets/models/props/synty_rock_cluster_east.glb": "Synty_Rock_Cluster_East",
	"res://assets/models/buildings/tool_shed/tool_shed.glb": "Tool_Shed",
}


## Every node in an imported model that carries a Mesh, by name.
##
## Read off PackedScene.get_state() rather than instantiate(): a SceneState is
## walked without building a node tree, so this test allocates no Node and has
## nothing to free (briefing section 2.2). Same technique as
## tests/art/test_farmhouse_model.gd.
func _mesh_node_names(path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return names
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			var value = state.get_node_property_value(node, property)
			if value is Mesh:
				names.append(state.get_node_name(node))
				break
	return names


func _triangles(path: String) -> int:
	var probe := AssetProbeScript.probe(path)
	if probe["error"] != "":
		return -1
	var total := 0
	for entry in probe["meshes"]:
		var mesh: Mesh = entry["resource"]
		total += mesh.get_faces().size() / 3
	return total


func test_every_prop_imports() -> void:
	for path in PROPS.keys():
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(
			resource is PackedScene,
			"%s must import as a PackedScene; a null here means it has never been imported, and a null passes every other gate by being invisible to it" % path
		)


## The property that makes the per-mesh topology gate an exact per-asset gate
## for these files. See the header.
func test_every_prop_is_a_single_mesh() -> void:
	for path in PROPS.keys():
		var names := _mesh_node_names(path)
		assert_eq(
			names.size(), 1,
			"%s must hold exactly one mesh so the per-mesh budget is the asset's budget; it holds %d: %s" % [path, names.size(), ", ".join(names)]
		)


func test_every_prop_mesh_is_named_as_the_scene_expects() -> void:
	for path in MESH_NAMES.keys():
		var names := _mesh_node_names(path)
		assert_true(
			names.has(MESH_NAMES[path]),
			"%s must hold a mesh called %s; it holds %s" % [path, MESH_NAMES[path], ", ".join(names)]
		)


func test_every_prop_is_within_the_budget_its_brief_set() -> void:
	for path in PROPS.keys():
		var count := _triangles(path)
		assert_true(count > 0, "no triangles were counted in %s at all" % path)
		assert_true(
			count <= PROPS[path],
			"%s is %d triangles, over the %d it is allowed" % [path, count, PROPS[path]]
		)


## Rule 7: trees are `#131C30` and nothing else. One material means one draw
## call and no chance of a limb ending up a different value from the twig on it.
func test_every_tree_is_one_flat_near_black() -> void:
	var bible: Resource = load("res://data/palette/color_bible.tres")
	assert_not_null(bible, "the palette must load for this test to mean anything")
	var expected: Color = bible.structure_tones[3]
	for path in PROPS.keys():
		if not (path as String).begins_with("res://assets/models/vegetation/"):
			continue
		var probe := AssetProbeScript.probe(path)
		assert_eq(probe["error"], "", "%s could not be read: %s" % [path, probe["error"]])
		var materials: Array = probe["materials"]
		assert_eq(materials.size(), 1, "%s must use exactly one material, it uses %d" % [path, materials.size()])
		for entry in materials:
			var material: Material = entry["resource"]
			assert_true(
				material is StandardMaterial3D,
				"%s must resolve to a StandardMaterial3D, got %s" % [path, material]
			)
			assert_eq(
				(material as StandardMaterial3D).albedo_color, expected,
				"rule 7 makes a tree #131C30 -- the palette's structure_tones[3]; %s is %s" % [path, (material as StandardMaterial3D).albedo_color]
			)


## ---------------------------------------------------------------------------
## THE WIRE TAKES NO SNOW
## ---------------------------------------------------------------------------
## `assets/shaders/cel_flat.gdshader` settles snow on everything facing the sky
## with a 1.33 m pattern. This wire is 0.07 m square -- one to two pixels at the
## game camera -- so it cannot carry a pattern; it can only break into pieces,
## and a wire breaking into pieces reads as a MESH COMING APART. Measured on the
## shipped scene at one fixed camera: the line is solid at cover 0.362 and dotted
## at 0.620, and it begins going at 0.14.
##
## Snow does lie on a power line in life. It cannot be drawn at one pixel, and
## the honest reading at this framing is that the line does not take it. The wire
## says so in its palette slot name, which CelPainter turns into
## `snow_receptivity = 0`.
const WIRE_MODEL := "res://assets/models/props/power_wire.glb"
const BARE_SLOT_MARK := "_BARE"


func test_the_power_wire_refuses_the_settled_snow() -> void:
	var packed := ResourceLoader.load(WIRE_MODEL, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(packed is PackedScene, "%s must import as a PackedScene" % WIRE_MODEL)
	if not (packed is PackedScene):
		return
	var root: Node = (packed as PackedScene).instantiate()
	var slots := PackedStringArray()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var instance := node as MeshInstance3D
		if instance != null and instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				var material := instance.mesh.surface_get_material(surface)
				slots.append("" if material == null else material.resource_name)
		for child in node.get_children():
			pending.append(child)
	assert_true(slots.size() > 0, "%s holds no surface at all" % WIRE_MODEL)
	for slot in slots:
		assert_true(
			slot.contains(BARE_SLOT_MARK),
			"every surface of the wire must be on a %s palette slot or the line goes dotted; found '%s'"
				% [BARE_SLOT_MARK, slot]
		)
	root.free()
