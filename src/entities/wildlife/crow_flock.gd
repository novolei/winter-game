class_name CrowFlock
extends BirdFlock

## The crows in the valley: `BirdFlock` driven by `data/wildlife/crow.tres`.
##
## Everything that was here -- the quiet timer, the arrival from off-frame, the
## fan, the stagger, the wind latch, the return after a startle, the perch
## gather, the published event -- is `src/entities/wildlife/bird_flock.gd`, and
## none of it was about crows. What was about crows is four numbers and a
## boolean, and they are in the resource:
##
##   fewest 1, most 5      one bird or several -- the owner's words
##   flush_radius_m 8.0    inside the tight framing stop's 10.5 m of world, so
##                         the flush happens on screen
##   daylight_only true    只有白天才会有乌鸦出现
##   avoids_occupied false the crows will still come down on a pigeon; see
##                         `BirdSpecies.avoids_occupied_perches`
##
## ---------------------------------------------------------------------------
## WHY THE CLASS SURVIVES THE REFACTOR
## ---------------------------------------------------------------------------
## `src/rendering/startle_shot.gd` -- a file this task may not touch -- declares
## `var _flock: CrowFlock` and locates it with `node is CrowFlock`. Deleting the
## name would have meant editing that file. So the name stays, and the two
## methods below are the whole of it.
##
## A third species does NOT need one of these: a `BirdFlock` node with `species`
## set in the scene hatches plain `Bird`s and behaves exactly as this does.
const SPECIES := preload("res://data/wildlife/crow.tres")


func _init() -> void:
	species = SPECIES


## A `Crow` rather than a plain `Bird`, and only so that `child is Crow` keeps
## answering for `test_crow_flock.gd`, `test_crow_gust.gd`, `tools/capture_crows.gd`
## and `crow_calls.gd`. `BirdFlock._build_bird()` hands it the species either way.
func _new_bird() -> Bird:
	return Crow.new()
