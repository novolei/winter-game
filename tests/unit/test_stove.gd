extends TestCase

## The stove: the only thing in the game that gives anything back.
##
## GDD section 5's funnel has one arrow into it and four out of it, and all five
## pass through here -- fuel goes in, and warmth, water, food and rest come out.
## Until this existed the player could only decline.
##
## Most of these run against the SHIPPED survival model rather than against a
## toy one, because the thing worth protecting is not "a number went up", it is
## the proportion between the restore side and the drain side. A fire that put
## warmth back at a hundredth of the rate the winter takes it would pass every
## test that only checked the sign, and nothing on screen would say otherwise.
## The three scenario tests at the bottom are the ones that would catch it.

const StoveScript := preload("res://src/entities/stove/stove.gd")
const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

const STOVE_SCENE := "res://scenes/entities/stove/stove.tscn"

## GDD section 4: every one of the seven days is 900 s. Day 1 is 600 s of
## daylight and 300 s of night.
const DAY_SECONDS := 900.0
const DAY_ONE_DAYLIGHT := 600.0
const DAY_ONE_NIGHT := 300.0

## Where the man stands. HEARTH is at the stove; OUTSIDE is far enough away that
## no falloff reaches him.
const HEARTH := Vector3.ZERO
const OUTSIDE := Vector3(40.0, 0.0, 0.0)

var _stove = null
var _second_stove = null
var _economy = null
var _survival = null
var _bus = null
var _events: Array = []

func before_each() -> void:
	_events = []

func after_each() -> void:
	# Every one of these extends Node, which is not reference counted: a missed
	# free() is a leaked ObjectDB instance and a failed run (briefing
	# constraint 2). The stoves go first -- they hold modifiers on the survival
	# model, and _exit_tree() is not called for a node that was never in a tree.
	for node in [_stove, _second_stove, _economy, _survival, _bus]:
		if node != null:
			node.free()
	_stove = null
	_second_stove = null
	_economy = null
	_survival = null
	_bus = null

# --- helpers ---------------------------------------------------------------

func _record(payload) -> void:
	_events.append(payload)

## A stove wired to an economy holding one log, and to the SHIPPED survival
## model. Nothing is lit and nothing is in the firebox yet.
func _build():
	_bus = EventBusScript.new()
	_bus.subscribe(&"stove.lit", _record)
	_bus.subscribe(&"stove.went_out", _record)

	_economy = FuelEconomyScript.new()
	_economy.load_from_directory()

	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	_economy.set_survival_system(_survival)

	_stove = StoveScript.new()
	_stove.set_fuel_economy(_economy)
	_stove.set_survival_system(_survival)
	_stove.set_event_bus(_bus)
	return _stove

## A lit stove with `seconds` banked, and nothing taken out of the store to do
## it -- for the tests that are about what a fire DOES rather than what it costs.
func _build_lit(seconds := 600.0):
	var stove = _build()
	stove.add_fuel_seconds(seconds)
	stove.light()
	return stove

## Advances the fire and the body together, in the sub-steps the survival model
## already integrates in, with the man standing at `point`. One call is a
## stretch of game time with somebody living through it.
func _spend(seconds: float, point: Vector3) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		var slice: float = minf(0.25, seconds - elapsed)
		# Recovery first, then time: a modifier pushed after the integration
		# would credit the slice it was not present for.
		_stove.apply_recovery(point)
		_stove.advance(slice)
		_survival.advance(slice)
		elapsed += slice

## Drops a stat by leaning on its own drain. There is no setter on the survival
## model, deliberately, and a test harness does not get one either.
func _drop_to(stat_id: StringName, value: float) -> void:
	_survival.push_modifier(stat_id, &"test_drop", Modifier.Operation.MULTIPLY, 200.0)
	var guard := 0
	while _survival.value_of(stat_id) > value and not _survival.is_dead() and guard < 10000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")

# --- fuel in ----------------------------------------------------------------

func test_a_new_stove_is_cold_and_empty() -> void:
	var stove = _build()
	assert_false(stove.is_lit(), "the stove starts lit with nothing in it")
	assert_eq(stove.fuel_remaining(), 0.0, "the firebox starts stocked")

func test_it_will_not_light_with_nothing_to_burn() -> void:
	var stove = _build()
	assert_false(stove.light(), "a stove with an empty firebox lit anyway")
	assert_false(stove.is_lit())

func test_stoking_takes_a_log_off_the_pile_and_banks_its_burn_time() -> void:
	var stove = _build()
	_economy.add(&"firewood", 2)
	var log_seconds: float = _economy.definition_of(&"firewood").fuel_value
	assert_true(stove.stoke(&"firewood"), "the log was refused")
	assert_almost_eq(
		stove.fuel_remaining(),
		log_seconds,
		0.001,
		"a log is worth its own fuel_value in the firebox and nothing else"
	)
	assert_eq(_economy.count_of(&"firewood"), 1, "the log is still on the pile after being burnt")

func test_stoking_something_you_do_not_have_changes_nothing() -> void:
	var stove = _build()
	assert_false(stove.stoke(&"firewood"), "a log that does not exist went on the fire")
	assert_eq(stove.fuel_remaining(), 0.0)
	_economy.add(&"meltwater", 1)
	assert_false(stove.stoke(&"meltwater"), "a cup of water was burnt as fuel")

## Banking the fire for a stretch is the beacon-shaped call: name the seconds,
## not the item, and take the cheapest fuel that covers it.
func test_banking_the_fire_spends_the_cheapest_fuel_first() -> void:
	var stove = _build()
	_economy.add(&"firewood", 1)
	_economy.add(&"coal", 1)
	var banked: float = stove.stoke_for(60.0)
	assert_almost_eq(banked, 600.0, 0.001, "that was not the firewood")
	assert_eq(_economy.count_of(&"coal"), 1, "the hoarded coal went on first")
	assert_almost_eq(stove.fuel_remaining(), 600.0, 0.001, "the surplus of the log was thrown away")

func test_a_lit_stove_burns_its_fuel_down() -> void:
	var stove = _build_lit(600.0)
	stove.advance(120.0)
	assert_almost_eq(stove.fuel_remaining(), 480.0, 0.001, "at burn_rate 1.0 a second costs a second")
	assert_true(stove.is_lit())

func test_a_cold_stove_burns_nothing() -> void:
	var stove = _build()
	stove.add_fuel_seconds(600.0)
	stove.advance(120.0)
	assert_almost_eq(stove.fuel_remaining(), 600.0, 0.001, "an unlit stove consumed its fuel")

func test_it_goes_out_when_the_fuel_runs_out() -> void:
	var stove = _build_lit(30.0)
	stove.advance(60.0)
	assert_false(stove.is_lit(), "the fire is still burning on nothing")
	assert_eq(stove.fuel_remaining(), 0.0, "the fuel went negative")

## GDD section 9 has no HUD, so the fire dying has to be announced or nothing
## else in the game can react to it -- not the music, not the audio, not a
## beacon going dark.
func test_lighting_and_going_out_are_announced() -> void:
	var stove = _build_lit(30.0)
	assert_eq(_events.size(), 1, "lighting the stove said nothing")
	stove.advance(60.0)
	assert_eq(_events.size(), 2, "the fire dying said nothing")
	stove.advance(60.0)
	assert_eq(_events.size(), 2, "a fire that is already out went out again")

func test_smothering_the_fire_puts_it_out_without_spending_the_fuel() -> void:
	var stove = _build_lit(600.0)
	stove.extinguish()
	assert_false(stove.is_lit())
	assert_almost_eq(stove.fuel_remaining(), 600.0, 0.001, "smothering the fire burnt the wood anyway")

# --- warmth out -------------------------------------------------------------

func test_warmth_is_full_at_the_hearth_and_gone_past_the_falloff() -> void:
	var stove = _build_lit()
	assert_almost_eq(stove.warmth_at(HEARTH), 1.0, 0.0001, "standing in the fire is not warm")
	var edge := Vector3(stove.warm_radius_m, 0.0, 0.0)
	assert_almost_eq(
		stove.warmth_at(edge),
		1.0,
		0.0001,
		"warm_radius_m is the edge of FULL warmth; the falloff starts there"
	)
	var beyond := Vector3(stove.warm_radius_m + stove.warm_falloff_m + 0.01, 0.0, 0.0)
	assert_eq(stove.warmth_at(beyond), 0.0, "the fire reaches past its own falloff")
	var halfway := Vector3(stove.warm_radius_m + stove.warm_falloff_m * 0.5, 0.0, 0.0)
	var middle: float = stove.warmth_at(halfway)
	assert_true(
		middle > 0.0 and middle < 1.0,
		"the falloff is a step rather than a gradient: %f halfway through it" % middle
	)

func test_a_cold_stove_gives_no_warmth() -> void:
	var stove = _build()
	stove.add_fuel_seconds(600.0)
	assert_eq(stove.warmth_at(HEARTH), 0.0, "an unlit stove is warming the room")

# --- what the warmth does to the body ---------------------------------------

## The proportion that matters. A fire that put warmth back slower than the
## winter takes it would still pass any test that only checked the sign.
func test_the_fire_puts_warmth_back_faster_than_the_winter_takes_it() -> void:
	var stove = _build_lit()
	assert_eq(
		_survival.recovery_rate_of(&"core_temperature"),
		0.0,
		"something is already putting warmth back before the fire was lit"
	)
	stove.apply_recovery(HEARTH)
	var recovery: float = _survival.recovery_rate_of(&"core_temperature")
	var drain: float = _survival.drain_rate_of(&"core_temperature")
	assert_true(drain > 0.0, "the shipped core_temperature does not drain at all")
	if drain <= 0.0:
		return
	assert_true(
		recovery / drain >= 3.0 and recovery / drain <= 6.0,
		"the fire returns warmth at %.2fx the rate the winter takes it; outside 3-6x "
			% (recovery / drain)
			+ "a night by the fire either fixes nothing or fixes everything instantly"
	)
	# The design statement rather than the rate: an empty man is warm again
	# inside one 900 s day of sitting there, and not inside one minute.
	var refill: float = 1.0 / (recovery - drain)
	assert_true(
		refill < DAY_SECONDS and refill > 120.0,
		"an empty man is warm again after %.0f s at the fire" % refill
	)

## The brief's own sentence, as a test. Out all of day 1's daylight, home at
## dusk, fed, and warm again before the night is over.
func test_a_night_by_the_fire_undoes_a_day_outdoors() -> void:
	var stove = _build_lit(DAY_ONE_NIGHT)
	_survival.advance(DAY_ONE_DAYLIGHT)
	var at_dusk: float = _survival.value_of(&"core_temperature")
	assert_true(
		at_dusk < 0.55 and at_dusk > 0.35,
		"a day outdoors left him at %f, which is not the half a bar the survival "
			% at_dusk
			+ "tuning says a day-1 excursion costs"
	)

	# He eats when he gets in. A starving body makes less heat -- GDD 5's
	# 饥饿低 -> 体温下降加速 -- so a fire warms a fed man faster, and leaving this
	# line out is what makes the difference visible.
	_economy.add(&"hot_stew", 1)
	assert_true(_economy.consume(&"hot_stew"), "there was no meal to eat")

	_spend(DAY_ONE_NIGHT, HEARTH)
	var at_dawn: float = _survival.value_of(&"core_temperature")
	assert_true(
		at_dawn >= 0.95,
		"a whole night by a fed fire took him from %f only as far as %f" % [at_dusk, at_dawn]
	)
	assert_false(_survival.is_dead())

## fatigue:recovery had no producer at all until the stove. The thirst interlock
## of GDD section 5 -- 口渴低 -> 疲劳恢复变慢 -- has been modelled and tested since
## the survival system shipped, and inert the whole time, because nothing ever
## put fatigue back for it to slow down.
func test_the_fire_is_the_first_thing_that_ever_recovered_fatigue() -> void:
	var stove = _build_lit()
	assert_eq(
		_survival.recovery_rate_of(&"fatigue"),
		0.0,
		"something already recovers fatigue"
	)
	stove.apply_recovery(HEARTH)
	var recovery: float = _survival.recovery_rate_of(&"fatigue")
	var drain: float = _survival.drain_rate_of(&"fatigue")
	assert_true(recovery > drain, "sitting by the fire is %f against a drain of %f" % [recovery, drain])
	assert_true(
		_survival.net_rate_of(&"fatigue") > 0.0,
		"a man sitting by the fire is still getting more tired"
	)
	# Slower than warmth on purpose: rest is the long one, and a night by the
	# fire must not be a whole night's sleep.
	var refill: float = 1.0 / (recovery - drain)
	assert_true(
		refill > DAY_ONE_NIGHT,
		"%.0f s at the fire refills the whole fatigue bar, which is less than one "
			% refill
			+ "of GDD section 4's nights: resting stops costing anything"
	)

func test_dehydration_slows_the_rest_the_fire_gives() -> void:
	var stove = _build_lit()
	stove.apply_recovery(HEARTH)
	var watered: float = _survival.recovery_rate_of(&"fatigue")
	assert_true(watered > 0.0, "the fire gives no rest at all")

	_drop_to(&"thirst", 0.25)
	stove.apply_recovery(HEARTH)
	var parched: float = _survival.recovery_rate_of(&"fatigue")
	assert_almost_eq(
		parched,
		watered * 0.5,
		0.000001,
		"GDD 5's 口渴低 -> 疲劳恢复变慢 does not bite: %f against %f" % [parched, watered]
	)

func test_walking_away_takes_the_recovery_with_you() -> void:
	var stove = _build_lit()
	stove.apply_recovery(HEARTH)
	assert_true(_survival.recovery_rate_of(&"core_temperature") > 0.0)
	stove.apply_recovery(OUTSIDE)
	assert_eq(
		_survival.recovery_rate_of(&"core_temperature"),
		0.0,
		"the fire is still warming a man who walked away from it"
	)
	assert_eq(
		_survival.recovery_rate_of(&"fatigue"),
		0.0,
		"the fire is still resting a man who walked away from it"
	)

func test_the_fire_going_out_stops_the_recovery() -> void:
	var stove = _build_lit(30.0)
	stove.apply_recovery(HEARTH)
	assert_true(_survival.recovery_rate_of(&"core_temperature") > 0.0)
	stove.advance(60.0)
	stove.apply_recovery(HEARTH)
	assert_eq(
		_survival.recovery_rate_of(&"core_temperature"),
		0.0,
		"a fire that has gone out is still warming him"
	)

## Each stove carries its own source id. Sharing one would make the second fire
## take the first fire's warmth off the body every time it updated, and two
## fires would be worth less than one.
func test_two_fires_do_not_take_each_others_warmth_off() -> void:
	var stove = _build_lit()
	_second_stove = StoveScript.new()
	_second_stove.set_survival_system(_survival)
	_second_stove.set_fuel_economy(_economy)
	_second_stove.add_fuel_seconds(600.0)
	_second_stove.light()

	stove.apply_recovery(HEARTH)
	var one: float = _survival.recovery_rate_of(&"core_temperature")
	_second_stove.apply_recovery(HEARTH)
	var two: float = _survival.recovery_rate_of(&"core_temperature")
	assert_almost_eq(two, one * 2.0, 0.000001, "the second fire replaced the first instead of adding")

	_second_stove.clear_recovery()
	assert_almost_eq(
		_survival.recovery_rate_of(&"core_temperature"),
		one,
		0.000001,
		"putting one fire out took the other one's warmth away as well"
	)

# --- water and food out ------------------------------------------------------

## 雪必须融化才能饮用, 融雪要烧火. The whole reason fuel is the only currency.
func test_melting_snow_needs_a_lit_stove_and_costs_fuel() -> void:
	var stove = _build()
	_economy.add(&"snow", 1)
	var cost: float = _economy.definition_of(&"snow").heat_seconds
	assert_eq(stove.heat(&"snow"), &"", "snow melted on a cold stove")
	assert_eq(_economy.count_of(&"snow"), 1, "the snow was consumed by a fire that was not lit")

	stove.add_fuel_seconds(600.0)
	stove.light()
	assert_eq(stove.heat(&"snow"), &"meltwater", "a lit stove would not melt the snow")
	assert_eq(_economy.count_of(&"snow"), 0, "the snow is still there after being melted")
	assert_eq(_economy.count_of(&"meltwater"), 1, "no water came out")
	assert_almost_eq(
		stove.fuel_remaining(),
		600.0 - cost,
		0.001,
		"melting snow cost the fire nothing"
	)

func test_what_comes_off_the_stove_can_actually_be_drunk() -> void:
	var stove = _build_lit()
	_economy.add(&"snow", 1)
	assert_false(_economy.consume(&"snow"), "snow was drunk straight, so melting it is pointless")
	stove.heat(&"snow")
	# He has to be thirsty first: restore() clamps at the top of the bar, so a
	# full man drinking would show nothing and this test would prove nothing.
	_drop_to(&"thirst", 0.2)
	var before: float = _survival.value_of(&"thirst")
	assert_true(_economy.consume(&"meltwater"), "the meltwater could not be drunk")
	assert_true(
		_survival.value_of(&"thirst") > before,
		"drinking the meltwater quenched nothing"
	)

func test_cooking_costs_more_fire_than_melting() -> void:
	var stove = _build_lit()
	var melt: float = _economy.definition_of(&"snow").heat_seconds
	var cook: float = _economy.definition_of(&"canned_stew").heat_seconds
	assert_true(
		cook > melt,
		"a meal costs %.0f s of fire and a drink %.0f: cooking has to be the bigger "
			% [cook, melt]
			+ "commitment or the choice between them is not a choice"
	)
	_economy.add(&"canned_stew", 1)
	assert_eq(stove.heat(&"canned_stew"), &"hot_stew")

## Refusing rather than half-doing it. A stove that took the snow, spent what
## fuel it had and produced nothing would destroy both, silently.
func test_a_stove_without_the_fuel_for_the_job_refuses_rather_than_half_doing_it() -> void:
	var stove = _build_lit(10.0)
	_economy.add(&"snow", 1)
	assert_eq(stove.heat(&"snow"), &"", "the snow was melted on ten seconds of fire")
	assert_eq(_economy.count_of(&"snow"), 1, "the snow was consumed anyway")
	assert_eq(_economy.count_of(&"meltwater"), 0, "water appeared out of nothing")
	assert_almost_eq(stove.fuel_remaining(), 10.0, 0.001, "the fuel was spent on the job it refused")

func test_something_with_no_recipe_is_left_alone() -> void:
	var stove = _build_lit()
	_economy.add(&"firewood", 1)
	assert_eq(stove.heat(&"firewood"), &"", "firewood cooked into something")
	assert_eq(_economy.count_of(&"firewood"), 1, "the log was destroyed by being put on the stove")
	assert_eq(stove.heat(&"nonsense"), &"", "an item nobody declared was cooked")

## One log, and a whole day's water and food out of it, with fuel left over.
## This is GDD section 5's funnel end to end and the arithmetic the economy is
## tuned around: 2 melts + 2 cooks is most of a log but not all of it.
func test_the_whole_funnel_runs_from_one_log() -> void:
	var stove = _build()
	_economy.add(&"firewood", 1)
	_economy.add(&"snow", 2)
	_economy.add(&"canned_stew", 2)
	assert_true(stove.stoke(&"firewood"))
	assert_true(stove.light())

	for i in 2:
		assert_eq(stove.heat(&"snow"), &"meltwater", "melt %d failed" % i)
		assert_eq(stove.heat(&"canned_stew"), &"hot_stew", "cook %d failed" % i)
	assert_true(
		stove.fuel_remaining() > 0.0,
		"a day's water and food used the whole log; there is nothing left to burn for warmth"
	)

	_drop_to(&"thirst", 0.2)
	_drop_to(&"hunger", 0.2)
	for i in 2:
		assert_true(_economy.consume(&"meltwater"), "drink %d failed" % i)
		assert_true(_economy.consume(&"hot_stew"), "meal %d failed" % i)
	assert_true(
		_survival.value_of(&"thirst") >= 0.99,
		"two drinks left thirst at %f" % _survival.value_of(&"thirst")
	)
	assert_true(
		_survival.value_of(&"hunger") >= 0.99,
		"two hot meals left hunger at %f" % _survival.value_of(&"hunger")
	)

# --- running out -------------------------------------------------------------

## The brief's other sentence: running out of fuel has to be frightening rather
## than instantly fatal. A fire that dies at dusk costs the player the night, not
## the run.
func test_running_out_of_fuel_is_frightening_rather_than_fatal() -> void:
	var stove = _build_lit(60.0)
	_spend(DAY_ONE_NIGHT, HEARTH)
	assert_false(_survival.is_dead(), "the fire going out killed him inside one night")
	var left: float = _survival.value_of(&"core_temperature")
	assert_true(left < 0.95, "a night with no fire cost him nothing at all: %f" % left)
	assert_true(
		left > 0.6,
		"a night with no fire left him at %f, which is close enough to dead that the "
			% left
			+ "fire going out is not a setback, it is the end"
	)

# --- ready to place ----------------------------------------------------------

## The scene the owner drags into a level. It is not in scenes/main.tscn -- that
## file belongs to another agent this wave -- so this is the only thing standing
## between the stove and being placed.
func test_the_scene_is_ready_to_place() -> void:
	var packed = load(STOVE_SCENE)
	assert_not_null(packed, "there is no stove scene at %s" % STOVE_SCENE)
	if packed == null:
		return
	var instance = packed.instantiate()
	assert_true(instance is Node3D, "the stove is not a thing with a position in the world")
	assert_true(
		instance.has_method("warmth_at"),
		"the scene's root does not carry the stove script"
	)
	instance.free()

## Briefing trap 3, for the stove's own three lookups: a project [autoload] is a
## node under /root and never an engine singleton. Written the plausible-looking
## way, a placed stove would find no economy, no body and no bus -- and would
## then behave exactly like a stove with nothing in it, which is what a stove
## found in the world is supposed to look like.
##
## FuelEconomy is not registered as an autoload yet, so the two that are stand in
## for the pattern: the fire is announced on the live bus, which can only happen
## if _ready() resolved it.
func test_a_placed_stove_resolves_the_autoloads_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		# Return rather than fall through: dereferencing a null tree aborts the
		# method, and with one assertion already counted the runner's
		# zero-assertion guard would let it print PASS.
		return
	var bus = tree.root.get_node_or_null("EventBus")
	assert_not_null(bus, "the EventBus autoload must be present at /root/EventBus")
	if bus == null:
		return
	# NOT assigned to _bus: after_each() frees _bus, and this one is the live
	# autoload, not ours to free.
	bus.subscribe(&"stove.lit", _record)

	var stove = StoveScript.new()
	# Authored to arrive burning, which is what a farmhouse stove on the morning
	# of day 1 is. No set_event_bus(): entering the tree fires _ready(), which is
	# the code path under test.
	stove.starting_fuel_seconds = 600.0
	stove.start_lit = true
	tree.root.add_child(stove)
	var lit: bool = stove.is_lit()

	# Unwind before asserting, not after. The bus is global state shared with
	# every later test, and a Node left under /root leaks at exit (briefing
	# constraint 2).
	bus.unsubscribe(&"stove.lit", _record)
	tree.root.remove_child(stove)
	stove.free()

	assert_true(lit, "an authored lit stove arrived cold")
	assert_eq(
		_events.size(),
		1,
		"_ready() did not find /root/EventBus, so nothing in the game can hear a fire"
	)

## The only warning the player gets. GDD section 9 has no HUD, so a fire with a
## minute left has to LOOK like a fire with a minute left.
func test_a_dying_fire_dims() -> void:
	var stove = _build_lit(600.0)
	# _ready() has not run: nothing has been added to the tree (briefing trap 1).
	stove._ready()
	stove.advance(1.0)
	var bright: float = stove.light_energy_now()
	stove.advance(600.0 - stove.light_fade_seconds * 0.5 - 1.0)
	var dying: float = stove.light_energy_now()
	assert_true(bright > 0.0, "a lit stove gives no light at all")
	assert_true(
		dying < bright,
		"a fire with %.0f s left is as bright as one with ten minutes: %f against %f"
			% [stove.fuel_remaining(), dying, bright]
	)
	stove.advance(600.0)
	assert_eq(stove.light_energy_now(), 0.0, "a dead fire is still giving light")
