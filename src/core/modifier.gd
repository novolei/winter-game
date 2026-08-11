class_name Modifier
extends Resource

## One adjustment to one numeric value, from one identified source.
##
## A Modifier says only *how* a value changes -- add this, scale by that,
## replace it outright -- never which value it changes or why. That belongs
## to whoever owns the ModifierStack. Because the whole adjustment is data,
## a rule of the form "condition X changes quantity Y" can live in a .tres
## file rather than a branch in GDScript.

enum Operation { ADD, MULTIPLY, OVERRIDE }

## Who applied this. Used to remove it again precisely.
@export var source_id: StringName = &""

@export var operation: Operation = Operation.ADD

@export var value: float = 0.0

## Seconds until this expires. Any value <= 0 means permanent until removed
## by source; -1 is the conventional way to write it.
@export var duration: float = -1.0
