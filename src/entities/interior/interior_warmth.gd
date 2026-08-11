class_name InteriorWarmth
extends Node3D

## Makes the room amber while the fire burns, and stops the fire lighting the
## valley.
##
## GDD section 2's first pillar is 暖色即生存 -- warm IS survival -- and this
## room is the only warm thing in the game. The whole point of the interior
## reveal is that both halves of that contrast are in ONE frame: cold blue snow
## outside the wall that just vanished, amber inside it. If the revealed room is
## merely blue-lit-slightly-differently, the reveal has uncovered a box.
##
## ---------------------------------------------------------------------------
## TWO JOBS, ONE LIST
## ---------------------------------------------------------------------------
## `warm_parts` is what counts as "the room", and it is used twice:
##
## 1. THE COLOUR. Those surfaces are re-materialled onto
##    assets/shaders/cel_interior.gdshader, which carries a second pair of
##    palette entries and a `warmth` blend between them. See that shader for
##    why warmth cannot be a light colour under a two-band cel light().
##
## 2. THE RENDER LAYER. They are put on INTERIOR_LAYER, and the stove's own
##    light is culled to that layer, so the fire lights the room and NOTHING
##    else. This is the fix for a real defect: with the stove's OmniLight on
##    the default cull mask it shone straight through the walls -- it has
##    shadows off by design -- and pushed an 18 m disc of snow from the shade
##    band into the lit band. A bright, texel-stepped circle centred on the
##    house, which read as a debug gizmo. The reveal must change the building
##    and nothing else; the snow does not know the player went in.
##
##    Same mechanism, same reasoning and the same shape as
##    PlayerController.CHARACTER_LAYER, which aims the character's key light at
##    the character alone.
##
## ---------------------------------------------------------------------------
## WHAT DRIVES IT
## ---------------------------------------------------------------------------
## The fire, and only the fire -- NOT whether the player is inside. Two reasons.
## It is one rule instead of two, and this component stays independent of the
## reveal so a building can have either without the other. And it makes the
## room's colour a readout: come home on day 6 to a stove that burned out while
## you were away and the room is as blue as the snow, with no UI saying so.
##
## Nothing warm is visible from outside while the fire burns, so this needs no
## coupling to the reveal to stay honest: the parts on the list are the floor,
## the furniture and the shell walls, and the shell's only camera-facing faces
## are its inward ones -- the camera is fixed at yaw -35, so it sees the -X and
## +Z sides, and the shell holds the +X and -Z ones. Its foundation skirt is the
## one part of it that faces the camera, and the snow stands about half a metre
## over the top of that (see the wave-2 report), so it is not in any frame.

const CEL_INTERIOR_SHADER := "res://assets/shaders/cel_interior.gdshader"

## Bit 2. Bit 0 is everything, bit 1 is PlayerController.CHARACTER_LAYER.
## Bit 0 stays set on these surfaces: the sun still lights the room through the
## opened roof, and the walls still cast into the world's shadow map.
const INTERIOR_LAYER := 1 << 2

## What counts as the room, by name, resolved under `building_path`. Authored
## per building exactly like InteriorReveal.fade_parts, and for the same reason:
## wave 4 adds four more buildings and none of them may need new code.
@export var warm_parts: Array[StringName] = []

## Empty means the node this hangs under.
@export var building_path: NodePath = ^""

## Which entries of ColorBible.warm_tones the two bands read. Indices, not
## colours -- briefing constraint 6, no hardcoded hex outside tools/.
##
## 2 and 1 are #FFB257 amber over #A05A35 rust. The brightest warm entry as the
## LIT band is a deliberate choice and it is the one that makes the room read as
## amber rather than as brown: index 1 over 0 was tried and gives a room that is
## warm in name only, because the whole point is the contrast against a snow
## field that renders around #A8CCF0.
@export var warm_lit_slot := 2
@export var warm_shade_slot := 1

## Surfaces already on this warm slot are light SOURCES, not lit surfaces: the
## stove's firebox is the only one in this building. They get emission, and the
## Environment's existing glow blooms them. Art Bible rule 12's warm-pixel quota
## was written before there was an interior -- see the wave-2 report, which asks
## for interior lighting to be added to rule 12's list explicitly.
@export var emissive_slot := 2
@export var emission_strength := 1.6

## How long the room takes to catch, and to go cold. Slower than the reveal's
## 0.30 s on purpose: a roof coming off is an edit, a fire taking hold is not.
@export var warm_seconds := 0.8

## Where the fire is. Anything with is_lit() will do.
@export var fire_path: NodePath = ^""

## The same two steps CelPainter uses for the cold pair, so a warmed surface at
## warmth 0 is byte-identical to how the rest of the world is painted.
@export var snow_shade_step := 3
@export var structure_shade_step := 1

var _warmth := 0.0
var _resolved := false
var _parts: Array[GeometryInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _missing := PackedStringArray()
var _tween: Tween = null
var _fire = null


func _ready() -> void:
	# DEFERRED, and this is load-bearing. Children are ready before parents, so
	# this runs before Farmhouse._ready() -- which calls CelPainter.paint() over
	# its whole subtree and would overwrite every override set here. Deferring
	# puts the repaint after that pass instead of before it.
	_start.call_deferred()


func _start() -> void:
	resolve()
	_complain()


func set_fire(fire) -> void:
	_fire = fire


func building_node() -> Node:
	if not building_path.is_empty():
		var named := get_node_or_null(building_path)
		if named != null:
			return named
	return get_parent()


func fire() -> Node:
	if _fire != null and is_instance_valid(_fire):
		return _fire as Node
	if not fire_path.is_empty():
		_fire = get_node_or_null(fire_path)
	return _fire as Node


## Find the parts, repaint them, put them on the interior layer. Idempotent.
func resolve() -> void:
	_parts.clear()
	_materials.clear()
	_missing = PackedStringArray()
	_resolved = true
	var bible: ColorBible = load(CelPainter.PALETTE_PATH)
	var shader: Shader = load(CEL_INTERIOR_SHADER)
	var painter := CelPainter.new(snow_shade_step, structure_shade_step)
	var building := building_node()
	for name in warm_parts:
		var found: GeometryInstance3D = null
		if building != null:
			found = building.find_child(String(name), true, false) as GeometryInstance3D
		if found == null:
			_missing.append(String(name))
			continue
		_parts.append(found)
		found.layers |= INTERIOR_LAYER
		_repaint(found, painter, bible, shader)
	apply_warmth(_warmth)


## Shouted from _ready() and NOT from resolve(), so that a test may resolve a
## deliberately broken list and assert what came back without printing an
## engine-level ERROR into a suite whose output has to stay pristine (briefing
## constraint 1). Same split as InteriorReveal.
func _complain() -> void:
	var building := building_node()
	for name in _missing:
		push_error(
			"interior_warmth: no GeometryInstance3D called %s under %s; that part of "
			% [name, String(building.name) if building != null else "?"]
			+ "the room will stay as cold as the snow with nothing reporting it."
		)


func _repaint(part: GeometryInstance3D, painter: CelPainter, bible: ColorBible, shader: Shader) -> void:
	var instance := part as MeshInstance3D
	if instance == null or instance.mesh == null:
		return
	var warm_lit := _warm_tone(bible, warm_lit_slot)
	var warm_shade := _warm_tone(bible, warm_shade_slot)
	var emissive := _warm_tone(bible, emissive_slot)
	for surface in range(instance.mesh.get_surface_count()):
		# Off the mesh's own imported material, not off whatever override is
		# there: CelPainter may or may not have run yet, and the palette colour
		# resolved at import time is the one fact that is true either way.
		var existing := instance.mesh.surface_get_material(surface)
		var albedo := Color(1.0, 0.0, 1.0)
		if existing is BaseMaterial3D:
			albedo = (existing as BaseMaterial3D).albedo_color
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("lit_color", albedo)
		material.set_shader_parameter("shade_color", painter.shade_for(albedo))
		material.set_shader_parameter("warm_lit_color", warm_lit)
		material.set_shader_parameter("warm_shade_color", warm_shade)
		material.set_shader_parameter("emission_strength",
			emission_strength if CelPainter._same(albedo, emissive) else 0.0)
		instance.set_surface_override_material(surface, material)
		_materials.append(material)


func _warm_tone(bible: ColorBible, slot: int) -> Color:
	if bible == null or bible.warm_tones.is_empty():
		return Color(1.0, 0.0, 1.0)
	return bible.warm_tones[clampi(slot, 0, bible.warm_tones.size() - 1)]


# --- the warmth itself ------------------------------------------------------

func parts() -> Array[GeometryInstance3D]:
	return _parts


func unresolved() -> PackedStringArray:
	return _missing


func warmth() -> float:
	return _warmth


## The one place that writes the blend. Public for the same reason
## InteriorReveal.apply_fade is: it is the tween's target, and a test should not
## have to wait 0.8 s of wall clock to assert an endpoint.
func apply_warmth(value: float) -> void:
	if not is_finite(value):
		return
	_warmth = clampf(value, 0.0, 1.0)
	if not _resolved:
		resolve()
		return
	for material in _materials:
		material.set_shader_parameter("warmth", _warmth)


func warm_duration_to(target: float) -> float:
	return warm_seconds * absf(clampf(target, 0.0, 1.0) - _warmth)


func set_burning(burning: bool) -> void:
	var target := 1.0 if burning else 0.0
	if is_equal_approx(target, _warmth):
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	var duration := warm_duration_to(target)
	if not is_inside_tree() or duration <= 0.0:
		apply_warmth(target)
		return
	_tween = create_tween()
	_tween.tween_method(apply_warmth, _warmth, target, duration)


## Polled rather than driven off stove.lit / stove.went_out on the EventBus.
##
## The events exist and would work, but the fire also goes out by running out of
## fuel mid-frame and can be relit in the same second, and a room whose colour
## is a function of a boolean it reads every frame cannot drift out of step with
## it. It is one comparison against a bool.
func _process(_delta: float) -> void:
	var burning := fire()
	if burning == null:
		return
	set_burning(bool(burning.call(&"is_lit")))
