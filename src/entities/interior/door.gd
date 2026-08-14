class_name Door
extends Area3D

## A door that opens, so that going inside is an ARRIVAL rather than a filter.
##
## The reveal on its own has a flaw you only notice by playing it: the player
## can walk in anywhere along the wall and the roof lifts, which makes the whole
## effect read as a region the camera behaves differently in. Walking to a door,
## opening it, and having the house open up is a different thing entirely -- it
## makes the threshold a PLACE. GDD section 11 already binds `E` to *interact:
## light a fire, pick up, open a door*, so this is the route the design expects.
##
## ---------------------------------------------------------------------------
## WHAT THIS CANNOT DO ON ITS OWN
## ---------------------------------------------------------------------------
## It cannot stop the player walking through a wall, because nothing in this
## world has a collision body yet -- the ground is a displaced mesh read
## analytically and the buildings are bare meshes. Making walls solid is
## another agent's task and must not be duplicated here.
##
## What it CAN do, and does, is make the door the only thing that lets the
## house open: InteriorReveal takes an `entry_gate_path`, and with this on the
## other end of it, crossing the threshold with the door shut reveals nothing.
## Walk through the wall and you get a room with its roof still on. That is the
## whole rule until the walls are solid, and it is the same rule afterwards.
##
## ---------------------------------------------------------------------------
## THE LEAF
## ---------------------------------------------------------------------------
## FH_Door is its own object in farmhouse.glb with its origin ON THE HINGE --
## see DOOR_HINGE in tools/blender/build_farmhouse.py, which is the only object
## in that model whose origin is not the world origin. So opening the door is
## one rotation about the leaf's local Y and no skinning, no animation player
## and no second mesh.

const EVENT_OPENED := &"door.opened"
const EVENT_CLOSED := &"door.closed"
const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"
const EVENT_ACTIVATED := &"interaction.activated"
const EVENT_ENTRY_REQUESTED := &"door.entry_requested"

## The hinged leaf, by name, resolved under `building_path` -- the same
## authored-name convention as InteriorReveal.fade_parts.
@export var leaf_part: StringName = &""

## Empty means the node this hangs under.
@export var building_path: NodePath = ^""

## Which way, and how far. Positive swings the leaf's +X end toward -Z, which
## for the farmhouse is INWARD -- a door opening onto the porch would foul the
## steps it stands at the top of, and the first drift would shut it.
@export var open_degrees := 90.0

## Slower than the reveal's 0.30 s, and it should be: the fade is an edit to the
## picture, this is a thing happening in the world.
@export var swing_seconds := 0.5

## GDD section 11. Registered here if no input map defines it, the same way
## PlayerController registers its four movement actions and for the same reason
## -- the whole input surface of the slice stays readable in the scripts that
## use it, and a real input map added later wins.
@export var interact_action: StringName = &"interact"

## Stable content identity for the central interaction focus. An empty value
## falls back to the scene path, while authored/runtime doors should set it.
@export var interaction_id: StringName = &""

## For a door that should just swing as you walk up to it. Off by default: the
## design says `E`.
@export var opens_on_approach := false

## Some fixed-camera doors are hard to steer through by hand. When enabled, E
## opens the leaf and publishes one value-only destination just beyond the
## threshold. PlayerController owns the short walk and releases control at the
## destination; the door never calls the player directly.
@export var guides_entry := false
@export var entry_target_offset := Vector3.ZERO
## Optional Marker3D kept on the visible door while the much larger Area3D may
## sit farther outside to make discovery forgiving.
@export var interaction_anchor_path: NodePath = ^""

@export var occupant_service: StringName = &"player"

var _open := false
var _swing := 0.0
var _leaf: Node3D = null
var _resolved := false
var _closed_basis := Basis.IDENTITY
var _tween: Tween = null
var _near := false
var _bus = null
var _registry = null
var _occupant: Node = null
var _offer_present := false


func _ready() -> void:
	if _bus == null:
		set_event_bus(get_node_or_null("/root/EventBus"))
	resolve()
	_complain()
	apply_swing(0.0)
	if not body_entered.is_connected(on_body_entered):
		body_entered.connect(on_body_entered)
	if not body_exited.is_connected(on_body_exited):
		body_exited.connect(on_body_exited)


func _exit_tree() -> void:
	_withdraw_offer()
	_disconnect_interaction()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_withdraw_offer()
		_disconnect_interaction()


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
	_occupant = node


func building_node() -> Node:
	if not building_path.is_empty():
		var named := get_node_or_null(building_path)
		if named != null:
			return named
	return get_parent()


func resolve() -> void:
	_resolved = true
	_leaf = null
	var building := building_node()
	if building != null and leaf_part != &"":
		_leaf = building.find_child(String(leaf_part), true, false) as Node3D
	if _leaf == null:
		return
	# The shut pose, captured once. Everything after this is a rotation applied
	# to it, so re-closing lands exactly where the model put the leaf rather
	# than on an accumulated identity.
	_closed_basis = _leaf.transform.basis


## Shouted from _ready() and NOT from resolve(), so a test may resolve a
## deliberately broken name and assert what came back without printing an
## engine-level ERROR into a suite whose output has to stay pristine (briefing
## constraint 1). Same split as InteriorReveal and InteriorWarmth.
func _complain() -> void:
	if _leaf != null or leaf_part == &"":
		return
	var building := building_node()
	push_error(
		"door: no Node3D called %s under %s. The door has nothing to swing, so the "
		% [leaf_part, String(building.name) if building != null else "?"]
		+ "house can only ever be entered through a painted rectangle."
	)


func leaf() -> Node3D:
	if not _resolved:
		resolve()
	return _leaf


## The hole in the wall, in world space -- the leaf's own bounds, because the
## leaf is exactly the shape of what it fills.
##
## Asked for by InteriorReveal when it publishes the building's footprint, so
## that the snow field can blow a drift through the opening rather than stamp a
## sealed rectangle. Read while the door is SHUT: an open leaf has swung out of
## the doorway it describes, which is why the footprint is published once at
## startup and not maintained.
##
## An empty AABB means there is nothing to describe -- no leaf, or a leaf that
## is not a visual. The reveal treats that as "this building has no doorway",
## which is the right answer for a barn with an open front.
func opening() -> AABB:
	var visual := leaf() as VisualInstance3D
	if visual == null:
		return AABB()
	# world_of, not global_transform: the latter asserts is_inside_tree() and
	# returns identity when it fails. See the note on InteriorReveal.world_of.
	return InteriorReveal.world_of(visual) * visual.get_aabb()


# --- opening ----------------------------------------------------------------

func is_open() -> bool:
	return _open


## How far through the swing, 0 shut .. 1 open. Public so a test can assert the
## pose without waiting for a tween.
func swing() -> float:
	return _swing


func apply_swing(value: float) -> void:
	if not is_finite(value):
		return
	_swing = clampf(value, 0.0, 1.0)
	if not _resolved:
		resolve()
	if _leaf == null:
		return
	_leaf.transform.basis = _closed_basis.rotated(Vector3.UP, deg_to_rad(open_degrees) * _swing)


func swing_duration_to(target: float) -> float:
	return swing_seconds * absf(clampf(target, 0.0, 1.0) - _swing)


func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


func set_open(wanted: bool) -> void:
	if wanted == _open:
		_publish_offer()
		return
	_open = wanted
	_announce(EVENT_OPENED if wanted else EVENT_CLOSED)
	_publish_offer()
	var target := 1.0 if wanted else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	var duration := swing_duration_to(target)
	if not is_inside_tree() or duration <= 0.0:
		apply_swing(target)
		return
	_tween = create_tween()
	_tween.tween_method(apply_swing, _swing, target, duration)


func toggle() -> void:
	set_open(not _open)


# --- the player at the door -------------------------------------------------

func is_occupant_near() -> bool:
	return _near


func on_body_entered(body: Node) -> void:
	if not accepts(body):
		return
	_near = true
	if opens_on_approach:
		open()
	_publish_offer()


func on_body_exited(body: Node) -> void:
	if not accepts(body):
		return
	_near = false
	_withdraw_offer()


## Fails closed, for the same reason InteriorReveal.accepts does: with no
## occupant resolvable nothing may open the house.
func accepts(body: Node) -> bool:
	var who := occupant()
	return who != null and body == who


func occupant() -> Node:
	if _occupant != null and is_instance_valid(_occupant):
		return _occupant
	if not is_inside_tree():
		return null
	if _registry == null:
		# get_node_or_null, NOT Engine.get_singleton (briefing trap 3).
		_registry = get_node_or_null("/root/ServiceRegistry")
		if _registry == null:
			return null
	_occupant = _registry.get_service(occupant_service) as Node
	return _occupant


## The main interaction director owns input. This handler validates its
## value-only command again so a stale focus cannot operate a departed door.
func _on_interaction_activated(payload) -> void:
	if not (payload is Dictionary):
		return
	if StringName(payload.get("id", &"")) != _offer_id() or not _near:
		return
	if guides_entry:
		open()
		_announce_entry_request()
		_withdraw_offer()
		return
	toggle()


func _publish_offer() -> void:
	if not _near:
		return
	var bus = _event_bus()
	if bus == null:
		return
	var payload := {
		"id": _offer_id(),
		"kind": &"door",
		"verb": "Enter" if guides_entry else ("Close" if _open else "Open"),
		"label": String(building_node().name) if guides_entry and building_node() != null else "Door",
		"world_position": _interaction_anchor(),
		"enabled": true,
	}
	bus.emit_event(EVENT_OFFER_CHANGED if _offer_present else EVENT_OFFER_ENTERED, payload)
	_offer_present = true


func _withdraw_offer() -> void:
	if not _offer_present:
		return
	if _bus != null and is_instance_valid(_bus):
		_bus.emit_event(EVENT_OFFER_EXITED, {"id": _offer_id()})
	_offer_present = false


func _offer_id() -> StringName:
	var stable := interaction_id
	if stable == &"":
		stable = StringName(String(get_path()) if is_inside_tree() else String(name))
	return StringName("door:%s" % String(stable))


func _interaction_anchor() -> Vector3:
	if not interaction_anchor_path.is_empty():
		var authored := get_node_or_null(interaction_anchor_path) as Node3D
		if authored != null:
			return InteriorReveal.world_of(authored) * Vector3.ZERO
	# The Area's authored centre stays in the doorway even while the leaf swings.
	# It is also the centre of the generous interaction range, so the prompt and
	# the physical affordance agree. Imported leaf bounds are only a fallback:
	# once the leaf opens their centre travels into the room with the mesh.
	for child in get_children():
		if child is CollisionShape3D:
			var shape := child as CollisionShape3D
			if is_inside_tree():
				return shape.global_position
			return position + shape.position
	var hole := opening()
	if hole.size.length_squared() > 0.000001:
		return hole.get_center()
	return global_position if is_inside_tree() else position


func entry_destination() -> Vector3:
	var building := building_node() as Node3D
	if building == null:
		return entry_target_offset
	return InteriorReveal.world_of(building) * entry_target_offset


func _announce_entry_request() -> void:
	var bus = _event_bus()
	if bus == null:
		return
	bus.emit_event(EVENT_ENTRY_REQUESTED, {
		"door_id": _offer_id(),
		"destination": entry_destination(),
	})


func _connect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.subscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _disconnect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.unsubscribe(EVENT_ACTIVATED, _on_interaction_activated)


## Which door, whether it is open -- and WHO worked it. The last of those was
## missing, and it is the same gap `InteriorReveal._announce()` had: an event
## that names its object but not its subject reads correctly for as long as
## there is exactly one character who could have been the subject.
##
## The door only ever toggles for the occupant standing at it, so `occupant()`
## is who did it. Wave 4's bear and wave 5's threats come through the same
## doorway, and a listener -- an audio director picking a sound, a threat
## noticing it has been heard -- cannot tell whose door this was without it.
func _announce(event: StringName) -> void:
	var bus = _event_bus()
	if bus == null:
		return
	bus.emit_event(event, {"door": self, "occupant": occupant(), "open": _open})


func _event_bus():
	if _bus != null:
		return _bus
	if is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	return _bus
