class_name SnowResponseDefinition
extends Resource

## The ground-snow contribution of one authored weather response.
##
## Weather owns the current intensity; this resource owns what a full-intensity
## response means in metres per second.  Keeping those two facts separate lets
## a new weather event change ground accumulation by assigning a `.tres`, not by
## teaching SnowField another event name.

## Fresh snow added per real-time second at intensity 1.0.
@export_range(0.0, 0.001, 0.000001, "suffix:m/s") var deposition_m_per_second := 0.0

## A dynamic tile never grows without bound during one phase of the project.
## Wind transport and thaw own later additions/removals; this cap only protects
## the continuous-fall layer from an accidentally overlong storm definition.
@export_range(0.0, 1.0, 0.001, "suffix:m") var maximum_added_depth_m := 0.0

@export_group("Wind transport")
## Material moved per exposed source tile per real-time second at strength 1.
## It is deliberately a small finite transfer: a wind shifts snow downwind; it
## never subtracts a global depth value.
@export_range(0.0, 0.1, 0.000001, "suffix:m/s") var wind_transport_m_per_second := 0.0

## Below this normalised wind strength the surface is stable.  A calm front
## should not make the field slowly crawl merely because it reports a non-zero
## atmospheric value.
@export_range(0.0, 1.0, 0.01) var wind_minimum_strength := 0.0

## Distance a parcel moves on one fixed tick.  Tile-sized steps keep the
## result readable and make a direction reversal a local, testable operation.
@export_range(0.1, 20.0, 0.05, "suffix:m") var wind_sample_distance_m := 0.0

## A lee retains more of the finite incoming material than equally exposed
## open snow.  The actual shelter shape lives in SnowFieldProfile data.
@export_range(1.0, 4.0, 0.01) var wind_shelter_deposition_gain := 1.0
