extends SceneTree

## One-off generator for res://data/audio/music_map.tres.
## Run: godot --headless --path <project> --script res://tools/generate_music_map.gd
##
## Casting comes from measuring the nine finished tracks -- every file decoded
## to PCM, then RMS level, octave-band balance, transient density, tempo,
## tonality and the shape of the loudness arc compared across the set. The
## numbers quoted in each cue's `notes` are those measurements; they are what
## the casting argument rests on, so they travel with the data.
##
## gain_db normalises every bed DOWN to the quietest track in the set
## (winnter1.mp3, -26.1 dBFS RMS) and every ending down to -20.0 dBFS RMS.
## Nothing is ever boosted. The endings sit 6 dB above the beds because an
## ending is the one moment the music is allowed to speak.

const DIR := "res://data/audio"
const PATH := "res://data/audio/music_map.tres"
const AUDIO := "res://assets/audio/vfxmusic/"

const BED_TARGET_DB := -26.0
const ENDING_TARGET_DB := -20.0

func _initialize() -> void:
	var CueScript := load("res://src/definitions/music_cue.gd")
	var MapScript := load("res://src/definitions/music_map.gd")

	# id, file, measured RMS dBFS, target, weight, situations, notes
	var rows := [
		[&"first_light", "morning.mp3", -15.9, BED_TARGET_DB, 1.0, [&"dawn"],
			"morning.mp3 -- 2:27, F# major, 69 BPM with the clearest pulse of any bed"
			+ " (tempo confidence 0.47) and the most harmonic movement (1.00). Warm and"
			+ " bright: content out to 10.5 kHz where the other beds die by 4-5 kHz."
			+ " Ramps in over 2.4 s and ends on a sustain rather than a fade. Name and"
			+ " material agree, so it is cast where its name says: first light."],

		[&"open_ground", "queite.mp3", -20.3, BED_TARGET_DB, 1.0, [&"day"],
			"queite.mp3 (\"quiet\") -- 2:59, F# major but the weakest key reading in the"
			+ " set (0.67), which is why it sits ambiguous. The distinguishing feature is"
			+ " spectral, not dynamic: it is bass-light (20-63 Hz sits 18 dB below its own"
			+ " peak band) and centred at 500-1000 Hz. That leaves the low end free for"
			+ " wind and the high end free for footsteps, and thin mid-range reads as"
			+ " exposure. Cast for ordinary daylight -- GDD section 9's solitude colour."],

		[&"long_walk", "bgm.mp3", -22.8, BED_TARGET_DB, 1.0, [&"day", &"dusk"],
			"bgm.mp3 -- 4:00, the longest bed, C major, very dark (nothing above 3.8 kHz"
			+ " despite a 320 kbps encode, so that is the material and not the encoder)."
			+ " Its ten-segment loudness arc is flat to within 1 dB for eight segments"
			+ " before a 6.7 s fade-out. No shape, no events, long: the definition of a"
			+ " bed. Doubles for dusk so that neither daylight nor nightfall is a single"
			+ " predictable track."],

		[&"hearth", "bgm2.mp3", -22.4, BED_TARGET_DB, 1.0, [&"shelter"],
			"bgm2.mp3 -- 2:50, C major, and the most featureless thing in the set: 6.3 dB"
			+ " of dynamic range (the narrowest), zero frames classified as transients,"
			+ " harmonic movement 0.47 (the most static -- close to a drone), bass-weighted"
			+ " at 63 Hz. A track with no events in it cannot pull focus, and low, static"
			+ " and warm is what a fire sounds like. Cast for GDD section 9's warmth"
			+ " layer: indoors, or at a lit beacon."],

		[&"failing_light", "winter2.mp3", -22.4, BED_TARGET_DB, 1.2, [&"dusk", &"night"],
			"winter2.mp3 -- 2:04, C major, 60 BPM. Flattest arc of any track with real"
			+ " content (-23.6 to -21.1 dB across eight of ten segments), 2.2% transient"
			+ " frames, and head/tail spectral similarity 0.98 -- the highest in the set,"
			+ " meaning it can repeat without an audible seam. Bass-weighted but with air"
			+ " out to 11 kHz. Present without being eventful: nightfall, and ordinary"
			+ " night."],

		[&"deep_cold", "winnter1.mp3", -26.1, BED_TARGET_DB, 1.5, [&"night"],
			"winnter1.mp3 (\"winter1\") -- 2:04, C major, and the most valuable track here"
			+ " for this particular game, which the filename gives no hint of. Quietest in"
			+ " the set by 3.3 dB (-26.1 dBFS RMS), slowest (~50 BPM), widest dynamic range"
			+ " (28.9 dB). Its second half decays monotonically -- -23.6, -24.4, -28.6,"
			+ " -30.8, -29.0, -37.5 dB -- while its spectral centroid RISES from 353 to 863"
			+ " Hz: the low end leaves first and only thin high material is left, then a"
			+ " 10.5 s fade to -79 dB, which is digital silence. Head/tail similarity 0.73,"
			+ " the lowest here: it does not loop, it ends. A track that dies away to"
			+ " nothing is GDD section 9's \"fear by absence\" already written into the"
			+ " material. Deep night, weighted to be drawn more often than its alternative."],

		[&"rescue", "victory.mp3", -11.0, ENDING_TARGET_DB, 1.0, [&"ending_rescue"],
			"victory.mp3 -- 2:04, F major with the highest key confidence in the set"
			+ " (0.92), the loudest track by 3.7 dB, brightest encode (12 kHz), and dual"
			+ " mono (both channels bit-identical, which is worth knowing before anyone"
			+ " tries to widen it). Builds across its arc from -15.8 to -9.0 dB with a flux"
			+ " peak two thirds through -- an arranged climax and resolution. GDD section"
			+ " 10's helicopter."],

		[&"death", "sad1.mp3", -14.7, ENDING_TARGET_DB, 1.0, [&"ending_death"],
			"sad1.mp3 -- 2:00, F major, 128 kbps (the only low-bitrate file). 77% of its"
			+ " energy sits below 250 Hz, peaking at 63-125 Hz, with 1.1% transient frames:"
			+ " heavy, low and entirely sustained. Its last two segments lighten and rise"
			+ " in centroid (203 to 455 Hz) as the low weight lifts away, which is a real"
			+ " ending gesture rather than a stop. Death."],

		[&"unseen", "mm.mp3", -17.4, ENDING_TARGET_DB, 1.0, [&"ending_unseen"],
			"mm.mp3 -- 3:58, and the ONLY minor-key track in the set (A minor, dominant"
			+ " pitch class A, confidence 0.72). 24.1 dB of dynamic range: it opens at -42"
			+ " dB, builds to -14.2, then fades out over 7.3 s. Long, minor, arc-shaped,"
			+ " resolving to nothing. Cast for GDD section 10's third ending -- the"
			+ " helicopter that does not see you -- because that ending is the artistic"
			+ " landing point and this is the only piece with the length and the mode for"
			+ " it. THIS IS THE LEAST CERTAIN CALL IN THIS FILE: \"mm\" most likely means"
			+ " main menu, and a menu theme is exactly this shape. If it is wanted there,"
			+ " move it and give ending_unseen to deep_cold, which also ends in silence."],
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

	var cues: Array[MusicCue] = []
	var failed := false
	for row in rows:
		var path: String = AUDIO + row[1]
		if not ResourceLoader.exists(path):
			print("generate_music_map: MISSING %s" % path)
			failed = true
			continue
		# Annotated, not `var cue =`: an untyped local makes the compiler emit an
		# untyped Array for the typed `situations` property below, which the
		# setter rejects at runtime and which ABORTS this function rather than
		# logging (briefing trap 4).
		var cue: MusicCue = CueScript.new()
		cue.cue_id = row[0]
		cue.stream_path = path
		var situations: Array[StringName] = []
		for s in row[5]:
			situations.append(s)
		cue.situations = situations
		# Never a boost: trim = target - measured, clamped at 0.
		cue.gain_db = minf(0.0, float(row[3]) - float(row[2]))
		cue.weight = row[4]
		cue.notes = row[6]
		cue.resource_name = String(row[0])
		cues.append(cue)

	var map: MusicMap = MapScript.new()
	map.cues = cues
	var silent: Array[StringName] = [&"danger"]
	map.silent_situations = silent
	var oneshot: Array[StringName] = [&"ending_rescue", &"ending_death", &"ending_unseen"]
	map.oneshot_situations = oneshot
	map.base_volume_db = -8.0
	map.crossfade_seconds = 6.0
	map.silence_fade_seconds = 3.0
	map.min_gap_seconds = 150.0
	map.max_gap_seconds = 420.0
	map.entry_gap_min_seconds = 5.0
	map.entry_gap_max_seconds = 40.0
	map.entry_chance = 0.5
	map.post_silence_hold_seconds = 45.0
	map.dawn_seconds = 90.0
	map.dusk_seconds = 75.0
	map.bus = &"Master"

	var error := ResourceSaver.save(map, PATH)
	if error != OK:
		print("generate_music_map: FAILED %s (%d)" % [PATH, error])
		failed = true
	else:
		print("generate_music_map: wrote %s with %d cues" % [PATH, cues.size()])

	# quit() only requests exit at the end of the current iteration and does not
	# return from this function, so accumulate and quit exactly once, last --
	# the same shape as tools/generate_schedules.gd.
	quit(1 if failed else 0)
