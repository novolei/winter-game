class_name ThreatDefinition
extends Resource

## A threat is a data file, not a class. The bear and the scavenger run the
## same code; they differ only in these values.

enum PerceptionKind { SIGHT, SCENT, TRACKS }

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Perception")
@export var perception_kinds: Array[PerceptionKind] = []
@export var sight_range := 30.0
@export var sight_angle_degrees := 90.0
## Scent only carries downwind -- wind direction is a gameplay variable.
@export var scent_range := 120.0
@export var track_follow_range := 40.0

@export_group("Locomotion")
@export var walk_speed := 2.0
@export var charge_speed := 8.0

@export_group("Engagement")
@export var warns_before_charging := false
@export var warning_duration := 2.0
@export var can_be_scared_off := false

@export_group("Schedule")
@export var first_active_day := 1
