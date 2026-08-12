extends TestCase

## What stands between the camera and the player gets out of the way.
##
## ---------------------------------------------------------------------------
## THIS REPLACES AN INVERTED FIRST ATTEMPT, AND THE INVERSION IS THE POINT
## ---------------------------------------------------------------------------
## The first pass at "the character disappears behind things" drew the CHARACTER
## through the occluder, as a translucent silhouette. The owner looked at it
## running and ruled it backwards: fading the man is the one thing that cannot
## achieve "I can still see my guy". The occluder fades; the character is not
## touched.
##
## Four rules came with that ruling, and each one is a test below:
##
##   1. THE WHOLE OCCLUDER, uniformly. No window cut around the character's
##      screen position -- that is the mosaic disc that was already removed from
##      the farmhouse once. The unit of fading is an object: a building, a tree,
##      a run of fence.
##   2. A LIGHT GREY-BLACK, translucent. The faded object reads as a soft dark
##      silhouette you can see straight through, not as a bleached ghost of its
##      own colour -- so both cel bands go to one flat tint.
##   3. THE TINT IS A RENDERING AFFORDANCE, not an albedo, so it is not bound by
##      the 12-colour table -- the same ruling that already covers sky, fog and
##      ambient. It still may not be warm: rule 12's quota is about pixels on
##      screen and this covers a lot of them.
##   4. THE CHARACTER'S OWN TRANSLUCENCY STAYS. His boots sink below the snow
##      surface and the part under it reads pale blue. That is a separate effect
##      that happens to share a mechanism with the one being removed, and it is
##      wanted -- see tests/unit/test_character_occlusion.gd, which is unchanged.

const FaderScript := preload("res://src/rendering/occluder_fader.gd")
const SETTINGS_PATH := "res://data/rendering/occluder_fade.tres"
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CONTROLLER_SOURCE := "res://src/entities/player/player_controller.gd"


## A stand-in for an instanced prop: `scene_file_path` is what Godot itself uses
## to mark the root of an instanced scene, which is exactly the engine's own
## notion of "one object".
func _prop(name: String, scene: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.scene_file_path = scene
	var mesh := MeshInstance3D.new()
	mesh.name = name + "_Mesh"
	mesh.mesh = BoxMesh.new()
	node.add_child(mesh)
	return node


## The collider tools/model_collision.gd builds at import, which is also what
## this system uses to decide what is in the way.
func _with_collider(prop: Node3D, size: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	prop.add_child(body)
	return prop


# --- what counts as one occluder ---------------------------------------------

func test_each_instanced_prop_is_one_unit() -> void:
	var root := Node3D.new()
	var yard := Node3D.new()
	yard.name = "Farmstead"
	root.add_child(yard)
	yard.add_child(_prop("Truck", "res://truck.glb"))
	yard.add_child(_prop("TreeA", "res://tree_a.glb"))
	yard.add_child(_prop("TreeB", "res://tree_a.glb"))
	var units: Array = FaderScript.units_in(root, null)
	var names := PackedStringArray()
	for unit in units:
		names.append(String((unit as Node3D).name))
	assert_eq(units.size(), 3, "expected one unit per prop, got %s" % ", ".join(names))
	root.free()


## Rule 1, the awkward half. A run of fence is one object even though it is
## twenty-two instances of one panel: fading a single panel out of the middle of
## a run is exactly the patchwork the owner ruled out.
func test_a_row_of_identical_instances_fades_as_one_object() -> void:
	var root := Node3D.new()
	var fence := Node3D.new()
	fence.name = "Fence"
	root.add_child(fence)
	for index in range(4):
		fence.add_child(_prop("Segment%d" % index, "res://fence_segment.glb"))
	var units: Array = FaderScript.units_in(root, null)
	assert_eq(units.size(), 1, "a fence run must be one unit, not %d" % units.size())
	if units.size() == 1:
		assert_eq(String((units[0] as Node3D).name), "Fence")
	root.free()


## And the rule must not swallow a yard that merely happens to hold two of the
## same tree. The row is only a row when EVERY instance under the parent is the
## same scene.
func test_a_yard_holding_two_of_the_same_tree_is_still_separate_trees() -> void:
	var root := Node3D.new()
	var yard := Node3D.new()
	yard.name = "Farmstead"
	root.add_child(yard)
	yard.add_child(_prop("TreeC", "res://tree_c.glb"))
	yard.add_child(_prop("TreeD", "res://tree_c.glb"))
	yard.add_child(_prop("WellHouse", "res://well_house.glb"))
	assert_eq(FaderScript.units_in(root, null).size(), 3)
	root.free()


## The ground is not an occluder. It is what the character stands in, it is what
## his sunken boots read through, and it is a script node rather than an
## instanced scene -- which is what keeps it out.
func test_the_ground_is_never_an_occluder() -> void:
	var root := Node3D.new()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = BoxMesh.new()
	root.add_child(terrain)
	assert_eq(FaderScript.units_in(root, null).size(), 0, "the terrain must never fade")
	root.free()


## Rule 4, at the structural level: the man is not an occluder of himself.
func test_the_character_is_never_faded_by_this_system() -> void:
	var root := Node3D.new()
	var player := Node3D.new()
	player.name = "Player"
	player.add_child(_prop("Body", "res://winter_wanderer.glb"))
	root.add_child(player)
	root.add_child(_prop("TreeA", "res://tree_a.glb"))
	var units: Array = FaderScript.units_in(root, player)
	assert_eq(units.size(), 1, "only the tree may be a unit")
	if units.size() == 1:
		assert_eq(String((units[0] as Node3D).name), "TreeA", "the character's own body was picked up as an occluder")
	root.free()


# --- what shape an occluder is -----------------------------------------------

## The mesh box is the wrong shape and a screenshot proved it: a bare tree's box
## is 5.6 x 9.4 x 6.5 m of mostly air, so a tree standing well clear of the
## player faded anyway because its BOX covered him. The trunk cylinder
## tools/model_collision.gd builds at import is the right shape, and it is
## already on the model.
func test_an_occluder_is_shaped_like_its_collider_not_like_its_mesh() -> void:
	var tree := _with_collider(_prop("TreeA", "res://tree_a.glb"), Vector3(0.6, 3.4, 0.6))
	# The mesh is a 2 m box; the collider is a 0.6 m trunk.
	(tree.get_child(0) as MeshInstance3D).mesh.size = Vector3(6.0, 8.0, 6.0)
	var bounds: Array = FaderScript.solid_bounds(tree)
	assert_eq(bounds.size(), 1, "the tree carries one collider")
	if bounds.size() == 1:
		assert_almost_eq((bounds[0] as AABB).size.x, 0.6, 0.001,
			"the occluder must be the trunk, not the crown")
	tree.free()


# --- what the ray is cast against ---------------------------------------------
#
# THIS REPLACES A SCREEN-RECTANGLE TEST, and the replacement is the whole of the
# owner's first two complaints. The shipped rule projected each collider's
# world-axis-aligned bounding box to a screen-axis-aligned rectangle and
# intersected it with the character's: two inflations stacked on a third. Scored
# against what the models actually draw, over a metre grid, it faded a run of
# fence over nine times the ground it should have (+885%), a truck over four
# times (+350%) and the farmhouse two thirds too much (+68%) -- which is
# "it fades things that are not blocking the player" and "it stays faded after I
# have walked clear" in one mechanism, because a trigger region four times too
# large is one you have to walk four times as far to leave.
#
# The rule now is the owner's: the camera casts a ray at the player and whatever
# blocks it fades. What the ray is cast against is what these tests are about.


func _soup(points: PackedVector3Array) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(points)
	return shape


func _box_mesh(node: Node3D, name: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	node.add_child(mesh)
	return mesh


func _with_shape(prop: Node3D, shape: Shape3D, at := Transform3D.IDENTITY) -> Node3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = at
	body.add_child(collider)
	prop.add_child(body)
	return prop


## The defect this found on the models on disk: a building's collision is the
## band of its walls a walker can hit, with the doorway cut out and the porch
## and THE ROOF left off. From a camera pitched 45 degrees the roof is what
## hides the player -- he is standing inside it in the approved shot -- so a ray
## against the walls alone missed a third of the ground where the house really
## covers him, and missed it in a speckle that would have made the fade chatter.
func test_a_building_occludes_with_what_it_draws_not_with_what_you_walk_into() -> void:
	var house := _prop("Model", "res://farmhouse.glb")
	# Drawn: a wall to 3 m and a roof from 3 m to 6 m.
	_box_mesh(house, "FH_Shell", Vector3(6.0, 3.0, 6.0), Vector3(0.0, 1.5, 0.0))
	_box_mesh(house, "FH_Fade_Roof", Vector3(7.0, 3.0, 7.0), Vector3(0.0, 4.5, 0.0))
	# Walked into: only the wall band, exactly as tools/model_collision.gd builds it.
	_with_shape(house, _soup(PackedVector3Array([
		Vector3(-3.0, 0.45, 3.0), Vector3(3.0, 0.45, 3.0), Vector3(3.0, 3.0, 3.0),
	])))
	var shapes := FaderScript.proxy_shapes(house)
	assert_eq(FaderScript.proxy_kind(FaderScript.colliders_of(house)), FaderScript.PROXY_DRAWN,
		"a building is recognised by its collision being a triangle soup")
	assert_eq(shapes.size(), 1, "a building occludes as one soup of its own geometry")
	if shapes.size() == 1:
		var built: Shape3D = shapes[0]["shape"]
		assert_true(built is ConcavePolygonShape3D, "the drawn proxy has to be a triangle soup")
		var reach := FaderScript._shape_bounds(built).end.y
		assert_true(reach > 5.9,
			"the proxy stops at %.2f m; the roof is drawn to 6 m and the roof is what hides him" % reach)
	house.free()


## And the other half of the same rule: a tree is NOT its drawn geometry. A bare
## crown is thin branches around a lot of air and hides nobody, so the collision
## cylinder's judgement -- only the trunk counts -- is kept.
func test_a_tree_occludes_with_a_trunk_and_not_with_its_crown() -> void:
	var tree := _prop("TreeA", "res://tree_a.glb")
	(tree.get_child(0) as MeshInstance3D).mesh.size = Vector3(6.0, 8.0, 6.0)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.3
	trunk.height = 3.4
	_with_shape(tree, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.7, 0.0)))
	assert_eq(FaderScript.proxy_kind(FaderScript.colliders_of(tree)), FaderScript.PROXY_TRUNK,
		"a cylinder is a model saying 'most of me is air, only this counts'")
	for entry in FaderScript.proxy_shapes(tree):
		var built: Shape3D = entry["shape"]
		var across := maxf(FaderScript._shape_bounds(built).size.x, FaderScript._shape_bounds(built).size.z)
		assert_true(across < 1.0,
			"the tree occludes with something %.2f m across; the crown is 6 m and is air" % across)
	tree.free()


## A box is left alone, and the reason is the opposite of the building's: a
## vehicle's box already IS its drawn bounds, and the geometry inside it is full
## of holes -- over the bed, under the cab, through a wheel well -- that a single
## ray threads on some frames and not others. Measured on pickup_truck.glb at
## 35 cm steps, the drawn silhouette at chest height is speckled; the box is the
## stable answer and its generosity is what buys the stability.
func test_a_vehicle_keeps_the_box_the_import_gave_it() -> void:
	var truck := _prop("Truck", "res://truck.glb")
	var box := BoxShape3D.new()
	box.size = Vector3(1.98, 1.82, 5.0)
	_with_shape(truck, box)
	assert_eq(FaderScript.proxy_kind(FaderScript.colliders_of(truck)), FaderScript.PROXY_KEEP)
	var shapes := FaderScript.proxy_shapes(truck)
	assert_eq(shapes.size(), 1)
	if shapes.size() == 1:
		assert_true(shapes[0]["shape"] == box, "the box is reused, not rebuilt")
	truck.free()


func test_something_with_no_collider_is_never_an_occluder() -> void:
	var wire := _prop("Wire", "res://power_wire.glb")
	assert_eq(FaderScript.solid_bounds(wire).size(), 0)
	assert_eq(FaderScript.proxy_shapes(wire).size(), 0, "a wire cannot be in anybody's way")
	assert_eq(FaderScript.proxy_kind(FaderScript.colliders_of(wire)), FaderScript.PROXY_NONE)
	wire.free()


# --- the trunk leans, and the collision did not ------------------------------
#
# THE ACTUAL CAUSE OF THE FALSE TRIGGERING, measured on the models on disk.
# `62faacf` measured each trunk from the vertices within 15 cm of the model's
# lowest point and built a VERTICAL cylinder there. The trunks lean. On
# tree_bare_d the drawn trunk has walked 0.51 m off that axis by chest height
# against a radius of 0.26, and 3.05 m by 3 m up -- so the invisible trunk and
# the visible one do not overlap at all where the ray is aimed. The fade fired
# beside the tree and held when he was clear of it, offset by the lean.


## A trunk built as two long quads has no vertices at all through its length, so
## the walk has to take the mesh's EDGES against each band's plane. A scan that
## collected vertices near the height would find nothing and fall back to the
## vertical cylinder without saying so.
func _leaning_trunk(lean: float, height: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var steps := 8
	var corners := [Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0.1, 0.1), Vector2(-0.1, 0.1)]
	for step in range(steps):
		var low := height * float(step) / float(steps)
		var high := height * float(step + 1) / float(steps)
		for side in range(4):
			var here: Vector2 = corners[side]
			var next: Vector2 = corners[(side + 1) % 4]
			var a := Vector3(lean * low + here.x, low, here.y)
			var b := Vector3(lean * low + next.x, low, next.y)
			var c := Vector3(lean * high + next.x, high, next.y)
			var d := Vector3(lean * high + here.x, high, here.y)
			faces.append_array([a, b, c, a, c, d])
	return faces


func test_the_trunk_walk_follows_a_leaning_trunk() -> void:
	var path := FaderScript.trunk_path(
		_leaning_trunk(0.35, 3.4), Vector3.ZERO, 0.15, 3.4)
	assert_true(path.size() >= 5, "the walk gave up after %d bands of a 3.4 m trunk" % path.size())
	if path.size() < 2:
		return
	var top: Vector3 = path[path.size() - 1]
	assert_almost_eq(top.x, 0.35 * top.y, 0.12,
		"the walk ended at x %.2f; the drawn trunk is at %.2f at that height" % [top.x, 0.35 * top.y])
	assert_true(top.y > 3.0, "the walk stopped %.2f m up a 3.4 m trunk" % top.y)


func test_the_trunk_walk_leaves_a_straight_trunk_straight() -> void:
	var path := FaderScript.trunk_path(
		_leaning_trunk(0.0, 3.4), Vector3.ZERO, 0.15, 3.4)
	for point in path:
		assert_almost_eq((point as Vector3).x, 0.0, 0.02,
			"a vertical trunk must not be bent by the walk")


## The guard on the walk itself. A band with nothing near the trunk must END the
## walk rather than jump to a branch on the far side of the crown -- which would
## put the proxy through open sky, the exact failure the coordinator predicted
## for a convex hull, arrived at by a different road.
func test_the_trunk_walk_stops_rather_than_jumping_to_a_branch() -> void:
	var faces := _leaning_trunk(0.0, 1.2)
	# A branch four metres away at 2 m up, and nothing between.
	faces.append_array([
		Vector3(4.0, 1.9, 0.0), Vector3(4.2, 1.9, 0.0), Vector3(4.1, 2.3, 0.0)])
	var path := FaderScript.trunk_path(faces, Vector3.ZERO, 0.15, 3.4)
	for point in path:
		assert_true(absf((point as Vector3).x) < 1.0,
			"the walk jumped to x %.2f, which is a branch and not the trunk" % (point as Vector3).x)


## And the proxy actually built from that walk has to lean with it. This is the
## assertion that fails against the shipped rule: a vertical cylinder covers
## x = 0 at every height, and the drawn trunk does not.
func test_a_leaning_tree_gets_a_proxy_that_leans_with_it() -> void:
	var tree := Node3D.new()
	tree.name = "TreeE"
	tree.scene_file_path = "res://tree_e.glb"
	var mesh := MeshInstance3D.new()
	mesh.name = "Tree_Bare_D"
	var built := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _leaning_trunk(0.35, 3.4)
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = built
	tree.add_child(mesh)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.2
	trunk.height = 3.4
	_with_shape(tree, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.7, 0.0)))

	var highest := Vector3.ZERO
	for entry in FaderScript.proxy_shapes(tree):
		var at: Vector3 = (entry["transform"] as Transform3D).origin
		if at.y > highest.y:
			highest = at
	assert_true(highest.x > 0.5,
		"the top of the proxy sits at x %.2f; the drawn trunk is at %.2f there, and a proxy that stays at 0 is the false trigger this task exists to fix"
			% [highest.x, 0.35 * highest.y])
	tree.free()


# --- where the ray is aimed ---------------------------------------------------

## The owner's rule: from the camera to his head and upper body. His origin is at
## his ankles, and a ray to it is aimed at the one part of him whose being
## covered nobody minds -- it under-detects when his body is hidden and his feet
## are clear, and over-detects the reverse.
func test_the_ray_is_aimed_at_his_chest_and_not_at_his_boots() -> void:
	var fader = FaderScript.new()
	var body := Node3D.new()
	var at := fader.aim_point(body)
	var settings = load(SETTINGS_PATH)
	assert_true(at.y > 1.0, "the ray is aimed %.2f m up, which is still his boots" % at.y)
	assert_almost_eq(at.y, fader.subject_height * settings.aim_height, 0.001)
	assert_true(settings.aim_height > 0.6 and settings.aim_height < 0.95,
		"the aim is at %.2f of his height; head and upper body is the rule" % settings.aim_height)
	body.free()
	fader.free()


# --- applying the fade -------------------------------------------------------

func _instance() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	return mesh


func test_no_fade_leaves_the_occluder_exactly_as_it_was() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	fader.apply_fade([mesh], 0.0)
	assert_true(mesh.material_override == null, "an un-faded occluder must carry no override")
	assert_almost_eq(mesh.transparency, 0.0, 0.0001)
	mesh.free()
	fader.free()


## Rule 2: at full fade both cel bands are the SAME tint, so the object is one
## flat silhouette rather than a lit shape in a new colour.
func test_a_full_fade_is_one_flat_translucent_tint() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	fader.apply_fade([mesh], 1.0)
	var override = mesh.material_override
	assert_not_null(override, "a fully faded occluder must be wearing the tint")
	# The override is the DEPTH prepass; the colour is the pass hung off it. See
	# OccluderFader.tint_material() for why a faded building needs both.
	assert_true(override is BaseMaterial3D, "the depth prepass must be a material Godot can write depth from")
	if override is BaseMaterial3D:
		var prepass := override as BaseMaterial3D
		assert_eq(prepass.depth_draw_mode, BaseMaterial3D.DEPTH_DRAW_ALWAYS,
			"without a depth write the faded building shows its own insides")
		assert_almost_eq(prepass.albedo_color.a, 0.0, 0.0001, "the depth pass must draw no colour of its own")
		assert_true(prepass.render_priority < 0,
			"every depth pass in the frame must sort before every colour pass, or a building of nine meshes still stacks")
	var tinted = override.next_pass as ShaderMaterial
	assert_not_null(tinted, "the depth pass must carry the colour pass")
	if tinted == null:
		mesh.free()
		fader.free()
		return
	var settings = load(SETTINGS_PATH)
	var tint: Color = tinted.get_shader_parameter("tint")
	assert_eq(
		Color(tint.r, tint.g, tint.b), Color(settings.tint.r, settings.tint.g, settings.tint.b),
		"the faded object must wear the tint the data asks for"
	)
	var code: String = (tinted.shader as Shader).code
	assert_true(
		code.contains("depth_draw_never"),
		"the fade shader must not write depth, or the faded occluder still hides the character it exists to reveal"
	)
	assert_true(code.contains("unshaded"), "a fade is a flat silhouette, not a lit shape in a new colour")
	assert_true(code.contains("ambient_light_disabled"), "every shader in this project disables ambient")
	var shown: float = mesh.get_instance_shader_parameter("fade_opacity")
	assert_almost_eq(shown, settings.tint.a, 0.0001,
		"a fully faded occluder must be translucent, not gone")
	assert_true(shown > 0.0 and shown < 1.0, "a silhouette you cannot see through is just a repaint")
	mesh.free()
	fader.free()


## The crossover between "fading out as itself" and "fading in as a silhouette"
## has to be a moment of full transparency approached from both sides, or the
## object changes colour in one frame while it is still visible.
func test_the_crossover_is_reached_from_both_sides_at_full_transparency() -> void:
	var alpha: float = (load(SETTINGS_PATH) as Resource).tint.a
	assert_almost_eq(FaderScript.visible_opacity(0.499, alpha), 0.0, 0.01,
		"approaching the crossover the object must be all but invisible")
	assert_almost_eq(FaderScript.visible_opacity(0.501, alpha), 0.0, 0.01,
		"leaving the crossover the silhouette must start from all but invisible")
	assert_almost_eq(FaderScript.visible_opacity(0.0, alpha), 1.0, 0.0001, "an un-faded object is fully drawn")
	assert_almost_eq(FaderScript.visible_opacity(1.0, alpha), alpha, 0.0001, "a fully faded object is the tint")


## Rule 2 again, from the other end: the tint must be DARK. A pale tint over
## bright snow is not a silhouette, it is the object disappearing.
func test_the_tint_is_a_dark_grey_black() -> void:
	var settings = load(SETTINGS_PATH)
	assert_not_null(settings, "%s must exist -- it is generated by tools/generate_occluder_fade.gd" % SETTINGS_PATH)
	if settings == null:
		return
	var tint: Color = settings.tint
	var luma := 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b
	assert_true(luma < 0.10, "the tint is at luma %.3f; 浅灰黑 is a dark grey-black" % luma)
	assert_true(tint.a > 0.15 and tint.a < 0.75, "the tint is %.2f opaque; it has to be see-through and still read" % tint.a)


## Rule 3's one limit. The tint is off-palette by the owner's ruling, but rule
## 12 reserves warm pixels for fire, windows, beacons, the scarf and the truck,
## and a faded farmhouse is a large fraction of the frame.
func test_the_tint_is_not_warm() -> void:
	var settings = load(SETTINGS_PATH)
	var bible = load(PALETTE_PATH)
	assert_not_null(settings)
	assert_not_null(bible)
	if settings == null or bible == null:
		return
	var tint: Color = settings.tint
	assert_false(bible.is_warm(Color(tint.r, tint.g, tint.b)), "the tint is one of rule 12's warm tones")
	assert_true(tint.r <= tint.b, "the tint is warmer than it is cool, which rule 12 does not allow here")


## Rule 4. The character's own translucency is a different feature and it stays.
## This is here rather than only in test_character_occlusion.gd because the
## obvious way to implement the owner's correction is to delete it.
func test_the_character_keeps_the_translucency_that_shows_his_sunken_boots() -> void:
	var source := FileAccess.get_file_as_string(CONTROLLER_SOURCE)
	assert_true(source.contains("wear_ghost(body_material)"),
		"the sunken-boot translucency was removed along with the occlusion fade; the owner asked for it to stay")
	var scheme = load("res://data/characters/wanderer_pale.tres")
	assert_not_null(scheme)
	if scheme != null:
		assert_true(scheme.ghost_color.a > 0.0, "the character's translucency has been switched off in data")


# --- how it moves -------------------------------------------------------------
#
# The owner's third complaint: it snaps between states with no eased motion, and
# he asked for a proper eased transition in DOTween's terms. DOTween is a Unity
# library; Godot's own Tween covers the same ground and TRANS_ELASTIC and
# TRANS_BACK are both right there. Neither is used, anywhere, and these tests
# pin that down along with the reasoning in OccluderFader.curve_for().


func test_nothing_in_this_effect_overshoots() -> void:
	var settings = load(SETTINGS_PATH)
	for metres in [0.3, 2.0, 3.9, 4.0, 12.0, 50.0]:
		var curve = FaderScript.curve_for(metres, settings.large_metres)
		assert_false(curve == Tween.TRANS_ELASTIC,
			"an elastic alpha clamps at both ends: on the way in it arrives early and holds, on the way out it pulses back toward solid. That is a rendering fault, not a spring.")
		assert_false(curve == Tween.TRANS_BACK,
			"same as elastic -- an overshoot on an alpha has nowhere to overshoot into")
		assert_false(curve == Tween.TRANS_LINEAR,
			"linear is what it did before, and it is what 'abrupt' meant")


## Scale the motion to the object. A house may not wobble; it may only be heavy.
func test_a_house_moves_more_slowly_than_a_fence_post() -> void:
	var settings = load(SETTINGS_PATH)
	var house := FaderScript.duration_for(
		1.0, 12.0, settings.large_metres, settings.fade_seconds, settings.fade_seconds_large)
	var post := FaderScript.duration_for(
		1.0, 0.4, settings.large_metres, settings.fade_seconds, settings.fade_seconds_large)
	assert_true(house > post,
		"a farmhouse takes %.2f s and a fence post %.2f s; a building that changes state as briskly as a post reads as a light switch" % [house, post])
	assert_true(house < 0.8, "%.2f s to answer 'where is my guy' is a player who has already stopped to look" % house)
	assert_eq(
		FaderScript.ease_for(12.0, settings.large_metres), Tween.EASE_IN_OUT,
		"a large object leaves and arrives gently at both ends")


## A reversal caught halfway takes half the time rather than crawling back over
## the full duration. Walking behind a tree and straight back out is the case,
## and it is the half of "expensive rather than cheap" that a curve alone cannot
## buy -- see _start(), which also begins every new tween AT THE CURRENT VALUE
## rather than at an endpoint.
func test_a_reversal_caught_halfway_takes_half_the_time() -> void:
	var settings = load(SETTINGS_PATH)
	var whole := FaderScript.duration_for(
		1.0, 0.4, settings.large_metres, settings.fade_seconds, settings.fade_seconds_large)
	var half := FaderScript.duration_for(
		-0.5, 0.4, settings.large_metres, settings.fade_seconds, settings.fade_seconds_large)
	assert_almost_eq(half, whole * 0.5, 0.001,
		"a reversal from halfway took %.3f s against a whole fade's %.3f s" % [half, whole])
	assert_almost_eq(
		FaderScript.duration_for(0.0, 0.4, settings.large_metres, settings.fade_seconds, settings.fade_seconds_large),
		0.0, 0.0001, "a move to where it already is takes no time at all")


## Bounded and small, and smaller than the fade it delays. A dwell is not a fix
## for a broken release path -- if an occluder ever appears to stick for longer
## than this, the trigger is wrong and this is not the place to look.
func test_the_dwell_is_short_and_bounded() -> void:
	var settings = load(SETTINGS_PATH)
	assert_true(settings.dwell_seconds > 0.0, "no dwell at all lets a single ray chatter on an edge")
	assert_true(settings.dwell_seconds <= 0.15,
		"the dwell is %.2f s; anything longer stops being anti-flicker and starts being the fade sticking" % settings.dwell_seconds)
	assert_true(settings.dwell_seconds < settings.fade_seconds,
		"the dwell must be shorter than the fade it delays, or it is the thing you see")


# --- one owner for a mesh's alpha ---------------------------------------------
#
# Two systems used to fade the farmhouse. InteriorReveal takes the roof off when
# the player steps inside; this fades the whole building when it stands in his
# way. They did not fight -- the fader stood down as soon as the reveal opened --
# but at the handover the house played briefly TOWARD SOLID while the roof was
# still coming off, which is a pop at the exact beat the reveal exists to serve.


func test_a_removal_request_alone_is_exactly_what_the_reveal_used_to_write() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	fader.request_removal(mesh, self, 0.4)
	assert_almost_eq(mesh.transparency, 0.4, 0.0001,
		"with nothing else interested, one owner has to produce the same number the reveal wrote for itself")
	assert_true(mesh.material_override == null, "a reveal is a removal, not a silhouette")
	fader.request_removal(mesh, self, 0.0)
	assert_almost_eq(mesh.transparency, 0.0, 0.0001, "dropping the request puts the mesh back")
	mesh.free()
	fader.free()


func test_the_larger_of_two_requests_wins() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	fader.request_removal(mesh, self, 0.3)
	assert_almost_eq(fader.removal_of(mesh), 0.3, 0.0001)
	var other := RefCounted.new()
	fader.request_removal(mesh, other, 0.8)
	assert_almost_eq(fader.removal_of(mesh), 0.8, 0.0001, "max(), not last-writer-wins")
	fader.request_removal(mesh, other, 0.0)
	assert_almost_eq(fader.removal_of(mesh), 0.3, 0.0001, "one source letting go must not release the other's")
	mesh.free()
	fader.free()


## The handover, as a number. Walking through it, what reaches the screen must
## never travel back toward solid -- and `max()` alone does not give you that,
## which is the part that looks like it should. See request_removal().
func test_the_handover_never_travels_back_toward_solid() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	var alpha: float = (load(SETTINGS_PATH) as Resource).tint.a
	var previous := 1.0
	# The house is a full silhouette and the player crosses the threshold. The
	# fader HOLDS -- it is not released while the reveal is part way in -- and
	# the reveal fades the roof out from there.
	for step in range(21):
		var reveal := float(step) / 20.0
		fader.paint(mesh, 1.0, reveal)
		var shown: float = mesh.get_instance_shader_parameter("fade_opacity")
		assert_true(mesh.material_override != null, "the roof stays a silhouette while it goes")
		assert_true(shown <= previous + 0.0001,
			"at reveal %.2f the roof came back to %.3f from %.3f, which is the pop" % [reveal, shown, previous])
		previous = shown
	assert_almost_eq(previous, 0.0, 0.0001, "a fully revealed roof has to be gone")
	assert_true(alpha > 0.0)
	mesh.free()
	fader.free()


## And the other end of it: once the reveal is complete the rest of the building
## is free to come back to solid, because the parts the reveal took are already
## invisible. A room that stayed a grey silhouette while the player stood in it
## would be the fix overshooting into the opposite defect.
func test_a_part_nobody_is_removing_still_comes_back_to_solid() -> void:
	var fader = FaderScript.new()
	var mesh := _instance()
	fader.paint(mesh, 0.0, 0.0)
	assert_true(mesh.material_override == null)
	assert_almost_eq(mesh.transparency, 0.0, 0.0001)
	mesh.free()
	fader.free()
