extends TestCase

const BeaconScript := preload("res://src/entities/beacon/beacon.gd")
const NetworkScript := preload("res://src/systems/beacon_network.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const PALETTE: ColorBible = preload("res://data/palette/color_bible.tres")
const IDS: Array[StringName] = [
	&"farmhouse_chimney", &"gas_station", &"church_tower", &"logging_camp", &"transmission_tower",
]

class FakeEconomy extends RefCounted:
	var award := 0.0
	var requests: Array[float] = []

	func draw_burn_seconds(wanted: float) -> float:
		requests.append(wanted)
		return award

	func fuel_seconds() -> float:
		return award


class FakeSurvival extends RefCounted:
	var modifiers: Dictionary = {}

	func remove_source(_source: StringName) -> void:
		modifiers.clear()

	func push_modifier(target: StringName, _source: StringName, _operation, amount: float) -> void:
		modifiers[target] = amount


var _network: BeaconNetwork = null
var _bus: Node = null
var _payload = null


func after_each() -> void:
	if _network != null:
		_network.free()
		_network = null
	if _bus != null:
		_bus.free()
		_bus = null
	_payload = null


func _definition(id: StringName, day := 1) -> BeaconDefinition:
	var definition := BeaconDefinition.new()
	definition.id = id
	definition.display_name = String(id)
	definition.unlock_day = day
	definition.fuel_capacity = 900.0
	definition.refill_request_seconds = 900.0
	definition.burn_rate = 1.0
	return definition


func _lamp(definition: BeaconDefinition = null) -> Beacon:
	var lamp := BeaconScript.new() as Beacon
	lamp.definition = definition if definition != null else _definition(&"probe")
	return lamp


func _build_network() -> BeaconNetwork:
	_bus = EventBusScript.new()
	_network = NetworkScript.new() as BeaconNetwork
	_network.set_event_bus(_bus)
	var definitions: Array[BeaconDefinition] = []
	for index in IDS.size():
		definitions.append(_definition(IDS[index], index + 1))
	_network.load_definitions(definitions)
	_network.spawn_missing()
	return _network


func _record(payload) -> void:
	_payload = payload


func test_the_five_gdd_beacons_ship_as_valid_data() -> void:
	var landmark_count := 0
	for id in IDS:
		var definition := ResourceLoader.load(
			"res://data/beacons/%s.tres" % String(id),
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as BeaconDefinition
		assert_not_null(definition, "beacon '%s' is missing" % id)
		if definition == null:
			continue
		assert_eq(definition.id, id)
		assert_true(definition.is_valid(), "beacon '%s' has invalid tuning" % id)
		var authored := PackedStringArray()
		for property in definition.get_property_list():
			authored.append(String(property["name"]))
		assert_true(authored.has("warm_radius_m"),
			"beacon '%s' has no authored full-warm radius" % id)
		assert_true(authored.has("warm_falloff_m"),
			"beacon '%s' has no authored warmth falloff" % id)
		if definition.landmark_scene != null:
			landmark_count += 1
	assert_eq(landmark_count, 4, "the farmhouse should reuse Main and the other four should carry landmarks")


func test_the_unlock_order_is_one_new_destination_per_day() -> void:
	for index in IDS.size():
		var definition := load("res://data/beacons/%s.tres" % String(IDS[index])) as BeaconDefinition
		assert_not_null(definition)
		if definition != null:
			assert_eq(definition.unlock_day, index + 1)


func test_refuelling_spends_shared_fuel_and_preserves_a_whole_items_surplus() -> void:
	var economy := FakeEconomy.new()
	economy.award = 1800.0
	var lamp := _lamp()
	lamp.set_fuel_economy(economy)
	lamp.set_unlocked(true)
	assert_almost_eq(lamp.refuel(), 1800.0)
	assert_almost_eq(lamp.fuel_remaining(), 1800.0, 0.001,
		"the part of a whole coal lump above nominal capacity was destroyed")
	assert_eq(economy.requests.size(), 1)
	assert_almost_eq(economy.requests[0], 900.0)
	lamp.free()


func test_beacon_domain_events_are_value_only_and_name_their_world_result() -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(&"beacon.lit", _record)
	var lamp := _lamp(_definition(&"value_probe"))
	lamp.position = Vector3(3.0, 0.0, -4.0)
	lamp.set_event_bus(_bus)
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(60.0)
	assert_true(lamp.light())
	assert_not_null(_payload)
	if _payload != null:
		assert_false(_contains_object(_payload), "beacon.lit leaks a live entity through EventBus")
		assert_eq(_payload.get("id"), &"value_probe")
		assert_eq(_payload.get("kind"), &"beacon")
		assert_eq(_payload.get("world_position"), Vector3(3.0, 0.0, -4.0))
	lamp.free()


func _contains_object(value) -> bool:
	if value is Object or value is Callable:
		return true
	if value is Dictionary:
		for nested in (value as Dictionary).values():
			if _contains_object(nested):
				return true
	if value is Array:
		for nested in value:
			if _contains_object(nested):
				return true
	return false


func test_a_locked_beacon_cannot_spend_fuel_or_light() -> void:
	var economy := FakeEconomy.new()
	economy.award = 900.0
	var lamp := _lamp()
	lamp.set_fuel_economy(economy)
	assert_false(lamp.interact())
	assert_eq(economy.requests.size(), 0)
	assert_false(lamp.is_lit())
	lamp.free()


func test_an_extinguished_beacon_relights_its_remaining_fuel_without_spending_an_item() -> void:
	var economy := FakeEconomy.new()
	economy.award = 900.0
	var lamp := _lamp()
	lamp.set_fuel_economy(economy)
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(120.0)
	assert_true(lamp.light())
	assert_true(lamp.extinguish(&"wind"))
	assert_true(lamp.interact())
	assert_true(lamp.is_lit())
	assert_almost_eq(lamp.fuel_remaining(), 120.0)
	assert_eq(economy.requests.size(), 0,
		"relighting a wind-extinguished ember withdrew a needless whole fuel item")
	lamp.free()


func test_a_stale_beacon_offer_reports_when_the_last_fuel_was_spent_elsewhere() -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(&"interaction.rejected", _record)
	var economy := FakeEconomy.new()
	economy.award = 900.0
	var occupant := Node3D.new()
	var lamp := _lamp(_definition(&"stale_probe"))
	lamp.set_event_bus(_bus)
	lamp.set_fuel_economy(economy)
	lamp.set_occupant(occupant)
	lamp.set_unlocked(true)
	lamp._on_body_entered(occupant)
	economy.award = 0.0
	lamp._on_interaction_activated({"id": &"beacon:stale_probe"})
	assert_false(lamp.is_lit())
	assert_not_null(_payload, "the failed cached command remained silent")
	if _payload != null:
		assert_eq(_payload.get("reason"), &"no_fuel")
		assert_false(_contains_object(_payload))
	lamp.free()
	occupant.free()


func test_a_lit_beacon_burns_down_and_goes_out_at_zero() -> void:
	var lamp := _lamp()
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(4.0)
	assert_true(lamp.light())
	lamp.advance(3.0)
	assert_true(lamp.is_lit())
	assert_almost_eq(lamp.fuel_remaining(), 1.0)
	lamp.advance(1.0)
	assert_false(lamp.is_lit())
	assert_almost_eq(lamp.fuel_remaining(), 0.0)
	lamp.free()


func test_a_lit_beacon_is_a_fire_and_membership_tracks_the_flame() -> void:
	var lamp := _lamp()
	lamp.position = Vector3(8.0, 0.0, -3.0)
	assert_true(Fires.answers(lamp),
		"the beacon cannot answer the shared fire contract, so sound, snow and threats cannot find it")
	if not Fires.answers(lamp):
		lamp.free()
		return
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	assert_true(lamp.light())
	assert_true(lamp.is_in_group(Fires.GROUP),
		"the lit beacon did not become one of the valley's discoverable fires")
	assert_almost_eq(float(lamp.call(&"warmth_at", lamp.position)), 1.0, 0.0001,
		"standing at a burning beacon is not a full warm point")
	assert_almost_eq(float(lamp.call(&"warmth_at", Vector3(100.0, 0.0, 0.0))), 0.0, 0.0001,
		"the beacon heats the whole valley instead of one readable refuge")
	lamp.extinguish(&"test")
	assert_false(lamp.is_in_group(Fires.GROUP),
		"an extinguished beacon is still advertised as a burning fire")
	assert_almost_eq(float(lamp.call(&"warmth_at", lamp.position)), 0.0, 0.0001)
	lamp.free()


func test_beacon_warmth_reaches_the_survival_recovery_channels() -> void:
	var lamp := _lamp()
	var survival := FakeSurvival.new()
	assert_true(lamp.has_method(&"set_survival_system"))
	assert_true(lamp.has_method(&"apply_recovery"))
	if not lamp.has_method(&"set_survival_system") or not lamp.has_method(&"apply_recovery"):
		lamp.free()
		return
	lamp.set_survival_system(survival)
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	lamp.call(&"apply_recovery", lamp.position)
	assert_true(float(survival.modifiers.get(&"core_temperature:recovery", 0.0)) > 0.0,
		"the beacon looks warm but does not restore core temperature")
	assert_true(float(survival.modifiers.get(&"fatigue:recovery", 0.0)) > 0.0,
		"resting at the beacon does not restore any fatigue")
	lamp.extinguish(&"test")
	assert_true(survival.modifiers.is_empty(),
		"the body keeps recovering after the beacon has gone out")
	lamp.free()


func test_wind_extinguish_probability_is_frame_rate_independent() -> void:
	var definition := _definition(&"probe")
	definition.wind_extinguish_threshold = 0.5
	definition.wind_extinguish_rate_per_second = 0.2
	var lamp := _lamp(definition)
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	var whole := lamp.wind_extinguish_probability(1.0, 1.0)
	var frame := lamp.wind_extinguish_probability(1.0, 1.0 / 60.0)
	var compounded := 1.0 - pow(1.0 - frame, 60.0)
	assert_almost_eq(compounded, whole, 0.0001)
	lamp.free()


func test_wind_below_the_authored_threshold_cannot_extinguish_a_beacon() -> void:
	var definition := _definition(&"probe")
	definition.wind_extinguish_threshold = 0.7
	var lamp := _lamp(definition)
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	assert_almost_eq(lamp.wind_extinguish_probability(0.7, 60.0), 0.0)
	assert_false(lamp.try_wind_extinguish(0.6, 60.0, 0.0))
	assert_true(lamp.is_lit())
	lamp.free()


func test_the_network_spawns_five_and_unlocks_only_through_the_current_day() -> void:
	var network := _build_network()
	assert_eq(network.total_count(), 5)
	network.set_day(3)
	for index in IDS.size():
		assert_eq(network.beacon(IDS[index]).is_unlocked(), index < 3)


func test_a_blizzard_extinguishes_at_least_one_burning_beacon() -> void:
	var network := _build_network()
	network.set_day(5)
	for lamp in network.beacons():
		lamp.add_fuel_seconds(100.0)
		lamp.light()
	assert_eq(network.lit_count(), 5)
	_bus.emit_event(&"weather.arrived", {
		"extinguishes_beacons": true,
		"min_beacons_extinguished": 1,
	})
	assert_eq(network.lit_count(), 4, "the blizzard arrived and every warm point stayed lit")


func test_an_ordinary_weather_arrival_does_not_touch_the_lamps() -> void:
	var network := _build_network()
	network.set_day(5)
	var lamp := network.beacon(IDS[0])
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	_bus.emit_event(&"weather.arrived", {
		"extinguishes_beacons": false,
		"min_beacons_extinguished": 3,
	})
	assert_true(lamp.is_lit())
	assert_eq(network.lit_count(), 1)


func test_run_reset_drains_every_beacon_and_returns_unlocks_to_day_one() -> void:
	var network := _build_network()
	network.set_day(5)
	for lamp in network.beacons():
		lamp.add_fuel_seconds(100.0)
		lamp.light()
	assert_eq(network.lit_count(), 5)
	_bus.emit_event(&"game.run_reset", {"seed": 1729})
	assert_eq(network.lit_count(), 0)
	for index in IDS.size():
		var lamp := network.beacon(IDS[index])
		assert_almost_eq(lamp.fuel_remaining(), 0.0)
		assert_eq(lamp.is_unlocked(), index == 0,
			"restart did not restore the authored day-one unlock boundary")


func test_the_first_run_started_event_binds_beacon_randomness_to_the_replay_seed() -> void:
	var network := _build_network()
	network.set_day(5)
	for lamp in network.beacons():
		lamp.add_fuel_seconds(100.0)
		lamp.light()
	_bus.emit_event(&"game.run_started", {"seed": 1729, "day": 1})
	assert_eq(network.current_run_seed(), 1729)
	assert_eq(network.extinguish_minimum(1, &"probe"), 1)
	var first_extinguished := &""
	for id in network.beacon_ids():
		if not network.beacon(id).is_lit():
			first_extinguished = id
	_bus.emit_event(&"game.run_reset", {"seed": 1729})
	network.set_day(5)
	for lamp in network.beacons():
		lamp.add_fuel_seconds(100.0)
		lamp.light()
	_bus.emit_event(&"game.run_started", {"seed": 1729, "day": 1})
	assert_eq(network.extinguish_minimum(1, &"probe"), 1)
	var replay_extinguished := &""
	for id in network.beacon_ids():
		if not network.beacon(id).is_lit():
			replay_extinguished = id
	assert_true(first_extinguished != &"", "the first seeded draw extinguished no beacon")
	assert_eq(replay_extinguished, first_extinguished,
		"the same run seed did not replay the beacon selection")


func test_the_run_end_publishes_the_visible_final_state() -> void:
	var network := _build_network()
	_bus.subscribe(&"beacons.final_state", _record)
	network.set_day(5)
	for lamp in network.beacons():
		lamp.add_fuel_seconds(10.0)
		lamp.light()
	_bus.emit_event(&"clock.run_finished", {"day": 8})
	assert_not_null(_payload)
	if _payload != null:
		assert_eq(_payload["lit"], 5)
		assert_eq(_payload["total"], 5)
		assert_true(_payload["all_lit"])


func test_beacon_light_uses_the_shared_warm_palette_and_casts_no_shadow() -> void:
	var definition := _definition(&"probe")
	definition.warm_tone_index = 2
	var lamp := _lamp(definition)
	lamp._apply_definition()
	var light := lamp.get_node("WarmPoint") as OmniLight3D
	assert_not_null(light)
	if light != null:
		assert_eq(light.light_color, PALETTE.warm_tones[2])
		assert_false(light.shadow_enabled, "five distant progress lights entered the shadow atlas")
	lamp.free()


func test_a_lit_beacon_has_one_low_poly_warm_marker_visible_in_empty_air() -> void:
	var definition := _definition(&"probe")
	definition.warm_tone_index = 1
	var lamp := _lamp(definition)
	lamp._apply_definition()
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	assert_true(lamp.light())
	var flame := lamp.get_node("FlameCore") as MeshInstance3D
	assert_not_null(flame)
	if flame != null:
		assert_true(flame.visible)
		assert_true(flame.mesh is SphereMesh)
		assert_eq((flame.mesh as SphereMesh).radial_segments, 8)
		var material := flame.mesh.material as StandardMaterial3D
		assert_not_null(material)
		if material != null:
			assert_eq(material.emission, PALETTE.warm_tones[1])
		assert_eq(flame.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	lamp.free()


func test_beacon_feedback_uses_two_small_fixed_gpu_pools() -> void:
	var lamp := _lamp()
	lamp._apply_definition()
	var embers := lamp.get_node("WindEmbers") as GPUParticles3D
	var smoke := lamp.get_node("ExtinguishSmoke") as GPUParticles3D
	assert_not_null(embers)
	assert_not_null(smoke)
	if embers != null and smoke != null:
		assert_eq(embers.amount, 12)
		assert_eq(smoke.amount, 18)
		assert_true(embers.fixed_fps <= 20 and smoke.fixed_fps <= 20)
		assert_eq(embers.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(smoke.gi_mode, GeometryInstance3D.GI_MODE_DISABLED)
	lamp.free()


func test_strong_wind_leans_the_flame_and_feeds_the_existing_ember_pool() -> void:
	var lamp := _lamp()
	lamp._apply_definition()
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	lamp.set_weather_wind(0.9, Vector3(7.0, 0.0, -3.0))
	lamp.advance(0.1)
	var flame := lamp.get_node("FlameCore") as MeshInstance3D
	var embers := lamp.get_node("WindEmbers") as GPUParticles3D
	assert_true(absf(flame.rotation.x) + absf(flame.rotation.z) > 0.01)
	assert_true(embers.emitting)
	assert_true(embers.amount_ratio > 0.8)
	lamp.free()


func test_extinguishing_restarts_the_preallocated_smoke_burst() -> void:
	var lamp := _lamp()
	lamp._apply_definition()
	lamp.set_unlocked(true)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	assert_true(lamp.extinguish(&"test"))
	var smoke := lamp.get_node("ExtinguishSmoke") as GPUParticles3D
	assert_true(smoke.one_shot)
	assert_true(smoke.emitting)
	lamp.free()


func test_the_far_wayfinder_is_cold_until_the_beacon_is_actually_lit() -> void:
	var definition := _definition(&"probe")
	definition.warm_tone_index = 2
	var lamp := _lamp(definition)
	lamp._apply_definition()
	var marker := lamp.get_node("Wayfinder") as MeshInstance3D
	var material := marker.mesh.material as StandardMaterial3D
	assert_false(marker.visible)
	lamp.set_unlocked(true)
	assert_true(marker.visible)
	assert_eq(material.albedo_color, PALETTE.structure_tones[2])
	assert_false(material.emission_enabled)
	lamp.add_fuel_seconds(100.0)
	lamp.light()
	assert_eq(material.albedo_color, PALETTE.warm_tones[2])
	assert_true(material.emission_enabled)
	lamp.free()


func test_main_scene_runs_the_beacon_network() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_true(source.contains("res://src/systems/beacon_network.gd"))
	assert_true(source.contains("[node name=\"BeaconNetwork\""))
