class_name UISoundCue
extends Resource

## One entry in UI design document section 8's pairing table -- a sound, and what
## the interface does to it before it is heard.
##
## Same shape as MusicCue, deliberately: the two maps are read the same way and a
## person who has understood one has understood both.
##
## THE POINT OF gain_db AND pitch_scale BEING HERE rather than at the call site
## is section 8's "菜单返回 -- 同上，降 3 个半音". Back and confirm are ONE file, and
## the pitch is the only thing that tells the player which of the two happened.
## Authored here, that is a row of data; authored at the call site it is a magic
## number in whatever code happens to cancel a menu, repeated at every other
## place that also cancels something.

@export var cue_id: StringName = &""

@export_file("*.wav", "*.ogg", "*.mp3") var stream_path: String = ""

## Negative pushes it under the world. Rule 6's sounds are heard INSIDE the wind,
## not over it.
@export var gain_db := 0.0

## A ratio, not semitones. n semitones is pow(2, n/12).
@export var pitch_scale := 1.0

## Per-play variation, as a ratio either side of pitch_scale. Zero for anything
## deliberate -- a confirm that wandered in pitch would read as a different sound
## each time -- and small for anything that repeats, which is how a menu move
## avoids sounding like a metronome.
@export var pitch_spread := 0.0

@export_multiline var notes := ""
