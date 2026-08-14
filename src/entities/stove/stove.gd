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
const EVENT_STOKED := &"stove.stoked"
const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"
const EVENT_ACTIVATED := &"interaction.activated"
const EVENT_REJECTED := &"interaction.rejected"

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
## World interaction
## ---------------------------------------------------------------------------
## One press banks one whole fuel item through FuelEconomy. The nominal cap is
## allowed to overflow by that item's surplus: clipping a coal to the cap would
## destroy part of the game's only currency without telling the player.
@export var interaction_id: StringName = &""
@export var interaction_label := "Stove"
@export var interaction_radius_m := 2.4
@export var interaction_offset := Vector3(0.0, 0.9, 0.45)
@export var interaction_area_offset := Vector3(0.0, 1.0, 1.1)
@export var interaction_area_size := Vector3(2.4, 2.2, 2.0)
@export var interaction_refill_seconds := 600.0
@export var interaction_capacity_seconds := 3600.0

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

## ---------------------------------------------------------------------------
## WHERE THE FLAME IS, WHICH IS NOT WHERE THE STOVE IS
## ---------------------------------------------------------------------------
## The node's origin sits on the floor, because that is where a stove stands and
## it is what `warmth_at()` measures from. The FIRE is in the firebox, most of a
## metre up, and until this existed the OmniLight sat on the floor with it --
## which has one consequence that is invisible in a list of properties and
## decides the whole look of the room.
##
## The world's two-band cel light() bands on `lambert * ATTENUATION`, and lambert
## for a floor is the dot of +Y with the direction to the light. A light lying ON
## the floor is in the floor's own plane, so that dot is zero everywhere and
## **the fire cannot light the floor at all, at any energy or range**. The room's
## floorboards took the shade band from wall to wall and the only lit surfaces
## were the vertical ones. Raised into the firebox the same light gives the floor
## a real falloff -- lambert h/d, brightest under the fire and dying with
## distance -- which is what makes the room read as lit from one corner.
##
## A vector rather than a height, because a firebox faces a direction. Left at
## the origin the light sits INSIDE the stove's own body, and with shadows on
## that is a lamp in a closed box: the first thing its shadow map sees is the
## casing around it. Offset out through the firebox door and the fire is where a
## fire is, in the room, throwing the stove's own bulk backward onto the wall
## behind it.
##
## Local to the stove, so a stove that is moved or turned takes its fire with it.
@export var light_offset := Vector3.ZERO

## Godot's omni decay exponent (`OmniLight3D.omni_attenuation`). 1.0 is the
## engine default and is roughly inverse-distance.
##
## Lower indoors, and the reason is the cel band rather than physics. At 1.0 the
## distance term falls so much faster than the angle term that the band boundary
## is a ring on the floor a couple of metres out, and every surface past it is
## one flat colour whichever way it faces. Bring the decay down and the ANGLE is
## what decides the band, so the boundary lands on the corners of the furniture
## -- Art Bible section 4.1's two bands, put where they describe the form.
@export var light_attenuation := 1.0

## Whether the fire casts shadows.
##
## Off by default and that must not change: a fire in the OPEN casting shadows
## would lay a second set of them across snow already shaded by the sun through
## a two-band cel shader, and there is only supposed to be one shadow direction
## in this world. The fire outdoors is a glow, not a lamp.
##
## INDOORS it is the opposite, and it is the cheapest form the room has. With
## `light_cull_mask` narrowed to the interior (see below) the shadow map holds
## only the room's own meshes and whoever is standing in it, and every piece of
## furniture gets a dark pool under it that both grounds it and separates it
## from the floorboards it would otherwise merge into.
@export var light_shadows := false

## Which render layers this fire may light. Default is everything, which is
## what a fire in the open should do.
##
## IT MUST NOT BE THE DEFAULT INDOORS, and this export exists because leaving it
## so shipped a visible defect. The world's two-band cel light() picks a palette
## colour from `lambert * ATTENUATION` and never reads LIGHT_COLOR, and this
## light has shadows off by design -- so a stove inside a house shone through
## its walls and pushed an 18 m disc of snow from the shade band into the lit
## one. A bright, texel-stepped circle centred on the building, which read as a
## debug gizmo rather than as firelight.
##
## Set it to InteriorWarmth.INTERIOR_LAYER | PlayerController.CHARACTER_LAYER
## for a fire in a room: it then lights the room and the person standing at it,
## and the valley outside does not know it is burning. Same mechanism as the
## character's own key light.
@export_flags_3d_render var light_cull_mask := 0xFFFFF

var _fuel := 0.0
var _lit := false
var _source_id: StringName = &""
var _light: OmniLight3D = null
var _economy = null
var _survival = null
var _bus = null
var _registry = null
var _occupant_node: Node = null
var _interaction_area: Area3D = null
var _interaction_shape: CollisionShape3D = null
var _near := false
var _offer_present := false
var _last_offer: Dictionary = {}

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
	set_event_bus(_bus)
	_build_light()
	_build_interaction_area()
	if starting_fuel_seconds > 0.0:
		add_fuel_seconds(starting_fuel_seconds)
	if start_lit:
		light()
	_drive_light()

func _exit_tree() -> void:
	_withdraw_offer()
	_disconnect_interaction()
	# A stove that is removed must take its warmth with it, or the body keeps
	# recovering from a fire that is no longer anywhere.
	clear_recovery()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_withdraw_offer()
		_disconnect_interaction()

func set_fuel_economy(economy) -> void:
	_economy = economy

func set_survival_system(system) -> void:
	_survival = system

func set_event_bus(bus) -> void:
	if bus == _bus:
		_connect_interaction()
		return
	_withdraw_offer()
	_disconnect_interaction()
	_bus = bus
	_connect_interaction()
	_publish_offer()

func set_occupant(node: Node) -> void:
	_occupant_node = node

func interaction_area() -> Area3D:
	return _interaction_area

func interaction_anchor_position() -> Vector3:
	return interaction_offset

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
	_emit_stoked(seconds)
	_publish_offer()
	return true

## Banking the fire for a stretch: name the seconds, not the item, and the
## cheapest fuel that covers it goes on. Returns what was actually banked, which
## may be MORE than asked for -- you put a whole log on -- and may be less when
## the pile runs out. GDD section 6's beacons want the same shape.
func stoke_for(seconds: float) -> float:
	if _economy == null:
		return 0.0
	var drawn := float(_economy.draw_burn_seconds(seconds))
	var added := add_fuel_seconds(drawn)
	if added > 0.0:
		_emit_stoked(added)
		_publish_offer()
	return added

## The gameplay action. A cold stove with banked fuel merely lights; an empty
## one first banks one whole item. A burning stove banks one more item. Fuel
## choice remains data-driven inside FuelEconomy.
func interact() -> bool:
	if _lit:
		if not _can_accept_fuel():
			return false
		return stoke_for(_refill_request()) > 0.0
	if _fuel <= 0.0:
		if not _can_accept_fuel() or stoke_for(_refill_request()) <= 0.0:
			return false
	var ignited := light()
	_publish_offer()
	return ignited

func light() -> bool:
	if _lit or _fuel <= 0.0:
		return false
	_lit = true
	# Findable from this instant, because being alight is the whole of what
	# membership means -- see src/entities/fires.gd. Joining here rather than in
	# _ready() is what makes the group's meaning enforceable: a caller asking the
	# group for fires gets fires, never a cold stove it has to filter out.
	Fires.join(self)
	_drive_light()
	_emit(EVENT_LIT)
	_publish_offer()
	return true

## Smothering it. The fuel stays in the firebox -- banking the fire and
## relighting in the evening is the whole of husbanding it.
func extinguish() -> void:
	if not _lit:
		return
	_lit = false
	# Both ways out of the fire lead here -- smothered, and burnt to nothing in
	# advance() -- so there is one place that has to remember to leave.
	Fires.leave(self)
	_drive_light()
	_emit(EVENT_WENT_OUT)
	_publish_offer()

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
##
## One of the three questions every member of the `&"fires"` group answers --
## see src/entities/fires.gd for the other two and for why they are a contract
## rather than a description of this file.
func warmth_at(point: Vector3) -> float:
	if not _lit:
		return 0.0
	var distance := fire_position().distance_to(point)
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
	_light.omni_attenuation = light_attenuation
	_light.light_cull_mask = light_cull_mask
	_light.position = light_offset
	# See light_shadows: off in the open, on in a room, and never on a light
	# whose cull mask still reaches the valley.
	_light.shadow_enabled = light_shadows
	# A room is boxes standing on a floor, all of it within a few metres of the
	# lamp, so the defaults -- tuned for a light out in a scene -- detach every
	# contact shadow from its caster. Small enough to keep the pool touching the
	# table leg, large enough that a wall the fire rakes along does not
	# self-shadow into vertical stripes, which is what the first pass produced
	# on the gable behind the stove.
	_light.shadow_bias = 0.02
	_light.shadow_normal_bias = 0.6
	# A HARD SHADOW, AND NOT BECAUSE HARD IS CHEAPER.
	#
	# A two-band cel light() is a THRESHOLD: `smoothstep(t-s, t+s, lambert *
	# ATTENUATION)` with a narrow s turns any value near t into one band or the
	# other. Feed it a filtered shadow -- PCF, or a penumbra off `light_size` --
	# and the filter's own sample pattern, which is invisible under smooth
	# shading, is quantised into a stipple across every surface whose lambert
	# happens to sit near the boundary. Measured on 4.7.1: `light_size` 0.35
	# dithered the whole room, and even the default PCF blur speckled the wall
	# behind the stove.
	#
	# So ATTENUATION has to arrive as 0 or 1 and the resolution has to carry the
	# edge instead -- which is what the positional shadow atlas in project.godot
	# is sized for. Art Bible rule 10's soft edges are the SUN's, and the sun
	# still has them: it is a different light with a different filter quality.
	_light.light_size = 0.0
	_light.shadow_blur = 0.0
	_light.light_specular = 0.0
	add_child(_light)

func _build_interaction_area() -> void:
	if _interaction_area == null:
		_interaction_area = Area3D.new()
		_interaction_area.name = "InteractionArea"
		_interaction_area.collision_layer = 0
		_interaction_area.collision_mask = 1
		_interaction_area.monitoring = true
		_interaction_area.monitorable = false
		_interaction_area.position = interaction_area_offset
		add_child(_interaction_area)
		_interaction_area.body_entered.connect(on_body_entered)
		_interaction_area.body_exited.connect(on_body_exited)
	if _interaction_shape == null:
		_interaction_shape = CollisionShape3D.new()
		_interaction_shape.name = "InteractionRadius"
		_interaction_area.add_child(_interaction_shape)
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(interaction_area_size.x, 0.1),
		maxf(interaction_area_size.y, 0.1),
		maxf(interaction_area_size.z, 0.1)
	)
	_interaction_shape.shape = box


func on_body_entered(body: Node) -> void:
	if not _accepts(body):
		return
	_near = true
	_publish_offer()


func on_body_exited(body: Node) -> void:
	if not _accepts(body):
		return
	_near = false
	_withdraw_offer()


func _on_interaction_activated(payload) -> void:
	if not (payload is Dictionary):
		return
	if StringName(payload.get("id", &"")) != _offer_id() or not _near:
		return
	if not interact():
		_emit_interaction_rejected()


func _emit_interaction_rejected() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	var offer := _interaction_offer()
	_bus.emit_event(EVENT_REJECTED, {
		"id": _offer_id(),
		"kind": &"stove",
		"verb": String(offer.get("verb", "Use")),
		"label": interaction_label,
		"reason": StringName(offer.get("reason", &"unavailable")),
		"world_position": _interaction_anchor(),
	})


func _publish_offer() -> void:
	if not _near:
		return
	if _bus == null or not is_instance_valid(_bus):
		return
	var offer := _interaction_offer()
	if _offer_present and offer == _last_offer:
		return
	_bus.emit_event(EVENT_OFFER_CHANGED if _offer_present else EVENT_OFFER_ENTERED, offer)
	_offer_present = true
	_last_offer = offer.duplicate(true)


func _withdraw_offer() -> void:
	if not _offer_present:
		return
	if _bus != null and is_instance_valid(_bus):
		_bus.emit_event(EVENT_OFFER_EXITED, {"id": _offer_id()})
	_offer_present = false
	_last_offer.clear()


func _interaction_offer() -> Dictionary:
	var can_light := not _lit and _fuel > 0.0
	var can_add := _can_accept_fuel()
	var enabled := can_light or can_add
	var reason: StringName = &""
	if not enabled:
		reason = &"full" if _at_nominal_capacity() else &"no_fuel"
	return {
		"id": _offer_id(),
		"kind": &"stove",
		"verb": "Add fuel" if _lit else "Light",
		"label": interaction_label,
		"world_position": _interaction_anchor(),
		"enabled": enabled,
		"reason": reason,
	}


func _can_accept_fuel() -> bool:
	if _at_nominal_capacity() or interaction_refill_seconds <= 0.0:
		return false
	return _inventory_fuel_seconds() > 0.0


func _at_nominal_capacity() -> bool:
	return interaction_capacity_seconds > 0.0 and _fuel >= interaction_capacity_seconds


func _refill_request() -> float:
	if interaction_capacity_seconds <= 0.0:
		return interaction_refill_seconds
	return minf(interaction_refill_seconds, maxf(interaction_capacity_seconds - _fuel, 0.0))


func _inventory_fuel_seconds() -> float:
	if _economy != null and _economy.has_method("fuel_seconds"):
		return float(_economy.fuel_seconds())
	return 0.0


func _interaction_anchor() -> Vector3:
	return (global_transform * interaction_offset) if is_inside_tree() else position + interaction_offset


func _offer_id() -> StringName:
	var stable := interaction_id
	if stable == &"":
		stable = StringName(String(get_path()) if is_inside_tree() else String(name))
	return StringName("stove:%s" % String(stable))


func _accepts(body: Node) -> bool:
	var who := _occupant()
	return who != null and body == who


func _connect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.subscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _disconnect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.unsubscribe(EVENT_ACTIVATED, _on_interaction_activated)

func _drive_light() -> void:
	if _light == null:
		return
	_light.light_energy = light_energy_now()
	_light.visible = _lit

# --- internals ---------------------------------------------------------------

## The fire's own position, and the point `warmth_at()` measures from -- the two
## have to be the same or a caller's distance test disagrees with the warmth it
## then asks for. The `&"fires"` group's second question; see fires.gd.
##
## NOT the OmniLight's place. `light_offset` lifts the flame into the firebox for
## the shading, but the warmth and the distance a body stands at are measured
## from where the stove STANDS, which is its own origin on the floor.
func fire_position() -> Vector3:
	return _origin_of(self)


## Where a Node3D is, without asserting that it is in a tree.
##
## `global_position` fails an engine assertion outside the tree and answers with
## the ORIGIN, so an unguarded read does not merely print an error -- for a stove
## at the origin it silently reports that whoever it was asked about is standing
## in the fire. A stove under test is never in a tree, and neither is a body a
## test registers with the ServiceRegistry. Out of a tree the local position IS
## the world position, because there is no parent transform to compose with.
static func _origin_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position

## One id per stove instance, so two fires in one room add up instead of
## replacing each other. Instance id rather than the node name: two stoves under
## different parents may legitimately both be called "Stove".
func _source() -> StringName:
	if _source_id == &"":
		_source_id = StringName("stove:%d" % get_instance_id())
	return _source_id

## WHICH fire, as well as where it is. A position is not an identity: two fires
## in one room cannot be told apart by it, and a listener keyed on position can
## never erase a fire that was moved between lighting it and its going out. The
## position stays because most listeners only want the place.
func _emit(event: StringName) -> void:
	if _bus != null:
		_bus.emit_event(event, {"fire": self, "position": fire_position()})

func _emit_stoked(seconds: float) -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	_bus.emit_event(EVENT_STOKED, {
		"id": interaction_id,
		"kind": &"stove",
		"label": interaction_label,
		"icon_id": &"stoke_fire",
		"added_seconds": seconds,
		"fuel_seconds": _fuel,
		"lit": _lit,
		"world_position": fire_position(),
	})

func _process(delta: float) -> void:
	advance(delta)
	# The inventory can change while the player stays inside this Area. The
	# payload omits the continuously burning timer, so this emits only on a real
	# availability/state change rather than once per frame.
	_publish_offer()
	if _survival == null:
		return
	var occupant := _occupant()
	if occupant == null:
		clear_recovery()
		return
	# _origin_of, not global_position: whoever the registry hands back is not
	# guaranteed to be in a tree, and an unguarded read there answers with the
	# origin -- which is where this stove is standing. See _origin_of().
	apply_recovery(_origin_of(occupant))

## Whoever the fire is warming. The player registers itself with the
## ServiceRegistry autoload on _ready(); when threats or a second character want
## warmth this is the one place that has to learn about them.
func _occupant() -> Node3D:
	if _occupant_node != null and is_instance_valid(_occupant_node):
		return _occupant_node as Node3D
	if not is_inside_tree():
		return null
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
		if _registry == null:
			return null
	_occupant_node = _registry.get_service(&"player") as Node3D
	return _occupant_node as Node3D
