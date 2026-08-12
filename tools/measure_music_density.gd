extends SceneTree

## How much of a run has music in it, and can a player tell a threat's silence
## from an ordinary gap? Both answered by simulating whole seven-day runs and
## counting seconds, not by reasoning about the two ranges.
##
## Run:
##   godot --headless --path <project> --script res://tools/measure_music_density.gd
##
## Everything here is measured through tools/music_run_simulation.gd, the same
## instrument tests/unit/test_music_density.gd uses, so the gate in the suite
## guards the number this tool produced rather than a different one.
##
## BEFORE and AFTER are both run. "Before" is not remembered, it is rebuilt:
## the shipped map with gap_cycle_music_share and gap_window_seconds set back to
## whatever reproduces the old authored 150-420 s gap, and entry_chance back to
## 0.5. The tool prints the reconstructed range so the comparison can be
## checked rather than believed.

const SimulationScript := preload("res://tools/music_run_simulation.gd")
const MAP_PATH := "res://data/audio/music_map.tres"

const RUNS := 200
const FIRST_SEED := 1000
const STEP := 0.25

## What shipped before this change, for the comparison.
const OLD_MIN_GAP := 150.0
const OLD_MAX_GAP := 420.0
const OLD_ENTRY_CHANCE := 0.5

const CLEAN := {"step_seconds": STEP}
const THREATENED := {
	"step_seconds": STEP,
	"threat_mean_gap_seconds": 600.0,
	"threat_dwell_min_seconds": 20.0,
	"threat_dwell_max_seconds": 70.0,
}
const LIVED_IN := {
	"step_seconds": STEP,
	"threat_mean_gap_seconds": 600.0,
	"threat_dwell_min_seconds": 20.0,
	"threat_dwell_max_seconds": 70.0,
	"shelter_mean_gap_seconds": 900.0,
	"shelter_dwell_min_seconds": 120.0,
	"shelter_dwell_max_seconds": 360.0,
}

func _initialize() -> void:
	var after := _load_map()
	if after == null:
		print("measure_music_density: could not load %s" % MAP_PATH)
		quit(1)
		return
	var before := _as_it_shipped(_load_map())

	print("=== the two settings ===")
	_describe("BEFORE", before)
	_describe("AFTER ", after)
	print("")

	print("=== timestep check: does the answer depend on how finely it is sampled? ===")
	for step in [1.0 / 60.0, 0.25, 0.5]:
		var opts := {"step_seconds": step}
		var runs := _runs(after, opts, 12)
		print("  step %.4f s -> share %.4f over 12 runs" % [step, _share(runs)])
	print("")

	print("=== what the knob buys: the cycle share vs the share actually heard ===")
	print("The derivation assumes a track runs to its end and only a gap follows")
	print("it. A real run also brings a track in at every dawn and nightfall, and")
	print("fourteen of those in 6300 s put a floor under the whole thing that the")
	print("gap cannot reach below. This is that offset, measured rather than argued.")
	var sweep := _load_map()
	for target in [0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50]:
		sweep.gap_cycle_music_share = target
		sweep.gap_window_seconds = sweep.post_silence_hold_seconds
		print("  cycle %.2f -> gap %6.1f-%6.1f s -> run share: alone %.4f   lived-in %.4f"
			% [target, sweep.gap_min_seconds(), sweep.gap_max_seconds(),
				_share(_runs(sweep, CLEAN, 60)), _share(_runs(sweep, LIVED_IN, 60))])
	print("")

	for scenario in [["no threats, no shelter", CLEAN],
			["a threat every ~10 min", THREATENED],
			["threats and shelter visits", LIVED_IN]]:
		var label: String = scenario[0]
		var opts: Dictionary = scenario[1]
		print("=== %s, %d runs of 6300 s each ===" % [label, RUNS])
		var before_runs := _runs(before, opts, RUNS)
		var after_runs := _runs(after, opts, RUNS)
		print("  share of a run with music sounding")
		print("    BEFORE %.4f      AFTER %.4f" % [_share(before_runs), _share(after_runs)])
		_per_situation("BEFORE", before_runs)
		_per_situation("AFTER ", after_runs)
		_silence_report("BEFORE", before_runs)
		_silence_report("AFTER ", after_runs)
		_phase_report("BEFORE", before_runs)
		_phase_report("AFTER ", after_runs)
		print("")

	print("=== the acceptance question: can an ordinary gap pass for a threat? ===")
	print("Ordinary gaps taken from the no-threat runs, where nothing can shorten")
	print("one by interrupting it; danger silences from the threatened runs.")
	for settings in [["BEFORE", before], ["AFTER ", after]]:
		var label: String = settings[0]
		var map: MusicMap = settings[1]
		var ordinary := _lengths(_runs(map, CLEAN, RUNS), false)
		var danger := _lengths(_runs(map, THREATENED, RUNS), true)
		_discriminability(label, ordinary, danger)
		# A threat's silence is supposed to be a full gap PLUS the hold. Anything
		# shorter than the shortest that can be means something cut it short.
		var floor_seconds := map.gap_min_seconds() + map.post_silence_hold_seconds
		var cut := danger.bsearch(floor_seconds, true)
		print("         %d of %d threat silences came in under the %.1f s floor (%.1f%%)"
			% [cut, danger.size(), floor_seconds, 100.0 * float(cut) / float(danger.size())])
	quit(0)

# --- setup -----------------------------------------------------------------

func _load_map() -> MusicMap:
	# CACHE_MODE_IGNORE: two loads of the same path otherwise return the SAME
	# object (briefing trap 6), and this tool edits one of them.
	return ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MusicMap

## The shipped map wound back to the numbers the owner was hearing. The gap was
## authored as a flat 150-420 s then, so the equivalent share is whatever makes
## the derivation produce a 285 s mean against these same tracks.
func _as_it_shipped(map: MusicMap) -> MusicMap:
	var mean_track := map.mean_cue_duration_seconds()
	var old_mean_gap := (OLD_MIN_GAP + OLD_MAX_GAP) * 0.5
	map.gap_cycle_music_share = mean_track / (mean_track + old_mean_gap)
	map.gap_window_seconds = OLD_MAX_GAP - OLD_MIN_GAP
	map.entry_chance = OLD_ENTRY_CHANCE
	return map

func _describe(label: String, map: MusicMap) -> void:
	print("  %s  tracks avg %.3f s   gap %.3f-%.3f s   entry gap %.0f-%.0f s at p=%.2f   hold %.0f s"
		% [label, map.mean_cue_duration_seconds(), map.gap_min_seconds(), map.gap_max_seconds(),
			map.entry_gap_min_seconds, map.entry_gap_max_seconds, map.entry_chance,
			map.post_silence_hold_seconds])

func _runs(map: MusicMap, options: Dictionary, count: int) -> Array:
	var out: Array = []
	for i in count:
		var simulation = SimulationScript.new()
		out.append(simulation.run(map, FIRST_SEED + i, options))
	return out

# --- reading the runs -------------------------------------------------------

func _share(runs: Array) -> float:
	var music := 0.0
	var total := 0.0
	for r in runs:
		music += float(r["music_seconds"])
		total += float(r["seconds"])
	return music / total if total > 0.0 else 0.0

func _per_situation(label: String, runs: Array) -> void:
	var seconds: Dictionary = {}
	var music: Dictionary = {}
	for r in runs:
		for key in r["situation_seconds"]:
			seconds[key] = float(seconds.get(key, 0.0)) + float(r["situation_seconds"][key])
		for key in r["situation_music_seconds"]:
			music[key] = float(music.get(key, 0.0)) + float(r["situation_music_seconds"][key])
	var names: Array = seconds.keys()
	names.sort()
	var line := "    %s per situation:" % label
	for key in names:
		var total: float = seconds[key]
		if total <= 0.0:
			continue
		var name_text := String(key)
		if name_text == "":
			name_text = "(none)"
		line += "  %s %.3f" % [name_text, float(music.get(key, 0.0)) / total]
	print(line)

func _lengths(runs: Array, danger: bool) -> Array:
	var out: Array = []
	for r in runs:
		for s in r["silences"]:
			if bool(s["danger"]) == danger:
				out.append(float(s["length"]))
	out.sort()
	return out

func _silence_report(label: String, runs: Array) -> void:
	var ordinary := _lengths(runs, false)
	var danger := _lengths(runs, true)
	print("    %s silences: ordinary n=%d %s | after a threat n=%d %s"
		% [label, ordinary.size(), _summary(ordinary), danger.size(), _summary(danger)])

func _phase_report(label: String, runs: Array) -> void:
	var delays: Array = []
	for r in runs:
		for d in r["phase_start_delays"]:
			delays.append(float(d))
	delays.sort()
	var late := 0
	for d in delays:
		if d > 45.0:
			late += 1
	print("    %s dawn/nightfall to music: n=%d %s | %d of them took over 45 s"
		% [label, delays.size(), _summary(delays), late])

func _summary(values: Array) -> String:
	if values.is_empty():
		return "(none)"
	var total := 0.0
	for v in values:
		total += float(v)
	return "min %.1f med %.1f mean %.1f p90 %.1f max %.1f" % [
		float(values[0]),
		_quantile(values, 0.5),
		total / float(values.size()),
		_quantile(values, 0.9),
		float(values[values.size() - 1]),
	]

func _quantile(sorted_values: Array, q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(round(q * float(sorted_values.size() - 1)))
	return float(sorted_values[clampi(index, 0, sorted_values.size() - 1)])

## Two questions, both about whether the LENGTH of a silence carries anything:
## how often an ordinary gap reaches a typical threat silence, and how often a
## randomly picked ordinary gap is at least as long as a randomly picked threat
## silence. The second is the honest one -- it is the coin flip a player is
## making when a silence goes on.
func _discriminability(label: String, ordinary: Array, danger: Array) -> void:
	if ordinary.is_empty() or danger.is_empty():
		print("  %s (not enough samples)" % label)
		return
	var median_danger := _quantile(danger, 0.5)
	var reach := float(ordinary.size() - ordinary.bsearch(median_danger, true)) / float(ordinary.size())
	var confusion := 0.0
	for d in danger:
		confusion += float(ordinary.size() - ordinary.bsearch(float(d), true))
	confusion /= float(ordinary.size()) * float(danger.size())
	print("  %s ordinary n=%d %s" % [label, ordinary.size(), _summary(ordinary)])
	print("         danger  n=%d %s" % [danger.size(), _summary(danger)])
	print("         an ordinary gap reaches the median threat silence %.2f%% of the time"
		% (reach * 100.0))
	print("         a random ordinary gap outlasts a random threat silence %.2f%% of the time"
		% (confusion * 100.0))
	print("         longest ordinary %.1f s vs shortest threat silence %.1f s -> %s"
		% [float(ordinary[ordinary.size() - 1]), float(danger[0]),
			"they overlap" if float(ordinary[ordinary.size() - 1]) >= float(danger[0])
				else "no overlap at all"])
