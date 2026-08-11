extends TestCase

## What a prop rests on.
##
## Farmstead._settle() drops every prop onto the lowest snow anywhere under its
## footprint, and the footprint is not the model's bounding box -- it is the XZ
## hull of the geometry that is actually near the ground. A bare tree's box is
## seven metres across and none of it touches snow except the trunk, so resting
## it on the lowest point under its *crown* drops it into a hole; a shed really
## does rest on all four walls.
##
## Getting that wrong is silent. The prop still lands on the terrain, just a few
## centimetres too deep, and the only symptom is that one thing in the frame
## looks slightly sunk -- which reads as art rather than as a defect.
##
## These need real Node3Ds in the real tree, because global_transform errors
## outside it. Everything allocated here is freed (briefing section 2.2).

const FarmsteadScript := preload("res://src/entities/farmstead.gd")

var _farmstead: Farmstead


func before_each() -> void:
	_farmstead = FarmsteadScript.new()
	# Nothing it reaches for on _ready() is registered in a test run -- no
	# snow_field, no track_mask, no Wires child -- so every one of its jobs
	# guards out and it is inert.
	Engine.get_main_loop().root.add_child(_farmstead)


func after_each() -> void:
	_farmstead.free()
	_farmstead = null


func _prop_with(boxes: Array) -> Node3D:
	var prop := Node3D.new()
	_farmstead.add_child(prop)
	for box: Dictionary in boxes:
		var mesh := BoxMesh.new()
		mesh.size = box["size"]
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = box["at"]
		var parent: Node = prop
		if box.get("mounted_at", Vector3.ZERO) != Vector3.ZERO:
			var mount := Node3D.new()
			mount.position = box["mounted_at"]
			prop.add_child(mount)
			parent = mount
			instance.position = Vector3.ZERO
		parent.add_child(instance)
	return prop


## A shed: walls on the ground, so all of it counts.
func test_geometry_on_the_ground_sets_the_footprint() -> void:
	var prop := _prop_with([{"size": Vector3(3.0, 2.0, 4.0), "at": Vector3(0.0, 1.0, 0.0)}])
	var footprint: Rect2 = _farmstead._ground_footprint(prop)
	assert_almost_eq(footprint.position.x, -1.5, 0.01)
	assert_almost_eq(footprint.position.y, -2.0, 0.01)
	assert_almost_eq(footprint.size.x, 3.0, 0.01)
	assert_almost_eq(footprint.size.y, 4.0, 0.01)
	prop.queue_free()


## A tree: a thin trunk at the bottom and a wide crown well above it. Only the
## trunk may set where the tree stands.
func test_a_crown_high_above_the_ground_does_not_widen_the_footprint() -> void:
	var prop := _prop_with([
		{"size": Vector3(0.4, 6.0, 0.4), "at": Vector3(0.0, 3.0, 0.0)},
		{"size": Vector3(7.0, 1.0, 7.0), "at": Vector3(0.0, 5.0, 0.0)},
	])
	var footprint: Rect2 = _farmstead._ground_footprint(prop)
	assert_true(
		footprint.size.x < 1.0 and footprint.size.y < 1.0,
		"the crown widened the footprint to %s; only the trunk touches snow" % footprint.size
	)
	prop.queue_free()


## The tire swing. It is parented to the tree at 2.8 m and hangs down to 0.71 m
## in the tree's own space, which is inside the ground band -- so without the
## mounted-child rule its tire drags the tree's footprint two metres sideways
## and the tree settles on the lowest snow under the *swing*.
func test_a_child_mounted_up_the_prop_does_not_widen_the_footprint_either() -> void:
	var alone := _prop_with([{"size": Vector3(0.4, 6.0, 0.4), "at": Vector3(0.0, 3.0, 0.0)}])
	var bare: Rect2 = _farmstead._ground_footprint(alone)

	var hung := _prop_with([
		{"size": Vector3(0.4, 6.0, 0.4), "at": Vector3(0.0, 3.0, 0.0)},
		{"size": Vector3(0.8, 2.1, 0.2), "at": Vector3.ZERO, "mounted_at": Vector3(-1.9, 2.8, 0.0)},
	])
	var swung: Rect2 = _farmstead._ground_footprint(hung)

	assert_almost_eq(swung.position.x, bare.position.x, 0.01)
	assert_almost_eq(swung.size.x, bare.size.x, 0.01)
	alone.queue_free()
	hung.queue_free()


## The swing itself, asked the same question, has no answer -- and an empty
## footprint is what tells _settle() to leave it exactly where the scene hung it
## instead of standing it on the snow.
func test_a_thing_that_only_hangs_has_no_footprint_at_all() -> void:
	var swing := Node3D.new()
	_farmstead.add_child(swing)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 2.1, 0.2)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	# Hanging below its own origin, as the real asset does: origin at the hang
	# point, tire down at -2.09.
	instance.position = Vector3(0.0, -1.05, 0.0)
	swing.add_child(instance)
	# ...and mounted well up a branch, which is where the scene puts it.
	swing.position = Vector3(-1.9, 2.8, -0.14)

	var footprint: Rect2 = _farmstead._ground_footprint(swing)
	# _settle() reads exactly this: a zero rect at the origin means "leave it".
	assert_true(
		footprint.size == Vector2.ZERO and footprint.position == Vector2.ZERO,
		"a hanging prop must report no footprint, got %s" % footprint
	)
	swing.queue_free()
