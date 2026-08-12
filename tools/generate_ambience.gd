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
## so the FOLDER is the data: drop `wind_low.ogg` into
## `assets/audio/ambience/` and the low bed sounds, with no `.gd` change, no
## regeneration of this file and no list to keep in step.
##
## Nothing is stubbed with a stand-in. `tools/generate_ui_sounds.gd` gives the
## reason and it holds here: a wrong sound in the right place is harder to notice
## than silence.
##
## THE FILES THIS PROJECT IS OWED, by folder and by role:
##
##   assets/audio/ambience/wind_low.ogg    seamless loop. The body of the air --
##                                         low, broad, no whistle. The one voice
##                                         that stays when something is near.
##   assets/audio/ambience/wind_mid.ogg    seamless loop. The wind proper: the
##                                         gust arriving, with movement in it.
##   assets/audio/ambience/wind_high.ogg   seamless loop. The top -- hiss, edge,
##                                         whistle round a corner. Squall only.
##   assets/audio/ambience/snow_fall.ogg   seamless loop. Falling snow: a dry
##                                         patter, no wind in it, or it will be
##                                         heard twice.
##   assets/audio/ambience/fire.ogg        seamless loop. A stove, close and dry.
##                                         Positional, one per lit fire.
##   assets/audio/weather/weather_tell_*.ogg   six one-shots, one per event id
##                                         already authored in data/weather/.
##
## All five loops must be SEAMLESS and must carry no wind of their own beyond
## their own band, because they play together and any overlap is heard as a
## phasing artefact rather than as weather.

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
	low.gain_db = -14.0
	low.pitch_scale = 0.97
	low.pitch_at_full = 1.02
	# GDD section 9: 抽走高频层，只剩低频. This is the 低频, so it is the one that
	# stays. Everything else in this map leaves.
	low.withdraws_near_danger = false
	low.notes = "The body of the air. Silent below 0.09, which is 97.6% of a still night and 22.3% of a valley day."

	var mid = LayerScript.new()
	mid.layer_id = &"wind_mid"
	mid.source = AmbienceLayer.Source.WIND
	mid.enters_at = 0.26
	mid.full_at = 0.52
	mid.gain_db = -12.0
	mid.pitch_scale = 0.98
	mid.pitch_at_full = 1.05
	mid.withdraws_near_danger = true
	mid.notes = "The gust. Enters just under wind_valley's own gust_threshold of 0.30, so it arrives with the event."

	var high = LayerScript.new()
	high.layer_id = &"wind_high"
	high.source = AmbienceLayer.Source.WIND
	high.enters_at = 0.55
	high.full_at = 0.88
	high.gain_db = -15.0
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
	snow.gain_db = -17.0
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
