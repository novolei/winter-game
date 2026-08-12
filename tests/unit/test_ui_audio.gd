extends TestCase

## The interface's own voice -- UI design document section 8's pairing table.
##
## Rule 6 says every 呵 has a sound, which makes audio part of the interface
## specification rather than dressing. This file is the gate on the two halves
## that can go wrong quietly: a cue pointing at a file that is not there, and a
## player pool that swallows a click because it was still busy with the last one.
##
## ---------------------------------------------------------------------------
## WHY THE POOL IS ROUND-ROBIN AND NOT "FIND A FREE PLAYER"
## ---------------------------------------------------------------------------
## The supplied click.mp3 is 0.813 s long and the audible part of a UI click is a
## few tens of milliseconds; the rest is tail and silence. A pool that looked for
## a player with is_playing() false would count those voices as busy for most of
## a second each, and a player moving quickly down a menu would find every voice
## occupied by silence and hear nothing. Cutting off an inaudible tail costs
## nothing; dropping the click costs the whole feel of the menu.

const UIAudioScript := preload("res://src/ui/ui_audio.gd")
const MAP_PATH := "res://data/audio/ui_sounds.tres"

var _audio: UIAudio = null
var _map: UISoundMap

func before_each() -> void:
	_map = ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UISoundMap
	_audio = UIAudioScript.new()
	_audio.load_map(MAP_PATH)

func after_each() -> void:
	if _audio != null:
		_audio.free()
		_audio = null

# --- the map ----------------------------------------------------------------

func test_the_map_ships() -> void:
	assert_not_null(_map, "%s must exist -- run tools/generate_ui_sounds.gd" % MAP_PATH)

## A cue whose file is missing plays nothing and says nothing. Silence is
## indistinguishable from "this action has no sound yet", so it has to fail here.
func test_every_cue_points_at_a_file_that_exists() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	assert_true(_map.cues.size() > 0, "the map is empty")
	for cue in _map.cues:
		assert_true(ResourceLoader.exists(cue.stream_path),
			"cue %s points at %s, which is not in the project" % [cue.cue_id, cue.stream_path])

## Section 8 names these three, and they are the three the shipped assets cover.
func test_the_three_menu_cues_are_all_present() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for id in [&"ui.move", &"ui.confirm", &"ui.back"]:
		assert_not_null(_map.cue(id), "section 8 requires a %s cue" % id)

func test_cue_ids_are_unique() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var seen := {}
	for cue in _map.cues:
		assert_false(seen.has(cue.cue_id), "cue %s is declared twice" % cue.cue_id)
		seen[cue.cue_id] = true

## Section 8: "菜单返回 -- 同上，降 3 个半音". Three semitones down is a pitch ratio
## of 2^(-3/12). Asserted as a NUMBER because "sounds a bit lower" is not a spec,
## and because back and confirm share one file -- the pitch is the only thing
## telling the player which one happened.
func test_back_is_the_confirm_sound_three_semitones_down() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var confirm := _map.cue(&"ui.confirm")
	var back := _map.cue(&"ui.back")
	assert_not_null(confirm)
	assert_not_null(back)
	if confirm == null or back == null:
		return
	assert_eq(back.stream_path, confirm.stream_path, "back is the confirm sound, re-pitched")
	assert_almost_eq(back.pitch_scale, confirm.pitch_scale * pow(2.0, -3.0 / 12.0), 0.001)

## Rule 6's sounds sit under the world, not over it. A menu move at 0 dB would
## be louder than the wind it is supposed to be heard inside.
func test_the_move_cue_is_quieter_than_the_confirm() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	assert_true(_map.cue(&"ui.move").gain_db < _map.cue(&"ui.confirm").gain_db,
		"moving the selection must be lighter than committing to it")

# --- playing ----------------------------------------------------------------

func test_it_loads_every_cue_in_the_map() -> void:
	assert_eq(_audio.cue_count(), _map.cues.size())

func test_playing_a_known_cue_reports_success() -> void:
	assert_true(_audio.play(&"ui.confirm"))

## A typo must not crash and must not be silently indistinguishable from a cue
## that played. It returns false so a caller -- or a test -- can tell.
func test_playing_an_unknown_cue_is_a_refusal_rather_than_a_crash() -> void:
	assert_false(_audio.play(&"ui.no_such_sound"))
	assert_false(_audio.play(&""))

func test_a_played_cue_carries_its_authored_gain_and_pitch() -> void:
	var cue := _map.cue(&"ui.back")
	_audio.play(&"ui.back")
	var player := _audio.last_player()
	assert_not_null(player)
	if player == null:
		return
	assert_almost_eq(player.volume_db, cue.gain_db, 0.001)
	assert_almost_eq(player.pitch_scale, cue.pitch_scale, 0.001)

## The pool must never refuse a click because a previous one has not finished.
## Twice the pool size in a row, and every one of them has to be accepted.
func test_rapid_clicks_are_never_dropped() -> void:
	var rounds: int = _audio.pool_size() * 2
	for i in range(rounds):
		assert_true(_audio.play(&"ui.move"), "click %d of %d was dropped" % [i + 1, rounds])

## Round-robin: consecutive plays land on different players, so a click is never
## cut off by the very next one while it is still audible.
func test_consecutive_clicks_land_on_different_players() -> void:
	_audio.play(&"ui.move")
	var first := _audio.last_player()
	_audio.play(&"ui.move")
	var second := _audio.last_player()
	assert_true(first != second, "the second click reused the first click's player")

func test_the_pool_wraps_around_rather_than_growing() -> void:
	var size: int = _audio.pool_size()
	for i in range(size * 3):
		_audio.play(&"ui.move")
	assert_eq(_audio.pool_size(), size, "the pool grew instead of wrapping")

# --- failure behaviour ------------------------------------------------------

func test_a_missing_map_leaves_it_inert_rather_than_crashing() -> void:
	var empty = UIAudioScript.new()
	var loaded: int = empty.load_map("res://data/audio/there_is_no_such_map.tres")
	assert_eq(loaded, 0)
	assert_false(empty.play(&"ui.confirm"))
	empty.free()
