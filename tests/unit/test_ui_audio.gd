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
	# IN THE TREE, because an AudioStreamPlayer genuinely cannot play outside one.
	# A bare .new() here exercised every branch except the one that makes a sound,
	# and the engine's refusal only showed up as ERROR lines in the console --
	# where the tests, which were all passing, could not see it. Briefing trap 1
	# permits reaching for the live tree when the wiring IS the thing under test;
	# what it requires is that whatever was added is removed and freed.
	_root().add_child(_audio)
	_audio.load_map(MAP_PATH)

func after_each() -> void:
	if _audio != null:
		_root().remove_child(_audio)
		_audio.free()
		_audio = null

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

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

## Every cue section 8 names that an asset now exists for.
func test_every_shipped_cue_is_present() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for id in [&"ui.move", &"ui.confirm", &"ui.back", &"ui.bloom",
			&"ui.ripple", &"ui.threshold", &"ui.critical", &"ui.nightfall"]:
		assert_not_null(_map.cue(id), "section 8 requires a %s cue" % id)

## Section 8: 阈值濒危 is 心跳 + 极高频耳鸣. It is the SAME heartbeat -- one body,
## one heart -- and the tinnitus is what is added. So the difference between the
## two states is the LAYER, not the pitch.
func test_the_critical_threshold_is_the_same_heartbeat_plus_the_tinnitus() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var ordinary := _map.cue(&"ui.threshold")
	var critical := _map.cue(&"ui.critical")
	assert_not_null(ordinary)
	assert_not_null(critical)
	if ordinary == null or critical == null:
		return
	assert_eq(critical.stream_path, ordinary.stream_path, "one heartbeat, two states")
	assert_almost_eq(critical.pitch_scale, ordinary.pitch_scale, 0.0001,
		"same heart; what makes this one worse is the layer, not the pitch")
	assert_eq(critical.layer_cue_id, &"ui.tinnitus", "the critical threshold must layer the tinnitus")
	assert_eq(ordinary.layer_cue_id, &"", "the ordinary threshold must NOT -- that is the whole distinction")
	assert_true(critical.gain_db > ordinary.gain_db,
		"and it is the louder one -- it is the last warning the player gets")

## Section 8 names -34 dB outright. The tinnitus is meant to sit at the edge of
## hearing: the player should notice the silence around it before the tone.
func test_the_tinnitus_is_the_quietest_thing_in_the_map() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var tinnitus := _map.cue(&"ui.tinnitus")
	assert_not_null(tinnitus)
	if tinnitus == null:
		return
	assert_almost_eq(tinnitus.gain_db, -34.0, 0.01)
	for cue in _map.cues:
		if cue.cue_id == &"ui.tinnitus":
			continue
		assert_true(cue.gain_db > tinnitus.gain_db,
			"%s is at or below the tinnitus's %.1f dB" % [cue.cue_id, tinnitus.gain_db])

## A layer that layered something else could ring for ever. One level deep makes
## that unrepresentable rather than merely unlikely, so the shipped data has to
## honour it too.
func test_no_layer_carries_a_layer_of_its_own() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for cue in _map.cues:
		if cue.layer_cue_id == &"":
			continue
		var layer := _map.cue(cue.layer_cue_id)
		assert_not_null(layer, "%s layers %s, which does not exist" % [cue.cue_id, cue.layer_cue_id])
		if layer == null:
			continue
		assert_eq(layer.layer_cue_id, &"",
			"%s layers %s, which layers %s in turn" % [cue.cue_id, layer.cue_id, layer.layer_cue_id])

## Playing a layered cue must actually put TWO voices to work, or the layer is
## configuration nobody hears.
func test_a_layered_cue_sounds_on_two_voices() -> void:
	_audio.play(&"ui.threshold")
	var single := _audio.last_player()
	_audio.play(&"ui.critical")
	var after := _audio.last_player()
	assert_true(single != after, "the layered cue used the same single voice")
	assert_true(after.is_playing(), "the layer is not actually playing")

## GDD section 3 makes NIGHTFALL = GO HOME a literal deadline, and section 5.4
## calls it the most important single piece of information in the game. If it is
## not the loudest thing the interface says, the mix is arguing with the design.
func test_nightfall_is_the_loudest_thing_the_interface_says() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var nightfall := _map.cue(&"ui.nightfall")
	assert_not_null(nightfall)
	if nightfall == null:
		return
	for cue in _map.cues:
		if cue.cue_id == &"ui.nightfall":
			continue
		assert_true(nightfall.gain_db > cue.gain_db,
			"%s is at %.1f dB, at or above nightfall's %.1f" % [cue.cue_id, cue.gain_db, nightfall.gain_db])

## Rule 6 puts these sounds INSIDE the wind rather than over it, so nothing in
## the map may sit at unity gain -- there is no headroom above the world.
func test_nothing_in_the_map_plays_at_full_level() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for cue in _map.cues:
		assert_true(cue.gain_db < 0.0,
			"%s plays at %.1f dB, which is over the world rather than under it"
				% [cue.cue_id, cue.gain_db])

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

## play() RETURNING TRUE IS NOT THE SAME AS A SOUND HAVING STARTED, and until
## this assertion existed nothing in the file could tell the two apart.
##
## AudioStreamPlayer refuses to play from outside the scene tree. It refuses
## loudly to the console and quietly to the caller: UIAudio's own bookkeeping has
## all succeeded by then, so play() still reports true. Every assertion above
## therefore measured the return value of a method that had played nothing.
##
## This is the one that checks the AudioServer instead of the return value.
func test_a_played_cue_actually_reaches_the_audio_server() -> void:
	assert_true(_audio.play(&"ui.confirm"))
	var player := _audio.last_player()
	assert_not_null(player)
	if player == null:
		return
	assert_true(player.is_playing(),
		"play() reported success but the AudioServer is not playing anything")

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
