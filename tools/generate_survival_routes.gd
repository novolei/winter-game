extends SceneTree

## Generates the four-leg exploration circuit and every authored beat on it.
## All meshes already ship in the project with their source textures and snow
## compatible cel material path; this script only gives them narrative places.

const ROUTES_DIR := "res://data/routes"
const NODES_DIR := "res://data/route_nodes"
const RouteScript := preload("res://src/definitions/survival_route_definition.gd")
const NodeScript := preload("res://src/definitions/survival_route_node_definition.gd")

static var ROUTES: Array[Dictionary] = [
	{
		"id": &"northern_supply_run", "name": "Northern supply run",
		"from": &"gas_station", "to": &"church_tower",
		"points": PackedVector2Array([
			Vector2(-38, 7), Vector2(-26, 10), Vector2(-9, 15),
			Vector2(9, 18), Vector2(27, 20), Vector2(42, 22),
		]),
	},
	{
		"id": &"eastern_pilgrim_track", "name": "Eastern pilgrim track",
		"from": &"church_tower", "to": &"transmission_tower",
		"points": PackedVector2Array([
			Vector2(42, 22), Vector2(45, 10), Vector2(44, -3),
			Vector2(45, -16), Vector2(43, -28), Vector2(42, -38),
		]),
	},
	{
		"id": &"southern_evacuation_road", "name": "Southern evacuation road",
		"from": &"transmission_tower", "to": &"logging_camp",
		"points": PackedVector2Array([
			Vector2(42, -38), Vector2(28, -42), Vector2(12, -41),
			Vector2(-5, -40), Vector2(-23, -38), Vector2(-40, -34),
		]),
	},
	{
		"id": &"western_timber_track", "name": "Western timber track",
		"from": &"logging_camp", "to": &"gas_station",
		"points": PackedVector2Array([
			Vector2(-40, -34), Vector2(-38, -25), Vector2(-37, -15),
			Vector2(-36, -6), Vector2(-37, 2), Vector2(-38, 7),
		]),
	},
]

static var NODES: Array[Dictionary] = [
	# North: supplies were moved from the petrol station toward the church, then
	# abandoned progressively rather than scattered uniformly.
	_node(&"petrol_barrel_west", &"northern_supply_run", 0, Vector3(-34, 0, 7), 18,
		"res://assets/models/props/synty_wooden_barrel.glb", &"petrol", 2),
	_node(&"north_road_sign", &"northern_supply_run", 1, Vector3(-25, 0, 10), -12,
		"res://assets/models/props/field_marker.glb"),
	_node(&"north_broken_gateway", &"northern_supply_run", 2, Vector3(-9, 0, 14), 74,
		"res://assets/models/props/synty_broken_gateway.glb"),
	_node(&"north_abandoned_crate", &"northern_supply_run", 3, Vector3(10, 0, 18), -23,
		"res://assets/models/props/synty_field_crate.glb", &"canned_stew", 5),
	_node(&"church_coal_cache", &"northern_supply_run", 4, Vector3(34, 0, 20), 11,
		"res://assets/models/props/supply_cache.glb", &"coal", 2),

	# East: shelter gives way to a blocked road, then to fuel cached below the
	# exposed tower. The gaps get longer as the route becomes less humane.
	_node(&"pilgrim_bedroll", &"eastern_pilgrim_track", 0, Vector3(43, 0, 12), -8,
		"res://assets/models/props/synty_refuge_bedroll.glb"),
	_node(&"east_road_sign", &"eastern_pilgrim_track", 1, Vector3(44, 0, 2), 91,
		"res://assets/models/props/field_marker.glb"),
	_node(&"east_supply_sacks", &"eastern_pilgrim_track", 2, Vector3(45, 0, -9), 14,
		"res://assets/models/props/synty_supply_sacks.glb", &"canned_stew", 5),
	_node(&"east_road_blockade", &"eastern_pilgrim_track", 3, Vector3(44, 0, -19), 89,
		"res://assets/models/props/synty_road_blockade.glb"),
	_node(&"tower_petrol_cache", &"eastern_pilgrim_track", 4, Vector3(43, 0, -30), -17,
		"res://assets/models/props/synty_tarped_cache.glb", &"petrol", 2),

	# South: a failed evacuation leaves the largest narrative objects on the
	# longest sightline. Coal is the difficult, valuable midpoint choice.
	_node(&"south_evacuation_cart", &"southern_evacuation_road", 0, Vector3(30, 0, -41), 78,
		"res://assets/models/props/evacuation_cart.glb"),
	_node(&"south_departure_pack", &"southern_evacuation_road", 1, Vector3(18, 0, -42), -31,
		"res://assets/models/props/departure_pack.glb", &"canned_stew", 4),
	_node(&"south_coal_cache", &"southern_evacuation_road", 2, Vector3(4, 0, -40), 7,
		"res://assets/models/props/synty_evacuation_cache.glb", &"coal", 2),
	_node(&"south_broken_gateway", &"southern_evacuation_road", 3, Vector3(-14, 0, -39), 83,
		"res://assets/models/props/synty_broken_gateway.glb"),
	_node(&"timber_road_sign", &"southern_evacuation_road", 4, Vector3(-29, 0, -36), -70,
		"res://assets/models/props/field_marker.glb"),

	# West: the route becomes a working timber story near camp. Two smaller wood
	# finds bookend tools and a snow-filled drum, giving the return journey a cadence.
	_node(&"logging_wood_station", &"western_timber_track", 0, Vector3(-39, 0, -29), 12,
		"res://assets/models/props/synty_woodwork_station.glb"),
	_node(&"logging_firewood", &"western_timber_track", 1, Vector3(-38, 0, -25), -14,
		"res://assets/models/props/woodpile.glb", &"firewood", 4),
	_node(&"west_chopping_block", &"western_timber_track", 2, Vector3(-37, 0, -17), 29,
		"res://assets/models/props/chopping_block.glb"),
	_node(&"west_snow_barrel", &"western_timber_track", 3, Vector3(-36, 0, -8), -9,
		"res://assets/models/props/synty_wooden_barrel.glb", &"snow", 14),
	_node(&"gas_firewood", &"western_timber_track", 4, Vector3(-37, 0, 1), 21,
		"res://assets/models/props/woodpile.glb", &"firewood", 2),
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROUTES_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NODES_DIR))
	var failed := false
	for row in ROUTES:
		var route: SurvivalRouteDefinition = RouteScript.new()
		route.id = row["id"]
		route.display_name = row["name"]
		route.from_beacon = row["from"]
		route.to_beacon = row["to"]
		route.points = row["points"]
		failed = _save(route, "%s/%s.tres" % [ROUTES_DIR, route.id]) or failed
	for row in NODES:
		var node: SurvivalRouteNodeDefinition = NodeScript.new()
		node.id = row["id"]
		node.route_id = row["route"]
		node.sequence = row["sequence"]
		node.world_position = row["position"]
		node.yaw_degrees = row["yaw"]
		node.model_scene = load(row["model"]) as PackedScene
		node.item_id = row["item"]
		node.item_count = row["count"]
		failed = _save(node, "%s/%s.tres" % [NODES_DIR, node.id]) or failed
	quit(1 if failed else 0)


static func _node(
	id: StringName, route: StringName, sequence: int, position: Vector3,
	yaw: float, model: String, item: StringName = &"", count: int = 0
) -> Dictionary:
	return {
		"id": id, "route": route, "sequence": sequence, "position": position,
		"yaw": yaw, "model": model, "item": item, "count": count,
	}


func _save(resource: Resource, path: String) -> bool:
	var error := ResourceSaver.save(resource, path)
	print("generate_survival_routes: %s -> %d" % [path, error])
	return error != OK
