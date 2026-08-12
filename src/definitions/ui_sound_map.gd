class_name UISoundMap
extends Resource

## Every sound the interface makes -- UI design document section 8.
##
## Adding one is a row in tools/generate_ui_sounds.gd and nothing else: no .gd
## anywhere learns a new name (briefing constraint 4).

@export var cues: Array[UISoundCue] = []

## Null for an id nobody declared. Callers check; UIAudio.play() returns false
## rather than pretending it played something.
func cue(cue_id: StringName) -> UISoundCue:
	for entry in cues:
		if entry != null and entry.cue_id == cue_id:
			return entry
	return null

func cue_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in cues:
		if entry != null and entry.cue_id != &"":
			ids.append(entry.cue_id)
	return ids
