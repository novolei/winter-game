class_name AnimalVoiceMap
extends Resource

## Everything one animal can say. One map per species; `data/audio/dog_voice.tres`
## is the first.
##
## Adding a call is a row in a generator under `tools/` and nothing else -- no
## `.gd` anywhere learns a new name (briefing constraint 4). Giving a second
## animal a voice is a second `.tres` and an `AnimalVoice` node pointed at it;
## there is no per-species script.

@export var calls: Array[AnimalCall] = []


## Null for an id nobody declared. Callers check; `AnimalVoice.say()` returns
## false rather than pretending it played something.
func call_named(call_id: StringName) -> AnimalCall:
	for entry in calls:
		if entry != null and entry.call_id == call_id:
			return entry
	return null


## The call an animation take triggers, or null.
##
## First match wins and that is deliberate: two calls claiming the same take is
## an authoring mistake, and `tests/unit/test_animal_voice.gd` fails on it rather
## than letting the order of the array decide what a dog says.
func call_for_take(take: StringName) -> AnimalCall:
	if take == &"":
		return null
	for entry in calls:
		if entry != null and entry.takes.has(take):
			return entry
	return null


func call_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in calls:
		if entry != null and entry.call_id != &"":
			ids.append(entry.call_id)
	return ids


## How many calls have a file behind them. The honest number, for a gate and for
## a report -- `calls.size()` counts the vocabulary, this counts the voice.
func voiced_count() -> int:
	var found := 0
	for entry in calls:
		if entry != null and entry.is_voiced():
			found += 1
	return found
