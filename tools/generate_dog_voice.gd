extends SceneTree

## Generator for res://data/audio/dog_voice.tres.
##
## Run: godot --headless --path <project> --script res://tools/generate_dog_voice.gd
##
## ---------------------------------------------------------------------------
## WHAT THE OWNER'S FILE ACTUALLY CONTAINED
## ---------------------------------------------------------------------------
## `assets/source/audio/wildlife/dog_raw.mp3`: 5.7379 s, 44100 Hz, true stereo,
## room tone throughout at -39.4 dBFS and no digital silence anywhere.
## `tools/cut_animal_calls.py` measured it and carries the full table; the eight
## slices it wrote are the eight files named below.
##
##   THREE BARKS    0.78, 1.62 and 2.36 s in. 91-93% of each one's energy sits
##                  in 800-2000 Hz over a sharp attack. The third is the loudest
##                  event in the take (peak 0.524) and the only one isolated on
##                  both sides.
##   THREE WHINES   sustained, periodicity 0.94-0.96, 723-848 Hz.
##   TWO WHIMPERS   quiet (peak 0.139 and 0.157), 649 and 668 Hz, slow rise and
##                  fall with no attack at all. The second falls in pitch across
##                  0.59 s, which is the injured-animal sound.
##
## ---------------------------------------------------------------------------
## THE GROWL, WHICH WAS NOT IN THE FIRST FILE AND IS THE WHOLE OF THE SECOND
## ---------------------------------------------------------------------------
## `dog_raw.mp3` had no growl in it, and this generator shipped `dog.growl`
## declared-and-silent for one commit on that measurement: across that whole take
## the 60-250 Hz band never rose more than 10.5 dB above its own noise floor,
## against 41.1 dB for the barks in 800-2000 Hz, and the low-frequency energy it
## did hold sat at 31-47 Hz at the SAME level in the silent tail -- mic and room
## rumble, not an animal. Nothing was substituted, because pitching a whine down
## an octave gives a moan and a wrong animal is worse than silence.
##
## `dog_growl_raw.mp3` closes it, and was put through the same instrument before
## a single sample was cut, because a file named growl is not evidence:
##
##                              dog_raw.mp3        dog_growl_raw.mp3
##   60-250 Hz over own floor    10.5 dB max        22.3 dB max, 11.0 mean
##   windows over 15 dB there    none               158 of 279
##   fundamental (autocorr)      500-900 Hz         41-251, mostly 145-200 Hz
##   60-250 share of energy      never over 0.13    0.15-0.88, typically 0.6-0.85
##   20-60 Hz share              the rumble         0.00-0.09, i.e. absent
##
## That last row is the one that matters most: the low energy here is NOT the
## 31-47 Hz rumble that fooled nobody last time. It is phonation at 145-200 Hz
## with the rumble band empty. This is a dog.
##
## The five files are cut at the animal's own breaths and each is verified
## individually -- 48-85% of every slice's energy is in 60-250 Hz, against 0.00
## to 0.01 for every bark, whine, whimper and caw in the project.
## `tests/unit/test_wildlife_calls.gd` re-checks it on every run by
## zero-crossing rate, so the growl slot cannot quietly come to hold a bark.
##
## What remains unpaired: **the animation has no whimper take**, and the audio
## now answers everything the animation can do.
##
## ---------------------------------------------------------------------------
## HOW FAR EACH ONE CARRIES, WHICH IS THE DESIGN AND NOT A DEFAULT
## ---------------------------------------------------------------------------
## Godot's inverse-distance attenuation is roughly `unit_size / distance`, so the
## gain at range is `gain_db + 20*log10(unit_size/distance)`. That arithmetic is
## the whole difference between these three calls:
##
##   growl     14 m, unit 3   -> -13 dB at the edge. INTIMATE ON PURPOSE. A
##             growl heard across the valley is not a warning about a place; the
##             player has to be near enough that "over there" means something.
##   bark      60 m, unit 8   -> -18 dB at the edge. A dog barking carries, and
##             in a valley it is the loudest thing an animal does.
##   whimper   45 m, unit 10  -> -17 dB at 45 m after its -4 dB trim. Generous
##             on purpose and the one number here that is a game decision rather
##             than an acoustic one: the rescue scene opens on an injured dog in
##             the snow and the animal is twenty pixels wide. The sound is how he
##             is found. It stays under the bark at every distance (-16 vs -14 dB
##             at 40 m), so it never reads as the louder animal.

const OUT_DIR := "res://data/audio"
const OUT_PATH := "res://data/audio/dog_voice.tres"
const CALL_DIR := "res://assets/audio/wildlife/dog"


func _initialize() -> void:
	var CallScript := load("res://src/definitions/animal_call.gd")
	var MapScript := load("res://src/definitions/animal_voice_map.gd")

	var bark = CallScript.new()
	bark.call_id = &"dog.bark"
	# Typed-array locals, annotated: `var x = [...]` is a Variant holding an
	# untyped Array, the typed setter rejects it, and the VM breaks out of this
	# function without a word (briefing trap 4). The generator would then save a
	# map of empty calls and print success.
	var bark_streams: Array[String] = [
		"%s/dog_bark_01.wav" % CALL_DIR,
		"%s/dog_bark_02.wav" % CALL_DIR,
		"%s/dog_bark_03.wav" % CALL_DIR,
	]
	bark.stream_paths = bark_streams
	var bark_takes: Array[StringName] = [&"bark"]
	bark.takes = bark_takes
	bark.gain_db = 0.0
	# Wider than the crow's, because a bark repeats within one burst and two
	# identical barks a third of a second apart is unmistakably one file.
	bark.pitch_spread = 0.07
	bark.carry_m = 60.0
	bark.unit_size = 8.0
	# A dog does not bark once. Two to four, a third of a second apart, is what
	# the take's own rhythm gives -- the source has three barks in 1.6 s.
	bark.repeat_min = 2
	bark.repeat_max = 4
	bark.gap_min = 0.28
	bark.gap_max = 0.55
	bark.cooldown_s = 1.2
	bark.notes = "Three cuts, 91-93% of their energy in 800-2000 Hz. Triggered by the `bark` take."

	var growl = CallScript.new()
	growl.call_id = &"dog.growl"
	# Five passages cut at the animal's own breaths. It shipped empty for one
	# commit and the header records why; `dog_growl_raw.mp3` closed it.
	var growl_streams: Array[String] = [
		"%s/dog_growl_01.wav" % CALL_DIR,
		"%s/dog_growl_02.wav" % CALL_DIR,
		"%s/dog_growl_03.wav" % CALL_DIR,
		"%s/dog_growl_04.wav" % CALL_DIR,
		"%s/dog_growl_05.wav" % CALL_DIR,
	]
	growl.stream_paths = growl_streams
	var growl_takes: Array[StringName] = [&"growl"]
	growl.takes = growl_takes
	growl.gain_db = -2.0
	# Small, and smaller than the bark's 0.07 deliberately: a growl's pitch IS
	# the animal's size, and one that wandered would read as a different dog
	# each cycle. +/-3% is about half a semitone.
	growl.pitch_spread = 0.03
	growl.carry_m = 14.0
	growl.unit_size = 3.0
	# One utterance per cycle, not a burst.
	growl.repeat_min = 1
	growl.repeat_max = 1
	# UNDER the take's 3.042 s loop, and that is the whole of it.
	#
	# This was 3.2 s while the call was silent, chosen as "just over the loop so
	# a held growl re-voices once per cycle". It does the opposite. `growl` is a
	# LOOPING take, so `AnimalVoice.notice_take()` sees the animation clock go
	# backwards every 3.042 s -- and 3.042 < 3.2, so every one of those restarts
	# was refused and only every SECOND one got through. A held growl would have
	# voiced every 6.084 s with clips averaging 2.64 s, leaving three and a half
	# seconds of silence in the middle of a dog that is visibly still growling.
	#
	# Nothing would have errored. The defect was invisible while there was no
	# file to play, and arrived the moment there was one.
	growl.cooldown_s = 2.8
	growl.notes = "Five passages, 1.93-3.67 s, cut at the dog's own breaths. 48-85% of each one's energy is in 60-250 Hz. Cooldown is under the take's 3.042 s loop so every cycle re-voices."

	var whine = CallScript.new()
	whine.call_id = &"dog.whine"
	var whine_streams: Array[String] = [
		"%s/dog_whine_01.wav" % CALL_DIR,
		"%s/dog_whine_02.wav" % CALL_DIR,
		"%s/dog_whine_03.wav" % CALL_DIR,
	]
	whine.stream_paths = whine_streams
	# No take. The three dogs have idle, walk, run, sit, stand, bark, lie and
	# growl and nothing that whines, so this one is asked for rather than
	# noticed -- which is honest: a whine with no matching animation would be a
	# sound coming out of a still dog.
	var whine_takes: Array[StringName] = []
	whine.takes = whine_takes
	whine.gain_db = -3.0
	whine.pitch_spread = 0.05
	whine.carry_m = 35.0
	whine.unit_size = 7.0
	whine.repeat_min = 1
	whine.repeat_max = 2
	whine.gap_min = 0.45
	whine.gap_max = 0.95
	whine.cooldown_s = 2.0
	whine.notes = "Sustained 723-848 Hz, periodicity 0.94-0.96. No animation take exists; call it."

	var whimper = CallScript.new()
	whimper.call_id = &"dog.whimper"
	var whimper_streams: Array[String] = [
		"%s/dog_whimper_01.wav" % CALL_DIR,
		"%s/dog_whimper_02.wav" % CALL_DIR,
	]
	whimper.stream_paths = whimper_streams
	var whimper_takes: Array[StringName] = []
	whimper.takes = whimper_takes
	whimper.gain_db = -4.0
	# Small. A whimper that wandered in pitch would read as a different animal
	# each time, and this is the one call the player has to recognise as a
	# specific dog in trouble rather than as wildlife.
	whimper.pitch_spread = 0.04
	whimper.carry_m = 45.0
	whimper.unit_size = 10.0
	# Repeated and slow. One whimper is a noise; three, spaced over four or five
	# seconds, is something asking for help -- and the repeat is what makes it
	# findable, since a player needs more than one sample to take a bearing.
	whimper.repeat_min = 2
	whimper.repeat_max = 3
	whimper.gap_min = 0.8
	whimper.gap_max = 1.8
	whimper.cooldown_s = 2.5
	whimper.notes = "Quiet (peak 0.139/0.157), 649 and 668 Hz, slow rise and fall. The rescue scene's beacon."

	var map = MapScript.new()
	var calls: Array[AnimalCall] = [bark, growl, whine, whimper]
	map.calls = calls

	var missing: Array[String] = []
	var voiced := 0
	for entry in map.calls:
		if entry.is_voiced():
			voiced += 1
		for path in entry.stream_paths:
			if not FileAccess.file_exists(path):
				missing.append(path)
	if not missing.is_empty():
		printerr("generate_dog_voice: stream(s) not on disk: %s" % ", ".join(missing))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(map, OUT_PATH)
	print("generate_dog_voice: save returned %d, %d calls (%d voiced, %d declared silent)" % [
		error, map.calls.size(), voiced, map.calls.size() - voiced])
	quit(0 if error == OK else 1)
