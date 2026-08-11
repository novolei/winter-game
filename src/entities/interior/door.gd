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

## For a door that should just swing as you walk up to it. Off by default: the
## design says `E`.
@export var opens_on_approach := false

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


func _ready() -> void:
	_register_action()
	resolve()
	_complain()
	apply_swing(0.0)
	if not body_entered.is_connected(on_body_entered):
		body_entered.connect(on_body_entered)
	if not body_exited.is_connected(on_body_exited):
		body_exited.connect(on_body_exited)


func _register_action() -> void:
	if InputMap.has_action(interact_action):
		return
	InputMap.add_action(interact_action)
	for key in [KEY_E]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(interact_action, event)


func set_event_bus(bus) -> void:
	_bus = bus


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
		return
	_open = wanted
	_announce(EVENT_OPENED if wanted else EVENT_CLOSED)
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


func on_body_exited(body: Node) -> void:
	if not accepts(body):
		return
	_near = false


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


## Polled rather than handled in _unhandled_input, to match PlayerController,
## which reads its four movement actions with Input.get_vector. It also has a
## practical edge: Input.action_press() -- which is how tools/capture_interior.gd
## drives a run, and how a test would -- sets action state without synthesising
## an InputEvent, so an _unhandled_input door could not be opened by anything
## except a human at a keyboard.
func _process(_delta: float) -> void:
	if _near and Input.is_action_just_pressed(interact_action):
		toggle()


func _announce(event: StringName) -> void:
	var bus = _event_bus()
	if bus == null:
		return
	bus.emit_event(event, {"door": self, "open": _open})


func _event_bus():
	if _bus != null:
		return _bus
	if is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	return _bus
