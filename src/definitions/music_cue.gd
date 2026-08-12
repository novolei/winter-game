class_name MusicCue
extends Resource

## One finished track, plus the situations it has been cast for.
##
## Casting lives here rather than in code so that re-casting a track -- moving
## winter2.mp3 off `night` and onto `dusk`, say -- is an edit to
## data/audio/music_map.tres and nothing else (system map principle 1).
##
## `stream_path` is a path, not an AudioStream reference, so that loading the
## map does not pull all nine files (~50 MB) into memory at once and so that
## tests can validate the casting without an audio device. MusicDirector loads
## a stream the first time a cue actually plays.

@export var cue_id: StringName = &""

@export_file("*.mp3", "*.ogg", "*.wav") var stream_path: String = ""

## How long the track runs, in seconds, measured off the file by
## tools/generate_music_map.gd rather than typed in from the sleeve notes.
##
## It is stored here for the same reason `stream_path` is a path: opening nine
## files at boot to find out how long they are would undo the lazy loading this
## class exists to allow. That makes it a COPY of a fact that lives in the mp3,
## so test_music_map_data.gd compares the two rather than trusting this one.
##
## It is load-bearing, not documentation. MusicMap derives the silence between
## cues from the mean of these, so a track re-cut a minute shorter changes how
## often music is heard -- and a stale number here would leave the gap sized
## for a track that no longer exists.
@export var duration_seconds := 0.0

## Every situation this cue may be drawn for. A cue can serve several.
@export var situations: Array[StringName] = []

## Per-track trim, in dB, applied on top of MusicMap.base_volume_db.
##
## The nine tracks arrived 15.1 dB apart in RMS level, so without this a
## selection change would double as a volume change. Always <= 0: the trims
## normalise every track DOWN to the quietest one rather than boosting
## anything, because boosting is how a music system starts upstaging the
## footsteps it is supposed to sit under.
@export var gain_db := 0.0

## Relative likelihood of being drawn when several cues share a situation.
@export var weight := 1.0

## Why this track was cast here. Kept with the data on purpose -- whoever
## re-casts it should be able to see the reasoning in the inspector.
@export_multiline var notes := ""

func plays_in(situation: StringName) -> bool:
	return situations.has(situation)
