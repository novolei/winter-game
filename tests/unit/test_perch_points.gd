extends TestCase

## Perches are declared by the prop that carries them, in the prop's own space,
## and resolved through whatever transform the prop ended up with.
##
## The whole reason this is not a list of world positions is that no perch in
## this game has a position until the game is running: `Farmstead` settles the
## pole onto procedural snow and then stretches the wires between whatever the
## pole and the house settled at. So the two things worth testing are that a
## moved prop takes its perches with it, and that a wire divides itself by its
## own length however long that turned out to be.

const PerchScript := preload("res://src/entities/wildlife/perch_points.gd")

var _prop: Node3D
var _perches: PerchPoints


func before_each() -> void:
	_prop = Node3D.new()
	_perches = PerchScript.new()
	_prop.add_child(_perches)


func after_each() -> void:
	# Frees the child with it. Node is not reference-counted (briefing
	# constraint 2).
	_prop.free()


# --- a crossarm ---------------------------------------------------------------


func test_declared_points_come_back_in_the_props_own_place() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_perches.points = [Vector3(-0.6, 8.0, 0.0), Vector3(0.6, 8.0, 0.0)]
	_prop.position = Vector3(10.0, 0.0, -4.0)
	var found := _perches.perches()
	assert_eq(found.size(), 2, "two declared points came back as %d" % found.size())
	assert_eq(found[0]["at"], Vector3(9.4, 8.0, -4.0), "the first perch is not where the prop put it")
	assert_eq(found[1]["at"], Vector3(10.6, 8.0, -4.0), "the second perch is not where the prop put it")


## The pole in scenes/main.tscn is yawed 22 degrees and settled onto the snow;
## a perch written in world coordinates would be beside it rather than on it.
func test_turning_the_prop_turns_its_perches() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_perches.points = [Vector3(1.0, 8.0, 0.0)]
	_prop.rotate_y(PI * 0.5)
	var at: Vector3 = _perches.perches()[0]["at"]
	assert_almost_eq(at.x, 0.0, 0.0001, "a quarter turn left the perch on the x axis")
	assert_almost_eq(at.y, 8.0, 0.0001, "a yaw moved the perch vertically")
	assert_almost_eq(at.z, -1.0, 0.0001, "a quarter turn did not carry the perch round to -z")


func test_a_perch_faces_the_props_own_forward_by_default() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_perches.points = [Vector3.ZERO]
	_prop.rotate_y(PI * 0.5)
	var facing: Vector3 = _perches.perches()[0]["facing"]
	assert_almost_eq(facing.x, -1.0, 0.0001, "a prop turned a quarter turn faces -x, and its birds should too")
	assert_almost_eq(facing.y, 0.0, 0.0001, "a perched bird's heading must be flat")


func test_a_disabled_declaration_offers_nothing() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_perches.points = [Vector3.ZERO, Vector3.ONE]
	_perches.enabled = false
	assert_eq(_perches.perches().size(), 0, "a disabled declaration still offered perches")


# --- a wire -------------------------------------------------------------------


## `power_wire.glb` is one metre along its own -Z and `Farmstead._string_wires()`
## writes `scale.z = length`, so the node's own basis carries the span. Nothing
## in the declaration knows how long the wire is, which is the point.
func test_a_span_divides_itself_by_the_length_the_scene_stretched_it_to() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	_prop.scale = Vector3(1.0, 1.0, 10.0)
	var found := _perches.perches()
	assert_eq(found.size(), 6, "a 10 m span at 2 m spacing should carry six perches, not %d" % found.size())
	assert_almost_eq((found[0]["at"] as Vector3).z, 0.0, 0.0001, "the first perch is not at the near end")
	assert_almost_eq((found[5]["at"] as Vector3).z, -10.0, 0.0001, "the last perch is not at the far end")


func test_the_same_declaration_on_a_longer_wire_carries_more_birds() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	_prop.scale = Vector3(1.0, 1.0, 4.0)
	var short := _perches.perches().size()
	_prop.scale = Vector3(1.0, 1.0, 20.0)
	var long := _perches.perches().size()
	assert_true(
		long > short,
		"a 20 m wire offered %d perches and a 4 m one offered %d -- the span is not being read off the scale" % [long, short]
	)


func test_the_fractions_keep_the_birds_off_the_insulators() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_perches.from_fraction = 0.25
	_perches.to_fraction = 0.75
	_prop.scale = Vector3(1.0, 1.0, 20.0)
	for perch in _perches.perches():
		var along := -(perch["at"] as Vector3).z
		assert_true(
			along >= 5.0 - 0.001 and along <= 15.0 + 0.001,
			"a perch landed %.2f m along a 20 m wire, outside the 25%%..75%% band it was given" % along
		)


## The service drop climbs off the top of the frame toward a pole that is not in
## the scene. A crow twenty metres up is a crow nobody will ever see -- but it
## would still take one of the flock's places.
func test_a_perch_above_the_ceiling_is_not_offered() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 5.0
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	_perches.ceiling_m = 6.0
	# A wire climbing at 45 degrees from ground level.
	_prop.scale = Vector3(1.0, 1.0, 20.0)
	_prop.rotate_x(deg_to_rad(45.0))
	var found := _perches.perches()
	assert_true(found.size() >= 1, "the ceiling threw the whole wire away")
	for perch in found:
		assert_true(
			(perch["at"] as Vector3).y <= _perches.ceiling_m,
			"a perch was offered at %.2f m, above the %.2f m ceiling" % [(perch["at"] as Vector3).y, _perches.ceiling_m]
		)


func test_a_bird_on_a_sloping_wire_does_not_point_its_beak_up_the_hill() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 5.0
	_prop.scale = Vector3(1.0, 1.0, 20.0)
	_prop.rotate_x(deg_to_rad(30.0))
	for perch in _perches.perches():
		assert_almost_eq(
			(perch["facing"] as Vector3).y, 0.0, 0.0001,
			"a perch on a sloping wire handed the bird a climbing heading"
		)


func test_a_span_with_no_length_offers_nothing() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_prop.scale = Vector3(1.0, 1.0, 0.0)
	assert_eq(_perches.perches().size(), 0, "a wire of zero length still offered somewhere to sit")


# --- the group ----------------------------------------------------------------


func test_gathering_without_a_tree_is_empty_rather_than_an_error() -> void:
	assert_eq(PerchScript.gather(null).size(), 0, "gathering from nothing must be empty, not a crash")
