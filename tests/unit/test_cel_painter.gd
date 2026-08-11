extends TestCase

## The one piece of shading logic that is not in a shader.
##
## Every solid in the world -- house, shed, truck, pole, trees -- arrives from
## Blender as a StandardMaterial3D holding a palette albedo, and every one of
## them is re-materialled onto the two-band cel shader on the way into the
## scene. The lit band is the albedo the palette already resolved. The *shade*
## band is chosen here, by walking down the same palette family, and that choice
## is the difference between the farmstead looking like it is standing in the
## snow and looking like a render pasted onto a painting.
##
## Art Bible section 4.1 is the rule being kept: the dark band is another entry
## from the 12-colour table, never the lit colour multiplied by a factor,
## because a multiply produces colours that are not in the table.

const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const FarmhouseScript := preload("res://src/entities/farmhouse.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"

var _bible: ColorBible
var _painter: CelPainter


func before_each() -> void:
	_bible = load(PALETTE_PATH)
	_painter = CelPainterScript.new()


## Snow steps three, because that is exactly the pair the ground uses --
## TerrainRenderer lights snow_tones[0] and shades snow_tones[3]. Snow on a roof
## has to take the same two colours as snow beside it or the roof line announces
## itself as a different material.
func test_snow_shades_to_the_same_pair_the_ground_uses() -> void:
	assert_eq(_painter.shade_for(_bible.snow_tones[0]), _bible.snow_tones[3])
	assert_eq(_painter.shade_for(_bible.snow_tones[1]), _bible.snow_tones[4])


## Structure steps one. The sun is at azimuth 118 against a camera yawed -35, so
## it is nearly behind the lens and every wall the camera can see is in the
## shade band -- the shaded colour is the building's colour on screen, not an
## accent, and two steps put the walls within a hair of the roof.
func test_structure_shades_one_step_down() -> void:
	assert_eq(_painter.shade_for(_bible.structure_tones[0]), _bible.structure_tones[1])
	assert_eq(_painter.shade_for(_bible.structure_tones[2]), _bible.structure_tones[3])


## Rule 12's warm accents are lit windows, fire and beacons. A window that goes
## dark on the shaded side of a building is a window with the light off.
func test_warm_does_not_shade_at_all() -> void:
	for index in range(_bible.warm_tones.size()):
		assert_eq(_painter.shade_for(_bible.warm_tones[index]), _bible.warm_tones[index])


## Stepping past the end of a family clamps rather than wrapping into another
## one, which would be an off-family colour arriving with no diagnostic.
func test_the_step_clamps_at_the_darkest_entry() -> void:
	var darkest_snow: Color = _bible.snow_tones[_bible.snow_tones.size() - 1]
	assert_eq(_painter.shade_for(darkest_snow), darkest_snow)
	var darkest_structure: Color = _bible.structure_tones[_bible.structure_tones.size() - 1]
	assert_eq(_painter.shade_for(darkest_structure), darkest_structure)


## tools/palette_import_materials.gd paints an unrecognised palette slot magenta
## on purpose, so a typo in a Blender material name becomes a loud red gate
## rather than a part that quietly keeps whatever the exporter wrote. That only
## works if magenta survives this step -- shading it into a palette colour would
## launder the failure into something that passes every art gate.
func test_an_off_palette_colour_passes_through_unchanged() -> void:
	var magenta := Color(1.0, 0.0, 1.0)
	assert_eq(_painter.shade_for(magenta), magenta)


## Ten palette slots must cost ten materials, not one per surface across every
## mesh in the farmstead.
func test_one_material_is_shared_by_every_surface_of_the_same_colour() -> void:
	var first := _painter.material_for(_bible.structure_tones[0])
	var again := _painter.material_for(_bible.structure_tones[0])
	var other := _painter.material_for(_bible.structure_tones[2])
	assert_true(first == again, "the same palette colour must return the same material instance")
	assert_true(first != other, "two palette colours must not share one material")
	assert_not_null(first.shader)
	assert_eq(first.get_shader_parameter("lit_color"), _bible.structure_tones[0])
	assert_eq(first.get_shader_parameter("shade_color"), _bible.structure_tones[1])


## The walk itself: a mesh arriving with a stock PBR material must leave with a
## surface override on the cel shader carrying the colour it came in with.
func test_painting_replaces_a_stock_material_and_keeps_its_colour() -> void:
	var mesh := BoxMesh.new()
	var arriving := StandardMaterial3D.new()
	arriving.albedo_color = _bible.structure_tones[0]
	mesh.surface_set_material(0, arriving)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var holder := Node3D.new()
	holder.add_child(instance)

	_painter.paint(holder)

	var applied := instance.get_surface_override_material(0)
	assert_not_null(applied)
	assert_true(applied is ShaderMaterial, "the surface must end up on the cel shader, not on a StandardMaterial3D")
	if applied is ShaderMaterial:
		assert_eq((applied as ShaderMaterial).get_shader_parameter("lit_color"), _bible.structure_tones[0])
	# Node is not reference counted (briefing section 2.2); freeing the holder
	# takes the instance with it.
	holder.free()


## The house and the props have to agree, or the roof of one shed is shaded
## differently from the roof of the building beside it. This is the drift the
## extraction was for, and it is one line either way.
func test_the_farmhouse_asks_for_the_same_steps_the_painter_defaults_to() -> void:
	var house: Farmhouse = FarmhouseScript.new()
	var as_the_house_asks: CelPainter = CelPainterScript.new(house.snow_shade_step, house.structure_shade_step)
	assert_eq(as_the_house_asks.shade_for(_bible.snow_tones[0]), _painter.shade_for(_bible.snow_tones[0]))
	assert_eq(
		as_the_house_asks.shade_for(_bible.structure_tones[0]),
		_painter.shade_for(_bible.structure_tones[0])
	)
	house.free()
