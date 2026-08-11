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
## 2. WHAT IT IS LIT BY. Handed to CelPainter, which every solid in the world
##    now shares -- see src/rendering/cel_painter.gd for why a stock
##    StandardMaterial3D beside the cel-shaded snow reads as a render pasted
##    into a painting.
##
## THE REVEAL SYSTEM IS NOT BUILT HERE. Fading FH_Fade_Roof / FH_Fade_Front /
## FH_Fade_Porch when the player crosses the threshold is a later wave. What
## this does do is check the three names still resolve after placement, loudly,
## because the failure mode is a wall left standing in front of the camera with
## nothing anywhere reporting it.

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

## How far down the palette the shadow band sits, per family. See CelPainter,
## which holds the reasoning and applies the same two steps to every other
## solid in the world.
@export var snow_shade_step := 3
@export var structure_shade_step := 1


func _ready() -> void:
	var painter := CelPainter.new(snow_shade_step, structure_shade_step)
	painter.paint(self)
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


func _check_reveal_groups() -> void:
	for group in REVEAL_GROUPS:
		if find_child(group, true, false) == null:
			push_error(
				"farmhouse: %s is not under this node any more. The interior-reveal "
				% group
				+ "system addresses the building by these names, and a missing one "
				+ "leaves a wall in front of the camera with nothing reporting it."
			)
