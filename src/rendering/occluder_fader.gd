extends Node

## Autoload "OccluderFader". Whatever stands between the camera and the player
## gets out of the way.
##
## ---------------------------------------------------------------------------
## THE RULE
## ---------------------------------------------------------------------------
## The camera casts a ray at the player, every frame. Whatever the ray is
## blocked by fades. That is the whole design, in the owner's words, and two
## things follow from it that are easy to get wrong:
##
##   * IT IS AIMED AT HIS BODY, NOT HIS FEET. The character's origin is at his
##     ankles -- the one part of him whose being covered nobody minds and whose
##     being clear proves nothing. The ray goes to the top of his chest.
##   * EVERY OBJECT THE RAY PASSES THROUGH FADES, not only the nearest. A fence
##     standing in front of the house means both are between the camera and the
##     player; a first-hit-only query fades the fence and leaves the house solid
##     on top of him.
##
## ---------------------------------------------------------------------------
## WHAT THE RAY IS CAST AGAINST, AND WHY IT IS NOT THE WORLD'S COLLISION
## ---------------------------------------------------------------------------
## `62faacf` generated every model's collision at import, and it generated it
## for WALKING INTO THINGS. That is a different question from "is this hiding
## him", and the differences were measured rather than assumed -- see
## `.superpowers/sdd/wave2/task-w2-fade-report.md` for the maps:
##
##   * A BUILDING'S COLLISION IS ITS WALLS BETWEEN THE KNEE AND THE REACH, with
##     the doorway cut out and the porch and the roof left off entirely. The
##     roof is the largest thing a farmhouse draws and, from a camera pitched 45
##     degrees, the thing that actually hides the player -- it is what he is
##     standing inside of in the approved shot. A ray against the walls alone
##     misses 32% of the positions where the house genuinely covers him, and
##     misses them in a SPECKLE -- over the wall band, through the missing roof,
##     back onto a partition -- so the fade would chatter as he walked.
##   * A TREE'S COLLISION IS A VERTICAL CYLINDER ON ITS FOOT. That was the right
##     call for walking and it is nearly right here -- a bare crown is thin
##     branches and hides nobody, so the trunk is what should fade a tree. But
##     THE TRUNKS LEAN, and the cylinder was measured from the vertices within
##     15 cm of the model's lowest point. Measured on the models on disk, the
##     drawn trunk has walked 0.51 m off that axis by chest height on
##     `tree_bare_d`, 0.61 m on another copy of it, 1.10 m by 2 m up on
##     `tree_bare_a` -- against cylinder radii of 0.26 and 0.30. The invisible
##     trunk is a whole trunk-width away from the visible one, so the fade fires
##     while the player is beside the tree and holds while he is clear of it.
##
## So this system builds its own occlusion proxies, once, at discovery, on a
## physics layer nothing else uses, and casts against those. Three rules and no
## more, each keyed off what the model's own collision already declares:
##
##   collision is a TRIANGLE SOUP -> the proxy is what the building DRAWS.
##       The soup is a clipped copy of the geometry; the geometry itself is the
##       silhouette, roof and porch included.
##   collision is a CYLINDER      -> the proxy FOLLOWS THE DRAWN TRUNK up from
##       the foot, band by band, at the radius the cylinder declares. The
##       cylinder's judgement -- "this thing is mostly air, only the trunk
##       counts" -- is kept; only its assumption that the trunk is vertical is
##       thrown away.
##   anything else (a BOX)        -> kept exactly as it is. A vehicle's box and
##       a fence panel's box already equal the drawn bounds, and the panel box
##       usefully closes the gaps between pickets that a ray would otherwise
##       thread on some frames and not others.
##
## ---------------------------------------------------------------------------
## THE OCCLUDER FADES. THE CHARACTER DOES NOT.
## ---------------------------------------------------------------------------
## The first attempt did the opposite -- it drew the character through the
## occluder as a translucent silhouette -- and the owner ruled it backwards on
## sight: fading the man is the one thing that cannot achieve "I can still see
## my guy". Nothing here writes to the character. He stays fully opaque and
## exactly as he was.
##
## What he *keeps* is a separate effect that happens to share a mechanism: the
## part of his boots below the snow surface reads translucent pale blue, because
## `PlayerController` sinks the body into the snow and his material carries a
## stencil x-ray (`CharacterScheme.wear_ghost`). That one is wanted and is
## untouched here. It survives because the ground is never an occluder unit --
## see `units_in()`.
##
## ---------------------------------------------------------------------------
## THE WHOLE OBJECT, UNIFORMLY, AND THE LOOK IS APPROVED
## ---------------------------------------------------------------------------
## No window is cut around the character's screen position. The entire building,
## the entire tree, the entire run of fence fades as one, to one flat `#16181C`
## tint at 0.55 with a depth prepass, and `shots/fade-behind-house.png` is the
## picture. **None of that changed in this task** -- what changed is when it
## fires, how it moves, and how it hands the farmhouse over to InteriorReveal.
##
## ---------------------------------------------------------------------------
## HOW THE FADE IS DRAWN, AND WHY IT IS TWO PHASES
## ---------------------------------------------------------------------------
##     amount 0.0 .. 0.5   the object itself, transparency 0 -> 1
##     amount 0.5 .. 1.0   the flat tint,     opacity      0 -> tint alpha
##
## The crossover is AT FULL TRANSPARENCY, where the object is invisible and the
## swap cannot be seen. The tint is drawn with a depth prepass so a hollow
## building fades as one shape rather than as forty stacked panels -- see
## `tint_material()`.

const SETTINGS_PATH := "res://data/rendering/occluder_fade.tres"
const FADE_SHADER_PATH := "res://assets/shaders/occluder_fade.gdshader"

## The physics layer the occlusion proxies live on, and the only layer this
## system queries. A high bit on purpose: it is not a gameplay layer, nothing
## else may put anything on it, and querying it cannot pick up the player's own
## body or the walk collision this system deliberately does not use.
const OCCLUSION_LAYER := 1 << 19

## How many objects deep the ray is followed. Every one of them fades; this is
## only the guard against a pathological scene.
const MAX_HITS := 8

## A one-sample edge hit is not evidence that a whole object changed state.
## Two 20 Hz samples add at most 50 ms after the first observation and prevent
## a thin wall/character-edge intersection from repeatedly reversing a fade.
const ENTER_CONFIRMATION_SAMPLES := 2
const EXIT_CONFIRMATION_SAMPLES := 2

## How finely the drawn trunk is followed. Small enough to catch the lean,
## large enough that a 600-triangle tree is one cheap pass at startup.
const TRUNK_BAND := 0.4


## Who is being kept visible. Resolved through the ServiceRegistry, the same way
## CameraRig and InteriorReveal find him.
@export var subject_service: StringName = &"player"

## Fallbacks for the subject's size, used only when it publishes neither.
@export var subject_height := 1.9
@export var subject_radius := 0.3

## Physics occlusion is sampled independently of render FPS.  Twenty hertz is
## faster than the authored fade gesture can reveal a new result, but bounds a
## 120/240 Hz machine to the same query cost as a 60 Hz one.  A stationary
## camera/subject pair reuses the exact result indefinitely.
@export_range(15.0, 20.0, 1.0) var occlusion_sample_hz := 20.0
@export var occlusion_motion_epsilon_m := 0.005
@export var occlusion_teleport_m := 1.0

var _settings: OccluderFadeSettings
var _tint: Material
var _subject: Node3D
var _registry: Node
var _scene: Node = null
var _units: Array = []
var _bounds: Dictionary = {}
var _meshes: Dictionary = {}
var _unit_of: Dictionary = {}
var _span: Dictionary = {}
var _proxies: Node3D = null
var _by_rid: Dictionary = {}
var _fade: Dictionary = {}
var _target: Dictionary = {}
var _tween: Dictionary = {}
var _release_at: Dictionary = {}
var _requests: Dictionary = {}
var _clock := 0.0
var _occlusion_sample_elapsed := 0.0
var _has_occlusion_sample := false
var _last_occlusion_camera := Transform3D.IDENTITY
var _last_occlusion_aim := Vector3.ZERO
var _cached_blocked: Dictionary = {}
var _stable_blocked: Dictionary = {}
var _hit_streak: Dictionary = {}
var _clear_streak: Dictionary = {}
var _occlusion_query_count := 0


func _ready() -> void:
	_settings = load(SETTINGS_PATH) as OccluderFadeSettings
	if _settings == null:
		# Never silently: with no settings every occluder stays solid and the
		# character goes on disappearing, which looks exactly like this file
		# not existing.
		push_warning("occluder_fader: no settings at %s, run tools/generate_occluder_fade.gd" % SETTINGS_PATH)
		_settings = OccluderFadeSettings.new()


func settings() -> OccluderFadeSettings:
	if _settings == null:
		_settings = load(SETTINGS_PATH) as OccluderFadeSettings
	if _settings == null:
		_settings = OccluderFadeSettings.new()
	return _settings


# --- the occluders ------------------------------------------------------------

## Every occluder unit under `root`, skipping anything inside `exclude`.
##
## A unit is ONE OBJECT, and the engine already knows what that means:
## `scene_file_path` is set on the root of an instanced scene and nowhere else.
## So each `.glb` placed in `scenes/main.tscn` is a unit -- the whole farmhouse,
## the whole tree, the tire swing hanging off it -- and the terrain, which is a
## script on a MeshInstance3D rather than an instance of anything, is not.
##
## THE ONE EXCEPTION IS A ROW. `Farmstead` builds the fence out of twenty-two
## instances of one panel, and fading a single panel out of the middle of a run
## is precisely the patchwork the owner ruled out. So a node whose Node3D
## children are ALL instances of the SAME scene is itself the unit. "All", not
## "some": the farmstead holds three copies of `tree_bare_c.glb` among a dozen
## other things, and collapsing on "some" would make the entire farmstead one
## object that fades whenever the player steps behind any part of it.
static func units_in(root: Node, exclude: Node) -> Array:
	var found: Array = []
	_collect(root, exclude, found)
	return found


static func _collect(node: Node, exclude: Node, found: Array) -> void:
	for child in node.get_children():
		if child == exclude:
			continue
		# A boot/main wrapper may instance the whole world. Treating that wrapper
		# as one occluder makes every mesh below it -- including the player -- one
		# fade unit. Walk through the ancestor until the excluded subject has been
		# cut out, then resume ordinary unit discovery around it.
		if exclude != null and child.is_ancestor_of(exclude):
			_collect(child, exclude, found)
			continue
		if not (child is Node3D):
			_collect(child, exclude, found)
			continue
		if _is_row(child):
			found.append(child)
			continue
		if String(child.scene_file_path) != "":
			found.append(child)
			continue
		_collect(child, exclude, found)


static func _is_row(node: Node) -> bool:
	if String(node.scene_file_path) != "":
		return false
	var scene := ""
	var count := 0
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var path := String(child.scene_file_path)
		if path == "":
			return false
		if scene == "":
			scene = path
		elif path != scene:
			return false
		count += 1
	return count >= 2


static func meshes_of(unit: Node, found: Array = []) -> Array:
	if unit is MeshInstance3D:
		found.append(unit)
	for child in unit.get_children():
		meshes_of(child, found)
	return found


## Every enabled CollisionShape3D under `unit`, as `{shape, transform}` in the
## UNIT's own space -- `global_transform` is not answerable for a node outside a
## tree, which is where every test builds its subjects.
static func colliders_of(unit: Node) -> Array:
	var found: Array = []
	if unit is CollisionShape3D:
		_add_collider(unit as CollisionShape3D, Transform3D.IDENTITY, found)
	for child in unit.get_children():
		_walk_colliders(child, Transform3D.IDENTITY, found)
	return found


static func _walk_colliders(node: Node, into: Transform3D, found: Array) -> void:
	var here := into
	if node is Node3D:
		here = into * (node as Node3D).transform
	if node is CollisionShape3D:
		_add_collider(node as CollisionShape3D, here, found)
	for child in node.get_children():
		_walk_colliders(child, here, found)


static func _add_collider(collider: CollisionShape3D, into: Transform3D, found: Array) -> void:
	if collider.disabled or collider.shape == null:
		return
	found.append({"shape": collider.shape, "transform": into})


## The bounds of what a unit declares solid, in its own space. Kept because the
## SIZE of an occluder decides how its fade moves -- see `duration_for()`.
static func solid_bounds(unit: Node) -> Array:
	var found: Array = []
	for entry in colliders_of(unit):
		var local := _shape_bounds(entry["shape"] as Shape3D)
		if local.size == Vector3.ZERO:
			continue
		found.append((entry["transform"] as Transform3D) * local)
	return found


static func _shape_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return AABB(
			Vector3(-cylinder.radius, -cylinder.height * 0.5, -cylinder.radius),
			Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0))
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return AABB(
			Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius),
			Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0))
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	if shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
		if faces.is_empty():
			return AABB()
		var bounds := AABB(faces[0], Vector3.ZERO)
		for vertex in faces:
			bounds = bounds.expand(vertex)
		return bounds
	return AABB()


# --- the occlusion proxy ------------------------------------------------------

enum { PROXY_NONE, PROXY_DRAWN, PROXY_TRUNK, PROXY_KEEP }

## Which of the three rules at the top of this file a unit falls under, read off
## the collision it already carries.
static func proxy_kind(shapes: Array) -> int:
	if shapes.is_empty():
		return PROXY_NONE
	for entry in shapes:
		if (entry["shape"] as Shape3D) is ConcavePolygonShape3D:
			return PROXY_DRAWN
	for entry in shapes:
		if (entry["shape"] as Shape3D) is CylinderShape3D:
			return PROXY_TRUNK
	return PROXY_KEEP


## Every triangle a unit draws, in the unit's own space.
static func drawn_faces(unit: Node) -> PackedVector3Array:
	var found := PackedVector3Array()
	for entry in meshes_of(unit):
		var mesh := entry as MeshInstance3D
		if mesh.mesh == null:
			continue
		var into := relative_to(unit, mesh)
		for vertex in mesh.mesh.get_faces():
			found.append(into * vertex)
	return found


## The transform from `node`'s own space out to `root`'s, composed by walking
## the parent chain. `global_transform` is the obvious call and the wrong one:
## it asserts `is_inside_tree()` and returns IDENTITY when that fails, which is
## every unit test.
static func relative_to(root: Node, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var walk := node
	while walk != null and walk != root:
		chain = walk.transform * chain
		walk = walk.get_parent() as Node3D
	return chain


## Follow the drawn trunk up from `base`, band by band, and return the line it
## actually takes.
##
## THE POINT OF THIS FUNCTION, in one sentence: the import-time collision put a
## VERTICAL cylinder under a trunk that leans, so by chest height the invisible
## trunk and the visible one are a trunk-width apart, and the fade fires beside
## the tree instead of behind it.
##
## The walk is deliberately dumb and local. At each band it takes the drawn
## cross-section nearest to where the trunk was in the band below, then averages
## everything within a couple of radii of that -- so a branch leaving the trunk
## cannot drag the line off it, and a band with nothing near enough ends the
## walk rather than jumping to the far side of the crown.
##
## The cross-section is taken by intersecting the mesh's EDGES with the band's
## plane, not by collecting vertices near it: a trunk modelled as a few long
## quads has no vertices at all through most of its length, and a vertex-based
## scan finds nothing and silently falls back.
static func trunk_path(
		faces: PackedVector3Array, base: Vector3, radius: float, top: float,
		band := TRUNK_BAND) -> PackedVector3Array:
	var path := PackedVector3Array([base])
	if top <= 0.0 or band <= 0.0 or faces.size() < 3:
		return path
	var steps := int(ceil(top / band))
	# Plain Arrays, not PackedVector2Array: a packed array read back out of an
	# Array is a copy, so `cuts[level].append(...)` would append to a temporary
	# and every band would come back empty.
	var cuts: Array = []
	for _index in range(steps):
		cuts.append([])
	var index := 0
	while index + 2 < faces.size():
		for corner in range(3):
			var a: Vector3 = faces[index + corner]
			var b: Vector3 = faces[index + (corner + 1) % 3]
			if is_equal_approx(a.y, b.y):
				continue
			var low := minf(a.y, b.y)
			var high := maxf(a.y, b.y)
			var first := int(ceil((low - base.y) / band - 1.0))
			var last := int(floor((high - base.y) / band - 1.0))
			for level in range(maxi(first, 0), mini(last, steps - 1) + 1):
				var height := base.y + band * float(level + 1)
				var along := (height - a.y) / (b.y - a.y)
				var at: Vector3 = a + (b - a) * along
				(cuts[level] as Array).append(Vector2(at.x, at.z))
		index += 3
	var here := Vector2(base.x, base.z)
	for level in range(steps):
		var centre = _trunk_centre(cuts[level], here, radius, band)
		if centre == null:
			break
		here = centre
		path.append(Vector3(here.x, base.y + band * float(level + 1), here.y))
	return path


static func _trunk_centre(points: Array, here: Vector2, radius: float, band: float):
	if points.is_empty():
		return null
	var nearest: Vector2 = points[0]
	for point in points:
		if (point as Vector2).distance_squared_to(here) < nearest.distance_squared_to(here):
			nearest = point
	# Past this the walk has lost the trunk -- it is above the top of it, or the
	# only thing at this height is a branch on the far side of the crown.
	if nearest.distance_to(here) > maxf(radius * 4.0, band * 2.0):
		return null
	# The MIDDLE OF THE EXTENT, not the mean of the points. A mesh is triangulated
	# however it happens to be triangulated, and the mean drifts toward whichever
	# side carries more edges -- measured at 22% of a trunk's width on a plain
	# four-sided prism, which is a systematic lean the model does not have.
	var reach := maxf(radius * 2.0, 0.15)
	var low := Vector2.INF
	var high := -Vector2.INF
	for point in points:
		if (point as Vector2).distance_to(nearest) > reach:
			continue
		low = low.min(point)
		high = high.max(point)
	if low.x > high.x:
		return null
	return (low + high) * 0.5


## A basis whose Y runs along `direction`, so a capsule can be laid along a
## leaning trunk.
static func basis_along(direction: Vector3) -> Basis:
	var up := direction.normalized()
	if up.is_zero_approx():
		return Basis.IDENTITY
	var reference := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var side := reference.cross(up).normalized()
	return Basis(side, up, side.cross(up))


## The shapes this unit occludes with, as `{shape, transform}` in its own space.
## Pure, so the three rules can be tested without a scene or a physics world.
static func proxy_shapes(unit: Node) -> Array:
	var collision := colliders_of(unit)
	var kind := proxy_kind(collision)
	if kind == PROXY_NONE:
		return []
	if kind == PROXY_DRAWN:
		var soup := ConcavePolygonShape3D.new()
		soup.set_faces(drawn_faces(unit))
		if soup.get_faces().is_empty():
			return collision
		return [{"shape": soup, "transform": Transform3D.IDENTITY}]
	if kind != PROXY_TRUNK:
		return collision
	var faces := drawn_faces(unit)
	var built: Array = []
	for entry in collision:
		var cylinder := entry["shape"] as CylinderShape3D
		if cylinder == null:
			built.append(entry)
			continue
		var placed: Transform3D = entry["transform"]
		var base: Vector3 = placed * Vector3(0.0, -cylinder.height * 0.5, 0.0)
		var path := trunk_path(faces, base, cylinder.radius, cylinder.height)
		if path.size() < 2:
			built.append(entry)
			continue
		for step in range(path.size() - 1):
			var from: Vector3 = path[step]
			var to: Vector3 = path[step + 1]
			var along := to - from
			var length := along.length()
			if length < 0.0001:
				continue
			var capsule := CapsuleShape3D.new()
			capsule.radius = cylinder.radius
			# The caps overlap the joint on purpose: a chain of capsules with
			# flat ends would leave a seam the ray could pass through.
			capsule.height = length + cylinder.radius * 2.0
			built.append({
				"shape": capsule,
				"transform": Transform3D(basis_along(along), from + along * 0.5),
			})
	return built if not built.is_empty() else collision


# --- the decision -------------------------------------------------------------

## Where on the character the ray is aimed. Not his origin: see `aim_height` in
## the settings.
func aim_point(subject: Node3D) -> Vector3:
	var height: float = subject.get("body_height") if subject.get("body_height") != null else subject_height
	# relative_to, not global_position: `global_position` asserts is_inside_tree()
	# and prints an engine ERROR when it is not, which the suite's pristine-output
	# rule turns into a failure a long way from its cause.
	return relative_to(null, subject).origin + Vector3(0.0, height * settings().aim_height, 0.0)


## Every unit the camera's ray to `at` passes through, recomputed from nothing.
##
## THERE IS NO REMOVAL PATH, AND THAT IS THE DESIGN. The blocking set is built
## fresh every frame; anything in last frame's set that is not in this one is
## simply not in this one. A system that added on a hit and removed on some
## other condition is a system whose removal path can be wrong -- which is
## exactly what "it stays faded after I have walked clear" is a symptom of.
##
## Every hit along the ray, not just the nearest: the query is repeated with
## each body it found excluded, so a fence in front of a house fades both.
func blocking_units(camera: Camera3D, at: Vector3) -> Dictionary:
	var found: Dictionary = {}
	var world := get_viewport().world_3d if get_viewport() != null else null
	if camera == null or world == null:
		return found
	var space := world.direct_space_state
	if space == null:
		return found
	var from := camera.project_ray_origin(camera.unproject_position(at))
	var exclude: Array[RID] = []
	for _step in range(MAX_HITS):
		var query := PhysicsRayQueryParameters3D.create(from, at, OCCLUSION_LAYER, exclude)
		query.hit_back_faces = true
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var unit = _by_rid.get(hit["rid"])
		if unit != null:
			found[unit] = true
		exclude.append(hit["rid"])
	return found


## Whether the exact ray stack needs refreshing this frame.  The game uses an
## orthographic camera, so rotation matters as well as camera origin: it moves
## the ray's projected origin even when the camera has not translated.
func occlusion_sample_due(
		delta: float, camera_transform: Transform3D, at: Vector3) -> bool:
	_occlusion_sample_elapsed += maxf(delta, 0.0)
	if not _has_occlusion_sample:
		_store_occlusion_sample(camera_transform, at)
		return true
	var camera_distance := camera_transform.origin.distance_to(_last_occlusion_camera.origin)
	var aim_distance := at.distance_to(_last_occlusion_aim)
	var teleported := maxf(camera_distance, aim_distance) >= maxf(occlusion_teleport_m, 0.0)
	var rotated := not camera_transform.basis.is_equal_approx(_last_occlusion_camera.basis)
	var moved := maxf(camera_distance, aim_distance) >= maxf(occlusion_motion_epsilon_m, 0.0)
	var interval := 1.0 / maxf(occlusion_sample_hz, 0.001)
	if not teleported and (_occlusion_sample_elapsed < interval or (not moved and not rotated)):
		return false
	_store_occlusion_sample(camera_transform, at)
	return true


func _store_occlusion_sample(camera_transform: Transform3D, at: Vector3) -> void:
	_has_occlusion_sample = true
	_occlusion_sample_elapsed = 0.0
	_last_occlusion_camera = camera_transform
	_last_occlusion_aim = at


func reset_occlusion_sampling() -> void:
	_has_occlusion_sample = false
	_occlusion_sample_elapsed = 0.0
	_cached_blocked.clear()
	_stable_blocked.clear()
	_hit_streak.clear()
	_clear_streak.clear()
	_occlusion_query_count = 0


## Debounced membership of one occluder. Entry and release both need two
## consecutive physics samples, so an edge hit cannot start a fade and an edge
## miss cannot reverse one. The authored time dwell remains the final release
## cushion after this geometric confirmation.
func confirmed_occlusion(unit: Object, observed: bool) -> bool:
	if unit == null:
		return false
	if observed:
		_hit_streak[unit] = int(_hit_streak.get(unit, 0)) + 1
		_clear_streak[unit] = 0
		if int(_hit_streak[unit]) >= ENTER_CONFIRMATION_SAMPLES:
			_stable_blocked[unit] = true
	else:
		_clear_streak[unit] = int(_clear_streak.get(unit, 0)) + 1
		_hit_streak[unit] = 0
		if int(_clear_streak[unit]) >= EXIT_CONFIRMATION_SAMPLES:
			_stable_blocked.erase(unit)
	return _stable_blocked.has(unit)


func occlusion_query_count() -> int:
	return _occlusion_query_count


# --- how it moves -------------------------------------------------------------

## The curve, by size, and NOTHING HERE OVERSHOOTS.
##
## The owner asked for the feel in DOTween's terms and named elastic. DOTween is
## a Unity library and Godot's Tween covers the same ground -- TRANS_ELASTIC and
## TRANS_BACK are both right there. I am not using either, anywhere, and this is
## the reasoning rather than a preference:
##
## An overshoot on a POSITION reads as weight arriving. An overshoot on an ALPHA
## cannot, because alpha has hard ends. TRANS_BACK on a 0 -> 1 fade pushes the
## value past 1, where it clamps -- so the object reaches full fade early and
## sits there, and then the curve comes BACK down below 1 and the silhouette
## briefly goes solid again. That is not a spring, it is a pulse, and it reads
## as the renderer glitching. The same at the other end. There is no version of
## it that is bouncy rather than broken.
##
## So the motion is scaled to the object by DURATION and by the shape of the
## ease instead:
##
##   large -- a building, a truck, a run of fence -- CUBIC, slower. Gentle in
##       the middle as well as at the ends. A house is heavy and must look it,
##       and it may not wobble at all.
##   small -- a trunk, a post, a single panel -- QUART, quicker. Sharper through
##       the middle, which is where "a little life" lives once overshoot is off
##       the table.
##
## BOTH ARE EASE_IN_OUT, and that is not laziness. EASE_OUT was tried first for
## the small objects on the reasoning that a light thing should leave hard, and
## a frame sequence of it is the complaint again: quint-out puts 95% of the fade
## in the first 45% of the time, so the picture flips and then the last of it
## creeps. A soft departure is most of what separates an eased transition from a
## state change, at every size.
static func curve_for(metres: float, large_metres: float) -> Tween.TransitionType:
	return Tween.TRANS_CUBIC if metres >= large_metres else Tween.TRANS_QUART


static func ease_for(_metres: float, _large_metres: float) -> Tween.EaseType:
	return Tween.EASE_IN_OUT


## How long a move of `distance` takes on an object `metres` across.
##
## Scaled by the distance actually travelled, so A REVERSAL CAUGHT HALFWAY TAKES
## HALF THE TIME rather than crawling back over the full duration. Together with
## starting every new tween from the CURRENT value -- see `_start()` -- that is
## what makes walking behind a tree and straight back out turn around smoothly
## instead of snapping.
static func duration_for(
		distance: float, metres: float, large_metres: float,
		small: float, large: float) -> float:
	var whole := large if metres >= large_metres else small
	return whole * clampf(absf(distance), 0.0, 1.0)


# --- applying it --------------------------------------------------------------

## How much of what is being drawn reaches the screen, at a given point in the
## fade. Zero at the crossover from BOTH sides, which is what makes the swap
## from the object to its silhouette invisible.
static func visible_opacity(fade: float, tint_alpha: float) -> float:
	if fade <= 0.5:
		return 1.0 - fade * 2.0
	return (fade - 0.5) * 2.0 * tint_alpha


## `amount` 0 is untouched, 1 is a flat translucent silhouette.
func apply_fade(meshes: Array, amount: float) -> void:
	for entry in meshes:
		if entry is GeometryInstance3D:
			paint(entry as GeometryInstance3D, amount, removal_of(entry))


## THE ONE PLACE ANY OF THIS IS WRITTEN, for every system that has an opinion
## about a mesh. See `request_removal()` for why there is only one.
##
##   amount   this system's own fade: 0 solid, 0.5 invisible, 1 flat silhouette
##   gone     what another system is removing, 0..1, applied on top
##
## At `amount` 0 the composite is exactly `transparency = gone`, which is
## byte-for-byte what InteriorReveal wrote for itself before it handed the
## write over -- so routing it through here changed no picture at all.
func paint(instance: GeometryInstance3D, amount: float, gone: float) -> void:
	var fade := clampf(amount, 0.0, 1.0)
	var removed := clampf(gone, 0.0, 1.0)
	if fade <= 0.0 and removed <= 0.0:
		instance.material_override = null
		instance.transparency = 0.0
		instance.set_instance_shader_parameter(&"fade_opacity", 1.0)
	elif fade <= 0.5:
		instance.material_override = null
		instance.transparency = maxf(fade * 2.0, removed)
	else:
		instance.material_override = tint_material()
		instance.transparency = 0.0
		# NOT `transparency`: assets/shaders/occluder_fade.gdshader assigns ALPHA
		# itself, which overwrites whatever the instance asked for. The removal
		# has to ride the shader's own instance uniform.
		instance.set_instance_shader_parameter(
			&"fade_opacity", visible_opacity(fade, settings().tint.a) * (1.0 - removed))


## One material for every faded object in the frame: the fade is one flat tint,
## so there is nothing to vary per object.
##
## `assets/shaders/occluder_fade.gdshader` rather than the world's cel shader,
## and the reason is written out there: a faded occluder that still writes depth
## still hides the character, so the fade has to be a real transparent pass with
## `depth_draw_never` rather than the cel shader turned down.
func tint_material() -> Material:
	if _tint != null:
		return _tint
	var colour := ShaderMaterial.new()
	colour.shader = load(FADE_SHADER_PATH)
	var tint: Color = settings().tint
	colour.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
	colour.render_priority = 0

	# THE DEPTH PREPASS, and it is what makes a faded building ONE shape rather
	# than forty transparent panels stacked on each other. Without it the faded
	# farmhouse shows its own insides -- floor joists, partitions and the far
	# roof plane compositing through the near one, three and four layers deep,
	# which is what alpha blending does to a hollow object.
	#
	# `render_priority` is the part that is easy to miss. The farmhouse is nine
	# separate meshes and Godot draws a transparent object's passes back to
	# back, so without this the second mesh's depth would be written after the
	# first mesh's colour and cull nothing.
	_tint = StandardMaterial3D.new()
	_tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tint.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_tint.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_tint.render_priority = -1
	_tint.next_pass = colour
	return _tint


# --- one owner for a mesh's alpha ---------------------------------------------

## Another system asking for a mesh to be removed, 0..1.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS: TWO SYSTEMS USED TO FADE THE FARMHOUSE
## ---------------------------------------------------------------------------
## `InteriorReveal` takes the roof and the front wall off when the player steps
## inside; this system fades the whole building when it stands in his way. They
## did not fight -- the fader stood down as soon as the reveal opened -- but at
## the handover the house played briefly TOWARD SOLID while the reveal was still
## lifting the roof, which is a visible pop at the exact dramatic beat the
## reveal exists to serve.
##
## So there is one writer now, and it is `paint()`. The reveal publishes a
## number here instead of writing `transparency` itself.
##
## AND `max()` ALONE IS NOT ENOUGH, which is worth writing down because it looks
## like it should be: the max of a FALLING ramp and a RISING one dips at the
## crossing. Releasing over 0.26 s against a reveal rising over 0.30 s, the
## composite falls to about 0.27 before it climbs again -- the house comes 60%
## of the way back to solid mid-handover. The fix is the other half of
## `_process()`: **a unit is not released while another system's request for it
## is part way in.** It holds where it is, the reveal fades it out from there,
## and only once that request is complete does this system let go of the rest of
## the building. The composite is then monotone by construction.
func request_removal(instance: GeometryInstance3D, source: Object, amount: float) -> bool:
	if instance == null or not is_instance_valid(instance):
		return false
	var per: Dictionary = _requests.get(instance, {})
	var wanted := clampf(amount, 0.0, 1.0)
	if wanted <= 0.0:
		per.erase(source)
	else:
		per[source] = wanted
	if per.is_empty():
		_requests.erase(instance)
	else:
		_requests[instance] = per
	var unit = _unit_of.get(instance)
	paint(instance, _fade.get(unit, 0.0), removal_of(instance))
	return true


func removal_of(instance: GeometryInstance3D) -> float:
	var per: Dictionary = _requests.get(instance, {})
	var most := 0.0
	for source in per:
		most = maxf(most, float(per[source]))
	return most


## Is another system part way through opening or closing this building?
##
## Not "has it any request outstanding" and not "is it revealed": both of those
## are false on the frame the player crosses the threshold, because the reveal
## flips its state before its tween has produced a single value -- and one
## unfrozen frame at the crossing is one frame of the house heading back toward
## solid, which is the pop this exists to remove. Mid-transition is the
## question, and this is what it looks like from outside.
func reveal_in_flight(unit: Node) -> bool:
	var building := unit.get_parent()
	if building == null:
		return false
	for child in building.get_children():
		if not (child.has_method("is_revealed") and child.has_method("fade")):
			continue
		var open: bool = child.is_revealed()
		var value: float = child.fade()
		if open and value < 1.0:
			return true
		if not open and value > 0.0:
			return true
	return false


# --- the frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	var camera := _camera()
	var subject := _resolve_subject()
	if camera == null or subject == null:
		return
	_rediscover(subject)
	if _units.is_empty():
		return

	var at := aim_point(subject)
	if occlusion_sample_due(delta, camera.global_transform, at):
		var observed := blocking_units(camera, at)
		_cached_blocked.clear()
		for unit in _units:
			if confirmed_occlusion(unit, observed.has(unit)):
				_cached_blocked[unit] = true
		_occlusion_query_count += 1
	var blocked := _cached_blocked
	var dwell: float = settings().dwell_seconds
	for unit in _units:
		if not is_instance_valid(unit):
			continue
		var wanted: float = _target.get(unit, 0.0)
		# A building whose interior is open is not this system's business:
		# src/entities/interior/interior_reveal.gd is taking its roof off, and a
		# tint silhouette over an open room is the wrong picture. Duck-typed on
		# purpose -- the reveal is a component any building can carry, and this
		# must not know which ones do.
		if blocked.has(unit) and not _interior_is_open(unit):
			_release_at.erase(unit)
			wanted = 1.0
		elif wanted > 0.0:
			# The dwell, and nothing more: a bounded pause so a single ray does
			# not chatter when he skims an edge.
			if not _release_at.has(unit):
				_release_at[unit] = _clock + dwell
			if _clock >= float(_release_at[unit]):
				_release_at.erase(unit)
				wanted = 0.0
		else:
			_release_at.erase(unit)

		# The handover. See request_removal() for why holding is the whole fix.
		#
		# Killed and re-aimed rather than paused and resumed: a Tween that
		# finishes while paused cannot be played again -- the engine says so out
		# loud -- and a hold that has to remember whether it paused something is
		# a piece of bookkeeping that can be wrong. Dropping the tween and
		# declaring the unit's target to be where it already is says the same
		# thing with no state, and the restart afterwards comes off the CURRENT
		# value like every other restart here.
		if reveal_in_flight(unit):
			var running: Tween = _tween.get(unit)
			if running != null and running.is_valid():
				running.kill()
			_tween.erase(unit)
			_target[unit] = _fade.get(unit, 0.0)
			continue
		if not is_equal_approx(wanted, _target.get(unit, 0.0)):
			_start(unit, wanted)


func _start(unit: Node, target: float) -> void:
	_target[unit] = target
	var from: float = _fade.get(unit, 0.0)
	var running: Tween = _tween.get(unit)
	if running != null and running.is_valid():
		# Killed rather than retargeted, and the new one starts FROM THE CURRENT
		# VALUE -- walking behind a tree and straight back out has to turn the
		# fade around from wherever it has got to, never snap to an endpoint and
		# run from there.
		running.kill()
	_tween.erase(unit)
	var span: float = _span.get(unit, 0.0)
	var duration := duration_for(
		target - from, span, settings().large_metres,
		settings().fade_seconds, settings().fade_seconds_large)
	if not is_inside_tree() or duration <= 0.0:
		_set_fade(unit, target)
		return
	var tween := create_tween()
	tween.set_trans(curve_for(span, settings().large_metres))
	tween.set_ease(ease_for(span, settings().large_metres))
	tween.tween_method(func(value: float) -> void: _set_fade(unit, value), from, target, duration)
	_tween[unit] = tween


func _set_fade(unit: Node, value: float) -> void:
	if not is_instance_valid(unit):
		return
	_fade[unit] = value
	for entry in _meshes.get(unit, []):
		var instance := entry as GeometryInstance3D
		if instance != null and is_instance_valid(instance):
			paint(instance, value, removal_of(instance))


## What every unit currently holds. Read by tools/capture_sequence.gd, which is
## how the motion gets judged -- a still cannot show whether a fade is eased.
func report() -> String:
	var parts := PackedStringArray()
	for unit in _units:
		var value: float = _fade.get(unit, 0.0)
		if value > 0.0005:
			parts.append("%s=%.2f" % [String((unit as Node3D).name), value])
	return "fade[" + " ".join(parts) + "]"


func _camera() -> Camera3D:
	var viewport := get_viewport()
	return null if viewport == null else viewport.get_camera_3d()


func _resolve_subject() -> Node3D:
	if _subject != null and is_instance_valid(_subject):
		return _subject
	if _registry == null:
		# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry
		# is a node under /root and never enters the engine's singleton registry
		# (briefing trap 3).
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry == null:
		return null
	_subject = _registry.get_service(subject_service) as Node3D
	return _subject


## Walked once per scene. Everything in this game is placed before the first
## frame -- the fence segments are built in `Farmstead._ready()`, which has run
## by the time an autoload's `_process` does -- so a rescan per frame would be
## twenty nodes of work to discover nothing.
func _rediscover(subject: Node3D) -> void:
	# The world is THE SCENE THE SUBJECT BELONGS TO, not `current_scene`.
	# `owner` is the node a scene's contents are saved under, so for the player
	# it is always the world he was placed in -- which stays true when the whole
	# of `scenes/main.tscn` is itself instanced inside something else, as every
	# capture harness in tools/ does it.
	var current: Node = subject.owner
	if current == null:
		current = get_tree().current_scene
	if current == _scene and not _units.is_empty():
		return
	_forget()
	_scene = current
	if current == null:
		return
	_proxies = Node3D.new()
	_proxies.name = "OcclusionProxies"
	add_child(_proxies)
	for unit in units_in(current, subject):
		# Defensive backstop for scene ownership changes: even if discovery is
		# refactored later, no ancestor containing the player can ever be painted.
		if unit == subject or (unit as Node).is_ancestor_of(subject):
			continue
		var placed := (unit as Node3D).global_transform
		var shapes := proxy_shapes(unit)
		if shapes.is_empty():
			# Nothing solid in it -- the wires, the swing hanging off a branch.
			# It cannot be in anybody's way.
			continue
		var body := StaticBody3D.new()
		body.name = "Proxy_" + String((unit as Node3D).name)
		body.collision_layer = OCCLUSION_LAYER
		body.collision_mask = 0
		for entry in shapes:
			var collider := CollisionShape3D.new()
			collider.shape = entry["shape"]
			collider.transform = placed * (entry["transform"] as Transform3D)
			body.add_child(collider)
		_proxies.add_child(body)
		_by_rid[body.get_rid()] = unit
		_units.append(unit)
		_meshes[unit] = meshes_of(unit)
		for instance in _meshes[unit]:
			_unit_of[instance] = unit
		var bounds: Array = []
		var span := AABB()
		var started := false
		for box in solid_bounds(unit):
			var world: AABB = placed * (box as AABB)
			bounds.append(world)
			span = span.merge(world) if started else world
			started = true
		_bounds[unit] = bounds
		_span[unit] = maxf(span.size.x, span.size.z)


func _forget() -> void:
	for unit in _tween:
		var tween: Tween = _tween[unit]
		if tween != null and tween.is_valid():
			tween.kill()
	_tween.clear()
	_units.clear()
	_bounds.clear()
	_meshes.clear()
	_unit_of.clear()
	_span.clear()
	_fade.clear()
	_target.clear()
	_release_at.clear()
	_by_rid.clear()
	_stable_blocked.clear()
	_hit_streak.clear()
	_clear_streak.clear()
	reset_occlusion_sampling()
	if _proxies != null and is_instance_valid(_proxies):
		_proxies.queue_free()
	_proxies = null


## True while another system already owns this object's transparency. Today that
## is only `InteriorReveal`, which takes the roof and the front wall off when the
## player steps inside.
func _interior_is_open(unit: Node) -> bool:
	var building := unit.get_parent()
	if building == null:
		return false
	for child in building.get_children():
		if child.has_method("is_revealed") and child.is_revealed():
			return true
	return false
