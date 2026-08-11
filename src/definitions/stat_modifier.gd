class_name StatModifier
extends Resource

## One authored adjustment to one named stat: "this event drains warmth 1.5x
## faster", "this item adds 0.4 hydration".
##
## Modifier, in src/core/, deliberately does not know which stat it hits: it
## is game-agnostic, and a ModifierStack is built per value, so the stack
## legitimately cannot name the stat it serves. That leaves nowhere for a
## designer to say WHICH stat a modifier in a .tres targets. This is that
## missing half -- the definitions-layer pairing of a target with an
## adjustment -- and it is why WeatherEventDefinition and ItemDefinition hold
## Array[StatModifier] rather than Array[Modifier].
##
## The modifier's fields are carried flat rather than as a nested Modifier
## sub-resource, matching ThresholdEffect, which already solves the same
## problem the same way. Flat means the whole rule is one panel in the
## inspector with nothing to instantiate; a nested Modifier would default to
## null in every file a designer creates and have to be added by hand before
## anything could be typed into it -- the authoring failure this exists to
## fix. to_modifier() is the single place the two shapes are mapped.

## The stat this adjusts. Matches a StatDefinition.id.
@export var target_stat: StringName = &""

## Who to credit, so ModifierStack.remove_by_source() can take it off again.
@export var source_id: StringName = &""

@export var operation: Modifier.Operation = Modifier.Operation.ADD

@export var value: float = 0.0

## Seconds until this expires. Any value <= 0 means permanent until removed
## by source; -1 is the conventional way to write it.
@export var duration: float = -1.0

## Builds the runtime Modifier this describes. Returns a FRESH instance every
## call, deliberately: .tres resources are cached and shared (briefing trap
## 6), so handing the same object to two ModifierStacks would be fine for the
## value but wrong for expiry bookkeeping upstream. A new instance per
## application keeps each slot independent.
func to_modifier() -> Modifier:
	var mod := Modifier.new()
	mod.source_id = source_id
	mod.operation = operation
	mod.value = value
	mod.duration = duration
	return mod
