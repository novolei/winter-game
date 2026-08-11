class_name MusicSelector
extends RefCounted

## Draws which track plays next, and how much silence comes before it.
##
## Kept apart from MusicDirector so the randomness can be seeded and the
## distribution actually checked. Holds no game state -- the map is passed in
## on every call, so re-casting a track in data changes what this draws with
## no change here.

var _rng := RandomNumberGenerator.new()

## situation -> the cue_id drawn for it last time. Per situation, not global:
## a track cast for both day and dusk that was just heard in daylight should
## not be treated as "just played" by dusk, which may have nothing else.
var _last: Dictionary = {}

## A seed of 0 means randomise -- the shipping behaviour. Tests pass a fixed
## seed so a distribution can be asserted.
func _init(seed_value := 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

func pick(map: MusicMap, situation: StringName) -> MusicCue:
	if map == null:
		return null
	var candidates := map.cues_for(situation)
	if candidates.is_empty():
		return null

	var last: StringName = _last.get(situation, &"")
	var penalty := clampf(map.repeat_penalty, 0.0, 1.0)
	var weights: Array[float] = []
	var total := 0.0
	for entry in candidates:
		var cue: MusicCue = entry
		var weight: float = cue.weight
		if cue.cue_id == last:
			weight *= penalty
		weights.append(weight)
		total += weight

	var chosen: MusicCue = null
	if total <= 0.0:
		# Only reachable when the one candidate is also the last one played and
		# the penalty is 0. A situation with a single cue has no alternative to
		# offer, so repeat it rather than fall silent.
		chosen = candidates[candidates.size() - 1]
	else:
		# randf() is [0, 1), so roll < total and the strict comparison below is
		# always crossed. Strict, so a candidate whose effective weight the
		# penalty drove to zero can never be landed on.
		var roll := _rng.randf() * total
		for i in candidates.size():
			roll -= weights[i]
			if roll < 0.0:
				chosen = candidates[i]
				break
		if chosen == null:
			chosen = candidates[candidates.size() - 1]

	_last[situation] = chosen.cue_id
	return chosen

## Silence after a track ends before the next one may begin. The long one.
func next_gap_seconds(map: MusicMap) -> float:
	if map == null:
		return 0.0
	return _rng.randf_range(map.min_gap_seconds, map.max_gap_seconds)

## Silence after a situation begins before its cue may begin. The short one,
## so that dawn occasionally gets dawn music instead of having ended first.
func next_entry_gap_seconds(map: MusicMap) -> float:
	if map == null:
		return 0.0
	return _rng.randf_range(map.entry_gap_min_seconds, map.entry_gap_max_seconds)

## Whether this situation change gets the short gap at all. Below 1.0 is what
## keeps the run from being scored end to end.
func roll_entry(map: MusicMap) -> bool:
	if map == null:
		return false
	return _rng.randf() < map.entry_chance

func forget(situation: StringName) -> void:
	_last.erase(situation)
