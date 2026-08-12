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


# --- what the prop is, not only where it was --------------------------------
#
# A perch used to be a pair of world vectors, and a world vector is a photograph
# of a moment. `src/rendering/wind_sway.gd` moves the spans up to 0.14 m every
# frame, so the moment expires immediately. Each perch now also carries the
# declaration that owns it and the place ON it, which is what a bird has to hold
# on to.


func test_a_perch_carries_the_declaration_that_offered_it() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_perches.points = [Vector3(0.6, 8.0, 0.0)]
	var perch: Dictionary = _perches.perches()[0]
	assert_true(perch.has("anchor"), "a perch does not say what declared it, so nothing can follow it")
	assert_eq(perch["anchor"], _perches, "a perch named something other than its own declaration as its anchor")
	assert_eq(perch["local"], Vector3(0.6, 8.0, 0.0), "a POINTS perch's local place is the point that was declared")


## The whole contract in one line: resolving the local place through the
## declaration's CURRENT transform must land exactly where the perch was offered.
## True for both kinds and at every point along a span.
func test_every_perch_resolves_back_to_itself_through_its_anchor() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_prop.scale = Vector3(1.0, 1.0, 14.0)
	_prop.position = Vector3(3.0, 7.0, -2.0)
	_prop.rotate_y(deg_to_rad(37.0))
	var placed := _perches.placement()
	var found := _perches.perches()
	assert_true(found.size() >= 4, "expected several perches on a 14 m wire, got %d" % found.size())
	for perch in found:
		var again: Vector3 = placed * (perch["local"] as Vector3)
		assert_almost_eq(
			again.distance_to(perch["at"] as Vector3), 0.0, 0.0001,
			"a perch resolved from its own local place landed %.4f m from where it was offered" % \
				again.distance_to(perch["at"] as Vector3)
		)


## And the point of all of it: move the prop, resolve the SAME stored local
## place, and the perch has moved with it. This is the wire in a gust.
func test_the_stored_place_follows_a_prop_that_moved() -> void:
	_perches.kind = PerchPoints.Kind.SPAN
	_perches.spacing_m = 2.0
	_prop.scale = Vector3(1.0, 1.0, 8.0)
	var perch: Dictionary = _perches.perches()[0]
	var local: Vector3 = perch["local"]
	_prop.position += Vector3(0.132, 0.042, 0.021)
	var moved: Vector3 = _perches.placement() * local
	assert_almost_eq(
		moved.distance_to(_perches.perches()[0]["at"] as Vector3), 0.0, 0.0001,
		"the stored place did not follow the prop"
	)
	assert_almost_eq(
		moved.distance_to(perch["at"] as Vector3), 0.1404, 0.001,
		"the prop moved 0.1404 m and the perch moved %.4f m" % moved.distance_to(perch["at"] as Vector3)
	)


## `placement()` is the public name of the by-hand parent walk that
## `global_transform` cannot do outside a tree. It is public because a bird holds
## on to a declaration and has to ask it where it is now.
func test_placement_composes_the_parent_chain_outside_a_tree() -> void:
	_perches.kind = PerchPoints.Kind.POINTS
	_prop.position = Vector3(5.0, 1.0, -3.0)
	_perches.position = Vector3(0.0, 2.0, 0.0)
	assert_eq(
		_perches.placement().origin, Vector3(5.0, 3.0, -3.0),
		"placement() outside a tree returned %s rather than the composed chain" % _perches.placement().origin
	)


# --- the group ----------------------------------------------------------------


func test_gathering_without_a_tree_is_empty_rather_than_an_error() -> void:
	assert_eq(PerchScript.gather(null).size(), 0, "gathering from nothing must be empty, not a crash")


# --- an eave, or a limb -------------------------------------------------------
#
# RUN is the third kind, and it exists because a SPAN cannot describe an eave.
# A span reads its length out of its own basis, because `Farmstead._string_wires()`
# writes `scale.z = length` onto a one-metre wire and that number does not exist
# until two other nodes have settled onto procedural snow. An eave is the
# opposite: a fixed edge of a model, both ends known in the model's own metres,
# nothing scaling it. Declaring one as a span would mean stretching an invisible
# node to the length of a roof and keeping the two in step by hand.


func test_a_run_divides_the_line_between_its_two_ends() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(-3.8, 3.03, 3.85)
	_perches.run_to = Vector3(0.2, 3.03, 3.85)
	_perches.spacing_m = 1.2
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	var found := _perches.perches()
	assert_eq(found.size(), 4, "a 4 m eave at 1.2 m spacing offered %d places" % found.size())
	# Distances rather than equality: the fractions are floats and the ends come
	# out of a lerp, so an exact compare fails on a value that prints identically.
	assert_almost_eq(
		(found[0]["at"] as Vector3).distance_to(Vector3(-3.8, 3.03, 3.85)), 0.0, 0.0001,
		"the first perch is at %s rather than the run's start" % str(found[0]["at"])
	)
	assert_almost_eq(
		(found[found.size() - 1]["at"] as Vector3).distance_to(Vector3(0.2, 3.03, 3.85)), 0.0, 0.0001,
		"the last perch is at %s rather than the run's end" % str(found[found.size() - 1]["at"])
	)


## The fractions keep birds off the corners of a roof, the way they keep them off
## the insulators on a wire.
func test_the_fractions_keep_the_birds_off_the_ends_of_a_run() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 3.0, 0.0)
	_perches.run_to = Vector3(10.0, 3.0, 0.0)
	_perches.spacing_m = 2.0
	_perches.from_fraction = 0.15
	_perches.to_fraction = 0.85
	for perch in _perches.perches():
		var at: Vector3 = perch["at"]
		assert_true(at.x >= 1.5 - 0.0001 and at.x <= 8.5 + 0.0001, "a perch landed at x = %.3f, outside the fractions" % at.x)


## The whole point of declaring it on the prop. The farmhouse in
## `scenes/main.tscn` stands at (13, 0, -12); an eave written in world metres
## would be a row of birds beside the house the day anybody nudges it.
func test_a_run_moves_and_turns_with_the_prop_that_declares_it() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 3.0, 1.0)
	_perches.run_to = Vector3(4.0, 3.0, 1.0)
	_perches.spacing_m = 4.0
	# The fractions default to 0.12..0.88 -- a bird does not sit on the corner of
	# a roof any more than it sits on an insulator -- and this test is about the
	# transform rather than about them, so it asks for the whole run.
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	_prop.position = Vector3(13.0, 0.0, -12.0)
	_prop.rotate_y(PI * 0.5)
	var found := _perches.perches()
	assert_eq(found.size(), 2, "expected the two ends, got %d" % found.size())
	var first: Vector3 = found[0]["at"]
	# A quarter turn about +Y sends local +x to -z and local +z to +x.
	assert_almost_eq(first.x, 14.0, 0.0001, "the run's start did not turn with the prop")
	assert_almost_eq(first.y, 3.0, 0.0001, "a yaw moved the run vertically")
	assert_almost_eq(first.z, -12.0, 0.0001, "the run's start did not turn with the prop")


## Spacing is in WORLD metres and the perch is in the prop's own. Those are the
## same number only while nothing is scaled, and a tree that is placed at 1.4x
## should carry more birds along the same declared limb rather than the same
## number spread further apart.
func test_a_scaled_prop_carries_more_birds_on_the_same_declared_run() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 4.0, 0.0)
	_perches.run_to = Vector3(2.0, 4.0, 0.0)
	_perches.spacing_m = 1.0
	_perches.from_fraction = 0.0
	_perches.to_fraction = 1.0
	var plain := _perches.perches().size()
	_prop.scale = Vector3(3.0, 1.0, 1.0)
	var stretched := _perches.perches().size()
	assert_eq(plain, 3, "a 2 m run at 1 m spacing offered %d places" % plain)
	assert_true(stretched > plain, "a 6 m run offered %d places against the 2 m run's %d" % [stretched, plain])


## A bird on an eave faces along it, which is what a row of pigeons on a roof
## edge does and is the only heading that does not look arbitrary.
func test_a_bird_on_a_run_faces_along_it() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 3.0, 0.0)
	_perches.run_to = Vector3(0.0, 3.0, 5.0)
	_perches.spacing_m = 5.0
	var facing: Vector3 = _perches.perches()[0]["facing"]
	assert_almost_eq(facing.z, 1.0, 0.0001, "a bird on a run along +z faces %s" % str(facing))
	assert_almost_eq(facing.y, 0.0, 0.0001, "the heading kept a climb in it")


## A sloping limb still stands its birds upright, the same way a sloping wire
## does.
func test_a_bird_on_a_sloping_run_gets_a_flat_heading() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 3.0, 0.0)
	_perches.run_to = Vector3(0.0, 6.0, 4.0)
	_perches.spacing_m = 5.0
	var facing: Vector3 = _perches.perches()[0]["facing"]
	assert_almost_eq(facing.y, 0.0, 0.0001, "a bird on a sloping limb points its beak up the hill")


## `facing` overrides the run's own direction, for a ledge birds sit on looking
## outward rather than a line they sit along.
func test_a_declared_facing_beats_the_runs_own_direction() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 3.0, 0.0)
	_perches.run_to = Vector3(4.0, 3.0, 0.0)
	_perches.spacing_m = 4.0
	_perches.facing = Vector3(0.0, 0.0, -1.0)
	var facing: Vector3 = _perches.perches()[0]["facing"]
	assert_almost_eq(facing.z, -1.0, 0.0001, "the declared facing was ignored: %s" % str(facing))


## A declaration nobody filled in must offer nothing rather than a pile of birds
## at the prop's origin.
func test_a_run_with_no_length_offers_nothing() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.spacing_m = 1.0
	assert_eq(_perches.perches().size(), 0, "an unset run offered somewhere to sit")


## The ceiling applies to a run as it does to a span: a limb twenty metres up is
## a bird nobody will ever see, and it would still take one of the flock's places
## away from a perch that is in shot.
func test_the_ceiling_drops_a_run_that_climbs_out_of_shot() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(0.0, 4.0, 0.0)
	_perches.run_to = Vector3(0.0, 20.0, 6.0)
	_perches.spacing_m = 4.0
	_perches.ceiling_m = 12.0
	for perch in _perches.perches():
		assert_true((perch["at"] as Vector3).y <= 12.0, "a perch survived at %.2f m" % (perch["at"] as Vector3).y)


## And the grip: the stored `local` resolves back to the same world point through
## the declaration on any later frame, which is what lets a bird ride a prop the
## wind is moving.
func test_every_run_perch_resolves_back_to_itself() -> void:
	_perches.kind = PerchPoints.Kind.RUN
	_perches.run_from = Vector3(-1.0, 3.0, 2.0)
	_perches.run_to = Vector3(3.0, 3.2, 2.0)
	_perches.spacing_m = 1.0
	_prop.position = Vector3(13.0, 0.0, -12.0)
	_prop.rotate_y(0.41)
	var found := _perches.perches()
	assert_true(found.size() > 1, "the run offered %d places, so this checks almost nothing" % found.size())
	for perch in found:
		var resolved: Vector3 = _perches.placement() * (perch["local"] as Vector3)
		assert_almost_eq(
			resolved.distance_to(perch["at"] as Vector3), 0.0, 0.0001,
			"the stored place resolves to %s rather than %s" % [str(resolved), str(perch["at"])]
		)
