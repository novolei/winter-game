class_name Blockout
extends Node3D

## Placeholder geometry whose only job is to cast shadows.
##
## Art Bible rule 10 says the long shadows are the subject of the composition,
## and in level.jpg they come off a farmhouse, a shed, a pole and four bare
## trees. An empty snow field lit by an 11-degree sun is just a flat blue
## rectangle -- there is nothing for the light to write with. So: a shed, a
## pole and some trees, in boxes, purely so the frame can be judged against the
## reference at all.
##
## None of this is art. It is deliberately built in code and deliberately not
## in assets/models/, because a real modelled farmhouse belongs to a later
## wave and putting a box there would tell the topology gate that a building
## exists when one does not.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CEL_SHADER_PATH := "res://assets/shaders/cel_flat.gdshader"

var _bible: ColorBible
var _shader: Shader


func _ready() -> void:
	_bible = load(PALETTE_PATH)
	_shader = load(CEL_SHADER_PATH)

	# Placed for the frame the camera actually shows -- roughly 60 m by 55 m
	# around the player -- and skewed away from the sun so their shadows run
	# across open snow rather than into each other.
	#
	# The farmhouse is two storeys because a wide flat box reads as a roof from
	# any elevated camera; height is what gives the walls enough screen area to
	# show that they are lit differently from the ground.
	_shed(Vector3(-13.0, 0.0, -7.0), Vector3(8.0, 7.0, 6.0), 0.35)
	_shed(Vector3(11.0, 0.0, -19.0), Vector3(4.6, 3.4, 3.8), -0.85)
	_pole(Vector3(15.0, 0.0, 4.0), 7.5)

	for spot in [
		Vector3(-21.0, 0.0, 7.0),
		Vector3(-4.0, 0.0, -24.0),
		Vector3(20.0, 0.0, -9.0),
		Vector3(24.0, 0.0, 16.0),
		Vector3(-26.0, 0.0, -16.0),
	]:
		_tree(spot)


## The ground is no longer a plane, so nothing can be placed at y = 0 any more.
## Everything stands on the bare terrain and lets the snow bank up around its
## base, which is also how it looks right: a shed in a hollow is half buried.
func _grounded(spot: Vector3) -> Vector3:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return spot
	var snow := registry.get_service(&"snow_field") as Node
	if snow == null:
		return spot
	return Vector3(spot.x, snow.terrain_height_at(spot), spot.z)


func _flat_material(lit: Color, shade: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("lit_color", lit)
	material.set_shader_parameter("shade_color", shade)
	return material


func _box(size: Vector3, position: Vector3, material: ShaderMaterial, yaw := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation = Vector3(0.0, yaw, 0.0)
	add_child(instance)


## Rule 2: a building is three to eight convex blocks. This is three -- a body
## and two roof slabs -- because it is a stand-in, not a building.
##
## The slabs are placed by arithmetic rather than by chaining local rotations
## and translations. The chained version put the pivot at the ridge instead of
## the slab's middle and the sheds came out looking like open boxes.
func _shed(spot: Vector3, size: Vector3, yaw: float) -> void:
	var base := _grounded(spot)
	# Rule 3's gable and rule 9's flat colour. Walls sit on the two lightest
	# structure tones so they read as blue clapboard rather than as another
	# tree silhouette; the roof is the darkest tone in both bands, which is
	# what makes it a black shape against the snow the way level.jpg does.
	var walls := _flat_material(_bible.structure_tones[0], _bible.structure_tones[1])
	var roof := _flat_material(_bible.structure_tones[3], _bible.structure_tones[3])

	var frame := Node3D.new()
	frame.position = base
	frame.rotation = Vector3(0.0, yaw, 0.0)
	add_child(frame)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = size
	body.mesh = body_mesh
	body.material_override = walls
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	frame.add_child(body)

	# Rule 3: one gable, no dormers, no cross-ridges. Half-span and rise give
	# the pitch; the slab is the hypotenuse between eave and ridge.
	var half_span := size.x * 0.5
	var rise := half_span * 0.55
	var slab_length := sqrt(half_span * half_span + rise * rise)
	var pitch := atan2(rise, half_span)
	# The two slabs and the body enclose a triangular void that is open at both
	# gable ends, and an 11-degree sun travels almost horizontally: it goes in
	# one end, straight out the other, and punches a lit diamond into the
	# middle of the shed's own shadow. This fills the void along its length.
	# Sized to fit under the slope -- at half its width the roof underside is
	# still above its top -- so it never breaks the silhouette.
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(size.x * 0.3, rise * 0.6, size.z + 0.7)
	fill.mesh = fill_mesh
	fill.material_override = roof
	fill.position = Vector3(0.0, size.y + rise * 0.3, 0.0)
	frame.add_child(fill)

	for side in [-1.0, 1.0]:
		var mesh := BoxMesh.new()
		# Overlong on purpose: the two slabs have to overlap past the ridge or
		# the sun finds the seam between them too.
		mesh.size = Vector3(slab_length + 0.8, 0.2, size.z + 0.7)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = roof
		instance.position = Vector3(side * half_span * 0.5, size.y + rise * 0.5, 0.0)
		instance.rotation = Vector3(0.0, 0.0, -side * pitch)
		frame.add_child(instance)


func _pole(spot: Vector3, height: float) -> void:
	var base := _grounded(spot)
	var wood := _flat_material(_bible.structure_tones[2], _bible.structure_tones[3])
	_box(Vector3(0.28, height, 0.28), base + Vector3(0.0, height * 0.5, 0.0), wood)
	_box(Vector3(2.6, 0.16, 0.16), base + Vector3(0.0, height - 0.7, 0.0), wood)


## Rule 7: a tree is a silhouette of bare branches at the darkest structure
## tone. Both cel bands are that same colour, so it stays a flat cut-out
## whichever way it faces -- and throws a 30 m shadow.
func _tree(spot: Vector3) -> void:
	var base := _grounded(spot)
	var bark := _flat_material(_bible.structure_tones[3], _bible.structure_tones[3])
	var height := 5.4 + fmod(absf(base.x * 7.3 + base.z * 3.1), 2.6)
	_box(Vector3(0.34, height, 0.34), base + Vector3(0.0, height * 0.5, 0.0), bark)

	var branches := 7
	for index in range(branches):
		var angle := TAU * float(index) / float(branches) + fmod(absf(base.x), 1.0)
		var length := 1.9 + fmod(absf(base.z * 2.7 + float(index)), 1.5)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.11, length, 0.11)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = bark
		instance.position = base + Vector3(0.0, height * (0.58 + 0.09 * float(index % 3)), 0.0)
		instance.rotation = Vector3(0.0, angle, 0.0)
		# Nearer upright than out: a bare tree's branches climb. At the previous
		# 0.75 rad they splayed flat and every tree read as an asterisk.
		instance.rotate_object_local(Vector3.FORWARD, 0.48 + 0.12 * float(index % 2))
		instance.translate_object_local(Vector3(0.0, length * 0.45, 0.0))
		add_child(instance)
