extends TestCase

## Unit tests for src/systems/survival_system.gd.
##
## Every subject here is built from definitions constructed IN THIS FILE, never
## from res://data/stats. That separation is deliberate: this file tests the
## machine, and tests/unit/test_survival_stats_data.gd tests the five stats the
## game ships. Mixing them would mean a tuning change to a .tres broke the
## machine's tests, which is exactly the coupling the data-driven design exists
## to avoid.

const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const StatDefinitionScript := preload("res://src/definitions/stat_definition.gd")
const ThresholdEffectScript := preload("res://src/definitions/threshold_effect.gd")
const StatModifierScript := preload("res://src/definitions/stat_modifier.gd")

## SurvivalSystem and EventBus both extend Node, which is not reference-counted.
## Both are freed in after_each(), or the suite reports leaked ObjectDB
## instances and the output stops being pristine (briefing constraint 2).
var _system = null
var _bus = null
var _events: Array = []

func before_each() -> void:
	_events = []

func after_each() -> void:
	if _system != null:
		_system.free()
		_system = null
	if _bus != null:
		_bus.free()
		_bus = null

# --- helpers ---------------------------------------------------------------

func _record(payload) -> void:
	_events.append(payload)

func _events_of(event_kind: String) -> Array:
	var found := []
	for payload in _events:
		if payload is Dictionary and payload.get("event", "") == event_kind:
			found.append(payload)
	return found

## Subscribes with a distinct recorder per event so a payload can be told apart
## after the fact. EventBus dispatches exactly one argument, so each callback
## declares exactly one parameter.
func _record_crossed(payload) -> void:
	var copy: Dictionary = (payload as Dictionary).duplicate()
	copy["event"] = "crossed"
	_events.append(copy)

func _record_depleted(payload) -> void:
	var copy: Dictionary = (payload as Dictionary).duplicate()
	copy["event"] = "depleted"
	_events.append(copy)

func _record_recovered(payload) -> void:
	var copy: Dictionary = (payload as Dictionary).duplicate()
	copy["event"] = "recovered"
	_events.append(copy)

func _record_died(payload) -> void:
	var copy: Dictionary = (payload as Dictionary).duplicate()
	copy["event"] = "died"
	_events.append(copy)

func _make_stat(id: StringName, decay: float, lethal := false, effects := []) -> StatDefinition:
	# Annotated, not `var stat =`. An untyped local makes the compiler emit an
	# untyped Array for the threshold_effects assignment below, the typed setter
	# rejects it, and the VM ABORTS the rest of this function (briefing trap 4).
	var stat: StatDefinition = StatDefinitionScript.new()
	stat.id = id
	stat.display_name = String(id)
	stat.initial_value = 1.0
	stat.min_value = 0.0
	stat.max_value = 1.0
	stat.base_decay_per_second = decay
	stat.lethal_at_min = lethal
	var typed: Array[ThresholdEffect] = []
	for effect in effects:
		typed.append(effect)
	stat.threshold_effects = typed
	return stat

func _make_effect(
	watch: StringName,
	threshold: float,
	target: StringName,
	operation: int,
	value: float,
	comparison := ThresholdEffect.Comparison.BELOW
) -> ThresholdEffect:
	var effect: ThresholdEffect = ThresholdEffectScript.new()
	effect.watch_stat = watch
	effect.comparison = comparison
	effect.threshold = threshold
	effect.target_stat = target
	effect.operation = operation
	effect.value = value
	return effect

func _build(definitions: Array):
	_bus = EventBusScript.new()
	_bus.subscribe(&"survival.threshold_crossed", _record_crossed)
	_bus.subscribe(&"survival.stat_depleted", _record_depleted)
	_bus.subscribe(&"survival.stat_recovered", _record_recovered)
	_bus.subscribe(&"survival.died", _record_died)
	_system = SurvivalSystemScript.new()
	_system.set_event_bus(_bus)
	_system.load_definitions(definitions)
	_system.start()
	return _system

# --- loading and the base clock --------------------------------------------

func test_stats_load_with_their_initial_values() -> void:
	var system = _build([_make_stat(&"warmth", 0.01), _make_stat(&"food", 0.02)])
	assert_eq(system.stat_ids().size(), 2, "both definitions should be loaded")
	assert_almost_eq(system.value_of(&"warmth"), 1.0, 0.0001, "a stat starts at its initial value")
	assert_true(system.has_stat(&"food"), "has_stat should report a loaded stat")

func test_stat_ids_cannot_be_mutated_through_the_getter() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	var ids: Array = system.stat_ids()
	ids.append(&"smuggled")
	assert_eq(system.stat_ids().size(), 1, "the returned id list must be a copy, not the system's own")
	assert_false(system.has_stat(&"smuggled"), "writing to the returned array must not add a stat")

func test_base_decay_drains_a_stat() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	system.advance(10.0)
	assert_almost_eq(system.value_of(&"warmth"), 0.9, 0.0005, "10 s at 0.01/s should cost 0.1")

func test_a_value_never_falls_below_its_minimum() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	system.advance(500.0)
	assert_almost_eq(system.value_of(&"warmth"), 0.0, 0.0001, "a stat clamps at min_value")

func test_a_value_never_rises_above_its_maximum() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	system.advance(10.0)
	system.restore(&"warmth", 5.0)
	assert_almost_eq(system.value_of(&"warmth"), 1.0, 0.0001, "a stat clamps at max_value")

func test_one_large_step_matches_many_small_ones() -> void:
	# The interlock crossing at 0.5 is what makes this a real test: an
	# implementation that integrates a 60 s call as ONE step evaluates the rate
	# once, misses the crossing entirely, and lands on 0.4 instead of 0.3.
	var effect := _make_effect(&"warmth", 0.5, &"warmth", Modifier.Operation.MULTIPLY, 2.0)
	var coarse = _build([_make_stat(&"warmth", 0.01, false, [effect])])
	coarse.advance(60.0)
	var coarse_value: float = coarse.value_of(&"warmth")
	# Both, and both nulled: _build() overwrites _bus as well, and after_each()
	# can only free what it can still see. The bus left behind here was three
	# ObjectDB instances at exit and a dirty console.
	coarse.free()
	_system = null
	_bus.free()
	_bus = null

	var fine = _build([_make_stat(&"warmth", 0.01, false, [effect])])
	for _i in 60:
		fine.advance(1.0)
	assert_almost_eq(coarse_value, fine.value_of(&"warmth"), 0.002, "one 60 s step must land where sixty 1 s steps do")
	assert_almost_eq(coarse_value, 0.3, 0.005, "0.5 at plain rate then 10 s at double rate leaves 0.3")

func test_advance_before_start_is_inert() -> void:
	_bus = EventBusScript.new()
	_system = SurvivalSystemScript.new()
	_system.set_event_bus(_bus)
	_system.load_definitions([_make_stat(&"warmth", 0.01)])
	_system.advance(100.0)
	assert_almost_eq(_system.value_of(&"warmth"), 1.0, 0.0001, "nothing drains until the run starts")
	assert_false(_system.is_running(), "the system is not running until start()")

func test_stop_freezes_the_model() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	system.advance(10.0)
	system.stop()
	var frozen: float = system.value_of(&"warmth")
	system.advance(100.0)
	assert_false(system.is_running(), "stop() ends the run")
	assert_almost_eq(system.value_of(&"warmth"), frozen, 0.0001, "and a body whose run is over stops draining")

# --- interlocks ------------------------------------------------------------

func test_a_threshold_effect_multiplies_the_target_drain() -> void:
	var effect := _make_effect(&"food", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [effect]),
	])
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "no interlock while food is high")
	system.advance(8.0)  # food 1.0 -> 0.2, below the 0.3 threshold
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.015, 0.0001, "a hungry body loses heat 1.5x faster")

func test_a_threshold_effect_is_removed_when_the_condition_lifts() -> void:
	var effect := _make_effect(&"food", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [effect]),
	])
	system.advance(8.0)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.015, 0.0001, "the interlock is active while hungry")
	system.restore(&"food", 1.0)
	system.advance(0.25)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "eating must take the modifier off again")

func test_a_holding_threshold_effect_is_applied_exactly_once() -> void:
	# The accumulation bug this design exists to prevent: adding the modifier
	# every tick while the condition holds would compound 1.5x per frame.
	var effect := _make_effect(&"food", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [effect]),
	])
	system.advance(8.0)
	system.advance(1.0)
	assert_eq(system.modifier_count(&"warmth:drain"), 1, "one active interlock is one modifier, however many ticks pass")
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.015, 0.0001, "and the rate stays 1.5x, not 1.5^n")

func test_an_above_comparison_works() -> void:
	var effect := _make_effect(
		&"food", 0.5, &"warmth", Modifier.Operation.MULTIPLY, 0.5,
		ThresholdEffect.Comparison.ABOVE
	)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [effect]),
	])
	system.advance(0.25)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.005, 0.0001, "a well fed body holds its heat")
	system.advance(6.0)  # food falls under 0.5
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "and loses the bonus once it is no longer above")

func test_a_recovery_modifier_offsets_the_drain() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	var modifier: StatModifier = StatModifierScript.new()
	modifier.target_stat = &"warmth:recovery"
	modifier.source_id = &"stove"
	modifier.operation = Modifier.Operation.ADD
	modifier.value = 0.03
	modifier.duration = -1.0
	system.apply_stat_modifier(modifier)
	assert_almost_eq(system.recovery_rate_of(&"warmth"), 0.03, 0.0001, "the fire recovers 0.03/s")
	assert_almost_eq(system.net_rate_of(&"warmth"), 0.02, 0.0001, "net rate is recovery minus drain")
	system.advance(10.0)
	assert_almost_eq(system.value_of(&"warmth"), 1.0, 0.0001, "and it cannot push past the maximum")

## The sign trap, and the reason drain and recovery are separate stacks.
##
## With one stack per stat, a fire would be an ADD of a negative number onto
## the drain, and (base + sum ADD) * product MULTIPLY would then make "you tire
## faster when dehydrated" -- a MULTIPLY above 1 -- scale a NEGATIVE total and
## recover you FASTER. Two stacks make that unrepresentable.
func test_scaling_recovery_leaves_the_drain_alone() -> void:
	var effect := _make_effect(&"water", 0.3, &"rest:recovery", Modifier.Operation.MULTIPLY, 0.5)
	var system = _build([
		_make_stat(&"rest", 0.01),
		_make_stat(&"water", 0.1, false, [effect]),
	])
	var modifier: StatModifier = StatModifierScript.new()
	modifier.target_stat = &"rest:recovery"
	modifier.source_id = &"sleep"
	modifier.operation = Modifier.Operation.ADD
	modifier.value = 0.04
	system.apply_stat_modifier(modifier)
	assert_almost_eq(system.recovery_rate_of(&"rest"), 0.04, 0.0001, "hydrated, sleep recovers at full rate")
	system.advance(8.0)  # water falls below 0.3
	assert_almost_eq(system.recovery_rate_of(&"rest"), 0.02, 0.0001, "dehydrated, the same sleep recovers half as fast")
	assert_almost_eq(system.drain_rate_of(&"rest"), 0.01, 0.0001, "and the drain is untouched -- the sign trap")

func test_a_threshold_effect_can_drive_a_behaviour_channel() -> void:
	var effect := _make_effect(&"rest", 0.3, &"locomotion:speed", Modifier.Operation.MULTIPLY, 0.85)
	var system = _build([_make_stat(&"rest", 0.1, false, [effect])])
	assert_almost_eq(system.channel_value(&"locomotion:speed", 4.0), 4.0, 0.0001, "a rested man walks at full speed")
	system.advance(8.0)
	assert_almost_eq(system.channel_value(&"locomotion:speed", 4.0), 3.4, 0.0001, "an exhausted one is slowed by data alone")

func test_channel_value_returns_the_base_when_nothing_modifies_it() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	assert_almost_eq(system.channel_value(&"aim:steadiness", 1.0), 1.0, 0.0001, "an unheard-of channel is the identity")

# --- events ----------------------------------------------------------------

func test_a_threshold_crossing_is_announced_once_per_threshold() -> void:
	# Two effects at the same threshold on the same stat: subscribers hear one
	# crossing, not one per target.
	var to_warmth := _make_effect(&"food", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var to_speed := _make_effect(&"food", 0.3, &"locomotion:speed", Modifier.Operation.MULTIPLY, 0.9)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [to_warmth, to_speed]),
	])
	system.advance(8.0)
	var crossings := _events_of("crossed")
	assert_eq(crossings.size(), 1, "one threshold crossed is one event, whatever it drives")
	assert_eq(system.active_threshold_count(), 1, "and one threshold is holding, not two")
	if crossings.is_empty():
		return
	assert_eq(crossings[0]["stat"], &"food", "the payload names the stat that crossed")
	assert_true(crossings[0]["active"], "and reports the threshold as entered")
	assert_almost_eq(crossings[0]["threshold"], 0.3, 0.0001, "and which threshold it was")

func test_leaving_a_threshold_is_announced_too() -> void:
	var effect := _make_effect(&"food", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [effect]),
	])
	system.advance(8.0)
	system.restore(&"food", 1.0)
	system.advance(0.25)
	var crossings := _events_of("crossed")
	assert_eq(crossings.size(), 2, "entering and leaving are both readable")
	if crossings.size() < 2:
		return
	assert_false(crossings[1]["active"], "the second event reports the threshold as left")

func test_a_depleted_stat_is_announced_once() -> void:
	var system = _build([_make_stat(&"water", 0.5)])
	system.advance(5.0)
	system.advance(5.0)
	var depleted := _events_of("depleted")
	assert_eq(depleted.size(), 1, "a stat bottoming out announces itself exactly once")
	if depleted.is_empty():
		return
	assert_eq(depleted[0]["stat"], &"water", "the payload names the stat")

func test_a_stat_that_comes_back_is_announced() -> void:
	var system = _build([_make_stat(&"water", 0.5)])
	system.advance(5.0)
	system.restore(&"water", 0.6)
	system.advance(0.25)
	assert_eq(_events_of("recovered").size(), 1, "coming off the floor is readable too")
	assert_almost_eq(system.value_of(&"water"), 0.475, 0.01, "and the value really did come back")

func test_a_lethal_stat_reaching_zero_kills_and_stops_the_clock() -> void:
	var system = _build([
		_make_stat(&"warmth", 0.5, true),
		_make_stat(&"food", 0.01),
	])
	system.advance(3.0)
	assert_true(system.is_dead(), "core temperature at zero ends the run")
	assert_eq(_events_of("died").size(), 1, "death is announced exactly once")
	var food_at_death: float = system.value_of(&"food")
	system.advance(100.0)
	assert_almost_eq(system.value_of(&"food"), food_at_death, 0.0001, "nothing ticks after death")
	assert_eq(_events_of("died").size(), 1, "and death is not announced twice")

func test_a_non_lethal_stat_reaching_zero_does_not_kill() -> void:
	# Frostbite is the reason this branch exists: GDD section 5 says it never
	# kills directly, however far it goes.
	var system = _build([_make_stat(&"hands", 0.5, false)])
	system.advance(3.0)
	assert_almost_eq(system.value_of(&"hands"), 0.0, 0.0001, "the limb is gone")
	assert_false(system.is_dead(), "and the man is not")
	assert_eq(_events_of("died").size(), 0, "no death event")

func test_start_after_death_begins_again() -> void:
	var system = _build([_make_stat(&"warmth", 0.5, true)])
	system.advance(3.0)
	assert_true(system.is_dead(), "dead first")
	system.start()
	assert_false(system.is_dead(), "permadeath restarts from day 1, so the model must reset")
	assert_almost_eq(system.value_of(&"warmth"), 1.0, 0.0001, "values return to their initial state")

# --- the API other systems use ---------------------------------------------

func test_content_modifiers_apply_and_are_removed_by_source() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	var blizzard: StatModifier = StatModifierScript.new()
	blizzard.target_stat = &"warmth"
	blizzard.source_id = &"blizzard"
	blizzard.operation = Modifier.Operation.MULTIPLY
	blizzard.value = 2.0
	blizzard.duration = -1.0
	assert_true(system.apply_stat_modifier(blizzard), "a modifier naming a known stat is accepted")
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.02, 0.0001, "a blizzard doubles the heat loss")
	assert_eq(system.remove_source(&"blizzard"), 1, "removing by source takes exactly one modifier off")
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "and the rate returns to base")
	assert_false(system.apply_stat_modifier(null), "and there is nothing to apply in nothing")

func test_a_timed_modifier_expires_on_its_own() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	var gust: StatModifier = StatModifierScript.new()
	gust.target_stat = &"warmth"
	gust.source_id = &"gust"
	gust.operation = Modifier.Operation.MULTIPLY
	gust.value = 3.0
	gust.duration = 5.0
	system.apply_stat_modifier(gust)
	system.advance(2.0)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.03, 0.0001, "still gusting at 2 s")
	system.advance(4.0)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "expired by 6 s")

func test_restore_raises_a_value_and_refuses_to_lower_one() -> void:
	var system = _build([_make_stat(&"water", 0.01)])
	system.advance(50.0)
	system.restore(&"water", 0.2)
	assert_almost_eq(system.value_of(&"water"), 0.7, 0.001, "drinking puts 0.2 back")
	system.restore(&"water", -0.5)
	assert_almost_eq(system.value_of(&"water"), 0.7, 0.001, "restore is not a back door for writing values down")

func test_unknown_stats_read_as_empty_and_report_absent() -> void:
	var system = _build([_make_stat(&"warmth", 0.01)])
	assert_false(system.has_stat(&"sanity"), "an unknown stat is absent")
	assert_almost_eq(system.value_of(&"sanity"), 0.0, 0.0001, "and reads as zero rather than crashing")
	assert_almost_eq(system.fraction_of(&"warmth"), 1.0, 0.0001, "a full stat is 1.0 of its range")

func test_an_effect_naming_an_unknown_stat_is_inert() -> void:
	# W1-D3: these are bare StringNames that nothing resolves. A typo must be a
	# no-op, not a crash -- the shipped data is gated in test_survival_stats_data.
	var typo := _make_effect(&"hungr", 0.3, &"warmth", Modifier.Operation.MULTIPLY, 1.5)
	var system = _build([
		_make_stat(&"warmth", 0.01),
		_make_stat(&"food", 0.1, false, [typo]),
	])
	system.advance(20.0)
	assert_almost_eq(system.drain_rate_of(&"warmth"), 0.01, 0.0001, "an effect watching a stat that does not exist never fires")
	assert_false(system.is_dead(), "and does not take the system down with it")

func test_limbs_are_addressable_independently() -> void:
	# GDD section 5: frostbite is LOCALISED. Hands and feet must be separately
	# damageable or the hands/feet distinction cannot exist.
	var to_hands := _make_effect(&"warmth", 0.5, &"hands", Modifier.Operation.ADD, 0.02)
	var system = _build([
		_make_stat(&"warmth", 0.1, true, [to_hands]),
		_make_stat(&"hands", 0.0),
		_make_stat(&"feet", 0.0),
	])
	system.advance(6.0)
	assert_true(system.value_of(&"hands") < 0.99, "the cold took the hands")
	assert_almost_eq(system.value_of(&"feet"), 1.0, 0.0001, "and left the feet alone")

# --- the data-driven promise ------------------------------------------------

## Briefing constraint 4, machine-checked: a sixth stat AND a brand new
## interlock between it and an existing one, added as .tres files only, with no
## line of GDScript anywhere in src/ aware that either exists.
func test_a_sixth_stat_and_a_new_interlock_need_no_code() -> void:
	var dir_path := "user://test_survival_sixth_stat"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var sanity_effect := _make_effect(&"sanity", 0.5, &"warmth", Modifier.Operation.MULTIPLY, 2.0)
	var sanity := _make_stat(&"sanity", 0.1, false, [sanity_effect])
	var warmth := _make_stat(&"warmth", 0.01)
	var sanity_path := dir_path.path_join("sanity.tres")
	var warmth_path := dir_path.path_join("warmth.tres")
	assert_eq(ResourceSaver.save(sanity, sanity_path), OK, "the new stat should save")
	assert_eq(ResourceSaver.save(warmth, warmth_path), OK, "the existing stat should save")

	_bus = EventBusScript.new()
	_system = SurvivalSystemScript.new()
	_system.set_event_bus(_bus)
	var loaded: int = _system.load_from_directory(dir_path)
	_system.start()
	assert_eq(loaded, 2, "both .tres files should be picked up from the directory")
	assert_true(_system.has_stat(&"sanity"), "the sixth stat exists because a file exists")
	_system.advance(6.0)
	assert_almost_eq(_system.drain_rate_of(&"warmth"), 0.02, 0.0001, "and its brand new interlock bites")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sanity_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(warmth_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))

# --- wiring -----------------------------------------------------------------

## The regression test for briefing trap 3, mirroring test_world_clock.gd's.
##
## _ready() resolves the bus with get_node_or_null("/root/EventBus"). Written
## the plausible-looking wrong way -- Engine.get_singleton / has_singleton -- it
## returns null forever, because a project [autoload] entry is a node under
## /root and never enters the engine's singleton registry. Every other test in
## this file injects a bus and never puts the system in a tree, so _ready()
## never runs and none of them can see it.
func test_ready_resolves_the_autoloaded_bus_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		return
	# Untyped on purpose: statically this is a Node, and a Node has no
	# subscribe(), so the call must dispatch dynamically.
	var bus = tree.root.get_node_or_null("EventBus")
	assert_not_null(bus, "the EventBus autoload must be present at /root/EventBus")
	if bus == null:
		return

	# NOT assigned to _bus: after_each() frees _bus, and this one is the live
	# autoload, not ours to free.
	bus.subscribe(&"survival.died", _record_died)

	_system = SurvivalSystemScript.new()
	# No set_event_bus() on purpose. Entering the tree fires _ready(), which is
	# the code path under test.
	tree.root.add_child(_system)
	_system.load_definitions([_make_stat(&"warmth", 1.0, true)])
	_system.start()
	_system.advance(2.0)

	# Unwind before asserting: the bus is global state shared with every later
	# test, and a Node left under /root leaks at exit.
	bus.unsubscribe(&"survival.died", _record_died)
	tree.root.remove_child(_system)

	assert_eq(_events_of("died").size(), 1, "death must reach the bus that _ready() resolved from /root")

func test_ready_loads_the_shipped_stats_when_nothing_was_injected() -> void:
	_system = SurvivalSystemScript.new()
	_bus = EventBusScript.new()
	_system.set_event_bus(_bus)
	_system.load_from_directory()
	assert_true(_system.stat_ids().size() >= 5, "the default directory is res://data/stats and it holds the shipped model")
	assert_true(_system.has_stat(&"core_temperature"), "and core temperature is in it")
