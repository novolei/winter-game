extends Node

## Autoload "OccluderFader". Whatever stands between the camera and the player
## gets out of the way.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Art Bible rule 1's last row: the camera **never rotates, it only follows**.
## There is no stick to swing, so a player who walks behind the farmhouse, a
## tree or the power pole simply stops being on screen -- and at 45 degrees
## against a farmstead that happens constantly. The owner reported it from play.
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
## untouched here. It survives this change precisely because the ground is never
## an occluder unit -- see `units_in()`.
##
## ---------------------------------------------------------------------------
## THE WHOLE OBJECT, UNIFORMLY
## ---------------------------------------------------------------------------
## No window is cut around the character's screen position. A dissolve disc is
## exactly the artefact that was already removed from the farmhouse once, and
## the owner asked for it not to come back. The entire building, the entire
## tree, the entire run of fence fades as one, to one flat tint.
##
## ---------------------------------------------------------------------------
## HOW THE FADE IS DRAWN, AND WHY IT IS TWO PHASES
## ---------------------------------------------------------------------------
## `GeometryInstance3D.transparency`, which the interior agent already measured
## on 4.7.1: it fades a mesh that CelPainter has re-materialled onto
## `assets/shaders/cel_flat.gdshader` even though that shader declares no ALPHA
## and no blend mode, **and no material on disk changes**, so no art gate moves.
##
## But transparency alone fades an object toward whatever is behind it, which
## bleaches it rather than silhouetting it -- a snow-covered roof would fade
## into the snow field and simply disappear. The owner asked for a light
## grey-black you can see straight through. So the far half of the fade wears a
## flat tint instead of the object's own two palette bands, and the crossover
## between the two is done AT FULL TRANSPARENCY, where the object is invisible
## and the swap cannot be seen:
##
##     amount 0.0 .. 0.5   the object itself, transparency 0 -> 1
##     amount 0.5 .. 1.0   the flat tint,     transparency 1 -> 1 - opacity
##
## The tint material is the world's own cel shader with both bands set to the
## same colour and its light tint neutralised, so a warm sunrise cannot push a
## faded building into rule 12's warm quota.

const SETTINGS_PATH := "res://data/rendering/occluder_fade.tres"
const FADE_SHADER_PATH := "res://assets/shaders/occluder_fade.gdshader"

## Who is being kept visible. Resolved through the ServiceRegistry, the same way
## CameraRig and InteriorReveal find him.
@export var subject_service: StringName = &"player"

## Fallbacks for the subject's size, used only when it publishes neither.
@export var subject_height := 1.9
@export var subject_radius := 0.3

var _settings: OccluderFadeSettings
var _tint: Material
var _subject: Node3D
var _registry: Node
var _scene: Node = null
var _units: Array = []
var _bounds: Dictionary = {}
var _fades: Dictionary = {}


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


## WHAT AN OCCLUDER IS SHAPED LIKE: ITS COLLISION, NOT ITS MESH.
##
## Every world model carries a collider built at import by
## `tools/model_collision.gd`, and that collider is already the answer to
## "which part of this is actually solid" -- the tree's is a cylinder on the
## trunk rather than a hull of its crown, precisely because the crown is mostly
## air. Reusing it here is not a shortcut, it is the same question asked twice.
##
## A mesh bounding box gets this badly wrong and the screenshot proved it: a bare
## tree's box is 5.6 x 9.4 x 6.5 m of mostly nothing, so a tree standing well
## clear of the player faded anyway because its BOX covered him. The trunk's does
## not.
##
## It also settles two other cases with no special rule. The power wires have no
## collider at all -- 7 cm of steel strung 30 m across the frame hides nothing --
## so they never occlude, where their bounding boxes covered most of the sky. And
## a run of fence is tested panel by panel while it FADES as one run, because the
## panels are what carry the colliders.
##
## Returned in the UNIT's own space -- `global_transform` is not answerable for a
## node outside a tree, which is where every test builds its subjects -- and
## converted to world once, at discovery. Nothing in this game moves after
## `_ready()` settles it onto the snow.
static func solid_bounds(unit: Node) -> Array:
	var found: Array = []
	if unit is CollisionShape3D:
		_add_shape(unit as CollisionShape3D, Transform3D.IDENTITY, found)
	for child in unit.get_children():
		_walk_bounds(child, Transform3D.IDENTITY, found)
	return found


static func _walk_bounds(node: Node, into: Transform3D, found: Array) -> void:
	var here := into
	if node is Node3D:
		here = into * (node as Node3D).transform
	if node is CollisionShape3D:
		_add_shape(node as CollisionShape3D, here, found)
	for child in node.get_children():
		_walk_bounds(child, here, found)


static func _add_shape(collider: CollisionShape3D, into: Transform3D, found: Array) -> void:
	if collider.disabled or collider.shape == null:
		return
	var local := _shape_bounds(collider.shape)
	if local.size == Vector3.ZERO:
		return
	found.append(into * local)


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


# --- the decision -------------------------------------------------------------

## Is a thing at `unit_rect` / `unit_depth` in the way of a subject at
## `subject_rect` / `subject_depth`?
##
## Both depths are the CENTRE of the object along the camera's view axis, not
## its nearest point, and that is the difference between a tree that fades when
## the player walks behind it and one that fades when he walks in front of it. A
## bare tree's crown is four metres across; its nearest point is nearer than the
## player's even when its trunk is a metre further away, so a nearest-point test
## fades the tree the player is standing in front of.
static func is_occluding(
		unit_rect: Rect2, unit_depth: float,
		subject_rect: Rect2, subject_depth: float) -> bool:
	if unit_depth >= subject_depth:
		return false
	return unit_rect.intersects(subject_rect)


# --- applying it --------------------------------------------------------------

## How much of what is being drawn reaches the screen, at a given point in the
## fade. Zero at the crossover from BOTH sides, which is what makes the swap
## from the object to its silhouette invisible.
static func visible_opacity(fade: float, tint_alpha: float) -> float:
	if fade <= 0.5:
		return 1.0 - fade * 2.0
	return (fade - 0.5) * 2.0 * tint_alpha


## `amount` 0 is untouched, 1 is a flat translucent silhouette. See the header
## for why the two halves are different.
func apply_fade(meshes: Array, amount: float) -> void:
	var fade := clampf(amount, 0.0, 1.0)
	var opacity: float = settings().tint.a
	for entry in meshes:
		if not (entry is GeometryInstance3D):
			continue
		var instance := entry as GeometryInstance3D
		if fade <= 0.0:
			instance.material_override = null
			instance.transparency = 0.0
			instance.set_instance_shader_parameter(&"fade_opacity", 1.0)
		elif fade <= 0.5:
			instance.material_override = null
			instance.transparency = fade * 2.0
		else:
			instance.material_override = tint_material()
			instance.transparency = 0.0
			instance.set_instance_shader_parameter(&"fade_opacity", visible_opacity(fade, opacity))


## One material for every faded object in the frame: the fade is one flat tint,
## so there is nothing to vary per object.
##
## `assets/shaders/occluder_fade.gdshader` rather than the world's cel shader,
## and the reason is written out there: a faded occluder that still writes depth
## still hides the character, so the fade has to be a real transparent pass with
## `depth_draw_never` rather than the cel shader turned down. The first attempt
## used the cel shader and produced a beautiful translucent tree with the
## character still culled behind it.
##
## Alpha is left at 1 in the material and applied through
## `GeometryInstance3D.transparency`, so `apply_fade()` drives the whole
## crossfade with one number.
func tint_material() -> Material:
	if _tint != null:
		return _tint
	var colour := ShaderMaterial.new()
	colour.shader = load(FADE_SHADER_PATH)
	var tint: Color = settings().tint
	colour.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
	colour.render_priority = 0

	# THE DEPTH PREPASS, and it is what makes a faded building ONE shape rather
	# than forty transparent panels stacked on each other.
	#
	# The symptom without it, and the owner named it exactly: the faded
	# farmhouse showed its own insides -- floor joists, partitions and the far
	# roof plane all compositing through the near one, three and four layers
	# deep. That is what alpha blending does to a hollow object.
	#
	# So the object is drawn twice. This pass writes nothing but depth, at
	# alpha zero; the pass hung off it writes the colour and no depth, so only
	# the surface nearest the camera survives to be blended and everything
	# behind it inside the same building is culled.
	#
	# `render_priority` is the part that is easy to miss. The farmhouse is nine
	# separate meshes and Godot draws a transparent object's passes back to
	# back, so without this the second mesh's depth would be written after the
	# first mesh's colour and cull nothing. Sorting by priority puts EVERY
	# depth pass in the frame before EVERY colour pass.
	_tint = StandardMaterial3D.new()
	_tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tint.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_tint.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_tint.render_priority = -1
	_tint.next_pass = colour
	return _tint


# --- the frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	var camera := _camera()
	var subject := _resolve_subject()
	if camera == null or subject == null:
		return
	_rediscover(subject)
	if _units.is_empty():
		return

	var subject_box := _subject_box(subject)
	var subject_rect := _screen_rect(camera, subject_box).grow(settings().margin_px)
	var subject_depth := _depth(camera, subject_box.get_center())
	var step := delta / maxf(settings().fade_seconds, 0.0001)

	for unit in _units:
		if not is_instance_valid(unit):
			continue
		var wanted := 0.0
		# A building whose interior is open is not this system's business:
		# src/entities/interior/interior_reveal.gd is already fading those walls
		# and two systems writing `transparency` to one mesh would fight every
		# frame. Duck-typed on purpose -- the reveal is a component any building
		# can carry, and this must not know which ones do.
		if not _interior_is_open(unit):
			# PER COLLIDER, faded PER UNIT. A run of fence is one object 30 m
			# long, so one box round the whole run covers a third of the frame;
			# its panels are the right size to test. What fades is still the
			# whole run.
			for box in _bounds.get(unit, []):
				if is_occluding(
						_screen_rect(camera, box), _depth(camera, box.get_center()),
						subject_rect, subject_depth):
					wanted = 1.0
					break
		var fade: float = _fades.get(unit, 0.0)
		fade = move_toward(fade, wanted, step)
		if is_equal_approx(fade, _fades.get(unit, -1.0)):
			continue
		_fades[unit] = fade
		apply_fade(meshes_of(unit), fade)


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
	# capture harness in tools/ does it. Reading `current_scene` there returns
	# the harness, whose only child is the world, and the world then looks like
	# one enormous occluder.
	var current: Node = subject.owner
	if current == null:
		current = get_tree().current_scene
	if current == _scene and not _units.is_empty():
		return
	_scene = current
	_units.clear()
	_fades.clear()
	_bounds.clear()
	if current == null:
		return
	for unit in units_in(current, subject):
		var bounds: Array = []
		for box in solid_bounds(unit):
			bounds.append((unit as Node3D).global_transform * (box as AABB))
		if bounds.is_empty():
			# Nothing solid in it -- the wires, the swing hanging off a branch.
			# It cannot be in anybody's way.
			continue
		_units.append(unit)
		_bounds[unit] = bounds


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


func _subject_box(subject: Node3D) -> AABB:
	var height: float = subject.get("body_height") if subject.get("body_height") != null else subject_height
	var radius: float = subject.get("body_radius") if subject.get("body_radius") != null else subject_radius
	var at := subject.global_position
	return AABB(at - Vector3(radius, 0.0, radius), Vector3(radius * 2.0, height, radius * 2.0))


func _world_bounds(unit: Node) -> AABB:
	var bounds := AABB()
	var started := false
	for entry in meshes_of(unit):
		var instance := entry as MeshInstance3D
		if instance.mesh == null:
			continue
		var box := instance.global_transform * instance.mesh.get_aabb()
		if started:
			bounds = bounds.merge(box)
		else:
			bounds = box
			started = true
	return bounds


## Distance along the camera's view axis. Larger is further away.
func _depth(camera: Camera3D, point: Vector3) -> float:
	return -(camera.global_transform.affine_inverse() * point).z


func _screen_rect(camera: Camera3D, box: AABB) -> Rect2:
	var rect := Rect2()
	var started := false
	for index in range(8):
		var corner := box.get_endpoint(index)
		if camera.is_position_behind(corner):
			continue
		var at := camera.unproject_position(corner)
		if started:
			rect = rect.expand(at)
		else:
			rect = Rect2(at, Vector2.ZERO)
			started = true
	return rect
