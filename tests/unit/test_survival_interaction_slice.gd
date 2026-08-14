extends TestCase

## A lightweight shipped-content slice: the west petrol barrel naturally sits
## inside the gas-station beacon's interaction reach. One command must collect
## that route reward once; only the following command may spend it on the lamp.

const RouteScene: PackedScene = preload("res://scenes/entities/survival_route_node.tscn")
const BeaconScene: PackedScene = preload("res://scenes/entities/beacon/beacon.tscn")
const DirectorScript := preload("res://src/ui/interaction_director.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const PICKUP_PATH := "res://data/route_nodes/petrol_barrel_west.tres"
const BEACON_PATH := "res://data/beacons/gas_station.tres"
const CAPTURED_EVENTS: Array[StringName] = [
	&"interaction.activated",
	&"item.picked_up",
	&"beacon.fueled",
	&"beacon.lit",
]

var _bus: Node = null
var _economy: Node = null
var _director = null
var _occupant: Node3D = null
var _pickup: SurvivalRouteNode = null
var _beacon: Beacon = null
var _events: Array[Dictionary] = []


func before_each() -> void:
	_bus = EventBusScript.new()
	_economy = FuelEconomyScript.new()
	_occupant = Node3D.new()
	_director = DirectorScript.new()
	_director.set_event_bus(_bus)
	_director.set_occupant(_occupant)
	for event_name in CAPTURED_EVENTS:
		_bus.subscribe(event_name, _record.bind(event_name))


func after_each() -> void:
	# Entities leave the bus before the director, and the bus dies last.
	for node in [_pickup, _beacon, _director, _occupant, _economy, _bus]:
		if node != null and is_instance_valid(node):
			node.free()
	_pickup = null
	_beacon = null
	_director = null
	_occupant = null
	_economy = null
	_bus = null
	_events.clear()


func _record(payload, event_name: StringName) -> void:
	_events.append({
		"event": event_name,
		"payload": payload.duplicate(true) if payload is Dictionary else payload,
	})


func _payloads(event_name: StringName) -> Array:
	var result: Array = []
	for record in _events:
		if StringName(record.get("event", &"")) == event_name:
			result.append(record.get("payload"))
	return result


func _contains_object(value) -> bool:
	if value is Object or value is Callable:
		return true
	if value is Dictionary:
		for key in value:
			if _contains_object(key) or _contains_object(value[key]):
				return true
	if value is Array:
		for nested in value:
			if _contains_object(nested):
				return true
	return false


func test_shipped_pickup_fuels_only_one_overlapping_beacon() -> void:
	assert_true(_economy.load_from_directory() > 0,
		"the vertical slice did not load the shipped item catalogue")
	var pickup_definition := ResourceLoader.load(
		PICKUP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as SurvivalRouteNodeDefinition
	var beacon_definition := ResourceLoader.load(
		BEACON_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as BeaconDefinition
	assert_not_null(pickup_definition, "the shipped route pickup is missing")
	assert_not_null(beacon_definition, "the shipped gas-station beacon is missing")
	if pickup_definition == null or beacon_definition == null:
		return
	var item_definition := _economy.definition_of(pickup_definition.item_id) as ItemDefinition
	assert_not_null(item_definition, "the shipped pickup names no shipped item")
	if item_definition == null:
		return
	assert_true(item_definition.fuel_value > 0.0,
		"the route reward cannot feed the data-driven fuel economy")
	if item_definition.fuel_value <= 0.0:
		return

	_pickup = RouteScene.instantiate() as SurvivalRouteNode
	_beacon = BeaconScene.instantiate() as Beacon
	assert_not_null(_pickup, "the shipped route-node scene did not instantiate")
	assert_not_null(_beacon, "the shipped beacon scene did not instantiate")
	if _pickup == null or _beacon == null:
		return
	_pickup.configure(pickup_definition)
	_pickup.set_fuel_economy(_economy)
	_pickup.set_occupant(_occupant)
	_pickup.set_event_bus(_bus)
	_beacon.configure(beacon_definition)
	_beacon.set_fuel_economy(_economy)
	_beacon.set_occupant(_occupant)
	_beacon.set_event_bus(_bus)
	_beacon.set_unlocked(true)

	# The authored centers are four metres apart and their authored Areas overlap.
	_occupant.position = pickup_definition.world_position
	assert_true(_occupant.position.distance_to(_pickup.position)
		<= pickup_definition.interaction_radius_m)
	assert_true(_occupant.position.distance_to(_beacon.position)
		<= beacon_definition.interaction_radius_m,
		"the test no longer represents a real overlapping shipped interaction")
	_beacon._on_body_entered(_occupant)
	_pickup._on_body_entered(_occupant)
	_director.reconsider()

	var pickup_offer_id := StringName("pickup:%s" % String(pickup_definition.id))
	var beacon_offer_id := StringName("beacon:%s" % String(beacon_definition.id))
	assert_eq(_director.offer_count(), 2,
		"the real overlap did not produce both value-only candidates")
	assert_eq(_director.focused_id(), pickup_offer_id,
		"the nearest route reward did not win the overlap")
	assert_false(_contains_object(_director.focused_offer()),
		"the pickup offer leaked a live scene object")
	assert_eq(_economy.count_of(pickup_definition.item_id), 0)
	assert_true(_director.activate_focused())
	assert_true(_pickup.is_collected())
	assert_eq(_economy.count_of(pickup_definition.item_id), pickup_definition.item_count,
		"one pickup interaction did not add exactly its authored count")
	assert_false(_beacon.is_lit(),
		"the overlapping beacon also consumed the pickup's command")
	assert_almost_eq(_beacon.fuel_remaining(), 0.0, 0.001)
	assert_eq(_payloads(&"item.picked_up").size(), 1)

	# Even a repeated domain call cannot mint the hidden reward a second time.
	assert_false(_pickup.collect(), "the same shipped pickup was collectable twice")
	assert_eq(_economy.count_of(pickup_definition.item_id), pickup_definition.item_count)
	assert_eq(_payloads(&"item.picked_up").size(), 1,
		"the rejected duplicate pickup published a second success")

	# Inventory changed while the player remained inside the beacon Area. Its
	# normal process tick refreshes the existing offer without a leave/re-enter.
	_beacon._process(0.0)
	_director.reconsider()
	assert_eq(_director.offer_count(), 1)
	assert_eq(_director.focused_id(), beacon_offer_id)
	assert_true(bool(_director.focused_offer().get("enabled", false)),
		"the beacon stayed disabled after the real pickup reached FuelEconomy")
	assert_false(_contains_object(_director.focused_offer()),
		"the beacon offer leaked a live scene object")

	var wanted := minf(beacon_definition.refill_request_seconds, beacon_definition.fuel_capacity)
	var expected_spent := mini(
		pickup_definition.item_count,
		int(ceil(wanted / item_definition.fuel_value))
	)
	var expected_banked := float(expected_spent) * item_definition.fuel_value
	assert_true(expected_spent > 0, "the shipped interaction did not demand any fuel")
	assert_true(_director.activate_focused())
	assert_eq(_economy.count_of(pickup_definition.item_id),
		pickup_definition.item_count - expected_spent,
		"one beacon command did not debit exactly the data-authored fuel cost")
	assert_almost_eq(_beacon.fuel_remaining(), expected_banked, 0.001,
		"the whole-item fuel surplus was not banked in the beacon")
	assert_true(_beacon.is_lit(), "the beacon took fuel but did not actually light")
	assert_false(_pickup.visible, "lighting the beacon resurrected its spent pickup")

	var activations := _payloads(&"interaction.activated")
	assert_eq(activations.size(), 2,
		"two deliberate interactions did not produce exactly two commands")
	if activations.size() == 2:
		assert_eq((activations[0] as Dictionary).get("id"), pickup_offer_id)
		assert_eq((activations[1] as Dictionary).get("id"), beacon_offer_id)
	assert_eq(_payloads(&"beacon.fueled").size(), 1)
	assert_eq(_payloads(&"beacon.lit").size(), 1)
	for record in _events:
		assert_false(_contains_object(record.get("payload")),
			"%s crossed EventBus with a live Object or Callable" % record.get("event"))
