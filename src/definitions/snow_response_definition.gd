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
