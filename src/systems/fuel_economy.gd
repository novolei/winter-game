extends Node

## Autoload "FuelEconomy". GDD section 5's resource funnel -- what the player
## has, and what it is worth in seconds of fire.
##
##     水  <- 融雪 <- 火 <- 燃料
##     食物 <- 烹饪 <-  ^
##     体温 <---------- '
##     信标 <---------- '
##
## Snow must be melted to drink; melting needs fire; fire needs fuel; beacons
## eat fuel too. FUEL IS THE ONLY TRUE CURRENCY, and wood, petrol and coal are
## three shapes of it. That is what makes "should I walk 200 m further for that
## bundle of wood" a decision about water, food, warmth and five lamps at once,
## and fuel_seconds() is that decision expressed as one number.
##
## It owns no rules of its own. Every item, every burn time, every calorie lives
## in res://data/items/*.tres; this file is the ledger. Adding a fourth fuel, or
## a food nobody has thought of, is a new .tres and nothing else (briefing
## constraint 4). The tuning surface is tools/generate_items.gd.
##
## ---------------------------------------------------------------------------
## WHAT IS AND IS NOT HERE
## ---------------------------------------------------------------------------
## The ledger and the conversion, and nothing that burns. A fire is a thing in
## the world with a position and a radius, so it is a node -- src/entities/stove
## -- and it asks this for fuel like everything else does. Beacons (GDD section
## 6) will do the same: they are the second caller of draw_burn_seconds(), and
## the reason it is written to serve anything rather than to serve the stove.
##
## Nothing here has an opinion about how fuel is FOUND. Picking up a bundle of
## wood, scooping snow into a pot and emptying a beacon's tank are all add() and
## take(), and whoever builds the world owns them.

const DEFAULT_ITEMS_DIRECTORY := "res://data/items"
const SERVICE := &"fuel_economy"

## Which stat an item's nutrition and hydration put back. Named here rather than
## carried per item because ItemDefinition's own field names already decide it:
## a "nutrition" that fed thirst would be a lie in the schema, not a tuning
## option. src/systems/ is game-specific and exempt from briefing constraint 5.
const STAT_HUNGER := &"hunger"
const STAT_THIRST := &"thirst"

var _order: Array[StringName] = []
var _definitions: Dictionary = {}

## item id -> how many are held. Ids with no entry are held zero times; an id
## never enters this table unless a definition declared it, so a typo cannot
## become an item that quietly exists with a count of nothing.
var _store: Dictionary = {}

var _survival = null

# --- wiring ----------------------------------------------------------------

func _ready() -> void:
	if _order.is_empty():
		load_from_directory()
	if is_inside_tree():
		var registry := get_node_or_null("/root/ServiceRegistry")
		if registry != null:
			registry.register(SERVICE, self)


func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(SERVICE) == self:
		registry.unregister(SERVICE)

func set_survival_system(system) -> void:
	_survival = system

## The body this feeds, resolved on first use rather than in _ready().
##
## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3). Getting that wrong leaves this null for ever and every meal is
## silently refused.
##
## Resolved lazily because autoloads are added to /root in the order
## project.godot lists them: from _ready(), an entry declared BELOW this one does
## not exist yet, so a line in the wrong place would produce a game in which
## nothing can ever be eaten and nothing anywhere would say why.
func _body():
	if _survival == null and is_inside_tree():
		_survival = get_node_or_null("/root/SurvivalSystem")
	return _survival

# --- loading ---------------------------------------------------------------

## Loads every ItemDefinition in a directory, in filename order so a run is
## reproducible. Returns how many were accepted.
func load_from_directory(directory_path := DEFAULT_ITEMS_DIRECTORY) -> int:
	var definitions: Array = []
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return 0
	var file_names := dir.get_files()
	file_names.sort()
	for entry in file_names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(directory_path.path_join(file_name))
		if resource is ItemDefinition:
			definitions.append(resource)
	load_definitions(definitions)
	return _order.size()

## Replaces the whole catalogue, and with it the store: an item that no longer
## exists cannot go on being held.
func load_definitions(definitions: Array) -> void:
	_definitions.clear()
	_order.clear()
	_store.clear()
	for definition in definitions:
		if not (definition is ItemDefinition):
			continue
		var id: StringName = definition.id
		if id == &"" or _definitions.has(id):
			continue
		_definitions[id] = definition
		_order.append(id)

func item_ids() -> Array[StringName]:
	return _order.duplicate()

func has_item(item_id: StringName) -> bool:
	return _definitions.has(item_id)

func definition_of(item_id: StringName) -> ItemDefinition:
	return _definitions.get(item_id, null)

# --- the store --------------------------------------------------------------

## Puts `count` of something into the store and returns the new total. An id
## nobody declared is refused outright and returns 0: the alternative is a typo
## becoming an item with no definition, which reads as an empty pile at every
## call site and is indistinguishable from having found nothing.
func add(item_id: StringName, count := 1) -> int:
	if not _definitions.has(item_id) or count <= 0:
		return count_of(item_id)
	_store[item_id] = count_of(item_id) + count
	return _store[item_id]

## Takes up to `count` and returns how many were actually taken, which may be
## fewer. Never reports more than it removed -- that shape of bug is free fuel,
## and nothing on screen would show it.
func take(item_id: StringName, count := 1) -> int:
	if count <= 0:
		return 0
	var held := count_of(item_id)
	var taken := mini(count, held)
	if taken <= 0:
		return 0
	_store[item_id] = held - taken
	return taken

func count_of(item_id: StringName) -> int:
	return int(_store.get(item_id, 0))

func store_mass_kg() -> float:
	var total := 0.0
	for item_id in _store:
		var definition: ItemDefinition = _definitions[item_id]
		total += definition.mass_kg * float(_store[item_id])
	return total

# --- fuel, the only real currency -------------------------------------------

## Every fuel that exists, cheapest first. The order is the burn order: scraps
## before logs, logs before coal. Ties break on id so a run is reproducible.
func fuel_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for item_id in _order:
		var definition: ItemDefinition = _definitions[item_id]
		if definition.category == ItemDefinition.Category.FUEL and definition.fuel_value > 0.0:
			ids.append(item_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var first: ItemDefinition = _definitions[a]
		var second: ItemDefinition = _definitions[b]
		if first.fuel_value == second.fuel_value:
			return String(a) < String(b)
		return first.fuel_value < second.fuel_value
	)
	return ids

## Everything the player owns, as seconds of fire. THE number of GDD section 5:
## water, food, warmth and five beacons are all bought out of it.
func fuel_seconds() -> float:
	var total := 0.0
	for item_id in _store:
		var definition: ItemDefinition = _definitions[item_id]
		if definition.category != ItemDefinition.Category.FUEL:
			continue
		total += definition.fuel_value * float(_store[item_id])
	return total

## Takes exactly one of a named fuel and returns its burn time, or 0.0 when
## there is none to take. What a stove does when the player chooses what to put
## on the fire.
func withdraw_fuel(item_id: StringName) -> float:
	var definition: ItemDefinition = _definitions.get(item_id, null)
	if definition == null or definition.category != ItemDefinition.Category.FUEL:
		return 0.0
	if definition.fuel_value <= 0.0 or take(item_id, 1) <= 0:
		return 0.0
	return definition.fuel_value

## Takes fuel until at least `wanted` seconds have been drawn, cheapest first,
## and returns how much was actually drawn.
##
## THE RETURN MAY EXCEED `wanted`, and that is the point: you put a whole log on
## the fire, and the surplus is the caller's to bank. Returning `wanted` instead
## would silently destroy the rest of the log every time -- a leak in the only
## currency the game has, invisible everywhere.
##
## Written to serve any consumer rather than the stove in particular: GDD
## section 6's beacons burn fuel through this same call.
func draw_burn_seconds(wanted: float) -> float:
	if not is_finite(wanted) or wanted <= 0.0:
		return 0.0
	var drawn := 0.0
	for item_id in fuel_ids():
		while drawn < wanted and count_of(item_id) > 0:
			drawn += withdraw_fuel(item_id)
		if drawn >= wanted:
			break
	return drawn

# --- what an item does to the body ------------------------------------------

## Eats or drinks one of something: nutrition into hunger, hydration into
## thirst, and every StatModifier the item carries pushed onto the body.
##
## Refuses, without consuming anything, when there is no body to feed, none of
## the item to be had, or nothing IN the item. That last one is GDD section 5's
## 雪必须融化才能饮用 expressed as a refusal rather than as a special case: snow
## has no hydration, so eating it is impossible rather than merely pointless,
## and the only way to drink is to have spent fire.
func consume(item_id: StringName) -> bool:
	var body = _body()
	if body == null:
		return false
	var definition: ItemDefinition = _definitions.get(item_id, null)
	if definition == null or not _has_anything_in_it(definition):
		return false
	if take(item_id, 1) <= 0:
		return false
	if definition.nutrition > 0.0:
		body.restore(STAT_HUNGER, definition.nutrition)
	if definition.hydration > 0.0:
		body.restore(STAT_THIRST, definition.hydration)
	for modifier in definition.use_modifiers:
		if modifier != null:
			body.apply_stat_modifier(modifier)
	return true

func _has_anything_in_it(definition: ItemDefinition) -> bool:
	if definition.nutrition > 0.0 or definition.hydration > 0.0:
		return true
	for modifier in definition.use_modifiers:
		if modifier != null and modifier.target_stat != &"":
			return true
	return false
