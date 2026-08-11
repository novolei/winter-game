extends SceneTree

## Generator for res://data/items/*.tres -- GDD section 5's resource economy.
##
## Run:
##   godot --headless --path <project> --script res://tools/generate_items.gd
##
## THIS FILE IS THE TUNING SURFACE. The .tres files are generated, never hand
## authored (briefing constraint 7), so this table is where a number gets
## changed and this comment block is where the reasoning lives. Nothing in src/
## knows any of these values, and adding a fourth fuel or a second meal here
## needs no code anywhere.
##
## ---------------------------------------------------------------------------
## THE FUNNEL
## ---------------------------------------------------------------------------
##     水  <- 融雪 <- 火 <- 燃料
##     食物 <- 烹饪 <-  ^
##     体温 <---------- '
##     信标 <---------- '
##
## Snow must be melted to drink; melting needs fire; fire needs fuel. Beacons
## eat fuel too. FUEL IS THE ONLY TRUE CURRENCY -- wood, petrol and coal are
## three shapes of it -- and that is what makes "should I walk 200 m further for
## that bundle of wood" a decision about water, food, warmth and five lamps at
## once.
##
## ---------------------------------------------------------------------------
## WHERE THE NUMBERS COME FROM
## ---------------------------------------------------------------------------
## Two units, and everything below is quoted in them.
##
##   A DAY is 900 s. GDD section 4's seven days are 600+300, 600+300, 480+420,
##   480+420, 420+480, 300+600, 240+660 -- every one of them 900.
##
##   A BAR is one stat emptied. From tools/generate_stats.gd: thirst is 600 s,
##   hunger 720 s, core temperature 1200 s, fatigue 1800 s. So a 900 s day costs
##   1.50 bars of thirst, 1.25 of hunger and 0.75 of warmth, and a restore of
##   `hydration` is worth hydration * 600 seconds of life.
##
## FUEL. fuel_value is SECONDS OF FIRE, because Stove.burn_rate is 1.0 -- a
## stove burns one second of fuel per second lit, so a log IS its number.
##
##   firewood  600 s = 2/3 day, 3 kg. The unit everything else is priced in and
##             the only one found lying about. 200 s/kg: the lightest thing to
##             carry and the worst value for the weight.
##   petrol    900 s = 1 day, 4 kg, 225 s/kg. A can from the truck or the
##             station. Also what a beacon runs on.
##   coal      1800 s = 2 days, 5 kg, 360 s/kg. The best fuel per kilogram
##             carried and the worst thing to be caught out with -- one lump is
##             five kilos and it is all or nothing.
##
##   The ladder runs the same way in both directions on purpose: the light unit
##   is the least efficient and the heavy one the most, so "which do I carry
##   home" has an answer that depends on how far away home is.
##
## WATER. GDD section 5: 雪必须融化才能饮用.
##
##   snow       0 hydration, 90 s of fire to melt. Free, everywhere, worthless.
##   meltwater  0.75 of the thirst bar = 450 s. Two a day, morning and evening,
##              covers the 1.5 bars a day costs, with the overflow lost if he
##              drinks while still full -- which is what makes it a chore with a
##              right time rather than a button.
##
##   180 s of fire a day, for water alone. That is the interlock that pulls the
##   fuel economy into EVERY day rather than every other one.
##
## FOOD. GDD section 5: 食物 <- 烹饪.
##
##   canned_stew  0.20 of the hunger bar = 144 s, eaten cold. 120 s of fire to
##                cook. Deliberately edible cold: the decision is "is a hot meal
##                worth two minutes of the fire", and there is no decision if the
##                cold option is nothing.
##   hot_stew     0.65 of the hunger bar = 468 s, and 0.10 of thirst on top. More
##                than three times the can, which is what makes the fire worth
##                lighting to eat. Two a day covers the 1.25 bars a day costs.
##   dried_meat   0.35 = 252 s, no fire, 0.2 kg. The food you carry, at half a
##                hot meal -- and the salt costs you water for the next five
##                minutes, which is the whole reason it is not simply better.
##
## THE DAY'S BILL. 2 melts (180 s) + 2 cooks (240 s) = 420 s of fire before a
## single second of warmth: seven tenths of a log every day, just to eat and
## drink. A night by the stove on day 1 is another 300 s. So a day is about 1.2
## logs, a week is eight or nine, and running out is a thing the player can see
## coming and still fail to prevent.
##
## USE MODIFIERS. Two ship, and they are the demonstration that an item can do
## anything a weather event can:
##
##   hot_stew    +1/1200 on core_temperature:RECOVERY for 120 s. That is exactly
##               the base loss of warmth, so a hot meal holds the winter off for
##               two minutes. On the recovery channel, never as a negative drain
##               -- see the survival report 2.5 for why that distinction is the
##               one thing in this model that cannot go wrong quietly.
##   dried_meat  x1.25 on the thirst DRAIN for 300 s. Salt meat does not
##               dehydrate you on the spot; it makes the next five minutes cost
##               more. 300 s at 1/600 with a quarter added is 0.125 of a bar,
##               about a sixth of a drink.

const ADD := 0  # Modifier.Operation.ADD
const MUL := 1  # Modifier.Operation.MULTIPLY

const FUEL := 0  # ItemDefinition.Category.FUEL
const FOOD := 1
const WATER := 2

## One row per item. `modifiers` rows are [target, operation, value, duration].
const ITEMS := [
	{
		"id": &"firewood",
		"display_name": "Firewood",
		"category": FUEL,
		"mass_kg": 3.0,
		"fuel_value": 600.0,
	},
	{
		"id": &"petrol",
		"display_name": "Jerry can of petrol",
		"category": FUEL,
		"mass_kg": 4.0,
		"fuel_value": 900.0,
	},
	{
		"id": &"coal",
		"display_name": "Coal",
		"category": FUEL,
		"mass_kg": 5.0,
		"fuel_value": 1800.0,
	},
	{
		"id": &"snow",
		"display_name": "Packed snow",
		"category": WATER,
		"mass_kg": 1.0,
		"heats_into": &"meltwater",
		"heat_seconds": 90.0,
	},
	{
		"id": &"meltwater",
		"display_name": "Meltwater",
		"category": WATER,
		"mass_kg": 1.0,
		"hydration": 0.75,
	},
	{
		"id": &"canned_stew",
		"display_name": "Tin of stew",
		"category": FOOD,
		"mass_kg": 0.5,
		"nutrition": 0.20,
		"heats_into": &"hot_stew",
		"heat_seconds": 120.0,
	},
	{
		"id": &"hot_stew",
		"display_name": "Hot stew",
		"category": FOOD,
		"mass_kg": 0.5,
		"nutrition": 0.65,
		"hydration": 0.10,
		"modifiers": [
			[&"core_temperature:recovery", ADD, 1.0 / 1200.0, 120.0],
		],
	},
	{
		"id": &"dried_meat",
		"display_name": "Dried meat",
		"category": FOOD,
		"mass_kg": 0.2,
		"nutrition": 0.35,
		"modifiers": [
			[&"thirst", MUL, 1.25, 300.0],
		],
	},
]

func _initialize() -> void:
	var ItemDefinitionScript := load("res://src/definitions/item_definition.gd")
	var StatModifierScript := load("res://src/definitions/stat_modifier.gd")
	var directory := "res://data/items"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

	var failed := false
	for row in ITEMS:
		var item: ItemDefinition = ItemDefinitionScript.new()
		item.id = row["id"]
		item.display_name = row["display_name"]
		item.category = row["category"]
		item.mass_kg = row["mass_kg"]
		item.fuel_value = row.get("fuel_value", 0.0)
		item.nutrition = row.get("nutrition", 0.0)
		item.hydration = row.get("hydration", 0.0)
		item.heats_into = row.get("heats_into", &"")
		item.heat_seconds = row.get("heat_seconds", 0.0)

		# Annotated, not `var modifiers = []`. An untyped local makes the compiler
		# emit an untyped Array for the assignment below, the typed setter rejects
		# it, and the VM ABORTS the rest of this function -- silently, after having
		# written some of the files (briefing trap 4).
		var modifiers: Array[StatModifier] = []
		for modifier_row in row.get("modifiers", []):
			var modifier: StatModifier = StatModifierScript.new()
			modifier.target_stat = modifier_row[0]
			# The item is the source, so remove_source(<item id>) takes back
			# everything that item ever pushed.
			modifier.source_id = row["id"]
			modifier.operation = modifier_row[1]
			modifier.value = modifier_row[2]
			modifier.duration = modifier_row[3]
			modifiers.append(modifier)
		item.use_modifiers = modifiers

		var path := "%s/%s.tres" % [directory, row["id"]]
		var error := ResourceSaver.save(item, path)
		if error != OK:
			print("generate_items: FAILED %s (%d)" % [path, error])
			failed = true
			continue
		print("generate_items: wrote %s" % path)
	# quit() only REQUESTS exit at the end of the current iteration; it does not
	# return from this function. An early quit(1) inside the loop would fall
	# through and be overwritten by a later quit(0), reporting success over a
	# failed save. Accumulate, and quit exactly once, last.
	quit(1 if failed else 0)
