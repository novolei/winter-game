extends TestCase

## The fade state machine. MusicMixer decides gains and plays nothing, so all
## of this runs headless with no audio device and no Node -- it extends
## RefCounted and frees itself.
##
## What is worth testing here is the property the brief makes non-negotiable:
## music changes by crossfade and never by cut, and it can reach true silence
## and stay there.

const MixerScript := preload("res://src/audio/music_mixer.gd")

const FADE := 6.0

func _faded_in(cue_id := &"a") -> MusicMixer:
	var mixer: MusicMixer = MixerScript.new()
	mixer.play(cue_id, FADE)
	mixer.advance(FADE)
	return mixer

func test_a_new_mixer_is_silent() -> void:
	var mixer: MusicMixer = MixerScript.new()
	assert_true(mixer.is_silent(), "nothing has been asked for yet")
	assert_eq(mixer.state(), MusicMixer.State.SILENT, "and the state should say so")
	assert_eq(mixer.active_cue_id(), &"", "with no cue claimed")

func test_play_fades_in_rather_than_jumping_to_full() -> void:
	var mixer: MusicMixer = MixerScript.new()
	mixer.play(&"a", FADE)
	mixer.advance(0.01)
	var gain: float = mixer.voice_gain(0)
	assert_true(gain > 0.0, "the fade should have started")
	assert_true(gain < 0.2, "but a 6 second fade must not be most of the way up after 10 ms, got %f" % gain)
	assert_eq(mixer.state(), MusicMixer.State.FADING_IN, "state should report the fade")

func test_a_fade_in_completes_after_exactly_its_own_duration() -> void:
	var mixer: MusicMixer = MixerScript.new()
	mixer.play(&"a", FADE)
	mixer.advance(FADE - 0.1)
	assert_true(mixer.voice_gain(0) < 1.0, "not finished a tenth of a second early")
	mixer.advance(0.2)
	assert_almost_eq(mixer.voice_gain(0), 1.0, 0.0001, "full gain once the fade time has passed")
	assert_eq(mixer.state(), MusicMixer.State.PLAYING, "and the fade is over")
	assert_eq(mixer.active_cue_id(), &"a", "the cue that was asked for is the one playing")

func test_a_second_cue_crossfades_and_never_cuts() -> void:
	var mixer := _faded_in(&"a")
	mixer.play(&"b", FADE)
	mixer.advance(0.1)
	assert_eq(mixer.state(), MusicMixer.State.CROSSFADING, "two cues should now be in flight")
	var outgoing := 0.0
	var incoming := 0.0
	for i in MusicMixer.VOICE_COUNT:
		if mixer.voice_cue_id(i) == &"a":
			outgoing = mixer.voice_gain(i)
		elif mixer.voice_cue_id(i) == &"b":
			incoming = mixer.voice_gain(i)
	# The whole point: 100 ms into a 6 second change, the old track is still
	# almost entirely there. A hard cut would read as 0.0 here.
	assert_true(outgoing > 0.95, "the outgoing cue must still be audible, got %f" % outgoing)
	assert_true(incoming > 0.0, "and the incoming one must have begun, got %f" % incoming)

func test_a_crossfade_holds_constant_power_throughout() -> void:
	## Ramping both voices linearly in amplitude dips ~3 dB in the middle of
	## every change, which is audible as a hole. Equal-power ramps do not.
	var mixer := _faded_in(&"a")
	mixer.play(&"b", FADE)
	var steps := 60
	for i in steps:
		mixer.advance(FADE / float(steps))
		assert_almost_eq(mixer.total_power(), 1.0, 0.001,
			"power should stay flat across the crossfade, dipped at step %d" % i)

func test_a_crossfade_ends_with_only_the_new_cue() -> void:
	var mixer := _faded_in(&"a")
	mixer.play(&"b", FADE)
	mixer.advance(FADE)
	assert_eq(mixer.active_cue_id(), &"b", "the new cue owns the mix")
	assert_eq(mixer.state(), MusicMixer.State.PLAYING, "and the change is over")
	for i in MusicMixer.VOICE_COUNT:
		if mixer.voice_cue_id(i) == &"a":
			assert_true(false, "the outgoing cue should have been released")

func test_asking_for_the_cue_already_playing_changes_nothing() -> void:
	var mixer := _faded_in(&"a")
	mixer.play(&"a", FADE)
	mixer.advance(0.1)
	assert_eq(mixer.state(), MusicMixer.State.PLAYING, "a cue must not crossfade with itself")
	assert_almost_eq(mixer.voice_gain(0), 1.0, 0.0001, "and its gain should be undisturbed")

func test_fade_to_silence_reaches_actual_silence() -> void:
	var mixer := _faded_in()
	mixer.fade_to_silence(3.0)
	mixer.advance(0.1)
	assert_eq(mixer.state(), MusicMixer.State.FADING_OUT, "it should be on its way out")
	assert_true(mixer.voice_gain(0) > 0.0, "gradually -- a fade, not a cut")
	mixer.advance(3.0)
	assert_true(mixer.is_silent(), "and it must arrive at silence, not merely near it")
	assert_almost_eq(mixer.total_power(), 0.0, 0.0001, "with no residual gain anywhere")
	assert_eq(mixer.active_cue_id(), &"", "and no cue still claimed")

func test_silence_persists() -> void:
	## GDD section 9 asks the music to drop away when a threat is near and to
	## STAY away. A mixer that drifted back up on its own would undo the only
	## audio idea the design insists on.
	var mixer := _faded_in()
	mixer.fade_to_silence(3.0)
	mixer.advance(3.0)
	mixer.advance(600.0)
	assert_true(mixer.is_silent(), "ten minutes later it is still silent")
	assert_eq(mixer.state(), MusicMixer.State.SILENT, "and the state agrees")

func test_a_cue_that_ends_leaves_the_mixer_silent() -> void:
	var mixer := _faded_in(&"a")
	mixer.notify_finished(&"a")
	assert_true(mixer.is_silent(), "a track that ran out is over immediately")
	assert_eq(mixer.active_cue_id(), &"", "and stops being the active cue")

func test_an_end_notice_for_some_other_cue_is_ignored() -> void:
	var mixer := _faded_in(&"a")
	mixer.notify_finished(&"b")
	assert_false(mixer.is_silent(), "a stale notice must not stop what is playing")
	assert_eq(mixer.active_cue_id(), &"a", "the active cue is unchanged")

func test_a_request_during_a_crossfade_is_honoured() -> void:
	var mixer := _faded_in(&"a")
	mixer.play(&"b", FADE)
	mixer.advance(FADE * 0.5)
	mixer.play(&"c", FADE)
	mixer.advance(FADE)
	assert_eq(mixer.active_cue_id(), &"c", "the last request wins")
	mixer.advance(FADE)
	assert_almost_eq(mixer.total_power(), 1.0, 0.01, "and the mix settles on it alone")
