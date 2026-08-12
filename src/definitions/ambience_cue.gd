class_name AmbienceCue
extends Resource

## A NAMED ONE-SHOT THE WORLD PLAYS -- above all, a weather's warning.
##
## Same shape as `UISoundCue` and `MusicCue` deliberately: three maps in this
## project are read the same way, and a person who has understood one has
## understood all three.
##
## ---------------------------------------------------------------------------
## THE ID IS ALREADY AUTHORED SOMEWHERE ELSE, AND THAT IS THE POINT
## ---------------------------------------------------------------------------
## `WeatherTell.sound` is a `StringName` and not a stream, on purpose -- its own
## header says so: "Wave 3's audio task owns playback, and this file must not
## grow an AudioStream field that would make the two tasks fight over the same
## asset. The name is published in the `weather.tell_started` payload for whoever
## subscribes."
##
## This is the other end of that seam. The six shipped events already name
## `weather_tell_blizzard`, `weather_tell_cold_snap`, `weather_tell_wind_shift`,
## `weather_tell_freezing_rain`, `weather_tell_snow_fog` and
## `weather_tell_clear_break`, and none of those names appears in any `.gd` file
## anywhere -- not in the weather system, not in the ambience director, not here.
## A seventh weather brings its own name and it works, which is binding rule 4
## stated as a property rather than as an aspiration.
##
## ---------------------------------------------------------------------------
## A ROW IS OPTIONAL
## ---------------------------------------------------------------------------
## `AmbienceMap.stream_for()` falls back to `<cue_folder>/<cue_id>.<ext>` when no
## row declares the id, so the FOLDER is the data and a cue with default gain
## needs no row at all -- the same shape `CrowCalls` uses for the caws, and the
## same reason: a list that has to be kept in step with a directory is a list
## that will one day disagree with it.
##
## Author a row when the sound needs something the file cannot carry: a level
## against the bed, a pitch, or a spread.

@export var cue_id: StringName = &""

@export_file("*.wav", "*.ogg", "*.mp3") var stream_path: String = ""

## Under the bed, not over it. A weather warning that shouts is a jump scare;
## GDD section 7 wants the player to READ the sky and decide, which needs a sound
## he has to attend to rather than one that arrives at him.
@export var gain_db := -8.0

@export var pitch_scale := 1.0

## Per-play variation either side of `pitch_scale`. Small for a weather tell: it
## fires once per event and a wandering pitch would only make two blizzards sound
## like different weathers.
@export var pitch_spread := 0.0

@export_multiline var notes := ""
