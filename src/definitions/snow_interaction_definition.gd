class_name SnowInteractionDefinition
extends Resource

## One authored way a contact changes the shared snow surface.
##
## Producers publish a generic `snow.interaction` payload.  This resource owns
## the visual/physical response, so a new contact language that reuses an
## existing primitive is data, not another TrackMask branch.

@export var interaction_id: StringName = &""
@export var primitive: StringName = &"footprint"

@export_group("Response")
@export_range(0.0, 2.0, 0.01) var strength_scale := 1.0
@export_range(0.0, 1.0, 0.01) var max_strength := 0.8
@export_range(0.01, 2.0, 0.01) var depth_reference_m := 0.4
@export_range(1.0, 10000.0, 1.0) var pressure_reference_ns_m2 := 1400.0

@export_group("Shape")
@export_range(0.1, 2.0, 0.01) var length_scale := 1.0
@export_range(0.1, 2.0, 0.01) var width_scale := 1.0
@export_range(0.0, 0.95, 0.01) var core := 0.45
@export_range(0.0, 0.8, 0.01) var irregularity := 0.12
@export_range(0.0, 1.0, 0.01) var continuity_floor := 1.0
@export_range(0.0, 0.1, 0.001) var meander_m := 0.0
