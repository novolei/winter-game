class_name PerchPoints
extends Node3D

## Somewhere a bird can sit, declared by the thing it sits on.
##
## ---------------------------------------------------------------------------
## WHY THE PROP DECLARES THIS AND THE FLOCK DOES NOT
## ---------------------------------------------------------------------------
## The obvious way to put crows on the wires is a list of world positions in the
## flock. It is also the way that rots: the pole is settled onto procedural snow
## at `_ready()` (see src/entities/farmstead.gd), the wires are *stretched
## between whatever the pole and the house actually settled at*, and none of
## those numbers exists until the game is running. A written-down perch would be
## a bird hanging in the air a hand's breadth off the wire, on a hill nobody
## sampled.
##
## So a perch is declared where it is fixed -- in the prop's own space -- and
## resolved through whatever transform the prop ended up with. Move the pole, the
## perches move with it. Duplicate the pole, the perches duplicate with it,
## because they are its children. Add a third wire and it carries its own.
##
## Membership is a GROUP rather than a registry call, the same shape
## `src/entities/fires.gd` uses: joining is one line in `_ready()`, anything that
## wants perches asks the tree, and a prop that is freed takes its perches with
## it without anybody having to remember to unregister.
##
## ---------------------------------------------------------------------------
## TWO KINDS, BECAUSE A POLE AND A WIRE ARE NOT THE SAME PROBLEM
## ---------------------------------------------------------------------------
## POINTS -- a crossarm. Somewhere between two and five places, each chosen to
## miss the insulators, written in the prop's own metres.
##
## SPAN -- a wire. `power_wire.glb` is one metre of wire along its own -Z which
## `Farmstead._string_wires()` scales to the length of the span, so a child of it
## is scaled too: this node's own basis carries the span's direction AND its
## length, and a perch every `spacing_m` is arithmetic on that. Nothing here has
## to be told how long the wire is, which is the whole reason it works -- the
## wire's length is decided at `_ready()` by two other nodes' settled positions.
##
## The bird also has to face somewhere. On a wire it faces along the wire, which
## is what a bird on a wire does and is also the only heading that does not look
## arbitrary; on a crossarm it faces whatever `facing` names, which for a pole is
## across the arm rather than along it.
##
## ---------------------------------------------------------------------------
## A PERCH IS NOT A POSITION -- IT IS A PLACE ON A PROP
## ---------------------------------------------------------------------------
## `perches()` used to answer with two world vectors, and a world vector is a
## photograph of a moment. That was true for exactly as long as the props stood
## still. `src/rendering/wind_sway.gd` now writes `global_position` on every span
## once a frame, up to 0.14 m across the wind plus a bob -- so a bird placed from
## that photograph stands in the air the wire used to occupy, and at the tight
## framing stop it is a 26-pixel bird a hand's breadth off a two-pixel line.
##
## So every perch also carries `anchor` -- the declaration that offered it -- and
## `local`, the place ON that declaration in its own basis. `anchor.placement() *
## local` is the perch on any frame you like, which is the whole fix:
##
##     at == placement() * local          for every perch, on every frame
##
## `local_facing` is the same trick for the heading. It costs one Vector3 per
## perch and it turns a photograph into a grip.
##
## Note what this does NOT do: it does not make the crow a child of the wire.
## `Farmstead._span()` writes `scale.z = length` onto the span, so a child would
## inherit a 34x stretch along the wire, and `Node3D` has no way to refuse a
## parent's scale short of `top_level`, which refuses the whole transform and
## puts us back where we started.

const GROUP := &"perches"

enum Kind {
	POINTS,
	SPAN,
}

@export var kind: Kind = Kind.POINTS

## Local, in the parent prop's own metres. Used when `kind` is POINTS.
@export var points: Array[Vector3] = []

## Which way a bird sitting on one of `points` looks, in the prop's own space.
## Zero means "along the prop's own -Z", which is the convention every model in
## this project is built to.
@export var facing := Vector3.ZERO

## SPAN only. How far apart along the span, in world metres, and how much of each
## end to leave alone -- a bird does not sit on the insulator.
@export var spacing_m := 2.4
@export var from_fraction := 0.12
@export var to_fraction := 0.88

## SPAN only. Perches above this are dropped. The service drop climbs off the top
## of the frame toward a pole that is not in the scene, and a crow twenty metres
## up is a crow nobody will ever see -- but it would still take one of the flock's
## places away from a wire that is in shot.
@export var ceiling_m := 12.0

## Off, and the prop stops offering anywhere to sit without being deleted. The
## switch a lighting or capture pass flips.
@export var enabled := true


func _ready() -> void:
	add_to_group(GROUP)


## Every perch this prop offers, as `{at, facing, anchor, local, local_facing}`.
##
## `at` and `facing` are world space **this instant**; `anchor`, `local` and
## `local_facing` are the same perch expressed so it can be resolved again on any
## later frame. See the header for why both halves are needed.
##
## Pure with respect to the tree -- it reads transforms and allocates nothing
## that has to be freed -- so a test can assert the geometry of a run of wire
## without a frame having been drawn.
func perches() -> Array:
	if not enabled:
		return []
	var placed := placement()
	if kind == Kind.SPAN:
		return _span_perches(placed)
	var found: Array = []
	var aim := facing if facing.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	for point in points:
		found.append({
			"at": placed * point,
			"facing": _flatten(placed.basis * aim),
			"anchor": self,
			"local": point,
			"local_facing": aim,
		})
	return found


## Where this node is, whether or not it is in a tree.
##
## `global_transform` fails an engine assertion outside the tree and answers with
## the IDENTITY, so an unguarded read does not error -- it silently reports every
## perch at the world origin, which is a flock of crows sitting in the snow at
## (0, 0, 0). A declaration under test is never in a tree. Same discipline as
## `Crow._where()` and `Stove._origin_of()`; composed up the chain by hand,
## because out of a tree there is nobody to compose it for you.
##
## Public because a perched bird holds on to its declaration and asks it, every
## frame the wind moves it, where the wire has got to.
func placement() -> Transform3D:
	if is_inside_tree():
		return global_transform
	var placed := transform
	var above := get_parent()
	while above is Node3D:
		placed = (above as Node3D).transform * placed
		above = above.get_parent()
	return placed


## The whole span, cut into places to sit.
##
## The scale IS the length: `_string_wires()` writes `wire.scale.z = length`, so
## the basis' Z axis is the span vector and its magnitude is the span in metres.
## Reading it back is how a perch on a 34 m run and a perch on a 4 m one come
## from the same two exported numbers.
func _span_perches(placed: Transform3D) -> Array:
	var along := -placed.basis.z
	var length := along.length()
	if length < 0.001 or spacing_m <= 0.0:
		return []
	var direction := along / length
	var first := minf(from_fraction, to_fraction) * length
	var last := maxf(from_fraction, to_fraction) * length
	var usable := last - first
	if usable <= 0.0:
		return []
	# At least one, and then as many more as fit -- a short drop from the eave to
	# the pole still gets somewhere to sit rather than being skipped for being
	# under one spacing long.
	var count := maxi(1, int(floorf(usable / spacing_m)) + 1)
	var found: Array = []
	for index in range(count):
		var travel := first if count == 1 \
			else first + usable * float(index) / float(count - 1)
		var at := placed.origin + direction * travel
		if at.y > ceiling_m:
			continue
		# The same point in the span's own basis. `placed.basis.z` is -1 * the
		# span vector, so a travel of `t` world metres is `-t / length` of a
		# basis whose Z is `length` long -- and `placed * local` returns `at`
		# exactly, which is what test_every_perch_resolves_back_to_itself
		# asserts rather than trusts.
		found.append({
			"at": at,
			"facing": _flatten(direction),
			"anchor": self,
			"local": Vector3(0.0, 0.0, -travel / length),
			"local_facing": Vector3(0.0, 0.0, -1.0),
		})
	return found


## A heading with the climb taken out of it. A bird on a sloping wire stands
## upright on it; it does not point its beak up the hill.
static func _flatten(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return Vector3(0.0, 0.0, -1.0)
	return flat.normalized()


## Every perch every prop in the tree is offering.
##
## Static and taking the tree, rather than a method on the flock, so the gather
## is the same call in the game and in a test that has built two poles and no
## crows at all.
static func gather(tree: SceneTree) -> Array:
	var found: Array = []
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(GROUP):
		var declaration := node as PerchPoints
		if declaration == null:
			continue
		found.append_array(declaration.perches())
	return found
