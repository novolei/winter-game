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

## ---------------------------------------------------------------------------
## THE WORLD'S SHADING, WHICH ARRIVES FROM THE LIGHTING AND NOT FROM HERE
## ---------------------------------------------------------------------------
## LightingPreset carries `cel_band_threshold`, `cel_band_softness` and the
## colour the lit band takes from the light. They have to reach every material
## this class has ever made -- the ones made before the preset landed and the
## ones made after it, because a building instanced at runtime has to be lit like
## the buildings already standing.
##
## STATIC, and deliberately. A painter is a RefCounted made and dropped by
## whoever is placing a building, so there is no instance for the director to
## hold a reference to; and there is exactly one lighting rig in the game, so one
## set of values is the truth for all of them. The alternative -- every building
## script growing a _process that pulls the same four lines out of the
## ServiceRegistry -- is how a contract drifts, and it would have meant editing
## five files instead of this one.
##
## The register holds WEAK references. A strong one would make this the reason
## every material the game has ever built stays alive for the process's lifetime,
## which is a leak with a tidy name.
## HOW FAR ABOVE THE GROUND'S BAND A SOLID'S BAND SITS, and the reason the two
## are not the same number.
##
## A ground plane and a wall meet a 21.5-degree sun at completely different
## angles: flat snow sits at N.L = 0.37 whatever the azimuth, while a wall runs
## from 0.93 down to 0 depending on which way it faces. The ground was tuned to
## 0.12 by screenshot against `Refs/game ref/level.jpg`; `cel_flat.gdshader` has
## shipped at 0.30 since it was written, and at 0.12 a wall stays lit until it is
## 83 degrees off the sun instead of 71 -- which is a different building.
##
## So the preset moves BOTH and the gap between them is held. Daylight is
## 0.12 + 0.18 = 0.30, which is exactly what the farmstead ships with today, and
## the dark presets carry the solids up with the ground rather than leaving them
## behind.
const SOLID_BAND_OFFSET := 0.18

static var _band_threshold := 0.30
static var _band_softness := 0.07
static var _light_tint := Vector3(1.0, 1.0, 1.0)
static var _register: Array[WeakRef] = []

var _bible: ColorBible
var _shader: Shader
var _materials: Dictionary = {}
var _snow_step: int
var _structure_step: int


## Called by LightingDirector on every write -- once per preset change, and once
## per frame for the eight seconds a crossfade runs.
##
## `ground_threshold` is the preset's own value, the one the SNOW takes;
## SOLID_BAND_OFFSET above is what turns it into a wall's.
static func set_world_shading(ground_threshold: float, softness: float, tint: Color) -> void:
	_band_threshold = ground_threshold + SOLID_BAND_OFFSET
	_band_softness = softness
	_light_tint = Vector3(tint.r, tint.g, tint.b)
	var living: Array[WeakRef] = []
	for handle in _register:
		var material := handle.get_ref() as ShaderMaterial
		if material == null:
			continue
		_stamp(material)
		living.append(handle)
	_register = living


## How many materials the broadcast would currently reach. Exists so a test can
## prove the register drops what it no longer holds.
static func live_material_count() -> int:
	var alive := 0
	for handle in _register:
		if handle.get_ref() != null:
			alive += 1
	return alive


static func _stamp(material: ShaderMaterial) -> void:
	material.set_shader_parameter("band_threshold", _band_threshold)
	material.set_shader_parameter("band_softness", _band_softness)
	material.set_shader_parameter("light_tint", _light_tint)


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
	# Stamped with whatever the light currently is, then registered so the next
	# preset change finds it. Both halves matter: a building placed at midnight
	# must not arrive lit for noon, and it must not stay lit for midnight either.
	_stamp(material)
	_register.append(weakref(material))
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
