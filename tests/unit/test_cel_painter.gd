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


## ---------------------------------------------------------------------------
## THE WORLD'S SHADING, WHICH ARRIVES FROM THE LIGHTING AND NOT FROM HERE
## ---------------------------------------------------------------------------
## `cel_band_threshold`, `cel_band_softness` and the colour the lit band takes
## from the light are authored on the six LightingPresets. They have to reach
## every material this painter has ever made, including the ones made before the
## preset landed and the ones made after it -- a building instanced at runtime
## has to be lit like the buildings that were already standing.
##
## The state is deliberately STATIC. A painter is a RefCounted created and
## dropped by whoever is placing a building, so there is no instance for the
## director to hold; and there is exactly one lighting rig in the game, so one
## set of values is the truth for all of them. The alternative -- every building
## script growing a _process that pulls from the ServiceRegistry -- puts the same
## four lines in five files and is the shape a contract drifts out of.

func test_a_material_built_after_the_light_lands_already_carries_it() -> void:
	CelPainterScript.set_world_shading(0.31, 0.09, Color(1.2, 0.98, 0.8))
	var material := _painter.material_for(_bible.snow_tones[0])
	assert_almost_eq(
		float(material.get_shader_parameter("band_threshold")),
		0.31 + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		"a wall's band is the ground's plus the offset -- see CelPainter.SOLID_BAND_OFFSET"
	)
	assert_almost_eq(float(material.get_shader_parameter("band_softness")), 0.09, 0.0001)
	var tint: Vector3 = material.get_shader_parameter("light_tint")
	assert_almost_eq(tint.x, 1.2, 0.0001, "the light's red")
	CelPainterScript.set_world_shading(0.12, 0.07, Color.WHITE)


## The other direction, and the one that actually matters in play: the farmstead
## is painted in _ready() and the light changes twice a day for the next seven
## days.
func test_a_material_built_before_the_light_changes_is_repainted_by_it() -> void:
	CelPainterScript.set_world_shading(0.12, 0.07, Color.WHITE)
	var material := _painter.material_for(_bible.structure_tones[0])
	CelPainterScript.set_world_shading(0.24, 0.10, Color(1.1, 1.0, 0.85))
	assert_almost_eq(
		float(material.get_shader_parameter("band_threshold")),
		0.24 + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		"a material already in the world kept the band it was built with"
	)
	var tint: Vector3 = material.get_shader_parameter("light_tint")
	assert_almost_eq(tint.z, 0.85, 0.0001, "the light's blue never reached a standing building")
	CelPainterScript.set_world_shading(0.12, 0.07, Color.WHITE)


## Materials are Resources and nothing frees them by hand, so the register that
## makes the broadcast possible must not be the thing that keeps them alive. It
## holds weak references and drops the dead ones on every broadcast.
func test_the_register_does_not_keep_a_dropped_material_alive() -> void:
	var before := CelPainterScript.live_material_count()
	var scratch: CelPainter = CelPainterScript.new()
	scratch.material_for(_bible.warm_tones[2])
	assert_true(
		CelPainterScript.live_material_count() > before,
		"a new material did not register itself, so a broadcast would never reach it"
	)
	scratch = null
	CelPainterScript.set_world_shading(0.12, 0.07, Color.WHITE)
	assert_eq(
		CelPainterScript.live_material_count(), before,
		"the register is still holding a material whose painter is gone"
	)


## ---------------------------------------------------------------------------
## THE SURFACES A SETTLED MASS DOES NOT LIE ON
## ---------------------------------------------------------------------------
## The wire, the insulators, the antenna, the roof planes and every tree in the
## wood are all PAL_STRUCT_4, so no rule keyed on colour can separate them. The
## build script says which is which in the material NAME, and this is the half
## of that contract that lives in the engine. Break it and two things regress at
## once: the power line goes dotted again (a 1.33 m pattern on a two-pixel wire),
## and the roof planes whiten behind their own modelled snow -- which is the
## defect the owner reported as the roof "resolving into rectangles".

func test_a_bare_slot_takes_no_snow_however_covered_the_world_is() -> void:
	var normal := _painter.material_for(_bible.structure_tones[3])
	var bare := _painter.material_for(_bible.structure_tones[3], true)
	assert_almost_eq(float(normal.get_shader_parameter("snow_receptivity")), 1.0, 0.0001)
	assert_almost_eq(float(bare.get_shader_parameter("snow_receptivity")), 0.0, 0.0001)


## Two materials, not one with a flag written over it. The roof planes and the
## trees are the same twelfth of the palette and only one of them refuses snow,
## so sharing would let whichever surface was painted last decide for both.
func test_a_bare_slot_is_its_own_material() -> void:
	var normal := _painter.material_for(_bible.structure_tones[3])
	var bare := _painter.material_for(_bible.structure_tones[3], true)
	assert_true(normal != bare, "the bare slot must not share the plain slot's material")
	assert_eq(bare.get_shader_parameter("lit_color"), _bible.structure_tones[3])
	assert_eq(bare.get_shader_parameter("shade_color"), _painter.shade_for(_bible.structure_tones[3]))


## The walk has to READ the mark, not just be able to honour one. This is the
## step that failed silently in the first attempt at this feature -- the data was
## in the model and nothing looked at it.
func test_painting_reads_the_bare_mark_off_the_material_name() -> void:
	var mesh := BoxMesh.new()
	var arriving := StandardMaterial3D.new()
	arriving.albedo_color = _bible.structure_tones[3]
	arriving.resource_name = "PAL_STRUCT_4_BARE"
	mesh.surface_set_material(0, arriving)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var holder := Node3D.new()
	holder.add_child(instance)

	_painter.paint(holder)

	var applied := instance.get_surface_override_material(0) as ShaderMaterial
	assert_not_null(applied)
	if applied != null:
		assert_almost_eq(
			float(applied.get_shader_parameter("snow_receptivity")), 0.0, 0.0001,
			"a surface whose palette slot is marked %s must refuse the settled snow"
				% CelPainterScript.BARE_SLOT_MARK
		)
	holder.free()


## ---------------------------------------------------------------------------
## THE SETTLED MASS
## ---------------------------------------------------------------------------
## Roof snow is not body snow. Body snow is powder caught in cloth and a noise
## threshold draws it well; roof snow is a mass that slumps, bulges at its edges
## and shows a cross-section at every boundary. A threshold has no thickness, so
## the mass is modelled geometry shipped as a blend shape and driven from here.

func test_a_bare_world_has_no_mass_and_a_buried_one_has_all_of_it() -> void:
	assert_almost_eq(CelPainterScript.snow_mass(0.0), 0.0, 0.0001, "a bare world must show no mass at all")
	assert_almost_eq(CelPainterScript.snow_mass(1.0), 1.0, 0.0001, "the deepest weather must settle the mass fully")


## 切记突变: the owner's one hard requirement on the whole accumulation. The mass
## is the most visible thing the cover drives, so a step anywhere in this mapping
## is a roof that changes between two frames.
func test_the_mass_never_jumps() -> void:
	var previous := CelPainterScript.snow_mass(0.0)
	var biggest := 0.0
	for step in range(1, 201):
		var mass := CelPainterScript.snow_mass(step / 200.0)
		assert_true(mass >= previous - 0.0001, "the mass went backwards at cover %.3f" % (step / 200.0))
		biggest = maxf(biggest, mass - previous)
		previous = mass
	# A linear ramp over the same span would move 0.0053 per step; anything much
	# above that is a corner rather than a curve.
	assert_true(biggest < 0.012, "the mass moves %.4f in one 0.005 step of cover, which is a jump" % biggest)


func test_a_mesh_that_ships_a_mass_is_driven_by_the_weather() -> void:
	var instance := _mass_instance()
	var holder := Node3D.new()
	holder.add_child(instance)

	_painter.paint(holder)
	CelPainterScript.set_snow_cover(0.0)
	assert_almost_eq(instance.get_blend_shape_value(0), 0.0, 0.0001, "a bare world left the roof carrying snow")
	CelPainterScript.set_snow_cover(0.62)
	assert_almost_eq(
		instance.get_blend_shape_value(0), CelPainterScript.snow_mass(0.62), 0.0001,
		"the broadcast did not reach the mass"
	)

	CelPainterScript.set_snow_cover(0.0)
	holder.free()


## A building placed mid-run has to arrive carrying the weather that is already
## outside -- the same claim the materials make, and the one that is easy to miss
## because a scene built at cover 0 never shows it.
func test_a_mass_adopted_after_the_snow_arrived_catches_up_at_once() -> void:
	CelPainterScript.set_snow_cover(0.80)
	var instance := _mass_instance()
	var holder := Node3D.new()
	holder.add_child(instance)

	_painter.paint(holder)
	assert_almost_eq(
		instance.get_blend_shape_value(0), CelPainterScript.snow_mass(0.80), 0.0001,
		"a building placed in deep winter arrived with a bare roof"
	)

	CelPainterScript.set_snow_cover(0.0)
	holder.free()


## The register holds weak references for the same reason the materials' does,
## and for a sharper one: a MeshInstance3D is a Node the tree frees the moment a
## building is removed, so a strong reference here is a demolished shed that
## stays in memory and a broadcast that writes to it.
func test_the_mass_register_does_not_keep_a_freed_instance_alive() -> void:
	var before := CelPainterScript.live_mass_count()
	var holder := Node3D.new()
	holder.add_child(_mass_instance())
	_painter.paint(holder)
	assert_true(
		CelPainterScript.live_mass_count() > before,
		"a mesh carrying a mass did not register, so the weather would never reach it"
	)
	holder.free()
	CelPainterScript.set_snow_cover(0.0)
	assert_eq(
		CelPainterScript.live_mass_count(), before,
		"the register is still holding a mesh whose building is gone"
	)


## The accumulation system reports its continuous cover every rendered frame,
## but a shader cannot distinguish values inside one 8-bit cover interval.  A
## second broadcast inside that interval used to allocate two weak-reference
## arrays and rewrite every solid and roof mass for no visible result.  The
## first value that crosses out of the interval must still reach both paths.
func test_same_snow_cover_bucket_skips_writes_but_a_crossing_reaches_materials_and_masses() -> void:
	var material := _painter.material_for(_bible.structure_tones[0])
	var holder := Node3D.new()
	var instance := _mass_instance()
	holder.add_child(instance)
	_painter.paint(holder)

	CelPainterScript.set_snow_cover(0.5000)
	var after_first: Dictionary = CelPainterScript.snow_cover_write_counts()
	CelPainterScript.set_snow_cover(0.5005)
	var same_bucket: Dictionary = CelPainterScript.snow_cover_write_counts()
	assert_eq(
		int(same_bucket["materials"]), int(after_first["materials"]),
		"two covers in one shader-visible bucket still rewrote every material"
	)
	assert_eq(
		int(same_bucket["masses"]), int(after_first["masses"]),
		"two covers in one shader-visible bucket still rewrote every roof mass"
	)

	CelPainterScript.set_snow_cover(0.5100)
	var crossed: Dictionary = CelPainterScript.snow_cover_write_counts()
	assert_true(
		int(crossed["materials"]) > int(same_bucket["materials"]),
		"crossing a shader-visible bucket did not update the standing material"
	)
	assert_true(
		int(crossed["masses"]) > int(same_bucket["masses"]),
		"crossing a shader-visible bucket did not update the standing roof mass"
	)
	assert_almost_eq(
		float(material.get_shader_parameter("snow_cover")), 0.5100, 0.0001,
		"the crossing never reached the material's visible cover"
	)
	assert_almost_eq(
		instance.get_blend_shape_value(0), CelPainterScript.snow_mass(0.5100), 0.0001,
		"the crossing never reached the roof's snow-mass curve"
	)

	holder.free()


## A triangle with one blend shape named the way the build scripts name theirs.
## Deliberately NOT the farmhouse: this is the contract, and a unit test that
## loads a 1,400-triangle building to check it would go red for reasons that have
## nothing to do with the claim.
func _mass_instance() -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape(CelPainterScript.SNOW_MASS_SHAPE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var settled := []
	settled.resize(Mesh.ARRAY_MAX)
	settled[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.UP, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [settled])
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance
