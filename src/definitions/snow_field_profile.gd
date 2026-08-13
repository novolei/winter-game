class_name SnowFieldProfile
extends Resource

## Authored facts for the valley's mature opening snow.  The run seed changes
## only the low-frequency variation inside the open field; the protected routes
## below remain the known, reliable first-day network.

@export var mature_variation_m := 0.08
@export var variation_frequency_per_m := 0.025
@export var variation_octaves := 2
@export var variation_gain := 0.45
@export var protected_routes: Array[SnowRouteConstraint] = []
## Sparse, authored wind breaks.  They represent large fixed world forms (a
## building mass, tree stand or rock rise) rather than querying live scene
## meshes per simulation tile.
@export var shelters: Array[SnowShelterDefinition] = []
