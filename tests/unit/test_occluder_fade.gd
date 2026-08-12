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


## And a thing with nothing solid in it is never in anybody's way. The three
## power wires are 7 cm of steel strung 30 m across the frame; their bounding
## boxes cover most of the sky and they hide nothing at all.
func test_something_with_no_collider_is_never_an_occluder() -> void:
	var wire := _prop("Wire", "res://power_wire.glb")
	assert_eq(FaderScript.solid_bounds(wire).size(), 0)
	wire.free()


# --- the occlusion decision --------------------------------------------------

func test_something_in_front_and_overlapping_occludes() -> void:
	assert_true(FaderScript.is_occluding(
		Rect2(90, 90, 40, 40), 10.0,
		Rect2(100, 100, 20, 60), 20.0))


func test_something_behind_the_subject_does_not_occlude() -> void:
	assert_false(FaderScript.is_occluding(
		Rect2(90, 90, 40, 40), 30.0,
		Rect2(100, 100, 20, 60), 20.0),
		"a tree the player is standing in front of must not fade")


func test_something_in_front_but_elsewhere_on_screen_does_not_occlude() -> void:
	assert_false(FaderScript.is_occluding(
		Rect2(600, 90, 40, 40), 10.0,
		Rect2(100, 100, 20, 60), 20.0),
		"half the farmstead is nearer the camera than the player; only what covers him may fade")


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
