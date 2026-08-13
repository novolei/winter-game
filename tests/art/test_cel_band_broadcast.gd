extends TestCase

## THE LIST NOBODY HAD EVER CHECKED.
##
## ---------------------------------------------------------------------------
## WHY THIS FILE EXISTS
## ---------------------------------------------------------------------------
## `assets/shaders/cel_interior.gdshader` was not on the lighting's broadcast for
## three waves. The farmhouse interior -- the one room in the game, the place the
## player shelters, sleeps and survives the night -- sat at whatever band it was
## authored with while the valley outside moved from PALE DAY to DEEP NIGHT. **A
## room whose light never changes is a room outside time**, in a game whose whole
## structure is seven days passing.
##
## It was found by accident, by the lighting audit, while it was looking for
## something else (`.superpowers/sdd/wave3/task-w3-lighting-audit-report.md`
## section 6.1). That is the part worth building a gate around: **one consumer
## found by accident means the list has never been enumerated at all.** There is
## no reason to believe the next cel shader will be wired either, and there is no
## reason to believe anybody would notice.
##
## Nothing errors when a broadcast misses a consumer. `set_shader_parameter` on a
## material nobody registered is not a failure -- it simply never happens, and
## the shader falls back to the default written in its own source. Which is a
## plausible-looking picture. That is the same shape as briefing traps 3, 13 and
## 16: a mechanism you assumed was running was not, and the output looked like
## art direction.
##
## ---------------------------------------------------------------------------
## WHAT COUNTS AS A CONSUMER
## ---------------------------------------------------------------------------
## The marker is the shader's own `band_threshold` uniform. A shader declaring it
## is asking to be told **where the boundary between the two cel bands falls**,
## and that is a per-preset quantity by construction -- `LightingPreset` carries
## it, the six presets author it from 0.10 to 0.35, and Art Bible section 4.1
## makes the two bands the whole shading model.
##
## Derived from the files rather than from a hardcoded list, so a tenth shader
## added next wave is judged the day it lands. `DRIVEN_BY` below is the declared
## register, and the two are checked against each other in BOTH directions: a
## shader missing from the register fails, and a register entry naming a shader
## that no longer exists fails too.
##
## This is the `WIND_CONSUMERS` shape the briefing asks for after trap 16 --
## **declare who is eligible, rather than discovering them and hoping.**
##
## ---------------------------------------------------------------------------
## AND THEN ACTUALLY DRIVE THEM
## ---------------------------------------------------------------------------
## A register is a claim. Every entry below is also exercised: a preset is applied
## through the real `LightingDirector`, and the value is read back off the
## material the consumer actually draws with. `test_lighting_director.gd` puts it
## exactly right for the exterior -- "`set_shader_parameter` on a uniform nothing
## reads is silent, so the only honest gate is the one that reads the value back
## off a material" -- and this file extends that to every consumer at once.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const TerrainRendererScript := preload("res://src/rendering/terrain_renderer.gd")
const InteriorWarmthScript := preload("res://src/entities/interior/interior_warmth.gd")
const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

## The same three roots `test_shader_compiles.gd` walks, and for the same reason:
## a shader is not required to live under `assets/shaders/`, and a gate that
## covers only the tidy case is blind to the untidy one. `res://addons` is
## deliberately absent -- a vendored shader is not ours to wire.
const SHADER_ROOTS: Array[String] = ["res://assets", "res://src", "res://scenes"]

## The marker uniform. See the header.
const BAND_UNIFORM := "band_threshold"

## THE REGISTER. Every cel-banded shader in the project, and the one place that
## is supposed to tell it where its boundary is.
##
## RAISE OR EXTEND THIS WHEN A CEL SHADER IS ADDED, and wire the shader in the
## same commit -- the entry is a promise the tests below then hold you to.
const DRIVEN_BY := {
	"res://assets/shaders/cel_flat.gdshader": "CelPainter.set_world_shading()",
	"res://assets/shaders/cel_interior.gdshader": "InteriorWarmth.apply_world_shading()",
	"res://assets/shaders/snow_ground.gdshader": "TerrainRenderer.apply_world_shading()",
}

## A preset far from every shader's authored default, so a uniform that did not
## move is unmistakable. DEEP NIGHT is also the case that matters: it is the
## largest step the run ever plays, and it is the night the room exists for.
const PROBE_PRESET := &"deep_night"

var _director: LightingDirector = null
var _bus = null
var _renderer: TerrainRenderer = null
var _building: Node3D = null


## Every subject here is a Node (briefing constraint 2).
func after_each() -> void:
	for node in [_director, _bus, _renderer, _building]:
		if node != null:
			node.free()
	_director = null
	_bus = null
	_renderer = null
	_building = null


# --- the register ------------------------------------------------------------


## Every `.gdshader` the project authors that declares the band uniform.
##
## Matched at the start of a statement rather than anywhere in the line, so the
## word appearing in a comment -- and this project's shaders are more comment
## than code -- is not mistaken for a declaration. Same test
## `test_shader_compiles.gd` applies, for the same reason.
func _cel_banded_shaders() -> Array[String]:
	var found: Array[String] = []
	for root in SHADER_ROOTS:
		for path in AssetScannerScript.find_files(root, [".gdshader"] as Array[String]):
			if found.has(path):
				continue
			for raw_line in FileAccess.get_file_as_string(path).split("\n"):
				var line := raw_line.strip_edges()
				if line.begins_with("uniform ") and line.contains(BAND_UNIFORM):
					found.append(path)
					break
	found.sort()
	return found


## THE ONE THAT WOULD HAVE CAUGHT IT.
##
## Both directions, because each catches a different mistake: a shader missing
## from the register is a new consumer nobody wired, and a register entry with no
## shader behind it is a wiring that outlived the thing it drove.
func test_every_cel_banded_shader_is_on_the_register() -> void:
	var shaders := _cel_banded_shaders()
	assert_true(
		shaders.size() >= DRIVEN_BY.size(),
		("found %d cel-banded shader(s) under %s, and the register names %d."
			% [shaders.size(), str(SHADER_ROOTS), DRIVEN_BY.size()])
			+ " Below the register size this gate is judging fewer shaders than"
			+ " it claims to, which is how the interior went three waves unlit."
	)
	for path in shaders:
		assert_true(
			DRIVEN_BY.has(path),
			("%s declares `%s` but nothing on the register drives it." % [path, BAND_UNIFORM])
				+ " A shader asking where its cel boundary falls and never being"
				+ " told sits at its own authored default for the whole run,"
				+ " through every preset, and nothing errors."
		)
	for path in DRIVEN_BY:
		assert_true(
			shaders.has(path),
			"the register claims %s is driven by %s, and that shader no longer declares `%s`"
				% [path, DRIVEN_BY[path], BAND_UNIFORM]
		)


# --- and then actually drive them ---------------------------------------------


func _director_at(preset_id: StringName) -> LightingDirector:
	_bus = EventBusScript.new()
	_director = LightingDirectorScript.new()
	# _ready() is called by hand because nothing is in a tree (briefing trap 1).
	_director._ready()
	_director.set_event_bus(_bus)
	_director.apply_preset(preset_id)
	return _director


## The ground. It PULLS rather than being pushed, from `_process`, so this
## exercises the same call `TerrainRenderer` makes with the director's own
## published values rather than with numbers typed twice.
func test_the_ground_receives_the_band_the_preset_asks_for() -> void:
	var director := _director_at(PROBE_PRESET)
	var look := director.preset(PROBE_PRESET)
	assert_not_null(look, "no preset '%s'" % PROBE_PRESET)
	if look == null:
		return
	_renderer = TerrainRendererScript.new()
	_renderer._ready()
	_renderer.apply_world_shading(
		director.cel_band_threshold(), director.cel_band_softness(), director.world_light_tint()
	)
	var material := _renderer.material_override as ShaderMaterial
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)), look.cel_band_threshold, 0.0001,
		"the ground did not take %s's band" % PROBE_PRESET
	)


## Every solid. Pushed, because a `CelPainter` is a RefCounted nobody holds.
func test_every_solid_receives_the_band_the_preset_asks_for() -> void:
	var director := _director_at(PROBE_PRESET)
	var look := director.preset(PROBE_PRESET)
	assert_not_null(look, "no preset '%s'" % PROBE_PRESET)
	if look == null:
		return
	var painter := CelPainterScript.new()
	var material := painter.material_for(load(CelPainterScript.PALETTE_PATH).structure_tones[0])
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)),
		look.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		"a wall did not take %s's band" % PROBE_PRESET
	)


## THE ROOM, which is the one that was not.
##
## Asserted at warmth 0 -- a room whose fire has gone out -- because that is the
## state `cel_interior.gdshader`'s own header promises is "cel_flat exactly". A
## cold room standing in DEEP NIGHT has to band like every other wall in the
## valley, and until this landed it banded like a wall at noon.
##
## What it does with the fire LIT is a separate question with a separate answer;
## `tests/unit/test_interior_warmth.gd` holds that one.
func test_a_cold_room_receives_the_band_the_preset_asks_for() -> void:
	var director := _director_at(PROBE_PRESET)
	var look := director.preset(PROBE_PRESET)
	assert_not_null(look, "no preset '%s'" % PROBE_PRESET)
	if look == null:
		return
	var warmth := _room()
	warmth.apply_warmth(0.0)
	var material := _room_material()
	assert_not_null(material, "the room was not repainted onto the interior shader at all")
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)),
		look.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		("a cold room banded at %s instead of %s's %.3f."
			% [
				str(material.get_shader_parameter(BAND_UNIFORM)),
				PROBE_PRESET,
				look.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET
			])
			+ " The valley outside the door moved and the room did not, which is"
			+ " a room outside time."
	)


## THE PUSH ITSELF, which is the half the other three cannot see.
##
## A room seeds its world values from CelPainter at construction, so a room built
## AFTER a preset landed is correct whether or not the broadcast reaches it. That
## makes the tests either side of this one necessary and not sufficient --
## deleting the registration entirely leaves all three of them green, which was
## measured before this method was written.
##
## The room the player lives in is built once, on frame one, and stands there for
## seven days. Everything that happens to its light after that arrives by PUSH.
## So: resolve the room first, change the preset after, and read the material.
func test_a_room_already_standing_follows_the_preset_when_it_changes() -> void:
	var director := _director_at(&"pale_day")
	var warmth := _room()
	warmth.apply_warmth(0.0)
	var day := director.preset(&"pale_day")
	var night := director.preset(PROBE_PRESET)
	assert_not_null(day, "no preset 'pale_day'")
	assert_not_null(night, "no preset '%s'" % PROBE_PRESET)
	if day == null or night == null:
		return
	var material := _room_material()
	assert_not_null(material, "the room was not repainted onto the interior shader at all")
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)),
		day.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		"the room did not start at the light that was already on"
	)
	director.apply_preset(PROBE_PRESET)
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)),
		night.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		("night fell on the valley and the room the player lives in kept the band"
			+ " it was built with. This is the defect, and it is the one nothing"
			+ " else in this file can see -- the room is built on frame one and"
			+ " everything that happens to its light after that arrives by push.")
	)


## A room built AFTER the preset landed takes it too.
##
## The same half of the contract `CelPainter.material_for()` keeps for a building
## instanced at runtime: wave 4 adds four more buildings, and a room resolved on
## day 5 must not arrive lit for the day the process started.
func test_a_room_resolved_after_the_preset_landed_is_not_lit_for_the_boot_frame() -> void:
	var director := _director_at(&"pale_day")
	director.apply_preset(&"whiteout")
	var look := director.preset(&"whiteout")
	assert_not_null(look, "no preset 'whiteout'")
	if look == null:
		return
	var warmth := _room()
	warmth.apply_warmth(0.0)
	var material := _room_material()
	assert_not_null(material, "the room was not repainted onto the interior shader at all")
	if material == null:
		return
	assert_almost_eq(
		float(material.get_shader_parameter(BAND_UNIFORM)),
		look.cel_band_threshold + CelPainterScript.SOLID_BAND_OFFSET, 0.0001,
		"a room resolved during the storm still carries the band the process booted with"
	)


## The register holds WEAK references, and this is the proof.
##
## A strong one would make CelPainter the reason a demolished building stayed in
## memory -- the same leak the material and mass registers are weak to avoid, and
## the same one briefing constraint 2 is about. A `Node` is not reference
## counted, so a room the scene tree frees has to fall out of here by itself.
func test_a_demolished_room_falls_off_the_broadcast() -> void:
	_director_at(PROBE_PRESET)
	var before := CelPainterScript.live_room_count()
	_room()
	assert_eq(
		CelPainterScript.live_room_count(), before + 1,
		"resolving a room did not put it on the broadcast at all"
	)
	# Node is not reference counted (briefing constraint 2). after_each() frees
	# _building too; freeing twice is guarded by nulling it here.
	_building.free()
	_building = null
	assert_eq(
		CelPainterScript.live_room_count(), before,
		"a freed room is still on the register, so CelPainter is why a demolished building stays in memory"
	)


# --- a room to look at --------------------------------------------------------


## The smallest building `InteriorWarmth` will accept: one named part carrying a
## real palette albedo, which is what the component reads off the imported mesh.
func _room() -> InteriorWarmth:
	var bible: ColorBible = load(CelPainterScript.PALETTE_PATH)
	_building = Node3D.new()
	_building.name = "Farmhouse"
	var part := MeshInstance3D.new()
	part.name = "FH_Room"
	var mesh := BoxMesh.new()
	var imported := StandardMaterial3D.new()
	imported.albedo_color = bible.structure_tones[1]
	mesh.surface_set_material(0, imported)
	part.mesh = mesh
	_building.add_child(part)
	var warmth: InteriorWarmth = InteriorWarmthScript.new()
	# Annotated, not `var list = []`: an untyped local makes the compiler emit an
	# untyped Array and the typed setter rejects it, aborting the rest of this
	# function with every later assertion silently unrun (briefing trap 4).
	var list: Array[StringName] = []
	list.assign([&"FH_Room"])
	warmth.warm_parts = list
	_building.add_child(warmth)
	warmth.resolve()
	return warmth


func _room_material() -> ShaderMaterial:
	var part := _building.find_child("FH_Room", true, false) as MeshInstance3D
	if part == null:
		return null
	return part.get_surface_override_material(0) as ShaderMaterial
