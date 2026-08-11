extends TestCase

## The gate on res://data/items -- GDD section 5's resource funnel as content.
##
##     水  <- 融雪 <- 火 <- 燃料
##     食物 <- 烹饪 <-  ^
##     体温 <---------- '
##     信标 <---------- '
##
## Everything in that diagram is one number in one .tres file, and the whole
## point of the design is the arithmetic BETWEEN them: snow is worthless until
## it has cost fire, a hot meal is worth several cold ones, and every second of
## fire came off a pile of wood somebody carried home. None of that is visible
## on screen and none of it can be eyeballed, so it is asserted here.
##
## tests/unit/test_fuel_economy.gd tests the machine on items it builds itself.
## This file tests the SHIPPED numbers, against the survival tuning they have to
## be in proportion to -- read out of res://data/stats rather than restated, so
## a tuning pass on one side cannot silently drift from the other.

const ITEMS_DIR := "res://data/items"
const STATS_DIR := "res://data/stats"

## GDD section 4: every one of the seven days is daylight plus night and every
## one adds up to the same 900 seconds. It is the only unit anybody can feel,
## so every claim below is stated in it.
const DAY_SECONDS := 900.0

## Targets a use_modifier is allowed to name that are not stats. Same list as
## tests/unit/test_survival_stats_data.gd, and for the same reason: adding to it
## is a decision, so it is written down rather than inferred.
const BEHAVIOUR_CHANNELS := [
	"locomotion",
	"ignition",
	"aim",
	"vision",
	"breath",
]

# --- helpers ---------------------------------------------------------------

func _load_items() -> Dictionary:
	var items := {}
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return items
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(ITEMS_DIR.path_join(file_name))
		if resource is ItemDefinition:
			items[resource.id] = resource
	return items

func _load_stats() -> Dictionary:
	var stats := {}
	var dir := DirAccess.open(STATS_DIR)
	if dir == null:
		return stats
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(STATS_DIR.path_join(file_name))
		if resource is StatDefinition:
			stats[resource.id] = resource
	return stats

## How many seconds of drain one full bar of a stat is worth. A restore of
## `amount` therefore buys `amount * _bar_seconds(stat)` seconds of life, which
## is the only currency the two halves of the design share.
func _bar_seconds(stat: StatDefinition) -> float:
	if stat == null or stat.base_decay_per_second <= 0.0:
		return 0.0
	return (stat.max_value - stat.min_value) / stat.base_decay_per_second

# --- what ships -------------------------------------------------------------

## The eight the funnel needs: three forms of fuel, snow and the water it
## becomes, and food raw, cooked and carried.
func test_every_item_the_funnel_needs_ships() -> void:
	var items := _load_items()
	for wanted in [
		&"firewood", &"petrol", &"coal",
		&"snow", &"meltwater",
		&"canned_stew", &"hot_stew", &"dried_meat",
	]:
		assert_true(items.has(wanted), "res://data/items is missing %s" % wanted)

func test_every_file_declares_the_id_it_is_named_after() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	assert_not_null(dir, "res://data/items does not exist")
	if dir == null:
		return
	var seen := {}
	var checked := 0
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(ITEMS_DIR.path_join(file_name))
		assert_true(resource is ItemDefinition, "%s is not an ItemDefinition" % file_name)
		if not (resource is ItemDefinition):
			continue
		var item: ItemDefinition = resource
		checked += 1
		assert_eq(
			String(item.id),
			file_name.trim_suffix(".tres"),
			"%s declares id %s; a file and its id must agree or nothing can find it"
				% [file_name, item.id]
		)
		assert_false(seen.has(item.id), "two files claim the id %s" % item.id)
		seen[item.id] = true
	assert_true(checked > 0, "no ItemDefinition was found in %s at all" % ITEMS_DIR)

## GDD section 5: 四类资源中前三类都是燃料的不同形态. Fuel is the only true
## currency, so nothing outside the fuel category may quietly also be fuel --
## a food with a burn time would be a second currency nobody was told about.
func test_only_fuel_burns_and_all_of_it_does() -> void:
	var items := _load_items()
	assert_true(items.size() > 0, "no items loaded")
	for id in items:
		var item: ItemDefinition = items[id]
		if item.category == ItemDefinition.Category.FUEL:
			assert_true(
				item.fuel_value > 0.0,
				"%s is filed as fuel and burns for %f seconds" % [id, item.fuel_value]
			)
		else:
			assert_eq(
				item.fuel_value,
				0.0,
				"%s is not fuel but burns for %f seconds" % [id, item.fuel_value]
			)

## Wood is the common one, petrol the found one, coal the hoarded one -- and the
## ladder has to run the same way in both directions or there is no decision in
## which to carry: the light unit is the least efficient, the heavy one the most.
func test_the_three_fuels_make_a_ladder() -> void:
	var items := _load_items()
	if not (items.has(&"firewood") and items.has(&"petrol") and items.has(&"coal")):
		assert_true(false, "the three fuels do not all ship")
		return
	var wood: ItemDefinition = items[&"firewood"]
	var petrol: ItemDefinition = items[&"petrol"]
	var coal: ItemDefinition = items[&"coal"]
	assert_true(
		wood.fuel_value < petrol.fuel_value and petrol.fuel_value < coal.fuel_value,
		"the burn times do not increase wood -> petrol -> coal: %f, %f, %f"
			% [wood.fuel_value, petrol.fuel_value, coal.fuel_value]
	)
	assert_true(
		wood.mass_kg < petrol.mass_kg and petrol.mass_kg < coal.mass_kg,
		"the masses do not increase wood -> petrol -> coal: %f, %f, %f"
			% [wood.mass_kg, petrol.mass_kg, coal.mass_kg]
	)
	var per_kg := func(item: ItemDefinition) -> float:
		return item.fuel_value / maxf(item.mass_kg, 0.0001)
	assert_true(
		per_kg.call(coal) > per_kg.call(petrol) and per_kg.call(petrol) > per_kg.call(wood),
		"coal must be the best fuel per kilogram carried and wood the worst, or the "
			+ "heavy one is never worth the walk: %f, %f, %f per kg"
			% [per_kg.call(coal), per_kg.call(petrol), per_kg.call(wood)]
	)

# --- the funnel -------------------------------------------------------------

## 雪必须融化才能饮用. Snow is everywhere and worth nothing; the fire is what
## turns it into water. If snow were drinkable the whole economy would collapse
## into "walk outside and lick the ground".
func test_snow_is_worth_nothing_until_it_has_cost_fire() -> void:
	var items := _load_items()
	if not (items.has(&"snow") and items.has(&"meltwater")):
		assert_true(false, "snow and meltwater do not both ship")
		return
	var snow: ItemDefinition = items[&"snow"]
	var water: ItemDefinition = items[&"meltwater"]
	assert_eq(snow.hydration, 0.0, "snow can be drunk straight; melting it is then pointless")
	assert_eq(snow.nutrition, 0.0, "snow is food")
	assert_eq(String(snow.heats_into), "meltwater", "snow does not melt into meltwater")
	assert_true(snow.heat_seconds > 0.0, "melting snow costs no fire at all")
	assert_true(water.hydration > 0.0, "meltwater does not quench anything")

## Every recipe resolves, and every one of them costs fire. A recipe that cost
## nothing would be a free upgrade and the funnel's arrow would point nowhere.
func test_every_recipe_names_something_real_and_costs_fire() -> void:
	var items := _load_items()
	var recipes := 0
	for id in items:
		var item: ItemDefinition = items[id]
		if item.heats_into == &"":
			assert_eq(
				item.heat_seconds,
				0.0,
				"%s costs %f seconds of fire but becomes nothing" % [id, item.heat_seconds]
			)
			continue
		recipes += 1
		assert_true(
			items.has(item.heats_into),
			"%s heats into %s, which is not an item" % [id, item.heats_into]
		)
		assert_true(
			item.heat_seconds > 0.0,
			"%s becomes %s for free" % [id, item.heats_into]
		)
		if items.has(item.heats_into):
			var output: ItemDefinition = items[item.heats_into]
			assert_eq(
				String(output.heats_into),
				"",
				"%s heats into %s, which heats into something else again; one pass at "
					% [id, item.heats_into]
					+ "the stove is the whole mechanic"
			)
	assert_true(recipes >= 2, "only %d recipe(s) ship; the funnel needs melting AND cooking" % recipes)

## 烹饪 has to be worth the fuel it costs, or the rational play is to eat
## everything cold and burn the wood on warmth instead.
func test_cooking_is_worth_the_fire_it_costs() -> void:
	var items := _load_items()
	if not (items.has(&"canned_stew") and items.has(&"hot_stew")):
		assert_true(false, "the raw and cooked meal do not both ship")
		return
	var raw: ItemDefinition = items[&"canned_stew"]
	var hot: ItemDefinition = items[&"hot_stew"]
	assert_true(raw.nutrition > 0.0, "a cold can feeds nobody at all; the choice disappears")
	assert_true(
		hot.nutrition >= raw.nutrition * 3.0,
		"cooking turns %f of nutrition into %f, which is not worth %f seconds of fire"
			% [raw.nutrition, hot.nutrition, raw.heat_seconds]
	)
	assert_eq(String(raw.heats_into), "hot_stew", "a can does not cook into the hot meal")

## The two chores that pull the fire into every single day. Both are asserted
## against the shipped stat bars rather than against a remembered number.
func test_two_drinks_and_two_meals_cover_a_day() -> void:
	var items := _load_items()
	var stats := _load_stats()
	var thirst_bar := _bar_seconds(stats.get(&"thirst", null))
	var hunger_bar := _bar_seconds(stats.get(&"hunger", null))
	assert_true(thirst_bar > 0.0 and hunger_bar > 0.0, "the thirst and hunger stats did not load")
	if thirst_bar <= 0.0 or hunger_bar <= 0.0:
		return
	var water: ItemDefinition = items.get(&"meltwater", null)
	var meal: ItemDefinition = items.get(&"hot_stew", null)
	assert_not_null(water, "meltwater does not ship")
	assert_not_null(meal, "hot_stew does not ship")
	if water == null or meal == null:
		return

	# A 900 s day costs more than one bar of either -- that is the whole point of
	# tuning both under a day (survival report 1.2) -- so two of each has to
	# cover a day and one must not.
	assert_true(
		2.0 * water.hydration * thirst_bar >= DAY_SECONDS,
		"two drinks buy %.0f s against a %.0f s day: the morning-and-evening chore "
			% [2.0 * water.hydration * thirst_bar, DAY_SECONDS]
			+ "does not actually keep up"
	)
	assert_true(
		water.hydration * thirst_bar < DAY_SECONDS,
		"one drink buys %.0f s and covers the whole day on its own; thirst stops "
			% (water.hydration * thirst_bar)
			+ "being a daily chore"
	)
	assert_true(
		2.0 * meal.nutrition * hunger_bar >= DAY_SECONDS,
		"two hot meals buy %.0f s against a %.0f s day"
			% [2.0 * meal.nutrition * hunger_bar, DAY_SECONDS]
	)
	assert_true(
		meal.nutrition * hunger_bar < DAY_SECONDS,
		"one hot meal buys %.0f s and feeds a man for a whole day"
			% (meal.nutrition * hunger_bar)
	)

## The sentence the whole economy exists to make true: one bundle of wood is
## about a day's water and food, and there is nothing left over for the night.
func test_a_days_water_and_food_costs_most_of_a_log() -> void:
	var items := _load_items()
	var wood: ItemDefinition = items.get(&"firewood", null)
	var snow: ItemDefinition = items.get(&"snow", null)
	var can: ItemDefinition = items.get(&"canned_stew", null)
	assert_not_null(wood, "firewood does not ship")
	if wood == null or snow == null or can == null:
		assert_true(false, "the day's chores cannot be priced; an item is missing")
		return
	var chores := 2.0 * snow.heat_seconds + 2.0 * can.heat_seconds
	assert_true(
		chores < wood.fuel_value,
		"a day of melting and cooking costs %.0f s and a log is %.0f: the day cannot "
			% [chores, wood.fuel_value]
			+ "be paid for at all"
	)
	assert_true(
		chores > wood.fuel_value * 0.5,
		"a day of melting and cooking costs %.0f s of a %.0f s log, so one log is "
			% [chores, wood.fuel_value]
			+ "two days of chores and firewood stops being scarce"
	)

# --- what an item does to the body ------------------------------------------

## use_modifiers is the general path -- an item may do anything a weather event
## can -- so a typo in one is a rule that silently never fires. The shipped set
## is gated the same way the shipped interlocks are.
func test_every_use_modifier_names_a_stat_or_a_channel_that_exists() -> void:
	var items := _load_items()
	var stats := _load_stats()
	assert_true(stats.size() > 0, "no stats loaded, so nothing here can be resolved")
	var checked := 0
	for id in items:
		var item: ItemDefinition = items[id]
		for modifier in item.use_modifiers:
			checked += 1
			assert_true(modifier != null, "%s carries a null use_modifier" % id)
			if modifier == null:
				continue
			var target := String(modifier.target_stat)
			var head := target.get_slice(":", 0)
			assert_true(
				stats.has(StringName(head)) or BEHAVIOUR_CHANNELS.has(head),
				"%s modifies %s, which is neither a stat nor a declared channel"
					% [id, modifier.target_stat]
			)
			assert_true(
				modifier.source_id != &"",
				"%s's modifier on %s has no source, so nothing can ever take it off"
					% [id, modifier.target_stat]
			)
	assert_true(checked > 0, "no item carries a use_modifier; the path is dead data")

## A hot meal is warmth as well as food. Written on the RECOVERY channel, never
## as a negative drain -- see the survival report 2.5 for why that distinction is
## the one thing in this model that cannot be got wrong quietly.
func test_a_hot_meal_holds_the_cold_off_for_a_while() -> void:
	var items := _load_items()
	var meal: ItemDefinition = items.get(&"hot_stew", null)
	assert_not_null(meal, "hot_stew does not ship")
	if meal == null:
		return
	var found := false
	for modifier in meal.use_modifiers:
		if modifier == null or String(modifier.target_stat) != "core_temperature:recovery":
			continue
		found = true
		assert_eq(
			modifier.operation,
			Modifier.Operation.ADD,
			"a hot meal must ADD to the recovery channel; a MULTIPLY of nothing is nothing"
		)
		assert_true(modifier.value > 0.0, "the hot meal's warmth is %f" % modifier.value)
		assert_true(
			modifier.duration > 0.0,
			"the hot meal warms him forever; it has to expire on its own"
		)
	assert_true(found, "hot_stew does nothing to core_temperature:recovery")

## Salt meat is the one carried food, and it costs water later. The modifier
## scales the DRAIN, which is the honest shape: it does not dehydrate you on the
## spot, it makes the next few minutes cost more.
func test_carried_food_costs_water_later() -> void:
	var items := _load_items()
	var meat: ItemDefinition = items.get(&"dried_meat", null)
	assert_not_null(meat, "dried_meat does not ship")
	if meat == null:
		return
	assert_true(meat.nutrition > 0.0, "dried meat feeds nobody")
	assert_eq(meat.heats_into, &"", "dried meat needs a fire, which is what it exists not to need")
	var found := false
	for modifier in meat.use_modifiers:
		if modifier == null or modifier.target_stat != &"thirst":
			continue
		found = true
		assert_eq(
			modifier.operation,
			Modifier.Operation.MULTIPLY,
			"the salt has to scale the thirst drain, not add to the value"
		)
		assert_true(
			modifier.value > 1.0,
			"dried meat scales thirst by %f, which makes salt meat quench you" % modifier.value
		)
		assert_true(modifier.duration > 0.0, "the salt never wears off")
	assert_true(found, "dried_meat costs no water at all")
