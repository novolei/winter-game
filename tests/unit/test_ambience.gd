extends TestCase

## THE VOICE OF THE VALLEY -- GDD section 9's world side.
##
## Section 9 opens with 因为没有 HUD，音频是生存状态的主要读数通道 -- because there
## is no HUD, audio is the primary readout channel for survival state. A minimal
## HUD now carries the five stats; audio still carries everything else, and it is
## the only channel for most of what the player needs to know about the world
## beyond the frame.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE HAS TO BE ABLE TO PROVE WITH ALMOST NO AUDIO ON DISK
## ---------------------------------------------------------------------------
## There are thirteen audio files in the whole project and none of them is a
## wind. So this suite is arranged in two halves, and the split is deliberate:
##
##   THE LAWS are pure and are tested against the real shipped data -- the wind
##   windows, the lead, the geometry, the danger subtraction, the interior
##   acoustic. None of them needs a file, because none of them is about a file.
##
##   THE PLAYBACK is tested against files that DO exist, by pointing a
##   test-built map at `assets/audio/foley` and `assets/audio/ui`. That half
##   exists because of this project's fifth false-PASS: a suite once asserted 44
##   successful `play()` calls while the engine refused every one, because an
##   `AudioStreamPlayer` outside the scene tree cannot play. So every playback
##   claim here asserts `is_playing()` and every player is in the tree.

const DirectorScript := preload("res://src/audio/ambience_director.gd")
const WindSystemScript := preload("res://src/systems/wind_system.gd")

const MAP_PATH := "res://data/audio/ambience.tres"
const WEATHER_DIR := "res://data/weather"

## Files that are actually in this repository, used to prove the playback wiring.
const REAL_LOOP_FOLDER := "res://assets/audio/foley"
const REAL_LOOP_STEM := &"footstep_snow_01"
const REAL_FIRE_STEM := &"footstep_snow_02"
const REAL_CUE_FOLDER := "res://assets/audio/ui"
const REAL_CUE_ID := &"click"

var _map: AmbienceMap = null
var _made: Array[Node] = []


func before_each() -> void:
	_map = ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as AmbienceMap


func after_each() -> void:
	for node in _made:
		if not is_instance_valid(node):
			continue
		if node.is_inside_tree():
			node.get_parent().remove_child(node)
		node.free()
	_made.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## Built, parented and remembered so `after_each` frees it. `Node` is not
## reference counted and a leaked one is a `WARNING: N ObjectDB instances were
## leaked at exit`, which fails the run (binding constraint 2).
func _director(map: AmbienceMap, in_tree := true) -> AmbienceDirector:
	var made: AmbienceDirector = DirectorScript.new()
	made.ask_on_first_frame = false
	made.manage_buses = false
	made.set_map(map)
	_made.append(made)
	if in_tree:
		_root().add_child(made)
	return made


func _profile(id: String) -> WindProfile:
	return ResourceLoader.load("res://data/weather/%s.tres" % id) as WindProfile


func _layer(id: StringName) -> AmbienceLayer:
	return _map.layer(id) if _map != null else null


## `EventBus` is a Node, so a test that makes one owns freeing it.
func _event_bus() -> Node:
	var bus: Node = preload("res://src/core/event_bus.gd").new()
	_made.append(bus)
	return bus


# --- the windows -------------------------------------------------------------

func test_the_map_ships() -> void:
	assert_not_null(_map, "%s must exist -- run tools/generate_ambience.gd" % MAP_PATH)
	if _map == null:
		return
	assert_true(_map.layers.size() >= 4, "the bed needs its layers")


func test_a_layer_is_silent_below_its_entry_rather_than_quiet() -> void:
	var layer := _layer(&"wind_low")
	assert_not_null(layer)
	if layer == null:
		return
	assert_eq(AmbienceLayer.gain_at(layer, 0.0), 0.0)
	assert_eq(AmbienceLayer.gain_at(layer, layer.enters_at), 0.0,
		"the entry is a floor, not a fade -- at it the layer is off")
	assert_eq(AmbienceLayer.gain_at(layer, layer.enters_at - 0.001), 0.0)


func test_a_layer_reaches_full_gain_at_the_top_of_its_window() -> void:
	var layer := _layer(&"wind_mid")
	assert_not_null(layer)
	if layer == null:
		return
	assert_almost_eq(AmbienceLayer.gain_at(layer, layer.full_at), 1.0, 0.0001)
	assert_almost_eq(AmbienceLayer.gain_at(layer, 1.0), 1.0, 0.0001)


## Smoothstep rather than a ramp, so a gust crossing the edge does not step.
func test_the_window_eases_rather_than_steps() -> void:
	var layer := _layer(&"wind_mid")
	assert_not_null(layer)
	if layer == null:
		return
	var middle := (layer.enters_at + layer.full_at) * 0.5
	assert_almost_eq(AmbienceLayer.gain_at(layer, middle), 0.5, 0.02)
	var quarter := lerpf(layer.enters_at, layer.full_at, 0.25)
	assert_true(AmbienceLayer.gain_at(layer, quarter) < 0.25,
		"a smoothstep is below the straight line in its first quarter")


func test_a_layer_with_an_upper_edge_leaves_again() -> void:
	var layer := AmbienceLayer.new()
	layer.enters_at = 0.1
	layer.full_at = 0.2
	layer.leaves_at = 0.5
	layer.gone_at = 0.7
	assert_almost_eq(AmbienceLayer.gain_at(layer, 0.35), 1.0, 0.0001)
	assert_almost_eq(AmbienceLayer.gain_at(layer, 0.6), 0.5, 0.02)
	assert_eq(AmbienceLayer.gain_at(layer, 0.8), 0.0)


func test_pitch_rises_across_the_window() -> void:
	var layer := _layer(&"wind_high")
	assert_not_null(layer)
	if layer == null:
		return
	assert_true(layer.pitch_at_full > layer.pitch_scale,
		"a bed that rises in level but not in pitch reads as the same recording played louder")
	assert_almost_eq(AmbienceLayer.pitch_at(layer, 0.0), layer.pitch_scale, 0.0001)
	assert_almost_eq(AmbienceLayer.pitch_at(layer, 1.0), layer.pitch_at_full, 0.0001)


func test_every_layer_has_a_gap_under_it() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	for layer in _map.layers:
		assert_true(layer.enters_at > 0.0,
			"%s enters at 0, so it is always sounding -- a reading that is always present carries no information" % layer.layer_id)
		assert_true(layer.full_at > layer.enters_at,
			"%s has an inverted window" % layer.layer_id)


# --- the gaps, measured ------------------------------------------------------

## The fraction of `seconds` for which `layer` would be silent under `profile`.
func _silent_fraction(layer: AmbienceLayer, profile: WindProfile, seconds := 1200.0) -> float:
	var step := 0.02
	var steps := int(seconds / step)
	var silent := 0
	for i in range(steps):
		var strength := WindSystemScript.strength_at(profile, float(i) * step)
		if AmbienceLayer.gain_at(layer, strength) <= 0.0:
			silent += 1
	return float(silent) / float(steps)


## 寒流's entire tell is 空气变得极静 and its `.tres` hands the wind system the
## still profile. The audible half of the best warning in the game is the bed
## GOING, and it needs no file at all.
func test_the_bed_is_silent_for_almost_all_of_a_still_night() -> void:
	var layer := _layer(&"wind_low")
	var profile := _profile("wind_still")
	assert_not_null(layer)
	assert_not_null(profile)
	if layer == null or profile == null:
		return
	var silent := _silent_fraction(layer, profile)
	assert_true(silent > 0.90,
		"the still night is only silent %.1f%% of the time -- 寒流's tell is carried by absence and needs the bed to actually go" % (silent * 100.0))


## Absence is a signal. A bed with no silence in it fills the valley and leaves
## nowhere for a footstep, a breath or the wire to be heard.
func test_an_ordinary_valley_day_has_real_gaps_in_it() -> void:
	var layer := _layer(&"wind_low")
	var profile := _profile("wind_valley")
	assert_not_null(layer)
	assert_not_null(profile)
	if layer == null or profile == null:
		return
	var silent := _silent_fraction(layer, profile)
	assert_true(silent > 0.12,
		"only %.1f%% of a valley day is silent -- the gaps are where the footsteps live" % (silent * 100.0))
	assert_true(silent < 0.45,
		"%.1f%% of a valley day is silent -- past this the world reads as dead rather than as quiet" % (silent * 100.0))


func test_a_gale_never_goes_quiet() -> void:
	var layer := _layer(&"wind_low")
	var profile := _profile("wind_gale")
	assert_not_null(layer)
	assert_not_null(profile)
	if layer == null or profile == null:
		return
	assert_eq(_silent_fraction(layer, profile), 0.0,
		"a gale that has gaps in it is not a gale")


## The second voice arrives with the gust the wind system announces, rather than
## at some level nobody else in the game has an opinion about.
func test_the_second_voice_arrives_with_the_gust_the_wind_announces() -> void:
	var layer := _layer(&"wind_mid")
	var profile := _profile("wind_valley")
	assert_not_null(layer)
	assert_not_null(profile)
	if layer == null or profile == null:
		return
	assert_true(layer.enters_at < profile.gust_threshold,
		"wind_mid enters at %.2f but the valley calls a gust at %.2f, so the sound would arrive after the event" % [layer.enters_at, profile.gust_threshold])
	assert_true(layer.enters_at > profile.lull_threshold,
		"wind_mid enters at %.2f, below the valley's own lull threshold of %.2f -- it would be sounding through the lulls" % [layer.enters_at, profile.lull_threshold])


# --- the lead: heard before it is felt ---------------------------------------

class FakeWind extends RefCounted:
	## Its own preload: an inner class cannot reach the outer script's constants.
	const Wind := preload("res://src/systems/wind_system.gd")
	var profile: WindProfile = null
	var at := 0.0
	func strength() -> float:
		return Wind.strength_at(profile, at)
	func strength_at(p, t) -> float:
		return Wind.strength_at(p, t)
	func active_profile():
		return profile
	func elapsed() -> float:
		return at
	func heading_degrees() -> float:
		return Wind.heading_at(profile, at)


## A wind that can say what it is doing NOW and nothing else -- the fallback path.
class BlindWind extends RefCounted:
	var value := 0.0
	func strength() -> float:
		return value


func _fake_wind(profile_id := "wind_valley") -> FakeWind:
	var wind := FakeWind.new()
	wind.profile = _profile(profile_id)
	return wind


## THE CLAIM: the bed plays the wind that has not arrived yet.
##
## `WindSystem`'s model is a pure function of time, so the bed can ask what the
## wind will be doing in `lead_seconds` and play that. Meanwhile the tyre swing
## and the smoke column LAG, because a cue is believed when it arrives late. The
## sound leading and the mass lagging is the whole of "heard before it is felt".
func test_the_bed_plays_the_wind_that_has_not_arrived_yet() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var wind := _fake_wind()
	var director := _director(_map, false)
	director.set_wind_system(wind)
	wind.at = 40.0
	var expected := WindSystemScript.strength_at(wind.profile, 40.0 + _map.lead_seconds)
	assert_almost_eq(director.look_ahead_strength(), expected, 0.0001)


func test_the_lead_is_a_real_lead_and_not_a_rounding_error() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	assert_true(_map.lead_seconds > 0.2,
		"a lead under a fifth of a second is not perceptible as an early warning")
	assert_true(_map.lead_seconds < 1.5,
		"past this the bed stops agreeing with the picture and reads as a mistake")
	# And it survives the smoothing: every second of `bed_response_seconds` is a
	# second given back of the lead.
	assert_true(_map.bed_response_seconds < _map.lead_seconds * 0.5,
		"the gain smoothing (%.2fs) eats the lead (%.2fs)" % [_map.bed_response_seconds, _map.lead_seconds])


## THE CLAIM AS A TIME, which is the only form of it a player can hear.
##
## The bed opens `lead_seconds` BEFORE the wind reaches the level that opens it.
## Measured across every upward crossing in twenty minutes of the shipped valley
## wind rather than at one instant, because a single sample proves nothing about
## a signal with three octaves in it.
##
## Note what a naive version of this test gets wrong, since it was written first
## and failed: "on any locally rising sample the look-ahead is higher than the
## present" is FALSE, and correctly so -- it holds on only 65.8% of them, because
## a wind rising now may have peaked again within the 0.85 s the bed is looking
## across. The bed is not a predictor of the next instant. It is the same signal,
## shifted, and a shift is what "heard before it is felt" actually means.
func test_the_bed_opens_before_the_wind_reaches_the_level_that_opens_it() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var profile := _profile("wind_valley")
	var layer := _layer(&"wind_mid")
	assert_not_null(profile)
	assert_not_null(layer)
	if profile == null or layer == null:
		return
	var wind := _fake_wind()
	var director := _director(_map, false)
	director.set_wind_system(wind)

	var step := 0.01
	var crossings := 0
	var total_lead := 0.0
	var was_open := false
	var closed_at := 0.0
	var bed_open_at := -1.0
	for i in range(120000):
		var t := float(i) * step
		wind.at = t
		var open_now := WindSystemScript.strength_at(profile, t) > layer.enters_at
		var bed_open := AmbienceLayer.gain_at(layer, director.look_ahead_strength()) > 0.0
		if bed_open and bed_open_at < 0.0:
			bed_open_at = t
		if open_now and not was_open:
			# Only crossings with ROOM for the lead in front of them can measure
			# it: where the wind closed less than `lead_seconds` ago, the bed was
			# already open for this crossing before the last one had finished, and
			# the sweep can see only the part after the close. Including those
			# pulls the mean down to 0.815 s and would look like the lead being
			# short when it is the ruler that is.
			if bed_open_at >= 0.0 and t - closed_at > _map.lead_seconds + 0.05:
				crossings += 1
				total_lead += t - bed_open_at
		if not open_now and was_open:
			closed_at = t
			bed_open_at = -1.0
		was_open = open_now
	assert_true(crossings > 20, "the sweep found only %d measurable crossings" % crossings)
	var measured := total_lead / float(maxi(crossings, 1))
	assert_almost_eq(measured, _map.lead_seconds, 0.02,
		"the bed leads the wind by %.3f s across %d crossings, and the map asks for %.3f" % [measured, crossings, _map.lead_seconds])


func test_a_wind_with_no_future_falls_back_to_the_present_rather_than_to_zero() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var wind := BlindWind.new()
	wind.value = 0.42
	var director := _director(_map, false)
	director.set_wind_system(wind)
	assert_almost_eq(director.look_ahead_strength(), 0.42, 0.0001)


func test_no_wind_at_all_is_silence_rather_than_a_crash() -> void:
	var director := _director(_map, false)
	assert_eq(director.look_ahead_strength(), 0.0)
	director.advance(0.1)
	assert_true(director.is_silent())


# --- where the bed sounds from -----------------------------------------------

## `WindProfile.prevailing_degrees` is the direction the wind BLOWS TO, so the
## sound comes from the opposite side.
func test_the_bed_sounds_from_upwind() -> void:
	var at := AmbienceDirector.upwind_of(Vector3.ZERO, 0.0, 10.0)
	assert_almost_eq(at.x, -10.0, 0.0001)
	assert_almost_eq(at.z, 0.0, 0.0001)
	var behind := AmbienceDirector.upwind_of(Vector3.ZERO, 180.0, 10.0)
	assert_almost_eq(behind.x, 10.0, 0.0001)


func test_the_emitter_is_placed_around_the_listener_rather_than_around_the_origin() -> void:
	var listener := Vector3(30.0, 2.0, -12.0)
	var at := AmbienceDirector.upwind_of(listener, 90.0, 8.0)
	assert_almost_eq(at.y, 2.0, 0.0001)
	assert_almost_eq(listener.distance_to(at), 8.0, 0.001)


## 风向突变's tell in GDD section 7 is 雪粒改向、风声移位 -- the snow changes
## direction and THE WIND SOUND MOVES. A positional bed gives that for nothing:
## the emitter swings round the listener as the heading veers, so the second half
## of the shipped tell is audible with no file and no extra system.
func test_the_wind_sound_moves_when_the_quarter_changes() -> void:
	var before := AmbienceDirector.upwind_of(Vector3.ZERO, 20.0, 10.0)
	var after := AmbienceDirector.upwind_of(Vector3.ZERO, 200.0, 10.0)
	assert_true(before.distance_to(after) > 15.0,
		"a 180-degree veer moved the source only %.2f m" % before.distance_to(after))


# --- absence is a signal -----------------------------------------------------

## GDD section 9: 危险靠近时，BGM 抽走高频层，只剩低频. A subtraction, not a sting --
## and specifically a subtraction of a BAND, so what the player hears is the
## world losing its top rather than the mix getting quieter.
func test_danger_takes_the_top_off_and_leaves_the_low() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	# A held strength rather than the gale model, so what is under test is the
	# subtraction and not where wind_gale happens to be at some instant.
	var wind := BlindWind.new()
	wind.value = 0.95
	var director := _director(_map, false)
	director.set_wind_system(wind)
	for i in range(200):
		director.advance(0.05)
	var low_before := director.bed_gain(0)
	var mid_before := director.bed_gain(1)
	assert_true(low_before > 0.5, "a strength of 0.95 is not driving the low bed")
	assert_true(mid_before > 0.5, "a strength of 0.95 is not driving the mid bed")

	director.set_danger(true)
	for i in range(400):
		director.advance(0.05)
	assert_true(director.bed_gain(1) < 0.02,
		"the gust layer is still at %.3f with a threat present" % director.bed_gain(1))
	assert_true(director.bed_gain(2) < 0.02, "the top layer is still sounding")
	assert_almost_eq(director.bed_gain(0), low_before, 0.02,
		"只剩低频 -- the low layer is the one that must NOT leave, or this is a duck rather than a subtraction")


## Section 9 puts this at its cruellest on day 7: 白茫茫什么都看不见，只能听见世界
## 安静下来. A whiteout whose falling snow kept hissing through a bear's approach
## could not do that.
func test_the_falling_snow_goes_quiet_too() -> void:
	var layer := _layer(&"snow_fall")
	assert_not_null(layer)
	if layer == null:
		return
	assert_true(layer.withdraws_near_danger,
		"in a whiteout the snow is most of what is audible; if it stays, day 7's scare cannot happen")


func test_only_the_low_layer_survives_a_threat() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var staying := 0
	for layer in _map.layers:
		if not layer.withdraws_near_danger:
			staying += 1
	assert_eq(staying, 1,
		"只剩低频 -- exactly one layer stays. %d stay, so the world does not go quiet." % staying)


## The bear wandering off is not the same moment as being safe. Snapping the
## world back on the instant the threat clears undoes the scene.
func test_the_world_does_not_come_back_the_moment_the_threat_leaves() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	assert_true(_map.danger_hold_seconds > 1.0, "the hold is what stops the snap-back")
	var wind := BlindWind.new()
	wind.value = 0.95
	var director := _director(_map, false)
	director.set_wind_system(wind)
	director.set_danger(true)
	for i in range(400):
		director.advance(0.05)
	assert_true(director.hush() > 0.95)
	director.set_danger(false)
	# One second later, still held.
	for i in range(20):
		director.advance(0.05)
	assert_true(director.hush() > 0.95,
		"the hush released after one second, so the world snapped back on")
	for i in range(400):
		director.advance(0.05)
	assert_true(director.hush() < 0.1, "and it does have to come back")


# --- inside is a different room ----------------------------------------------

## The four things that move, and the ORDER OF THEIR SIZES. A room that is only
## quieter reads as the mix being turned down, which the player attributes to the
## build rather than to the door.
func test_going_inside_is_an_acoustic_and_not_a_volume() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	assert_true(_map.cutoff_for(1.0) < _map.cutoff_for(0.0) * 0.1,
		"the wall has to actually close: %.0f Hz inside against %.0f Hz outside" % [_map.cutoff_for(1.0), _map.cutoff_for(0.0)])
	assert_true(_map.radius_for(1.0) > _map.radius_for(0.0) * 1.5,
		"the wind has to move OUTSIDE, not just down")
	assert_true(_map.panning_for(1.0) > _map.panning_for(0.0),
		"inside it arrives through a gap, so it localises")
	assert_true(absf(_map.trim_db_for(1.0)) <= 6.0,
		"the trim is %.1f dB, which is doing more work than the acoustic" % _map.trim_db_for(1.0))


func test_the_acoustic_arrives_gradually_rather_than_on_the_frame_the_door_opens() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var director := _director(_map, false)
	director.set_inside(true)
	director.advance(0.05)
	assert_true(director.insideness() > 0.0, "it has to start")
	assert_true(director.insideness() < 0.5,
		"one frame took it %.2f of the way in -- that is a switch, not a threshold" % director.insideness())
	for i in range(200):
		director.advance(0.05)
	assert_true(director.insideness() > 0.98)


## The bus is the one part of this that touches global engine state, so it gets
## its own test rather than being taken on trust.
func test_the_wall_reaches_the_bus() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var director: AmbienceDirector = DirectorScript.new()
	director.ask_on_first_frame = false
	director.manage_buses = true
	_made.append(director)
	_root().add_child(director)
	director.set_map(_map)
	director.advance(0.05)
	var outside := director.cutoff_hz()
	assert_almost_eq(outside, _map.exterior_cutoff_hz, 1.0,
		"outdoors the low-pass has to be out of the way")
	director.set_inside(true)
	for i in range(200):
		director.advance(0.05)
	assert_true(director.cutoff_hz() < _map.interior_cutoff_hz * 1.05,
		"the filter did not follow the crossing: %.0f Hz" % director.cutoff_hz())


func test_the_bus_is_put_back_when_the_director_goes() -> void:
	var before := AudioServer.bus_count
	var director: AmbienceDirector = DirectorScript.new()
	director.ask_on_first_frame = false
	director.manage_buses = true
	# Remembered before anything can fail, so an early assertion cannot leak it.
	_made.append(director)
	_root().add_child(director)
	director.set_map(_map)
	assert_eq(AudioServer.bus_count, before + 1, "the bed's bus was not created")
	_root().remove_child(director)
	director.free()
	assert_eq(AudioServer.bus_count, before,
		"the bus outlived the director, so a suite that builds several leaks one each time")


# --- it asks, as well as listening -------------------------------------------

class FakeReveal extends Node:
	var inside := false
	func is_occupant_inside() -> bool:
		return inside


class FakeFire extends Node3D:
	var lit := true
	func is_lit() -> bool:
		return lit
	func fire_position() -> Vector3:
		return position
	func warmth_at(_point: Vector3) -> float:
		return 0.0


func _reveal(inside: bool) -> FakeReveal:
	var made := FakeReveal.new()
	made.inside = inside
	_made.append(made)
	_root().add_child(made)
	return made


func _fire(at: Vector3, lit := true) -> FakeFire:
	var made := FakeFire.new()
	made.lit = lit
	made.position = at
	_made.append(made)
	_root().add_child(made)
	made.add_to_group(&"fires")
	return made


## A node that only subscribes to a TRANSITION can never learn a state that
## changed before it existed. This project has paid for it twice -- the stove and
## the day/night phase -- so it is a test rather than a comment.
func test_it_learns_it_is_already_indoors_rather_than_waiting_for_a_door() -> void:
	var reveal := _reveal(true)
	var director := _director(_map)
	assert_false(director.is_inside(), "nothing has been asked yet")
	director.ask_the_world()
	assert_true(director.is_inside(),
		"the occupant was already inside and the director never found out")
	assert_true(director.interior_count() >= 1)
	reveal.inside = false


func test_leaving_one_building_while_standing_in_another_stays_inside() -> void:
	var first := _reveal(true)
	var second := _reveal(true)
	var director := _director(_map)
	director.ask_the_world()
	assert_true(director.is_inside())
	first.inside = false
	director.reconsider()
	assert_true(director.is_inside(),
		"one building's exit put the listener outdoors while he was standing in the other")
	second.inside = false
	director.reconsider()
	assert_false(director.is_inside())


func test_it_finds_a_fire_that_was_already_burning() -> void:
	var fire := _fire(Vector3(3.0, 0.0, -2.0))
	var map := _playable_map()
	var director := _director(map)
	director.refresh_fires()
	assert_eq(director.fire_voice_count(), 1,
		"the stove was lit before the director existed and never got a voice")
	fire.lit = false


func test_a_fire_going_out_takes_its_voice_with_it() -> void:
	var fire := _fire(Vector3(1.0, 0.0, 1.0))
	var map := _playable_map()
	var director := _director(map)
	director.refresh_fires()
	assert_eq(director.fire_voice_count(), 1)
	fire.lit = false
	director.refresh_fires()
	assert_eq(director.fire_voice_count(), 0,
		"an unlit stove kept its fire loop, so the room still sounds warm")


func test_the_fire_sounds_from_where_the_fire_is() -> void:
	var fire := _fire(Vector3(6.0, 0.0, -4.0))
	var map := _playable_map()
	var director := _director(map)
	director.refresh_fires()
	var voice: AudioStreamPlayer3D = null
	for child in director.get_children():
		if child.name.begins_with("Fire"):
			voice = child
	assert_not_null(voice, "no fire voice was built")
	if voice == null:
		return
	assert_almost_eq(voice.global_position.distance_to(Vector3(6.0, 0.0, -4.0)), 0.0, 0.001,
		"the fire is a PLACE, not a level")
	fire.lit = false


# --- the weather's audible half ----------------------------------------------

func _shipped_events() -> Array:
	var found: Array = []
	var directory := DirAccess.open(WEATHER_DIR)
	if directory == null:
		return found
	for file in directory.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var loaded = ResourceLoader.load("%s/%s" % [WEATHER_DIR, name])
		if loaded is WeatherEventDefinition:
			found.append(loaded)
	return found


func test_every_shipped_weather_tell_that_names_a_sound_has_a_cue_for_it() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var checked := 0
	for event in _shipped_events():
		if event.tell == null or event.tell.sound == &"":
			continue
		checked += 1
		assert_not_null(_map.cue(event.tell.sound),
			"%s names the sound %s and the ambience map has no cue for it" % [event.id, event.tell.sound])
	assert_true(checked >= 6, "only %d shipped tells name a sound" % checked)


## Binding rule 4, as a property rather than as an intention. Not one of the six
## sound ids appears in any `.gd` file: they are authored in `data/weather/*.tres`
## and resolved by id, so a seventh weather's sound is a `.tres` and a file.
func test_no_gd_file_names_a_weather_sound() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var offenders := PackedStringArray()
	for path in _gd_files_under("res://src"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		# Comment lines stripped first. A `##` line that lists the six ids -- and
		# `ambience_cue.gd` has one, which is how this test first failed -- cannot
		# make a seventh weather need a code change. A string literal can, and is
		# still caught.
		var code := PackedStringArray()
		for line in file.get_as_text().split("
"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		var text := "
".join(code)
		for cue in _map.cues:
			if text.contains(String(cue.cue_id)):
				offenders.append("%s names %s" % [path, cue.cue_id])
	assert_eq(offenders.size(), 0,
		"a weather's sound is hardcoded, so a seventh weather would need a .gd change: %s" % ", ".join(offenders))


func _gd_files_under(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var directory := DirAccess.open(root)
	if directory == null:
		return found
	for name in directory.get_directories():
		found.append_array(_gd_files_under("%s/%s" % [root, name]))
	for name in directory.get_files():
		if name.ends_with(".gd"):
			found.append("%s/%s" % [root, name])
	return found


## The tell's snowfall rate is what gives 冻雨 an audible half at all: its wind
## speed multiplier scales `gale_metres` rather than `strength()`, so the wind
## bed never hears it. The snow layer does.
func test_freezing_rains_tell_lifts_the_snow_out_of_silence() -> void:
	var layer := _layer(&"snow_fall")
	assert_not_null(layer)
	if layer == null:
		return
	# Snowfall's own ambient rate under pale_day.
	assert_eq(AmbienceLayer.gain_at(layer, 0.12), 0.0,
		"a light day already has an audible fall, so 冻雨's tell would be a thickening rather than an arrival")
	var during := AmbienceLayer.gain_at(layer, 0.5)
	assert_true(during > 0.5,
		"冻雨's tell drives the rate to 0.50 and the snow layer only reaches %.2f" % during)


func test_the_snow_layer_hears_the_snow_and_not_the_wind() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var layer := _layer(&"snow_fall")
	assert_not_null(layer)
	if layer == null:
		return
	assert_eq(layer.source, AmbienceLayer.Source.SNOWFALL)
	var wind := BlindWind.new()
	wind.value = 0.95
	var snow := FakeSnow.new()
	snow.rate = 0.0
	var director := _director(_map, false)
	director.set_wind_system(wind)
	director.set_snowfall(snow)
	for i in range(200):
		director.advance(0.05)
	assert_true(director.bed_gain(0) > 0.5, "the wind bed is not being driven at all")
	assert_eq(director.bed_gain(3), 0.0,
		"the snow layer is sounding in a dry gale, so it is reading the wind")
	snow.rate = 0.8
	for i in range(200):
		director.advance(0.05)
	assert_true(director.bed_gain(3) > 0.9, "and it has to follow the snow")


class FakeSnow extends RefCounted:
	var rate := 0.0
	func snowfall_rate() -> float:
		return rate


## 寒流 again, this time end to end: the profile its `.tres` actually hands the
## wind system, driven through the director, has to end in silence.
func test_the_cold_snaps_tell_takes_the_bed_away() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var wind := _fake_wind("wind_valley")
	wind.at = 12.0
	var director := _director(_map, false)
	director.set_wind_system(wind)
	for i in range(200):
		director.advance(0.05)
	# Now the tell lands and the wind becomes the still profile.
	wind.profile = _profile("wind_still")
	var loudest := 0.0
	for i in range(2000):
		wind.at += 0.05
		director.advance(0.05)
		if i > 400:
			loudest = maxf(loudest, director.bed_level())
	assert_true(loudest < 0.10,
		"the bed still reaches %.3f under the still profile -- 空气变得极静 is carried by the bed going" % loudest)


# --- playback, against files that exist --------------------------------------

## A map pointed at audio that is genuinely in this repository. Everything about
## the shipped map is the same except where the files come from, so this proves
## the wiring the shipped map will use the day the wind loops land.
func _playable_map() -> AmbienceMap:
	var map := AmbienceMap.new()
	map.sound_folder = REAL_LOOP_FOLDER
	map.cue_folder = REAL_CUE_FOLDER
	map.fire_stem = REAL_FIRE_STEM
	var layer := AmbienceLayer.new()
	layer.layer_id = REAL_LOOP_STEM
	layer.enters_at = 0.05
	layer.full_at = 0.20
	var layers: Array[AmbienceLayer] = [layer]
	map.layers = layers
	return map


func test_the_folder_is_the_data() -> void:
	var map := _playable_map()
	assert_eq(map.stream_for_layer(map.layers[0]),
		"%s/%s.wav" % [REAL_LOOP_FOLDER, REAL_LOOP_STEM],
		"a layer has to find its file by name, or every new sound needs a .tres regenerated")
	assert_eq(map.stream_for(REAL_CUE_ID), "%s/%s.mp3" % [REAL_CUE_FOLDER, REAL_CUE_ID])
	assert_eq(map.stream_for(&"nothing_by_this_name"), "")


func test_a_row_overrides_the_folder() -> void:
	var map := _playable_map()
	var cue := AmbienceCue.new()
	cue.cue_id = &"borrowed"
	cue.stream_path = "%s/%s.wav" % [REAL_LOOP_FOLDER, REAL_LOOP_STEM]
	var cues: Array[AmbienceCue] = [cue]
	map.cues = cues
	assert_eq(map.stream_for(&"borrowed"), cue.stream_path)


## This project's fifth false-PASS was a suite asserting 44 successful `play()`
## calls while the engine refused every one. `is_playing()`, and in the tree.
func test_a_bed_layer_actually_reaches_the_audio_server() -> void:
	var map := _playable_map()
	var director := _director(map)
	var wind := BlindWind.new()
	wind.value = 0.9
	director.set_wind_system(wind)
	for i in range(20):
		director.advance(0.05)
	assert_true(director.bed_gain(0) > 0.9, "the window is not open")
	var voice := director.voice(0)
	assert_not_null(voice)
	if voice == null:
		return
	assert_true(voice.is_playing(),
		"the bed reports a gain of %.2f and nothing is sounding" % director.bed_gain(0))


func test_a_layer_below_its_window_is_stopped_rather_than_played_silently() -> void:
	var map := _playable_map()
	var director := _director(map)
	var wind := BlindWind.new()
	wind.value = 0.9
	director.set_wind_system(wind)
	for i in range(20):
		director.advance(0.05)
	assert_true(director.voice(0).is_playing())
	wind.value = 0.0
	for i in range(60):
		director.advance(0.05)
	assert_false(director.voice(0).is_playing(),
		"a silent layer left running holds a voice and a stream for nothing")


func test_a_bed_layer_is_made_to_loop_whatever_its_import_said() -> void:
	var map := _playable_map()
	var director := _director(map)
	var voice := director.voice(0)
	assert_not_null(voice)
	if voice == null:
		return
	assert_not_null(voice.stream)
	if voice.stream == null:
		return
	var wav := voice.stream as AudioStreamWAV
	assert_not_null(wav, "the test asset is a wav")
	if wav == null:
		return
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD,
		"a bed that stops thirty seconds in is the most audible mistake this system could make")
	assert_true(wav.loop_end > 0)
	# And the shared copy is untouched -- briefing trap 6.
	var shared := ResourceLoader.load("%s/%s.wav" % [REAL_LOOP_FOLDER, REAL_LOOP_STEM]) as AudioStreamWAV
	assert_not_null(shared)
	if shared == null:
		return
	assert_eq(shared.loop_mode, AudioStreamWAV.LOOP_DISABLED,
		"the footstep now loops, because the bed set a flag on the instance everybody shares")


## Measured in the live scene: over thirty seconds of the shipped valley wind the
## low bed crosses its own entry eight times. A `play()` with no argument would
## restart the recording at its first sample every one of those, so the player
## would hear the same two hundred milliseconds of wind eight times in half a
## minute -- which is the fastest way to make a bed sound like a bed.
func test_a_layer_that_comes_back_resumes_rather_than_restarting() -> void:
	var map := _playable_map()
	var director := _director(map)
	var wind := BlindWind.new()
	wind.value = 0.9
	director.set_wind_system(wind)
	for i in range(20):
		director.advance(0.05)
	assert_true(director.voice(0).is_playing())
	wind.value = 0.0
	for i in range(60):
		director.advance(0.05)
	assert_false(director.voice(0).is_playing())
	# ...and the recording kept running behind the silence.
	var during := director.resume_position(0)
	assert_true(during > 0.0,
		"the layer would come back at its first sample, which is the same attack every time")
	director.advance(0.05)
	# Moved, not necessarily forward in the file: the test asset is 0.6 s long, so
	# the clock wraps. What is under test is that it RUNS.
	assert_true(absf(director.resume_position(0) - during) > 0.0001,
		"the air stopped while nobody was listening to it")
	var length: float = director.voice(0).stream.get_length()
	assert_true(director.resume_position(0) >= 0.0 and director.resume_position(0) < length,
		"the resume point (%.3f) is outside the recording (%.3f s)" % [director.resume_position(0), length])
	wind.value = 0.9
	director.advance(0.05)
	assert_true(director.voice(0).is_playing())
	assert_true(director.voice(0).get_playback_position() > 0.0,
		"it came back at the top of the file")


func test_the_tell_event_plays_the_cue_its_own_tres_named() -> void:
	var map := _playable_map()
	var director := _director(map)
	assert_true(director.play_cue(REAL_CUE_ID))
	assert_eq(director.cue_voice_count(), 1)
	var voice: AudioStreamPlayer3D = null
	for child in director.get_children():
		if child.name.begins_with("Cue"):
			voice = child
	assert_not_null(voice)
	if voice == null:
		return
	assert_true(voice.is_playing(), "play_cue said yes and nothing is sounding")


func test_a_cue_with_no_file_refuses_rather_than_pretending() -> void:
	var map := _playable_map()
	var director := _director(map)
	assert_false(director.play_cue(&"weather_tell_blizzard"),
		"there is no blizzard audio in this repository yet and saying otherwise hides that")
	assert_false(director.play_cue(&""))


func test_a_director_outside_the_tree_refuses_rather_than_lying() -> void:
	var map := _playable_map()
	var director := _director(map, false)
	assert_false(director.play_cue(REAL_CUE_ID),
		"an AudioStreamPlayer cannot play outside the tree, and saying it did is the fifth false-PASS")


func test_the_shipped_map_is_silent_today_and_says_so() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	# Not an assertion that the files are missing -- an assertion that the
	# mechanism does not lie about them. Whichever is true, the map's answer and
	# the disk have to agree.
	for layer in _map.layers:
		var path := _map.stream_for_layer(layer)
		if path == "":
			continue
		assert_true(ResourceLoader.exists(path),
			"the map resolved %s to %s, which is not there" % [layer.layer_id, path])
	for cue in _map.cues:
		var path := _map.stream_for(cue.cue_id)
		if path == "":
			continue
		assert_true(ResourceLoader.exists(path),
			"the map resolved %s to %s, which is not there" % [cue.cue_id, path])


# --- wiring ------------------------------------------------------------------

## THE REGRESSION TEST FOR A DEFECT THE UNIT TESTS COULD NOT SEE.
##
## `WindSystem._collect()` sweeps the whole tree and adopts every node answering
## `set_wind` or `set_wind_strength` as a wind CONSUMER, then drives it with
## `set_wind(velocity())` -- a Vector3 -- every frame. The first version of the
## director called its wind INJECTOR `set_wind()`, so the wind system overwrote
## the injected system with a vector on frame one, `is_instance_valid()` went
## false for it, and `look_ahead_strength()` returned 0.0 for the rest of the
## run. Silently. The whole bed never sounded.
##
## The unit tests all passed, because they inject by hand and there is no
## `WindSystem` within a mile of them. It took printing what the director had
## actually resolved inside the real scene. This test is the guard, and it uses
## the real sweep rather than a list of forbidden names.
func test_the_wind_system_does_not_mistake_the_director_for_a_consumer() -> void:
	var holder := Node.new()
	_made.append(holder)
	var director: AmbienceDirector = DirectorScript.new()
	director.ask_on_first_frame = false
	director.manage_buses = false
	holder.add_child(director)
	var wind = WindSystemScript.new()
	_made.append(wind)
	wind.refresh_consumers(holder)
	assert_eq(wind.consumer_count(), 0,
		"the wind system adopted the ambience director as a consumer, so it will overwrite whatever the director keeps in the property its set_wind() writes")



func test_it_subscribes_to_the_events_it_needs_and_lets_go_again() -> void:
	var bus := _event_bus()
	var director := _director(_map, false)
	director.set_event_bus(bus)
	assert_true(director.has_event_bus())
	for event in [
		AmbienceDirector.EVENT_TELL_STARTED,
		AmbienceDirector.EVENT_THREAT_DETECTED,
		AmbienceDirector.EVENT_THREAT_LOST,
		AmbienceDirector.EVENT_INTERIOR_ENTERED,
		AmbienceDirector.EVENT_INTERIOR_EXITED,
	]:
		assert_eq(bus.subscriber_count(event), 1, "not subscribed to %s" % event)
	director.detach()
	for event in [AmbienceDirector.EVENT_TELL_STARTED, AmbienceDirector.EVENT_THREAT_DETECTED]:
		assert_eq(bus.subscriber_count(event), 0, "still subscribed to %s after detach" % event)


func test_a_threat_event_hushes_the_world() -> void:
	var bus := _event_bus()
	var director := _director(_map, false)
	director.set_event_bus(bus)
	bus.emit_event(AmbienceDirector.EVENT_THREAT_DETECTED, {})
	assert_true(director.in_danger())
	bus.emit_event(AmbienceDirector.EVENT_THREAT_LOST, {})
	assert_false(director.in_danger())


func test_a_tell_event_carrying_no_sound_is_a_no_op_rather_than_an_error() -> void:
	var map := _playable_map()
	var director := _director(map)
	var bus := _event_bus()
	director.set_event_bus(bus)
	bus.emit_event(AmbienceDirector.EVENT_TELL_STARTED, {"id": &"x", "sound": &""})
	assert_eq(director.cue_voice_count(), 0)
	bus.emit_event(AmbienceDirector.EVENT_TELL_STARTED, {"id": &"x", "sound": REAL_CUE_ID})
	assert_eq(director.cue_voice_count(), 1)


func test_disabled_means_silent_rather_than_quiet() -> void:
	var map := _playable_map()
	var director := _director(map)
	var wind := BlindWind.new()
	wind.value = 0.9
	director.set_wind_system(wind)
	for i in range(20):
		director.advance(0.05)
	assert_true(director.voice(0).is_playing())
	director.enabled = false
	director.advance(0.05)
	assert_false(director.voice(0).is_playing())
	assert_false(director.play_cue(REAL_CUE_ID))


func test_a_missing_map_leaves_it_inert_rather_than_crashing() -> void:
	var director: AmbienceDirector = DirectorScript.new()
	director.ask_on_first_frame = false
	director.manage_buses = false
	# Set BEFORE it enters the tree, or `_ready()` loads the shipped map and the
	# test measures that instead.
	director.map_path = "res://data/audio/does_not_exist.tres"
	_made.append(director)
	_root().add_child(director)
	assert_eq(director.load_map("res://data/audio/does_not_exist.tres"), 0)
	director.advance(0.1)
	assert_eq(director.voice_count(), 0)
	assert_true(director.is_silent())


# --- the bed files on disk ---------------------------------------------------
#
# Five loops were cut from the owner's takes by `tools/build_ambience_loops.py`,
# which verifies the join at build time. These are the gates on everything that
# can go wrong AFTER that, silently, without anybody re-running the builder.

func _bed_streams() -> Dictionary:
	var found := {}
	if _map == null:
		return found
	for layer in _map.layers:
		var path := _map.stream_for_layer(layer)
		if path == "":
			continue
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		if stream != null:
			found[layer.layer_id] = stream
	return found


## THE FAILURE THIS PREVENTS IS SILENT AND SLOW. A `.import` file regenerates
## with `edit/loop_mode` at its default -- which is "Detect From WAV", and these
## carry no loop marker -- and the bed then stops a few seconds into a run and
## never comes back. Nothing errors; the valley simply goes quiet and stays
## quiet, and the player has no reason to think the wind was supposed to return.
##
## `AmbienceDirector._make_it_loop()` forces it at load as well, so this is the
## second of two guards. It is worth having both: the runtime forcing is what
## makes a newly dropped file work at all, and this is what stops the shipped
## ones drifting.
func test_every_bed_layer_is_imported_as_a_forward_loop() -> void:
	var streams := _bed_streams()
	assert_true(streams.size() >= 4,
		"only %d bed layers have audio on disk -- run tools/build_ambience_loops.py" % streams.size())
	for id in streams:
		var stream: AudioStreamWAV = streams[id]
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
			"%s is imported with loop_mode %d; a bed that stops mid-run is the loudest silence in the game" % [id, stream.loop_mode])
		assert_eq(stream.loop_begin, 0, "%s does not loop from its start" % id)
		assert_true(stream.loop_end > 0, "%s has no loop end" % id)


## Uncompressed, and NOT this project's usual QOA.
##
## QOA is lossy and block-based and its encoder does not know the signal wraps,
## so the one sample junction the whole file exists to protect is the one place
## the codec is free to guess. The whole set is 3.3 MB as PCM.
func test_every_bed_layer_ships_uncompressed_and_mono() -> void:
	var streams := _bed_streams()
	if streams.is_empty():
		assert_true(false, "no bed audio on disk")
		return
	for id in streams:
		var stream: AudioStreamWAV = streams[id]
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS,
			"%s is not 16-bit PCM (format %d) -- a lossy codec is free to guess at the loop join" % [id, stream.format])
		assert_false(stream.stereo,
			"%s is stereo; a positional emitter's own panning is what carries the wind's direction" % id)


## THE JOIN, ASSERTED FROM THE SHIPPED BYTES rather than trusted from the
## builder's own report.
##
## The test is not "is the step small" -- inside noise, adjacent samples differ
## constantly. It is whether the step ACROSS THE WRAP is ORDINARY, measured
## against the file's own distribution of adjacent-sample steps. That is the same
## instrument `build_ambience_loops.py` uses, applied to what actually landed, so
## a file replaced by hand with one that clicks fails here.
func test_no_bed_layer_clicks_where_it_wraps() -> void:
	var streams := _bed_streams()
	if streams.is_empty():
		assert_true(false, "no bed audio on disk")
		return
	for id in streams:
		var stream: AudioStreamWAV = streams[id]
		var data := stream.data
		var frames := data.size() / 2
		if frames < 4096:
			continue
		# The file's own motion, sampled across the whole length rather than at
		# one place: a wind's step distribution is not the same in a lull as in
		# a gust, and the wrap has to be ordinary against all of it.
		var steps: Array[int] = []
		var stride := maxi(1, frames / 20000)
		for i in range(1, frames - 1, stride):
			steps.append(absi(data.decode_s16(i * 2) - data.decode_s16((i - 1) * 2)))
		steps.sort()
		var p999: int = steps[mini(steps.size() - 1, int(steps.size() * 0.999))]
		var wrap := absi(data.decode_s16(0) - data.decode_s16((frames - 1) * 2))
		assert_true(wrap <= p999,
			"%s steps %d across its wrap against a p99.9 of %d in its own body -- that is a click once per cycle" % [id, wrap, p999])


## The mix is derived rather than heard, so the ORDER of the authored gains is
## the part a test can hold. A hiss louder than the body of the air is the one
## arrangement that would be wrong in every weather.
func test_the_hiss_never_outweighs_the_body_of_the_air() -> void:
	assert_not_null(_map)
	if _map == null:
		return
	var low := _layer(&"wind_low")
	var high := _layer(&"wind_high")
	var snow := _layer(&"snow_fall")
	assert_not_null(low)
	assert_not_null(high)
	assert_not_null(snow)
	if low == null or high == null or snow == null:
		return
	assert_true(high.gain_db < low.gain_db - 3.0,
		"wind_high is authored at %.1f dB against wind_low's %.1f -- the top would sit over the body" % [high.gain_db, low.gain_db])
	assert_true(snow.gain_db < low.gain_db,
		"the falling snow is authored over the wind")
