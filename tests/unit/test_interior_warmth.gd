extends TestCase

## The room is the only warm thing in the game.
##
## GDD section 2's first pillar is 暖色即生存, and this component is where that
## stops being a slogan: it is the difference between a reveal that uncovers a
## room and a reveal that uncovers a box. Two behaviours are protected here and
## both of them were defects before they were features.
##
##   1. THE ROOM GOES AMBER, AND ONLY WHILE THE FIRE BURNS. Under the world's
##      two-band cel light() a light cannot tint anything -- it picks between
##      two palette colours and never reads LIGHT_COLOR -- so warmth is a
##      second pair of palette entries and a blend, not a light. See
##      assets/shaders/cel_interior.gdshader.
##
##   2. THE FIRE DOES NOT LIGHT THE VALLEY. The stove's OmniLight has shadows
##      off by design, so on the default cull mask it shone through the walls
##      and lifted an 18 m disc of snow into the lit band -- a bright circle
##      centred on the house that read as a debug gizmo. Putting the room on
##      its own render layer is what lets that light be aimed at the room.
##
## Every subject is built with .new() and never enters the tree, so the blend
## snaps instead of tweening and every endpoint is assertable with no wall clock.

const InteriorWarmthScript := preload("res://src/entities/interior/interior_warmth.gd")
const ColorBibleScript := preload("res://src/definitions/color_bible.gd")

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CEL_INTERIOR_SHADER := "res://assets/shaders/cel_interior.gdshader"

const WARMED := [&"FH_Room", &"FH_Furniture"]
const LEFT_COLD := [&"FH_Porch"]

var _building: Node3D = null
var _fire: Node = null


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2).
	for node in [_building, _fire]:
		if node != null:
			node.free()
	_building = null
	_fire = null


# --- helpers ---------------------------------------------------------------

func _bible() -> ColorBible:
	return load(PALETTE_PATH)


## A building whose parts carry real palette colours, because that is what the
## component reads: the .glb's imported StandardMaterial3D albedo, resolved at
## import time by tools/palette_import_materials.gd.
func _build(names := WARMED) -> InteriorWarmth:
	var bible := _bible()
	_building = Node3D.new()
	_building.name = "Farmhouse"
	var model := Node3D.new()
	model.name = "Model"
	_building.add_child(model)
	var colors := {
		&"FH_Room": bible.structure_tones[1],
		# Two surfaces: the furniture's own tone and the firebox's amber, which
		# is the one that has to come out emissive.
		&"FH_Furniture": bible.warm_tones[2],
		&"FH_Porch": bible.snow_tones[1],
	}
	for part_name in WARMED + LEFT_COLD:
		var part := MeshInstance3D.new()
		part.name = String(part_name)
		var mesh := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[part_name]
		mesh.surface_set_material(0, material)
		part.mesh = mesh
		model.add_child(part)
	var warmth: InteriorWarmth = InteriorWarmthScript.new()
	var list: Array[StringName] = []
	list.assign(names)
	warmth.warm_parts = list
	_building.add_child(warmth)
	warmth.resolve()
	return warmth


func _part(part_name: StringName) -> MeshInstance3D:
	return _building.find_child(String(part_name), true, false) as MeshInstance3D


func _material(part_name: StringName) -> ShaderMaterial:
	return _part(part_name).get_surface_override_material(0) as ShaderMaterial


# --- the list ---------------------------------------------------------------

func test_it_finds_the_parts_it_was_handed_by_name() -> void:
	var warmth := _build()
	assert_eq(warmth.parts().size(), 2, "two names were given, %d resolved" % warmth.parts().size())
	assert_eq(warmth.unresolved().size(), 0, "nothing should be unresolved; got %s" % ", ".join(warmth.unresolved()))


func test_a_name_the_building_does_not_have_is_reported() -> void:
	var warmth := _build([&"FH_Room", &"FH_Cellar"])
	assert_eq(warmth.parts().size(), 1, "only one of the two names exists")
	assert_eq(
		Array(warmth.unresolved()), ["FH_Cellar"],
		"a part of the room that cannot be found must be nameable; got %s" % ", ".join(warmth.unresolved())
	)


# --- the light layer, which is what kills the disc --------------------------

func test_every_warmed_part_goes_on_the_interior_light_layer() -> void:
	var warmth := _build()
	for part_name in WARMED:
		assert_true(
			_part(part_name).layers & InteriorWarmthScript.INTERIOR_LAYER != 0,
			"%s is not on the interior layer, so the stove's light cannot be aimed at it" % part_name
		)


## Bit 0 is what the sun and the world's shadow map use. Replacing the mask
## rather than or-ing into it would take the room out of the sunlight and out of
## every shadow at once, and the room would go black the moment the roof lifted.
func test_the_interior_layer_is_added_to_the_default_and_does_not_replace_it() -> void:
	var warmth := _build()
	for part_name in WARMED:
		assert_true(
			_part(part_name).layers & 1 != 0,
			"%s lost render layer 1; the sun would stop lighting it" % part_name
		)


func test_a_part_that_is_not_on_the_list_is_left_on_the_default_layer() -> void:
	var warmth := _build()
	assert_eq(
		_part(&"FH_Porch").layers, 1,
		"FH_Porch is outside the room and must not be on the fire's layer"
	)


func test_the_interior_layer_is_not_the_character_layer() -> void:
	assert_true(
		InteriorWarmthScript.INTERIOR_LAYER != PlayerController.CHARACTER_LAYER,
		"the room and the character must be separately addressable by a light"
	)


# --- the warmth itself ------------------------------------------------------

func test_a_room_starts_cold() -> void:
	var warmth := _build()
	assert_almost_eq(warmth.warmth(), 0.0, 0.0001, "a room with no fire in it is as cold as the snow")
	for part_name in WARMED:
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("warmth")), 0.0, 0.0001,
			"%s starts on the cold pair" % part_name
		)


func test_a_burning_fire_makes_the_room_amber() -> void:
	var warmth := _build()
	warmth.set_burning(true)
	assert_almost_eq(warmth.warmth(), 1.0, 0.0001, "a burning fire warms the room fully")
	for part_name in WARMED:
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("warmth")), 1.0, 0.0001,
			"%s must be on the warm pair while the fire burns" % part_name
		)


## The readout GDD section 9 asks for and no HUD provides: come home to a stove
## that burned out while you were away, and the room is the same colour as the
## snow you walked through.
func test_a_fire_that_goes_out_takes_the_warmth_with_it() -> void:
	var warmth := _build()
	warmth.set_burning(true)
	warmth.set_burning(false)
	assert_almost_eq(warmth.warmth(), 0.0, 0.0001, "a dead fire leaves a cold room")


func test_the_warm_colours_come_off_the_palette() -> void:
	var warmth := _build()
	var bible := _bible()
	var material := _material(&"FH_Room")
	assert_eq(
		material.get_shader_parameter("warm_lit_color"), bible.warm_tones[warmth.warm_lit_slot],
		"the lit band must be a palette entry, never a literal (briefing constraint 6)"
	)
	assert_eq(
		material.get_shader_parameter("warm_shade_color"), bible.warm_tones[warmth.warm_shade_slot],
		"the shade band must be a palette entry"
	)


func test_the_cold_pair_is_the_colour_the_part_already_had() -> void:
	var warmth := _build()
	var bible := _bible()
	assert_eq(
		_material(&"FH_Room").get_shader_parameter("lit_color"), bible.structure_tones[1],
		"at warmth 0 a warmed surface must be exactly what CelPainter would have painted"
	)


func test_the_room_uses_the_interior_shader_and_not_a_stock_material() -> void:
	var warmth := _build()
	var material := _material(&"FH_Room")
	assert_not_null(material, "FH_Room has no surface override")
	if material == null:
		return
	assert_eq(
		material.shader.resource_path, CEL_INTERIOR_SHADER,
		"a warmed surface must be on the interior cel shader"
	)


func test_a_part_that_is_not_on_the_list_keeps_whatever_it_had() -> void:
	var warmth := _build()
	warmth.set_burning(true)
	assert_true(
		_part(&"FH_Porch").get_surface_override_material(0) == null,
		"FH_Porch is outside and must not be repainted by the interior"
	)


# --- emission ---------------------------------------------------------------

## Art Bible rule 12 lists where warm pixels may appear -- fire, windows,
## beacons, the scarf, the truck -- and the firebox is the first of them to be
## inside a room. Only a surface already on the emissive palette slot glows; the
## walls are lit, not luminous, and the difference is what keeps the fire the
## brightest thing in the frame.
func test_only_a_surface_on_the_emissive_slot_glows() -> void:
	var warmth := _build()
	assert_true(
		float(_material(&"FH_Furniture").get_shader_parameter("emission_strength")) > 0.0,
		"the firebox is on the emissive warm slot and must bloom"
	)
	assert_almost_eq(
		float(_material(&"FH_Room").get_shader_parameter("emission_strength")), 0.0, 0.0001,
		"the floor is lit, not luminous"
	)


# --- timing -----------------------------------------------------------------

func test_the_room_takes_time_to_catch_and_the_same_time_to_die() -> void:
	var warmth := _build()
	assert_true(warmth.warm_seconds > 0.0, "a room that snaps to amber reads as a switch, not a fire")
	assert_almost_eq(warmth.warm_duration_to(1.0), warmth.warm_seconds, 0.0001, "catching takes the full time")
	warmth.apply_warmth(1.0)
	assert_almost_eq(warmth.warm_duration_to(0.0), warmth.warm_seconds, 0.0001, "dying takes the full time")
	warmth.apply_warmth(0.5)
	assert_almost_eq(warmth.warm_duration_to(1.0), warmth.warm_seconds * 0.5, 0.0001, "a reversal runs at the same rate")


func test_the_blend_is_clamped() -> void:
	var warmth := _build()
	warmth.apply_warmth(9.0)
	assert_almost_eq(warmth.warmth(), 1.0, 0.0001, "warmth above 1 clamps")
	warmth.apply_warmth(-9.0)
	assert_almost_eq(warmth.warmth(), 0.0, 0.0001, "warmth below 0 clamps")
