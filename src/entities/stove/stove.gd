class_name Stove
extends Node3D

## The fire. GDD section 5's resource funnel has one arrow in and four out, and
## every one of them passes through this node.
##
##     水  <- 融雪 <- 火 <- 燃料
##     食物 <- 烹饪 <-  ^
##     体温 <---------- '
##     信标 <---------- '
##
## It is the reason the farmhouse is home. Before it existed every survival stat
## could only fall: there was no fire, no food, no water and no shelter, so the
## whole model was a countdown with no way to answer it. A stove turns fuel into
## warmth, into drinkable water, into a hot meal and into rest, and the fact that
## all four come out of the same pile of wood is what makes "should I walk 200 m
## further for that bundle" a decision at all.
##
## ---------------------------------------------------------------------------
## WHAT IS HERE AND WHAT IS NOT
## ---------------------------------------------------------------------------
## The fire is a thing in the world -- it has a position and a radius, so it is a
## node. The LEDGER is not: what the player owns and what an item is worth live
## in the FuelEconomy autoload, and this asks it for fuel like a beacon will.
## Nothing here knows what firewood is; it knows that fuel_value is seconds.
##
## Lighting it is a bare light() today. GDD section 5 makes cold hands slower to
## light a fire -- the survival model publishes `ignition:speed` for exactly that
## -- but no fire-lighting ACTION exists yet, so there is nothing here for that
## channel to modulate and inventing one would mean two of them later.
##
## ---------------------------------------------------------------------------
## HOW IT REACHES THE BODY
## ---------------------------------------------------------------------------
## Through the RECOVERY channel, never as a negative drain. SurvivalSystem keeps
## `<stat>:drain` and `<stat>:recovery` as separate stacks precisely so that a
## fire cannot be written as "drain, minus something": with one stack, "you tire
## faster when dehydrated" -- a MULTIPLY above 1 -- would scale a negative total
## and recover the player FASTER. See the survival report 2.5.
##
## Writing it the right way round also makes GDD section 5's thirst interlock
## live for the first time: 口渴低 -> 疲劳恢复变慢 multiplies fatigue:recovery by
## 0.5, and until something produced fatigue:recovery there was nothing for it to
## halve. This stove is that producer.
##
## Each stove carries its OWN source id. Sharing one would make the second fire
## take the first one's warmth off the body every time it updated, and two fires
## would be worth less than one.

const EVENT_LIT := &"stove.lit"
const EVENT_WENT_OUT := &"stove.went_out"

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## The two stats a fire puts back, and the channel it puts them on.
const TARGET_WARMTH := &"core_temperature:recovery"
const TARGET_REST := &"fatigue:recovery"

## ---------------------------------------------------------------------------
## Fuel
## ---------------------------------------------------------------------------
## Seconds of fuel consumed per second alight. AT 1.0, AN ITEM'S `fuel_value` IS
## LITERALLY HOW LONG IT BURNS, and the whole economy is priced in that one unit:
## a log is 600 s, melting snow costs 90, a hot meal 120. Changing this rescales
## every one of those at once, which is the point of it being a single number --
## a bigger stove is one that eats its wood faster.
@export var burn_rate := 1.0

## Authored starting state, for a stove placed in a level that should already be
## going -- the farmhouse's own fire on the morning of day 1. Zero means cold and
## empty, which is what a stove found in the world should be.
@export var starting_fuel_seconds := 0.0
@export var start_lit := false

## ---------------------------------------------------------------------------
## Warmth
## ---------------------------------------------------------------------------
## Full warmth out to `warm_radius_m`, then falling to nothing over another
## `warm_falloff_m`. Three metres is a room's hearth: close enough that standing
## at the fire is a place you are rather than a spot you balance on, and short
## enough that the warm corner of a farmhouse is a corner.
@export var warm_radius_m := 3.0
@export var warm_falloff_m := 3.0

## ---------------------------------------------------------------------------
## What the warmth is worth -- the two numbers this whole node exists to set
## ---------------------------------------------------------------------------
## Both are stated as multiples of the drain they answer, because a restore rate
## on its own means nothing: what matters is the proportion to the loss side in
## tools/generate_stats.gd.
##
##   WARMTH  1/300 per second is FOUR TIMES core temperature's own 1/1200 loss,
##           so the net at the hearth is three times the loss and an empty man is
##           warm again in 400 s. A day-1 excursion costs about half the bar and
##           comes back in a little over 200 s -- inside day 1's 300 s night,
##           with time left for the other chores. That is "a night by a well-fed
##           fire meaningfully undoes a day outdoors" as a number.
##
##           Note what it does NOT do: it cannot outrun a starving body. Hunger
##           below 0.30 scales the temperature DRAIN by 1.5 and below 0.05 by
##           3.0, and the drain is a different stack, so a starving man at the
##           fire warms at a third of the rate a fed one does. Eating is part of
##           getting warm, which is GDD section 5's interlock doing its job.
##
##   REST    1/600 per second is THREE TIMES fatigue's own 1/1800, so the net is
##           twice the loss and a full bar takes 900 s -- a whole day of sitting
##           by the fire, and three times day 1's night. Deliberately the slower
##           of the two: sitting up by a fire is not sleeping, and whoever builds
##           sleep should push a bigger number onto the same channel and get the
##           dehydration penalty for free.
@export var warmth_recovery_per_second := 1.0 / 300.0
@export var rest_recovery_per_second := 1.0 / 600.0

## ---------------------------------------------------------------------------
## The light
## ---------------------------------------------------------------------------
## The one warm point in a blue frame -- Art Bible rule 12 keeps warm pixels for
## fire, windows, beacons, the scarf and the truck, and this is the first of
## them. The colour is read from the palette, never written here.
##
## `light_fade_seconds` is the only warning the player gets that the fire is
## dying: GDD section 9 has no HUD, so a fire with a minute left has to LOOK like
## a fire with a minute left.
@export var light_energy := 2.2
@export var light_range_m := 9.0
@export var light_fade_seconds := 60.0

var _fuel := 0.0
var _lit := false
var _source_id: StringName = &""
var _light: OmniLight3D = null
var _economy = null
var _survival = null
var _bus = null
var _registry = null

# --- wiring ----------------------------------------------------------------

func _ready() -> void:
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
	# node under /root and never enters the engine's singleton registry
	# (briefing trap 3). Guarded on is_inside_tree() because an absolute path
	# cannot be resolved from a node that is not in a tree, and a stove under
	# test never is.
	if is_inside_tree():
		if _economy == null:
			_economy = get_node_or_null("/root/FuelEconomy")
		if _survival == null:
			_survival = get_node_or_null("/root/SurvivalSystem")
		if _bus == null:
			_bus = get_node_or_null("/root/EventBus")
	_build_light()
	if starting_fuel_seconds > 0.0:
		add_fuel_seconds(starting_fuel_seconds)
	if start_lit:
		light()
	_drive_light()

func _exit_tree() -> void:
	# A stove that is removed must take its warmth with it, or the body keeps
	# recovering from a fire that is no longer anywhere.
	clear_recovery()

func set_fuel_economy(economy) -> void:
	_economy = economy

func set_survival_system(system) -> void:
	_survival = system

func set_event_bus(bus) -> void:
	_bus = bus

# --- fuel -------------------------------------------------------------------

func is_lit() -> bool:
	return _lit

func fuel_remaining() -> float:
	return _fuel

## Puts burn time straight into the firebox, off no pile and at no cost. The
## AUTHORED path -- `starting_fuel_seconds` on a placed stove, and a test that
## cares what a fire does rather than what it costs. Gameplay goes through
## stoke() and stoke_for(), which take it off the player's own store.
func add_fuel_seconds(seconds: float) -> float:
	if not is_finite(seconds) or seconds <= 0.0:
		return 0.0
	_fuel += seconds
	return seconds

## The player choosing what to put on: takes exactly one of a named fuel off the
## store and banks its whole burn time.
func stoke(item_id: StringName) -> bool:
	if _economy == null:
		return false
	var seconds: float = _economy.withdraw_fuel(item_id)
	if seconds <= 0.0:
		return false
	add_fuel_seconds(seconds)
	return true

## Banking the fire for a stretch: name the seconds, not the item, and the
## cheapest fuel that covers it goes on. Returns what was actually banked, which
## may be MORE than asked for -- you put a whole log on -- and may be less when
## the pile runs out. GDD section 6's beacons want the same shape.
func stoke_for(seconds: float) -> float:
	if _economy == null:
		return 0.0
	return add_fuel_seconds(_economy.draw_burn_seconds(seconds))

func light() -> bool:
	if _lit or _fuel <= 0.0:
		return false
	_lit = true
	_drive_light()
	_emit(EVENT_LIT)
	return true

## Smothering it. The fuel stays in the firebox -- banking the fire and
## relighting in the evening is the whole of husbanding it.
func extinguish() -> void:
	if not _lit:
		return
	_lit = false
	_drive_light()
	_emit(EVENT_WENT_OUT)

## Public and carrying all the logic; _process only forwards to it. That lets a
## fire be burned down a whole night at a time in a test with no running
## SceneTree, the same way WorldClock and SurvivalSystem are written.
func advance(delta: float) -> void:
	if not _lit or not is_finite(delta) or delta <= 0.0:
		return
	_fuel = maxf(_fuel - delta * burn_rate, 0.0)
	if _fuel <= 0.0:
		extinguish()
	else:
		_drive_light()

# --- warmth -----------------------------------------------------------------

## How much of this fire reaches `point`, 0 .. 1. Zero when it is not burning:
## an unlit stove is furniture.
func warmth_at(point: Vector3) -> float:
	if not _lit:
		return 0.0
	var distance := _origin().distance_to(point)
	if distance <= warm_radius_m:
		return 1.0
	if warm_falloff_m <= 0.0:
		return 0.0
	return 1.0 - smoothstep(warm_radius_m, warm_radius_m + warm_falloff_m, distance)

## What a body standing at `point` receives, as target -> per-second recovery.
## Pure, so the proportion to the drain side can be asserted without anything
## having to happen.
func recovery_at(point: Vector3) -> Dictionary:
	var warmth := warmth_at(point)
	return {
		TARGET_WARMTH: warmth_recovery_per_second * warmth,
		TARGET_REST: rest_recovery_per_second * warmth,
	}

## Pushes what recovery_at() says onto the body, replacing whatever this stove
## pushed last time.
##
## Removed and re-added every call rather than accumulated -- the same discipline
## SurvivalSystem's own threshold effects use. An implementation that re-added
## while the player stood still would compound the fire's warmth every frame and
## look perfectly fine on screen for about four seconds.
##
## Re-pushing unconditionally is also what makes this survive a restart:
## SurvivalSystem.start() clears every stack, so a stove that only pushed when
## its value changed would go silently inert for the whole of the next run.
func apply_recovery(point: Vector3) -> void:
	if _survival == null:
		return
	var source := _source()
	_survival.remove_source(source)
	var rates := recovery_at(point)
	for target in rates:
		var amount: float = rates[target]
		if amount > 0.0:
			_survival.push_modifier(target, source, Modifier.Operation.ADD, amount)

func clear_recovery() -> void:
	if _survival != null:
		_survival.remove_source(_source())

# --- melting and cooking -----------------------------------------------------

## Puts one of something on the fire and returns what came off, or &"" when
## nothing did.
##
## 雪必须融化才能饮用, 融雪要烧火 -- melting snow and cooking a meal are the same
## mechanic and the same two fields in a .tres (ItemDefinition.heats_into and
## heat_seconds). Adding a recipe is content; there is no branch here that knows
## what snow is.
##
## The fuel is spent at once rather than over the seconds it names. A stove that
## took the snow, spent what fuel it had and produced nothing would destroy both
## silently, so the job is refused outright when the firebox cannot cover it.
func heat(item_id: StringName) -> StringName:
	if _economy == null or not _lit:
		return &""
	var definition: ItemDefinition = _economy.definition_of(item_id)
	if definition == null or definition.heats_into == &"":
		return &""
	if not _economy.has_item(definition.heats_into):
		return &""
	if _fuel < definition.heat_seconds:
		return &""
	if _economy.take(item_id, 1) <= 0:
		return &""
	_fuel = maxf(_fuel - definition.heat_seconds, 0.0)
	_economy.add(definition.heats_into, 1)
	if _fuel <= 0.0:
		# The job that takes the last of the wood also takes the fire.
		extinguish()
	else:
		_drive_light()
	return definition.heats_into

# --- the light ---------------------------------------------------------------

## What the fire is putting out right now, after the dying-down fade. Public so
## the fade can be asserted without reaching into the OmniLight.
func light_energy_now() -> float:
	if not _lit:
		return 0.0
	if light_fade_seconds <= 0.0:
		return light_energy
	return light_energy * clampf(_fuel / light_fade_seconds, 0.0, 1.0)

func _build_light() -> void:
	if _light != null:
		return
	var bible = load(PALETTE_PATH)
	_light = OmniLight3D.new()
	_light.name = "Firelight"
	# Never a literal. Every colour in this project comes out of
	# data/palette/color_bible.tres (briefing constraint 6); warm_tones' last
	# entry is the bright one the windows and the beacons share.
	if bible != null and not bible.warm_tones.is_empty():
		_light.light_color = bible.warm_tones[bible.warm_tones.size() - 1]
	_light.omni_range = light_range_m
	# Off: the world is lit by one directional sun through a two-band cel
	# shader, and a second shadow-casting light would lay a second band across
	# the snow. The fire is a glow, not a lamp.
	_light.shadow_enabled = false
	_light.light_specular = 0.0
	add_child(_light)

func _drive_light() -> void:
	if _light == null:
		return
	_light.light_energy = light_energy_now()
	_light.visible = _lit

# --- internals ---------------------------------------------------------------

## The fire's own position. Node3D.global_position asserts on a node that is not
## inside a tree, and a stove under test never is, so the local transform stands
## in for it there.
func _origin() -> Vector3:
	return global_position if is_inside_tree() else position

## One id per stove instance, so two fires in one room add up instead of
## replacing each other. Instance id rather than the node name: two stoves under
## different parents may legitimately both be called "Stove".
func _source() -> StringName:
	if _source_id == &"":
		_source_id = StringName("stove:%d" % get_instance_id())
	return _source_id

func _emit(event: StringName) -> void:
	if _bus != null:
		_bus.emit_event(event, {"position": _origin()})

func _process(delta: float) -> void:
	advance(delta)
	if _survival == null:
		return
	var occupant := _occupant()
	if occupant == null:
		clear_recovery()
		return
	apply_recovery(occupant.global_position)

## Whoever the fire is warming. The player registers itself with the
## ServiceRegistry autoload on _ready(); when threats or a second character want
## warmth this is the one place that has to learn about them.
func _occupant() -> Node3D:
	if not is_inside_tree():
		return null
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
		if _registry == null:
			return null
	return _registry.get_service(&"player") as Node3D
