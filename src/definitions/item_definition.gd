class_name ItemDefinition
extends Resource

## Anything the player can carry. Fuel is the real currency: water needs
## melting, melting needs fire, fire needs fuel -- and so do the beacons.

enum Category { FUEL, FOOD, WATER, MEDICINE, TOOL }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.FUEL

@export var mass_kg := 1.0

## Seconds of burn time this yields. Zero for non-fuel items.
@export var fuel_value := 0.0

@export var nutrition := 0.0
@export var hydration := 0.0

## Applied to the player's stats when used. StatModifier, not Modifier: a
## bare Modifier carries no target, so a file with three of them could not
## say which stat each one hits.
@export var use_modifiers: Array[StatModifier] = []
