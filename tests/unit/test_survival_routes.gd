extends TestCase

const LayerScript := preload("res://src/systems/survival_route_layer.gd")
const NodeScript := preload("res://src/entities/survival_route_node.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")

class FakeEconomy extends RefCounted:
	var held: Dictionary = {}

	func add(item_id: StringName, count := 1) -> int:
		held[item_id] = int(held.get(item_id, 0)) + count
		return held[item_id]

	func count_of(item_id: StringName) -> int:
		return int(held.get(item_id, 0))


class FakeTrackMask extends RefCounted:
	var paths: Array = []

	func bake_path(points, radius, strength, core, irregularity, seed) -> void:
		paths.append([points, radius, strength, core, irregularity, seed])


var _bus: Node = null
var _payload = null


func after_each() -> void:
	if _bus != null:
		_bus.free()
		_bus = null
	_payload = null


func _record(payload) -> void:
	_payload = payload


func _routes() -> Array[SurvivalRouteDefinition]:
	var result: Array[SurvivalRouteDefinition] = []
	for path in _files("res://data/routes"):
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is SurvivalRouteDefinition:
			result.append(resource)
	return result


func _nodes() -> Array[SurvivalRouteNodeDefinition]:
	var result: Array[SurvivalRouteNodeDefinition] = []
	for path in _files("res://data/route_nodes"):
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is SurvivalRouteNodeDefinition:
			result.append(resource)
	return result


func _files(directory_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	var names := directory.get_files()
	names.sort()
	for name in names:
		if name.ends_with(".tres"):
			result.append(directory_path.path_join(name))
	return result


func test_four_valid_routes_form_one_closed_landmark_circuit() -> void:
	var routes := _routes()
	assert_eq(routes.size(), 4)
	var by_start: Dictionary = {}
	for route in routes:
		assert_true(route.is_valid(), "%s is invalid" % route.id)
		assert_false(by_start.has(route.from_beacon), "two legs leave %s" % route.from_beacon)
		by_start[route.from_beacon] = route
	var at: StringName = &"gas_station"
	var visited: Dictionary = {}
	for _step in 4:
		assert_true(by_start.has(at), "the circuit stops at %s" % at)
		if not by_start.has(at):
			return
		var route: SurvivalRouteDefinition = by_start[at]
		visited[route.id] = true
		at = route.to_beacon
	assert_eq(at, &"gas_station")
	assert_eq(visited.size(), 4)


func test_every_route_bends_and_the_whole_loop_stays_walkable_in_scope() -> void:
	var length := 0.0
	for route in _routes():
		assert_true(route.points.size() >= 5, "%s is a straight technical link" % route.id)
		for index in range(route.points.size() - 1):
			length += route.points[index].distance_to(route.points[index + 1])
	assert_true(length >= 240.0 and length <= 300.0,
		"the authored circuit is %.1f m rather than one purposeful expedition" % length)


func test_twenty_route_beats_are_valid_and_belong_to_a_real_leg() -> void:
	var routes: Dictionary = {}
	for route in _routes():
		routes[route.id] = true
	var nodes := _nodes()
	assert_eq(nodes.size(), 20)
	for node in nodes:
		assert_true(node.is_valid(), "%s is invalid" % node.id)
		assert_true(routes.has(node.route_id), "%s belongs to no route" % node.id)


func test_each_leg_has_five_ordered_story_beats() -> void:
	var sequences: Dictionary = {}
	for node in _nodes():
		if not sequences.has(node.route_id):
			sequences[node.route_id] = []
		sequences[node.route_id].append(node.sequence)
	assert_eq(sequences.size(), 4)
	for route_id in sequences:
		var order: Array = sequences[route_id]
		order.sort()
		assert_eq(order, [0, 1, 2, 3, 4], "%s has no five-beat cadence" % route_id)


func test_pickups_are_finite_and_cover_fuel_and_the_seven_day_provisions() -> void:
	var pickups := 0
	var forms: Dictionary = {}
	for node in _nodes():
		if not node.is_pickup():
			continue
		pickups += 1
		forms[node.item_id] = int(forms.get(node.item_id, 0)) + node.item_count
	assert_eq(pickups, 10)
	assert_eq(forms.get(&"firewood", 0), 6)
	assert_eq(forms.get(&"petrol", 0), 4)
	assert_eq(forms.get(&"coal", 0), 4)
	assert_eq(forms.get(&"canned_stew", 0), 14)
	assert_eq(forms.get(&"snow", 0), 14)


func test_every_pickup_names_an_item_the_shared_economy_ships() -> void:
	var economy := FuelEconomyScript.new()
	economy.load_from_directory()
	for node in _nodes():
		if node.is_pickup():
			assert_true(economy.has_item(node.item_id), "%s cannot enter the ledger" % node.item_id)
	economy.free()


func test_collecting_one_node_adds_exactly_its_authored_count_once() -> void:
	var definition := SurvivalRouteNodeDefinition.new()
	definition.id = &"probe"
	definition.route_id = &"probe_route"
	definition.item_id = &"firewood"
	definition.item_count = 2
	var economy := FakeEconomy.new()
	var node: SurvivalRouteNode = NodeScript.new()
	node.definition = definition
	node.set_fuel_economy(economy)
	assert_true(node.collect())
	assert_eq(economy.count_of(&"firewood"), 2)
	assert_false(node.collect(), "a hidden pile was collected twice")
	assert_eq(economy.count_of(&"firewood"), 2)
	node.free()


func test_run_reset_restores_a_collected_route_pickup() -> void:
	var definition := SurvivalRouteNodeDefinition.new()
	definition.id = &"probe"
	definition.route_id = &"probe_route"
	definition.item_id = &"firewood"
	definition.item_count = 2
	var economy := FakeEconomy.new()
	var node: SurvivalRouteNode = NodeScript.new()
	node.definition = definition
	node.set_fuel_economy(economy)
	assert_true(node.collect())
	node.reset_for_run()
	assert_false(node.is_collected())
	assert_true(node.visible)
	assert_true(node.collect(), "the pickup stayed exhausted in the next attempt")
	assert_eq(economy.count_of(&"firewood"), 4)
	node.free()


func test_route_layer_consumes_the_shared_run_reset_event() -> void:
	_bus = EventBusScript.new()
	var economy := FakeEconomy.new()
	var layer: SurvivalRouteLayer = LayerScript.new()
	layer.set_event_bus(_bus)
	layer.set_fuel_economy(economy)
	layer.load_routes_from_directory()
	layer.load_nodes_from_directory()
	layer.spawn_missing()
	var pickup: SurvivalRouteNode = null
	for candidate in layer.route_nodes():
		if candidate.definition.is_pickup():
			pickup = candidate
			break
	assert_not_null(pickup)
	if pickup != null:
		assert_true(pickup.collect())
		_bus.emit_event(&"game.run_reset", {"seed": 1729})
		assert_false(pickup.is_collected(), "the route layer ignored the new-run boundary")
	layer.free()


func test_a_pickup_publishes_what_was_found_and_where() -> void:
	var definition := SurvivalRouteNodeDefinition.new()
	definition.id = &"probe"
	definition.route_id = &"north"
	definition.world_position = Vector3(4.0, 0.0, -2.0)
	definition.item_id = &"petrol"
	definition.item_count = 1
	_bus = EventBusScript.new()
	_bus.subscribe(&"item.picked_up", _record)
	var node: SurvivalRouteNode = NodeScript.new()
	node.definition = definition
	node.position = definition.world_position
	node.set_fuel_economy(FakeEconomy.new())
	node.set_event_bus(_bus)
	assert_true(node.collect())
	assert_not_null(_payload)
	if _payload != null:
		assert_eq(_payload["item_id"], &"petrol")
		assert_eq(_payload["route_id"], &"north")
		assert_eq(_payload["count"], 1)
		assert_eq(_payload["kind"], &"pickup")
		assert_eq(_payload["label"], "Petrol")
		assert_eq(_payload["icon_id"], &"petrol")
	node.free()


func test_a_dressing_node_can_never_mint_inventory() -> void:
	var definition := SurvivalRouteNodeDefinition.new()
	definition.id = &"sign"
	definition.route_id = &"north"
	var economy := FakeEconomy.new()
	var node: SurvivalRouteNode = NodeScript.new()
	node.definition = definition
	node.set_fuel_economy(economy)
	assert_false(node.collect())
	assert_eq(economy.held.size(), 0)
	node.free()


func test_the_generic_layer_discovers_content_without_an_id_list() -> void:
	var layer: SurvivalRouteLayer = LayerScript.new()
	assert_eq(layer.load_routes_from_directory(), 4)
	assert_eq(layer.load_nodes_from_directory(), 20)
	assert_eq(layer.pickup_count(), 10)
	assert_true(layer.total_route_length_m() >= 240.0)
	layer.free()


func test_each_route_bakes_one_bed_and_two_ruts() -> void:
	var layer: SurvivalRouteLayer = LayerScript.new()
	layer.load_routes_from_directory()
	var tracks := FakeTrackMask.new()
	assert_eq(layer.bake_route_traces(tracks), 4)
	assert_eq(tracks.paths.size(), 12)
	for index in range(0, tracks.paths.size(), 3):
		assert_true((tracks.paths[index][0] as Array).size() >= 5)
		assert_true(float(tracks.paths[index][1]) > float(tracks.paths[index + 1][1]))
	layer.free()


func test_the_snow_profile_protects_all_four_new_travel_corridors() -> void:
	var profile := load("res://data/snow/valley_profile.tres") as SnowFieldProfile
	assert_not_null(profile)
	if profile != null:
		assert_eq(profile.protected_routes.size(), 10,
			"the four visible routes and traversable snow have drifted apart")


func test_main_scene_runs_the_survival_route_layer() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("res://src/systems/survival_route_layer.gd"))
	assert_true(source.contains("[node name=\"SurvivalRoutes\""))


func test_route_content_stays_inside_the_bounded_runtime_budget() -> void:
	var total_points := 0
	for route in _routes():
		total_points += route.points.size()
	assert_true(_nodes().size() <= 24, "the route layer became a prop scatter")
	assert_true(total_points <= 28, "the static trail became an over-tessellated spline")
