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
	assert_true(map.gap_min_seconds() >= 60.0,
		"long silences between cues are the design; min gap is %f s" % map.gap_min_seconds())
	assert_true(map.gap_max_seconds() > map.gap_min_seconds(),
		"the gap must be a range, or every cue lands on a metronome")

func test_every_cue_carries_the_length_the_file_actually_is() -> void:
	## duration_seconds is a COPY of a fact that lives in the mp3, kept in the
	## map so that booting the game does not have to open nine files to find
	## out how long they are. A copy can go stale, and this one is load-bearing:
	## the silence between cues is derived from it, so a wrong number here moves
	## the density of the whole score without failing anything else.
	##
	## This is the only place the copy and the original are ever compared.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	for cue in map.cues:
		var stream := ResourceLoader.load(cue.stream_path) as AudioStream
		assert_not_null(stream, "cue %s did not load as an AudioStream" % cue.cue_id)
		if stream == null:
			continue
		assert_true(cue.duration_seconds > 0.0,
			"cue %s ships with no measured length, and the gap is derived from it"
			% cue.cue_id)
		assert_almost_eq(cue.duration_seconds, stream.get_length(), 0.05,
			"cue %s says %f s; the file is %f s. Re-run tools/generate_music_map.gd."
			% [cue.cue_id, cue.duration_seconds, stream.get_length()])

func test_a_situation_beginning_always_brings_music_with_it() -> void:
	## entry_chance below 1.0 was the second of two stacked randomisers -- a
	## long gap AND a coin flip -- and the two together meant a nightfall could
	## pass in silence for no reason at all. That is the one thing this system
	## cannot afford: it is built so that music LEAVING says a threat is near
	## (GDD section 9), and absence cannot carry a signal if it also happens by
	## accident.
	##
	## Sparseness is the gap's job, and the gap alone. Pinned rather than
	## bounded: anything below 1.0 here is the defect coming back.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	assert_almost_eq(map.entry_chance, 1.0, 0.0001,
		("entry_chance is %f; below 1.0 music fails to arrive for no reason,"
		+ " and absence that happens for no reason cannot carry a signal")
		% map.entry_chance)

func test_the_gap_is_derived_from_the_tracks_and_not_chosen() -> void:
	## The gap is not a constant. It is what a density and the measured track
	## lengths imply, and it has to be read that way or it drifts the moment a
	## track is re-cut: a track that becomes a minute shorter needs a shorter
	## gap to keep the same density, and nobody would think to come here.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	var mean := map.mean_cue_duration_seconds()
	assert_true(mean > 0.0, "the derivation needs at least one measured track length")
	var share := map.gap_cycle_music_share
	# Bounded, not pinned. This is a cycle share, and what a whole RUN measures
	# is well above it -- 0.45 here measured 59.3% of a run with music across
	# 200 simulated runs. The band is where that run-level figure stays inside
	# the "roughly half" the owner asked for; tools/measure_music_density.gd is
	# what settles it, and moving this without re-running that tool is guessing.
	assert_true(share >= 0.30 and share <= 0.55,
		"a cycle share of %f puts the run-level share outside roughly half;"
		% share
		+ " re-run tools/measure_music_density.gd before moving it")
	var expected := mean * (1.0 - share) / share
	assert_almost_eq((map.gap_min_seconds() + map.gap_max_seconds()) * 0.5, expected, 0.01,
		"the mean gap should be exactly what %f s of track at a %f share implies"
		% [mean, share])

func test_no_ordinary_gap_can_outlast_the_quiet_that_follows_a_threat() -> void:
	## THE acceptance test for making music more frequent. GDD section 9 builds
	## its fear out of the music going away, which only works if a long silence
	## cannot happen by chance.
	##
	## A threat's silence is a full gap PLUS post_silence_hold_seconds, so the
	## random spread of an ordinary gap must not be wider than that hold -- or
	## the noise in an ordinary gap swallows the signal that says "something is
	## out there". This is a relationship between two numbers, not a bound on
	## one, so it is asserted against the hold rather than against a constant.
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	var spread := map.gap_max_seconds() - map.gap_min_seconds()
	assert_true(spread <= map.post_silence_hold_seconds,
		"an ordinary gap varies by %f s but the quiet after a threat only adds %f s;"
		% [spread, map.post_silence_hold_seconds]
		+ " a silence long enough to mean danger would be reachable by luck")

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
