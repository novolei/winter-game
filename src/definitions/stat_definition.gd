class_name StatDefinition
extends Resource

## One survival track: core temperature, hunger, thirst, fatigue, frostbite.

@export var id: StringName = &""
@export var display_name: String = ""

@export var initial_value: float = 1.0
@export var min_value: float = 0.0
@export var max_value: float = 1.0

## Baseline drain per second before any modifier applies.
@export var base_decay_per_second: float = 0.0

## When true, reaching min_value ends the run.
@export var lethal_at_min: bool = false

## Interlocks with other stats.
@export var threshold_effects: Array[ThresholdEffect] = []
