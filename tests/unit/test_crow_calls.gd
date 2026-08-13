extends TestCase

## The caws: their rhythm, and the fact that they follow the birds.
##
## ---------------------------------------------------------------------------
## THE FOLDER IS NO LONGER EMPTY, AND THAT CHANGED WHAT THIS FILE HAS TO SAY
## ---------------------------------------------------------------------------
## This header used to open "there is no crow audio in this repository". Three
## caws arrived at `7cbe595`. What is asserted here is still everything that is
## NOT the sound file -- how many calls a burst gets, when they land, which birds
## make them, and that a voice tracks its bird rather than staying where the bird
## was -- because all of that is wrong or right regardless of the folder, and all
## of it is what a naive implementation gets wrong: one trigger per bird on the
## frame the flock leaves, which is five crows cawing in unison.
##
## ---------------------------------------------------------------------------
## AND NOTE WHAT THIS FILE STILL CANNOT SEE
## ---------------------------------------------------------------------------
## Nothing here -- and nothing anywhere in this suite -- asserts that a caw was
## AUDIBLE. Measured on the real scene at HEAD, on the master bus peak: a caw at
## the player reaches **-200.00 dB**, digital silence, while `playing` reports
## `true`. The cause is outside `crow_calls.gd` (the listener is the camera and
## the camera rides a 90 m boom, against this system's 60 m cutoff) and is
## written up in `.superpowers/sdd/wave3/task-w3-bird-system-explained.md`.
##
## It is recorded here because this file is where the next person will come
## looking, and because it is the briefing's 「设进去了 ≠ 起作用了」 one notch
## further along: the suite has moved from "`play()` returned true" to "the
## server accepted it", and has never once reached "a sound was heard".

const CallsScript := preload("res://src/entities/wildlife/crow_calls.gd")
const CrowScript := preload("res://src/entities/wildlife/crow.gd")

const FRAME := 1.0 / 60.0

var _calls: CrowCalls


func before_each() -> void:
	_calls = CallsScript.new()
	_calls.random_seed = 4711


func after_each() -> void:
	_calls.free()


func _some_birds(count: int) -> Array[Crow]:
	var birds: Array[Crow] = []
	for index in range(count):
		var crow: Crow = CrowScript.new()
		crow.perch_on(Vector3(0.0, 6.0, float(index) * 2.0), Vector3(1.0, 0.0, 0.0))
		birds.append(crow)
	return birds


func _release(birds: Array[Crow]) -> void:
	for crow in birds:
		crow.free()


# --- the honest part -------------------------------------------------------------


func test_the_folder_is_where_the_caws_go() -> void:
	# Not an assertion that it MUST hold any particular number -- an empty folder
	# is a legal state and this should keep passing through it. What it pins is
	# that the folder is readable and is the data.
	var found := _calls.call_count()
	assert_true(found >= 0, "the call folder could not be read at all")


## Briefing trap 17. `DirAccess.get_files()` lists the asset AND its `.import`
## sidecar when running from source, and `calls()` trims `.import` off every name
## so that one line serves both a source tree and an exported build -- which made
## both listings name the same file and loaded every caw TWICE. `call_count()`
## reported **6 for the 3 files on disk**.
##
## It is asserted as "no path appears twice" rather than as "the count is 3",
## deliberately: the count is a fact about the folder today and would have to be
## edited every time a caw is added, while the duplication is the defect and is
## true of any folder. `ResourceLoader` caches by path, so a doubly-loaded caw is
## literally the same object twice over -- which is why identity is enough here.
##
## Why it survived: a uniform draw over a doubled list is still uniform, so it
## SOUNDED correct. Nothing errored. The same shape waits in anything that
## enumerates a directory, and the sidecar count is now two (`.uid` as well).
func test_no_caw_is_loaded_twice() -> void:
	var streams := _calls.calls()
	var seen := {}
	for stream in streams:
		var path := stream.resource_path
		assert_false(
			seen.has(path),
			"%s was loaded more than once -- the .import sidecar was counted as a second caw" % path
		)
		seen[path] = true
	assert_eq(
		_calls.call_count(),
		seen.size(),
		"call_count() reports %d for %d distinct caw(s) on disk" % [_calls.call_count(), seen.size()]
	)


## Silence must not be a crash. Every schedule still runs with nothing to play.
func test_a_burst_with_no_audio_on_disk_still_schedules_and_still_ticks() -> void:
	var birds := _some_birds(4)
	assert_true(_calls.announce(birds) > 0, "a flock of four scheduled no calls at all")
	var left := 3.0
	while left > 0.0:
		_calls.advance(FRAME)
		left -= FRAME
	for entry in _calls.pending():
		assert_true(entry["played"], "a scheduled call at %.3f s never fired" % float(entry["at"]))
	_release(birds)


# --- the rhythm ------------------------------------------------------------------


## NOT A CHORUS. The failure this exists to catch is the obvious implementation:
## one call per bird, all on the frame the flock goes up.
func test_it_is_not_one_caw_per_bird() -> void:
	var birds := _some_birds(5)
	var scheduled := _calls.announce(birds)
	assert_true(
		scheduled < birds.size(),
		"five birds scheduled %d calls -- that is a chorus, not a flock" % scheduled
	)
	assert_true(scheduled >= 1, "a flock of five made no sound at all")
	_release(birds)


## One, then two overlapping, then a gap. The pattern is the point and it is
## measurable: somewhere in the schedule there is a pair closer together than any
## reasonable single caw, and somewhere there is a silence.
func test_the_pattern_is_one_then_an_overlapping_pair_then_a_gap() -> void:
	# A seed that draws the full four-call shape.
	var found := false
	for seed in [4711, 3, 41, 20260812, 31337, 9001, 77, 1234]:
		_calls.random_seed = seed
		_calls.seed_rng()
		var birds := _some_birds(5)
		var scheduled := _calls.announce(birds)
		if scheduled >= 4:
			var times: Array = []
			for entry in _calls.pending():
				times.append(float(entry["at"]))
			var gaps: Array = []
			for index in range(1, times.size()):
				gaps.append(times[index] - times[index - 1])
			var tightest := 1e9
			var loosest := -1e9
			for gap in gaps:
				tightest = minf(tightest, float(gap))
				loosest = maxf(loosest, float(gap))
			assert_true(
				tightest <= _calls.overlap_max + 0.001,
				"seed %d: the closest two calls are %.3f s apart, which is a sequence not an overlap" % [
					seed, tightest]
			)
			assert_true(
				loosest >= _calls.gap_min - 0.001,
				"seed %d: the longest silence is %.3f s, which is a rest not a gap" % [seed, loosest]
			)
			assert_true(
				loosest > tightest * 3.0,
				"seed %d: the gaps are %.3f..%.3f -- that is a metre, not a rhythm" % [
					seed, tightest, loosest]
			)
			found = true
			_release(birds)
			break
		_release(birds)
	assert_true(found, "no seed out of eight drew a four-call burst")


## Two birds, not one bird twice. A crow answering itself a tenth of a second
## later is one animal with a stutter.
func test_the_overlapping_pair_comes_from_two_different_birds() -> void:
	# Forced to three calls rather than hoping the draw gives three -- written as
	# an `if` first, and the seed drew a one-call burst, so the test reported
	# itself as having executed no assertions at all. The runner catches that; a
	# quieter framework would have shown a green line for a test that checked
	# nothing.
	_calls.fewest = 3
	var birds := _some_birds(5)
	var scheduled := _calls.announce(birds)
	assert_true(scheduled >= 3, "a forced three-call burst scheduled only %d" % scheduled)
	if scheduled < 3:
		_release(birds)
		return
	var pending := _calls.pending()
	assert_true(
		int(pending[1]["bird"]) != int(pending[2]["bird"]),
		"the overlapping pair is bird %d answering itself" % int(pending[1]["bird"])
	)
	_release(birds)


## Irregular across bursts as well as within one. The ruling's axis is "哪几声叫、
## 在什么时刻", and a fixed rhythm played at a random start time is not that.
func test_no_two_bursts_share_a_rhythm() -> void:
	var firsts: Array = []
	var counts: Dictionary = {}
	for seed in [3, 41, 4711, 20260812, 31337, 9001]:
		_calls.random_seed = seed
		_calls.seed_rng()
		var birds := _some_birds(5)
		counts[_calls.announce(birds)] = true
		var pending := _calls.pending()
		if not pending.is_empty():
			firsts.append(float(pending[0]["at"]))
		_release(birds)
	assert_true(counts.size() >= 2, "every burst made exactly the same number of calls")
	var low := 1e9
	var high := -1e9
	for at in firsts:
		low = minf(low, float(at))
		high = maxf(high, float(at))
	assert_true(
		high - low > 0.05,
		"the first caw landed within %.4f s of the same moment in every burst" % (high - low)
	)


# --- positional --------------------------------------------------------------------


## The half a non-positional implementation cannot have: a call belongs to a bird
## and goes where it goes.
func test_a_call_is_addressed_to_a_bird_and_not_to_a_place() -> void:
	var birds := _some_birds(4)
	_calls.announce(birds)
	var seen: Dictionary = {}
	for entry in _calls.pending():
		var index := int(entry["bird"])
		assert_true(
			index >= 0 and index < birds.size(),
			"a call was addressed to bird %d out of %d" % [index, birds.size()]
		)
		seen[index] = true
	assert_true(
		seen.size() >= mini(2, _calls.pending().size()),
		"every call in the burst came from the same bird"
	)
	_release(birds)


## And the birds it is addressed to are moving apart, which is what makes the
## calls scatter and recede. Measured on the real departure rather than asserted.
func test_the_birds_a_burst_is_addressed_to_actually_separate() -> void:
	var birds := _some_birds(4)
	_calls.announce(birds)
	var before := _spread_of(birds)
	var bearing := 0.0
	for crow in birds:
		crow.scatter(Vector3(cos(bearing), 0.4, sin(bearing)).normalized(), 0.0, 2.0, 0.9)
		bearing += TAU / float(birds.size())
	# Long enough to be past the launch AND past the mill. Written as 2.5 s first,
	# which is 0.93 s of launch plus 0.9 s of wheeling and leaves under a second of
	# committed flight -- the flock had barely begun to open out and the maximum
	# pairwise distance had actually FALLEN, because four birds turning the same
	# way in formation come closer before they diverge.
	var left := 5.0
	while left > 0.0:
		for crow in birds:
			crow.advance(FRAME)
		left -= FRAME
	var after := _spread_of(birds)
	assert_true(
		after > before + 4.0,
		"the flock spread from %.2f m to %.2f m -- the calls would not scatter" % [before, after]
	)
	_release(birds)


func _spread_of(birds: Array[Crow]) -> float:
	var worst := 0.0
	for a in birds:
		for b in birds:
			worst = maxf(worst, a.where().distance_to(b.where()))
	return worst
