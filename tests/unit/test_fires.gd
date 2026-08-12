extends TestCase

## THE THINGS THAT ARE BURNING.
##
## Four systems ask the same question -- the snow he is carrying melts near one,
## wave 4's beacon is one, wave 5's threats approach the light and heat of one,
## and the survival model warms a body at one. Before the group existed the only
## way to answer it was to walk the whole scene tree asking every node whether it
## happened to answer to `is_lit()` and `warmth_at()`, which is what
## `src/entities/snow_load.gd` does today and what its own header asks for
## instead.
##
## Two properties are what make this worth having over a bare convention, and
## both of them are what these tests are for:
##
##   1. MEMBERSHIP TRACKS THE STATE. A cold stove is not a fire. The group holds
##      things that are actually alight, so a caller never filters.
##   2. EVERY MEMBER ANSWERS THE SAME QUESTIONS. A group whose members answer
##      different questions is worse than no group: the caller ends up
##      `has_method`-ing each one, which is the tree walk again with extra steps.
##
## The subjects below are deliberately NOT stoves for most of it. A `Bonfire`
## built here, answering three methods and nothing else, is the wave 4 beacon
## standing in early -- and the fact that these tests pass with a subject that
## has never heard of fuel, palettes or survival stats is the whole claim that
## the contract is a contract rather than a description of the stove.

const StoveScript := preload("res://src/entities/stove/stove.gd")


## Everything a fire has to be. Nothing else -- no fuel, no light, no economy.
class Bonfire extends Node3D:
	var lit := true
	var reach := 3.0

	func is_lit() -> bool:
		return lit

	## Guarded, because a subject a test builds with .new() is not in a tree and
	## `global_position` fails an engine assertion there and answers with the
	## origin. Out of a tree the local position IS the world position.
	func fire_position() -> Vector3:
		return global_position if is_inside_tree() else position

	func warmth_at(point: Vector3) -> float:
		return 1.0 - clampf(fire_position().distance_to(point) / reach, 0.0, 1.0)


## Answers two of the three. A node like this is exactly what a group with no
## stated contract fills up with: it looks like a fire from one angle and breaks
## the first caller that asks it the other question.
class HalfAFire extends Node3D:
	func is_lit() -> bool:
		return true

	func fire_position() -> Vector3:
		return position


var _nodes: Array[Node] = []


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2), and anything put
	# under /root has to come back out before it is freed.
	for node in _nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_nodes.clear()


# --- helpers ----------------------------------------------------------------

func _bonfire(at := Vector3.ZERO, reach := 3.0) -> Bonfire:
	var fire := Bonfire.new()
	fire.position = at
	fire.reach = reach
	_nodes.append(fire)
	return fire


## A bonfire standing in the live scene tree and in the group, which is what
## every query below needs: `get_nodes_in_group` only ever returns nodes that
## are in a tree.
func _lit_in_the_world(at := Vector3.ZERO, reach := 3.0) -> Bonfire:
	var fire := _bonfire(at, reach)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(fire)
	Fires.join(fire)
	return fire


# --- the name and the contract ----------------------------------------------

## Written out rather than read back off the constant: a test that reads the
## value out of the thing it is checking asserts only that the constant equals
## itself. Same reason the palette tests hardcode their hexes.
func test_the_group_is_called_fires() -> void:
	assert_eq(Fires.GROUP, &"fires", "the group's name is what every caller types")


## The contract is the point of the file. If a question is dropped from it, the
## callers that ask that question break; if one is added, every member has to
## grow it. Either way somebody should have to change this line on purpose.
func test_the_contract_is_where_it_is_how_warm_it_is_and_that_it_is_alight() -> void:
	var questions := Array(Fires.CONTRACT)
	assert_eq(questions.size(), 3, "the contract is three questions; got %s" % [questions])
	assert_true(questions.has(&"fire_position"), "a caller cannot do a distance test without a position")
	assert_true(questions.has(&"warmth_at"), "a caller cannot tell a hearth from a candle without warmth")
	assert_true(questions.has(&"is_lit"), "the invariant the group is keeping has to be askable")


## Today's only real member, checked against today's contract. This is the line
## that fails the day somebody adds a question and forgets the stove.
func test_the_stove_answers_every_question_in_the_contract() -> void:
	var stove = StoveScript.new()
	_nodes.append(stove)
	for question in Fires.CONTRACT:
		assert_true(
			stove.has_method(question),
			"the stove cannot answer %s, so it cannot be a member of its own group" % question
		)


func test_a_thing_that_answers_all_three_is_a_fire() -> void:
	assert_true(Fires.answers(_bonfire()), "a node answering the whole contract was refused")


## The refusal is quiet HERE -- `answers()` is a predicate and a test has to be
## able to ask it without the console going dirty. `join()` is the loud one, and
## it is loud on the game path where nobody is looking.
func test_a_thing_that_answers_two_of_three_is_not_a_fire() -> void:
	var half := HalfAFire.new()
	_nodes.append(half)
	assert_false(
		Fires.answers(half),
		"a node that says it is lit and where it is, but cannot say how warm it "
		+ "is, was admitted -- and the first caller to ask it would crash"
	)


func test_a_node_that_answers_nothing_is_not_a_fire() -> void:
	var bare := Node3D.new()
	_nodes.append(bare)
	assert_false(Fires.answers(bare), "an ordinary Node3D was admitted to the group")
	assert_false(Fires.answers(null), "null was admitted to the group")


# --- membership tracks the state --------------------------------------------

func test_joining_puts_a_fire_in_the_group_and_leaving_takes_it_out() -> void:
	var fire := _bonfire()
	assert_true(Fires.join(fire), "a conforming fire was refused")
	assert_true(fire.is_in_group(Fires.GROUP), "join() did not put it in the group")
	assert_true(Fires.join(fire), "joining twice must be idempotent, not an error")
	Fires.leave(fire)
	assert_false(fire.is_in_group(Fires.GROUP), "leave() did not take it out")
	Fires.leave(fire)
	assert_false(fire.is_in_group(Fires.GROUP), "leaving twice must be idempotent")


## THE PROPERTY THE WHOLE DESIGN RESTS ON. A caller asks the group for fires and
## gets fires -- not fire-shaped objects it then has to interrogate.
func test_a_fire_that_goes_out_stops_being_found() -> void:
	var here := _lit_in_the_world(Vector3.ZERO)
	var there := _lit_in_the_world(Vector3(10.0, 0.0, 0.0))
	assert_eq(Fires.all(here).size(), 2, "two fires were lit and the group does not hold both")
	there.lit = false
	Fires.leave(there)
	var found := Fires.all(here)
	assert_eq(found.size(), 1, "a fire that went out is still being handed to callers")
	if found.is_empty():
		return
	assert_eq(found[0], here, "the wrong fire was left in the group")
	for fire in found:
		assert_true(
			bool(fire.call(&"is_lit")),
			"the group handed back something that is not burning, which is the "
			+ "filter every caller was supposed to stop writing"
		)


# --- the query surface -------------------------------------------------------

func test_asking_from_outside_the_tree_answers_nothing_rather_than_failing() -> void:
	var loose := _bonfire()
	Fires.join(loose)
	# `get_tree()` on a node that is not in a tree is an engine ERROR, and by
	# this project's standard a stray ERROR is a failed run whatever the
	# assertions said. An empty answer is the honest one: a node with no tree
	# above it can see no scene.
	assert_eq(Fires.all(loose).size(), 0, "a node outside the tree found fires in a scene it is not in")
	assert_eq(Fires.all(null).size(), 0, "asking with no node at all found fires")
	assert_eq(Fires.near(loose, Vector3.ZERO, 100.0).size(), 0, "near() reached into a tree that is not there")
	assert_eq(Fires.nearest(loose, Vector3.ZERO), null, "nearest() answered from outside the tree")
	assert_eq(Fires.warmth_at(loose, Vector3.ZERO), 0.0, "warmth_at() answered from outside the tree")


## The question the snow load asks every frame, and the one wave 5's threats
## will ask: is there a fire within so many metres of this point.
func test_near_finds_the_fires_within_reach_and_no_others() -> void:
	var close := _lit_in_the_world(Vector3(1.0, 0.0, 0.0))
	_lit_in_the_world(Vector3(40.0, 0.0, 0.0))
	var found := Fires.near(close, Vector3.ZERO, 4.0)
	assert_eq(found.size(), 1, "expected one fire within four metres; got %d" % found.size())
	if found.is_empty():
		return
	assert_eq(found[0], close, "near() returned the far fire")


func test_the_nearest_fire_is_the_nearest_one() -> void:
	var far := _lit_in_the_world(Vector3(40.0, 0.0, 0.0))
	var close := _lit_in_the_world(Vector3(2.0, 0.0, 0.0))
	assert_eq(Fires.nearest(far, Vector3.ZERO), close, "nearest() picked the further fire")
	assert_eq(Fires.nearest(far, Vector3(41.0, 0.0, 0.0)), far, "nearest() ignores the point it was asked about")


## THE WARMEST, NOT THE SUM. Two fires do not make a place twice as warm -- the
## reading is 0 .. 1 and saturates. What the survival model does with a fire is a
## different thing entirely: each one pushes its own modifier under its own
## source id, which is what stops the second fire taking the first one's warmth
## off the body. This is the "how much fire is here" reading, and it is the one
## a threat's approach behaviour and a melting crust want.
func test_the_warmth_at_a_point_is_the_warmest_fire_rather_than_their_sum() -> void:
	var one := _lit_in_the_world(Vector3.ZERO, 4.0)
	_lit_in_the_world(Vector3(1.0, 0.0, 0.0), 4.0)
	var warmth := Fires.warmth_at(one, Vector3.ZERO)
	assert_almost_eq(
		warmth, 1.0, 0.0001,
		"two fires at one hearth read %f: they were added rather than compared, "
		% warmth
		+ "and a third would put the reading past anything the scale means"
	)
	var away := Fires.warmth_at(one, Vector3(100.0, 0.0, 0.0))
	assert_eq(away, 0.0, "a point out of reach of every fire is not warm")


func test_where_a_fire_is_is_asked_of_the_fire() -> void:
	var fire := _bonfire(Vector3(3.0, 1.0, -5.0))
	assert_eq(
		Fires.position_of(fire), Vector3(3.0, 1.0, -5.0),
		"the group's own position read disagrees with the fire's"
	)
