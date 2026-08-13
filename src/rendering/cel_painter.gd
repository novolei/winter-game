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

## ---------------------------------------------------------------------------
## THE SURFACES A SETTLED MASS DOES NOT LIE ON
## ---------------------------------------------------------------------------
## The three numbers above are facts about a palette COLOUR, and two kinds of
## surface need something a colour cannot say:
##
##   * a HAIRLINE. The shader's snow pattern is 1.33 m across and a power wire is
##     one to two pixels at the game camera. A wire cannot carry a pattern; it
##     can only break into dashes, and a wire breaking into dashes reads as a
##     MESH COMING APART. Measured on the shipped scene at one camera: solid line
##     at cover 0.362, dotted at 0.620, and it begins at 0.14.
##   * a ROOF PLANE that carries a modelled settled mass. Two white things on one
##     roof is the whole of the defect this closes -- the mass's silhouette stops
##     reading the moment the plane behind it is white too, and what the eye
##     picks out instead is its stepped edges and its cast shadows. The owner's
##     own words, from play: the roof "resolves into rectangles".
##
## The wire, the insulators, the antenna, the roof planes and every tree in the
## wood are all `PAL_STRUCT_4`, so `receptivity_for()` cannot separate them. The
## PART can, and it says so in the material name the build script already
## authors: `PAL_STRUCT_4_BARE` is the same colour with the snow refused.
## tools/blender/propkit.py carries the reasoning and the measurement behind
## choosing a name over a vertex attribute.
const BARE_SLOT_MARK := "_BARE"

## ---------------------------------------------------------------------------
## THE MASS ITSELF, and why this class drives it
## ---------------------------------------------------------------------------
## Roof snow and body snow are different materials and must not share a look.
## Body snow is powder caught in cloth -- noise-broken patches with ragged edges,
## which is src/entities/snow_load.gd's job and correct there. Roof snow is a
## settled MASS: it slumps under its own weight, its edges roll off and bulge,
## and it reads smooth and swelling. At every boundary it shows a cross-section,
## and that cross-section is where the thickness lives.
##
## A threshold in a shader cannot draw that, because a threshold has no
## thickness -- it can only pick a side of a line, and both sides are the same
## flat plane. So the mass is GEOMETRY, shipped in the .glb as a blend shape
## named `snow_mass`: collapsed inside the roof slab at one end of its travel,
## and at the other a mass 0.24 m thick whose lip rolls out past the eave.
##
## It is driven from HERE rather than from a building script for the same reason
## the light is: there is one world scalar, it moves every frame, and a building
## instanced at runtime has to carry the same weather as the ones already
## standing. `paint()` already walks every mesh in a model, so adopting the ones
## that can grow costs one test per mesh and no new wiring anywhere.
const SNOW_MASS_SHAPE := "snow_mass"

## Below this the world has a dusting rather than a mass, and a dusting has no
## cross-section to show. Above it the mass builds continuously for the rest of
## the run -- `smoothstep`, so its rate is continuous at both ends too and there
## is no frame at which the roof changes suddenly.
const SNOW_MASS_ONSET := 0.06

## ---------------------------------------------------------------------------
## THE SECOND REGISTER, AND WHY A ROOM CANNOT JOIN THE FIRST ONE
## ---------------------------------------------------------------------------
## `assets/shaders/cel_interior.gdshader` carries the same two-band contract as
## `cel_flat` and was on nobody's broadcast for three waves -- the farmhouse
## interior sat at its authored boundary from PALE DAY to DEEP NIGHT while the
## valley outside the door moved by 4.64x in luminance. See
## `.superpowers/sdd/wave3/task-w3-lighting-audit-report.md` section 6.1, and
## `tests/art/test_cel_band_broadcast.gd`, which is the gate that now enumerates
## every cel-banded shader and proves each is actually receiving.
##
## The obvious repair is to append an interior material to `_register` above, and
## it is wrong on two counts:
##
##   * **The numbers.** `_stamp()` writes the WALL's band -- the ground's plus
##     SOLID_BAND_OFFSET, tuned against a 21.5-degree sun on flat snow. A room is
##     lit by a point source standing IN it, so its band term is the angle to the
##     fire and the distance from it. At DEEP NIGHT's 0.42 the boundary is a ring
##     about two metres from the stove. A fire does not weaken at three in the
##     morning and the band it casts must not either.
##   * **The rest of the stamp.** `snow_cover` is meaningless on a floor, and the
##     tint has to be gated on whether the fire is burning.
##
## So a room registers as an OBJECT and recomputes its own shading from the
## world's, exactly as `_masses` does for a settled roof mass. `InteriorWarmth`
## owns that arithmetic and `assets/shaders/cel_interior.gdshader` carries the
## reasoning; this class's whole job here is to make sure the room is told.
##
## Weak, for the same reason both other registers are: a strong reference would
## make this the reason a demolished building stayed in memory.
static var _band_threshold := 0.30
static var _band_softness := 0.07
static var _light_tint := Vector3(1.0, 1.0, 1.0)
static var _tint_color := Color.WHITE
static var _snow_cover := 0.0
static var _register: Array[WeakRef] = []
static var _masses: Array[WeakRef] = []
static var _rooms: Array[WeakRef] = []

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
	_tint_color = tint
	var living: Array[WeakRef] = []
	for handle in _register:
		var material := handle.get_ref() as ShaderMaterial
		if material == null:
			continue
		_stamp(material)
		living.append(handle)
	_register = living

	var standing: Array[WeakRef] = []
	for handle in _rooms:
		# Read untyped, check, then narrow (briefing trap 18): a statically
		# Variant source is validated at the ASSIGNMENT, so `var room: Node =
		# handle.get_ref()` would throw on a freed room one line before the guard
		# that exists to catch it -- and take every room after it in this list.
		var raw: Variant = handle.get_ref()
		if raw == null or not is_instance_valid(raw):
			continue
		standing.append(handle)
		raw.apply_world_shading(_band_threshold, _band_softness, _tint_color)
	_rooms = standing


## A room that wants the world's shading pushed to it.
##
## An EXPLICIT registration and not a sweep for whoever answers the method name.
## Briefing trap 16 is the third instance in this project of a system that
## discovers collaborators by method name having an API surface much larger than
## its class, and the fix recorded there is exactly this: drive who registered,
## not everyone who happens to look right.
##
## Idempotent, because `InteriorWarmth.resolve()` is.
## Duck-typed rather than typed `InteriorWarmth`, and the shout is what pays for
## it: this class is generic rendering and that one is a game entity, so naming
## it here would point the dependency backwards. The check is at REGISTRATION and
## not in the sweep, so a wiring mistake shouts once at the moment it is made
## rather than sixty times a second for the rest of the run.
static func register_room(room) -> void:
	if room == null or not is_instance_valid(room):
		return
	if not room.has_method("apply_world_shading"):
		push_error(
			"cel_painter: %s registered as a room and cannot answer apply_world_shading(), "
				% str(room)
				+ "so it would sit at its shader's authored band for the whole run"
		)
		return
	for handle in _rooms:
		if handle.get_ref() == room:
			return
	_rooms.append(weakref(room))
	# Stamped with whatever the light currently is, then registered so the next
	# change finds it -- the same both-halves contract `material_for()` keeps. A
	# building placed at midnight must not arrive lit for the boot frame, and it
	# must not stay that way either.
	room.apply_world_shading(_band_threshold, _band_softness, _tint_color)


## How many rooms the broadcast would currently reach. Exists so a test can prove
## the register drops what it no longer holds.
static func live_room_count() -> int:
	var alive := 0
	for handle in _rooms:
		if handle.get_ref() != null:
			alive += 1
	return alive


## THE THREE VALUES A SOLID CURRENTLY TAKES FROM THE LIGHT.
##
## Published because a room resolving mid-run has to be able to ask what the
## world is doing rather than start at a script default and wait for the next
## preset change -- which, on a day with no weather, is up to ten minutes away
## (lighting audit section 3).
##
## `world_band_threshold()` is the WALL's number, SOLID_BAND_OFFSET already
## added, because the surfaces in a room are walls.
static func world_band_threshold() -> float:
	return _band_threshold


static func world_band_softness() -> float:
	return _band_softness


static func world_light_tint() -> Color:
	return _tint_color


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

	var mass := snow_mass(_snow_cover)
	var standing: Array[WeakRef] = []
	for handle in _masses:
		var instance := handle.get_ref() as MeshInstance3D
		if instance == null:
			continue
		_set_mass(instance, mass)
		standing.append(handle)
	_masses = standing


## How far the modelled roof mass has grown, 0 collapsed .. 1 fully settled.
##
## Static and public because it is the one number that decides what the roofs
## look like, and a test asserting the shape of the settling has to be able to
## ask for it without a frame.
static func snow_mass(cover: float) -> float:
	return smoothstep(SNOW_MASS_ONSET, 1.0, clampf(cover, 0.0, 1.0))


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


## The same, for the meshes carrying a settled mass. A separate register from
## the materials': a material is a Resource nothing frees by hand, a mesh
## instance is a Node the scene tree frees the moment a building is removed, and
## a strong reference here would be the reason a demolished shed stayed in
## memory.
static func live_mass_count() -> int:
	var alive := 0
	for handle in _masses:
		if handle.get_ref() != null:
			alive += 1
	return alive


## Which blend shape on this instance is the settled mass, or -1.
##
## Asked of the MESH rather than through MeshInstance3D's own lookup, because
## the mesh is where the names live and a null mesh is the ordinary state of an
## instance a test has just constructed.
##
## **The cast to ArrayMesh is load-bearing.** `get_blend_shape_count()` is
## declared on ArrayMesh, not on Mesh, so calling it on the BoxMesh a test builds
## -- or on any PrimitiveMesh the game ever places -- is a script error, and a
## script error aborts the caller rather than returning something wrong. Every
## imported .glb arrives as an ArrayMesh; nothing else can carry a blend shape.
static func mass_shape_index(instance: MeshInstance3D) -> int:
	if instance == null:
		return -1
	var mesh := instance.mesh as ArrayMesh
	if mesh == null:
		return -1
	for index in range(mesh.get_blend_shape_count()):
		if mesh.get_blend_shape_name(index) == SNOW_MASS_SHAPE:
			return index
	return -1


static func _set_mass(instance: MeshInstance3D, mass: float) -> void:
	var index := mass_shape_index(instance)
	if index >= 0:
		instance.set_blend_shape_value(index, mass)


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
				var bare := false
				if existing is BaseMaterial3D:
					albedo = (existing as BaseMaterial3D).albedo_color
				if existing != null:
					# `contains` rather than `ends_with`: Godot's glTF importer
					# appends `.001` to a duplicated material name, and the
					# palette gate already matches these by prefix for the same
					# reason.
					bare = existing.resource_name.contains(BARE_SLOT_MARK)
				instance.set_surface_override_material(surface, material_for(albedo, bare))
		_adopt_mass(instance)
	for child in node.get_children():
		paint(child)


## Take over any mesh that ships a settled mass, and set it to the weather that
## is already outside. Both halves matter for the same reason the materials'
## do: a shed placed on day 5 must not arrive with a bare roof, and it must not
## stay that way either.
func _adopt_mass(instance: MeshInstance3D) -> void:
	if mass_shape_index(instance) < 0:
		return
	for handle in _masses:
		if handle.get_ref() == instance:
			return
	_masses.append(weakref(instance))
	_set_mass(instance, snow_mass(_snow_cover))


## One material per palette colour, so ten slots cost ten materials rather than
## one per surface across every mesh in the farmstead.
##
## `bare` is part of the key, not a property written onto a shared material: the
## roof planes and the trees are the same colour and only one of them refuses
## snow, so they have to be two materials or the last surface painted would
## decide for both.
func material_for(lit: Color, bare := false) -> ShaderMaterial:
	var key := "%s|%s" % [lit.to_html(false), bare]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("lit_color", lit)
	material.set_shader_parameter("shade_color", shade_for(lit))
	_stamp_snow_profile(material, lit, bare)
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
func _stamp_snow_profile(material: ShaderMaterial, lit: Color, bare := false) -> void:
	if _bible != null and _bible.snow_tones.size() > 3:
		material.set_shader_parameter("snow_lit", _bible.snow_tones[0])
		material.set_shader_parameter("snow_shade", _bible.snow_tones[3])
	material.set_shader_parameter("snow_receptivity", 0.0 if bare else receptivity_for(lit))
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
