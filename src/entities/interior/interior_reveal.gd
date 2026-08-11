class_name InteriorReveal
extends Area3D

## The moment the roof comes off.
##
##     "The house interior. It's not a different location, it's the same one.
##      So the player sees the danger outside the house. The moment I step
##      inside, the roof and the front wall come off. That's it."
##
## No loading screen, no second scene, no camera move. The same world, with
## some of its geometry no longer drawn -- so the snow, the tracks and whatever
## is walking across them stay on screen while the player stands at the stove.
## That continuity is the whole point: it is what keeps outside dangerous while
## you are inside.
##
## ---------------------------------------------------------------------------
## THE TECHNIQUE, AND WHY IT IS NOT CLEVERER THAN THIS
## ---------------------------------------------------------------------------
## System Map section 4.4, in full: cross an Area3D threshold, tween a FIXED
## EXPORTED LIST of parts over 0.30 s, switch the audio at the same moment.
## **No ray, no occlusion culling, no camera-relative test.**
##
## Every one of those is a thing somebody will reach for, and every one of them
## trades a property this has for one it does not need:
##
##   * a raycast from the camera has to run every frame, and its answer changes
##     with where the player happens to stand, so the same doorway reads
##     differently on two visits;
##   * occlusion culling removes what is hidden, which is not the same set as
##     what is IN THE WAY -- the far wall is hidden and must stay, the near
##     wall is visible and must go;
##   * a camera-relative test would have to be re-derived the day the camera
##     changes, and this camera is fixed by design (CameraRig).
##
## An authored list is a decision made once, by a person, looking at the actual
## frame. It costs one property write per part per frame of the fade and
## nothing at all the rest of the time.
##
## ---------------------------------------------------------------------------
## IT IS A COMPONENT, NOT A FARMHOUSE FEATURE
## ---------------------------------------------------------------------------
## Wave 4 adds the fuel station, the church, the logging camp and the pylon,
## and every one of them needs this. So nothing here knows what a farmhouse is.
## A building carries a reveal the way it carries a mesh: drop this Area3D
## under it, give it a shape covering the interior, and list the parts to fade.
## Adding the reveal to a new building is scene setup, not new code -- briefing
## constraint 4, content is data.
##
## ---------------------------------------------------------------------------
## TWO THINGS MEASURED ON 4.7.1 RATHER THAN ASSUMED
## ---------------------------------------------------------------------------
## 1. GeometryInstance3D.transparency DOES fade a mesh that CelPainter has
##    re-materialled onto assets/shaders/cel_flat.gdshader, even though that
##    shader declares no ALPHA and no blend mode. Sampled through the frame:
##    solid #445670 -> half #5b708f -> gone #6e87aa, and at 1.0 the frame is
##    indistinguishable from visible = false (3.1% of pixels differing against
##    a 2.3% temporal-noise floor). No material change, so no art gate moves.
##
## 2. A FADED PART STILL CASTS ITS SHADOW. Same measurement: turning cast_shadow
##    off changed 7.8% of the room's pixels mid-fade and 4.1% at full fade,
##    against that same 2.3% floor. A roof you cannot see, throwing a shadow you
##    can, puts the revealed room in the dark -- which would make the whole
##    feature pointless. So the shadow moves with the fade, and it moves at the
##    FIRST frame of it rather than the last: mid-fade is where an unshadowed
##    roof is drawn faintest and shadows hardest.
##
## ---------------------------------------------------------------------------
## AUDIO
## ---------------------------------------------------------------------------
## Section 4.4 also says the audio switches to interior filtering and reverb at
## this moment, through AudioDirector. **AudioDirector does not exist yet** --
## it is task 11 and it has not been built; src/audio/ holds only the music
## stack. So this publishes the crossing on the EventBus, at the exact frame,
## naming the building, and the director subscribes when it lands. That seam is
## tested; the filtering behind it is not, because there is nothing behind it.

const EVENT_ENTERED := &"interior.entered"
const EVENT_EXITED := &"interior.exited"

## The parts to fade, by name, resolved under `building_path`. THE AUTHORED
## LIST -- this is the whole configuration surface of the feature. For the
## farmhouse it is every part standing between a camera pitched 45 degrees and
## yawed -35 and the room behind it; for the next building it will be a
## different list, and that is a scene edit.
@export var fade_parts: Array[StringName] = []

## Where to look for them. Empty means the node this reveal hangs under, which
## is the case that wants no configuration at all: an InteriorReveal parented to
## the building it belongs to.
@export var building_path: NodePath = ^""

## System Map section 4.4. Both directions, and a reversal partway through runs
## at the same rate rather than for the same time -- see fade_duration_to().
@export var fade_seconds := 0.30

## Used only when the scene authored no CollisionShape3D of its own. A real
## interior is rarely one box -- the farmhouse is two, one per room -- so the
## shapes are normally authored; this is the one-room default so that dropping
## the node in and typing a list is enough to see something happen.
@export var threshold_size := Vector3(4.0, 2.4, 4.0)

## Who counts as being inside. Resolved through the ServiceRegistry autoload,
## the same way CameraRig and Stove find the player, so that a threat walking
## past the door or an item dropped in it does not take the roof off.
@export var occupant_service: StringName = &"player"

## Optional. A node with `is_open() -> bool` -- in practice a Door -- that has
## to be open before crossing the threshold reveals anything.
##
## THIS IS WHAT MAKES ENTRY BE THROUGH THE DOOR. Nothing in this world has a
## collision body yet, so the player can walk through a wall; with a gate set,
## doing that gets them a room with its roof still on, and the only way to open
## the house is to open the door. When walls become solid (another agent's
## task) the rule is unchanged -- it just stops being the only thing enforcing
## it.
##
## It gates ENTERING and nothing else. Shutting the door behind you must not
## put the roof back on, so once revealed the gate is not consulted again until
## the player has left.
@export var entry_gate_path: NodePath = ^""

var _fade := 0.0
var _revealed := false
var _inside := false
var _resolved := false
var _parts: Array[GeometryInstance3D] = []
var _shadow_before: Array[int] = []
var _missing := PackedStringArray()
var _tween: Tween = null
var _bus = null
var _registry = null
var _occupant: Node = null


# --- wiring -----------------------------------------------------------------

func _ready() -> void:
	_ensure_threshold()
	resolve()
	for name in _missing:
		push_error(
			"interior_reveal: no GeometryInstance3D called %s under %s. The reveal "
			% [name, _building_name()]
			+ "addresses the building by these names, and a missing one leaves a "
			+ "wall in front of a camera that cannot move, with nothing reporting it."
		)
	apply_fade(0.0)
	if not body_entered.is_connected(on_body_entered):
		body_entered.connect(on_body_entered)
	if not body_exited.is_connected(on_body_exited):
		body_exited.connect(on_body_exited)


## A threshold with no shape is a threshold nothing can cross, and it fails in
## total silence. Build the default rather than leave it inert.
func _ensure_threshold() -> void:
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			return
	var shape := BoxShape3D.new()
	shape.size = threshold_size
	var collider := CollisionShape3D.new()
	collider.name = "Threshold"
	collider.shape = shape
	add_child(collider)


func set_event_bus(bus) -> void:
	_bus = bus


func set_occupant(node: Node) -> void:
	_occupant = node


# --- the list ---------------------------------------------------------------

## Turn the authored names into nodes. Idempotent, and safe to call before the
## reveal is in a tree: find_child walks the parent chain directly.
##
## `owned = false` matters and is not a detail. The farmhouse's meshes belong to
## farmhouse.glb's own scene, not to main.tscn, so an owned search finds none of
## them -- the same call and the same reason as in src/entities/farmhouse.gd.
func resolve() -> void:
	_parts.clear()
	_shadow_before.clear()
	_missing = PackedStringArray()
	_resolved = true
	var building := building_node()
	for name in fade_parts:
		var found: GeometryInstance3D = null
		if building != null:
			found = building.find_child(String(name), true, false) as GeometryInstance3D
		if found == null:
			_missing.append(String(name))
			continue
		_parts.append(found)
		# Remembered rather than assumed: a part authored not to cast must not
		# start casting the first time the player walks out of the house.
		_shadow_before.append(found.cast_shadow)


func parts() -> Array[GeometryInstance3D]:
	return _parts


## The names that matched nothing. A caller can see this; _ready() also shouts
## about it, because in the game nobody is looking.
func unresolved() -> PackedStringArray:
	return _missing


func building_node() -> Node:
	if not building_path.is_empty():
		var named := get_node_or_null(building_path)
		if named != null:
			return named
	return get_parent()


# --- the fade ---------------------------------------------------------------

func fade() -> float:
	return _fade


func is_revealed() -> bool:
	return _revealed


## The one place that writes to the building. Public because it is also the
## tween's target, and because a test that had to wait 0.30 s of wall clock to
## check an endpoint would be both slow and flaky.
##
## Three writes per part, and the order they are decided in matters:
##
##   transparency  the fade itself
##   cast_shadow   OFF the instant the fade starts, ON again only at 0
##   visible       false only at a full fade, which is the steady state while
##                 the player is indoors -- so the roof costs nothing at all
##                 for the whole of the night, rather than sitting in the
##                 transparent pipeline. Measured indistinguishable from
##                 transparency 1.0, so this changes cost and not the picture.
func apply_fade(value: float) -> void:
	if not is_finite(value):
		return
	_fade = clampf(value, 0.0, 1.0)
	if not _resolved:
		resolve()
	var casting := _fade <= 0.0
	for index in range(_parts.size()):
		var part := _parts[index]
		part.transparency = _fade
		part.cast_shadow = (
			_shadow_before[index]
			if casting
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		part.visible = _fade < 1.0


## How long a move to `target` takes from where the fade is now.
##
## `fade_seconds` is the time for a whole 0 -> 1, so a reversal caught halfway
## takes half of it. The alternative -- always 0.30 s -- makes a player who
## steps in and straight back out watch the roof crawl, because it would be
## covering half the distance in the same time.
func fade_duration_to(target: float) -> float:
	return fade_seconds * absf(clampf(target, 0.0, 1.0) - _fade)


func reveal() -> void:
	set_revealed(true)


func conceal() -> void:
	set_revealed(false)


## Crossing, in either direction. Idempotent: a threshold built from two boxes
## reports entering twice, and a doorway is exactly the place a player dithers.
func set_revealed(inside: bool) -> void:
	if inside == _revealed:
		return
	_revealed = inside
	# Announced BEFORE the fade starts, not after it finishes. The audio switch
	# is meant to land on the same frame as the first frame of the fade -- a
	# room that sounds like outside for 0.30 s after the roof lifts is the
	# tell that these are two systems rather than one moment.
	_announce(EVENT_ENTERED if inside else EVENT_EXITED)
	_start_fade(1.0 if inside else 0.0)


func _start_fade(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	var duration := fade_duration_to(target)
	# Outside a tree there is no SceneTree to run a Tween on, which is the case
	# every unit test is in. Snapping there keeps the endpoints assertable with
	# no wall clock; fade_duration_to() is what covers the timing rule.
	if not is_inside_tree() or duration <= 0.0:
		apply_fade(target)
		return
	_tween = create_tween()
	_tween.tween_method(apply_fade, _fade, target, duration)


# --- the threshold ----------------------------------------------------------

## Public, and named without a leading underscore, because the Area3D signals
## are not the only caller: a test drives these directly, and so does the
## capture harness.
func on_body_entered(body: Node) -> void:
	if accepts(body):
		_inside = true
		reconsider()


func on_body_exited(body: Node) -> void:
	if accepts(body):
		_inside = false
		reconsider()


func is_occupant_inside() -> bool:
	return _inside


## Leaving always conceals. Entering reveals only once the gate is open -- and
## once it has, the gate is done: see entry_gate_path on why shutting the door
## behind you must not undo it.
func reconsider() -> void:
	if not _inside:
		set_revealed(false)
		return
	if _revealed or entry_is_open():
		set_revealed(true)


func entry_gate() -> Node:
	if entry_gate_path.is_empty():
		return null
	return get_node_or_null(entry_gate_path)


func entry_is_open() -> bool:
	var gate := entry_gate()
	if gate == null:
		return true
	return bool(gate.call(&"is_open"))


## Polled, so that opening the door while already standing in the doorway works.
## Area3D reports crossing once; "the gate opened while I was inside it" is not
## a crossing and would otherwise need the player to step out and back in.
func _process(_delta: float) -> void:
	if _inside and not _revealed:
		reconsider()


## Fails closed. With no occupant resolvable, nothing crosses -- a reveal that
## defaulted to "anything counts" would come apart the day the world gets a
## second physics body in it.
func accepts(body: Node) -> bool:
	var who := occupant()
	return who != null and body == who


func occupant() -> Node:
	if _occupant != null and is_instance_valid(_occupant):
		return _occupant
	if not is_inside_tree():
		return null
	if _registry == null:
		# get_node_or_null, NOT Engine.get_singleton: a project [autoload] is a
		# node under /root and never enters the engine's singleton registry
		# (briefing trap 3).
		_registry = get_node_or_null("/root/ServiceRegistry")
		if _registry == null:
			return null
	_occupant = _registry.get_service(occupant_service) as Node
	return _occupant


# --- announcing -------------------------------------------------------------

func _announce(event: StringName) -> void:
	var bus = _event_bus()
	if bus == null:
		return
	bus.emit_event(event, {
		"building": _building_name(),
		"reveal": self,
		"fade_seconds": fade_seconds,
	})


func _event_bus():
	if _bus != null:
		return _bus
	if is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	return _bus


func _building_name() -> String:
	var building := building_node()
	return String(building.name) if building != null else ""
