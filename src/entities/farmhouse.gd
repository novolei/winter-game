class_name Farmhouse
extends Node3D

## Stands the hero building on the snow and paints it with the world's shader.
##
## Two jobs, and both of them exist because the model cannot know them:
##
## 1. WHERE THE GROUND IS. The terrain is procedural noise regenerated around
##    the player, so no height can be baked into scenes/main.tscn. The building
##    samples the snow surface under its own footprint at _ready() and sits on
##    the lowest point it finds -- see _settle().
##
## 2. WHAT IT IS LIT BY. The .glb arrives painted in flat palette colour by
##    tools/palette_import_materials.gd, which is correct as *albedo* and is
##    what the art gates judge. But a StandardMaterial3D is lit by Godot's stock
##    PBR: a smooth Lambert ramp, plus the Environment's ambient, plus the 1.3
##    exposure. The snow beside it is lit by a two-band cel light() with
##    ambient_light_disabled, which picks a palette colour outright and is
##    multiplied by nothing. Left alone the house is the one solid in the frame
##    shaded by a different model from the ground it stands on, and it reads as
##    a render pasted into a painting. So every surface is re-materialled onto
##    assets/shaders/cel_flat.gdshader here -- the same shader, and the same two
##    bands, as the blocked-out sheds and the trees.
##
## THE REVEAL SYSTEM IS NOT BUILT HERE. Fading FH_Fade_Roof / FH_Fade_Front /
## FH_Fade_Porch when the player crosses the threshold is a later wave. What
## this does do is check the three names still resolve after placement, loudly,
## because the failure mode is a wall left standing in front of the camera with
## nothing anywhere reporting it.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CEL_SHADER_PATH := "res://assets/shaders/cel_flat.gdshader"

## Named here only so placing the house cannot quietly break them. The list is
## the same one in tests/art/test_farmhouse_model.gd and in DEFAULT_REVEAL in
## tools/blender/build_farmhouse.py; those two are the contract, this is a
## smoke alarm.
const REVEAL_GROUPS: Array[String] = ["FH_Fade_Roof", "FH_Fade_Front", "FH_Fade_Porch"]

## The model's own footprint about its origin, from its bind-pose AABB:
## x -3.90..+3.89, z -6.30..+3.89. Sampled on a 1 m grid, which is finer than
## anything a 20 m noise swell does inside 10 m.
@export var footprint_min := Vector2(-3.9, -6.3)
@export var footprint_max := Vector2(3.9, 3.9)
@export var footprint_step := 1.0

## Pushed a little further into the snow than the lowest point strictly needs,
## so the foundation reads as bedded in rather than as resting on the surface.
## Small: the foundation slab is only 0.30 m tall.
@export var bed_depth := 0.08

## How far down the palette the shadow band sits, per family.
##
## Each family gets the step the world already uses for it, rather than one
## rule applied to both. Snow is 3 because that is exactly the ground's own
## pair -- TerrainRenderer lights snow_tones[0] and shades snow_tones[3] -- so
## the snow lying on this roof takes the same two colours as the snow lying
## beside it and the roof line does not announce itself as a different
## material. Structure is 1 because that is the blocked-out sheds' pair, and
## because of where the sun is: at azimuth 118 against a camera yawed -35 the
## sun is almost behind the lens, so **every wall the camera can see is in the
## shade band**. The shaded colour is not an accent here, it is the building's
## colour on screen, and at 2 the walls came out within a hair of the roof and
## the whole house read as one black mass. Compared side by side at the same
## framing; the screenshots are in the wave report.
##
## Warm is 0 on purpose: rule 12's warm accents are the lit windows and the
## firebox, and a window that goes dark on the shaded side of the building is a
## window with the light off.
@export var snow_shade_step := 3
@export var structure_shade_step := 1

var _bible: ColorBible
var _shader: Shader
var _materials: Dictionary = {}


func _ready() -> void:
	_bible = load(PALETTE_PATH)
	_shader = load(CEL_SHADER_PATH)
	_repaint(self)
	_settle()
	_check_reveal_groups()


## Sit on the lowest snow surface anywhere under the footprint.
##
## The lowest rather than the average, and that is the whole decision. Sitting
## on the average puts the downhill corner in the air, and a building with
## daylight under one corner is unmistakable at any distance; sitting on the
## lowest point buries the uphill corner instead, and a building with snow
## banked up one wall is what a farmhouse in a drift looks like anyway.
##
## The cost is stated rather than hidden: the terrain here has no flat ground,
## so the burial is however much the snow surface rises across ten metres.
## Choosing the site is what keeps that small -- see the wave report.
##
## Sampled through the *snow* surface, not the bare ground, because the snow is
## what is drawn. A hollow holds most of a metre of it and that is a metre of
## gap it can hide.
func _settle() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	var snow := registry.get_service(&"snow_field") as Node
	if snow == null:
		return
	var lowest := INF
	var here := global_position
	var basis := global_transform.basis
	var x := footprint_min.x
	while x <= footprint_max.x:
		var z := footprint_min.y
		while z <= footprint_max.y:
			var spot: Vector3 = here + basis * Vector3(x, 0.0, z)
			var surface: float = snow.terrain_height_at(spot) + snow.depth_at(spot)
			lowest = minf(lowest, surface)
			z += footprint_step
		x += footprint_step
	if lowest == INF:
		return
	global_position.y = lowest - bed_depth


## Every surface onto the world's cel shader, keeping the colour the palette
## already resolved for it.
##
## The lit band is read off the imported material's albedo rather than off its
## slot name, so this stays correct if a part is ever moved from one palette
## slot to another in Blender -- the name is the .glb's business, the colour is
## the palette's, and this only needs the colour.
func _repaint(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var existing := mesh.surface_get_material(surface)
				var albedo := Color(1.0, 0.0, 1.0)
				if existing is BaseMaterial3D:
					albedo = (existing as BaseMaterial3D).albedo_color
				instance.set_surface_override_material(surface, _cel_material(albedo))
	for child in node.get_children():
		_repaint(child)


## One material per palette colour, so ten slots cost ten materials rather than
## one per surface across nine meshes.
func _cel_material(lit: Color) -> ShaderMaterial:
	var key := lit.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("lit_color", lit)
	material.set_shader_parameter("shade_color", _shade_for(lit))
	_materials[key] = material
	return material


## The shaded band for a lit palette colour: the same family, a fixed number of
## steps darker, clamped at the darkest entry. A colour that is not in the
## palette at all -- the magenta the import script paints an unrecognised slot
## -- is returned unchanged, so it stays magenta in both bands and remains the
## loud failure it was built to be.
func _shade_for(lit: Color) -> Color:
	if _bible == null:
		return lit
	for family in [
		{"tones": _bible.snow_tones, "step": snow_shade_step},
		{"tones": _bible.structure_tones, "step": structure_shade_step},
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
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 0.004 and absf(a.g - b.g) <= 0.004 and absf(a.b - b.b) <= 0.004


func _check_reveal_groups() -> void:
	for group in REVEAL_GROUPS:
		if find_child(group, true, false) == null:
			push_error(
				"farmhouse: %s is not under this node any more. The interior-reveal "
				% group
				+ "system addresses the building by these names, and a missing one "
				+ "leaves a wall in front of the camera with nothing reporting it."
			)
