class_name Montage
extends Resource

## An ordered run of shots. UI design document section 4.5.
##
## Adding one is a new .tres out of tools/generate_montages.gd and nothing else
## -- no .gd anywhere learns a new name (briefing constraint 4).

@export var id: StringName = &""
@export var shots: Array[MontageShot] = []

func shot_count() -> int:
	return shots.size()

func total_seconds() -> float:
	var total := 0.0
	for shot in shots:
		if shot != null:
			total += maxf(shot.duration, 0.0)
	return total

## Which shot is playing at `t`, and how far into it. [-1, 0.0] once the montage
## is over, so a caller can tell "finished" from "on the last frame of the last
## shot" -- those are different states and only one of them should cut away.
func locate(t: float) -> Array:
	if t < 0.0:
		return [0, 0.0]
	var remaining := t
	for index in range(shots.size()):
		var shot: MontageShot = shots[index]
		if shot == null:
			continue
		var length := maxf(shot.duration, 0.0)
		if remaining < length:
			return [index, remaining]
		remaining -= length
	return [-1, 0.0]
