class_name SnowFieldProfile
extends Resource

## Authored facts for the valley's mature opening snow.  The run seed changes
## only the low-frequency variation inside the open field; the protected routes
## below remain the known, reliable first-day network.

## Bump only when this authored profile's persistence interpretation changes.
## A newer profile must reject an older dynamic snapshot rather than replaying
## its sparse snow against subtly different route or shelter semantics.
@export var persistence_version := 1
@export var mature_variation_m := 0.08
@export var variation_frequency_per_m := 0.025
@export var variation_octaves := 2
@export var variation_gain := 0.45
## Mature open ground always retains this much compressible surface cover when
## it has not been packed or carved.  It is visible material for a boot to
## displace, not additional structural depth charged to traversal.
@export var minimum_imprintable_cover_m := 0.0
## Cover at which a boot has the full authored ability to hold its shape.
@export var full_imprint_depth_m := 0.0
## A boot can displace only this much of the column, however deep the drift.
@export var max_boot_depression_m := 0.0
## Leave a thin physical bed instead of cutting a footprint through to soil.
@export var residual_cover_m := 0.0
## Metres represented by a full-value TrackMask sample.  Keeping the conversion
## beside the cover budget lets the player and renderer share one data fact.
@export var footprint_response_depth_m := 0.0
@export var protected_routes: Array[SnowRouteConstraint] = []
## Sparse, authored wind breaks.  They represent large fixed world forms (a
## building mass, tree stand or rock rise) rather than querying live scene
## meshes per simulation tile.
@export var shelters: Array[SnowShelterDefinition] = []
