class_name ColorBible
extends Resource

## The twelve colors every model builds from. Nothing in the project may
## hardcode a color; everything reads this resource.

@export var snow_tones: Array[Color] = []
@export var structure_tones: Array[Color] = []
@export var warm_tones: Array[Color] = []

func all_colors() -> Array[Color]:
	var combined: Array[Color] = []
	combined.append_array(snow_tones)
	combined.append_array(structure_tones)
	combined.append_array(warm_tones)
	return combined

func _matches(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance \
		and absf(a.g - b.g) <= tolerance \
		and absf(a.b - b.b) <= tolerance

## Tolerance defaults to ~1/255, absorbing 8-bit rounding without letting
## a genuinely different color slip through.
func contains(c: Color, tolerance := 0.004) -> bool:
	for known in all_colors():
		if _matches(known, c, tolerance):
			return true
	return false

func is_warm(c: Color, tolerance := 0.004) -> bool:
	for known in warm_tones:
		if _matches(known, c, tolerance):
			return true
	return false
