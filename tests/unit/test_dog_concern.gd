extends TestCase

## The dog notices that something is wrong with you.
##
## Every test here drives `advance()` by hand rather than waiting for a frame,
## and none of them touch the live autoloads: a `DogConcern` that reached for
## `/root/SurvivalSystem` would inherit whatever state the tests before it left
## in the singleton, and would leave its own subscriptions in the shared bus for
## every test after it.

const ConcernScript := preload("res://src/entities/wildlife/dog_concern.gd")

const STATS_DIRECTORY := "res://data/stats"
const LAYOUT_PATH := "res://data/ui/vital_layout.tres"

var _concern: DogConcern = null
var _host: Node3D = null
var _survival: _Model = null
var _bus: _Bus = null
var _heard: Array = []


func before_each() -> void:
	_heard = []
	_survival = _Model.new()
	_bus = _Bus.new(self)
	_host = Node3D.new()
	_host.name = "Host"
	_root().add_child(_host)
	_concern = ConcernScript.new()
	# Both injected BEFORE add_child, so `_ready()` finds them already set and
	# never falls through to the autoloads.
	_concern.set_event_bus(_bus)
	_concern.set_survival_system(_survival)
	_host.add_child(_concern)


func after_each() -> void:
	_concern = null
	if _host != null:
		_root().remove_child(_host)
		# Frees the concern node and its readout with it. Node is not
		# reference-counted; leaving one is "N ObjectDB instances were leaked".
		_host.free()
		_host = null
	_survival = null
	_bus = null


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## A stand-in for SurvivalSystem: the four calls `DogConcern` actually makes.
class _Model:
	extends RefCounted
	var values := {
		&"core_temperature": 1.0,
		&"hunger": 1.0,
		&"thirst": 1.0,
		&"fatigue": 1.0,
		&"frostbite_hands": 1.0,
		&"frostbite_feet": 1.0,
	}

	func stat_ids() -> Array[StringName]:
		var out: Array[StringName] = []
		for id in values:
			out.append(id)
		return out

	func fraction_of(stat_id: StringName) -> float:
		return float(values.get(stat_id, 0.0))


class _Bus:
	extends RefCounted
	var _subscribers := {}
	var _test

	func _init(test) -> void:
		_test = test

	func subscribe(event: StringName, callback: Callable) -> void:
		if not _subscribers.has(event):
			_subscribers[event] = []
		(_subscribers[event] as Array).append(callback)

	func unsubscribe(event: StringName, callback: Callable) -> void:
		if _subscribers.has(event):
			(_subscribers[event] as Array).erase(callback)

	func emit_event(event: StringName, payload = null) -> void:
		_test._heard.append(event)
		for callback in (_subscribers.get(event, []) as Array).duplicate():
			(callback as Callable).call(payload)

	func subscriber_count(event: StringName) -> int:
		return (_subscribers.get(event, []) as Array).size()


func _worsen(stat_id: StringName, to: float) -> void:
	_survival.values[stat_id] = to


# --- the onset is a relationship, not a number --------------------------------


## The number that says "bad enough for the dog to notice" is only meaningful
## against the thresholds the designer authored. Asserted against a SECOND,
## independent scan of the same directory rather than against 0.50, so moving a
## threshold in data moves the dog and does not fail this test.
func test_the_onset_is_the_highest_threshold_anybody_authored() -> void:
	var highest := 0.0
	var dir := DirAccess.open(STATS_DIRECTORY)
	assert_not_null(dir, "%s must exist" % STATS_DIRECTORY)
	if dir == null:
		return
	var seen := 0
	for entry in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var definition := ResourceLoader.load(STATS_DIRECTORY.path_join(entry)) as StatDefinition
		if definition == null:
			continue
		for effect in definition.threshold_effects:
			if effect == null or effect.comparison != ThresholdEffect.Comparison.BELOW:
				continue
			seen += 1
			highest = maxf(highest, effect.threshold)
	assert_true(seen > 0, "no BELOW thresholds authored in %s at all" % STATS_DIRECTORY)
	assert_almost_eq(_concern.onset(), highest,
		0.0001, "the dog starts worrying at %.3f but the body first changes at %.3f"
			% [_concern.onset(), highest])


func test_a_healthy_body_worries_nobody() -> void:
	_concern.advance(1.0)
	assert_almost_eq(_concern.concern(), 0.0, 0.0001)
	assert_false(_concern.is_concerned())
	assert_true(_concern.may_lie_down(), "a dog may lie down beside a healthy man")


func test_concern_reaches_one_only_when_the_reading_is_on_the_floor() -> void:
	_worsen(&"thirst", 0.0)
	_concern.advance(1.0)
	assert_almost_eq(_concern.concern(), 1.0, 0.0001)


## Halfway to the onset is halfway worried, and this is the property every
## behaviour below is derived from -- so if it drifts, all three drift together
## and none of them contradicts the badge.
func test_concern_runs_evenly_from_the_onset_to_the_floor() -> void:
	var onset := _concern.onset()
	_worsen(&"hunger", onset * 0.5)
	_concern.advance(1.0)
	assert_almost_eq(_concern.concern(), 0.5, 0.0001)


# --- one icon at a time, and it is the worst one ------------------------------


func test_it_reports_the_single_worst_reading_and_not_a_list() -> void:
	_worsen(&"hunger", 0.40)
	_worsen(&"thirst", 0.12)
	_worsen(&"fatigue", 0.30)
	_concern.advance(1.0)
	assert_eq(_concern.worst_stat(), &"thirst",
		"three readings are low and the dog showed %s" % _concern.worst_stat())
	assert_almost_eq(_concern.worst_fraction(), 0.12, 0.0001)
	assert_eq(_concern.readout().stat(), &"thirst")


## Ties are not the point; overtaking is. A dog still showing the stat that was
## worst a minute ago is a dashboard with one slot.
func test_the_icon_changes_when_a_different_reading_overtakes() -> void:
	_worsen(&"hunger", 0.10)
	_concern.advance(1.0)
	assert_eq(_concern.readout().stat(), &"hunger")
	_worsen(&"core_temperature", 0.04)
	_bus.emit_event(&"survival.threshold_crossed",
		{"stat": &"core_temperature", "active": true})
	assert_eq(_concern.readout().stat(), &"core_temperature")


# --- it is born knowing -------------------------------------------------------


## Three nodes in this project have shipped listening only for transitions and
## therefore never learning the state they were born into. A dog is rescued
## mid-run, so this one is born into a state by definition.
func test_a_dog_that_arrives_late_is_already_worried() -> void:
	var model := _Model.new()
	model.values[&"core_temperature"] = 0.10
	var late = ConcernScript.new()
	late.set_event_bus(_Bus.new(self))
	late.set_survival_system(model)
	_host.add_child(late)
	assert_true(late.is_concerned(),
		"it heard no event, so it decided nothing was wrong")
	assert_eq(late.worst_stat(), &"core_temperature")
	assert_true(late.badges_shown() >= 1,
		"a dog that arrives beside a freezing man says nothing")
	_host.remove_child(late)
	late.free()


func test_it_subscribes_to_all_three_survival_events() -> void:
	assert_eq(_bus.subscriber_count(&"survival.threshold_crossed"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_depleted"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_recovered"), 1)


func test_it_lets_go_of_the_bus_when_it_leaves() -> void:
	_host.remove_child(_concern)
	assert_eq(_bus.subscriber_count(&"survival.threshold_crossed"), 0,
		"a freed node's callback is still in the bus")
	_host.add_child(_concern)


## Crossing a threshold on the way UP is the body getting better. A warning that
## also fires on recovery is a warning that means nothing.
func test_recovering_past_a_threshold_raises_nothing() -> void:
	_worsen(&"hunger", 0.20)
	_concern.advance(1.0)
	var before := _concern.badges_shown()
	_bus.emit_event(&"survival.threshold_crossed",
		{"stat": &"hunger", "active": false})
	assert_eq(_concern.badges_shown(), before,
		"the dog warned the player about getting better")


# --- nothing is permanent -----------------------------------------------------


## UI rule 4. The badge blooms, holds and drifts, and then there is nothing above
## the dog's head. A marker that is always there is not a warning, it is a HUD
## that happens to be world-anchored.
func test_the_badge_dies_on_its_own_while_the_body_is_still_failing() -> void:
	_worsen(&"thirst", 0.05)
	_concern.advance(0.1)
	assert_true(_concern.readout().is_live(), "it never appeared")
	var elapsed := 0.0
	while elapsed < 6.0 and _concern.readout().is_live():
		_concern.advance(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	assert_false(_concern.readout().is_live(),
		"still on screen after %.2f s with the stat unchanged" % elapsed)
	assert_true(_concern.is_concerned(),
		"the badge died because the body recovered, which tests nothing")


## ...and it is allowed back, or a player who looked away has lost the warning
## for the rest of the run. Allowed back on a TIMER, which is what keeps it a
## warning rather than a gauge.
func test_it_comes_back_after_its_own_interval_and_not_before() -> void:
	_worsen(&"thirst", 0.05)
	_concern.advance(0.1)
	var first := _concern.badges_shown()
	var elapsed := 0.0
	while elapsed < _concern.badge_repeat_seconds - 0.5:
		_concern.advance(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	assert_eq(_concern.badges_shown(), first, "it came back early")
	while elapsed < _concern.badge_repeat_seconds + 1.0:
		_concern.advance(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	assert_eq(_concern.badges_shown(), first + 1, "it never came back")


# --- the behaviour, which has to read with the badge off screen ---------------


func test_it_comes_closer_and_the_distance_falls_the_whole_way() -> void:
	var last := INF
	for fraction in [1.0, 0.5, 0.35, 0.2, 0.1, 0.0]:
		_worsen(&"fatigue", _concern.onset() * float(fraction))
		_concern.advance(0.01)
		var now := _concern.standoff_m()
		assert_true(now <= last + 0.0001,
			"standoff went back UP from %.2f to %.2f at %.2f of the onset"
				% [last, now, fraction])
		last = now
	assert_almost_eq(_concern.standoff_m(), _concern.close_standoff_m, 0.0001)


## Constraint 4: a sixth stat is a `.tres` and no `.gd`. That only holds if the
## dog can find a pictograph for a reading nobody told it about -- so every stat
## the model carries must resolve to an icon that is on disk.
##
## It also holds the frostbite pair apart. `frostbite_feet` is the SECOND site on
## the hands' row, so the row's own glyph is a hand, and a dog warning about the
## player's feet while drawing a hand would be wrong in the way nobody files.
func test_every_reading_the_model_has_resolves_to_a_pictograph_on_disk() -> void:
	var missing: Array[String] = []
	for stat_id in _survival.stat_ids():
		var glyph: StringName = _concern._glyph_for(stat_id)
		if glyph == &"" or not ResourceLoader.exists("res://assets/ui/icons/%s.png" % glyph):
			missing.append(String(stat_id))
	assert_true(missing.is_empty(),
		"no pictograph for: %s" % ", ".join(missing))
	assert_eq(_concern._glyph_for(&"frostbite_feet"), &"frostbite_feet",
		"the feet borrowed the hand's icon")
	assert_eq(_concern._glyph_for(&"frostbite_hands"), &"frostbite_hands")


func test_it_actually_walks_the_distance_in_and_holds_it() -> void:
	var dog := Node3D.new()
	var man := Node3D.new()
	_host.add_child(dog)
	_host.add_child(man)
	man.global_position = Vector3.ZERO
	dog.global_position = Vector3(9.0, 0.0, 0.0)
	_concern.set_dog(dog)
	_concern.set_target(man)
	_worsen(&"core_temperature", 0.02)
	for _step in range(1200):
		_concern.advance(1.0 / 60.0)
	var closed := dog.global_position.distance_to(man.global_position)
	assert_almost_eq(closed, _concern.standoff_m(), _concern.standoff_slack_m + 0.05,
		"it stopped %.2f m out and its standoff is %.2f m" % [closed, _concern.standoff_m()])
	# ...and holds. A dog that closes and then drifts off has said nothing.
	for _step in range(600):
		_concern.advance(1.0 / 60.0)
	assert_almost_eq(dog.global_position.distance_to(man.global_position),
		_concern.standoff_m(), _concern.standoff_slack_m + 0.05,
		"it did not stay")


func test_it_will_not_lie_down_while_the_player_is_in_trouble() -> void:
	_worsen(&"hunger", 0.05)
	_concern.advance(0.1)
	assert_false(_concern.may_lie_down())
	assert_false(_concern.lie_down(), "it lay down anyway")
	assert_false(_concern.is_lying())
	# and settles again once the body does
	_worsen(&"hunger", 1.0)
	_concern.advance(0.1)
	assert_true(_concern.may_lie_down())


func test_the_whine_comes_faster_as_it_gets_worse() -> void:
	_worsen(&"thirst", _concern.onset())
	_concern.advance(0.01)
	var easy := _concern.whine_period()
	_worsen(&"thirst", 0.0)
	_concern.advance(0.01)
	var worst := _concern.whine_period()
	assert_true(worst < easy,
		"period stayed at %.2f s from the onset to the floor" % worst)
	assert_almost_eq(easy, _concern.whine_period_easy, 0.0001)
	assert_almost_eq(worst, _concern.whine_period_worst, 0.0001)


## Inward and outward must never be confused. This class owns the inward half and
## must not be able to reach the outward one: the growl belongs to whatever owns
## threats, and it arrives through the take.
func test_the_concern_never_speaks_outward() -> void:
	assert_false(String(_concern.whine_call).contains("growl"),
		"the concern is wired to %s" % _concern.whine_call)
	var source := FileAccess.get_file_as_string("res://src/entities/wildlife/dog_concern.gd")
	assert_false(source.contains("DogAnimations.GROWL"),
		"the concern plays the threat take")


## Off is off. A capture, a montage or a cutscene turns this node off and expects
## the dog to stop being driven, not to stop only some of the time.
func test_disabling_it_stops_everything() -> void:
	_worsen(&"thirst", 0.0)
	_concern.advance(0.1)
	var shown := _concern.badges_shown()
	_concern.enabled = false
	_bus.emit_event(&"survival.stat_depleted", {"stat": &"thirst"})
	_concern.advance(30.0)
	assert_eq(_concern.badges_shown(), shown)
