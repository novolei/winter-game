class_name CelPainter
extends RefCounted

## Re-materials an imported model onto the world's two-band cel shader.
##
## Every .glb in this project arrives painted in flat palette colour by
## tools/palette_import_materials.gd. That is correct as *albedo* and it is what
## the art gates judge, but a StandardMaterial3D is lit by Godot's stock PBR: a
## smooth Lambert ramp, plus the Environment's ambient, plus the exposure. The
## snow beside it is lit by a two-band cel light() with ambient_light_disabled,
## which picks a palette colour outright and is multiplied by nothing.
##
## Left alone, every solid in the frame is shaded by a different model from the
## ground it stands on, and the whole farmstead reads as a render pasted into a
## painting. So every surface goes onto assets/shaders/cel_flat.gdshader -- the
## same shader and the same two bands as the terrain.
##
## This started inside src/entities/farmhouse.gd and moved out the moment a
## second thing in the world needed it. The two shade steps are the part worth
## sharing: the snow lying on a shed roof has to take the same two colours as
## the snow lying beside it, or the roof line announces itself as a different
## material.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CEL_SHADER_PATH := "res://assets/shaders/cel_flat.gdshader"

var _bible: ColorBible
var _shader: Shader
var _materials: Dictionary = {}
var _snow_step: int
var _structure_step: int


## How far down the palette the shadow band sits, per family.
##
## Each family gets the step the world already uses for it, rather than one rule
## applied to both. Snow is 3 because that is exactly the ground's own pair --
## TerrainRenderer lights snow_tones[0] and shades snow_tones[3]. Structure is 1
## because that is the blocked-out sheds' pair, and because of where the sun is:
## at azimuth 118 against a camera yawed -35 the sun is almost behind the lens,
## so **every wall the camera can see is in the shade band**. The shaded colour
## is not an accent, it is the building's colour on screen, and at 2 the walls
## came out within a hair of the roof and the house read as one black mass.
##
## Warm is 0 on purpose: rule 12's warm accents are the lit windows and the
## firebox, and a window that goes dark on the shaded side is a window with the
## light off.
func _init(snow_shade_step := 3, structure_shade_step := 1) -> void:
	_snow_step = snow_shade_step
	_structure_step = structure_shade_step
	_bible = load(PALETTE_PATH)
	_shader = load(CEL_SHADER_PATH)


## Every surface under `node` onto the cel shader, keeping the colour the
## palette already resolved for it.
##
## The lit band is read off the imported material's albedo rather than off its
## slot name, so this stays correct if a part is ever moved from one palette
## slot to another in Blender -- the name is the .glb's business, the colour is
## the palette's, and this only needs the colour.
func paint(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var existing := mesh.surface_get_material(surface)
				var albedo := Color(1.0, 0.0, 1.0)
				if existing is BaseMaterial3D:
					albedo = (existing as BaseMaterial3D).albedo_color
				instance.set_surface_override_material(surface, material_for(albedo))
	for child in node.get_children():
		paint(child)


## One material per palette colour, so ten slots cost ten materials rather than
## one per surface across every mesh in the farmstead.
func material_for(lit: Color) -> ShaderMaterial:
	var key := lit.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("lit_color", lit)
	material.set_shader_parameter("shade_color", shade_for(lit))
	_materials[key] = material
	return material


## The shaded band for a lit palette colour: the same family, a fixed number of
## steps darker, clamped at the darkest entry. A colour that is not in the
## palette at all -- the magenta the import script paints an unrecognised slot
## -- is returned unchanged, so it stays magenta in both bands and remains the
## loud failure it was built to be.
func shade_for(lit: Color) -> Color:
	if _bible == null:
		return lit
	for family in [
		{"tones": _bible.snow_tones, "step": _snow_step},
		{"tones": _bible.structure_tones, "step": _structure_step},
		{"tones": _bible.warm_tones, "step": 0},
	]:
		var tones: Array = family["tones"]
		for index in range(tones.size()):
			if not _same(tones[index], lit):
				continue
			return tones[mini(index + int(family["step"]), tones.size() - 1)]
	return lit


## The same 1/255 tolerance ColorBible.contains() uses, and for the same reason:
## the colour has been through an 8-bit albedo field on the way here.
static func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 0.004 and absf(a.g - b.g) <= 0.004 and absf(a.b - b.b) <= 0.004
