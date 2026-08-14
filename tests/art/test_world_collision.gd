extends TestCase

## The world is solid, and it is solid in the right shape.
##
## tests/unit/test_model_collision.gd proves the geometry; this proves it
## actually reached the models on disk. The two failure modes it is here for are
## both silent:
##
##   * `tools/palette_import_materials.gd` builds the collision inside
##     `_post_import`, which only an import pass runs. Editing that script does
##     not invalidate Godot's import cache, so the code can be perfectly correct
##     and every `.glb` in the project still arrive hollow. Nothing else would
##     say a word -- the game looks identical and the player walks through the
##     house.
##   * A shape of the wrong KIND is worse than none. A convex hull of a bare
##     tree is an invisible eight-metre blob; a wall across the farmhouse
##     doorway is a building nobody can enter, and the agent building door entry
##     would be debugging its own code.
##
## So the checks below are about kind and size, not merely presence.

const CollisionScript := preload("res://tools/model_collision.gd")
const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

const MODEL_SUFFIXES: Array[String] = [".glb", ".gltf", ".fbx", ".dae", ".obj"]

const FARMHOUSE := "res://assets/models/buildings/farmhouse/farmhouse.glb"

const TREES := [
	"res://assets/models/vegetation/tree_bare_a.glb",
	"res://assets/models/vegetation/tree_bare_b.glb",
	"res://assets/models/vegetation/tree_bare_c.glb",
	"res://assets/models/vegetation/tree_bare_d.glb",
	"res://assets/models/vegetation/tree_bare_e.glb",
]

const BOXED := [
	"res://assets/models/props/pickup_truck.glb",
	"res://assets/models/props/flatbed_truck.glb",
	"res://assets/models/props/panel_van.glb",
	"res://assets/models/props/fence_segment.glb",
	"res://assets/models/props/woodpile.glb",
	"res://assets/models/props/supply_cache.glb",
	"res://assets/models/props/field_marker.glb",
	"res://assets/models/props/fallen_limb.glb",
	"res://assets/models/props/emergency_sled.glb",
	"res://assets/models/props/departure_pack.glb",
	"res://assets/models/props/chopping_block.glb",
	"res://assets/models/props/evacuation_cart.glb",
	"res://assets/models/props/synty_supply_sacks.glb",
	"res://assets/models/props/synty_wooden_barrel.glb",
	"res://assets/models/props/synty_field_crate.glb",
	"res://assets/models/props/synty_work_log.glb",
	"res://assets/models/props/synty_field_stump.glb",
	"res://assets/models/props/synty_yard_cache.glb",
	"res://assets/models/props/synty_evacuation_cache.glb",
	"res://assets/models/props/synty_woodwork_station.glb",
	"res://assets/models/props/synty_larder_chest.glb",
	"res://assets/models/props/synty_provision_stack.glb",
	"res://assets/models/props/synty_yard_table.glb",
	"res://assets/models/props/synty_tarped_cache.glb",
	"res://assets/models/props/synty_broken_gateway.glb",
	"res://assets/models/props/synty_firepit.glb",
	"res://assets/models/props/synty_generator_cache.glb",
	"res://assets/models/props/synty_field_clinic.glb",
	"res://assets/models/props/synty_fish_camp.glb",
	"res://assets/models/props/synty_fuel_depot.glb",
	"res://assets/models/props/synty_road_blockade.glb",
	"res://assets/models/props/synty_radio_relay.glb",
	"res://assets/models/props/synty_refuge_bedroll.glb",
	"res://assets/models/props/synty_rock_cluster_north.glb",
	"res://assets/models/props/synty_rock_cluster_south.glb",
	"res://assets/models/props/synty_rock_cluster_east.glb",
	"res://assets/models/props/burning_barrel.glb",
	"res://assets/models/props/campfire.glb",
]

const SWINGS := [
	"res://assets/models/props/tire_swing.glb",
]

const BUILDINGS := [
	FARMHOUSE,
	"res://assets/models/buildings/tool_shed/tool_shed.glb",
	"res://assets/models/buildings/well_house/well_house.glb",
	"res://assets/models/props/water_well.glb",
	"res://assets/models/buildings/gas_station/gas_station.glb",
	"res://assets/models/buildings/church/church.glb",
	"res://assets/models/buildings/logging_camp/logging_camp.glb",
	"res://assets/models/buildings/transmission_tower/transmission_tower.glb",
]

## Nothing in the frame should stop a walker here. The wires are 7 cm of steel
## eight metres up; the swing is deliberately excluded because its tire is a
## player-facing physical object.
const HOLLOW := [
	"res://assets/models/props/power_wire.glb",
	"res://assets/models/props/synty_pickaxe.glb",
]

## The farmhouse's front doorway, probed a little inside the opening the import
## cuts so that a triangle clipped exactly to its edge is not a failure.
const DOORWAY_PROBE := AABB(Vector3(1.35, 0.55, -0.20), Vector3(0.90, 1.90, 0.25))

## The facade either side of it, at chest height.
const WALL_RIGHT_OF_DOOR := AABB(Vector3(2.45, 1.00, -0.20), Vector3(0.90, 1.00, 0.25))
const WALL_LEFT_OF_DOOR := AABB(Vector3(0.25, 1.00, -0.20), Vector3(0.90, 1.00, 0.25))


## Every collider a model carries, as `{shape, transform}` in the model's space.
##
## Instantiates, which allocates Nodes -- so it frees the tree before returning
## (briefing section 2.2). The shapes outlive it: a Shape3D is a Resource.
func _colliders(path: String) -> Array:
	var found: Array = []
	var scene = load(path)
	if not (scene is PackedScene):
		return found
	var root := (scene as PackedScene).instantiate()
	for node in _walk(root):
		if not (node is CollisionShape3D):
			continue
		var collider := node as CollisionShape3D
		if collider.shape == null:
			continue
		found.append({
			"shape": collider.shape,
			"transform": CollisionScript._transform_to(collider, root),
			"name": String(collider.name),
		})
	root.free()
	return found


func _walk(node: Node, found: Array = []) -> Array:
	found.append(node)
	for child in node.get_children():
		_walk(child, found)
	return found


func _has_body(path: String) -> bool:
	var scene = load(path)
	if not (scene is PackedScene):
		return false
	var root := (scene as PackedScene).instantiate()
	var found := false
	for node in _walk(root):
		if node is StaticBody3D:
			found = true
			break
	root.free()
	return found


## Every collision triangle a model carries, in the model's own space.
func _collision_faces(path: String) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for entry in _colliders(path):
		var shape = entry["shape"]
		if not (shape is ConcavePolygonShape3D):
			continue
		var into: Transform3D = entry["transform"]
		for vertex in (shape as ConcavePolygonShape3D).get_faces():
			faces.append(into * vertex)
	return faces


func _triangles_touching(faces: PackedVector3Array, box: AABB) -> int:
	var hits := 0
	for index in range(0, faces.size() - 2, 3):
		var bounds := AABB(faces[index], Vector3.ZERO) \
			.expand(faces[index + 1]).expand(faces[index + 2])
		if box.intersects(bounds):
			hits += 1
	return hits


func _models() -> PackedStringArray:
	var found := PackedStringArray()
	for root in AssetScannerScript.SCAN_ROOTS:
		found.append_array(AssetScannerScript.find_files(root, MODEL_SUFFIXES))
	return found


# --- coverage ----------------------------------------------------------------

## The rule table must be total over what is actually on disk. A model whose
## name nothing matches gets no collision at all, and the only symptom in play
## is walking through it.
func test_every_world_mesh_has_a_declared_collision_policy() -> void:
	var undeclared := PackedStringArray()
	var seen := 0
	for path in _models():
		if AssetScannerScript.is_surface_rule_exempt(path):
			continue
		var scene = load(path)
		if not (scene is PackedScene):
			continue
		var root := (scene as PackedScene).instantiate()
		for node in _walk(root):
			if not (node is MeshInstance3D):
				continue
			seen += 1
			if CollisionScript.rule_for(String(node.name)).is_empty():
				undeclared.append("%s holds a mesh called %s, which no rule in tools/model_collision.gd declares -- it will arrive with no collision and nothing else will say so" % [path, node.name])
		root.free()
	assert_true(seen > 0, "no world mesh was found at all, so this test checked nothing")
	assert_eq(undeclared.size(), 0, "; ".join(undeclared))


func test_every_solid_model_arrives_carrying_a_body() -> void:
	var hollow := PackedStringArray()
	for path in TREES + BOXED + SWINGS + BUILDINGS:
		if not _has_body(path):
			hollow.append("%s carries no StaticBody3D -- run tools/wire_model_imports.gd, then --headless --import" % path)
	assert_eq(hollow.size(), 0, "; ".join(hollow))


func test_the_wires_arrive_hollow() -> void:
	for path in HOLLOW:
		assert_false(_has_body(path), "%s must not be solid" % path)


func test_the_tire_swing_arrives_with_one_tire_collider() -> void:
	for path in SWINGS:
		var colliders := _colliders(path)
		assert_eq(colliders.size(), 1, "%s must carry exactly one tire collider" % path)
		if colliders.is_empty():
			continue
		assert_true(
			colliders[0]["shape"] is SphereShape3D,
			"%s must collide as a compact tire sphere, not as its hanging rope" % path
		)


# --- trees and the pole ------------------------------------------------------

## Art Bible rule 7 makes a tree a silhouette of bare twigs, and the space
## between them is most of the model. The collider must be the trunk.
func test_a_tree_collides_on_its_trunk_and_not_across_its_crown() -> void:
	for path in TREES:
		var colliders := _colliders(path)
		assert_eq(colliders.size(), 1, "%s must carry exactly one collider, it carries %d" % [path, colliders.size()])
		if colliders.is_empty():
			continue
		var shape = colliders[0]["shape"]
		assert_true(
			shape is CylinderShape3D,
			"%s must collide as a cylinder on the trunk; it collides as %s" % [path, shape]
		)
		if not (shape is CylinderShape3D):
			continue
		var radius: float = (shape as CylinderShape3D).radius
		var crown := _crown_width(path)
		assert_true(
			radius <= 0.40,
			"%s has a %.2f m collision radius; a trunk is not that thick" % [path, radius]
		)
		assert_true(
			radius < crown * 0.25,
			"%s is %.2f m across and collides at radius %.2f -- that is the crown, not the trunk" % [path, crown, radius]
		)


func _crown_width(path: String) -> float:
	var scene = load(path)
	if not (scene is PackedScene):
		return 0.0
	var root := (scene as PackedScene).instantiate()
	var widest := 0.0
	for node in _walk(root):
		if not (node is MeshInstance3D):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z))
	root.free()
	return widest


## The pole's AABB is 2.12 m wide and every centimetre past the post is
## crossarm, eight metres up.
func test_the_power_pole_collides_as_a_post_and_not_as_its_crossarm() -> void:
	var colliders := _colliders("res://assets/models/props/power_pole.glb")
	assert_eq(colliders.size(), 1)
	if colliders.is_empty():
		return
	var shape = colliders[0]["shape"]
	assert_true(shape is CylinderShape3D, "the pole must collide as a post, it collides as %s" % shape)
	if shape is CylinderShape3D:
		assert_true(
			(shape as CylinderShape3D).radius <= 0.35,
			"the pole collides at radius %.2f, which is its crossarm" % (shape as CylinderShape3D).radius
		)


# --- vehicles and the fence --------------------------------------------------

func test_each_vehicle_collides_as_one_box() -> void:
	for path in BOXED:
		var colliders := _colliders(path)
		assert_eq(colliders.size(), 1, "%s must carry one box, it carries %d" % [path, colliders.size()])
		if colliders.is_empty():
			continue
		assert_true(
			colliders[0]["shape"] is BoxShape3D,
			"%s must collide as a box; it collides as %s" % [path, colliders[0]["shape"]]
		)


## The fence's collision has to repeat with the fence, and this is what makes it
## do so: `Farmstead._build_fences()` instances the same PackedScene once per
## segment, so a collider carried by the model is a collider on every post.
## Nothing in src/ or in the scene mentions fence collision at all, which is the
## point.
func test_the_fence_segment_carries_the_collider_that_repeats_with_it() -> void:
	var colliders := _colliders("res://assets/models/props/fence_segment.glb")
	assert_eq(colliders.size(), 1, "a fence segment must carry exactly one collider")
	if colliders.is_empty():
		return
	var shape = colliders[0]["shape"]
	assert_true(shape is BoxShape3D, "a fence panel is a box; this is %s" % shape)
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		assert_true(size.z > 2.0, "the panel must span the run between posts, it is %.2f m" % size.z)
		assert_true(size.x < 0.6, "a fence is thin; this one is %.2f m thick" % size.x)


## And the run really is instanced from that file rather than from a copy.
func test_the_farmstead_builds_its_fence_from_the_model_that_carries_the_collider() -> void:
	var farmstead := Farmstead.new()
	var run: int = farmstead.fence_layout().size()
	farmstead.free()
	assert_true(run > 1, "the fence is %d segment(s); collision that repeats needs a run to repeat along" % run)
	assert_true(
		Farmstead.FENCE_SEGMENT.resource_path == "res://assets/models/props/fence_segment.glb",
		"the farmstead instances %s, not the model this gate checked" % Farmstead.FENCE_SEGMENT.resource_path
	)


# --- the buildings -----------------------------------------------------------

func test_every_building_collides_as_a_trimesh_of_its_walls() -> void:
	for path in BUILDINGS:
		var faces := _collision_faces(path)
		assert_true(faces.size() >= 3, "%s carries no wall collision at all" % path)


## The rule that keeps a foundation slab from becoming an invisible kerb. The
## player's Y is assigned from the snow height field every frame and there is no
## gravity, so nothing can be stepped onto: anything left under the knee is a
## wall he walks into, not a step he walks up.
func test_no_building_left_a_kerb_below_the_knee() -> void:
	for path in BUILDINGS:
		var faces := _collision_faces(path)
		var kerbs := 0
		for index in range(0, faces.size() - 2, 3):
			var top := maxf(faces[index].y, maxf(faces[index + 1].y, faces[index + 2].y))
			if top <= CollisionScript.KNEE:
				kerbs += 1
		assert_eq(kerbs, 0, "%s has %d collision triangle(s) entirely below the knee" % [path, kerbs])


## THE DOORWAY IS A GAP. Another agent is making door entry work; a wall-shaped
## collider across the opening would defeat it, and the symptom would look like
## a bug in their code.
func test_the_farmhouse_doorway_is_a_gap() -> void:
	var faces := _collision_faces(FARMHOUSE)
	assert_true(faces.size() > 0, "the farmhouse carries no collision, so this checked nothing")
	assert_eq(
		_triangles_touching(faces, DOORWAY_PROBE), 0,
		"the farmhouse doorway is covered by collision -- the only way into the building is sealed"
	)


## The other half of that contract, and the half that is easy to lose: a gate
## that only checked the doorway would pass on a house with no collision at all.
func test_the_farmhouse_facade_is_solid_either_side_of_the_doorway() -> void:
	var faces := _collision_faces(FARMHOUSE)
	assert_true(
		_triangles_touching(faces, WALL_RIGHT_OF_DOOR) > 0,
		"the facade to the right of the door is not solid"
	)
	assert_true(
		_triangles_touching(faces, WALL_LEFT_OF_DOOR) > 0,
		"the facade to the left of the door is not solid"
	)


## The roof is not collision. Nothing can reach it, and a roof in the physics
## world is a few hundred triangles of nothing.
func test_the_farmhouse_roof_is_not_solid() -> void:
	var faces := _collision_faces(FARMHOUSE)
	var above := 0
	for index in range(0, faces.size() - 2, 3):
		var bottom := minf(faces[index].y, minf(faces[index + 1].y, faces[index + 2].y))
		if bottom >= CollisionScript.REACH:
			above += 1
	assert_eq(above, 0, "%d collision triangle(s) sit entirely above head height" % above)
