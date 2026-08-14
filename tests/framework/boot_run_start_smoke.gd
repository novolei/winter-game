extends SceneTree

## Production boot-lifecycle smoke.
##
## This process runs the shipped Boot scene, not a unit double.  It watches the
## real Main while Boot holds it at PROCESS_MODE_DISABLED and proves that both
## autoload simulations remain inert.  Only after Boot restores Main may its
## RunLifecycle request the fixed-seed attempt.

const BOOT_SCENE := preload("res://scenes/boot.tscn")
# The world is cached so this short-lived subprocess tests the Boot boundary,
# not ResourceLoader's background-thread shutdown bookkeeping. Boot still owns
# instantiation, PROCESS_MODE_DISABLED staging and the final hand-off.
const MAIN_SCENE := preload("res://scenes/main.tscn")
const PASS_SENTINEL := "Boot run-start smoke: PASS"
const MAX_SECONDS := 30.0
const CLEANUP_FRAMES := 8
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_RUN_STARTED := &"game.run_started"

var _phase := 0
var _started_ms := 0
var _boot: Node = null
var _game = null
var _survival = null
var _clock = null
var _initial_values: Dictionary = {}
var _event_order: Array[StringName] = []
var _saw_disabled_world := false
var _active_wait_frames := 0
var _cleanup_frames := 0


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if float(Time.get_ticks_msec() - _started_ms) / 1000.0 > MAX_SECONDS:
		_fail("the shipped Boot did not hand control to Main within %.0f seconds" % MAX_SECONDS)
		return false
	match _phase:
		0:
			_start_boot()
		1:
			_watch_boot_boundary()
		2:
			_finish_cleanly()
	return false


func _start_boot() -> void:
	_game = root.get_node_or_null("GameState")
	_survival = root.get_node_or_null("SurvivalSystem")
	_clock = root.get_node_or_null("WorldClock")
	var bus = root.get_node_or_null("EventBus")
	if null in [_game, _survival, _clock, bus]:
		_fail("a required run autoload was unavailable")
		return
	if _game.state() != _game.STATE_IDLE or _survival.is_running() or _clock.is_running():
		_fail("autoload simulation began before the Boot scene existed")
		return
	_game.run_seed = 1729
	for stat_id in _survival.stat_ids():
		_initial_values[stat_id] = _survival.value_of(stat_id)
	bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	bus.subscribe(EVENT_RUN_STARTED, _on_run_started)
	_boot = BOOT_SCENE.instantiate()
	if _boot == null:
		_fail("boot.tscn could not instantiate")
		return
	root.add_child(_boot)
	current_scene = _boot
	_phase = 1


func _watch_boot_boundary() -> void:
	if current_scene == null:
		_fail("Boot left the SceneTree without a Main replacement")
		return
	var world_is_main := current_scene != _boot and current_scene.name == "Main"
	if not world_is_main:
		_assert_inert("while the splash owned current_scene")
		return
	if current_scene.process_mode == Node.PROCESS_MODE_DISABLED:
		_saw_disabled_world = true
		_assert_inert("while Main was staged but disabled")
		return
	if not _game.is_running():
		_active_wait_frames += 1
		_assert_inert("during Main's sibling-attachment frame")
		if _active_wait_frames > 10:
			_fail("active Main never requested its first run")
		return
	_validate_started_world()


func _assert_inert(context: String) -> void:
	if _game.is_running() or _survival.is_running() or _clock.is_running():
		_fail("the attempt started %s" % context)
		return
	if absf(_clock.phase_elapsed()) > 0.000001:
		_fail("the calendar advanced %s" % context)
		return
	if not _event_order.is_empty():
		_fail("start events escaped %s" % context)
		return
	for stat_id in _initial_values:
		if absf(_survival.value_of(stat_id) - float(_initial_values[stat_id])) > 0.000001:
			_fail("%s changed %s" % [stat_id, context])
			return


func _validate_started_world() -> void:
	if not _saw_disabled_world:
		_fail("the smoke never observed Boot's real disabled-Main preparation window")
		return
	if _event_order != [EVENT_DAY_STARTED, EVENT_RUN_STARTED]:
		_fail("first-run event order was %s" % [_event_order])
		return
	if not _survival.is_running() or not _clock.is_running():
		_fail("GameState started without both simulations")
		return
	if _game.current_run_seed() != 1729:
		_fail("Boot lost the requested replay seed")
		return
	if _clock.current_day() != 1 or _clock.is_night() or _clock.phase_elapsed() > 0.25:
		_fail("the playable world did not begin at fresh day-one daylight")
		return
	var weather = current_scene.get_node_or_null("Weather")
	if weather == null or weather.current_run_seed() != 1729:
		_fail("Weather attached before the fixed run seed became authoritative")
		return
	var snow_field = current_scene.get_node_or_null("SnowField")
	if snow_field == null or snow_field.current_run_seed() != 1729:
		_fail("SnowField did not receive the first attempt's fixed seed")
		return
	var beacons = current_scene.get_node_or_null("BeaconNetwork")
	if beacons == null or beacons.current_run_seed() != 1729:
		_fail("BeaconNetwork kept its fallback seed on the first attempt")
		return
	if is_instance_valid(_boot) and _boot.is_inside_tree():
		_fail("the attempt began while the splash still owned the screen")
		return
	_begin_cleanup()


func _begin_cleanup() -> void:
	var bus = root.get_node_or_null("EventBus")
	if bus != null:
		bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
		bus.unsubscribe(EVENT_RUN_STARTED, _on_run_started)
	_survival.stop()
	_clock.stop()
	var scene := current_scene
	current_scene = null
	if scene != null and is_instance_valid(scene):
		scene.free()
	if is_instance_valid(_boot):
		_boot.free()
	_boot = null
	_phase = 2


func _finish_cleanly() -> void:
	_cleanup_frames += 1
	if _cleanup_frames < CLEANUP_FRAMES:
		return
	print(PASS_SENTINEL)
	quit(0)
	_phase = 99


func _on_day_started(_payload) -> void:
	_event_order.append(EVENT_DAY_STARTED)


func _on_run_started(_payload) -> void:
	_event_order.append(EVENT_RUN_STARTED)


func _fail(message: String) -> void:
	printerr("Boot run-start smoke failed: %s" % message)
	quit(1)
	_phase = 99
