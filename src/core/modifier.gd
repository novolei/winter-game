class_name Modifier
extends Resource

## One adjustment to one numeric value, from one identified source.
##
## This is the unit that makes the survival model data-driven: "low hunger
## makes body heat drain faster" is a Modifier stored in a .tres file, not
## a branch in GDScript.

enum Operation { ADD, MULTIPLY, OVERRIDE }

## Who applied this. Used to remove it again precisely.
@export var source_id: StringName = &""

@export var operation: Operation = Operation.ADD

@export var value: float = 0.0

## Seconds until this expires. Any value <= 0 means permanent until removed
## by source; -1 is the conventional way to write it.
@export var duration: float = -1.0
