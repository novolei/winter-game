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

## ---------------------------------------------------------------------------
## THE SNOW THAT SETTLES ON EVERY SOLID
## ---------------------------------------------------------------------------
## src/systems/snow_accumulation.gd owns one scalar for the whole world and
## TerrainRenderer pushes it here every frame, the same way it pushes the
## lighting's band. The shape of the snow -- where the line sits at bare and at
## full, how ragged its edge is -- is authored HERE rather than left to the
## shader's uniform defaults, so that the two invariants below have an authority
## a test can read.
##
## Both are in assets/shaders/cel_flat.gdshader's own words, and both are
## asserted by tests/unit/test_snow_accumulation.gd:
##
##   SNOW_BARE_THRESHOLD - SNOW_EDGE_SOFTNESS > 1 + SNOW_NOISE_STRENGTH
##       at cover 0 nothing anywhere is covered, whatever its normal
##   SNOW_FULL_THRESHOLD - SNOW_EDGE_SOFTNESS > SNOW_NOISE_STRENGTH
##       a vertical wall is never covered, at any cover
##
## The margin on each is 0.15 and 0.10 of normal.y respectively. They are not
## style knobs: break the first and the world ships with a fleck of snow it can
## never take off, break the second and snow crawls down the walls in a storm.
##
## THE NOISE IS BELL-SHAPED, WHICH IS WHY THESE ARE NOT THE FIRST NUMBERS. Value
## noise is an interpolation between hashes, so its values crowd around the
## middle and the tails are rare -- the *effective* spread across a surface is
## perhaps half the nominal strength, not all of it. The first capture was
## authored against the nominal figure and the farmhouse roof went from a few
## flecks to completely white between cover 0.36 and 0.65, which is a third of
## the week rather than the whole of it, and which loses the ridge line that
## Art Bible rule 10 and tools/blender/build_farmhouse.py both go out of their
## way to keep. Widening the strength and moving the full threshold up to pay
## for it spreads the same transition over 0.67 of cover instead of 0.45.
const SNOW_BARE_THRESHOLD := 1.50
const SNOW_FULL_THRESHOLD := 0.45
const SNOW_EDGE_SOFTNESS := 0.05
const SNOW_NOISE_SCALE := 0.75
const SNOW_NOISE_STRENGTH := 0.30

## ---------------------------------------------------------------------------
## HOW READILY EACH OF THE TWELVE TAKES SNOW, and why it is a palette rule
## ---------------------------------------------------------------------------
## Style document section 18 asks for a snow_amount per object -- roof 0.75,
## car 0.25, pole 0.10, branches 0.35 -- and the brief for this task asks for
## one shader applied broadly with no per-object authoring. Those look opposed
## and are not, because what section 18 is actually protecting is Art Bible rule
## 12: the frame has three warm entries in it and they are the whole of its
## warmth, so snow must not be allowed to take them.
##
## That is a fact about the PALETTE, not about the objects, and the painter
## already keys one material per palette colour. So:
##
##   snow and structure   1.00   the world, and it goes under
##   warm paint           0.45   the truck's #6E2F2E, the scarf's #A05A35. Snow
##                               on the bonnet with the doors still red is what
##                               the reference shows; a white truck is the
##                               second visual centre gone.
##   warm light           0.00   #FFB257 is rule 12's lit windows, fire and
##                               beacons. A light with snow drawn over it is a
##                               light that has gone out.
##
## Three numbers, no per-object state, and every object in the game gets the
## right one for free because it was already painted from the twelve. A window
## pane is vertical and the normal test would spare it anyway; the zero is for
## the day something warm is modelled facing the sky -- a brazier, a lamp on a
## post, GDD section 6's beacon.
const WARM_LIGHT_INDEX := 2
const WARM_PAINT_RECEPTIVITY := 0.45

static var _band_threshold := 0.30
static var _band_softness := 0.07
static var _light_tint := Vector3(1.0, 1.0, 1.0)
static var _snow_cover := 0.0
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


## How much snow has settled on everything facing the sky, 0..1.
##
## A SEPARATE BROADCAST from set_world_shading() and deliberately so: the two
## change on completely different clocks. The light moves twice a day, in an
## eight-second crossfade; the snow moves continuously, every frame, for the
## whole run. Folding the cover into the lighting's call would make every
## caller of that one supply a snow depth it has no opinion about, and would
## have put the accumulation on the lighting's schedule -- which is the one
## thing src/systems/snow_accumulation.gd exists to keep it off.
##
## Pushed by TerrainRenderer, which already pulls the lighting's band from the
## ServiceRegistry every frame and is the one node in the world holding both a
## per-frame tick and a licence to reach for the paint shop.
static func set_snow_cover(cover: float) -> void:
	_snow_cover = clampf(cover, 0.0, 1.0)
	var living: Array[WeakRef] = []
	for handle in _register:
		var material := handle.get_ref() as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("snow_cover", _snow_cover)
		living.append(handle)
	_register = living


## What the last broadcast carried. For a test, and for a tuner reading the
## world's state without a frame in front of them.
static func snow_cover() -> float:
	return _snow_cover


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
	material.set_shader_parameter("snow_cover", _snow_cover)


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
	_stamp_snow_profile(material, lit)
	# Stamped with whatever the light and the weather currently are, then
	# registered so the next change of either finds it. Both halves matter: a
	# building placed at midnight in a blizzard must not arrive lit for noon and
	# bare, and it must not stay that way either.
	_stamp(material)
	_register.append(weakref(material))
	_materials[key] = material
	return material


## The shape of the snow, and which of the twelve refuses it. Written once at
## creation rather than on every broadcast: none of it moves, and the one thing
## that does -- the cover -- goes through _stamp().
func _stamp_snow_profile(material: ShaderMaterial, lit: Color) -> void:
	if _bible != null and _bible.snow_tones.size() > 3:
		material.set_shader_parameter("snow_lit", _bible.snow_tones[0])
		material.set_shader_parameter("snow_shade", _bible.snow_tones[3])
	material.set_shader_parameter("snow_receptivity", receptivity_for(lit))
	material.set_shader_parameter("snow_bare_threshold", SNOW_BARE_THRESHOLD)
	material.set_shader_parameter("snow_full_threshold", SNOW_FULL_THRESHOLD)
	material.set_shader_parameter("snow_edge_softness", SNOW_EDGE_SOFTNESS)
	material.set_shader_parameter("snow_noise_scale", SNOW_NOISE_SCALE)
	material.set_shader_parameter("snow_noise_strength", SNOW_NOISE_STRENGTH)


## How readily snow lies on a surface painted this colour. See the block above
## WARM_LIGHT_INDEX for the whole of the reasoning.
func receptivity_for(lit: Color) -> float:
	if _bible == null or _bible.warm_tones.size() <= WARM_LIGHT_INDEX:
		return 1.0
	for index in range(_bible.warm_tones.size()):
		if not _same(_bible.warm_tones[index], lit):
			continue
		return 0.0 if index == WARM_LIGHT_INDEX else WARM_PAINT_RECEPTIVITY
	return 1.0


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
