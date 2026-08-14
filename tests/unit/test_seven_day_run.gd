extends TestCase

## One scripted, successful attempt through the real seven-day domain model.
##
## This deliberately stays outside the SceneTree: the test is about the
## calendar, weather, body, route ledger, stove and five lamps sharing one
## deterministic run, not about rendering the valley or proving the player-
## input seam. Route collection already uses the real interaction-facing API;
## hearth preparation and consumption still call the domain APIs directly and
## must remain documented as pending player-facing integration work.

const EventBusScript := preload("res://src/core/event_bus.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const WeatherSystemScript := preload("res://src/systems/weather_system.gd")
const WindSystemScript := preload("res://src/systems/wind_system.gd")
const NightExposureScript := preload("res://src/systems/night_exposure.gd")
const BeaconNetworkScript := preload("res://src/systems/beacon_network.gd")
const RouteLayerScript := preload("res://src/systems/survival_route_layer.gd")
const GameStateScript := preload("res://src/systems/game_state.gd")

const STOVE_SCENE := "res://scenes/entities/stove/stove.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const CORE_TEMPERATURE_DEFINITION := "res://data/stats/core_temperature.tres"
const RUN_SEED := 1729
const STEP_SECONDS := 1.0
const TOTAL_RUN_SECONDS := 6300.0
const ROUTE_FUEL_SECONDS := 14400.0
const STARTING_STOVE_SECONDS := 600.0
const EXPECTED_REMAINDER_SECONDS := 3255.0
const CONTINUOUS_BEACON_BURN_SECONDS := 5625.0
const DAILY_RAW_SERVINGS := 2
const EXPECTED_WEATHER_TRACE: Array[StringName] = [
	&"clear_break",
	&"snow_fog",
	&"snow_fog",
	&"clear_break",
	&"snow_fog",
	&"snow_fog",
	&"snow_fog",
	&"clear_break",
	&"clear_break",
	&"wind_shift",
	&"cold_snap",
	&"blizzard",
	&"wind_shift",
]


class LightingStandIn extends RefCounted:
	var preset_id: StringName = &"pale_day"

	func crossfade_to(id: StringName, _seconds: float) -> void:
		if id != &"":
			preset_id = id

	func target_preset_id() -> StringName:
		return preset_id

	func active_preset() -> Dictionary:
		return {"id": preset_id}


var _bus = null
var _clock = null
var _survival = null
var _economy = null
var _lighting: LightingStandIn = null
var _weather = null
var _wind = null
var _exposure = null
var _network = null
var _routes = null
var _stove: Stove = null
var _game = null

var _weather_tells: Array[StringName] = []
var _weather_arrivals: Array[StringName] = []
var _unwarned_weather_arrivals := 0
var _blizzard_tell_day := 0
var _blizzard_arrival_day := 0
var _blizzard_arrived_at_night := false
var _blizzard_arrival_temperature_drain := 0.0
var _blizzard_arrival_was_exposed := false
var _blizzard_extinguishes := 0
var _weather_relights := 0
var _prepared_days := 0
var _preparation_failures := 0
var _night_banks := 0
var _night_bank_failures := 0
var _consumed_hot_stew := 0
var _consumed_meltwater := 0
var _weather_shelter := false
var _extra_hearth_burn_seconds := 0.0
var _beacon_burn_seconds := 0.0
var _minimum_hunger := 1.0
var _minimum_thirst := 1.0
var _minimum_temperature := 1.0


func after_each() -> void:
	if _weather != null:
		_weather.detach()
	if _exposure != null:
		_exposure.detach()
	if _stove != null:
		_stove.clear_recovery()
		_stove.extinguish()
		_stove.free()
		_stove = null
	if _routes != null:
		_routes.free()
		_routes = null
	if _network != null:
		_network.free()
		_network = null
	if _wind != null:
		_wind.free()
		_wind = null
	if _weather != null:
		_weather.free()
		_weather = null
	if _exposure != null:
		_exposure.free()
		_exposure = null
	if _game != null:
		_game.free()
		_game = null
	if _clock != null:
		_clock.free()
		_clock = null
	if _economy != null:
		_economy.free()
		_economy = null
	if _survival != null:
		_survival.free()
		_survival = null
	_lighting = null
	if _bus != null:
		_bus.free()
		_bus = null


func _build_run() -> void:
	_bus = EventBusScript.new()

	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	_clock.load_schedules_from_directory()

	_survival = SurvivalSystemScript.new()
	_survival.set_event_bus(_bus)
	_survival.load_from_directory()

	_economy = FuelEconomyScript.new()
	_economy.set_event_bus(_bus)
	_economy.set_survival_system(_survival)
	_economy.load_from_directory()

	_lighting = LightingStandIn.new()
	_wind = WindSystemScript.new()
	_wind.set_event_bus(_bus)
	_wind.set_lighting(_lighting)
	_wind.set_map(load("res://data/weather/wind_map.tres"))

	_weather = WeatherSystemScript.new()
	_weather.set_event_bus(_bus)
	_weather.set_world_clock(_clock)
	_weather.set_survival_system(_survival)
	_weather.set_lighting(_lighting)
	_weather.set_wind_system(_wind)
	_weather.load_events_from_directory()
	_weather.attach()

	_exposure = NightExposureScript.new()
	_exposure.set_event_bus(_bus)
	_exposure.set_survival_system(_survival)
	_exposure.attach()

	_network = BeaconNetworkScript.new()
	_network.set_event_bus(_bus)
	_network.set_fuel_economy(_economy)
	_network.set_wind_system(_wind)
	_network.load_from_directory()
	_network.spawn_missing()

	_routes = RouteLayerScript.new()
	_routes.set_event_bus(_bus)
	_routes.set_fuel_economy(_economy)
	_routes.load_routes_from_directory()
	_routes.load_nodes_from_directory()
	_routes.spawn_missing()

	_game = GameStateScript.new()
	_game.run_seed = RUN_SEED
	_game.set_event_bus(_bus)
	_game.set_survival_system(_survival)
	_game.set_world_clock(_clock)

	_bus.subscribe(WeatherSystemScript.EVENT_TELL_STARTED, _record_weather_tell)
	_bus.subscribe(WeatherSystemScript.EVENT_ARRIVED, _record_weather_arrival)
	_bus.subscribe(WeatherSystemScript.EVENT_CLEARED, _record_weather_cleared)
	_bus.subscribe(&"beacon.extinguished", _record_beacon_extinguish)

	# A detached graph cannot resolve GameState through ServiceRegistry. The
	# shared reset event is the production replay boundary and seeds both random
	# consumers with the same value before day one is announced.
	_bus.emit_event(GameStateScript.EVENT_RUN_RESET, {"seed": _game.current_run_seed()})

	_stove = (load(STOVE_SCENE) as PackedScene).instantiate() as Stove
	_stove.set_event_bus(_bus)
	_stove.set_survival_system(_survival)
	_stove.set_fuel_economy(_economy)
	var stove_start := _main_stove_settings()
	if float(stove_start.get("fuel", 0.0)) > 0.0:
		_stove.add_fuel_seconds(float(stove_start["fuel"]))
	if bool(stove_start.get("lit", false)):
		_stove.light()


func _main_stove_settings() -> Dictionary:
	var result := {"fuel": 0.0, "lit": false}
	var packed := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return result
	var state := packed.get_state()
	for node_index in range(state.get_node_count()):
		var instance := state.get_node_instance(node_index) as PackedScene
		if instance == null or instance.resource_path != STOVE_SCENE:
			continue
		for property_index in range(state.get_node_property_count(node_index)):
			var property := state.get_node_property_name(node_index, property_index)
			if property == &"starting_fuel_seconds":
				result["fuel"] = float(state.get_node_property_value(node_index, property_index))
			elif property == &"start_lit":
				result["lit"] = bool(state.get_node_property_value(node_index, property_index))
		return result
	return result


func _collect_the_circuit() -> int:
	var collected := 0
	for node in _routes.route_nodes():
		if node.definition.is_pickup() and node.collect():
			collected += 1
	return collected


func _bank_hearth_coal() -> int:
	var banked := 0
	while _economy.count_of(&"coal") > 0:
		if not _stove.stoke(&"coal"):
			break
		banked += 1
	return banked


func _ensure_stove_fuel(seconds: float) -> bool:
	var missing := maxf(seconds - _stove.fuel_remaining(), 0.0)
	if missing > 0.0:
		_stove.stoke_for(missing)
	return _stove.fuel_remaining() + 0.0001 >= seconds


func _prepare_daily_food() -> bool:
	var heat_cost := 0.0
	for id in [&"snow", &"canned_stew"]:
		var definition: ItemDefinition = _economy.definition_of(id)
		if definition != null:
			heat_cost += definition.heat_seconds * float(DAILY_RAW_SERVINGS)
	if not _ensure_stove_fuel(heat_cost):
		return false
	if not _stove.is_lit() and not _stove.light():
		return false
	for _serving in range(DAILY_RAW_SERVINGS):
		if _stove.heat(&"snow") != &"meltwater":
			return false
		if _stove.heat(&"canned_stew") != &"hot_stew":
			return false
	_prepared_days += 1
	_stove.extinguish()
	return true


func _bank_the_night() -> bool:
	_exposure.set_sheltered(true)
	if not _ensure_stove_fuel(_clock.phase_duration()):
		return false
	return _stove.is_lit() or _stove.light()


func _maintain_unlocked_beacons() -> void:
	var schedule = _clock.current_schedule()
	for lamp in _network.beacons():
		if not lamp.is_unlocked():
			continue
		var until_next_visit := 0.0
		if schedule != null:
			until_next_visit = (
				float(schedule.daylight_seconds) + float(schedule.night_seconds)
			) * float(lamp.definition.burn_rate)
		if lamp.fuel_remaining() <= until_next_visit + 0.0001:
			lamp.refuel()
		if not lamp.is_lit() and lamp.fuel_remaining() > 0.0:
			lamp.light()


func _meet_body_needs() -> void:
	_minimum_hunger = minf(_minimum_hunger, _survival.fraction_of(&"hunger"))
	_minimum_thirst = minf(_minimum_thirst, _survival.fraction_of(&"thirst"))
	_minimum_temperature = minf(
		_minimum_temperature, _survival.fraction_of(&"core_temperature")
	)
	if _survival.fraction_of(&"hunger") <= 0.35:
		if _economy.consume(&"hot_stew"):
			_consumed_hot_stew += 1
	if _survival.fraction_of(&"thirst") <= 0.25:
		if _economy.consume(&"meltwater"):
			_consumed_meltwater += 1


func _sync_schedule_lighting() -> void:
	var schedule = _clock.current_schedule()
	if schedule == null:
		return
	var preset: StringName = (
		schedule.night_lighting_preset
		if _clock.is_night()
		else schedule.primary_lighting_preset
	)
	_lighting.crossfade_to(preset, 0.0)


func _relight_weather_losses() -> void:
	for lamp in _network.beacons():
		if lamp.is_unlocked() and not lamp.is_lit() and lamp.fuel_remaining() > 0.0:
			if lamp.light():
				_weather_relights += 1


func _advance_one_second() -> void:
	_exposure.set_sheltered(_clock.is_night() or _weather_shelter)
	_meet_body_needs()
	if _clock.is_night() or _weather_shelter:
		_stove.apply_recovery(_stove.fire_position())
	else:
		_stove.clear_recovery()

	_weather.advance(STEP_SECONDS)
	_wind.advance(STEP_SECONDS)
	_network.advance(STEP_SECONDS)
	for lamp in _network.beacons():
		if lamp.is_lit():
			_beacon_burn_seconds += minf(
				lamp.fuel_remaining(), STEP_SECONDS * float(lamp.definition.burn_rate)
			)
		lamp.advance(STEP_SECONDS)
	if _weather_shelter and not _clock.is_night() and _stove.is_lit():
		_extra_hearth_burn_seconds += STEP_SECONDS * _stove.burn_rate
	_stove.advance(STEP_SECONDS)
	_survival.advance(STEP_SECONDS)
	_relight_weather_losses()

	var previous_day: int = _clock.current_day()
	var previous_night: bool = _clock.is_night()
	_clock.advance(STEP_SECONDS)
	if _clock.is_finished() or not _game.is_running():
		return
	if _clock.current_day() != previous_day:
		_sync_schedule_lighting()
		_exposure.set_sheltered(false)
		_stove.extinguish()
		if not _prepare_daily_food():
			_preparation_failures += 1
		_maintain_unlocked_beacons()
	elif not previous_night and _clock.is_night():
		_sync_schedule_lighting()
		if _bank_the_night():
			_night_banks += 1
		else:
			_night_bank_failures += 1


func _remaining_fuel_seconds() -> float:
	var total: float = _economy.fuel_seconds() + _stove.fuel_remaining()
	for lamp in _network.beacons():
		total += lamp.fuel_remaining()
	return total


func _record_weather_tell(payload) -> void:
	if payload is Dictionary:
		var id := StringName(payload.get("id", &""))
		_weather_tells.append(id)
		if id == &"blizzard":
			_blizzard_tell_day = _clock.current_day()
			_weather_shelter = true
			_ensure_stove_fuel(600.0)
			if not _stove.is_lit():
				_stove.light()


func _record_weather_arrival(payload) -> void:
	if payload is Dictionary:
		var id := StringName(payload.get("id", &""))
		if _weather_tells.count(id) <= _weather_arrivals.count(id):
			_unwarned_weather_arrivals += 1
		_weather_arrivals.append(id)
		if id == &"blizzard":
			_blizzard_arrival_day = _clock.current_day()
			_blizzard_arrived_at_night = _clock.is_night()
			_blizzard_arrival_was_exposed = _exposure.is_doubling()
			_blizzard_arrival_temperature_drain = (
				_survival.drain_rate_of(&"core_temperature")
			)


func _record_weather_cleared(payload) -> void:
	if not (payload is Dictionary) or StringName(payload.get("id", &"")) != &"blizzard":
		return
	_weather_shelter = false
	if not _clock.is_night():
		_stove.extinguish()


func _record_beacon_extinguish(payload) -> void:
	if payload is Dictionary and StringName(payload.get("cause", &"")) == &"blizzard":
		_blizzard_extinguishes += 1


func test_fixed_seed_route_income_carries_one_real_body_and_five_lamps_through_seven_days() -> void:
	_build_run()
	assert_eq(_clock.schedule_count(), 7)
	assert_almost_eq(_clock.total_run_seconds(), TOTAL_RUN_SECONDS, 0.0001)
	assert_eq(_weather.current_run_seed(), _game.current_run_seed())
	assert_almost_eq(_stove.fuel_remaining(), STARTING_STOVE_SECONDS, 0.0001)
	assert_true(_stove.is_lit(), "the simulation did not inherit the main scene's lit hearth")
	assert_true(_game.begin_run(RUN_SEED))
	_sync_schedule_lighting()

	assert_eq(_collect_the_circuit(), 10)
	assert_almost_eq(_economy.fuel_seconds(), ROUTE_FUEL_SECONDS, 0.0001)
	assert_eq(_economy.count_of(&"canned_stew"), 14)
	assert_eq(_economy.count_of(&"snow"), 14)
	assert_eq(_bank_hearth_coal(), 4, "the indivisible storm reserve was left to strand in lamp bowls")
	assert_true(_prepare_daily_food(), "day one provisions could not be prepared")
	_maintain_unlocked_beacons()

	for _second in range(int(TOTAL_RUN_SECONDS) + 2):
		if _clock.is_finished() or not _game.is_running():
			break
		_advance_one_second()

	assert_eq(_weather_tells, EXPECTED_WEATHER_TRACE)
	assert_eq(_unwarned_weather_arrivals, 0, "a weather arrived before its warning")
	assert_eq(_weather_arrivals, _weather_tells, "a weather arrived without its warning")
	assert_true(_weather_tells.size() >= 10, "seven real days scheduled almost no weather")
	if not _weather_tells.is_empty():
		assert_eq(_weather_tells.front(), &"clear_break")
	assert_true(_weather_tells.has(&"blizzard"), "day seven lost its forced blizzard")
	assert_eq(_blizzard_tell_day, 7, "the forced blizzard warning left day seven")
	assert_eq(_blizzard_arrival_day, 7, "the forced blizzard left day seven")
	assert_false(_blizzard_arrived_at_night, "the forced blizzard missed day seven daylight")
	assert_false(_blizzard_arrival_was_exposed,
		"the scripted shelter did not remove the ordinary night multiplier")
	var temperature: StatDefinition = load(CORE_TEMPERATURE_DEFINITION) as StatDefinition
	var blizzard: WeatherEventDefinition = _weather.definition(&"blizzard")
	var blizzard_multiplier := 1.0
	if blizzard != null:
		for modifier in blizzard.stat_modifiers:
			if modifier != null \
					and modifier.target_stat in [&"core_temperature", &"core_temperature:drain"] \
					and modifier.operation == Modifier.Operation.MULTIPLY:
				blizzard_multiplier *= modifier.value
	assert_not_null(temperature)
	assert_not_null(blizzard)
	assert_true(blizzard_multiplier > 1.0,
		"the authored blizzard lost its body-temperature pressure")
	if temperature != null and blizzard != null:
		assert_almost_eq(
			_blizzard_arrival_temperature_drain,
			temperature.base_decay_per_second * blizzard_multiplier,
			0.000001,
			"the day-seven weather modifier never reached the real body"
		)
	assert_true(_blizzard_extinguishes >= 1, "the blizzard left all five lamps untouched")
	assert_true(_weather_relights >= _blizzard_extinguishes, "weather losses were not relit")
	assert_eq(_prepared_days, 7)
	assert_eq(_preparation_failures, 0)
	assert_eq(_night_banks, 7)
	assert_eq(_night_bank_failures, 0)
	assert_eq(_economy.count_of(&"canned_stew"), 0)
	assert_eq(_economy.count_of(&"snow"), 0)
	assert_true(_consumed_hot_stew > 0, "the prepared food never reached hunger")
	assert_true(_consumed_meltwater > 0, "the prepared water never reached thirst")
	assert_eq(
		_economy.count_of(&"hot_stew"),
		_prepared_days * DAILY_RAW_SERVINGS - _consumed_hot_stew,
		"processed food was minted or lost before consumption"
	)
	assert_eq(
		_economy.count_of(&"meltwater"),
		_prepared_days * DAILY_RAW_SERVINGS - _consumed_meltwater,
		"processed water was minted or lost before consumption"
	)
	assert_true(_minimum_hunger < 0.5, "food was consumed before hunger mattered")
	assert_true(_minimum_thirst < 0.5, "water was consumed before thirst mattered")
	assert_true(_minimum_temperature < 0.75, "body temperature never entered a consequential range")
	assert_false(_survival.is_dead())
	assert_true(_clock.is_finished())
	assert_eq(_network.lit_count(), 5)
	assert_true(_network.all_lit())
	assert_eq(_game.outcome(), GameStateScript.OUTCOME_RESCUED)
	assert_true(_beacon_burn_seconds > 5600.0, "the five lamps were dark for a material part of the run")
	assert_almost_eq(
		_remaining_fuel_seconds(),
		EXPECTED_REMAINDER_SECONDS
			- _extra_hearth_burn_seconds
			+ CONTINUOUS_BEACON_BURN_SECONDS
			- _beacon_burn_seconds,
		0.01,
		"fuel was minted or lost between route pickups, chores, hearth and lamps"
	)
