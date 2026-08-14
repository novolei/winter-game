@tool
extends RefCounted

## Gives a world model its collision, at import, from what the model already is.
##
## ---------------------------------------------------------------------------
## WHY THIS RUNS AT IMPORT AND NOT IN THE SCENE
## ---------------------------------------------------------------------------
## Every world model is placed by `scenes/main.tscn` or, in the fence's case,
## instanced at runtime by `src/entities/farmstead.gd`. Collision authored in the
## scene would therefore have to be authored twice -- once per placement -- and
## the fence's twenty-two segments could not be authored at all, because they do
## not exist until `_ready()` runs. A model that carries its own body is placed,
## instanced and duplicated with it, and a run of fence gets a run of collision
## for free.
##
## The wiring is `tools/palette_import_materials.gd`, which every world model's
## `.import` already points at through `import_script/path` and which
## `tests/art/test_import_wiring.gd` already guards. Adding a second import
## script would mean a second line in every `.import` file and a second gate to
## keep it there; this is one more thing the existing one does.
##
## Godot's own name-suffix mechanism (`-col`, `-convcol`, ...) was the first
## choice and does not fit. It would mean renaming meshes in the Blender build
## scripts and re-exporting every model, and the two shapes this project
## actually needs -- a trunk cylinder under a crown, a wall with a doorway cut
## out of it -- are not among the ones a suffix can ask for.
##
## ---------------------------------------------------------------------------
## FIVE KINDS, AND WHY EACH IS THE ONE IT IS
## ---------------------------------------------------------------------------
## **TRUNK** -- trees and the power pole. A convex hull of a bare tree is an
## eight-metre invisible blob: `tree_bare_a.glb` is 7.96 m across and almost all
## of that is air between twigs. The trunk is measured at the base band, where
## the only geometry is the trunk itself, and becomes a cylinder about a metre
## and a half taller than the walker. The pole is the same problem wearing a
## crossarm: its AABB is 2.12 m wide and its post is 0.28.
##
## **BOX** -- the two vehicles and the fence segment. The model's own AABB. For
## a truck that includes the wing mirrors, which is fine: nobody needs to walk
## between a mirror and the door. For the fence it is exactly right -- a thin,
## tall, 2.78 m box is what a fence panel is -- and because it rides the model,
## the collision repeats every time `Farmstead._build_fences()` instances one.
##
## **SWING** -- the tire only. A full AABB would make the hanging rope into a
## two-metre invisible wall, so the player meets the round tire but can pass
## beneath the branch and either side of the rope.
##
## **WALLS** -- the buildings. A trimesh of the geometry, taken from the band
## between the knee and a little over head height, with declared openings cut
## out of it. Two decisions in there, both load-bearing:
##
##   * THE BAND. `PlayerController` places the body's Y from the snow height
##     field every frame and there is no gravity in this game (see its
##     `_physics_process`), so nothing can be stepped onto. A porch deck, a
##     floor slab or a foundation skirt left in the collision is therefore not
##     a step, it is a 45 cm invisible kerb -- and the farmhouse's skirt runs
##     under the whole ground floor, so the kerb would be across the doorway.
##     Anything whose top is under the knee cannot stop a walker and is dropped.
##     So is anything whose bottom is over head height, which is the roof.
##   * THE OPENINGS. The farmhouse's front wall HAS NO HOLE IN IT.
##     `tools/blender/build_farmhouse.py` draws the door as a flat panel on a
##     solid `Wall_Front_Porch`, so collision taken straight off the geometry
##     seals the only way into the building. `subtract_box()` cuts the doorway
##     out of the triangle soup properly -- clipped, not merely triangles
##     dropped, because that wall is two triangles wide and dropping either
##     would take out half the facade.
##
## **NONE** -- the wires, roof, porch, floor, furniture and door leaf. Declared
## rather than defaulted: see RULES.
##
## ---------------------------------------------------------------------------
## WHAT IT DOES NOT DO
## ---------------------------------------------------------------------------
## Nothing here touches a material, a mesh or a colour. Art Bible rules 8 and 9
## and the gates that enforce them are untouched by collision: a Shape3D has no
## surface.

## The kinds a rule can ask for.
const NONE := &"none"
const BOX := &"box"
const TRUNK := &"trunk"
const WALLS := &"walls"
const SWING := &"swing"

## How far up the model the trunk is measured. One ring of the tapered tube, and
## nothing else in any of these models is that close to the ground.
const TRUNK_BAND := 0.15

## Below this, in the model's own metres, geometry cannot stop a walker whose
## feet are placed by the height field; above it, nothing can reach him. Both
## are model-space heights rather than offsets from each mesh's own base,
## because every world model in this project is built standing on y = 0.
const KNEE := 0.45
const REACH := 3.2

## The farmhouse's front doorway, in the model's own metres.
##
## `tools/blender/build_farmhouse.py`: `DOOR_X0, DOOR_X1 = 1.30, 2.30`, the wall
## it is cut from is `Wall_Front_Porch` at Blender y 0.00..0.16, and the leaf
## sits proud of it at y = -0.04. That file's own header gives the axis mapping:
## Blender (x, y, z) arrives in Godot as (x, z, -y). So the doorway is
## x 1.30..2.30, z -0.16..+0.04, and the height runs from under the foundation
## skirt to the head of the frame at 2.55.
##
## It is generous downward on purpose. The skirt (Blender z 0.00..0.42) is
## dropped by the knee rule already, but a model rebuilt with a sill or a
## threshold must not be able to put a lip back across the door.
##
## THE DOOR LEAF ITSELF sits entirely inside this box, so `FH_Door` -- the
## swinging leaf another agent is building -- is cut away with the wall whether
## or not its rule says NONE. A closed door you cannot walk through would be
## correct one day and is not this task's to decide; today it must not be the
## thing that makes the house unenterable.
const FARMHOUSE_DOOR := AABB(Vector3(1.30, -1.0, -0.30), Vector3(1.00, 3.55, 0.50))

## Every mesh name this project ships, and what it collides as.
##
## PREFIX-MATCHED, first match wins. Godot's importer appends a suffix to a
## duplicated node name, so a whole-string match would go quietly missing the
## day two copies of a mesh landed in one file.
##
## THERE IS NO DEFAULT. A name that matches nothing gets no collision and
## `tests/art/test_world_collision.gd` fails naming the file, because the
## alternative -- a sensible-looking default -- is how a new tree ends up
## wearing a convex hull of its own crown with nothing reporting it.
const RULES := [
	{"name": "Tree_Bare_", "kind": TRUNK, "height": 3.4},
	# Taller than a tree's because the pole is buried 0.45 m and the height is
	# measured from the lowest vertex.
	{"name": "Power_Pole", "kind": TRUNK, "height": 4.0},
	{"name": "Power_Wire", "kind": NONE},
	{"name": "Tire_Swing", "kind": SWING},
	{"name": "Fence_Segment", "kind": BOX},
	{"name": "Pickup_Truck", "kind": BOX},
	{"name": "Flatbed_Truck", "kind": BOX},
	{"name": "Panel_Van", "kind": BOX},
	{"name": "Woodpile", "kind": BOX},
	{"name": "Supply_Cache", "kind": BOX},
	{"name": "Field_Marker", "kind": BOX},
	{"name": "Fallen_Limb", "kind": BOX},
	{"name": "Emergency_Sled", "kind": BOX},
	{"name": "Departure_Pack", "kind": BOX},
	{"name": "Chopping_Block", "kind": BOX},
	{"name": "Evacuation_Cart", "kind": BOX},
	{"name": "Gas_Station", "kind": WALLS},
	{"name": "Church", "kind": WALLS},
	{"name": "Logging_Camp", "kind": WALLS},
	{"name": "Transmission_Tower", "kind": WALLS},
	{"name": "Synty_Supply_Sacks", "kind": BOX},
	{"name": "Synty_Wooden_Barrel", "kind": BOX},
	{"name": "Synty_Field_Crate", "kind": BOX},
	{"name": "Synty_Work_Log", "kind": BOX},
	{"name": "Synty_Field_Stump", "kind": BOX},
	{"name": "Synty_Pickaxe", "kind": NONE},
	{"name": "Synty_Yard_Cache", "kind": BOX},
	{"name": "Synty_Evacuation_Cache", "kind": BOX},
	{"name": "Synty_Woodwork_Station", "kind": BOX},
	{"name": "Synty_Larder_Chest", "kind": BOX},
	{"name": "Synty_Provision_Stack", "kind": BOX},
	{"name": "Synty_Yard_Table", "kind": BOX},
	{"name": "Synty_Tarped_Cache", "kind": BOX},
	{"name": "Synty_Broken_Gateway", "kind": BOX},
	{"name": "Synty_Firepit", "kind": BOX},
	{"name": "Synty_Generator_Cache", "kind": BOX},
	{"name": "Synty_Field_Clinic", "kind": BOX},
	{"name": "Synty_Fish_Camp", "kind": BOX},
	{"name": "Synty_Fuel_Depot", "kind": BOX},
	{"name": "Synty_Road_Blockade", "kind": BOX},
	{"name": "Synty_Radio_Relay", "kind": BOX},
	{"name": "Synty_Refuge_Bedroll", "kind": BOX},
	{"name": "Synty_Rock_Cluster_North", "kind": BOX},
	{"name": "Synty_Rock_Cluster_South", "kind": BOX},
	{"name": "Synty_Rock_Cluster_East", "kind": BOX},
	{"name": "Tool_Shed", "kind": WALLS},
	{"name": "Well_House", "kind": WALLS},
	# A stone ring with posts and a little roof: wall-shaped, and the trimesh
	# band drops the rim and the water while keeping what a walker meets.
	{"name": "Water_Well", "kind": WALLS},
	# Drum, fire and all: nobody needs to walk through the flame to the rim.
	{"name": "Burning_Barrel", "kind": BOX},
	# A knee-high stone ring: a walk-around thing, not a step-onto thing.
	{"name": "Campfire", "kind": BOX},
	# The farmhouse, part by part. Only the four wall groups are solid.
	{"name": "FH_Shell", "kind": WALLS, "openings": [FARMHOUSE_DOOR]},
	{"name": "FH_Fade_Front", "kind": WALLS, "openings": [FARMHOUSE_DOOR]},
	{"name": "FH_Fade_SideLeft", "kind": WALLS},
	{"name": "FH_Fade_Divider", "kind": WALLS},
	{"name": "FH_Fade_Roof", "kind": NONE},
	# The porch posts, rails and steps are left open DELIBERATELY. They stand
	# between the snow and the only door in the game, another agent is making
	# that door work, and a newel post in the wrong place is a house nobody can
	# get into. Walking through a handrail is the cheaper mistake.
	{"name": "FH_Fade_Porch", "kind": NONE},
	{"name": "FH_Porch", "kind": NONE},
	{"name": "FH_Room", "kind": NONE},
	# The interior's business, not this pass's.
	{"name": "FH_Furniture", "kind": NONE},
	{"name": "FH_Door", "kind": NONE},
]

## Ordinary geometric slack, in metres. Small enough not to move a wall, large
## enough that a vertex landing exactly on a clipping plane is not classified
## twice by floating-point noise.
const EPSILON := 0.0001

## Anything thinner than this is a sliver the clip produced, not a surface.
const MIN_TRIANGLE_AREA := 0.000001


## The whole of the public entry point. Walks an imported scene, gives every
## mesh the collision its name declares, and hangs it all off one StaticBody3D.
##
## Returns the number of shapes added, so a caller can report having done
## nothing rather than assume it worked.
##
## ONE BODY PER MODEL, not one per mesh, and it is a sibling of the meshes
## rather than a child of them. The farmhouse's walls are faded to transparent
## by `src/entities/interior/interior_reveal.gd` when the player steps inside --
## which sets `visible = false` at the end of the fade -- and a collider parented
## under a hidden node is a question about Godot's visibility propagation that
## this does not need to ask. A wall you cannot see is still a wall.
static func attach(root: Node) -> int:
	var body: StaticBody3D = null
	var added := 0
	for instance in _mesh_instances(root):
		var built: Array = shapes_for(String(instance.name), instance.mesh)
		if built.is_empty():
			continue
		if body == null:
			body = StaticBody3D.new()
			body.name = "Collision"
			root.add_child(body)
			# NOT OPTIONAL. PackedScene.pack() keeps only nodes whose owner chain
			# reaches the root, so a collider without one is built at import,
			# thrown away when the importer saves the scene, and the world is
			# exactly as hollow as it was -- with nothing anywhere reporting it.
			body.owner = root
		var into_root := _transform_to(instance, root)
		for index in range(built.size()):
			var entry: Dictionary = built[index]
			var collider := CollisionShape3D.new()
			collider.name = "%s_%d" % [instance.name, index]
			collider.shape = entry["shape"]
			collider.transform = into_root * (entry["transform"] as Transform3D)
			body.add_child(collider)
			collider.owner = root
			added += 1
	return added


## The rule for a mesh name, or an empty dictionary when nothing declares it.
static func rule_for(mesh_name: String) -> Dictionary:
	for rule in RULES:
		if mesh_name.begins_with(String(rule["name"])):
			return rule
	return {}


## `[{shape: Shape3D, transform: Transform3D}]`, in the mesh's own space.
static func shapes_for(mesh_name: String, mesh: Mesh) -> Array:
	if mesh == null:
		return []
	var rule := rule_for(mesh_name)
	if rule.is_empty():
		return []
	match rule.get("kind", NONE):
		BOX:
			return _box_shape(mesh)
		TRUNK:
			return _trunk_shape(mesh, float(rule.get("height", 3.0)))
		SWING:
			return _swing_shape(mesh)
		WALLS:
			return _wall_shape(mesh, rule.get("openings", []) as Array,
				float(rule.get("knee", KNEE)), float(rule.get("reach", REACH)))
		_:
			return []


# --- the shapes --------------------------------------------------------------

static func _box_shape(mesh: Mesh) -> Array:
	var box := mesh.get_aabb()
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return []
	var shape := BoxShape3D.new()
	shape.size = box.size
	return [{
		"shape": shape,
		"transform": Transform3D(Basis.IDENTITY, box.position + box.size * 0.5),
	}]


static func _trunk_shape(mesh: Mesh, height: float) -> Array:
	var trunk := trunk_of(mesh.get_faces(), TRUNK_BAND)
	var radius := float(trunk["radius"])
	if radius <= 0.01 or height <= 0.0:
		return []
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var centre: Vector2 = trunk["centre"]
	return [{
		"shape": shape,
		"transform": Transform3D(
			Basis.IDENTITY,
			Vector3(centre.x, float(trunk["base"]) + height * 0.5, centre.y)),
	}]


## The swing is authored with its rope from the AABB top to a tire in the
## lowest fifth. Collide with the visible, kickable tire only; the player can
## still pass by the narrow rope without an exaggerated box collider.
static func _swing_shape(mesh: Mesh) -> Array:
	var box := mesh.get_aabb()
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return []
	var shape := SphereShape3D.new()
	shape.radius = maxf(box.size.x, box.size.z) * 0.5
	var centre := box.get_center()
	centre.y = box.position.y + box.size.y * 0.19
	return [{
		"shape": shape,
		"transform": Transform3D(Basis.IDENTITY, centre),
	}]


static func _wall_shape(mesh: Mesh, openings: Array, knee: float, reach: float) -> Array:
	var faces := standing_faces(mesh.get_faces(), knee, reach)
	for opening in openings:
		faces = subtract_box(faces, opening as AABB)
	if faces.size() < 3:
		return []
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# A wall is a wall from both sides, and a concave shape has no inside to
	# infer one from. Off, which is the default, means a body that ends up on
	# the wrong side of a face passes straight through it -- and the player's Y
	# is assigned rather than simulated, so ending up on the wrong side is a
	# thing that can happen.
	shape.backface_collision = true
	return [{"shape": shape, "transform": Transform3D.IDENTITY}]


# --- the geometry, all pure --------------------------------------------------

## Where the trunk is and how thick it is: `{base, centre, radius}`.
##
## `base` is the lowest vertex in the model -- trees are modelled with their
## roots below their origin and the pole is buried 0.45 m -- `centre` is the XZ
## middle of the base band and `radius` reaches the furthest vertex in it.
static func trunk_of(faces: PackedVector3Array, band: float) -> Dictionary:
	var empty := {"base": 0.0, "centre": Vector2.ZERO, "radius": 0.0}
	if faces.is_empty():
		return empty
	var base := INF
	for vertex in faces:
		base = minf(base, vertex.y)
	var ceiling := base + band
	var centre := Vector2.ZERO
	var count := 0
	for vertex in faces:
		if vertex.y > ceiling:
			continue
		centre += Vector2(vertex.x, vertex.z)
		count += 1
	if count == 0:
		return empty
	centre /= float(count)
	var radius := 0.0
	for vertex in faces:
		if vertex.y > ceiling:
			continue
		radius = maxf(radius, Vector2(vertex.x, vertex.z).distance_to(centre))
	return {"base": base, "centre": centre, "radius": radius}


## The triangles that can stop a walker: everything except what lies wholly
## under `floor_y` or wholly over `ceiling_y`.
##
## Whole triangles, not clipped ones. A wall is kept at its full height rather
## than trimmed to the band, because trimming would leave a gap under every wall
## in the game and under a wall is exactly where a walker's feet are.
static func standing_faces(faces: PackedVector3Array, floor_y: float, ceiling_y: float) -> PackedVector3Array:
	var kept := PackedVector3Array()
	for index in range(0, faces.size() - 2, 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		if maxf(a.y, maxf(b.y, c.y)) <= floor_y:
			continue
		if minf(a.y, minf(b.y, c.y)) >= ceiling_y:
			continue
		kept.append(a)
		kept.append(b)
		kept.append(c)
	return kept


## The soup with everything inside `box` cut away.
##
## Clipped rather than filtered, and that is the whole point. The farmhouse's
## front wall is a single `block()` -- twelve triangles for the entire facade --
## so "drop the triangles that overlap the doorway" removes half the front of
## the house, and "drop the triangles whose centre is in the doorway" removes
## nothing at all. Each triangle is split against the six planes of the box; the
## part outside any of them is kept, and what survives all six was inside the
## box and is dropped.
static func subtract_box(faces: PackedVector3Array, box: AABB) -> PackedVector3Array:
	var kept := PackedVector3Array()
	var planes := _outward_planes(box)
	for index in range(0, faces.size() - 2, 3):
		var triangle := PackedVector3Array([faces[index], faces[index + 1], faces[index + 2]])
		var bounds := AABB(triangle[0], Vector3.ZERO).expand(triangle[1]).expand(triangle[2])
		if not box.intersects(bounds):
			kept.append_array(triangle)
			continue
		var pending: Array = [triangle]
		for plane in planes:
			var still_inside: Array = []
			for polygon in pending:
				var halves := _split(polygon as PackedVector3Array, plane as Plane)
				_fan(halves[0] as PackedVector3Array, kept)
				var inside: PackedVector3Array = halves[1]
				if inside.size() >= 3:
					still_inside.append(inside)
			pending = still_inside
			if pending.is_empty():
				break
	return kept


## The six half-spaces of a box, oriented so that a positive distance means
## OUTSIDE the box on that side.
static func _outward_planes(box: AABB) -> Array:
	var low := box.position
	var high := box.end
	return [
		Plane(Vector3(-1.0, 0.0, 0.0), -low.x),
		Plane(Vector3(1.0, 0.0, 0.0), high.x),
		Plane(Vector3(0.0, -1.0, 0.0), -low.y),
		Plane(Vector3(0.0, 1.0, 0.0), high.y),
		Plane(Vector3(0.0, 0.0, -1.0), -low.z),
		Plane(Vector3(0.0, 0.0, 1.0), high.z),
	]


## Sutherland-Hodgman, returning BOTH halves: `[outside, inside]`.
##
## A vertex within EPSILON of the plane goes into both, which is what keeps a
## polygon lying exactly in a clipping plane from being classified by rounding.
## Vertex order is preserved, so the winding -- and with it every triangle's
## normal -- survives the clip.
static func _split(polygon: PackedVector3Array, plane: Plane) -> Array:
	var outside := PackedVector3Array()
	var inside := PackedVector3Array()
	var count := polygon.size()
	for index in range(count):
		var here := polygon[index]
		var next := polygon[(index + 1) % count]
		var here_distance := plane.distance_to(here)
		var next_distance := plane.distance_to(next)
		if here_distance >= -EPSILON:
			outside.append(here)
		if here_distance <= EPSILON:
			inside.append(here)
		var crosses := (here_distance > EPSILON and next_distance < -EPSILON) \
			or (here_distance < -EPSILON and next_distance > EPSILON)
		if crosses:
			var crossing := here.lerp(next, here_distance / (here_distance - next_distance))
			outside.append(crossing)
			inside.append(crossing)
	return [outside, inside]


## A convex polygon appended to a soup as a triangle fan, skipping slivers.
static func _fan(polygon: PackedVector3Array, into: PackedVector3Array) -> void:
	if polygon.size() < 3:
		return
	for index in range(1, polygon.size() - 1):
		var a := polygon[0]
		var b := polygon[index]
		var c := polygon[index + 1]
		if (b - a).cross(c - a).length() * 0.5 < MIN_TRIANGLE_AREA:
			continue
		into.append(a)
		into.append(b)
		into.append(c)


# --- walking the imported scene ----------------------------------------------

static func _mesh_instances(node: Node, found: Array = []) -> Array:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		_mesh_instances(child, found)
	return found


## The node's transform expressed in the root's space.
##
## Multiplied up the parent chain rather than read off `global_transform`: the
## scene an `EditorScenePostImport` is handed is not in a tree, and a global
## transform outside one is a question with no reliable answer.
static func _transform_to(node: Node3D, root: Node) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		if walk is Node3D:
			combined = (walk as Node3D).transform * combined
		walk = walk.get_parent()
	return combined
