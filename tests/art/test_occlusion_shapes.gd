extends TestCase

## What the occlusion ray is cast against, checked on the models as they arrive
## from the importer.
##
## ---------------------------------------------------------------------------
## WHY THIS GATE EXISTS
## ---------------------------------------------------------------------------
## `tests/art/test_world_collision.gd` proves the world is solid in the shape
## you WALK INTO. This proves it is solid in the shape you CANNOT SEE THROUGH,
## and the two are not the same question -- the owner reported the fade firing
## with nothing in the way and holding after he had walked clear, and both came
## from asking the first question and using the answer for the second:
##
##   * A BUILDING'S walk-collision is the band between the knee and the reach,
##     with the doorway cut and the porch and the roof left off. From a camera
##     pitched 45 degrees the roof is the thing that hides the player.
##   * A TREE'S is a VERTICAL cylinder measured at the foot. The trunks lean.
##     On the models below the drawn trunk has walked half a metre off that axis
##     by the height the ray is aimed at -- further than the trunk is wide -- so
##     the invisible trunk and the visible one do not overlap where it matters.
##
## Both failures are silent: the collision is correct, the picture is correct,
## and only the fade is wrong. So the checks below are about AGREEMENT between
## the proxy and the drawn geometry, not about presence.

const FaderScript := preload("res://src/rendering/occluder_fader.gd")

const TREES := [
	"res://assets/models/vegetation/tree_bare_a.glb",
	"res://assets/models/vegetation/tree_bare_b.glb",
	"res://assets/models/vegetation/tree_bare_c.glb",
	"res://assets/models/vegetation/tree_bare_d.glb",
	"res://assets/models/vegetation/tree_bare_e.glb",
]

const BUILDINGS := [
	"res://assets/models/buildings/farmhouse/farmhouse.glb",
	"res://assets/models/buildings/tool_shed/tool_shed.glb",
	"res://assets/models/buildings/well_house/well_house.glb",
]

const BOXED := [
	"res://assets/models/props/pickup_truck.glb",
	"res://assets/models/props/flatbed_truck.glb",
	"res://assets/models/props/fence_segment.glb",
]

const HOLLOW := [
	"res://assets/models/props/power_wire.glb",
	"res://assets/models/props/tire_swing.glb",
]

## Where the ray is aimed on a 1.88 m character, and the height the lean is
## judged at. It is not an arbitrary probe: it is the only height that matters.
const CHEST := 1.47


## Instantiates, so it frees the tree before returning (briefing section 2.2).
## Shapes and vertex arrays outlive it -- a Shape3D is a Resource.
func _model(path: String):
	var scene = load(path)
	if not (scene is PackedScene):
		return null
	return (scene as PackedScene).instantiate()


func _proxy(path: String) -> Array:
	var root = _model(path)
	if root == null:
		return []
	var shapes := FaderScript.proxy_shapes(root)
	root.free()
	return shapes


func _drawn(path: String) -> PackedVector3Array:
	var root = _model(path)
	if root == null:
		return PackedVector3Array()
	var faces := FaderScript.drawn_faces(root)
	root.free()
	return faces


func _bounds(shapes: Array) -> AABB:
	var whole := AABB()
	var started := false
	for entry in shapes:
		var local := FaderScript._shape_bounds(entry["shape"] as Shape3D)
		if local.size == Vector3.ZERO:
			continue
		var placed: AABB = (entry["transform"] as Transform3D) * local
		whole = whole.merge(placed) if started else placed
		started = true
	return whole


func _drawn_bounds(faces: PackedVector3Array) -> AABB:
	if faces.is_empty():
		return AABB()
	var whole := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		whole = whole.expand(vertex)
	return whole


# --- the shape nobody wants ---------------------------------------------------

## The failure everybody predicts for a bare tree, and the one this project does
## NOT have -- recorded as a gate so it stays that way. A convex hull of a bare
## crown is a solid eight-metre cone of empty sky, and a ray through the gap
## between two twigs would register a hit.
func test_nothing_occludes_with_a_convex_hull() -> void:
	for path in TREES + BUILDINGS + BOXED:
		for entry in _proxy(path):
			assert_false(
				(entry["shape"] as Shape3D) is ConvexPolygonShape3D,
				"%s occludes with a convex hull, which around a bare crown or a "
				% path + "porch is a solid volume of the air beside it"
			)


# --- buildings ----------------------------------------------------------------

## The one that fixes the farmhouse. Its walk-collision stops at 5.14 m in world
## terms while the roof is drawn to 8.99 m, so a ray against the collision goes
## clean over the top of a house the player is plainly standing behind.
func test_a_building_occludes_all_the_way_up_to_its_own_roof() -> void:
	for path in BUILDINGS:
		var shapes := _proxy(path)
		assert_true(shapes.size() > 0, "%s has no occlusion proxy at all" % path)
		var drawn := _drawn_bounds(_drawn(path))
		var proxy := _bounds(shapes)
		assert_true(
			proxy.end.y >= drawn.end.y - 0.05,
			"%s occludes to %.2f m and is drawn to %.2f m; the missing part is the roof, which is what hides him"
				% [path, proxy.end.y, drawn.end.y]
		)
		assert_true(
			proxy.size.x >= drawn.size.x - 0.05 and proxy.size.z >= drawn.size.z - 0.05,
			"%s occludes over %.2f x %.2f m and is drawn over %.2f x %.2f; the missing part is the eaves and the porch"
				% [path, proxy.size.x, proxy.size.z, drawn.size.x, drawn.size.z]
		)


## And it must be a soup rather than one box round the whole building. A box
## would put the whole footprint's worth of sky in front of the camera.
func test_a_building_occludes_with_its_geometry_and_not_with_a_box() -> void:
	for path in BUILDINGS:
		var shapes := _proxy(path)
		assert_eq(shapes.size(), 1, "%s should occlude as one soup" % path)
		if shapes.size() != 1:
			continue
		var shape: Shape3D = shapes[0]["shape"]
		assert_true(shape is ConcavePolygonShape3D, "%s occludes with a %s" % [path, shape.get_class()])
		if shape is ConcavePolygonShape3D:
			var count := (shape as ConcavePolygonShape3D).get_faces().size() / 3
			assert_true(count > 50, "%s occludes with only %d triangles" % [path, count])


# --- trees --------------------------------------------------------------------

## THE FALSE-TRIGGER GATE. For each tree, find where the drawn trunk actually is
## at the height the ray is aimed, and require the proxy to be there too.
##
## Against the shipped rule -- one vertical cylinder on the model's foot -- this
## fails on three of the five trees by between 0.2 and 0.6 m, which is more than
## a trunk is wide. That is the fade firing beside the tree and holding when the
## player is clear of it, and it is the whole of the owner's first two
## complaints.
func test_a_trees_proxy_is_where_the_trunk_is_drawn_at_chest_height() -> void:
	for path in TREES:
		var faces := _drawn(path)
		var cylinder := _first_cylinder(path)
		if cylinder == null:
			assert_true(false, "%s carries no trunk cylinder to build a proxy from" % path)
			continue
		var radius: float = cylinder.radius
		var path_up := FaderScript.trunk_path(faces, Vector3.ZERO, radius, cylinder.height)
		var drawn_at = _at_height(path_up, CHEST)
		var proxy_at = _proxy_centre_at(_proxy(path), CHEST)
		if drawn_at == null or proxy_at == null:
			assert_true(false, "%s: no trunk found at %.2f m" % [path, CHEST])
			continue
		var off: float = (drawn_at as Vector2).distance_to(proxy_at)
		assert_true(
			off <= radius,
			"%s: at %.2f m the proxy is %.2f m from the drawn trunk, which is %.2f m across. It is aimed at empty air beside the tree."
				% [path, CHEST, off, radius * 2.0]
		)


## The other half: a tree still occludes with a TRUNK and not with its crown. A
## bare crown is thin branches around a lot of air and hides nobody, so this is
## as much a gate as the lean is.
func test_a_tree_still_occludes_with_a_trunk_and_not_with_its_crown() -> void:
	for path in TREES:
		var drawn := _drawn_bounds(_drawn(path))
		var proxy := _bounds(_proxy(path))
		var widest := maxf(proxy.size.x, proxy.size.z)
		assert_true(
			widest < maxf(drawn.size.x, drawn.size.z) * 0.5,
			"%s occludes over %.2f m against a crown of %.2f m; the crown is air"
				% [path, widest, maxf(drawn.size.x, drawn.size.z)]
		)


func _first_cylinder(path: String) -> CylinderShape3D:
	var root = _model(path)
	if root == null:
		return null
	var found: CylinderShape3D = null
	for entry in FaderScript.colliders_of(root):
		if (entry["shape"] as Shape3D) is CylinderShape3D:
			found = entry["shape"]
			break
	root.free()
	return found


func _at_height(path_up: PackedVector3Array, height: float):
	for step in range(path_up.size() - 1):
		var from: Vector3 = path_up[step]
		var to: Vector3 = path_up[step + 1]
		if height < from.y or height > to.y or is_equal_approx(from.y, to.y):
			continue
		var along := (height - from.y) / (to.y - from.y)
		var at: Vector3 = from + (to - from) * along
		return Vector2(at.x, at.z)
	return null


## Where the proxy's own material sits at that height, read off the shapes it
## actually ships rather than off the walk that built them -- so a proxy that
## ignored the walk is caught.
func _proxy_centre_at(shapes: Array, height: float):
	var low := Vector2.INF
	var high := -Vector2.INF
	var found := false
	for entry in shapes:
		var placed: Transform3D = entry["transform"]
		var local := FaderScript._shape_bounds(entry["shape"] as Shape3D)
		var box: AABB = placed * local
		if height < box.position.y or height > box.end.y:
			continue
		var centre := box.get_center()
		low = low.min(Vector2(centre.x, centre.z))
		high = high.max(Vector2(centre.x, centre.z))
		found = true
	return (low + high) * 0.5 if found else null


# --- the rest -----------------------------------------------------------------

## A vehicle and a fence panel keep the box the import gave them, and the reason
## is the opposite of the building's: their box already IS their drawn bounds,
## and the geometry inside it is full of holes -- over the bed, under the cab,
## between two pickets -- that a single ray threads on some frames and not
## others. The box's generosity is what buys a fade that does not chatter.
func test_a_vehicle_and_a_fence_panel_occlude_with_their_box() -> void:
	for path in BOXED:
		var shapes := _proxy(path)
		assert_true(shapes.size() > 0, "%s has no occlusion proxy" % path)
		for entry in shapes:
			assert_true(
				(entry["shape"] as Shape3D) is BoxShape3D,
				"%s occludes with a %s rather than the box it was given"
					% [path, (entry["shape"] as Shape3D).get_class()]
			)
		var drawn := _drawn_bounds(_drawn(path))
		var proxy := _bounds(shapes)
		assert_almost_eq(proxy.size.y, drawn.size.y, 0.05,
			"%s's box is not the height of the thing it stands for" % path)


## Nothing solid in it, so it cannot be in anybody's way. Seven centimetres of
## steel strung thirty metres across the frame hides nobody, and a swing hangs
## off a tree that is already an occluder.
func test_the_wires_and_the_swing_occlude_with_nothing() -> void:
	for path in HOLLOW:
		assert_eq(_proxy(path).size(), 0, "%s produced an occlusion proxy" % path)
