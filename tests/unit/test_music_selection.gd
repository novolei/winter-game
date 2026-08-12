extends TestCase

## Which track gets drawn, and how much silence comes before it.
##
## Everything here is built from throwaway resources rather than the shipped
## map, so a re-casting decision in data/audio/music_map.tres cannot break
## these -- the shipped mapping has its own gate in test_music_map_data.gd.
##
## MusicSelector, MusicMap and MusicCue all extend RefCounted or Resource, so
## nothing here needs freeing.

const SelectorScript := preload("res://src/audio/music_selection.gd")
const MapScript := preload("res://src/definitions/music_map.gd")
const CueScript := preload("res://src/definitions/music_cue.gd")

const SEED := 20260812

const TRACK_SECONDS := 200.0

func _cue(id: StringName, situations: Array, weight := 1.0) -> MusicCue:
	# Annotated, not `var cue =`: an untyped local emits an untyped Array for
	# the typed `situations` property, which the setter rejects at runtime and
	# which aborts the calling function outright (briefing trap 4).
	var cue: MusicCue = CueScript.new()
	cue.cue_id = id
	cue.weight = weight
	cue.duration_seconds = TRACK_SECONDS
	var list: Array[StringName] = []
	for s in situations:
		list.append(s)
	cue.situations = list
	return cue

func _map(cues: Array, penalty := 0.2) -> MusicMap:
	var map: MusicMap = MapScript.new()
	var list: Array[MusicCue] = []
	for c in cues:
		list.append(c)
	map.cues = list
	map.repeat_penalty = penalty
	# The gap is derived, so a test that wants a known gap states the two
	# things it comes from: how long a track runs and what share of the time
	# music should sound. 200 s of track at a half share is a 200 s gap.
	map.gap_cycle_music_share = 0.5
	map.gap_window_seconds = 90.0
	map.entry_gap_min_seconds = 5.0
	map.entry_gap_max_seconds = 40.0
	return map

func _two_day_cues() -> MusicMap:
	return _map([_cue(&"day_a", [&"day"]), _cue(&"day_b", [&"day"]), _cue(&"night_a", [&"night"])])

func test_only_cues_cast_for_the_situation_are_drawn() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	for i in 40:
		var cue := selector.pick(map, &"day")
		assert_not_null(cue, "a situation with cues should always yield one")
		if cue == null:
			return
		assert_true(cue.cue_id == &"day_a" or cue.cue_id == &"day_b",
			"drew %s, which is not cast for day" % cue.cue_id)

func test_a_situation_with_no_cues_yields_nothing() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	assert_eq(selector.pick(map, &"danger"), null, "danger has no track cast for it")
	assert_eq(selector.pick(map, &"nonsense"), null, "and neither has an unknown situation")
	assert_eq(selector.pick(map, &""), null, "nor the empty situation")

func test_a_zero_weight_cue_is_never_drawn() -> void:
	## Weight is the intended way to bench a track without deleting the casting.
	var map := _map([_cue(&"kept", [&"day"]), _cue(&"benched", [&"day"], 0.0)])
	var selector: MusicSelector = SelectorScript.new(SEED)
	for i in 50:
		var cue := selector.pick(map, &"day")
		assert_not_null(cue, "the remaining cue should still be drawable")
		if cue == null:
			return
		assert_eq(cue.cue_id, &"kept", "a zero-weight cue must stay benched")

func test_the_only_candidate_is_always_drawn() -> void:
	var map := _map([_cue(&"solo", [&"dawn"])])
	var selector: MusicSelector = SelectorScript.new(SEED)
	for i in 10:
		var cue := selector.pick(map, &"dawn")
		assert_not_null(cue, "one candidate is still a candidate")
		if cue == null:
			return
		assert_eq(cue.cue_id, &"solo", "with no alternative there is nothing else to draw")

func test_a_zero_repeat_penalty_forbids_playing_the_same_track_twice_running() -> void:
	var map := _map([_cue(&"day_a", [&"day"]), _cue(&"day_b", [&"day"])], 0.0)
	var selector: MusicSelector = SelectorScript.new(SEED)
	var previous := &""
	for i in 40:
		var cue := selector.pick(map, &"day")
		assert_not_null(cue, "a draw should always succeed here")
		if cue == null:
			return
		assert_true(cue.cue_id != previous, "drew %s twice running at %d" % [cue.cue_id, i])
		previous = cue.cue_id

func test_the_default_penalty_discourages_repeats_without_forbidding_them() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	var repeats := 0
	var previous := &""
	var draws := 400
	for i in draws:
		var cue := selector.pick(map, &"day")
		if cue == null:
			assert_true(false, "a draw should always succeed here")
			return
		if cue.cue_id == previous:
			repeats += 1
		previous = cue.cue_id
	# Even odds would give ~200. A 0.2 penalty on one of two equal cues gives
	# 0.2 / 1.2, about 67. Bounded on both sides: zero repeats would mean the
	# penalty had become a ban, and a third would mean it was doing nothing.
	assert_true(repeats > 0, "a repeat should remain possible, saw none in %d draws" % draws)
	assert_true(repeats < draws / 4, "but should stay uncommon, saw %d in %d" % [repeats, draws])

func test_weight_biases_the_draw() -> void:
	var map := _map([
		_cue(&"heavy", [&"night"], 8.0),
		_cue(&"light_a", [&"night"], 1.0),
		_cue(&"light_b", [&"night"], 1.0),
	], 1.0)
	var selector: MusicSelector = SelectorScript.new(SEED)
	var heavy := 0
	var draws := 400
	for i in draws:
		var cue := selector.pick(map, &"night")
		if cue == null:
			assert_true(false, "a draw should always succeed here")
			return
		if cue.cue_id == &"heavy":
			heavy += 1
	# 8:1:1 is 80%. Wide bounds -- this asserts that weight is honoured at all,
	# not that 400 samples land on the exact expectation.
	assert_true(heavy > draws / 2, "the heavy cue should dominate, got %d of %d" % [heavy, draws])
	assert_true(heavy < draws, "but must not be the only one drawn, got %d of %d" % [heavy, draws])

func test_the_same_seed_replays_the_same_draws() -> void:
	## The two tests above read a distribution off a fixed seed. That is only
	## worth anything if the seed actually determines the sequence.
	var map := _two_day_cues()
	var first: Array = []
	var second: Array = []
	var a: MusicSelector = SelectorScript.new(SEED)
	var b: MusicSelector = SelectorScript.new(SEED)
	for i in 20:
		first.append(a.pick(map, &"day").cue_id)
		second.append(b.pick(map, &"day").cue_id)
	assert_eq(first, second, "the same seed must produce the same sequence")

func test_each_situation_remembers_its_own_last_track() -> void:
	## long_walk is cast for both day and dusk. Drawing it for day must not
	## make dusk think it just played something it did not.
	var map := _map([
		_cue(&"shared", [&"day", &"dusk"]),
		_cue(&"day_only", [&"day"]),
	], 0.0)
	var selector: MusicSelector = SelectorScript.new(SEED)
	# Force `shared` to be day's last draw, then ask dusk, where it is the only
	# candidate. A single shared memory would have nothing to return.
	for i in 4:
		selector.pick(map, &"day")
	var cue := selector.pick(map, &"dusk")
	assert_not_null(cue, "dusk should still have a candidate")
	if cue == null:
		return
	assert_eq(cue.cue_id, &"shared", "dusk's only cue must remain drawable")

func test_the_gap_between_cues_falls_inside_the_derived_range() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	for i in 100:
		var gap := selector.next_gap_seconds(map)
		assert_true(gap >= map.gap_min_seconds() and gap <= map.gap_max_seconds(),
			"gap %f is outside [%f, %f]" % [gap, map.gap_min_seconds(), map.gap_max_seconds()])

func test_the_gap_is_what_the_track_lengths_and_the_target_share_imply() -> void:
	## The gap is not stored anywhere. It is L * (1 - s) / s, and this is the
	## test that would notice if it stopped being that -- including the case
	## the whole change is about: a track re-cut shorter must shorten the gap
	## with it, or the density quietly moves and nobody thinks to look here.
	var map := _two_day_cues()
	assert_almost_eq(map.mean_cue_duration_seconds(), TRACK_SECONDS, 0.0001,
		"three equal-weight cues of the same length average to that length")
	assert_almost_eq(map.gap_mean_seconds(), TRACK_SECONDS, 0.0001,
		"at a half share the gap is exactly as long as the track before it")

	map.gap_cycle_music_share = 0.25
	assert_almost_eq(map.gap_mean_seconds(), TRACK_SECONDS * 3.0, 0.0001,
		"a quarter share is one part music to three parts quiet")

	map.gap_cycle_music_share = 0.5
	for cue in map.cues:
		cue.duration_seconds = TRACK_SECONDS * 0.5
	assert_almost_eq(map.gap_mean_seconds(), TRACK_SECONDS * 0.5, 0.0001,
		"halving the tracks must halve the gap, or the density moved on its own")

func test_a_map_whose_lengths_were_never_measured_errs_towards_silence() -> void:
	## A derivation that fell through to zero would produce wall-to-wall music,
	## which is the loudest possible way to fail. Better a gap that is too long
	## than a game that never stops playing.
	var map := _map([_cue(&"day_a", [&"day"])])
	for cue in map.cues:
		cue.duration_seconds = 0.0
	assert_almost_eq(map.mean_cue_duration_seconds(), MapScript.UNMEASURED_DURATION_SECONDS,
		0.0001, "an unmeasured map must not report a zero-length track")
	assert_true(map.gap_min_seconds() > 60.0,
		"and must not collapse the gap; got %f s" % map.gap_min_seconds())

func test_an_ending_does_not_drag_the_gap_around() -> void:
	## Endings are oneshots: they never precede a gap, so their length has no
	## business setting one. mm.mp3 is 3:58 against night beds of 2:04, so
	## including it would stretch every gap in the game by a third.
	var map := _map([_cue(&"night_a", [&"night"]), _cue(&"finale", [&"ending_unseen"])])
	var oneshot: Array[StringName] = [&"ending_unseen"]
	map.oneshot_situations = oneshot
	map.cues[1].duration_seconds = TRACK_SECONDS * 4.0
	assert_almost_eq(map.mean_cue_duration_seconds(), TRACK_SECONDS, 0.0001,
		"only the tracks that play during the run may set the gap")

func test_the_entry_gap_falls_inside_its_own_shorter_range() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	for i in 100:
		var gap := selector.next_entry_gap_seconds(map)
		assert_true(gap >= map.entry_gap_min_seconds and gap <= map.entry_gap_max_seconds,
			"entry gap %f is outside [%f, %f]" % [gap, map.entry_gap_min_seconds, map.entry_gap_max_seconds])

func test_entry_chance_bounds_are_absolute() -> void:
	var map := _two_day_cues()
	var selector: MusicSelector = SelectorScript.new(SEED)
	map.entry_chance = 0.0
	for i in 50:
		assert_false(selector.roll_entry(map), "at 0.0 a situation change never brings music in early")
	map.entry_chance = 1.0
	for i in 50:
		assert_true(selector.roll_entry(map), "at 1.0 it always does")
