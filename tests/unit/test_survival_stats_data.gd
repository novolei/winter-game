extends TestCase

## The gate on res://data/stats -- the five interlocking stats of GDD section 5
## and the numbers they are tuned to.
##
## tests/unit/test_survival_system.gd tests the machine on definitions it builds
## itself. This file tests the CONTENT: that every stat the GDD names ships,
## that every interlock the GDD describes exists and bites in the right
## direction, and that the tuning still means what the report says it means.
##
## The scenario tests at the bottom are the ones worth keeping honest. A rate is
## a number nobody can eyeball; "total neglect kills you before the first day is
## out" is a design statement, and it is the only kind of assertion that catches
## a decimal point in the wrong place.
##
## Everything here derives from GDD section 4's clock: every day is
## 600+300 = 480+420 = 420+480 = 300+600 = 240+660 = 900 SECONDS, and the run is
## seven of them.

const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

const STATS_DIR := "res://data/stats"
const DAY_SECONDS := 900.0

## id -> [seconds to empty from full with no interlock active, lethal at zero].
## INF means the stat has no clock of its own: frostbite is a function of
## exposure, not of time, so it only moves when core temperature says so.
const TUNING := {
	&"core_temperature": [1200.0, true],
	&"hunger": [720.0, false],
	&"thirst": [600.0, false],
	&"fatigue": [1800.0, false],
	&"frostbite_hands": [INF, false],
	&"frostbite_feet": [INF, false],
}

## Targets that are not stats. A threshold effect may point at one of these to
## modulate a behaviour -- the localised half of GDD section 5 -- and whoever
## owns that behaviour reads it back with channel_value(). Adding to this list
## is a decision, which is why the list is here and not inferred.
## ---------------------------------------------------------------------------
## THE SUB-CHANNEL IS DECLARED TOO, AND IT WAS NOT BEFORE
## ---------------------------------------------------------------------------
## This list held only the HEAD -- "locomotion" -- so `locomotion:run_speed` and
## `locomotion:rn_speed` were equally acceptable and the second is a silent
## no-op, which is exactly the W1-D3 defect this test exists to end. It went
## unnoticed while `locomotion` had two sub-channels and both were spelt right;
## it has five now, and a typo in one of them would be invisible again.
const BEHAVIOUR_CHANNELS := {
	"locomotion": [
		"run_speed",       # 0 means running is off entirely
		"run_snow_limit",  # how deep the snow may be before the run goes
		"rhythm",          # how much of the terrain's penalty keeping going wins back
		"footing",         # how much of an ordinary walk his feet still carry
	],
	"ignition": ["speed"],      # how long lighting a fire takes
	"aim": ["steadiness"],      # weapon steadiness
	"vision": ["focus"],        # GDD section 5's 画面轻微失焦
	"breath": ["rate"],         # GDD section 9's 呼吸变浅变快
	"stand": ["composure"],     # how much of his bearing his hands let him keep
}

var _system = null
var _bus = null
var _deaths: Array = []

func before_each() -> void:
	_deaths = []

func after_each() -> void:
	if _system != null:
		_system.free()
		_system = null
	if _bus != null:
		_bus.free()
		_bus = null

# --- helpers ---------------------------------------------------------------

func _record_died(payload) -> void:
	_deaths.append(payload)

func _load_definitions() -> Array:
	var definitions := []
	var dir := DirAccess.open(STATS_DIR)
	if dir == null:
		return definitions
	var names := dir.get_files()
	names.sort()
	for name in names:
		if not name.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(STATS_DIR.path_join(name))
		if resource is StatDefinition:
			definitions.append(resource)
	return definitions

func _build():
	_bus = EventBusScript.new()
	_bus.subscribe(&"survival.died", _record_died)
	_system = SurvivalSystemScript.new()
	_system.set_event_bus(_bus)
	_system.load_from_directory(STATS_DIR)
	_system.start()
	return _system

## Drops a stat to `value` as fast as the model allows, by leaning on its drain
## rather than by writing to it -- there is no setter, deliberately. The
## multiplier is large so that the descent itself costs almost nothing: at 200x
## the body crosses the whole frostbite band in under a second.
func _chill_to(system, stat_id: StringName, value: float) -> void:
	system.push_modifier(stat_id, &"test_chill", Modifier.Operation.MULTIPLY, 200.0)
	var guard := 0
	while system.value_of(stat_id) > value and not system.is_dead() and guard < 10000:
		system.advance(0.25)
		guard += 1
	system.remove_source(&"test_chill")

## Advances `seconds`, holding one stat AT `value` by topping it back up after
## every slice. The harness for "what happens to everything else while the body
## sits at this temperature", which is otherwise unreachable: a body that cold
## is dead in a couple of minutes. Call _chill_to() first -- restore() only ever
## adds, so this holds a floor and cannot bring a value down to meet it.
func _hold(system, stat_id: StringName, value: float, seconds: float, slice := 1.0) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not system.is_dead():
		system.advance(slice)
		elapsed += slice
		var current: float = system.value_of(stat_id)
		if current < value:
			system.restore(stat_id, value - current)

## Advances until the run ends, and returns when. -1.0 if it never does.
func _time_of_death(system, limit: float, slice := 1.0) -> float:
	var elapsed := 0.0
	while elapsed < limit:
		system.advance(slice)
		elapsed += slice
		if system.is_dead():
			return elapsed
	return -1.0

func _effects_of(definition) -> Array:
	var effects := []
	for effect in definition.threshold_effects:
		if effect != null:
			effects.append(effect)
	return effects

## True when the shipped data holds an effect matching every field given.
func _has_effect(watch: StringName, threshold: float, target: StringName, operation: int, value: float) -> bool:
	for definition in _load_definitions():
		for effect in _effects_of(definition):
			if effect.watch_stat != watch or effect.target_stat != target:
				continue
			if effect.operation != operation:
				continue
			if absf(effect.threshold - threshold) > 0.0001:
				continue
			if absf(effect.value - value) > 0.0001:
				continue
			return true
	return false

# --- the shape of the shipped model ----------------------------------------

func test_every_stat_the_gdd_names_ships() -> void:
	var definitions := _load_definitions()
	var ids := []
	for definition in definitions:
		ids.append(definition.id)
	assert_eq(definitions.size(), TUNING.size(), "res://data/stats holds exactly the model, no strays")
	for id in TUNING.keys():
		assert_true(ids.has(id), "%s must ship as a .tres" % id)

func test_every_stat_is_a_reserve() -> void:
	# The polarity the whole model and every readout depends on: full is
	# healthy, empty is the worst it gets, for all of them, including the two
	# whose names read the other way round.
	for definition in _load_definitions():
		assert_almost_eq(definition.min_value, 0.0, 0.0001, "%s should bottom out at 0" % definition.id)
		assert_almost_eq(definition.max_value, 1.0, 0.0001, "%s should top out at 1" % definition.id)
		assert_almost_eq(
			definition.initial_value, definition.max_value, 0.0001,
			"%s must start full -- a reserve, not an accumulator" % definition.id
		)

func test_only_core_temperature_ends_the_run() -> void:
	# GDD section 5: core temperature is the master clock and the only stat
	# whose zero is death. Frostbite in particular never kills.
	for definition in _load_definitions():
		var expected: bool = TUNING[definition.id][1]
		assert_eq(definition.lethal_at_min, expected, "%s lethal_at_min" % definition.id)

func test_base_lifetimes_match_the_tuning_table() -> void:
	for definition in _load_definitions():
		var expected: float = TUNING[definition.id][0]
		if is_inf(expected):
			assert_almost_eq(
				definition.base_decay_per_second, 0.0, 0.000001,
				"%s has no clock of its own -- it moves only when an interlock says so" % definition.id
			)
			continue
		assert_true(definition.base_decay_per_second > 0.0, "%s must actually drain" % definition.id)
		if definition.base_decay_per_second <= 0.0:
			continue
		assert_almost_eq(
			1.0 / definition.base_decay_per_second, expected, 1.0,
			"%s should empty in %d s" % [definition.id, int(expected)]
		)

func test_every_interlock_names_something_that_exists() -> void:
	# W1-D3: watch_stat and target_stat are bare StringNames that nothing
	# resolves, so a typo is a silent no-op at runtime. This is where it stops
	# being silent.
	var ids := []
	for definition in _load_definitions():
		ids.append(String(definition.id))
	for definition in _load_definitions():
		for effect in _effects_of(definition):
			assert_true(
				ids.has(String(effect.watch_stat)),
				"%s watches '%s', which is not a stat" % [definition.id, effect.watch_stat]
			)
			var target := String(effect.target_stat)
			var head := target
			var channel := "drain"
			var split := target.split(":", false)
			if split.size() == 2:
				head = split[0]
				channel = split[1]
			if ids.has(head):
				assert_true(
					channel == "drain" or channel == "recovery",
					"%s targets '%s': a stat has only drain and recovery" % [definition.id, target]
				)
			else:
				assert_true(
					BEHAVIOUR_CHANNELS.has(head),
					"%s targets '%s', which is neither a stat nor a declared behaviour channel" % [definition.id, target]
				)
				if BEHAVIOUR_CHANNELS.has(head):
					assert_true(
						(BEHAVIOUR_CHANNELS[head] as Array).has(channel),
						"%s targets '%s': '%s' is not a declared sub-channel of '%s', and an "
							% [definition.id, target, channel, head]
							+ "undeclared one is a silent no-op at runtime"
					)

func test_every_effect_lives_in_the_file_of_the_stat_it_watches() -> void:
	# Nothing in the machine requires this -- an effect carries its own
	# watch_stat. It is a filing convention, and it is the difference between
	# "what does hunger do to me" being one file and being a search.
	for definition in _load_definitions():
		for effect in _effects_of(definition):
			assert_eq(
				effect.watch_stat, definition.id,
				"%s.tres holds an effect watching %s" % [definition.id, effect.watch_stat]
			)

func test_every_threshold_is_reachable() -> void:
	# A BELOW threshold at or under a stat's minimum can never fire, because the
	# value clamps at the minimum and the comparison is strict. Dead data that
	# looks alive.
	var by_id := {}
	for definition in _load_definitions():
		by_id[definition.id] = definition
	for definition in _load_definitions():
		for effect in _effects_of(definition):
			var watched = by_id.get(effect.watch_stat, null)
			if watched == null:
				continue
			assert_true(
				effect.threshold > watched.min_value and effect.threshold <= watched.max_value,
				"%s: threshold %f sits outside what %s can ever be" % [definition.id, effect.threshold, effect.watch_stat]
			)

# --- the interlocks GDD section 5 requires ----------------------------------

func test_hunger_accelerates_the_loss_of_heat() -> void:
	var system = _build()
	var base: float = system.drain_rate_of(&"core_temperature")
	assert_almost_eq(base, 1.0 / 1200.0, 0.00001, "a fed body loses its heat at the base rate")
	system.advance(520.0)  # hunger 720 s * 0.7 = 504 s to fall under 0.30
	assert_true(system.value_of(&"hunger") < 0.3, "precondition: hungry")
	assert_almost_eq(
		system.drain_rate_of(&"core_temperature"), base * 1.5, 0.00001,
		"GDD 5: 饥饿低 -> 身体产热下降 -> 体温下降加速"
	)
	system.advance(180.0)  # and under 0.05
	assert_true(system.value_of(&"hunger") < 0.05, "precondition: starving")
	assert_almost_eq(
		system.drain_rate_of(&"core_temperature"), base * 3.0, 0.00001,
		"GDD 5: 归零后果 -- 体温加速流失. The two tiers compound, 1.5 * 2.0"
	)

func test_thirst_slows_and_then_stops_fatigue_recovery() -> void:
	var system = _build()
	# A stand-in for the fire/sleep that will push recovery once those systems
	# exist. Without one there is nothing for thirst to slow down, which is the
	# whole reason recovery is a channel of its own.
	system.push_modifier(&"fatigue:recovery", &"stove", Modifier.Operation.ADD, 0.002)
	assert_almost_eq(system.recovery_rate_of(&"fatigue"), 0.002, 0.00001, "watered, rest works at full rate")
	system.advance(430.0)  # thirst 600 s * 0.7 = 420 s to fall under 0.30
	assert_true(system.value_of(&"thirst") < 0.3, "precondition: thirsty")
	assert_almost_eq(
		system.recovery_rate_of(&"fatigue"), 0.001, 0.00001,
		"GDD 5: 口渴低 -> 疲劳恢复变慢"
	)
	assert_almost_eq(
		system.drain_rate_of(&"fatigue"), 1.0 / 1800.0, 0.00001,
		"and the drain is untouched: thirst slows recovery, it does not tire you"
	)
	system.advance(150.0)  # and under 0.05
	assert_almost_eq(
		system.recovery_rate_of(&"fatigue"), 0.0, 0.00001,
		"GDD 5: 归零后果 -- 疲劳无法恢复"
	)

## GDD 5's whole fatigue row, and every step of it is now a CAPABILITY.
##
## `locomotion:speed` and `locomotion:snow_cost` used to carry 移速下降 and
## 雪深惩罚加剧 as plain multipliers. The owner's ruling is that only snow depth
## and terrain slope may scale movement speed, so the body gates instead: a tired
## man loses the run in half the snow a fresh man manages, and an empty bar takes
## it away outright. Nothing here scales a speed any more.
func test_fatigue_costs_the_run_in_deep_snow_and_finally_the_run_itself() -> void:
	var system = _build()
	assert_almost_eq(
		system.channel_value(&"locomotion:run_snow_limit", 1.0), 1.0, 0.0001,
		"rested, he runs through as much snow as the body allows"
	)
	assert_almost_eq(system.channel_value(&"locomotion:run_speed", 1.0), 1.0, 0.0001, "and can run")
	# Fatigue is the slowest clock in the model, so everything else has to be
	# held up while it runs down.
	system.push_modifier(&"core_temperature:recovery", &"harness", Modifier.Operation.ADD, 1.0)
	system.push_modifier(&"hunger:recovery", &"harness", Modifier.Operation.ADD, 1.0)
	system.push_modifier(&"thirst:recovery", &"harness", Modifier.Operation.ADD, 1.0)
	system.advance(1300.0)  # fatigue 1800 s * 0.7 = 1260 s to fall under 0.30
	assert_true(system.value_of(&"fatigue") < 0.3, "precondition: tired")
	# One row answers both halves of GDD 5's 移速下降、雪深惩罚加剧: the snow he
	# can still run through halves, which is both a worsened snow penalty and a
	# slower man, stated as something he can notice happening.
	assert_almost_eq(
		system.channel_value(&"locomotion:run_snow_limit", 1.0), 0.5, 0.0001,
		"GDD 5: 疲劳高 -> 移速下降、雪深惩罚加剧, as a gate"
	)
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 1.0, 0.0001,
		"...but a quarter-full bar is not 归零: he can still run on clear ground"
	)
	system.advance(600.0)  # and to the floor
	assert_almost_eq(system.value_of(&"fatigue"), 0.0, 0.0001, "precondition: spent")
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 0.0, 0.0001,
		"GDD 5: 归零后果 -- 无法奔跑"
	)

func test_frostbite_only_accumulates_when_the_body_is_cold() -> void:
	var system = _build()
	_chill_to(system, &"core_temperature", 0.6)
	_hold(system, &"core_temperature", 0.6, 120.0)
	assert_almost_eq(
		system.value_of(&"frostbite_hands"), 1.0, 0.0001,
		"a body holding its heat does not get frostbite, however long it is out"
	)
	_chill_to(system, &"core_temperature", 0.25)
	var hands_before: float = system.value_of(&"frostbite_hands")
	var feet_before: float = system.value_of(&"frostbite_feet")
	_hold(system, &"core_temperature", 0.25, 60.0)
	assert_almost_eq(
		hands_before - system.value_of(&"frostbite_hands"), 60.0 / 600.0, 0.005,
		"GDD 5: 冻伤是暴露时间的函数 -- 600 s of unbroken cold costs the hands"
	)
	assert_almost_eq(
		feet_before - system.value_of(&"frostbite_feet"), 60.0 / 900.0, 0.005,
		"boots buy the feet half again as long as bare hands"
	)

func test_deep_cold_takes_the_limbs_twice_as_fast() -> void:
	var system = _build()
	_chill_to(system, &"core_temperature", 0.10)
	var hands_before: float = system.value_of(&"frostbite_hands")
	_hold(system, &"core_temperature", 0.10, 60.0)
	assert_almost_eq(
		hands_before - system.value_of(&"frostbite_hands"), 120.0 / 600.0, 0.005,
		"below 0.15 the rate doubles -- the cost of nearly dying"
	)

func test_frostbite_degrades_all_four_of_the_others() -> void:
	var system = _build()
	var temperature_base: float = system.drain_rate_of(&"core_temperature")
	var hunger_base: float = system.drain_rate_of(&"hunger")
	var fatigue_base: float = system.drain_rate_of(&"fatigue")
	var thirst_base: float = system.drain_rate_of(&"thirst")
	# Without this the whole test passes vacuously on an empty data directory:
	# every rate is 0.0, and 0.0 is 1.1 times 0.0.
	assert_true(temperature_base > 0.0, "precondition: the shipped model is loaded")
	# Straight to the damage, without the 400 s of cold it would take to earn.
	system.push_modifier(&"frostbite_hands", &"harness", Modifier.Operation.ADD, 0.1)
	system.push_modifier(&"frostbite_feet", &"harness", Modifier.Operation.ADD, 0.1)
	system.advance(6.0)
	assert_true(system.value_of(&"frostbite_hands") < 0.5, "precondition: hands are gone")
	assert_true(system.value_of(&"frostbite_feet") < 0.5, "precondition: feet are gone")
	assert_almost_eq(
		system.drain_rate_of(&"core_temperature"), temperature_base * 1.10, 0.00001,
		"GDD 5: 冻伤让其它四条全面恶化 -- heat, through bad circulation"
	)
	assert_almost_eq(
		system.drain_rate_of(&"hunger"), hunger_base * 1.15, 0.00001,
		"...hunger, because a shivering body burns more"
	)
	assert_almost_eq(
		system.drain_rate_of(&"fatigue"), fatigue_base * 1.25, 0.00001,
		"...fatigue, because every step on ruined feet costs more"
	)
	assert_almost_eq(
		system.drain_rate_of(&"thirst"), thirst_base * 1.10, 0.00001,
		"...and thirst, because that heavier work is paid for in breath"
	)

func test_frostbitten_hands_slow_the_fire_and_spoil_the_aim() -> void:
	var system = _build()
	system.push_modifier(&"frostbite_hands", &"harness", Modifier.Operation.ADD, 0.1)
	system.advance(6.0)
	assert_almost_eq(
		system.channel_value(&"ignition:speed", 1.0), 0.6, 0.0001,
		"GDD 5: 手部冻伤 -> 点火变慢"
	)
	assert_almost_eq(
		system.channel_value(&"aim:steadiness", 1.0), 0.7, 0.0001,
		"GDD 5: 射击精度下降"
	)
	system.advance(4.0)
	assert_true(system.value_of(&"frostbite_hands") < 0.2, "precondition: worse than gone")
	assert_almost_eq(
		system.channel_value(&"ignition:speed", 1.0), 0.3, 0.0001,
		"the second tier compounds: 0.6 * 0.5"
	)

## GDD 5: 足部冻伤 -> 移速永久下降，直到在火边治疗. Two stages, both capabilities:
## sore feet cannot carry a run through a drift, ruined feet cannot carry one at
## all. What is permanent is the lost RUN rather than a quietly smaller number.
func test_frostbitten_feet_cost_movement_until_they_are_treated() -> void:
	var system = _build()
	system.push_modifier(&"frostbite_feet", &"harness", Modifier.Operation.ADD, 0.1)
	system.advance(6.0)
	system.remove_source(&"harness")
	assert_true(system.value_of(&"frostbite_feet") < 0.5, "precondition: sore feet")
	assert_almost_eq(
		system.channel_value(&"locomotion:run_snow_limit", 1.0), 0.5, 0.0001,
		"GDD 5: 足部冻伤 -> 移速下降, as a gate"
	)
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 1.0, 0.0001,
		"sore feet are not ruined feet: he can still run on clear ground"
	)
	system.advance(120.0)
	assert_almost_eq(
		system.channel_value(&"locomotion:run_snow_limit", 1.0), 0.5, 0.0001,
		"...permanently: nothing gives a limb back on its own"
	)

	# ...and worse feet are genuinely worse.
	system.push_modifier(&"frostbite_feet", &"harness", Modifier.Operation.ADD, 0.1)
	system.advance(3.0)
	system.remove_source(&"harness")
	assert_true(system.value_of(&"frostbite_feet") < 0.2, "precondition: ruined feet")
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 0.0, 0.0001,
		"ruined feet still leave him a run"
	)

	system.restore(&"frostbite_feet", 1.0)
	system.advance(0.25)
	assert_almost_eq(
		system.channel_value(&"locomotion:run_snow_limit", 1.0), 1.0, 0.0001,
		"...until it is treated at a fire"
	)
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 1.0, 0.0001,
		"...and then he can run again"
	)

# --- what the numbers mean in play ------------------------------------------

func test_total_neglect_kills_before_the_first_day_is_out() -> void:
	# The headline scenario, and the one the tuning is answerable to: no fire,
	# no food, no water, standing outdoors from dawn on day 1.
	#
	# Analytically, from the shipped rates: hunger crosses 0.30 at 504 s and
	# 0.05 at 684 s, so core temperature runs at 1/1200 to 504 s (0.42 gone),
	# at 1.5x to 684 s (0.225 more), then at 3x from 0.355 -- reaching zero at
	# 826 s. Which is 0.92 of GDD section 4's 900 s day.
	var system = _build()
	var death := _time_of_death(system, 2.0 * DAY_SECONDS)
	assert_true(death > 0.0, "an unattended body must actually die")
	if death <= 0.0:
		return
	assert_eq(_deaths.size(), 1, "and say so exactly once")
	assert_almost_eq(death, 826.0, 10.0, "the tuning table's number, in seconds")
	assert_true(death > 300.0, "not in thirty seconds: the first day must be survivable while you learn")
	assert_true(death < DAY_SECONDS, "and not in a week: one day of neglect is fatal")

func test_a_full_day_outdoors_costs_half_the_warmth() -> void:
	# Day 1's daylight is 600 s (GDD section 4). Spending all of it outside,
	# with nothing to eat on the way, is what a first expedition looks like.
	var system = _build()
	system.advance(600.0)
	assert_false(system.is_dead(), "a day out is survivable")
	assert_almost_eq(
		system.value_of(&"core_temperature"), 0.46, 0.03,
		"and costs a little over half the warmth -- the fire has to do the rest"
	)
	assert_almost_eq(
		system.value_of(&"frostbite_hands"), 1.0, 0.0001,
		"a day inside the margin costs no limbs"
	)

func test_a_night_outdoors_is_lethal_at_the_gdd_doubling() -> void:
	# GDD section 3: 天黑后仍在野外，体温下降速率翻倍. The clock is not this
	# system's to know about, so the doubling arrives as a modifier -- and the
	# temperature bar is tuned so that a day out plus a night out is exactly
	# fatal. NIGHTFALL = GO HOME, in numbers.
	var system = _build()
	system.advance(600.0)
	assert_false(system.is_dead(), "still alive at dusk")
	system.push_modifier(&"core_temperature", &"night", Modifier.Operation.MULTIPLY, 2.0)
	var death := _time_of_death(system, 300.0)
	assert_true(death > 0.0, "a night in the open with no fire kills before dawn")
	assert_true(death < 300.0, "and day 1's night is only 300 s long")

func test_frostbite_never_kills() -> void:
	var system = _build()
	_chill_to(system, &"core_temperature", 0.25)
	_hold(system, &"core_temperature", 0.25, 650.0)
	assert_almost_eq(system.value_of(&"frostbite_hands"), 0.0, 0.0001, "the hands are lost")
	assert_true(system.is_depleted(&"frostbite_hands"), "and the model says so")
	assert_false(system.is_dead(), "GDD 5: 冻伤不会直接致死")
	assert_eq(_deaths.size(), 0, "no death event came from a limb")

func test_seven_days_of_care_is_survivable_but_sleepless_is_not_free() -> void:
	# The other end of the band: if food, water and a fire are kept up, the
	# seven-day run of GDD section 4 is survivable -- but nothing here restores
	# fatigue, so by the end he cannot run. Sleep is a mechanic the model needs,
	# not a nicety.
	var system = _build()
	system.push_modifier(&"core_temperature:recovery", &"hearth", Modifier.Operation.ADD, 0.01)
	system.push_modifier(&"hunger:recovery", &"larder", Modifier.Operation.ADD, 0.01)
	system.push_modifier(&"thirst:recovery", &"meltwater", Modifier.Operation.ADD, 0.01)
	system.advance(7.0 * DAY_SECONDS)
	assert_false(system.is_dead(), "seven days with the chores done is a run you can finish")
	assert_almost_eq(system.value_of(&"core_temperature"), 1.0, 0.0001, "a tended fire holds the temperature")
	assert_almost_eq(system.value_of(&"fatigue"), 0.0, 0.0001, "and seven days without sleep leaves nothing")
	assert_almost_eq(
		system.channel_value(&"locomotion:run_speed", 1.0), 0.0, 0.0001,
		"which by GDD 5 means he cannot run on the last night, when it matters most"
	)
