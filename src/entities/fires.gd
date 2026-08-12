class_name Fires
extends RefCounted

## THE THINGS THAT ARE BURNING, and the questions every one of them answers.
##
## Never instantiated -- all of it is static. This file is the group's own
## definition: the name, the contract its members keep, and the four queries
## that are the whole reason for having it.
##
## ---------------------------------------------------------------------------
## WHY THERE IS A GROUP AT ALL
## ---------------------------------------------------------------------------
## "Is there a fire near me?" is asked by four different things, and until this
## existed none of them could ask it.
##
##   * the snow he is carrying melts near a fire (`src/entities/snow_load.gd`)
##   * wave 4's beacon IS one, and lighting the chain is the game's spine
##   * wave 5's threats approach light and heat, or avoid it
##   * the survival model warms a body at one
##
## `Stove` states everything about ITSELF perfectly well -- `is_lit()`,
## `warmth_at()`. What no fire stated was that it EXISTS. With no group and no
## key, a system asking the question can only walk the entire scene tree asking
## every node whether it happens to answer to the right pair of methods, which
## is what snow_load.gd does today and what its own header asks for instead.
##
## ---------------------------------------------------------------------------
## AND WHY IT IS NOT A ServiceRegistry KEY
## ---------------------------------------------------------------------------
## The registry holds ONE instance per key -- `&"player"`, `&"snow_field"` --
## and this is a collection whose membership changes while the game runs. Two
## fires in a room, a beacon lit on day 5, a campfire that burns out: none of
## that is expressible as a key, and faking it with `&"fire_1"`, `&"fire_2"`
## would put the lookup back where it started.
##
## ---------------------------------------------------------------------------
## 1. MEMBERSHIP TRACKS THE STATE, NOT THE OBJECT
## ---------------------------------------------------------------------------
## A cold stove is not a fire. A member joins when it is ALIGHT and leaves when
## it goes out, so `get_nodes_in_group(&"fires")` hands back things that are
## actually burning and a caller never filters.
##
## That is the difference between a group whose meaning is enforceable and one
## that is merely conventional. Let a cold stove sit in the group and the group
## means "stove-shaped node"; every caller then grows the same `if
## fire.is_lit()` line, one of them forgets it, and the bug is a man warming
## himself at a stove with no fire in it -- which looks like tuning.
##
## ---------------------------------------------------------------------------
## 2. THE CONTRACT -- and it is here rather than in a report
## ---------------------------------------------------------------------------
## A group whose members answer different questions is worse than no group: the
## caller has to `has_method` each one, which is the tree walk again with extra
## steps. So every member answers exactly these, and `join()` refuses anything
## that cannot:
##
##   fire_position() -> Vector3   WHERE IT IS, in world space, and answerable
##                                outside the tree -- `global_position` fails an
##                                engine assertion there and returns the ORIGIN,
##                                so an unguarded read does not merely print an
##                                error, it silently says the fire is at (0,0,0).
##                                It must be the same point `warmth_at()`
##                                measures from, or a caller's distance test and
##                                the warmth it then asks for disagree.
##
##   warmth_at(point) -> float    HOW MUCH OF IT REACHES `point`, 0 .. 1. A
##                                distance alone cannot tell a hearth from a
##                                candle, and every consumer of this group cares
##                                about the difference.
##
##   is_lit() -> bool             THE INVARIANT, not a filter. It is always true
##                                for a member; it is in the contract so that
##                                the property above is checkable rather than
##                                merely asserted, and a caller that finds it
##                                false has found a bug in the member.
##
## ADDING A QUESTION IS A REAL COST -- every member has to grow it -- so the
## list is the minimum that answers "is there a fire near me, and is it worth
## walking to". Light colour, radius and fuel are deliberately absent: they are
## properties of a particular kind of fire, and the group is not the place to
## learn what kind.
##
## ---------------------------------------------------------------------------
## WHERE THIS LIVES
## ---------------------------------------------------------------------------
## Beside the entities that join it, and not hung off `Stove`: the stove is the
## first member, not the owner. Wave 4's beacon has no fuel economy, no firebox
## and no recipes, and it must be able to satisfy this contract without
## inheriting a stove.

const GROUP := &"fires"

## The questions above, as data, so a test can assert that today's members
## answer today's contract and fail the day one of them stops.
const CONTRACT: Array[StringName] = [&"fire_position", &"warmth_at", &"is_lit"]


# --- membership --------------------------------------------------------------

## Can this thing be a fire? Quiet, and a predicate: a test has to be able to ask
## without the console going dirty, which is the same split
## `InteriorReveal.unresolved()` makes against its `_ready()` alarm.
static func answers(node: Object) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for question in CONTRACT:
		if not node.has_method(question):
			return false
	return true


## Alight. Idempotent, so a fire that is already burning may say so again.
##
## THE LOUD ONE. A node that cannot answer the contract is refused rather than
## admitted, and it shouts, because the alternative is a fire that silently never
## joins -- and in the game nobody is looking. Returns whether it is in the group
## when this call is done.
static func join(node: Node) -> bool:
	if not answers(node):
		push_error(
			"fires: %s cannot answer %s, so it may not join the fires group. " % [node, CONTRACT]
			+ "Every member has to answer all of them or a caller reaching into "
			+ "the group crashes on whichever one is missing."
		)
		return false
	if not node.is_in_group(GROUP):
		node.add_to_group(GROUP)
	return true


## Out. Idempotent, and safe on something that was never in.
##
## Nodes are dropped from their groups when they are freed and
## `get_nodes_in_group` only ever returns nodes that are in a tree, so this is
## about the FIRE going out rather than about tidying up after one.
static func leave(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.is_in_group(GROUP):
		node.remove_from_group(GROUP)


# --- the queries -------------------------------------------------------------

## Every fire burning in the scene `from` is standing in.
##
## Empty when `from` is not in a tree, which is the case every unit test is in:
## `get_tree()` there is an engine ERROR, and by this project's standard a stray
## ERROR is a failed run whatever the assertions said. An empty answer is also
## the honest one -- a node with no tree above it can see no scene.
static func all(from: Node) -> Array[Node]:
	var found: Array[Node] = []
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return found
	found.assign(from.get_tree().get_nodes_in_group(GROUP))
	return found


## The fires within `radius` of `point` -- the question the snow load asks every
## footfall and the one a threat's approach behaviour will ask.
static func near(from: Node, point: Vector3, radius: float) -> Array[Node]:
	var found: Array[Node] = []
	for fire in all(from):
		if position_of(fire).distance_to(point) <= radius:
			found.append(fire)
	return found


## The closest fire to `point`, or null when nothing is burning.
static func nearest(from: Node, point: Vector3) -> Node:
	var best: Node = null
	var best_distance := INF
	for fire in all(from):
		var distance := position_of(fire).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = fire
	return best


## How much fire reaches `point`, 0 .. 1.
##
## THE WARMEST, NOT THE SUM. Two fires do not make a place twice as warm; the
## reading saturates and a third one must not push it past what the scale means.
##
## This is the "how much fire is here" reading -- what melts a crust, what a
## threat weighs up. It is NOT the survival maths: a body being warmed takes one
## modifier per fire, each under its own source id, which is what stops the
## second fire taking the first one's warmth back off. See `Stove.apply_recovery`.
static func warmth_at(from: Node, point: Vector3) -> float:
	var most := 0.0
	for fire in all(from):
		var reach = fire.call(&"warmth_at", point)
		if reach is float or reach is int:
			most = maxf(most, float(reach))
	return most


## Where a fire is, asked of the fire. Vector3.ZERO for anything that answers
## with something else -- a member is contract-checked when it joins, so this is
## the last line of defence rather than the expected path.
static func position_of(fire: Node) -> Vector3:
	if fire == null or not is_instance_valid(fire) or not fire.has_method(&"fire_position"):
		return Vector3.ZERO
	var spot = fire.call(&"fire_position")
	return spot if spot is Vector3 else Vector3.ZERO
