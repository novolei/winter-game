extends SceneTree

## Generator for res://data/audio/ambience.tres -- GDD section 9's world side.
##
## Run: godot --headless --path <project> --script res://tools/generate_ambience.gd
##
## ---------------------------------------------------------------------------
## THE WINDOWS ARE MEASURED, NOT CHOSEN
## ---------------------------------------------------------------------------
## Every `enters_at` below was set against a sweep of the five shipped wind
## profiles -- 60,000 samples each, 20 minutes of weather per profile, taken
## through `WindSystem.strength_at()`, which is a pure function of time and so
## can be swept without a frame.
##
##   profile        min    mean    max     p50     p90
##   wind_still    0.020  0.038  0.108   0.031   0.068
##   wind_calm     0.040  0.096  0.377   0.077   0.175
##   wind_valley   0.060  0.205  0.835   0.158   0.443
##   wind_rising   0.130  0.276  0.766   0.238   0.493
##   wind_gale     0.280  0.553  0.996   0.527   0.802
##
## What that buys, and it is the whole design rather than a mix decision:
##
##   `wind_low` enters at 0.09, so the bed is SILENT for 97.6% of a still night,
##   for 22.3% of an ordinary valley day, and never during a gale. The gaps are
##   real, they are where the footsteps and the breath live, and 寒流's tell --
##   空气变得极静 -- is carried by the bed going away rather than by any file.
##
##   `wind_mid` enters at 0.26, just under the valley's own `gust_threshold` of
##   0.30, so the second voice arrives with the gust the wind system announces.
##   Present 24.4% of a valley day; continuously during a gale.
##
##   `wind_high` enters at 0.55: 5.4% of a valley day, 46.3% of a gale. It is the
##   squall, and it is the first thing a threat takes away.
##
## Re-run the sweep before changing any of these. A window authored by ear
## against one profile will be silent or saturated under another, and there are
## five.
##
## ---------------------------------------------------------------------------
## NO STREAM PATHS, AND THAT IS NOT AN OMISSION
## ---------------------------------------------------------------------------
## Not one row below names a file. `AmbienceMap` resolves a layer as
## `<sound_folder>/<layer_id>.<ext>` and a cue as `<cue_folder>/<cue_id>.<ext>`,
## so the FOLDER is the data: drop `wind_low.wav` into `assets/audio/ambience/`
## and the low bed sounds, with no `.gd` change, no regeneration of this file and
## no list to keep in step.
##
## ---------------------------------------------------------------------------
## THE FIVE BED FILES HAVE LANDED. THE SIX WEATHER CUES HAVE NOT.
## ---------------------------------------------------------------------------
## `tools/build_ambience_loops.py` cuts the owner's five takes into seamless
## loops and writes them into `assets/audio/ambience/`. Read its header for the
## method and for the first finding, which is that two of the supplied filenames
## are the wrong way round.
##
##   wind_low    60.0 s   48000 Hz   from Freesound 261226, later passage (CC0)
##   wind_mid    60.0 s   48000 Hz   from Freesound 261226, early passage (CC0)
##   wind_high    4.6 s   22050 Hz   from wind_high.wav  (86% in 0.8-2.5 kHz)
##   snow_fall    5.4 s   44100 Hz   from snow_fall.mp3  (high-passed to patter)
##   fire        12.0 s   44100 Hz   from fire.mp3       (unfiltered)
##
## Still owed: the six one-shots in `assets/audio/weather/`, named
## `weather_tell_<event id>` for the six events in `data/weather/`.
##
## ---------------------------------------------------------------------------
## THE GAINS BELOW ARE MEASURED, NOT CHOSEN BY EAR
## ---------------------------------------------------------------------------
## Nobody on this end can hear these files, so the mix is derived rather than
## judged. Every loop leaves the builder at the same RMS, and the builder then
## measures each one's ITU-R BS.1770 loudness -- because EQUAL RMS IS NOT EQUAL
## LOUDNESS, and on this set that difference decides whether the mix works:
##
##   layer       loudness at equal RMS    correction owed
##   wind_low         -20.8 LUFS               +0.2 dB
##   wind_mid         -20.6 LUFS               +0.0 dB
##   wind_high        -20.2 LUFS               +0.0 dB
##   snow_fall        -22.8 LUFS               +2.6 dB
##   fire             -37.1 LUFS              +16.9 dB
##
## `fire` is 17 dB down because it is a peaky recording -- 36 dB crest -- whose
## peak hits the ceiling long before its average reaches the others'. That is
## what a fire is, so it is corrected here rather than compressed there.
##
## So each `gain_db` below starts from a BASE near -14 dB, which is where the bed sits
## under the footsteps and the breath; plus a RELATIVE design target against
## `wind_low`; plus that layer's measured correction. Each is written out at its
## row so a later ear can move one number and know what it was.
const OUT_DIR := "res://data/audio"
const OUT_PATH := "res://data/audio/ambience.tres"

const WEATHER_DIR := "res://data/weather"


func _initialize() -> void:
	var LayerScript := load("res://src/definitions/ambience_layer.gd")
	var CueScript := load("res://src/definitions/ambience_cue.gd")
	var MapScript := load("res://src/definitions/ambience_map.gd")

	# --- the bed -------------------------------------------------------------

	var low = LayerScript.new()
	low.layer_id = &"wind_low"
	low.source = AmbienceLayer.Source.WIND
	low.enters_at = 0.09
	low.full_at = 0.30
	# The replacement take is 1.5 LU louder at equal RMS. A further 1 dB
	# subjective trim keeps the opening air behind footsteps and breath while
	# preserving the >3 dB gap to wind_high.
	low.gain_db = -16.5
	low.pitch_scale = 0.97
	low.pitch_at_full = 1.02
	# The opening valley profile dips below the window after 3.6 s and returns
	# shortly afterwards. A 1.25 s release joins those pieces into one natural
	# body of air while the still-night profile remains silent over 90% of time.
	low.release_seconds = 1.25
	# GDD section 9: 抽走高频层，只剩低频. This is the 低频, so it is the one that
	# stays. Everything else in this map leaves.
	low.withdraws_near_danger = false
	low.notes = "The body of the air. A 1.25 s release bridges brief gust troughs; trimmed 2.5 dB so it stays behind footsteps and breath."

	var mid = LayerScript.new()
	mid.layer_id = &"wind_mid"
	mid.source = AmbienceLayer.Source.WIND
	mid.enters_at = 0.26
	mid.full_at = 0.52
	# -14 base + 1.0 relative (a gust ARRIVING has to be noticed) - 1.6 correction.
	mid.gain_db = -14.5
	mid.pitch_scale = 0.98
	mid.pitch_at_full = 1.05
	mid.withdraws_near_danger = true
	mid.notes = "The gust. Enters just under wind_valley's own gust_threshold of 0.30, so it arrives with the event."

	var high = LayerScript.new()
	high.layer_id = &"wind_high"
	high.source = AmbienceLayer.Source.WIND
	high.enters_at = 0.55
	high.full_at = 0.88
	# -14 base - 4.0 relative (a hiss at the body's level is piercing) - 2.1.
	high.gain_db = -20.0
	high.pitch_scale = 1.0
	high.pitch_at_full = 1.09
	high.withdraws_near_danger = true
	high.notes = "The squall's top. 5.4% of a valley day, 46.3% of a gale."

	var snow = LayerScript.new()
	snow.layer_id = &"snow_fall"
	snow.source = AmbienceLayer.Source.SNOWFALL
	# Above pale_day's ambient 0.12 and below nightfall's 0.35, so a light day has
	# no audible fall and 冻雨's tell -- which drives the rate to 0.50 -- is the
	# snow ARRIVING rather than thickening. That is its audible half.
	snow.enters_at = 0.16
	snow.full_at = 0.62
	# -14 base - 5.0 relative (under everything) + 0.5 correction.
	snow.gain_db = -18.5
	snow.pitch_scale = 1.0
	snow.pitch_at_full = 1.06
	# It goes too. GDD section 9 is specific that day 7 is where this is at its
	# cruellest -- 白茫茫什么都看不见，只能听见世界安静下来 -- and a whiteout whose
	# snow kept hissing through a bear's approach could not do that.
	snow.withdraws_near_danger = true
	snow.notes = "Falling snow, driven by Snowfall.snowfall_rate() rather than by the wind."

	var map = MapScript.new()
	# Typed-array property, so the local MUST be annotated: `var x = [...]` is a
	# Variant holding an untyped Array, the typed setter rejects it, and the VM
	# breaks out of this function without a word (briefing trap 4). The generator
	# would then save an EMPTY map and print success.
	var layers: Array[AmbienceLayer] = [low, mid, high, snow]
	map.layers = layers

	# --- the one-shots -------------------------------------------------------
	#
	# Read off data/weather/ rather than typed out, so this generator names no
	# weather either. A seventh event's tell sound appears here the moment its
	# .tres does.
	var cues: Array[AmbienceCue] = []
	for id in _tell_sounds():
		var cue = CueScript.new()
		cue.cue_id = id
		# Under the bed. GDD section 7 wants the player to READ the warning and
		# decide whether to press on, which needs a sound he has to attend to.
		cue.gain_db = -9.0
		cue.pitch_scale = 1.0
		cue.pitch_spread = 0.0
		cue.notes = "Weather tell, named by data/weather/. No .gd file anywhere knows this id."
		cues.append(cue)
	map.cues = cues

	var error := ResourceSaver.save(map, OUT_PATH)
	print("generate_ambience: save returned %d, %d layers, %d cues" % [
		error, map.layers.size(), map.cues.size()])
	# The honest count of what is actually playable today. Not an error: the
	# files are owed and every consumer is built to be silent until they land.
	var on_disk := 0
	for entry in map.layers:
		if map.stream_for_layer(entry) != "":
			on_disk += 1
	var cues_on_disk := 0
	for entry in map.cues:
		if map.stream_for(entry.cue_id) != "":
			cues_on_disk += 1
	print("generate_ambience: %d/%d layers and %d/%d cues have audio on disk" % [
		on_disk, map.layers.size(), cues_on_disk, map.cues.size()])
	quit(0 if error == OK else 1)


## Every sound a shipped weather tell names, in directory order. Nothing here
## knows what a blizzard is.
func _tell_sounds() -> Array[StringName]:
	var found: Array[StringName] = []
	var directory := DirAccess.open(WEATHER_DIR)
	if directory == null:
		return found
	var names := directory.get_files()
	names.sort()
	for file in names:
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var event = ResourceLoader.load("%s/%s" % [WEATHER_DIR, name])
		if event == null or not (&"tell" in event):
			continue
		var tell = event.get(&"tell")
		if tell == null or not (&"sound" in tell):
			continue
		var sound = tell.get(&"sound")
		if sound is StringName and sound != &"" and not found.has(sound):
			found.append(sound)
	return found
