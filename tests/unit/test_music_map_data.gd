extends TestCase

## The shipped casting, res://data/audio/music_map.tres.
##
## The mechanism has its own tests. This file guards the thing the owner will
## actually change: which track plays where, how loud, and how much quiet sits
## between. Those are one-line data edits by design, which is exactly why the
## constraints they can violate need to be written down somewhere that fails.

const MAP_PATH := "res://data/audio/music_map.tres"
const AUDIO_ROOT := "res://assets/audio/vfxmusic"

## Every situation the director can resolve to. A situation missing from the
## data means silence at that moment, which is a legitimate design choice and
## an easy accident, so each one is accounted for explicitly below.
const AMBIENT_SITUATIONS: Array[StringName] = [
	&"dawn", &"day", &"dusk", &"night", &"shelter",
]
const ENDING_SITUATIONS: Array[StringName] = [
	&"ending_rescue", &"ending_death", &"ending_unseen",
]

func _map() -> MusicMap:
	return ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MusicMap

func test_the_shipped_map_loads() -> void:
	var map := _map()
	assert_not_null(map, "%s must exist and parse as a MusicMap" % MAP_PATH)
	if map == null:
		return
	assert_true(map.cues.size() > 0, "a map with no cues would be silence with extra steps")

func test_every_cast_track_is_actually_on_disk() -> void:
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for cue in map.cues:
		assert_true(cue.stream_path != "", "cue %s has no stream" % cue.cue_id)
		assert_true(ResourceLoader.exists(cue.stream_path),
			"cue %s points at %s, which is not there" % [cue.cue_id, cue.stream_path])

func test_every_track_in_the_folder_is_cast_exactly_once() -> void:
	## An uncast file is a track the owner paid for and will never hear; a file
	## cast twice under two ids is a track that can follow itself.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	var suffixes: Array[String] = [".mp3"]
	var on_disk := AssetScanner.find_files(AUDIO_ROOT, suffixes)
	assert_true(on_disk.size() > 0, "the audio folder should not be empty")
	var cast_paths: Array = []
	for cue in map.cues:
		assert_false(cast_paths.has(cue.stream_path),
			"%s is cast more than once, most recently as %s" % [cue.stream_path, cue.cue_id])
		cast_paths.append(cue.stream_path)
	for path in on_disk:
		assert_true(cast_paths.has(path), "%s is on disk but cast for nothing" % path)

func test_cue_ids_are_unique() -> void:
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	var seen: Array = []
	for cue in map.cues:
		assert_true(cue.cue_id != &"", "every cue needs an id")
		assert_false(seen.has(cue.cue_id), "duplicate cue id %s" % cue.cue_id)
		seen.append(cue.cue_id)

func test_every_ambient_situation_has_something_to_draw() -> void:
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for situation in AMBIENT_SITUATIONS:
		assert_true(map.cues_for(situation).size() > 0,
			"nothing is cast for %s, so it would play in silence" % situation)

func test_daylight_and_night_have_more_than_one_option() -> void:
	## The owner's brief asks for randomised play across times and scenes. A
	## situation with one cue can only ever produce that cue. Dawn and shelter
	## are single on purpose -- they are specific colours, and how often they
	## are heard at all is randomised by the gap -- but the two long stretches
	## of the day should vary.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for situation in [&"day", &"dusk", &"night"]:
		assert_true(map.cues_for(situation).size() >= 2,
			"%s has only %d cue(s); it would be the same track every time"
			% [situation, map.cues_for(situation).size()])

func test_danger_is_declared_silent_and_has_no_track() -> void:
	## The single most important line in this file. GDD section 9 builds its
	## fear out of the music going away, so danger must be silent by
	## declaration -- not silent by having been forgotten, which a later edit
	## could reverse without anyone noticing.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	assert_true(map.is_silent_situation(&"danger"), "danger must be declared silent")
	assert_eq(map.cues_for(&"danger").size(), 0, "and nothing may be cast for it")

func test_each_ending_has_exactly_one_cue_and_plays_once() -> void:
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for situation in ENDING_SITUATIONS:
		assert_eq(map.cues_for(situation).size(), 1, "%s should have one cue" % situation)
		assert_true(map.is_oneshot_situation(situation),
			"%s must be declared oneshot or it would loop behind the ending" % situation)

func test_no_track_is_boosted() -> void:
	## The nine tracks arrived 15.1 dB apart. gain_db exists to pull the loud
	## ones down to the quiet ones; a positive value here would mean a casting
	## change had turned into a volume change.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for cue in map.cues:
		assert_true(cue.gain_db <= 0.0,
			"cue %s is boosted by %f dB; trims only ever cut" % [cue.cue_id, cue.gain_db])
		assert_true(cue.gain_db > -30.0,
			"cue %s is trimmed by %f dB, which is inaudible rather than quiet"
			% [cue.cue_id, cue.gain_db])

func test_the_design_constraints_survive_tuning() -> void:
	## These four numbers are the owner's brief in data form. Someone tuning by
	## ear can move any of them; these bounds say how far before it stops being
	## the thing that was asked for.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	assert_true(map.base_volume_db <= -6.0,
		"music is meant to sit under the game, not on it; base is %f dB" % map.base_volume_db)
	assert_true(map.crossfade_seconds >= 3.0,
		"crossfades are several seconds, never a cut; got %f" % map.crossfade_seconds)
	assert_true(map.silence_fade_seconds >= 1.0 and map.silence_fade_seconds <= map.crossfade_seconds,
		"the drop to silence should be quicker than a crossfade but still a fade; got %f"
		% map.silence_fade_seconds)
	assert_true(map.min_gap_seconds >= 60.0,
		"long silences between cues are the design; min gap is %f s" % map.min_gap_seconds)
	assert_true(map.max_gap_seconds > map.min_gap_seconds,
		"the gap must be a range, or every cue lands on a metronome")

func test_no_track_is_imported_as_a_loop() -> void:
	## A looping stream never reaches its end, the director never hears it
	## finish, and the gap that is supposed to follow never starts -- which
	## turns the whole design into wall-to-wall music without failing anything
	## else. Read from the .import files as text so this costs no decoding.
	var suffixes: Array[String] = [".mp3"]
	var on_disk := AssetScanner.find_files(AUDIO_ROOT, suffixes)
	assert_true(on_disk.size() > 0, "the audio folder should not be empty")
	for path in on_disk:
		var import_path: String = path + ".import"
		var text := FileAccess.get_file_as_string(import_path)
		assert_true(text != "", "%s has no import settings" % path)
		assert_true(text.contains("loop=false"),
			"%s is imported as a loop; it would never end and the gaps would never run" % path)

func test_every_cue_records_why_it_was_cast_there() -> void:
	## The mapping is the part of this system most likely to be revisited, and
	## the reasoning is worth more to whoever revisits it than the code is.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for cue in map.cues:
		assert_true(cue.notes.length() > 40, "cue %s ships without a reading" % cue.cue_id)
