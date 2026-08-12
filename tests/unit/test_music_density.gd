extends TestCase

## How much of a run has music in it, measured rather than asserted.
##
## Every other music test checks a decision in isolation. This one plays whole
## seven-day runs through the real director with the shipped map and counts the
## seconds, because the thing the owner reported -- "I often hear no music at
## all" -- is not visible in any single decision. It is a property of the
## distribution, and the only way to see a distribution is to draw from it.
##
## The instrument is tools/music_run_simulation.gd, the same one
## tools/measure_music_density.gd uses to settle these numbers over hundreds of
## runs. This file runs a handful, with fixed seeds, and holds the answer still.
## Bounds are wide on purpose: a gate that pins a mean to two decimal places
## fails on the next re-cut of a track, which is a change this system is
## supposed to absorb.

const SimulationScript := preload("res://tools/music_run_simulation.gd")
const MAP_PATH := "res://data/audio/music_map.tres"

## Enough runs that the mean is steady to well under a percentage point and
## there are hundreds of silences to look at, few enough that the suite does
## not notice. tools/measure_music_density.gd runs 400.
const RUNS := 8
const FIRST_SEED := 41

## Coarser than the 1/60 the game runs at. Checked against 1/60 in the
## measuring tool, not assumed: the share came out the same to 0.1 pp.
const STEP := 0.25

func _map() -> MusicMap:
	# CACHE_MODE_IGNORE: ResourceLoader hands every caller the same instance
	# (briefing trap 6), and these runs must not inherit a map another test has
	# been editing.
	return ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MusicMap

func _run_map(map: MusicMap, options: Dictionary, count: int) -> Array:
	var out: Array = []
	for i in count:
		var simulation = SimulationScript.new()
		out.append(simulation.run(map, FIRST_SEED + i, options))
	return out

func _run_many(options: Dictionary) -> Array:
	return _run_map(_map(), options, RUNS)

func _clean_runs() -> Array:
	## No threats, no shelter: the density the gap alone produces.
	return _run_many({"step_seconds": STEP})

func _threatened_runs() -> Array:
	## A threat about every ten minutes, present for twenty to seventy seconds.
	## Wave 5 owns the system that will really emit these; until it exists the
	## arrival model is an assumption and is stated here rather than buried.
	return _run_many({
		"step_seconds": STEP,
		"threat_mean_gap_seconds": 600.0,
		"threat_dwell_min_seconds": 20.0,
		"threat_dwell_max_seconds": 70.0,
	})

func _share(runs: Array) -> float:
	var music := 0.0
	var total := 0.0
	for r in runs:
		music += float(r["music_seconds"])
		total += float(r["seconds"])
	return music / total if total > 0.0 else 0.0

func _silences(runs: Array, danger: bool) -> Array:
	var out: Array = []
	for r in runs:
		for s in r["silences"]:
			if bool(s["danger"]) == danger:
				out.append(float(s["length"]))
	out.sort()
	return out

func test_a_run_is_about_half_music() -> void:
	## The owner asked for roughly half. Wide bounds: below a third and the
	## complaint that started this is back, above two thirds and the game is
	## scored end to end, which is the thing the sparseness exists to avoid.
	var runs := _clean_runs()
	var share := _share(runs)
	assert_true(share > 0.33,
		"only %.1f%% of a run had music in it; the owner's complaint was that he"
		% (share * 100.0)
		+ " often hears none")
	assert_true(share < 0.67,
		"%.1f%% of a run had music in it, which is a soundtrack rather than a"
		% (share * 100.0)
		+ " game that goes quiet")

func test_the_density_knob_still_moves_the_density() -> void:
	## gap_cycle_music_share governs the gap, and the gap is only part of what
	## a run is made of -- every dawn and nightfall brings a track in on top of
	## it. That floor is high enough that the knob has less leverage than its
	## name suggests, and it would be entirely possible for a future change to
	## take the last of that leverage away without failing anything.
	##
	## A knob that does nothing is worse than no knob, because someone will
	## turn it and believe the result. This is the test that notices.
	var quiet := _map()
	var busy := _map()
	assert_not_null(quiet, "the map must load")
	if quiet == null or busy == null:
		return
	quiet.gap_cycle_music_share = 0.20
	busy.gap_cycle_music_share = 0.50
	assert_true(busy.gap_mean_seconds() < quiet.gap_mean_seconds(),
		"more music per cycle has to mean a shorter gap")
	var quiet_share := _share(_run_map(quiet, {"step_seconds": STEP}, 4))
	var busy_share := _share(_run_map(busy, {"step_seconds": STEP}, 4))
	assert_true(busy_share - quiet_share > 0.10,
		"turning the knob from 0.20 to 0.50 moved the measured share only from"
		+ " %.1f%% to %.1f%%" % [quiet_share * 100.0, busy_share * 100.0])

func test_every_dawn_and_every_nightfall_brings_music_with_it() -> void:
	## The point of taking entry_chance to 1.0. A player can only read anything
	## into music being absent at nightfall if music is otherwise reliably
	## there -- so with no threat in play, every one of the fourteen phase
	## boundaries in a run must be followed by music, soon.
	var runs := _clean_runs()
	var map := _map()
	assert_not_null(map, "the map must load")
	if map == null:
		return
	var worst := 0.0
	var count := 0
	for r in runs:
		for delay in r["phase_start_delays"]:
			worst = maxf(worst, float(delay))
			count += 1
	assert_eq(count, RUNS * 14, "seven days is fourteen phase boundaries per run")
	assert_true(worst <= map.entry_gap_max_seconds + STEP,
		"a phase began and music took %.1f s to arrive; the entry gap tops out at %.1f s"
		% [worst, map.entry_gap_max_seconds])

func test_the_quiet_after_a_threat_outlasts_every_ordinary_gap() -> void:
	## The acceptance test for the whole change, and the reason the gap window
	## is no wider than post_silence_hold_seconds.
	##
	## GDD section 9 makes the music LEAVING the signal that something is near.
	## That reading is only available if a silence long enough to mean danger
	## cannot also happen for no reason -- so the longest ordinary gap must not
	## reach the shortest danger silence. Measured across whole runs rather
	## than argued from the two ranges, because the director spends gaps in
	## places the ranges do not describe.
	var ordinary := _silences(_clean_runs(), false)
	var threatened := _silences(_threatened_runs(), true)
	assert_true(ordinary.size() > 50, "only %d ordinary gaps to compare" % ordinary.size())
	assert_true(threatened.size() > 20, "only %d danger silences to compare" % threatened.size())
	if ordinary.is_empty() or threatened.is_empty():
		return
	var longest_ordinary: float = ordinary[ordinary.size() - 1]
	var shortest_danger: float = threatened[0]
	assert_true(shortest_danger > longest_ordinary,
		"the shortest silence a threat produced was %.1f s and the longest gap that"
		% shortest_danger
		+ " happened for no reason was %.1f s; a player cannot tell those apart"
		% longest_ordinary)
