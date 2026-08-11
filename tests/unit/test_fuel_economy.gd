extends TestCase

## The machine, on items this file builds itself, so a tuning pass on
## res://data/items cannot break it. The shipped numbers are gated separately in
## tests/unit/test_items_data.gd.
##
## FuelEconomy owns two things and the seam between them: what the player has,
## and what it is worth in seconds of fire. GDD section 5 makes that second
## number the only real currency in the game -- wood, petrol and coal are three
## shapes of it, and water, food, warmth and every beacon are bought with it --
## so `fuel_seconds()` is the single number the whole design funnels into.

const FuelEconomyScript := preload("res://src/systems/fuel_economy.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

var _economy = null
var _survival = null

func after_each() -> void:
	# Both extend Node, which is not reference counted: a missed free() is a
	# leaked ObjectDB instance and a failed run (briefing constraint 2).
	if _economy != null:
		_economy.free()
		_economy = null
	if _survival != null:
		_survival.free()
		_survival = null

# --- helpers ---------------------------------------------------------------

func _item(
	id: StringName,
	category: int,
	fuel := 0.0,
	nutrition := 0.0,
	hydration := 0.0,
	mass := 1.0
) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = id
	item.display_name = String(id)
	item.category = category
	item.fuel_value = fuel
	item.nutrition = nutrition
	item.hydration = hydration
	item.mass_kg = mass
	return item

## Three fuels an order apart, so "cheapest first" is unambiguous, plus a meal
## and a drink.
func _build():
	_economy = FuelEconomyScript.new()
	var definitions: Array = [
		_item(&"kindling", ItemDefinition.Category.FUEL, 60.0, 0.0, 0.0, 0.5),
		_item(&"log", ItemDefinition.Category.FUEL, 600.0, 0.0, 0.0, 3.0),
		_item(&"lump", ItemDefinition.Category.FUEL, 1800.0, 0.0, 0.0, 5.0),
		_item(&"meal", ItemDefinition.Category.FOOD, 0.0, 0.5, 0.1, 0.4),
		_item(&"drink", ItemDefinition.Category.WATER, 0.0, 0.0, 0.6, 1.0),
		_item(&"rubble", ItemDefinition.Category.TOOL, 0.0, 0.0, 0.0, 2.0),
	]
	_economy.load_definitions(definitions)
	return _economy

## A survival model with one stat per thing an item can touch, built here rather
## than loaded so these tests do not depend on the shipped tuning.
func _build_body():
	var hunger := StatDefinition.new()
	hunger.id = &"hunger"
	hunger.initial_value = 0.2
	hunger.base_decay_per_second = 0.0
	var thirst := StatDefinition.new()
	thirst.id = &"thirst"
	thirst.initial_value = 0.2
	thirst.base_decay_per_second = 0.0
	var temperature := StatDefinition.new()
	temperature.id = &"core_temperature"
	temperature.initial_value = 0.5
	temperature.base_decay_per_second = 0.001
	_survival = SurvivalSystemScript.new()
	_survival.load_definitions([hunger, thirst, temperature])
	_survival.start()
	_economy.set_survival_system(_survival)
	return _survival

# --- the store --------------------------------------------------------------

func test_a_new_economy_owns_nothing() -> void:
	var economy = _build()
	assert_eq(economy.count_of(&"log"), 0, "the pile starts stocked")
	assert_eq(economy.fuel_seconds(), 0.0, "there is fire in the bank before anything was found")
	assert_almost_eq(economy.store_mass_kg(), 0.0, 0.0001, "the pack has weight in it already")

func test_adding_and_taking_move_the_count() -> void:
	var economy = _build()
	assert_eq(economy.add(&"log", 3), 3, "add did not report the new count")
	assert_eq(economy.count_of(&"log"), 3)
	assert_eq(economy.take(&"log", 2), 2, "take did not report what it took")
	assert_eq(economy.count_of(&"log"), 1)

## Refusing rather than clamping to zero: "I took two" when there was one is the
## shape of bug that turns into free fuel, and it cannot be seen on screen.
func test_taking_more_than_there_is_takes_only_what_there_is() -> void:
	var economy = _build()
	economy.add(&"log", 1)
	assert_eq(economy.take(&"log", 5), 1, "take reported more than the pile held")
	assert_eq(economy.count_of(&"log"), 0)
	assert_eq(economy.take(&"log", 1), 0, "took a log off an empty pile")

## An id nobody declared cannot enter the store at all. The alternative is a
## typo becoming an item with no definition, and every read of it returning
## zero -- which looks exactly like an empty pile.
func test_an_item_nobody_declared_cannot_be_stocked() -> void:
	var economy = _build()
	assert_eq(economy.add(&"unobtainium", 4), 0, "an undeclared item was accepted")
	assert_eq(economy.count_of(&"unobtainium"), 0)
	assert_false(economy.has_item(&"unobtainium"))

func test_store_mass_adds_up() -> void:
	var economy = _build()
	economy.add(&"log", 2)
	economy.add(&"drink", 1)
	assert_almost_eq(economy.store_mass_kg(), 7.0, 0.0001, "2 logs at 3 kg and a 1 kg drink")

# --- fuel, the only real currency -------------------------------------------

## The single number the design funnels into: everything you own, expressed as
## seconds of fire.
func test_fuel_seconds_is_every_form_of_fuel_in_one_number() -> void:
	var economy = _build()
	economy.add(&"kindling", 2)
	economy.add(&"log", 1)
	economy.add(&"lump", 1)
	assert_almost_eq(
		economy.fuel_seconds(),
		2.0 * 60.0 + 600.0 + 1800.0,
		0.001,
		"the three forms of fuel do not add up to one currency"
	)

func test_food_and_water_are_not_fuel() -> void:
	var economy = _build()
	economy.add(&"meal", 5)
	economy.add(&"drink", 5)
	economy.add(&"rubble", 5)
	assert_eq(economy.fuel_seconds(), 0.0, "something that is not fuel is being counted as fuel")
	assert_false(economy.fuel_ids().has(&"meal"), "a meal is listed among the fuels")

func test_fuel_ids_are_ordered_cheapest_first() -> void:
	var economy = _build()
	# Annotated, not `var wanted = [...]`: an untyped local would compare a plain
	# Array against a typed one, and the shape of that comparison is exactly the
	# sort of thing that passes for the wrong reason.
	var wanted: Array[StringName] = [&"kindling", &"log", &"lump"]
	assert_eq(economy.fuel_ids(), wanted)

func test_withdrawing_one_takes_it_off_the_pile_and_returns_its_burn_time() -> void:
	var economy = _build()
	economy.add(&"log", 2)
	assert_almost_eq(economy.withdraw_fuel(&"log"), 600.0, 0.001)
	assert_eq(economy.count_of(&"log"), 1)
	economy.take(&"log", 1)
	assert_eq(economy.withdraw_fuel(&"log"), 0.0, "withdrew fuel that was not there")

## Kindling before the log, the log before the coal. Burning the hoarded lump
## first is the one ordering that turns a careful player into a dead one, and
## nothing on screen would show it happening.
func test_drawing_burn_seconds_spends_the_cheapest_fuel_first() -> void:
	var economy = _build()
	economy.add(&"kindling", 1)
	economy.add(&"log", 1)
	economy.add(&"lump", 1)
	assert_almost_eq(economy.draw_burn_seconds(30.0), 60.0, 0.001, "that was not the kindling")
	assert_eq(economy.count_of(&"kindling"), 0)
	assert_eq(economy.count_of(&"log"), 1, "the log went in before the kindling was gone")
	assert_eq(economy.count_of(&"lump"), 1, "the coal went in first")

## You put a whole log on the fire. The surplus is not lost -- the caller banks
## it -- so the returned number is what was actually withdrawn, not what was
## asked for.
func test_a_short_burn_still_takes_a_whole_log() -> void:
	var economy = _build()
	economy.add(&"log", 1)
	assert_almost_eq(
		economy.draw_burn_seconds(10.0),
		600.0,
		0.001,
		"draw_burn_seconds must report the whole log it took, or the surplus vanishes"
	)
	assert_eq(economy.count_of(&"log"), 0)

func test_drawing_more_than_you_own_empties_the_pile_and_says_how_little_it_was() -> void:
	var economy = _build()
	economy.add(&"kindling", 2)
	assert_almost_eq(economy.draw_burn_seconds(5000.0), 120.0, 0.001)
	assert_eq(economy.fuel_seconds(), 0.0, "there is fuel left after drawing more than there was")

func test_drawing_from_an_empty_pile_is_nothing_rather_than_an_error() -> void:
	var economy = _build()
	assert_eq(economy.draw_burn_seconds(100.0), 0.0)
	assert_eq(economy.draw_burn_seconds(-100.0), 0.0, "a negative draw produced fuel")

# --- what an item does to the body ------------------------------------------

func test_eating_raises_hunger_and_costs_the_meal() -> void:
	var economy = _build()
	var body = _build_body()
	economy.add(&"meal", 1)
	assert_true(economy.consume(&"meal"), "the meal was refused")
	assert_almost_eq(body.value_of(&"hunger"), 0.7, 0.0001, "0.2 of a bar plus 0.5 of nutrition")
	assert_almost_eq(body.value_of(&"thirst"), 0.3, 0.0001, "a meal carries its own water")
	assert_eq(economy.count_of(&"meal"), 0, "the meal is still in the pack after being eaten")

func test_drinking_raises_thirst() -> void:
	var economy = _build()
	var body = _build_body()
	economy.add(&"drink", 1)
	assert_true(economy.consume(&"drink"))
	assert_almost_eq(body.value_of(&"thirst"), 0.8, 0.0001)

## GDD section 5's funnel as a refusal: something with nothing in it cannot be
## consumed at all. Snow is the case this exists for -- eating it must not
## quietly destroy it for no gain.
func test_something_with_nothing_in_it_cannot_be_consumed() -> void:
	var economy = _build()
	_build_body()
	economy.add(&"rubble", 1)
	assert_false(economy.consume(&"rubble"), "an item with no nutrition, water or effect was consumed")
	assert_eq(economy.count_of(&"rubble"), 1, "it was destroyed anyway")

func test_consuming_something_you_do_not_have_does_nothing() -> void:
	var economy = _build()
	var body = _build_body()
	assert_false(economy.consume(&"meal"))
	assert_almost_eq(body.value_of(&"hunger"), 0.2, 0.0001, "hunger moved without a meal")

## The general path: an item may carry any StatModifier a weather event could,
## and this is the only place items and the modifier stacks meet.
func test_an_items_own_modifiers_are_applied_when_it_is_used() -> void:
	var economy = _build()
	var body = _build_body()
	var salty := _item(&"salt_meat", ItemDefinition.Category.FOOD, 0.0, 0.3)
	var thirstier := StatModifier.new()
	thirstier.target_stat = &"thirst"
	thirstier.source_id = &"salt_meat"
	thirstier.operation = Modifier.Operation.MULTIPLY
	thirstier.value = 2.0
	thirstier.duration = 60.0
	var modifiers: Array[StatModifier] = [thirstier]
	salty.use_modifiers = modifiers
	economy.load_definitions([salty])
	economy.set_survival_system(body)
	economy.add(&"salt_meat", 1)

	assert_eq(body.modifier_count(&"thirst"), 0, "something is already scaling thirst")
	assert_true(economy.consume(&"salt_meat"))
	assert_eq(body.modifier_count(&"thirst"), 1, "the item's own modifier never reached the body")

func test_consuming_without_a_body_is_refused_rather_than_wasted() -> void:
	var economy = _build()
	economy.add(&"meal", 1)
	assert_false(economy.consume(&"meal"), "a meal was eaten with nothing to eat it")
	assert_eq(economy.count_of(&"meal"), 1, "the meal was destroyed with no body to feed")

# --- the shipped content ----------------------------------------------------

## Briefing trap 3: a project [autoload] is a node under /root and never an
## engine singleton, so the resolution has to be get_node_or_null("/root/...").
## Left as Engine.get_singleton this file would refuse every meal for ever,
## silently, and no test that injects its own model would ever notice.
##
## The proof is behavioural: consume() returns false when there is no body, so a
## true here is the resolution having worked. Meltwater is used deliberately --
## it carries no use_modifier, and the live model's thirst is already full, so
## nothing about the shared autoload is left changed.
func test_the_economy_resolves_the_autoloaded_survival_model_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		# Return rather than fall through: dereferencing a null tree aborts the
		# method, and with one assertion already counted the runner's
		# zero-assertion guard would let it print PASS.
		return

	var economy = FuelEconomyScript.new()
	# No set_survival_system() and no load_from_directory(): entering the tree
	# fires _ready(), which is the code path under test.
	tree.root.add_child(economy)
	var loaded: int = economy.item_ids().size()
	economy.add(&"meltwater", 1)
	var drank: bool = economy.consume(&"meltwater")

	# Unwind before asserting, not after: a Node left under /root leaks at exit
	# (briefing constraint 2), and assertions record rather than halt.
	tree.root.remove_child(economy)
	economy.free()

	assert_true(loaded > 0, "_ready() did not load res://data/items")
	assert_true(
		drank,
		"/root/SurvivalSystem was never resolved, so nothing can ever be eaten or drunk"
	)

func test_the_shipped_items_load_from_disk() -> void:
	var economy = FuelEconomyScript.new()
	_economy = economy
	var loaded: int = economy.load_from_directory()
	assert_true(loaded >= 8, "only %d item(s) loaded from res://data/items" % loaded)
	assert_true(economy.has_item(&"firewood"), "firewood is not in the shipped economy")
	economy.add(&"firewood", 1)
	assert_true(economy.fuel_seconds() > 0.0, "a log of the shipped firewood burns for nothing")
