extends SceneTree

## Production scene-reload smoke.
##
## The unit suite cannot call reload_current_scene(): its current scene is the
## test runner itself. This second, short Godot process makes the shipped Main
## current, reaches death through the real SurvivalSystem, sends the real
## interact action through Input, and observes the replacement scene after the
## exact production reload call. Any failure exits non-zero; run_tests.sh also
## requires the success sentinel below.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const PASS_SENTINEL := "Restart scene smoke: PASS"
const MAX_RELOAD_FRAMES := 180

var _phase := 0
var _waited_frames := 0
var _old_main_id := 0
var _old_player_id := 0
var _authored_spawn := Vector3.ZERO


func _initialize() -> void:
	# Work begins on the first process tick, after autoload _ready methods have
	# run and absolute /root lookups are legal.
	pass


func _process(_delta: float) -> bool:
	match _phase:
		0:
			_start_attempt()
		1:
			_kill_and_request_restart()
		2:
			_wait_for_replacement()
	return false


func _start_attempt() -> void:
	var main := MAIN_SCENE.instantiate()
	if main == null:
		_fail("main.tscn could not instantiate")
		return
	root.add_child(main)
	current_scene = main
	_old_main_id = main.get_instance_id()
	var player := main.get_node_or_null("Player") as Node3D
	if player == null:
		_fail("the real Main has no Player")
		return
	_old_player_id = player.get_instance_id()
	_authored_spawn = player.global_position
	# Leave a scene-local value that only a true replacement can erase.
	player.global_position += Vector3(7.0, 0.0, 0.0)
	_phase = 1


func _kill_and_request_restart() -> void:
	var game = root.get_node_or_null("GameState")
	var survival = root.get_node_or_null("SurvivalSystem")
	var clock = root.get_node_or_null("WorldClock")
	if game == null or survival == null or clock == null:
		_fail("run autoloads were not available")
		return
	if not game.is_running() and not game.begin_run(4242):
		_fail("the first real run could not start")
		return
	# No synthetic survival.died: the shipped drains and EventBus settle it.
	survival.advance(2000.0)
	if game.state() != game.STATE_ENDED or game.outcome() != game.OUTCOME_DEAD:
		_fail("real survival depletion did not settle a dead run")
		return
	var result = current_scene.get_node_or_null("RunResult")
	if result == null or not result.is_active() or not paused:
		_fail("death did not claim its visible terminal pause")
		return
	result.advance(result.RESTART_READY_SECONDS)
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	_phase = 2


func _wait_for_replacement() -> void:
	_waited_frames += 1
	if current_scene == null or current_scene.get_instance_id() == _old_main_id:
		if _waited_frames >= MAX_RELOAD_FRAMES:
			_fail("reload_current_scene did not replace Main")
		return
	_validate_replacement()


func _validate_replacement() -> void:
	var game = root.get_node_or_null("GameState")
	var survival = root.get_node_or_null("SurvivalSystem")
	var clock = root.get_node_or_null("WorldClock")
	var economy = root.get_node_or_null("FuelEconomy")
	var registry = root.get_node_or_null("ServiceRegistry")
	if null in [game, survival, clock, economy, registry]:
		_fail("replacement lost a required autoload")
		return
	if is_instance_id_valid(_old_main_id) or is_instance_id_valid(_old_player_id):
		_fail("the settled Main or Player survived scene replacement")
		return
	var player := current_scene.get_node_or_null("Player") as Node3D
	var stove = current_scene.get_node_or_null("Farmhouse/Stove")
	var door = current_scene.get_node_or_null("Farmhouse/Door")
	var reveal = current_scene.get_node_or_null("Farmhouse/InteriorReveal")
	var routes = current_scene.get_node_or_null("SurvivalRoutes")
	var result = current_scene.get_node_or_null("RunResult")
	if null in [player, stove, door, reveal, routes, result]:
		_fail("replacement Main is missing a production node")
		return
	var horizontal_error := Vector2(
		player.global_position.x - _authored_spawn.x,
		player.global_position.z - _authored_spawn.z
	).length()
	var vertical_error := absf(player.global_position.y - _authored_spawn.y)
	if horizontal_error > 0.05 or vertical_error > 0.25:
		_fail("Player did not return to the authored spawn (expected %s, got %s)" \
			% [_authored_spawn, player.global_position])
		return
	if registry.get_service(&"player") != player:
		_fail("ServiceRegistry still points at the old Player")
		return
	if not stove.is_lit() or stove.fuel_remaining() < 590.0 \
			or stove.fuel_remaining() > stove.starting_fuel_seconds:
		_fail("the replacement Stove did not restore its authored fire")
		return
	if door.is_open() or reveal.is_occupant_inside():
		_fail("the replacement farmhouse inherited an interior state")
		return
	for route_node in routes.route_nodes():
		if route_node.is_collected():
			_fail("a replacement route pickup stayed collected")
			return
	if result.is_active() or paused:
		_fail("the replacement kept the terminal UI or pause")
		return
	if not game.is_running() or survival.is_dead() or not survival.is_running():
		_fail("the replacement did not keep the restarted body running")
		return
	if not clock.is_running() or clock.current_day() != 1 or clock.is_night() \
			or clock.phase_elapsed() > 1.0:
		_fail("the replacement did not resume at day-one daylight")
		return
	for item_id in economy.item_ids():
		if economy.count_of(item_id) != 0:
			_fail("the replacement inherited carried inventory")
			return
	print(PASS_SENTINEL)
	quit(0)


func _fail(message: String) -> void:
	printerr("Restart scene smoke failed: %s" % message)
	quit(1)
	_phase = 99
