extends TestCase

## The composition, as a contract.
##
## Art Bible rule 1: the camera never rotates. So the frame is composed by
## moving the *world*, and scenes/main.tscn is the only place that composition
## is written down. That makes it exactly as load-bearing as any script here,
## and exactly as easy to break silently -- a node renamed, a model dropped, a
## transform pasted twice -- with the only symptom being a screenshot somebody
## takes a week later.
##
## Walked off SceneState rather than instantiated, for the reason
## test_farmhouse_placement.gd gives: instancing main.tscn builds a 512-square
## noise field and a 320-subdivision terrain mesh, and a placement test has no
## business paying for that.
##
## What this does NOT check is whether the shot looks like the reference. That
## is a screenshot and a person, and it is in the wave report. What it checks is
## the set of things that would make the shot impossible to take at all.

const MAIN_SCENE := "res://scenes/main.tscn"
const FARMSTEAD_SCRIPT := "res://src/entities/farmstead.gd"
const WIRE_MODEL := "res://assets/models/props/power_wire.glb"
const SWING_MODEL := "res://assets/models/props/tire_swing.glb"

const FarmsteadScript := preload("res://src/entities/farmstead.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const TrackMaskScript := preload("res://src/systems/track_mask.gd")

## Every model the reference calls for, and the frame is short of one if any is
## missing. The three trees are listed separately because "scattering one tree
## three times reads as wallpaper" was the props task's whole argument for
## building three.
const REQUIRED_MODELS: Array[String] = [
	"res://assets/models/buildings/farmhouse/farmhouse.glb",
	"res://assets/models/buildings/tool_shed/tool_shed.glb",
	"res://assets/models/buildings/well_house/well_house.glb",
	"res://assets/models/props/pickup_truck.glb",
	"res://assets/models/props/power_pole.glb",
	"res://assets/models/props/power_wire.glb",
	"res://assets/models/props/tire_swing.glb",
	"res://assets/models/vegetation/tree_bare_a.glb",
	"res://assets/models/vegetation/tree_bare_b.glb",
	"res://assets/models/vegetation/tree_bare_c.glb",
]


## name -> {path, parent, instance, transform, has_transform}
func _placed() -> Dictionary:
	var found: Dictionary = {}
	var resource := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (resource is PackedScene):
		return found
	var state := (resource as PackedScene).get_state()
	for node in range(state.get_node_count()):
		var instance := state.get_node_instance(node)
		var entry := {
			"path": str(state.get_node_path(node)),
			"parent": str(state.get_node_path(node, true)).get_base_dir(),
			"instance": "" if instance == null else instance.resource_path,
			"script": "",
			"transform": Transform3D(),
			"has_transform": false,
		}
		for property in range(state.get_node_property_count(node)):
			var name := state.get_node_property_name(node, property)
			var value = state.get_node_property_value(node, property)
			if value is Script:
				entry["script"] = (value as Script).resource_path
			if name == "transform" and value is Transform3D:
				entry["transform"] = value
				entry["has_transform"] = true
		found[str(state.get_node_name(node))] = entry
	return found


func test_the_main_scene_runs_the_farmstead() -> void:
	var placed := _placed()
	var running := PackedStringArray()
	for name in placed:
		if placed[name]["script"] == FARMSTEAD_SCRIPT:
			running.append(name)
	assert_eq(
		running.size(), 1,
		"%s must hold exactly one node running %s; it holds %d" % [MAIN_SCENE, FARMSTEAD_SCRIPT, running.size()]
	)


## Every asset the wave built is actually in the shot. A model that exists on
## disk and is in no scene is a model nobody will notice is missing.
func test_every_model_the_reference_calls_for_is_in_the_scene() -> void:
	var placed := _placed()
	var instanced := PackedStringArray()
	for name in placed:
		var path: String = placed[name]["instance"]
		if path != "" and not instanced.has(path):
			instanced.append(path)
	var missing := PackedStringArray()
	for model in REQUIRED_MODELS:
		if not instanced.has(model):
			missing.append(model)
	assert_eq(
		missing.size(), 0,
		"%s does not place %s; it places %s" % [MAIN_SCENE, ", ".join(missing), ", ".join(instanced)]
	)


## The props report's one documented inconsistency: the tire swing's origin is
## its hang point, not its base, because it hangs. Placed on the ground like
## everything else it would be buried to the axle, and there is nothing in the
## file that would say so. So it is asserted: the swing is parented to a tree
## and lifted off that tree's origin.
func test_the_tire_swing_hangs_from_a_tree_rather_than_standing_on_the_ground() -> void:
	var placed := _placed()
	var swing := {}
	for name in placed:
		if placed[name]["instance"] == SWING_MODEL:
			swing = placed[name]
	assert_true(not swing.is_empty(), "no node in %s instances %s" % [MAIN_SCENE, SWING_MODEL])
	if swing.is_empty():
		return
	var parent_name: String = str(swing["path"]).get_base_dir().get_file()
	var parent: Dictionary = placed.get(parent_name, {})
	assert_true(
		parent.get("instance", "").begins_with("res://assets/models/vegetation/"),
		"the tire swing hangs off a branch, so its parent must be a tree; it is under %s" % parent_name
	)
	var offset: Vector3 = (swing["transform"] as Transform3D).origin
	assert_true(
		offset.y > 1.5,
		"the swing's origin is its hang point, so it must be lifted onto a branch; it sits at y = %.2f" % offset.y
	)


## The wires are the one thing in the scene the script positions rather than the
## file, so all three have to be reachable where the script looks for them.
func test_three_wires_are_placed_where_the_script_strings_them() -> void:
	var placed := _placed()
	var farmstead: Farmstead = FarmsteadScript.new()
	var root := str(farmstead.wire_root)
	# Node is not reference counted (briefing section 2.2).
	farmstead.free()
	var under := PackedStringArray()
	for name in placed:
		if placed[name]["instance"] != WIRE_MODEL:
			continue
		under.append(str(placed[name]["path"]).get_base_dir().get_file())
	assert_eq(under.size(), 3, "the reference has three spans; the scene has %d" % under.size())
	for parent in under:
		assert_eq(
			parent, root.get_file(),
			"a wire is under %s, but Farmstead.wire_root looks under %s and will never string it" % [parent, root]
		)


## Y is left to _settle(), which reads the procedural terrain at runtime. A
## height saved in the file is a height that is wrong the moment the noise seed
## changes -- and a building a hand's width above a drift is the one defect that
## kills the frame instantly.
func test_nothing_is_placed_at_a_height_the_scene_file_guessed() -> void:
	var placed := _placed()
	var offenders := PackedStringArray()
	for name in placed:
		var entry: Dictionary = placed[name]
		if entry["instance"] == "" or not entry["has_transform"]:
			continue
		if entry["instance"] == SWING_MODEL:
			continue  # hangs off a branch; its height is the branch's business
		var spot: Vector3 = (entry["transform"] as Transform3D).origin
		if absf(spot.y) > 0.001:
			offenders.append("%s is placed at y = %.3f" % [name, spot.y])
	assert_eq(
		offenders.size(), 0,
		"%s -- every prop's height belongs to Farmstead._settle(), which samples the height field" % "; ".join(offenders)
	)


## _settle() reads SnowField, whose window is 120 m around the player's start.
## A prop outside it does not error -- the bilinear read clamps to the border
## texel -- it just settles onto a height that has nothing to do with the ground
## under it. Silent, and only visible as one thing floating.
func test_every_prop_stands_inside_the_height_field_the_settle_reads() -> void:
	var placed := _placed()
	var reach: float = SnowFieldScript.EXTENT_M * 0.5 - 8.0
	var offenders := PackedStringArray()
	for name in placed:
		var entry: Dictionary = placed[name]
		if entry["instance"] == "" or not entry["has_transform"]:
			continue
		var spot: Vector3 = (entry["transform"] as Transform3D).origin
		var distance := Vector2(spot.x, spot.z).length()
		if distance > reach:
			offenders.append("%s is %.1f m from the player's start, past the %.0f m the height field covers" % [name, distance, reach])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Two props on the same spot is what a duplicated transform looks like, and in
## a frame this sparse it reads as one prop with a rendering fault. The number
## is generous on purpose -- the truck really is parked close to the house --
## so it only catches a genuine collision.
func test_no_two_props_stand_on_the_same_patch_of_snow() -> void:
	var placed := _placed()
	var spots: Dictionary = {}
	for name in placed:
		var entry: Dictionary = placed[name]
		if entry["instance"] == "" or entry["instance"] == WIRE_MODEL or entry["instance"] == SWING_MODEL:
			continue
		if not entry["has_transform"]:
			continue
		spots[name] = (entry["transform"] as Transform3D).origin
	var offenders := PackedStringArray()
	var names: Array = spots.keys()
	for a in range(names.size()):
		for b in range(a + 1, names.size()):
			var one: Vector3 = spots[names[a]]
			var two: Vector3 = spots[names[b]]
			var gap := Vector2(one.x - two.x, one.z - two.z).length()
			if gap < 3.0:
				offenders.append("%s and %s are %.2f m apart" % [names[a], names[b], gap])
	assert_eq(offenders.size(), 0, "%s -- two props on one spot" % "; ".join(offenders))


## Every line the farmstead bakes has to fall inside the baked window, because a
## stroke outside it writes into nothing and reports nothing. This is the whole
## failure mode of a fixed window, and it is cheap to rule out.
func test_every_baked_line_falls_inside_the_baked_window() -> void:
	var farmstead: Farmstead = FarmsteadScript.new()
	var centre: Vector3 = FarmsteadScript.BAKE_CENTRE
	var half: float = TrackMaskScript.STATIC_EXTENT_M * 0.5
	var points: Array = []
	points.append_array(FarmsteadScript.ROAD)
	points.append_array(FarmsteadScript.YARD)
	points.append(FarmsteadScript.SPUR_JUNCTION)
	points.append(FarmsteadScript.SPUR_BEND)
	# The furrow band's four corners, from the same parameters bake_furrows uses.
	var along: Vector2 = farmstead.furrow_direction.normalized()
	var across := Vector2(-along.y, along.x)
	var span: Vector2 = across * (farmstead.furrow_spacing * float(farmstead.furrow_count - 1))
	for reach in [0.0, farmstead.furrow_length]:
		for offset in [Vector2.ZERO, span]:
			points.append(
				farmstead.furrow_origin
				+ Vector3(along.x, 0.0, along.y) * reach
				+ Vector3(offset.x, 0.0, offset.y)
			)
	var offenders := PackedStringArray()
	for point: Vector3 in points:
		if absf(point.x - centre.x) > half or absf(point.z - centre.z) > half:
			offenders.append("(%.1f, %.1f)" % [point.x, point.z])
	# Node is not reference counted (briefing section 2.2).
	farmstead.free()
	assert_eq(
		offenders.size(), 0,
		"%s fall outside the %.0f m baked window centred on (%.1f, %.1f), so they would draw nothing at all" % [
			", ".join(offenders), TrackMaskScript.STATIC_EXTENT_M, centre.x, centre.z,
		]
	)
