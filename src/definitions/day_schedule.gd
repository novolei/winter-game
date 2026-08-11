class_name DaySchedule
extends Resource

## The authored half of the weather model: each day's budget and its
## mandatory beats. Randomness lives inside these bounds so the dramatic
## arc survives it.

@export var day_number := 1

@export var daylight_seconds := 600.0
@export var night_seconds := 300.0

@export var primary_lighting_preset: StringName = &""

## Events that may be drawn at random today.
@export var allowed_weather_events: Array[StringName] = []

## An event that must happen today regardless of the draw. Day 7 forces
## the blizzard.
@export var forced_weather_event: StringName = &""

## The beacon that becomes lightable today, if any.
@export var beacon_unlocked: StringName = &""
