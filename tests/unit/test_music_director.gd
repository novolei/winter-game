extends TestCase

## The director: turning what the game reports into which situation is in
## force, and when a cue is allowed to start.
##
## Built with .new() and driven through advance(), the same shape as
## test_world_clock.gd. _ready() therefore never runs, so no AudioStreamPlayer
## is ever created and nothing is decoded -- these tests are about the
## decisions, not about whether a file makes a sound.
##
## The director extends Node, which is not reference-counted, so it is freed in
## after_each() or the suite reports leaked ObjectDB instances.

const DirectorScript := preload("res://src/audio/music_director.gd")
const SelectorScript := preload("res://src/audio/music_selection.gd")
const MapScript := preload("res://src/definitions/music_map.gd")
const CueScript := preload("res://src/definitions/music_cue.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

const SEED := 776
const ENTRY_GAP := 5.0
const GAP := 100.0
const DAWN := 20.0
const DUSK := 15.0
const CROSSFADE := 6.0
const SILENCE_FADE := 3.0
const HOLD := 45.0

var _director = null
var _bus = null

func after_each() -> void:
	if _director != null:
		_director.free()
		_director = null
	if _bus != null:
		_bus.free()
		_bus = null

func _cue(id: StringName, situations: Array) -> MusicCue:
	var cue: MusicCue = CueScript.new()
	cue.cue_id = id
	cue.stream_path = ""
	# The gap is derived from the track length, so every cue here is GAP long
	# and the map asks for a half share: a GAP-second track at a half share is
	# followed by a GAP-second gap.
	cue.duration_seconds = GAP
	var list: Array[StringName] = []
	for s in situations:
		list.append(s)
	cue.situations = list
	return cue

## Gaps are pinned (a zero-width window, entry_chance 1.0) so a test can say
## exactly when a cue is due. The shipped map randomises all of them.
func _map() -> MusicMap:
	var map: MusicMap = MapScript.new()
	var cues: Array[MusicCue] = [
		_cue(&"dawn_only", [&"dawn"]),
		_cue(&"shared", [&"day", &"dusk"]),
		_cue(&"night_only", [&"night"]),
		_cue(&"by_the_fire", [&"shelter"]),
		_cue(&"win", [&"ending_rescue"]),
	]
	map.cues = cues
	var silent: Array[StringName] = [&"danger"]
	map.silent_situations = silent
	var oneshot: Array[StringName] = [&"ending_rescue"]
	map.oneshot_situations = oneshot
	map.base_volume_db = -8.0
	map.crossfade_seconds = CROSSFADE
	map.silence_fade_seconds = SILENCE_FADE
	map.gap_cycle_music_share = 0.5
	map.gap_window_seconds = 0.0
	map.entry_gap_min_seconds = ENTRY_GAP
	map.entry_gap_max_seconds = ENTRY_GAP
	map.entry_chance = 1.0
	map.post_silence_hold_seconds = HOLD
	map.dawn_seconds = DAWN
	map.dusk_seconds = DUSK
	return map

func _build():
	_director = DirectorScript.new()
	_director.set_map(_map())
	_director.set_selector(SelectorScript.new(SEED))
	return _director

## A cue up and at full gain, 11.1 s into a day -- still inside the dawn
## window, which is why the tests below expect dawn to be what resumes.
func _playing_music():
	var director = _build()
	director.on_day_started(1)
	director.advance(ENTRY_GAP + 0.1)
	director.advance(CROSSFADE)
	return director

# --- situation resolution -------------------------------------------------

func test_the_director_starts_silent() -> void:
	var director = _build()
	assert_eq(director.current_situation(), &"", "nothing has happened yet")
	assert_true(director.is_silent(), "so there is nothing to hear")

func test_day_started_opens_on_dawn_then_settles_into_daylight() -> void:
	var director = _build()
	director.on_day_started(1)
	assert_eq(director.current_situation(), &"dawn", "a day opens at dawn")
	director.advance(DAWN - 1.0)
	assert_eq(director.current_situation(), &"dawn", "still dawn a second before the window closes")
	director.advance(2.0)
	assert_eq(director.current_situation(), &"day", "and ordinary daylight after it")

func test_night_started_opens_on_nightfall_then_settles_into_deep_night() -> void:
	var director = _build()
	director.on_night_started(1)
	assert_eq(director.current_situation(), &"dusk", "night opens at nightfall")
	director.advance(DUSK - 1.0)
	assert_eq(director.current_situation(), &"dusk", "still nightfall a second early")
	director.advance(2.0)
	assert_eq(director.current_situation(), &"night", "and deep night after it")

func test_shelter_outranks_the_time_of_day() -> void:
	var director = _build()
	director.on_day_started(1)
	director.set_in_shelter(true)
	assert_eq(director.current_situation(), &"shelter", "indoors is what matters, not the hour")
	director.set_in_shelter(false)
	assert_eq(director.current_situation(), &"dawn", "and the hour resumes on the way out")

func test_danger_outranks_shelter() -> void:
	var director = _build()
	director.on_day_started(1)
	director.set_in_shelter(true)
	director.set_danger(true)
	assert_eq(director.current_situation(), &"danger", "a threat is the only thing that matters")

func test_an_ending_outranks_everything() -> void:
	var director = _build()
	director.on_day_started(1)
	director.set_danger(true)
	director.set_ending(&"rescue")
	assert_eq(director.current_situation(), &"ending_rescue", "the run is over; nothing outranks that")

# --- when a cue is allowed to start ---------------------------------------

func test_a_cue_waits_for_its_gap() -> void:
	var director = _build()
	director.on_day_started(1)
	assert_true(director.is_silent(), "a situation beginning is not itself a cue")
	director.advance(ENTRY_GAP - 0.5)
	assert_true(director.is_silent(), "still inside the gap")
	director.advance(1.0)
	assert_false(director.is_silent(), "and the cue starts once the gap runs out")
	assert_eq(director.active_cue_id(), &"dawn_only", "the cue cast for dawn")

func test_silence_returns_between_cues() -> void:
	## The brief is explicit that quiet between tracks is the design, not a
	## gap in it. A track ending must leave real silence, for a long time.
	var director = _playing_music()
	var cue: StringName = director.active_cue_id()
	director.notify_cue_finished(cue)
	assert_true(director.is_silent(), "the track ended, so there is nothing playing")
	director.advance(GAP - 1.0)
	assert_true(director.is_silent(), "and it stays quiet for the whole gap")
	director.advance(2.0)
	assert_false(director.is_silent(), "then the next cue arrives")

func test_the_situation_changing_crossfades_rather_than_waiting() -> void:
	var director = _build()
	director.on_day_started(1)
	director.advance(ENTRY_GAP + 0.1)
	director.advance(CROSSFADE)
	assert_eq(director.active_cue_id(), &"dawn_only", "dawn's cue is up")
	director.advance(DAWN)
	assert_eq(director.current_situation(), &"day", "the dawn window has closed")
	assert_eq(director.active_cue_id(), &"shared", "so daylight's cue takes over at once")

func test_a_cue_cast_for_both_situations_is_left_alone() -> void:
	## `shared` stands in for the shipped long_walk, cast for day and dusk.
	## Changing tracks when the same one still fits would be churn the player
	## hears for no reason.
	var director = _build()
	director.on_day_started(1)
	director.advance(DAWN + ENTRY_GAP + 0.1)
	director.advance(CROSSFADE)
	assert_eq(director.active_cue_id(), &"shared", "daylight's cue is up")
	director.on_night_started(1)
	assert_eq(director.current_situation(), &"dusk", "nightfall has begun")
	assert_eq(director.active_cue_id(), &"shared", "and the cue that covers it too is kept")

# --- the important one: danger is silence ---------------------------------

func test_danger_fades_the_music_out() -> void:
	var director = _playing_music()
	assert_false(director.is_silent(), "music is up before the threat arrives")
	director.set_danger(true)
	director.advance(0.1)
	assert_false(director.is_silent(), "it leaves gradually -- a fade, not a stinger cut")
	director.advance(SILENCE_FADE)
	assert_true(director.is_silent(), "and then there is nothing")
	assert_eq(director.active_cue_id(), &"", "with no cue held in reserve")

func test_danger_is_a_state_and_not_a_pause() -> void:
	## GDD section 9 builds its fear out of absence. Music creeping back while
	## the threat is still there would take the whole idea away, so this walks
	## fifteen minutes of danger -- several times any gap in the shipped map.
	var director = _playing_music()
	director.set_danger(true)
	director.advance(SILENCE_FADE)
	for i in 90:
		director.advance(10.0)
		if not director.is_silent():
			assert_true(false, "music returned %d seconds into an unbroken threat" % ((i + 1) * 10))
			return
	assert_true(director.is_silent(), "fifteen minutes of threat, fifteen minutes of silence")
	assert_eq(director.current_situation(), &"danger", "and the situation never moved off danger")

func test_danger_is_silent_even_when_it_begins_in_silence() -> void:
	## Entering danger from a gap must not leave the pending cue scheduled to
	## arrive mid-threat.
	var director = _build()
	director.on_day_started(1)
	director.set_danger(true)
	director.advance(600.0)
	assert_true(director.is_silent(), "no cue may fire while a threat is present")

func test_the_quiet_outlasts_the_threat() -> void:
	## Snapping back to music the instant the bear wanders off would undo the
	## scene. Leaving a silent situation adds post_silence_hold_seconds on top
	## of a full gap, rather than using the short entry gap a situation change
	## normally gets.
	var director = _playing_music()
	director.set_danger(true)
	director.advance(SILENCE_FADE)
	director.set_danger(false)
	assert_eq(director.current_situation(), &"dawn", "the hour resumes as the situation")
	director.advance(ENTRY_GAP + 1.0)
	assert_true(director.is_silent(), "but not as music -- the entry gap must not apply here")
	director.advance(GAP)
	assert_true(director.is_silent(), "the hold is on top of a full gap")
	director.advance(HOLD)
	assert_false(director.is_silent(), "and only then does the score come back")

func test_a_nightfall_in_the_middle_of_that_quiet_does_not_end_it() -> void:
	## Found by simulating whole runs, not by reading: a dawn or a nightfall
	## landing inside the quiet that follows a threat used to replace it with
	## the short entry gap, and 44.6% of threat silences were being cut short
	## that way -- some to under 80 s, which is shorter than an ordinary gap.
	##
	## The entry gap exists so that a situation beginning gets music soon. The
	## one silence in this game that carries information is not a situation
	## beginning, and it is not for the clock to sound the all-clear on it.
	var director = _playing_music()
	director.set_danger(true)
	director.advance(SILENCE_FADE)
	director.set_danger(false)
	# GAP + HOLD is now armed. Nightfall arrives halfway through it.
	director.advance(GAP * 0.5)
	director.on_night_started(1)
	assert_eq(director.current_situation(), &"dusk", "the hour still moves on")
	director.advance(ENTRY_GAP + 1.0)
	assert_true(director.is_silent(),
		"the entry gap must not fire into a threat's quiet")
	director.advance(GAP + HOLD - GAP * 0.5 - ENTRY_GAP - 1.0 - 1.0)
	assert_true(director.is_silent(), "which runs its own full length regardless")
	director.advance(2.0)
	assert_false(director.is_silent(), "and only then does music come back")

func test_a_situation_beginning_never_makes_the_wait_longer() -> void:
	## The other half of the same finding. A nightfall landing near the END of
	## an ordinary gap used to throw away the seconds still owed and start a
	## fresh 5-40 s entry gap, which POSTPONES music rather than bringing it
	## forward -- the opposite of what that branch is for.
	##
	## It also lets an ordinary silence run to gap_max PLUS entry_gap_max, past
	## the longest gap the density derivation ever draws, which is the length a
	## threat's silence has to stay clear of to remain readable.
	var director = _playing_music()
	director.notify_cue_finished(director.active_cue_id())
	assert_true(director.is_silent(), "the track ended, so a full gap is running")
	director.advance(GAP - 2.0)
	assert_true(director.is_silent(), "two seconds of it left")
	director.on_night_started(1)
	director.advance(2.5)
	assert_false(director.is_silent(),
		"nightfall may bring music forward, never push it back: two seconds were"
		+ " owed and the entry gap is %f s" % ENTRY_GAP)

# --- endings ---------------------------------------------------------------

func test_an_ending_plays_immediately() -> void:
	var director = _build()
	director.on_day_started(1)
	director.set_ending(&"rescue")
	assert_eq(director.active_cue_id(), &"win", "an ending does not queue behind a gap")

func test_an_ending_accepts_either_spelling() -> void:
	var director = _build()
	director.set_ending(&"ending_rescue")
	assert_eq(director.current_situation(), &"ending_rescue", "the full situation id works too")

func test_nothing_follows_an_ending() -> void:
	var director = _build()
	director.on_day_started(1)
	director.set_ending(&"rescue")
	director.advance(CROSSFADE)
	director.notify_cue_finished(&"win")
	director.advance(3600.0)
	assert_true(director.is_silent(), "the run is over; the credits do not loop")

func test_the_run_finishing_takes_the_music_away() -> void:
	var director = _playing_music()
	director.on_run_finished(null)
	director.advance(SILENCE_FADE)
	assert_true(director.is_silent(), "the clock ran out")
	director.advance(1200.0)
	assert_true(director.is_silent(), "and nothing starts up behind it")

# --- wiring ----------------------------------------------------------------

func test_the_event_bus_drives_the_director() -> void:
	## The director subscribes; it never reaches into WorldClock or a threat.
	## This is the whole of its coupling to the rest of the game.
	_bus = EventBusScript.new()
	var director = DirectorScript.new()
	_director = director
	director.set_map(_map())
	director.set_selector(SelectorScript.new(SEED))
	director.set_event_bus(_bus)

	_bus.emit_event(&"clock.day_started", 1)
	assert_eq(director.current_situation(), &"dawn", "clock.day_started should open dawn")

	_bus.emit_event(&"threat.detected_player", null)
	assert_eq(director.current_situation(), &"danger", "a threat should silence the music")

	_bus.emit_event(&"threat.lost_player", null)
	assert_eq(director.current_situation(), &"dawn", "and losing it should restore the hour")

	_bus.emit_event(&"clock.night_started", 1)
	assert_eq(director.current_situation(), &"dusk", "clock.night_started should open nightfall")

	_bus.emit_event(&"game.ended", &"rescue")
	assert_eq(director.current_situation(), &"ending_rescue", "game.ended should call the ending")

func test_replacing_the_bus_drops_the_old_subscriptions() -> void:
	_bus = EventBusScript.new()
	var director = DirectorScript.new()
	_director = director
	director.set_map(_map())
	director.set_selector(SelectorScript.new(SEED))
	director.set_event_bus(_bus)
	var subscribed: int = _bus.subscriber_count(&"clock.day_started")
	assert_eq(subscribed, 1, "the director should be listening once")
	director.set_event_bus(null)
	assert_eq(_bus.subscriber_count(&"clock.day_started"), 0,
		"and should let go rather than leaving a dangling callable behind")

func test_the_default_volume_comes_from_the_map_and_can_be_overridden() -> void:
	## "Exposed so it can be tuned by ear without touching code" -- the map is
	## editable in the inspector, and this setter is what an options slider
	## would move.
	var director = _build()
	assert_almost_eq(director.music_volume_db(), -8.0, 0.0001, "the map's base level is the default")
	director.set_music_volume_db(-24.0)
	assert_almost_eq(director.music_volume_db(), -24.0, 0.0001, "and it can be turned down at runtime")

func test_a_director_with_no_map_is_inert_rather_than_broken() -> void:
	## Autoloads load before their data is guaranteed present. Advancing must
	## not error.
	_director = DirectorScript.new()
	_director.on_day_started(1)
	_director.advance(1000.0)
	assert_true(_director.is_silent(), "no map, no music, no crash")
	assert_eq(_director.active_cue_id(), &"", "and nothing claimed")
