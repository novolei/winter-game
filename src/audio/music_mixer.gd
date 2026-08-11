class_name MusicMixer
extends RefCounted

## The fade state machine for music. Decides gains; plays nothing.
##
## Separated from MusicDirector so the behaviour the brief cares about most --
## music arrives and leaves by fade, and can reach true silence and stay there
## -- is testable with no audio device, no Node and no decoding.
##
## Each voice carries a `level` in 0..1 which ramps linearly, and reports a
## gain of sqrt(level). That mapping is the point: during a crossfade one
## level runs 1 -> 0 while the other runs 0 -> 1, so the levels always sum to
## 1 and the GAINS always sum to 1 in power. Ramping the gains linearly
## instead would dip about 3 dB in the middle of every change, which is
## audible as a hole -- and in a game where the music is a survival readout,
## a hole in the music reads as information.

enum State { SILENT, FADING_IN, PLAYING, CROSSFADING, FADING_OUT }

## Three, not two. Two is enough for a crossfade, but a third request arriving
## mid-crossfade would then have to evict a voice that is still audible, which
## is the hard cut this system exists to avoid. With three, an eviction needs
## four overlapping requests inside one fade.
const VOICE_COUNT := 3

const EPSILON := 0.00001

var _cue_ids: Array[StringName] = [&"", &"", &""]
var _levels: Array[float] = [0.0, 0.0, 0.0]
var _targets: Array[float] = [0.0, 0.0, 0.0]
var _rates: Array[float] = [0.0, 0.0, 0.0]

## Bring `cue_id` up over `fade_seconds`, taking whatever else is sounding
## down over the same span. Asking for the cue already playing does nothing.
func play(cue_id: StringName, fade_seconds: float) -> void:
	if cue_id == &"":
		fade_to_silence(fade_seconds)
		return
	var rate := 1.0 / maxf(fade_seconds, EPSILON)
	var slot := -1
	for i in VOICE_COUNT:
		if _cue_ids[i] == cue_id:
			slot = i
			break
	if slot != -1 and _targets[slot] > 0.0:
		return  # already the active cue; a cue must not crossfade with itself
	for i in VOICE_COUNT:
		if _cue_ids[i] != &"":
			_targets[i] = 0.0
			_rates[i] = rate
	if slot == -1:
		slot = _free_slot()
	if _cue_ids[slot] != cue_id:
		_cue_ids[slot] = cue_id
		_levels[slot] = 0.0
	_targets[slot] = 1.0
	_rates[slot] = rate

func fade_to_silence(fade_seconds: float) -> void:
	var rate := 1.0 / maxf(fade_seconds, EPSILON)
	for i in VOICE_COUNT:
		if _cue_ids[i] != &"":
			_targets[i] = 0.0
			_rates[i] = rate

## The stream ran out on its own. Only the active cue is dropped: a voice that
## is already on its way out is mid-fade for a reason, and cutting it because
## its file happened to end would reintroduce the hard cut.
func notify_finished(cue_id: StringName) -> void:
	for i in VOICE_COUNT:
		if _cue_ids[i] == cue_id and _targets[i] > 0.0:
			_release(i)

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	for i in VOICE_COUNT:
		if _cue_ids[i] == &"":
			continue
		var step := _rates[i] * delta
		if _levels[i] < _targets[i]:
			_levels[i] = minf(_targets[i], _levels[i] + step)
		elif _levels[i] > _targets[i]:
			_levels[i] = maxf(_targets[i], _levels[i] - step)
		if _targets[i] <= 0.0 and _levels[i] <= EPSILON:
			_release(i)

func state() -> State:
	var rising := 0
	var falling := 0
	var holding := 0
	for i in VOICE_COUNT:
		if _cue_ids[i] == &"":
			continue
		if _levels[i] < _targets[i]:
			rising += 1
		elif _levels[i] > _targets[i]:
			falling += 1
		else:
			holding += 1
	if rising == 0 and falling == 0 and holding == 0:
		return State.SILENT
	if rising > 0 and (falling > 0 or holding > 0):
		return State.CROSSFADING
	if rising > 0:
		return State.FADING_IN
	if falling > 0 and holding == 0:
		return State.FADING_OUT
	return State.PLAYING

## The cue the mixer is heading towards, which is not the same as the cue
## currently loudest. Empty while fading out and while silent.
func active_cue_id() -> StringName:
	for i in VOICE_COUNT:
		if _cue_ids[i] != &"" and _targets[i] > 0.0:
			return _cue_ids[i]
	return &""

func is_silent() -> bool:
	for i in VOICE_COUNT:
		if _cue_ids[i] != &"":
			return false
	return true

func voice_cue_id(index: int) -> StringName:
	if index < 0 or index >= VOICE_COUNT:
		return &""
	return _cue_ids[index]

func voice_gain(index: int) -> float:
	if index < 0 or index >= VOICE_COUNT:
		return 0.0
	return sqrt(_levels[index])

## Sum of the squared gains, which is the sum of the levels. 1.0 through a
## clean crossfade; anything less is a dip the player would hear.
func total_power() -> float:
	var total := 0.0
	for i in VOICE_COUNT:
		if _cue_ids[i] != &"":
			total += _levels[i]
	return total

func _free_slot() -> int:
	for i in VOICE_COUNT:
		if _cue_ids[i] == &"":
			return i
	# Every voice busy. Evict the quietest, which is the least audible cut
	# available -- and unreachable without four requests inside one fade.
	var quietest := 0
	for i in VOICE_COUNT:
		if _levels[i] < _levels[quietest]:
			quietest = i
	return quietest

func _release(index: int) -> void:
	_cue_ids[index] = &""
	_levels[index] = 0.0
	_targets[index] = 0.0
	_rates[index] = 0.0
