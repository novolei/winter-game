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
##   3. THE ROOM HAS FORM IN IT. The first version handed every warmed surface
##      the same warm pair, and at warmth 1 the blend reaches the far end -- so
##      the floor, the walls, the table and the bed all arrived at the identical
##      two colours and the payoff frame of the whole game was an even orange
##      field with the furniture invisible inside it. The warm pair is now
##      chosen per part off a ladder, and these tests are what stop it
##      collapsing back to one.
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
func _build(names := WARMED, furnishings := []) -> InteriorWarmth:
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
		# A furnishing that is NOT already warm, so the ladder actually moves for
		# it -- the table, the bench, the bed frame.
		&"FH_Table": bible.structure_tones[2],
	}
	for part_name in WARMED + LEFT_COLD + [&"FH_Table"]:
		var part := MeshInstance3D.new()
		part.name = String(part_name)
		var mesh := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[part_name]
		mesh.surface_set_material(0, material)
		part.mesh = mesh
		model.add_child(part)
	var warmth: InteriorWarmth = InteriorWarmthScript.new()
	# Annotated, not `var list = []`: an untyped local makes the compiler emit an
	# untyped Array and the typed setter rejects it, aborting the rest of this
	# function with every later assertion silently unrun (briefing trap 4).
	var list: Array[StringName] = []
	list.assign(names)
	warmth.warm_parts = list
	var stood_on: Array[StringName] = []
	stood_on.assign(furnishings)
	warmth.furnishing_parts = stood_on
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


# --- the two tiers, which are what put form back in the room ----------------

## THE REGRESSION TEST FOR THE ORANGE BOX.
##
## `mix(lit_color, warm_lit_color, warmth)` at warmth 1 is warm_lit_color
## outright, so whatever pair a surface is handed IS its colour in the frame the
## whole reveal exists to produce. One pair for the room means one colour for the
## room. A furnishing has to arrive on a different, darker pair or the table is
## the same value as the floor it stands on.
func test_a_furnishing_takes_a_darker_warm_pair_than_the_field() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	var field := _material(&"FH_Room")
	var stood_on := _material(&"FH_Table")
	assert_true(
		_luma(stood_on.get_shader_parameter("warm_lit_color"))
			< _luma(field.get_shader_parameter("warm_lit_color")),
		"a furnishing's lit band is not darker than the field's, so the room is flat again"
	)
	assert_true(
		_luma(stood_on.get_shader_parameter("warm_shade_color"))
			< _luma(field.get_shader_parameter("warm_shade_color")),
		"a furnishing's shade band is not darker than the field's"
	)


## One rung, exactly. The furnishing's LIT band is the field's SHADE band, which
## is what makes it impossible for a piece of furniture to out-value the room it
## stands in whichever band either of them is in.
func test_a_furnishing_can_never_out_value_the_field() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	assert_eq(
		_material(&"FH_Table").get_shader_parameter("warm_lit_color"),
		_material(&"FH_Room").get_shader_parameter("warm_shade_color"),
		"the ladder has more than one rung between the field and what stands on it"
	)


func test_the_two_tiers_come_off_the_palette_and_not_out_of_a_literal() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	var bible := _bible()
	for pair in [
		{"part": &"FH_Room", "drop": 0},
		{"part": &"FH_Table", "drop": warmth.furnishing_drop},
	]:
		var expected: Array[Color] = warmth.warm_pair_for(int(pair["drop"]))
		var material := _material(pair["part"])
		assert_eq(
			material.get_shader_parameter("warm_lit_color"), expected[0],
			"%s's lit band is not the palette entry its tier names" % pair["part"]
		)
		assert_eq(
			material.get_shader_parameter("warm_shade_color"), expected[1],
			"%s's shade band is not the palette entry its tier names" % pair["part"]
		)
		assert_true(
			bible.warm_tones.has(expected[0]) and bible.warm_tones.has(expected[1]),
			"both bands must be entries of ColorBible.warm_tones (briefing constraint 6)"
		)


## The firebox is a light SOURCE. Art Bible rule 12 spends warm pixels on the
## fire before anything else, so a stove that went one rung down because a stove
## is furniture would be a fire behind smoked glass.
func test_a_surface_already_warm_keeps_the_brightest_pair_wherever_it_is_listed() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Furniture"])
	var bible := _bible()
	assert_eq(
		_material(&"FH_Furniture").get_shader_parameter("warm_lit_color"),
		bible.warm_tones[warmth.warm_lit_slot],
		"the firebox dropped a rung with the furniture it is built into"
	)
	assert_true(
		float(_material(&"FH_Furniture").get_shader_parameter("emission_strength")) > 0.0,
		"the firebox stopped glowing"
	)


func test_a_furnishing_is_on_the_fires_render_layer_too() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	assert_true(
		_part(&"FH_Table").layers & InteriorWarmthScript.INTERIOR_LAYER != 0,
		"a furnishing off the interior layer is furniture the fire cannot light"
	)
	assert_eq(warmth.parts().size(), 2, "both lists must resolve into the same part list")


func test_a_furnishing_name_the_building_does_not_have_is_reported() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Cellar"])
	assert_eq(
		Array(warmth.unresolved()), ["FH_Cellar"],
		"a missing furnishing must be nameable; got %s" % ", ".join(warmth.unresolved())
	)


# --- where the band boundary falls ------------------------------------------

## WITH THE FIRE AT FULL, THE ROOM'S BAND IS THE FIRE'S AND NOT THE SUN'S.
##
## This is the answer to the design question inside the broadcast defect, and it
## is the reason the fix is not "register the interior with CelPainter and let
## the exterior's numbers land on it". They are the wrong numbers: at DEEP NIGHT
## a wall bands at 0.42, and at 0.42 the boundary is a ring about two metres from
## the stove with five-sixths of the floor outside it. **A room at night with a
## fire lit is not DEEP NIGHT.** Nothing about the fire dims at three in the
## morning, so nothing about the band it casts may either.
func test_a_lit_room_holds_its_own_band_against_the_night() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	warmth.apply_world_shading(0.42, 0.10, Color.WHITE)
	warmth.apply_warmth(1.0)
	for part_name in [&"FH_Room", &"FH_Table"]:
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("band_threshold")),
			warmth.fire_band_threshold, 0.0001,
			("%s banded at the valley's boundary while the stove was burning." % part_name)
				+ " Outdoors the sun weakens and more of the world falls into shade;"
				+ " indoors the fire does not weaken, and the band must not move."
		)
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("band_softness")),
			warmth.fire_band_softness, 0.0001,
			"%s did not take the fire's own softness" % part_name
		)


## AND WITH THE FIRE OUT, IT IS THE WORLD'S.
##
## `cel_interior.gdshader`'s own header promises that "`warmth` at 0 is this
## shader being cel_flat exactly". It was not, and could not be: cel_flat's band
## moves with the preset and the interior's was a constant. A cold room in DEEP
## NIGHT banded like a wall at noon.
##
## The room going cold and the room rejoining the world are the same event.
func test_a_cold_room_bands_like_every_other_wall_in_the_valley() -> void:
	var warmth := _build([&"FH_Room"], [&"FH_Table"])
	warmth.apply_world_shading(0.42, 0.10, Color.WHITE)
	warmth.apply_warmth(0.0)
	for part_name in [&"FH_Room", &"FH_Table"]:
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("band_threshold")),
			0.42, 0.0001,
			"%s did not take the world's band once its fire had gone out" % part_name
		)
		assert_almost_eq(
			float(_material(part_name).get_shader_parameter("band_softness")),
			0.10, 0.0001,
			"%s did not take the world's softness once its fire had gone out" % part_name
		)


## And between them it travels, on the same 0.8 s the colour does.
##
## One blend, not two: a room whose colour and whose shading crossed over at
## different moments would show the handover, and the handover is the thing that
## has to be invisible.
func test_the_band_travels_with_the_warmth_rather_than_switching() -> void:
	var warmth := _build()
	warmth.apply_world_shading(0.42, 0.10, Color.WHITE)
	warmth.apply_warmth(0.5)
	assert_almost_eq(
		float(_material(&"FH_Room").get_shader_parameter("band_threshold")),
		(0.42 + warmth.fire_band_threshold) * 0.5, 0.0001,
		"the band jumped rather than travelling, so the handover is visible"
	)
	assert_almost_eq(
		float(_material(&"FH_Room").get_shader_parameter("band_softness")),
		(0.10 + warmth.fire_band_softness) * 0.5, 0.0001,
		"the softness jumped rather than travelling"
	)


## THE WORLD'S LIGHT COLOUR REACHES A COLD ROOM AND NOT A BURNING ONE.
##
## `world_light_tint` is the hue the SUN lends the lit band -- SUNRISE's amber,
## which is the only preset that carries any. A room lit by its own fire has no
## business taking the sun's hue on top of the fire's: rule 3 of the UI document
## states the law the whole project shares, that **a warm pixel means the presence
## of heat and nothing else**, and the heat in that room is the stove. Stacking
## dawn's amber on the stove's amber would make the room warmer for a reason that
## is not heat.
##
## So the tint arrives in exact proportion to how far the fire has died -- which
## is the same proportion the band arrives on, and for the same reason.
func test_the_suns_hue_reaches_a_cold_room_and_not_a_burning_one() -> void:
	var warmth := _build()
	var dawn := Color(1.18, 0.98, 0.72)
	warmth.apply_world_shading(0.30, 0.07, dawn)
	warmth.apply_warmth(0.0)
	var cold: Vector3 = _material(&"FH_Room").get_shader_parameter("light_tint")
	assert_almost_eq(cold.x, dawn.r, 0.0001, "a cold room refused the sun's hue")
	assert_almost_eq(cold.z, dawn.b, 0.0001, "a cold room refused the sun's hue")
	warmth.apply_warmth(1.0)
	var burning: Vector3 = _material(&"FH_Room").get_shader_parameter("light_tint")
	assert_almost_eq(
		burning.x, 1.0, 0.0001,
		"the sun's amber was stacked on the stove's, so part of that room is warm for a reason that is not heat"
	)
	assert_almost_eq(burning.z, 1.0, 0.0001, "the sun's hue reached a room the sun does not light")


## THE HATCH GUARD, NOW HELD ACROSS EVERY PRESET AND EVERY WARMTH.
##
## The sun still reaches a revealed room, and it meets the inward face of the
## back wall at N.L = 0.129 -- see LightingDirector.sun_azimuth_degrees and
## sun_elevation_degrees, from which this number is derived below rather than
## typed. A band boundary anywhere near it puts the largest shape in the frame
## exactly ON the threshold, where the directional shadow's sampled penumbra is
## quantised into a hatch across the whole wall. Art Bible rule 10's own
## technical note is that **a cel band is a threshold, and a threshold cannot
## consume a filtered shadow**; this is the arithmetic that keeps the boundary
## off it.
##
## It used to check one number, because the room only had one. Now the room's
## boundary travels between its own and the world's, so the guard has to hold at
## both ends of that travel, at every preset -- and because `threshold - softness`
## is linear in the blend, holding at both ends holds everywhere between.
func test_the_band_boundary_clears_the_grazing_sun_at_every_preset() -> void:
	var warmth := _build()
	var elevation := deg_to_rad(21.5)
	var azimuth := deg_to_rad(82.0)
	# The direction back toward the sun, and the inward normal of a wall whose
	# outward face is -Z. Same construction as LightingDirector._write().
	var to_sun := Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
	var grazing: float = maxf(to_sun.dot(Vector3(0.0, 0.0, 1.0)), 0.0)
	assert_almost_eq(grazing, 0.1295, 0.002, "the wall's grazing lambert is not what the tuning assumed")
	assert_true(
		warmth.fire_band_threshold - warmth.fire_band_softness > grazing,
		"the fire's band boundary (%.3f - %.3f) sits on the sun's grazing hit (%.3f) on the back wall"
			% [warmth.fire_band_threshold, warmth.fire_band_softness, grazing]
	)
	var presets := _presets()
	assert_true(presets.size() == 6, "Art Bible section 4.2 names six, and this gate read %d" % presets.size())
	for look in presets:
		var threshold: float = look.cel_band_threshold + CelPainter.SOLID_BAND_OFFSET
		assert_true(
			threshold - look.cel_band_softness > grazing,
			("%s hands a cold room a boundary of %.3f - %.3f, which sits on the sun's"
				% [look.id, threshold, look.cel_band_softness])
				+ " grazing hit (%.3f) on the back wall -- Art Bible rule 10's hatch." % grazing
		)


## The six, off disk. Read rather than constructed, because the numbers that
## matter here are the authored ones.
func _presets() -> Array:
	var found: Array = []
	var dir := DirAccess.open("res://data/lighting")
	if dir == null:
		return found
	for file in dir.get_files():
		# `.import` and `.uid` sidecars are listed beside the resource
		# (briefing trap 17); take the suffix wanted rather than excluding the
		# suffixes known to be bad.
		if not file.ends_with(".tres"):
			continue
		var look: LightingPreset = load("res://data/lighting/%s" % file)
		if look != null:
			found.append(look)
	return found


## Perceived brightness, sRGB-weighted. Enough to rank three palette entries,
## and deliberately not a colour comparison: the point of the ladder is VALUE.
func _luma(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


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
