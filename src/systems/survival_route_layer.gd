class_name SurvivalRouteLayer
extends Node3D

## Builds the four-leg exploration circuit from Resources. The layer owns no
## route ids, no prop list and no item table: adding or rearranging content is a
## data regeneration, while this stays one bounded runtime batch.

const SERVICE := &"survival_routes"
const DEFAULT_ROUTES_DIRECTORY := "res://data/routes"
const DEFAULT_NODES_DIRECTORY := "res://data/route_nodes"
const NODE_SCENE := preload("res://scenes/entities/survival_route_node.tscn")
const EVENT_RUN_RESET := &"game.run_reset"

@export var routes_directory := DEFAULT_ROUTES_DIRECTORY
@export var nodes_directory := DEFAULT_NODES_DIRECTORY

var _routes: Dictionary = {}
var _route_order: Array[StringName] = []
var _definitions: Dictionary = {}
var _node_order: Array[StringName] = []
var _nodes: Dictionary = {}
var _registry = null
var _economy = null
var _bus = null
var _subscribed := false


func _ready() -> void:
	_resolve_services()
	_subscribe()
	if _registry != null:
		_registry.register(SERVICE, self)
	load_routes_from_directory(routes_directory)
	load_nodes_from_directory(nodes_directory)
	spawn_missing()
	bake_route_traces()


func _exit_tree() -> void:
	_unsubscribe()
	if _registry != null and _registry.get_service(SERVICE) == self:
		_registry.unregister(SERVICE)


func set_fuel_economy(economy) -> void:
	_economy = economy
	for node in route_nodes():
		node.set_fuel_economy(_economy)


func set_event_bus(bus) -> void:
	_unsubscribe()
	_bus = bus
	_subscribe()
	for node in route_nodes():
		node.set_event_bus(_bus)


func reset_for_run() -> void:
	for node in route_nodes():
		node.reset_for_run()


func _on_run_reset(_payload) -> void:
	reset_for_run()


func _subscribe() -> void:
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_RUN_RESET, _on_run_reset)
	_subscribed = true


func _unsubscribe() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_RUN_RESET, _on_run_reset)
	_subscribed = false


func load_routes_from_directory(path := DEFAULT_ROUTES_DIRECTORY) -> int:
	var loaded: Array[SurvivalRouteDefinition] = []
	for resource in _resources_at(path):
		if resource is SurvivalRouteDefinition:
			loaded.append(resource)
	load_routes(loaded)
	return _route_order.size()


func load_nodes_from_directory(path := DEFAULT_NODES_DIRECTORY) -> int:
	var loaded: Array[SurvivalRouteNodeDefinition] = []
	for resource in _resources_at(path):
		if resource is SurvivalRouteNodeDefinition:
			loaded.append(resource)
	load_node_definitions(loaded)
	return _node_order.size()


func load_routes(definitions: Array[SurvivalRouteDefinition]) -> void:
	_routes.clear()
	_route_order.clear()
	for definition in definitions:
		if definition == null or not definition.is_valid() or _routes.has(definition.id):
			continue
		_routes[definition.id] = definition
		_route_order.append(definition.id)


func load_node_definitions(definitions: Array[SurvivalRouteNodeDefinition]) -> void:
	_definitions.clear()
	_node_order.clear()
	definitions.sort_custom(func(a: SurvivalRouteNodeDefinition, b: SurvivalRouteNodeDefinition) -> bool:
		if a.route_id == b.route_id and a.sequence == b.sequence:
			return String(a.id) < String(b.id)
		if a.route_id == b.route_id:
			return a.sequence < b.sequence
		return String(a.route_id) < String(b.route_id)
	)
	for definition in definitions:
		if definition == null or not definition.is_valid() or _definitions.has(definition.id):
			continue
		if not _routes.has(definition.route_id):
			continue
		_definitions[definition.id] = definition
		_node_order.append(definition.id)


func route_ids() -> Array[StringName]:
	return _route_order.duplicate()


func route(id: StringName) -> SurvivalRouteDefinition:
	return _routes.get(id, null)


func route_node_ids() -> Array[StringName]:
	return _node_order.duplicate()


func route_node(id: StringName) -> SurvivalRouteNode:
	return _nodes.get(id, null)


func route_nodes() -> Array[SurvivalRouteNode]:
	var result: Array[SurvivalRouteNode] = []
	for id in _node_order:
		var found: SurvivalRouteNode = _nodes.get(id, null)
		if found != null and is_instance_valid(found):
			result.append(found)
	return result


func pickup_count() -> int:
	var total := 0
	for definition in _definitions.values():
		if definition.is_pickup():
			total += 1
	return total


func spawn_missing() -> int:
	var spawned := 0
	for id in _node_order:
		if _nodes.has(id):
			continue
		var node := NODE_SCENE.instantiate() as SurvivalRouteNode
		if node == null:
			continue
		node.name = String(id).to_pascal_case()
		node.definition = _definitions[id]
		node.set_fuel_economy(_economy)
		node.set_event_bus(_bus)
		add_child(node)
		_nodes[id] = node
		spawned += 1
	return spawned


func bake_route_traces(track_mask = null) -> int:
	if track_mask == null:
		_resolve_services()
		track_mask = _registry.get_service(&"track_mask") if _registry != null else null
	if track_mask == null or not track_mask.has_method("bake_path"):
		return 0
	var baked := 0
	for id in _route_order:
		var definition: SurvivalRouteDefinition = _routes[id]
		var points := definition.world_points()
		track_mask.bake_path(
			points, definition.bed_half_width_m, definition.bed_strength,
			0.16, definition.edge_irregularity, float(baked) * 19.0
		)
		for side in [-1.0, 1.0]:
			track_mask.bake_path(
				_offset(points, definition.rut_gauge_m * side),
				definition.rut_radius_m, definition.rut_strength,
				0.38, definition.edge_irregularity * 0.55,
				43.0 + float(baked) * 23.0 + side * 7.0
			)
		baked += 1
	return baked


func total_route_length_m() -> float:
	var total := 0.0
	for id in _route_order:
		var points: PackedVector2Array = (_routes[id] as SurvivalRouteDefinition).points
		for index in range(points.size() - 1):
			total += points[index].distance_to(points[index + 1])
	return total


func _offset(points: Array[Vector3], distance: float) -> Array[Vector3]:
	var shifted: Array[Vector3] = []
	for index in range(points.size()):
		var behind := points[maxi(index - 1, 0)]
		var ahead := points[mini(index + 1, points.size() - 1)]
		var run := Vector2(ahead.x - behind.x, ahead.z - behind.z)
		if run.length_squared() <= 0.0001:
			shifted.append(points[index])
			continue
		var across := run.normalized().orthogonal() * distance
		shifted.append(points[index] + Vector3(across.x, 0.0, across.y))
	return shifted


func _resources_at(path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	var files := directory.get_files()
	files.sort()
	for raw in files:
		var file_name: String = raw
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(path.path_join(file_name))
		if resource != null:
			result.append(resource)
	return result


func _resolve_services() -> void:
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
	if _registry != null and _economy == null:
		_economy = _registry.get_service(&"fuel_economy")
