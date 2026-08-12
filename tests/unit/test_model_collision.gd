extends TestCase

## The geometry behind the world's collision, exercised without an importer.
##
## tools/model_collision.gd runs inside `_post_import`, which only the editor's
## import pass ever calls. Everything it decides is therefore written as pure
## functions over a triangle soup so that it can be tested here, from a headless
## run, against shapes whose right answer is arithmetic rather than a judgement
## about a screenshot.
##
## The three that carry the weight:
##
##   standing_faces  drops what cannot stop a walker -- floor slabs, porch
##                   decks, roofs. This is what keeps a 0.42 m foundation slab
##                   from becoming an invisible kerb around every building.
##   subtract_box    punches the doorway. The farmhouse's front wall has NO
##                   hole in it -- tools/blender/build_farmhouse.py draws the
##                   door as a flat panel on a solid wall -- so a collision mesh
##                   taken straight off the geometry seals the only way in.
##   trunk_of        finds the trunk under a crown. A bare tree is mostly empty
##                   space and its convex hull is an eight-metre invisible blob.

const CollisionScript := preload("res://tools/model_collision.gd")


## A triangle soup for an axis-aligned box, as Mesh.get_faces() would hand it
## over: three vertices per triangle, twelve triangles, no indices.
func _box_faces(box: AABB) -> PackedVector3Array:
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var faces := mesh.get_faces()
	var moved := PackedVector3Array()
	var centre := box.position + box.size * 0.5
	for vertex in faces:
		moved.append(vertex + centre)
	return moved


func _area(faces: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(0, faces.size(), 3):
		total += (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length() * 0.5
	return total


func _centroid(faces: PackedVector3Array, index: int) -> Vector3:
	return (faces[index] + faces[index + 1] + faces[index + 2]) / 3.0


func _bounds(faces: PackedVector3Array) -> AABB:
	if faces.is_empty():
		return AABB()
	var box := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		box = box.expand(vertex)
	return box


# --- the rule table ----------------------------------------------------------

## Every name is declared, and an undeclared one is not quietly given a default.
## A model that arrives with a name nothing matches gets NO collision, and
## tests/art/test_world_collision.gd fails on it by name -- which is the loud
## version of the same fact.
func test_an_unknown_mesh_name_matches_no_rule() -> void:
	assert_true(
		CollisionScript.rule_for("Something_Nobody_Declared").is_empty(),
		"an undeclared mesh must match no rule, so the art gate can name it"
	)


func test_the_tree_rule_is_a_trunk_and_the_truck_rule_is_a_box() -> void:
	assert_eq(CollisionScript.rule_for("Tree_Bare_A").get("kind", &""), CollisionScript.TRUNK)
	assert_eq(CollisionScript.rule_for("Pickup_Truck").get("kind", &""), CollisionScript.BOX)
	assert_eq(CollisionScript.rule_for("FH_Shell").get("kind", &""), CollisionScript.WALLS)
	assert_eq(CollisionScript.rule_for("Power_Wire").get("kind", &""), CollisionScript.NONE)


## Godot's importer appends a suffix to a duplicated node name, so the table is
## prefix-matched. A rule that only matched the whole string would go silently
## missing the day a second copy of a mesh landed in one file.
func test_a_suffixed_name_still_matches_its_rule() -> void:
	assert_eq(CollisionScript.rule_for("Tree_Bare_A_002").get("kind", &""), CollisionScript.TRUNK)


# --- standing_faces ----------------------------------------------------------

## A porch deck, a floor slab and a roof cannot stop a walker whose feet are
## placed by the height field, and every one of them becomes an invisible kerb
## or ceiling if it is left in.
func test_a_slab_below_the_knee_is_dropped_whole() -> void:
	var slab := _box_faces(AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 0.42, 6.0)))
	assert_eq(
		CollisionScript.standing_faces(slab, 0.45, 3.2).size(), 0,
		"a slab whose highest point is under the knee must leave nothing behind"
	)


func test_a_roof_above_the_reach_is_dropped_whole() -> void:
	var roof := _box_faces(AABB(Vector3(-3.0, 4.0, -3.0), Vector3(6.0, 1.0, 6.0)))
	assert_eq(CollisionScript.standing_faces(roof, 0.45, 3.2).size(), 0)


## The case that matters most: a wall that starts below the knee and runs past
## the reach must survive at its full height, not be trimmed to the band.
## Trimming it would leave a gap under and over every wall in the game -- and
## the gap under is exactly where a walker's feet are.
func test_a_wall_that_spans_the_band_survives_at_full_height() -> void:
	var wall := _box_faces(AABB(Vector3(-3.0, 0.3, -0.08), Vector3(6.0, 4.7, 0.16)))
	var kept := CollisionScript.standing_faces(wall, 0.45, 3.2)
	assert_true(kept.size() > 0, "the wall was removed entirely")
	var bounds := _bounds(kept)
	assert_almost_eq(bounds.position.x, -3.0, 0.001)
	assert_almost_eq(bounds.end.x, 3.0, 0.001)
	assert_true(bounds.position.y <= 0.45, "the wall no longer reaches down past the knee")
	assert_true(bounds.end.y >= 3.2, "the wall no longer reaches up past head height")


# --- subtract_box ------------------------------------------------------------

func test_a_box_that_touches_nothing_leaves_the_soup_alone() -> void:
	var wall := _box_faces(AABB(Vector3(-3.0, 0.3, -0.08), Vector3(6.0, 2.7, 0.16)))
	var after := CollisionScript.subtract_box(wall, AABB(Vector3(20.0, 0.0, 20.0), Vector3(1.0, 2.0, 1.0)))
	assert_eq(after.size(), wall.size(), "a distant opening must not touch the geometry")
	assert_almost_eq(_area(after), _area(wall), 0.0001)


## The doorway itself. A wall with a rectangle taken out of it must have no
## surface left inside that rectangle, and must still be a wall either side.
func test_an_opening_leaves_a_hole_and_keeps_the_wall_around_it() -> void:
	var wall := _box_faces(AABB(Vector3(-3.0, 0.0, -0.08), Vector3(6.0, 3.0, 0.16)))
	var door := AABB(Vector3(1.3, -1.0, -0.3), Vector3(1.0, 3.55, 0.6))
	var after := CollisionScript.subtract_box(wall, door)

	assert_true(after.size() > 0, "subtracting a doorway must not delete the whole wall")
	assert_true(after.size() % 3 == 0, "a triangle soup must stay a multiple of three vertices")

	var inside := 0
	for index in range(0, after.size(), 3):
		if door.grow(-0.001).has_point(_centroid(after, index)):
			inside += 1
	assert_eq(inside, 0, "%d triangle(s) are still inside the doorway" % inside)

	var left := false
	var right := false
	for index in range(0, after.size(), 3):
		var centre := _centroid(after, index)
		left = left or centre.x < door.position.x
		right = right or centre.x > door.end.x
	assert_true(left, "the wall to the left of the doorway was removed with it")
	assert_true(right, "the wall to the right of the doorway was removed with it")
	assert_true(_area(after) < _area(wall), "the doorway removed no surface at all")


## Clipping must not leave zero-area slivers behind: a degenerate triangle in a
## ConcavePolygonShape3D is a face with no normal, and the physics server's
## behaviour on one is not something to find out in play.
func test_the_clip_leaves_no_degenerate_triangles() -> void:
	var wall := _box_faces(AABB(Vector3(-3.0, 0.0, -0.08), Vector3(6.0, 3.0, 0.16)))
	var after := CollisionScript.subtract_box(wall, AABB(Vector3(1.3, -1.0, -0.3), Vector3(1.0, 3.55, 0.6)))
	var degenerate := 0
	for index in range(0, after.size(), 3):
		var area := (after[index + 1] - after[index]).cross(after[index + 2] - after[index]).length() * 0.5
		if area < 0.000001:
			degenerate += 1
	assert_eq(degenerate, 0, "%d degenerate triangle(s) survived the clip" % degenerate)


## A box that swallows the whole wall leaves nothing, rather than leaving the
## wall untouched -- the failure mode a "keep what I could not clip" fallback
## would have.
func test_an_opening_that_covers_everything_removes_everything() -> void:
	var wall := _box_faces(AABB(Vector3(-1.0, 0.0, -0.08), Vector3(2.0, 2.0, 0.16)))
	assert_eq(CollisionScript.subtract_box(wall, AABB(Vector3(-9.0, -9.0, -9.0), Vector3(18.0, 18.0, 18.0))).size(), 0)


# --- trunk_of ----------------------------------------------------------------

## A bare tree is mostly air. The base band is the trunk and nothing else, so
## the radius comes off the base band rather than off the model's width.
func test_the_trunk_is_measured_at_the_base_and_not_across_the_crown() -> void:
	var faces := _box_faces(AABB(Vector3(-0.15, -0.2, -0.15), Vector3(0.3, 4.0, 0.3)))
	# A branch four metres out, well above the base band.
	faces.append_array(_box_faces(AABB(Vector3(-4.0, 3.0, -0.05), Vector3(4.0, 0.1, 0.1))))
	var trunk: Dictionary = CollisionScript.trunk_of(faces, 0.15)
	assert_almost_eq(trunk["base"], -0.2, 0.0001)
	assert_true(
		trunk["radius"] < 0.30,
		"the trunk radius is %.3f; the crown reaches 4 m and must not be in it" % trunk["radius"]
	)
	assert_true(trunk["radius"] > 0.15, "the trunk radius is %.3f, narrower than the trunk" % trunk["radius"])
	assert_almost_eq((trunk["centre"] as Vector2).length(), 0.0, 0.01)


func test_a_leaning_trunk_is_centred_on_its_own_base() -> void:
	var faces := _box_faces(AABB(Vector3(1.9, 0.0, -3.1), Vector3(0.2, 3.0, 0.2)))
	var trunk: Dictionary = CollisionScript.trunk_of(faces, 0.15)
	assert_almost_eq((trunk["centre"] as Vector2).x, 2.0, 0.01)
	assert_almost_eq((trunk["centre"] as Vector2).y, -3.0, 0.01)


# --- shapes_for --------------------------------------------------------------

func test_a_vehicle_becomes_one_box_the_size_of_the_model() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 1.8, 5.0)
	var built: Array = CollisionScript.shapes_for("Pickup_Truck", mesh)
	assert_eq(built.size(), 1, "a vehicle is one box")
	if built.is_empty():
		return
	var shape = built[0]["shape"]
	assert_true(shape is BoxShape3D, "a vehicle must collide as a BoxShape3D, got %s" % shape)
	if shape is BoxShape3D:
		assert_almost_eq((shape as BoxShape3D).size.x, 2.0, 0.01)
		assert_almost_eq((shape as BoxShape3D).size.z, 5.0, 0.01)


func test_a_tree_becomes_one_cylinder_far_narrower_than_the_model() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.2
	mesh.height = 6.0
	var built: Array = CollisionScript.shapes_for("Tree_Bare_A", mesh)
	assert_eq(built.size(), 1)
	if built.is_empty():
		return
	assert_true(built[0]["shape"] is CylinderShape3D, "a tree must collide as a cylinder on the trunk")


func test_a_wire_gets_nothing_at_all() -> void:
	var mesh := BoxMesh.new()
	assert_eq(CollisionScript.shapes_for("Power_Wire", mesh).size(), 0)
	assert_eq(CollisionScript.shapes_for("Tire_Swing", mesh).size(), 0)


func test_an_undeclared_mesh_gets_nothing_at_all() -> void:
	var mesh := BoxMesh.new()
	assert_eq(CollisionScript.shapes_for("Nobody_Declared_This", mesh).size(), 0)


# --- attach ------------------------------------------------------------------

## What `_post_import` actually calls. The owner assignment is the part that is
## easy to leave out and impossible to see: PackedScene.pack() saves only nodes
## whose owner chain reaches the root, so a collider without one is built at
## import, discarded on save, and the world is exactly as hollow as before.
func test_attach_builds_one_static_body_and_owns_every_node_it_adds() -> void:
	var root := Node3D.new()
	root.name = "prop"
	var instance := MeshInstance3D.new()
	instance.name = "Pickup_Truck"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 1.8, 5.0)
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root

	var added: int = CollisionScript.attach(root)
	assert_eq(added, 1, "one mesh with a box rule must yield one collider")

	var body := root.get_node_or_null("Collision")
	assert_not_null(body, "attach() must add a StaticBody3D called Collision")
	if body != null:
		assert_true(body is StaticBody3D)
		assert_eq(body.owner, root, "the body is not owned by the root, so it is dropped when the scene is packed")
		assert_true(body.get_child_count() > 0, "the body carries no shape")
		for child in body.get_children():
			assert_true(child is CollisionShape3D)
			assert_eq(child.owner, root, "%s is not owned by the root and will not be saved" % child.name)
	root.free()


func test_attach_adds_nothing_to_a_model_that_declares_no_collision() -> void:
	var root := Node3D.new()
	root.name = "wire"
	var instance := MeshInstance3D.new()
	instance.name = "Power_Wire"
	instance.mesh = BoxMesh.new()
	root.add_child(instance)
	instance.owner = root
	assert_eq(CollisionScript.attach(root), 0)
	assert_true(root.get_node_or_null("Collision") == null, "a wire must not carry a physics body")
	root.free()
