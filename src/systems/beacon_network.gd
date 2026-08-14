class_name BeaconNetwork
extends Node

## The valley-wide state of the five lamps.
##
## Definitions are discovered from data/beacons, entities are spawned from one
## generic scene, and all cross-system input arrives through EventBus or
## ServiceRegistry. Weather knows only that its payload asks for extinguishes;
## it never knows a Beacon or this network exists.

const SERVICE := &"beacon_network"
const DEFINITIONS_DIRECTORY := "res://data/beacons"
const BEACON_SCENE := preload("res://scenes/entities/beacon/beacon.tscn")
const EVENT_WEATHER_ARRIVED := &"weather.arrived"
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"
const EVENT_FINAL_STATE := &"beacons.final_state"

@export var definitions_directory := DEFINITIONS_DIRECTORY
@export var random_seed := 20260813

var _definitions: Dictionary = {}
var _order: Array[StringName] = []
var _beacons: Dictionary = {}
var _day := 1
var _bus = null
var _wind = null
var _economy = null
var _registry = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_resolve()
	if _registry != null:
		_registry.register(SERVICE, self)
	_subscribe()
	_rng.seed = random_seed
	load_from_directory(definitions_directory)
	spawn_missing()
	set_day(_day)


func _exit_tree() -> void:
	_unsubscribe()
	if _registry != null and _registry.get_service(SERVICE) == self:
		_registry.unregister(SERVICE)


func set_event_bus(bus) -> void:
	_unsubscribe()
	_bus = bus
	_subscribe()


func set_wind_system(wind) -> void:
	_wind = wind


func set_fuel_economy(economy) -> void:
	_economy = economy
	for beacon in _beacons.values():
		beacon.set_fuel_economy(_economy)


func load_from_directory(path := DEFINITIONS_DIRECTORY) -> int:
	var loaded: Array[BeaconDefinition] = []
	var directory := DirAccess.open(path)
	if directory == null:
		load_definitions(loaded)
		return 0
	var files := directory.get_files()
	files.sort()
	for raw in files:
		var file_name: String = raw
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(path.path_join(file_name))
		if resource is BeaconDefinition:
			loaded.append(resource)
	load_definitions(loaded)
	return _order.size()


func load_definitions(definitions: Array[BeaconDefinition]) -> void:
	_definitions.clear()
	_order.clear()
	for definition in definitions:
		if definition == null or not definition.is_valid() or _definitions.has(definition.id):
			continue
		_definitions[definition.id] = definition
		_order.append(definition.id)


func definition(id: StringName) -> BeaconDefinition:
	return _definitions.get(id, null)


func beacon_ids() -> Array[StringName]:
	return _order.duplicate()


func beacon(id: StringName) -> Beacon:
	return _beacons.get(id, null)


func beacons() -> Array[Beacon]:
	var result: Array[Beacon] = []
	for id in _order:
		var found: Beacon = _beacons.get(id, null)
		if found != null:
			result.append(found)
	return result


func spawn_missing() -> int:
	var spawned := 0
	for id in _order:
		if _beacons.has(id):
			continue
		var node := BEACON_SCENE.instantiate() as Beacon
		node.name = String(id).to_pascal_case()
		node.definition = _definitions[id]
		node.set_fuel_economy(_economy)
		node.set_event_bus(_bus)
		add_child(node)
		_beacons[id] = node
		spawned += 1
	return spawned


func set_day(day: int) -> void:
	_day = maxi(day, 1)
	for lamp in beacons():
		lamp.set_unlocked(lamp.definition.unlock_day <= _day)


func lit_count() -> int:
	var count := 0
	for lamp in beacons():
		if lamp.is_lit():
			count += 1
	return count


func total_count() -> int:
	return _beacons.size()


func all_lit() -> bool:
	return total_count() > 0 and lit_count() == total_count()


## Returns how many were actually lost. If only two lamps burn, a request for
## three extinguishes two and reports two rather than pretending at a guarantee
## the current world state could not satisfy.
func extinguish_minimum(count: int, cause: StringName = &"weather") -> int:
	var candidates: Array[Beacon] = []
	for lamp in beacons():
		if lamp.is_lit():
			candidates.append(lamp)
	for index in range(candidates.size() - 1, 0, -1):
		var swap := _rng.randi_range(0, index)
		var held := candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	var extinguished := 0
	for lamp in candidates:
		if extinguished >= maxi(count, 0):
			break
		if lamp.extinguish(cause):
			extinguished += 1
	return extinguished


func advance(delta: float) -> void:
	_resolve()
	var strength := 0.0
	var velocity := Vector3.ZERO
	if _wind != null and _wind.has_method("strength"):
		strength = float(_wind.strength())
	if _wind != null and _wind.has_method("velocity"):
		velocity = _wind.velocity()
	for lamp in beacons():
		lamp.set_weather_wind(strength, velocity)
		lamp.try_wind_extinguish(strength, delta, _rng.randf())


func _process(delta: float) -> void:
	advance(delta)


func _on_weather_arrived(payload) -> void:
	if not (payload is Dictionary) or not bool(payload.get("extinguishes_beacons", false)):
		return
	extinguish_minimum(int(payload.get("min_beacons_extinguished", 0)), &"blizzard")


func _on_day_started(payload) -> void:
	set_day(int(payload))


func _on_run_finished(_payload) -> void:
	if _bus != null:
		_bus.emit_event(EVENT_FINAL_STATE, {
			"lit": lit_count(),
			"total": total_count(),
			"all_lit": all_lit(),
		})


func _resolve() -> void:
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
	if _registry != null:
		if _wind == null:
			_wind = _registry.get_service(&"wind")
		if _economy == null:
			_economy = _registry.get_service(&"fuel_economy")


func _subscribe() -> void:
	if _bus == null:
		return
	_bus.subscribe(EVENT_WEATHER_ARRIVED, _on_weather_arrived)
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_RUN_FINISHED, _on_run_finished)


func _unsubscribe() -> void:
	if _bus == null:
		return
	_bus.unsubscribe(EVENT_WEATHER_ARRIVED, _on_weather_arrived)
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_RUN_FINISHED, _on_run_finished)
