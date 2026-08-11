class_name ThresholdEffect
extends Resource

## "When hunger drops below 0.3, multiply core temperature decay by 1.5."
##
## Encoding the survival model's interlocks as data is what lets a designer
## add a sixth stat, or a new interlock between two existing ones, without
## touching GDScript.

enum Comparison { BELOW, ABOVE }

## The stat being watched.
@export var watch_stat: StringName = &""

@export var comparison: Comparison = Comparison.BELOW

@export var threshold: float = 0.0

## The stat that gets modified when the condition holds.
@export var target_stat: StringName = &""

@export var operation: Modifier.Operation = Modifier.Operation.MULTIPLY

@export var value: float = 1.0
