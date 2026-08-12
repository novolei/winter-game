class_name AnimalCall
extends Resource

## One thing an animal can say, and everything about how it says it.
##
## Same shape as `UISoundCue` and `MusicCue` deliberately -- three sound maps
## read the same way, and a person who has understood one has understood all of
## them.
##
## ---------------------------------------------------------------------------
## WHY *THIS* IS A RESOURCE WHEN THE CROW'S CALLS ARE A FOLDER
## ---------------------------------------------------------------------------
## `CrowCalls` scans `assets/audio/wildlife/crow/` and plays whatever it finds,
## which satisfies constraint 4 for one animal saying one thing: every caw is
## interchangeable with every other, so a folder listing IS the data.
##
## A dog is not that. A bark and a whimper differ in more than which file plays:
## they carry different distances, repeat different numbers of times, and mean
## opposite things. **How far a call carries is the whole of what a growl is
## for** -- a growl audible across the valley is not a warning about a place,
## and a whimper that dies at ten metres cannot be how a player finds an injured
## animal in the snow. None of that fits in a filename.
##
## So the folder stays the data for "which take of this call", and this resource
## is the data for everything else. Adding `dog.howl`, or giving the fox a voice,
## is a row in a generator under `tools/` and no `.gd` change anywhere.

## `dog.bark`, `dog.growl`. Namespaced by animal so one map per species can
## still be told apart in a log.
@export var call_id: StringName = &""

## The takes of this call. One is drawn per utterance, so two barks in a row are
## rarely the same file; an empty list is a call that is DECLARED and SILENT,
## which is a legal state and the one `dog.growl` ships in.
@export var stream_paths: Array[String] = []

## Which animation take states make the animal say this without being asked.
##
## Matched against `AnimationPlayer.current_animation` with the library prefix
## stripped, so the key is the take's own name -- `&"bark"`, `&"growl"`. Empty
## means nothing triggers it automatically and a behaviour must call `say()`,
## which is where `whine` and `whimper` sit: the dogs have no take for either.
@export var takes: Array[StringName] = []

@export var gain_db := 0.0

@export var pitch_scale := 1.0

## Per-utterance variation as a ratio either side of `pitch_scale`. Never zero
## for an animal: a dog that barks four times at an identical pitch is a sample
## being retriggered, and the ear catches it immediately.
@export var pitch_spread := 0.05

## HOW FAR IT CARRIES. `max_distance` on the emitter -- beyond this the call is
## not mixed at all.
@export var carry_m := 40.0

## The attenuation reference. Larger carries further at the same gain; this is
## the knob that separates "quiet but findable across a field" from "quiet".
@export var unit_size := 8.0

## HOW OFTEN. A burst is `repeat_min..repeat_max` utterances spaced
## `gap_min..gap_max` apart; `cooldown_s` is the floor between bursts, so a state
## that re-enters every frame cannot make the animal stutter.
@export var repeat_min := 1
@export var repeat_max := 1
@export var gap_min := 0.3
@export var gap_max := 0.6
@export var cooldown_s := 1.0

@export_multiline var notes := ""


## The utterances in one burst, given a drawn value in 0..1.
func repeats(draw: float) -> int:
	var low := maxi(repeat_min, 1)
	var high := maxi(repeat_max, low)
	return low + int(floor(clampf(draw, 0.0, 0.9999) * float(high - low + 1)))


## Whether this call has anything to play. A declared-but-silent call is not a
## defect; a call that thinks it has a file and does not is.
func is_voiced() -> bool:
	return not stream_paths.is_empty()
