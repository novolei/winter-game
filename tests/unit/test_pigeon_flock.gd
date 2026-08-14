extends TestCase

## The pigeons: the same wires as the crows, the same burst, and -- the one
## behavioural difference the brief asked for -- still there after dark.
##
## Same shape as `test_crow_flock.gd`, and deliberately so: everything runs with
## no SceneTree, because `advance()` is public and every collaborator is
## injected. What is asserted here is only what DIFFERS from the parent; the
## flock's own machinery is the crow's and is covered by the crow's file. A
## second copy of those eighteen tests would be a second copy to keep in step.

const FlockScript := preload("res://src/entities/wildlife/pigeon_flock.gd")
const CrowFlockScript := preload("res://src/entities/wildlife/crow_flock.gd")
const PigeonScript := preload("res://src/entities/wildlife/pigeon.gd")
const PIGEON_SPECIES: BirdSpecies = preload("res://data/wildlife/pigeon.tres")
const PRESENTATION_PATH := "res://data/wildlife/pigeon_presentation.tres"
const CALL_AUDIO_PATH := "res://assets/audio/wildlife/pigeon/pigeon_call.mp3"
const DEPARTURE_AUDIO_PATH := "res://assets/audio/wildlife/pigeon/pigeon_departure_wings.ogg"

const AN_EAVE := [
	{"at": Vector3(0.0, 3.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 1.5), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 3.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 4.5), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 6.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 3.0, 7.5), "facing": Vector3(1.0, 0.0, 0.0)},
]

const FRAME := 1.0 / 60.0

var _flock: PigeonFlock
var _bus: BusStand
var _clock: ClockStand
var _watched: Node3D


## EventBus's whole contract, in the three calls this uses. RefCounted, so
## nothing here has to be freed (briefing constraint 2).
class BusStand extends RefCounted:
	var published: Array = []
	var subscriptions: Dictionary = {}

	func subscribe(event: StringName, callback: Callable) -> void:
		if not subscriptions.has(event):
			subscriptions[event] = []
		var list: Array = subscriptions[event]
		if not list.has(callback):
			list.append(callback)

	func unsubscribe(event: StringName, callback: Callable) -> void:
		if subscriptions.has(event):
			(subscriptions[event] as Array).erase(callback)

	func emit_event(event: StringName, payload: Variant = null) -> void:
		published.append({"event": event, "payload": payload})
		for callback in (subscriptions.get(event, []) as Array).duplicate():
			(callback as Callable).call(payload)

	func of(event: StringName) -> Array:
		var found: Array = []
		for entry in published:
			if entry["event"] == event:
				found.append(entry)
		return found


## WorldClock in the one respect a flock reads it.
class ClockStand extends RefCounted:
	var night := false

	func is_night() -> bool:
		return night


func before_each() -> void:
	_bus = BusStand.new()
	_clock = ClockStand.new()
	_watched = Node3D.new()
	_watched.position = Vector3(0.0, 0.0, 200.0)
	_flock = FlockScript.new()
	_flock.random_seed = 20260812
	_flock.first_arrival_seconds = 1.0
	_flock.set_event_bus(_bus)
	_flock.set_world_clock(_clock)
	_flock.set_watched(_watched)
	_flock.set_perches(AN_EAVE)


func after_each() -> void:
	# Node is not reference-counted; the flock owns every bird it hatched, so
	# freeing it frees them.
	_flock.free()
	_watched.free()


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_flock.advance(FRAME)
		left -= FRAME


func _birds() -> Array:
	var found: Array = []
	for child in _flock.get_children():
		if child is Bird:
			found.append(child)
	return found


func _ground_pigeon(landing: Vector3, wait_seconds := 30.0) -> Pigeon:
	var pigeon: Pigeon = PigeonScript.new()
	assert_true(
		pigeon.begin_ground_visit(
			landing,
			landing + Vector3(0.0, 2.0, 5.0),
			_watched,
			wait_seconds
		),
		"the ground visit could not begin"
	)
	# The flight and landing curve has its own focused coverage. These tests begin
	# at touchdown so they can measure the ground state without spending twenty
	# seconds getting there.
	pigeon.perch_on(landing, Vector3.BACK)
	pigeon.advance(FRAME)
	return pigeon


func _ground_state_value(label: StringName) -> int:
	var script := ResourceLoader.load("res://src/entities/wildlife/pigeon.gd") as Script
	var constants: Dictionary = script.get_script_constant_map() if script != null else {}
	var states: Dictionary = constants.get("GroundState", {})
	return int(states.get(label, -1))


func _receive_food_accepts_a_target(pigeon: Pigeon) -> bool:
	for method: Dictionary in pigeon.get_method_list():
		if StringName(method.get("name", &"")) == &"receive_food":
			return (method.get("args", []) as Array).size() >= 1
	return false


# --- what it builds -----------------------------------------------------------


## A `Pigeon` is a `Bird` carrying `data/wildlife/pigeon.tres`, and so is a
## `Crow` -- which is why this has to be asserted rather than assumed. A
## `_new_bird()` that had lost its override would hand back plain birds wearing
## the pigeon species, every OTHER test in this file would still pass, and
## nothing would report it. It is the same assertion that guarded the five
## overrides this class used to need.
func test_the_flock_hatches_pigeons_and_not_crows() -> void:
	_flock.arrive_now()
	var birds := _birds()
	assert_true(birds.size() > 0, "no bird arrived at all")
	var wrong := 0
	for bird in birds:
		if not (bird is Pigeon):
			wrong += 1
	assert_eq(wrong, 0, "%d of %d birds are plain crows" % [wrong, birds.size()])


func test_the_pigeon_presentation_defines_three_independent_plumages() -> void:
	assert_true(
		ResourceLoader.exists(PRESENTATION_PATH),
		"the pigeon presentation data has not been generated"
	)
	if not ResourceLoader.exists(PRESENTATION_PATH):
		return
	var presentation = load(PRESENTATION_PATH)
	var tones: Array[Color] = presentation.plumage_tones
	assert_eq(tones.size(), Pigeon.PLUMAGE_COUNT, "the presentation does not define all three plumages")
	var seen: Array[Color] = []
	for tone in tones:
		assert_false(seen.has(tone), "two named pigeon plumages use the same colour")
		seen.append(tone)
	var prompt_green: Color = presentation.feed_prompt_color
	assert_true(prompt_green.g > prompt_green.r and prompt_green.g > prompt_green.b,
		"the feeding affordance no longer carries the requested theme green")
	assert_true(prompt_green.a > 0.99, "the authored ring colour is already faded in data")
	assert_eq(presentation.feed_prompt_color, Color("#51FF2D"),
		"the E ring drifted from the approved bright theme green")
	assert_eq(presentation.feed_guide_color, Color("#667890"),
		"the straight leader drifted from its quiet medium grey")
	var bible: ColorBible = load(BirdSpecies.PALETTE_PATH)
	var outside := 0
	for tone in tones:
		if not bible.contains(tone):
			outside += 1
	assert_true(outside > 0, "the pigeon palette is still confined to the world's twelve colours")


func test_the_two_supplied_pigeon_sounds_are_shipped_and_non_looping() -> void:
	assert_true(FileAccess.file_exists(CALL_AUDIO_PATH), "the supplied pigeon call was not copied into the project")
	assert_true(
		FileAccess.file_exists(DEPARTURE_AUDIO_PATH),
		"the supplied departure wing sound was not copied into the project"
	)
	if not FileAccess.file_exists(CALL_AUDIO_PATH) or not FileAccess.file_exists(DEPARTURE_AUDIO_PATH):
		return
	var call := load(CALL_AUDIO_PATH) as AudioStream
	var wings := load(DEPARTURE_AUDIO_PATH) as AudioStream
	assert_not_null(call, "the pigeon call does not import as audio")
	assert_not_null(wings, "the departure wings do not import as audio")
	assert_true(call.get_length() > 0.0, "the pigeon call has no duration")
	assert_true(wings.get_length() > 0.0, "the departure wings have no duration")


func test_a_hatched_flock_randomises_its_plumage() -> void:
	_flock.attach()
	_flock.arrive_now()
	var seen := {}
	for bird in _birds():
		var pigeon := bird as Pigeon
		assert_not_null(pigeon, "a non-pigeon entered the pigeon flock")
		if pigeon != null:
			seen[pigeon.plumage_variant()] = true
	assert_true(seen.size() >= 2, "the seeded flock drew only one plumage, so the visual variation is not observable")


func test_a_friendly_pigeon_can_land_near_the_player_to_wait_for_food() -> void:
	_flock.attach()
	_flock.friendly_wait_min_seconds = 40.0
	_flock.friendly_wait_max_seconds = 40.0
	_watched.position = Vector3(12.0, 0.0, -8.0)
	assert_true(_flock.try_friendly_visit(true), "the forced friendly visit was refused")
	assert_eq(_flock.ground_visitor_count(), 1, "the friendly arrival is not tracked as a ground visitor")
	var pigeon := _birds()[0] as Pigeon
	var landing := pigeon.target_perch()
	var gap := Vector2(landing.x - _watched.position.x, landing.z - _watched.position.z).length()
	assert_true(
		gap >= _flock.friendly_radius_min_m and gap <= _flock.friendly_radius_max_m,
		"the pigeon chose %.2f m, outside the authored friendly ring" % gap
	)
	assert_eq(
		_bus.of(PigeonFlock.EVENT_WAITING_FOR_FOOD).size(), 0,
		"the pigeon announced food interaction while it was still airborne"
	)
	_run(20.0)
	assert_true(pigeon.is_waiting_for_food(), "the pigeon never completed its ground landing")
	assert_eq(
		_bus.of(PigeonFlock.EVENT_WAITING_FOR_FOOD).size(), 1,
		"the rest of the game was not told the landed pigeon is waiting for food"
	)
	assert_true(pigeon.ground_call_count() >= 2, "the landed pigeon did not produce its multi-call greeting")
	var prints := _bus.of(PigeonFlock.EVENT_FOOTPRINT)
	assert_true(not prints.is_empty(), "the walking pigeon left no small ground marks")
	if not prints.is_empty():
		var payload: Dictionary = prints[0]["payload"]
		assert_eq(payload.get("subject"), &"pigeon", "the mark lost the bird that made it")
		assert_true(
			float(payload.get("lifetime_seconds", 99.0)) <= 6.0,
			"a pigeon mark outlives the brief's fast wind-snow erasure"
		)
	assert_eq(_flock.offer_food(pigeon.where(), 1.0), 1, "food beside the waiting pigeon was ignored")
	assert_eq(
		_bus.of(PigeonFlock.EVENT_FED).size(), 0,
		"feeding completed before the pigeon played its peck"
	)
	_run(PIGEON_SPECIES.length_of(&"peck") + FRAME * 2.0)
	assert_eq(_bus.of(PigeonFlock.EVENT_FED).size(), 1, "the completed meal did not publish its decoupled event")


func test_a_ground_pigeon_wanders_around_its_landing_and_not_around_the_player() -> void:
	_watched.position = Vector3.ZERO
	var landing := Vector3(4.0, 0.0, 0.0)
	var pigeon := _ground_pigeon(landing, 60.0)
	# Moving the player sideways must not drag the pigeon's patrol centre with
	# him. This remains outside the flee radius throughout the observation.
	_watched.position = Vector3(0.0, 0.0, 2.0)
	var farthest := 0.0
	for _frame in range(8 * 60):
		pigeon.advance(FRAME)
		farthest = maxf(farthest, pigeon.where().distance_to(landing))
	assert_true(
		farthest <= 0.75,
		"the pigeon wandered %.2f m from its landing, so it is still orbiting the player" % farthest
	)
	pigeon.free()


func test_a_player_inside_the_ground_flee_radius_preempts_every_other_ground_action() -> void:
	_watched.position = Vector3.ZERO
	var landing := Vector3(4.0, 0.0, 0.0)
	var pigeon := _ground_pigeon(landing, 60.0)
	assert_true(pigeon.is_waiting_for_food(), "the pigeon was not settled before the approach")
	_watched.position = landing + Vector3(1.70, 0.0, 0.0)
	pigeon.advance(FRAME)
	assert_false(pigeon.is_waiting_for_food(), "a player 1.70 m away did not frighten the pigeon")
	assert_true(pigeon.state() != Bird.State.PERCHED, "the frightened pigeon stayed on the ground")
	assert_eq(pigeon.departure_sound_count(), 1, "one close approach scheduled the wing sound more than once")
	pigeon.free()


func test_a_ground_visitor_does_not_make_distant_wire_pigeons_scatter() -> void:
	_flock.attach()
	_flock.friendly_wait_min_seconds = 60.0
	_flock.friendly_wait_max_seconds = 60.0
	_watched.position = Vector3(12.0, 0.0, -8.0)
	assert_true(_flock.try_friendly_visit(true), "the ground visitor could not be created")
	_run(20.0)
	var visitor: Pigeon = _birds()[0] as Pigeon
	assert_true(visitor.is_waiting_for_food(), "the ground visitor did not land")
	assert_true(_flock.land_now() > 0, "the distant wire flock did not land")
	var wire_before := _flock.perched_count()
	_watched.position = visitor.where() + Vector3(1.70, 0.0, 0.0)
	_flock.advance(FRAME)
	assert_eq(
		_flock.perched_count(), wire_before,
		"approaching a ground visitor also frightened %d distant wire pigeons" % wire_before
	)
	assert_eq(
		_bus.of(CrowFlock.EVENT_SCATTERED).size(), 0,
		"the individual ground escape was misreported as a flock scatter"
	)


func test_food_is_walked_to_and_only_completes_after_the_real_peck_take() -> void:
	_watched.position = Vector3.ZERO
	var landing := Vector3(4.0, 0.0, 0.0)
	var pigeon := _ground_pigeon(landing, 60.0)
	var required_methods: Array[StringName] = [
		&"ground_state", &"ground_anchor", &"ground_position", &"food_target", &"meal_count",
	]
	for method in required_methods:
		assert_true(pigeon.has_method(method), "the pigeon exposes no %s getter" % method)
	assert_true(pigeon.has_signal(&"meal_completed"), "the pigeon has no meal_completed signal")
	var accepts_target := _receive_food_accepts_a_target(pigeon)
	assert_true(accepts_target, "receive_food cannot name where the crumbs landed")
	if not accepts_target or not pigeon.has_signal(&"meal_completed"):
		pigeon.free()
		return
	for method in required_methods:
		if not pigeon.has_method(method):
			pigeon.free()
			return

	var completed: Array[Vector3] = []
	pigeon.connect(&"meal_completed", func(at: Vector3) -> void: completed.append(at))
	var crumbs := landing + Vector3(1.10, 0.0, 0.0)
	pigeon.call(&"receive_food", crumbs)
	assert_eq(
		int(pigeon.call(&"ground_state")), _ground_state_value(&"SEEKING_FOOD"),
		"food beside the pigeon started eating before it walked there"
	)
	assert_true(
		(pigeon.call(&"food_target") as Vector3).distance_to(crumbs) < 0.001,
		"the food target is not where the crumbs landed"
	)

	var seek_left := 6.0
	while seek_left > 0.0 \
			and int(pigeon.call(&"ground_state")) != _ground_state_value(&"EATING"):
		pigeon.advance(FRAME)
		seek_left -= FRAME
	assert_eq(
		int(pigeon.call(&"ground_state")), _ground_state_value(&"EATING"),
		"the pigeon never reached the crumbs"
	)
	assert_true(completed.is_empty(), "the meal completed on arrival, before the peck played")
	assert_true(
		(pigeon.call(&"ground_position") as Vector3).distance_to(crumbs) <= 0.25,
		"the pigeon began pecking %.2f m away from the crumbs" % (
			pigeon.call(&"ground_position") as Vector3).distance_to(crumbs)
	)
	pigeon.advance(0.22)
	assert_true(float(pigeon.call(&"feeding_lean")) > 0.95,
		"the body stayed upright while the head pecked at ground food")
	assert_true(absf(float(pigeon.call(&"feeding_body_pitch_degrees"))) >= 28.0,
		"the feeding body lean is too small to bring the breast and head toward the crumbs")

	var peck_seconds := PIGEON_SPECIES.length_of(&"peck")
	var almost_done := maxf(peck_seconds - 0.22 - FRAME * 2.0, 0.0)
	var elapsed := 0.22
	while elapsed < almost_done:
		pigeon.advance(FRAME)
		elapsed += FRAME
	assert_true(completed.is_empty(), "the meal completed before the %.3f s peck take" % peck_seconds)
	while completed.is_empty() and elapsed < peck_seconds + 0.25:
		pigeon.advance(FRAME)
		elapsed += FRAME
	assert_eq(completed.size(), 1, "one meal emitted %d completion signals" % completed.size())
	if not completed.is_empty():
		assert_true(completed[0].distance_to(crumbs) < 0.001, "the meal completed at the wrong position")
	assert_eq(int(pigeon.call(&"meal_count")), 1, "one finished meal was counted more than once")
	assert_eq(
		int(pigeon.call(&"ground_state")), _ground_state_value(&"WANDERING"),
		"the pigeon did not return to wandering after it ate"
	)
	pigeon.free()


func test_a_player_approach_interrupts_the_walk_to_food() -> void:
	_watched.position = Vector3.ZERO
	var landing := Vector3(4.0, 0.0, 0.0)
	var pigeon := _ground_pigeon(landing, 60.0)
	var accepts_target := _receive_food_accepts_a_target(pigeon)
	assert_true(accepts_target, "receive_food cannot name where the crumbs landed")
	if not accepts_target:
		pigeon.free()
		return
	pigeon.call(&"receive_food", landing + Vector3(1.0, 0.0, 0.0))
	_watched.position = pigeon.where() + Vector3(0.0, 0.0, 1.70)
	pigeon.advance(FRAME)
	assert_true(pigeon.state() != Bird.State.PERCHED, "seeking food made the pigeon ignore the player")
	assert_eq(pigeon.departure_sound_count(), 1, "the interrupted meal played no departure wings")
	pigeon.free()


## This uses real AudioStreamPlayer3D nodes under the live test tree. Counters
## alone would prove the schedule and still allow `play()` never to reach audio.
func test_ground_calls_and_sudden_departure_play_positional_audio() -> void:
	var pigeon := Pigeon.new()
	pigeon.vanish_distance_m = 1000.0
	Engine.get_main_loop().root.add_child(pigeon)
	var landing := Vector3(0.0, 0.0, 0.0)
	# Safe interaction distance: placing the watched player on the bird itself now
	# correctly exercises the flee rule instead of the audio schedule.
	_watched.position = landing + Vector3(3.0, 0.0, 0.0)
	assert_true(
		pigeon.begin_ground_visit(landing, Vector3(0.0, 2.0, 5.0), _watched, 4.5, null, 3),
		"the ground visit could not begin"
	)
	# The preceding friendly-visit test owns the real approach and touchdown.
	# This test isolates the audio edge by beginning at the instant the feet have
	# reached the chosen ground perch; otherwise Bird's inbound timeout, normally
	# supervised by the flock, can make a standalone node leave before it calls.
	pigeon.perch_on(landing, Vector3.BACK)
	var heard_call := false
	var heard_wings := false
	# The authored arrival wheels and flares before touching down; the timer is
	# deliberately long enough to observe that real approach plus three complete
	# one-second calls and the eventual unscripted departure.
	var left := 35.0
	while left > 0.0 and not heard_wings:
		pigeon.advance(FRAME)
		var call := pigeon.call_voice()
		var wings := pigeon.departure_voice()
		heard_call = heard_call or (call != null and call.playing)
		heard_wings = heard_wings or (wings != null and wings.playing)
		left -= FRAME
	assert_true(heard_call, "the landed pigeon's AudioStreamPlayer3D never started")
	assert_true(heard_wings, "the sudden departure's AudioStreamPlayer3D never started")
	assert_true(pigeon.ground_call_count() >= 2, "the pigeon left without multiple calls")
	assert_eq(pigeon.departure_sound_count(), 1, "one departure scheduled more than one wing sound")
	Engine.get_main_loop().root.remove_child(pigeon)
	pigeon.free()


func test_a_flock_of_pigeons_is_bigger_than_a_flock_of_crows() -> void:
	var crows: CrowFlock = CrowFlockScript.new()
	assert_true(
		_flock.most > crows.most or _flock.fewest > crows.fewest,
		"pigeons flock in %d..%d against the crows' %d..%d, so there is nothing to tell them apart at a glance" % [
			_flock.fewest, _flock.most, crows.fewest, crows.most]
	)
	assert_true(
		_flock.flush_radius_m < crows.flush_radius_m,
		"a pigeon is used to people and should let him closer than a crow does"
	)
	crows.free()


# --- day AND night, which is the whole difference -----------------------------


## The crows' rule is "daylight only". This one's is not, and the difference has
## to survive both halves of the day/night wiring -- the subscription AND the
## question asked on attach.
func test_a_flock_arrives_after_dark() -> void:
	_clock.night = true
	_flock.attach()
	_run(6.0)
	assert_true(_birds().size() > 0, "the wire is empty at night; a rock dove roosts on the ledge it feeds from")


## The half a subscription cannot do. A flock born into night that only listened
## would sit at its member's default until the first sunrise -- which is up to a
## whole phase away, and reads as a tuning choice rather than as a defect.
func test_it_asks_the_clock_what_time_it_is_rather_than_waiting_to_be_told() -> void:
	_clock.night = true
	_flock.attach()
	assert_true(_flock.is_dark(), "the flock was born at night and does not know it")
	_clock.night = false
	_flock.attach()
	assert_false(_flock.is_dark(), "the flock was born in daylight and thinks it is night")


## And the parent's own gate stays open, which is the mechanism.
##
## `CrowFlock._night` means one thing in the parent's logic: the wires must be
## empty. For this bird that is never true, so the flag is held at false and the
## real phase is kept as `is_dark()`. Asserting both is what stops a later edit
## from "tidying" the two back into one.
func test_the_parents_empty_the_wires_flag_is_never_set() -> void:
	_clock.night = true
	_flock.attach()
	assert_true(_flock.is_dark(), "the clock says night and the flock disagrees")
	assert_false(_flock.is_night(), "the parent's flag is set, which blocks every arrival until sunrise")


func test_nightfall_does_not_flush_the_wire() -> void:
	_flock.attach()
	_flock.land_now()
	var before := _flock.perched_count()
	assert_true(before > 0, "nothing landed, so there is nothing to flush")
	_bus.emit_event(&"clock.night_started", null)
	_run(0.5)
	assert_eq(
		_flock.perched_count(), before,
		"nightfall put %d of %d pigeons up; only the crows go home at dusk" % [
			before - _flock.perched_count(), before]
	)
	assert_eq(_bus.of(CrowFlock.EVENT_SCATTERED).size(), 0, "nightfall published a scatter")


## The same event, the same cause, unchanged from the parent -- because a Wave 5
## listener wanting "something is out there" wants one subscription and does not
## care which bird raised it.
func test_the_man_still_puts_them_up_and_it_is_still_published() -> void:
	_flock.attach()
	_flock.land_now()
	var landed := _flock.perched_count()
	assert_true(landed > 0, "nothing landed")
	_watched.position = Vector3(0.0, 0.0, 3.0)
	_run(0.5)
	var scattered := _bus.of(CrowFlock.EVENT_SCATTERED)
	assert_eq(scattered.size(), 1, "the burst was published %d times" % scattered.size())
	if scattered.is_empty():
		return
	var payload: Dictionary = scattered[0]["payload"]
	assert_eq(payload["cause"], CrowFlock.CAUSE_PLAYER, "the cause was %s" % payload["cause"])
	assert_eq(payload["count"], landed, "%d birds went up out of %d" % [payload["count"], landed])


## And it happens at night as well, which the crows can never do -- a crow flock
## is empty after dark, so this event only ever had a daylight source.
func test_they_can_be_put_up_after_dark() -> void:
	_clock.night = true
	_flock.attach()
	_flock.land_now()
	assert_true(_flock.perched_count() > 0, "nothing landed after dark")
	_watched.position = Vector3(0.0, 0.0, 3.0)
	_run(0.5)
	assert_eq(_bus.of(CrowFlock.EVENT_SCATTERED).size(), 1, "a night startle published nothing")


# --- and it will not land on somebody -----------------------------------------


func test_a_perch_somebody_is_standing_on_is_not_offered() -> void:
	var free := FlockScript.free_of(AN_EAVE, [Vector3(0.0, 3.0, 1.5)])
	assert_eq(free.size(), AN_EAVE.size() - 1, "%d perches came back out of %d" % [free.size(), AN_EAVE.size()])
	for perch in free:
		assert_true(
			(perch["at"] as Vector3).distance_to(Vector3(0.0, 3.0, 1.5)) > PigeonFlock.OCCUPIED_WITHIN_M,
			"the occupied perch is still on offer"
		)


## The neighbours must survive. A radius wide enough to clear a whole wire would
## empty the valley the moment one bird landed on it.
func test_a_bird_on_one_perch_does_not_close_the_ones_beside_it() -> void:
	var free := FlockScript.free_of(AN_EAVE, [Vector3(0.0, 3.0, 0.0)])
	assert_eq(free.size(), AN_EAVE.size() - 1, "one bird closed %d perches" % [AN_EAVE.size() - free.size()])


func test_an_empty_sky_leaves_every_perch_on_offer() -> void:
	assert_eq(FlockScript.free_of(AN_EAVE, []).size(), AN_EAVE.size(), "perches went missing with nothing standing on them")


## The filter is on the flock's own door, so a flock that has been handed
## explicit perches still gets them. Otherwise a capture that placed a bird
## exactly where it wanted one would find the perch refused.
func test_the_filter_leaves_explicit_perches_alone_outside_a_tree() -> void:
	assert_eq(
		_flock.available_perches().size(), AN_EAVE.size(),
		"the perches handed to the flock came back short"
	)
