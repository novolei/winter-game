extends TestCase

## One narrow, live-scene exit test for the player's survival chores. The
## domain tests prove each ledger operation in isolation; this test proves the
## shipped main scene lets one real player reach them through the one real E-key
## director, and that the farmhouse threshold reaches the night rule.

const MainScene := preload("res://scenes/main.tscn")
const EventBusScript := preload("res://src/core/event_bus.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const NightExposureScript := preload("res://src/systems/night_exposure.gd")
const GameStateScript := preload("res://src/systems/game_state.gd")

const SERVICE_KEYS: Array[StringName] = [
	&"player",
	&"snow_field",
	&"track_mask",
	&"snow_accumulation",
	&"camera_rig",
	&"lighting",
	&"snowfall",
	&"wind",
	&"weather",
	&"weather_vfx",
	&"beacon_network",
	&"survival_routes",
	&"aurora",
	&"ui_layer",
]

var _main: Node = null
var _tree: SceneTree = null
var _tree_was_paused := false
var _bus: Node = null
var _economy: Node = null
var _survival: Node = null
var _clock: Node = null
var _exposure: Node = null
var _registry: Node = null
var _registry_snapshot: Dictionary = {}
var _player: Node3D = null
var _routes = null
var _stove = null
var _director = null
var _door = null
var _reveal = null
var _result_surfacing = null
var _run_result = null
var _exit_menu = null
var _game = null
var _activations: Array = []
var _interior_events: Array[StringName] = []
var _run_events: Array[StringName] = []
var _reload_calls := 0


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	if _tree == null or _tree.root == null:
		return
	_tree_was_paused = _tree.paused
	_tree.paused = false
	_reload_calls = 0
	_registry = _tree.root.get_node_or_null("ServiceRegistry")
	_snapshot_services()

	_bus = EventBusScript.new()
	_economy = FuelEconomyScript.new()
	_economy.load_from_directory()
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.set_event_bus(_bus)
	_survival.start()
	# The authored rates put hunger near .29 and thirst near .15. A hot meal and
	# one meltwater then both fit without wasting recovery, so the contextual
	# queue has one deterministic pass through every requested chore.
	_survival.advance(510.0)
	_economy.set_survival_system(_survival)
	_economy.set_event_bus(_bus)

	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	_clock.load_schedules_from_directory()
	_clock.start()

	_exposure = NightExposureScript.new()
	_exposure.set_event_bus(_bus)
	_exposure.set_survival_system(_survival)
	_exposure.attach()
	_bus.subscribe(&"interaction.activated", _record_activation)
	_bus.subscribe(&"interior.entered", _record_interior_entered)
	_bus.subscribe(&"interior.exited", _record_interior_exited)

	_main = MainScene.instantiate()
	_player = _main.get_node_or_null("Player") as Node3D
	_routes = _main.get_node_or_null("SurvivalRoutes")
	_stove = _main.get_node_or_null("Farmhouse/Stove")
	_director = _main.get_node_or_null("UI/Interaction")
	_result_surfacing = _main.get_node_or_null("UI/ResultSurfacing")
	_run_result = _main.get_node_or_null("RunResult")
	_exit_menu = _main.get_node_or_null("ExitMenu")
	_door = _main.get_node_or_null("Farmhouse/Door")
	_reveal = _main.get_node_or_null("Farmhouse/InteriorReveal")
	_wire_private_dependencies(_main)
	_wire_occupants()
	# add_child() is the part this test is for: it synchronously executes the
	# real main graph's _ready methods, builds the route nodes, starts the placed
	# stove and registers the exact production services.
	_tree.root.add_child(_main)
	_wire_occupants()
	for route_node in _routes.route_nodes() if _routes != null else []:
		route_node.set_event_bus(_bus)
		route_node.set_fuel_economy(_economy)
		route_node.set_occupant(_player)


func after_each() -> void:
	if _tree != null:
		_tree.paused = false
	if _game != null and is_instance_valid(_game):
		_game.set_event_bus(null)
		_game.free()
		_game = null
	if _bus != null and is_instance_valid(_bus):
		# Removes NightExposure's named drain before its collaborators disappear.
		_bus.emit_event(WorldClockScript.EVENT_RUN_FINISHED, null)
	if _exposure != null and is_instance_valid(_exposure):
		_exposure.detach()
	if _main != null and is_instance_valid(_main):
		var weather = _main.get_node_or_null("Weather")
		if weather != null and weather.has_method("clear_now"):
			weather.clear_now()
		_main.free()
		if _registry != null and is_instance_valid(_registry):
			assert_false(_registry.has(&"ui_layer"),
				"freeing the real main scene left its UILayer registered as a freed service")
	_restore_services()
	for node in [_exposure, _clock, _economy, _survival, _bus]:
		if node != null and is_instance_valid(node):
			node.free()
	_main = null
	_bus = null
	_economy = null
	_survival = null
	_clock = null
	_exposure = null
	_registry = null
	_registry_snapshot.clear()
	_player = null
	_routes = null
	_stove = null
	_director = null
	_door = null
	_reveal = null
	_result_surfacing = null
	_run_result = null
	_exit_menu = null
	_activations.clear()
	_interior_events.clear()
	_run_events.clear()
	_reload_calls = 0
	if _tree != null:
		_tree.paused = _tree_was_paused
	_tree = null


func test_real_main_routes_e_through_hearth_and_interior_survival() -> void:
	assert_not_null(_main, "the shipped main scene did not instantiate into the live tree")
	assert_not_null(_player, "main has no real Player for the Area contracts")
	assert_not_null(_routes, "main has no real SurvivalRoutes layer")
	assert_not_null(_stove, "main has no placed farmhouse Stove")
	assert_not_null(_director, "main has no sole InteractionDirector")
	assert_not_null(_door, "main has no farmhouse Door gate")
	assert_not_null(_reveal, "main has no farmhouse InteriorReveal threshold")
	assert_not_null(_registry, "the live tree has no ServiceRegistry for lifecycle verification")
	if null in [_main, _player, _routes, _stove, _director, _door, _reveal]:
		return
	if _registry != null:
		assert_true(_registry.get_service(&"ui_layer") == _main.get_node("UI"),
			"the real UILayer never registered before its cleanup was tested")
	assert_eq(_routes.route_nodes().size(), 20,
		"the real scene did not spawn its authored route-node graph")

	_pick_up(&"east_supply_sacks", &"canned_stew", 5)
	_pick_up(&"west_snow_barrel", &"snow", 14)
	_pick_up(&"gas_firewood", &"firewood", 2)
	assert_eq(_activations.size(), 3, "three route E presses did not produce three commands")

	var hunger_before: float = _survival.value_of(&"hunger")
	var thirst_before: float = _survival.value_of(&"thirst")
	_stove.on_body_entered(_player)
	_director.reconsider()
	assert_eq(_director.focused_id(), &"stove:farmhouse_hearth")
	assert_false(bool(_director.focused_offer().get("guide_line", false)),
		"the hearth added a vertical lead instead of reusing the plain pigeon E ring")
	var expected_tap_verbs := [
		"Cook Tin of stew",
		"Eat Hot stew",
		"Melt Packed snow",
		"Drink Meltwater",
		"Add fuel",
	]
	for verb in expected_tap_verbs:
		assert_eq(_director.focused_offer().get("verb"), verb,
			"the real hearth queue pictured the wrong next atomic action")
		assert_true(_press_e(), "%s never reached the placed stove" % verb)
	var smother_offer: Dictionary = _director.focused_offer()
	assert_eq(smother_offer.get("verb"), "Add fuel",
		"the hearth lost repeated one-item refilling below its capacity")
	assert_true(bool(smother_offer.get("alternate_hold", false)))
	assert_eq(smother_offer.get("hold_verb"), "Extinguish")
	assert_true(_hold_e(), "the real hearth's E hold did not smother the fire")
	assert_eq(_activations.size(), 9, "the nine physical E presses were not one command each")
	assert_eq(_economy.count_of(&"canned_stew"), 4)
	assert_eq(_economy.count_of(&"snow"), 13)
	assert_eq(_economy.count_of(&"hot_stew"), 0)
	assert_eq(_economy.count_of(&"meltwater"), 0)
	assert_eq(_economy.count_of(&"firewood"), 1)
	assert_almost_eq(_stove.fuel_remaining(), 990.0, 0.001,
		"the scene chain did not preserve 600 - 120 - 90 + one 600-second log")
	assert_false(_stove.is_lit(), "the final pictured E action did not smother the real stove")
	assert_true(_survival.value_of(&"hunger") > hunger_before)
	assert_true(_survival.value_of(&"thirst") > thirst_before)
	for payload in _activations:
		for value in (payload as Dictionary).values():
			assert_false(value is Object,
				"InteractionDirector carried a live scene object across the EventBus")

	var day_rate: float = _survival.drain_rate_of(&"core_temperature")
	_bus.emit_event(WorldClockScript.EVENT_NIGHT_STARTED, 1)
	assert_almost_eq(_survival.drain_rate_of(&"core_temperature"), day_rate * 2.0, 0.000001)
	_door.open()
	_reveal.on_body_entered(_player)
	assert_true(_reveal.is_occupant_inside())
	assert_true(_exposure.is_sheltered(), "the real farmhouse entered event never reached NightExposure")
	assert_almost_eq(_survival.drain_rate_of(&"core_temperature"), day_rate, 0.000001,
		"the real interior left the outdoor night penalty on the player")
	_reveal.on_body_exited(_player)
	assert_false(_exposure.is_sheltered())
	assert_almost_eq(_survival.drain_rate_of(&"core_temperature"), day_rate * 2.0, 0.000001,
		"leaving the real interior did not restore outdoor exposure")
	assert_eq(_interior_events, [&"entered", &"exited"],
		"the real threshold did not publish one balanced entered/exited pair")


func test_real_main_surfaces_shortage_death_and_restarts_through_e() -> void:
	for node in [_main, _player, _stove, _director, _result_surfacing,
			_run_result, _exit_menu, _survival, _clock, _bus]:
		assert_not_null(node)
	if null in [_main, _player, _stove, _director, _result_surfacing,
			_run_result, _exit_menu, _survival, _clock, _bus]:
		return

	# The placed fire itself must announce exhaustion through the shipped result
	# consumer; no synthetic outage event is used here.
	_stove.advance(_stove.fuel_remaining() + 1.0)
	_result_surfacing.flush_pending()
	var outage = _result_surfacing.active_for(&"outage:stove:farmhouse_hearth")
	assert_not_null(outage, "the real farmhouse fire died without a visible result")
	if outage != null:
		assert_eq(outage.copy_text(), "Went out · Stove")

	# A lit but empty-pack hearth explains the missing remedy on short E while
	# preserving the same prompt's long-E smother action.
	_stove.add_fuel_seconds(60.0)
	assert_true(_stove.light())
	_survival.advance(510.0)
	_stove.on_body_entered(_player)
	_director.reconsider()
	var shortage_offer: Dictionary = _director.focused_offer()
	assert_eq(shortage_offer.get("verb"), "Eat")
	assert_false(bool(shortage_offer.get("enabled", true)))
	assert_eq(shortage_offer.get("reason"), &"no_food")
	assert_true(bool(shortage_offer.get("hold_enabled", false)))
	assert_false(_press_e(), "a missing-food tap claimed to mutate the world")
	_result_surfacing.flush_pending()
	var shortage = _result_surfacing.active_for(&"rejected:stove:farmhouse_hearth")
	assert_not_null(shortage, "the real E rejection never reached the receipt layer")
	if shortage != null:
		assert_eq(shortage.copy_text(), "Stove · No food")

	# Hand the already-live body and clock to the real lifecycle owner, then let
	# the real survival drain produce death. The test never emits survival.died.
	_stove.extinguish()
	_stove.clear_recovery()
	_survival.stop()
	_clock.stop()
	_bus.subscribe(&"game.restart_requested", _record_restart_requested)
	_bus.subscribe(&"game.run_reset", _record_run_reset)
	_bus.subscribe(&"clock.day_started", _record_day_started)
	_bus.subscribe(&"game.run_started", _record_run_started)
	_game = GameStateScript.new()
	_game.set_event_bus(_bus)
	_game.set_survival_system(_survival)
	_game.set_world_clock(_clock)
	assert_true(_game.begin_run(101))
	_run_events.clear()
	_run_result.set_reload_action(_record_reload)
	_survival.advance(1201.0)
	assert_eq(_game.state(), GameStateScript.STATE_ENDED)
	assert_eq(_game.outcome(), GameStateScript.OUTCOME_DEAD)
	assert_false(_survival.is_running())
	assert_false(_clock.is_running())
	assert_true(_run_result.is_active())
	assert_eq(_run_result.day_text(), "第 一 日。")
	assert_true(_tree.paused, "the real death left input and simulation running")
	_exit_menu.open()
	assert_false(_exit_menu.is_open(), "Escape could still expose Continue after death")

	_run_result.advance(_run_result.RESTART_READY_SECONDS)
	var restart_key := InputEventAction.new()
	restart_key.action = &"interact"
	restart_key.pressed = true
	_run_result._unhandled_input(restart_key)
	assert_eq(_run_events, [
		&"restart_requested", &"run_reset", &"day_started", &"run_started",
	], "E restart crossed the lifecycle boundary out of order")
	assert_true(_run_result.is_reload_pending())
	assert_true(_tree.paused, "the settled scene resumed before replacement")
	assert_true(_survival.is_running())
	assert_false(_survival.is_dead())
	assert_eq(_clock.current_day(), 1)
	assert_true(_clock.is_running())
	assert_eq(_economy.item_ids().filter(func(item_id): return _economy.count_of(item_id) > 0).size(), 0,
		"restart inherited inventory from the dead attempt")
	assert_false(_exposure.is_night())
	assert_false(_exposure.is_sheltered())
	assert_true(_run_result.flush_reload())
	assert_eq(_reload_calls, 1, "successful restart did not replace the scene exactly once")
	assert_false(_tree.paused)
	assert_false(_run_result.is_active())


func _pick_up(node_id: StringName, item_id: StringName, expected_count: int) -> void:
	var pickup = _routes.route_node(node_id)
	assert_not_null(pickup, "the real route layer did not spawn %s" % node_id)
	if pickup == null:
		return
	pickup.set_occupant(_player)
	pickup.body_entered.emit(_player)
	_director.reconsider()
	assert_eq(_director.focused_id(), StringName("pickup:%s" % node_id))
	assert_eq(_director.focused_offer().get("kind"), &"pickup")
	var before: int = _economy.count_of(item_id)
	assert_true(_press_e(), "the real pickup Area did not accept E")
	assert_true(pickup.is_collected(), "the E command left the pickup in the world")
	assert_eq(_economy.count_of(item_id), before + expected_count)


func _press_e() -> bool:
	var activated: bool = bool(_director.advance_interaction(0.0, true, true))
	activated = _director.advance_interaction(0.0, false) or activated
	return activated


func _hold_e() -> bool:
	var duration := float(_director.focused_offer().get("hold_seconds", 0.0))
	var activated: bool = bool(_director.advance_interaction(duration, true, true))
	activated = _director.advance_interaction(0.0, false) or activated
	return activated


func _wire_private_dependencies(node: Node) -> void:
	if node.has_method("set_event_bus"):
		node.call("set_event_bus", _bus)
	if node.has_method("set_fuel_economy"):
		node.call("set_fuel_economy", _economy)
	if node.has_method("set_survival_system"):
		node.call("set_survival_system", _survival)
	if node.has_method("set_world_clock"):
		node.call("set_world_clock", _clock)
	if node.has_method("set_clock"):
		node.call("set_clock", _clock)
	if node.has_method("set_service_registry"):
		node.call("set_service_registry", _registry)
	if node.has_method("set_watched"):
		node.call("set_watched", _player)
	for child in node.get_children():
		_wire_private_dependencies(child)


func _wire_occupants() -> void:
	for node in [_stove, _director, _door, _reveal]:
		if node != null and node.has_method("set_occupant"):
			node.call("set_occupant", _player)


func _record_activation(payload) -> void:
	if payload is Dictionary:
		_activations.append((payload as Dictionary).duplicate(true))


func _record_interior_entered(_payload) -> void:
	_interior_events.append(&"entered")


func _record_interior_exited(_payload) -> void:
	_interior_events.append(&"exited")


func _record_restart_requested(_payload) -> void:
	_run_events.append(&"restart_requested")


func _record_run_reset(_payload) -> void:
	_run_events.append(&"run_reset")


func _record_day_started(_payload) -> void:
	_run_events.append(&"day_started")


func _record_run_started(_payload) -> void:
	_run_events.append(&"run_started")


func _record_reload() -> int:
	_reload_calls += 1
	return OK


func _snapshot_services() -> void:
	if _registry == null:
		return
	for key in SERVICE_KEYS:
		_registry_snapshot[key] = {
			"had": _registry.has(key),
			"service": _registry.get_service(key),
		}


func _restore_services() -> void:
	if _registry == null or not is_instance_valid(_registry):
		return
	for key in SERVICE_KEYS:
		_registry.unregister(key)
		var saved: Dictionary = _registry_snapshot.get(key, {})
		if bool(saved.get("had", false)):
			var service: Variant = saved.get("service", null)
			if service != null and is_instance_valid(service):
				_registry.register(key, service)
