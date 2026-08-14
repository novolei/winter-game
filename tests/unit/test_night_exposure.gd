extends TestCase

## GDD section 3, the line the whole day loop exists to enforce:
##
##   `NIGHTFALL = GO HOME` 是字面意义的死线。天黑后仍在野外，体温下降速率翻倍。
##
## Nightfall is a literal deadline: after dark, still OUT IN THE OPEN, core
## temperature falls twice as fast.
##
## Until this landed the nights were exactly as dangerous as the days, and the
## temperature bar had been tuned assuming they were not -- so every warmth
## figure in the fuel report was optimistic by a factor of two after sundown.
##
## ---------------------------------------------------------------------------
## "OUTDOORS" AND THE INTERIOR THRESHOLD
## ---------------------------------------------------------------------------
## The shelter half has one honest default -- everybody is outdoors until the
## real InteriorReveal events say otherwise. These tests pin both halves: the
## doubling and the EventBus-driven indoor exemption.

const NightExposureScript := preload("res://src/systems/night_exposure.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

const TEMPERATURE := &"core_temperature"

var _exposure = null
var _survival = null
var _bus = null
var _clock = null

## Every one of these extends Node (briefing constraint 2).
func after_each() -> void:
	if _exposure != null:
		_exposure.free()
		_exposure = null
	if _clock != null:
		_clock.free()
		_clock = null
	if _survival != null:
		_survival.free()
		_survival = null
	if _bus != null:
		_bus.free()
		_bus = null

## The shipped stat model, running, plus the exposure rule attached to it
## through a real EventBus. Nothing is stubbed: the point of this file is the
## wiring between three systems that only ever meet at runtime.
func _build():
	_bus = EventBusScript.new()
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	_exposure = NightExposureScript.new()
	_exposure.set_event_bus(_bus)
	_exposure.set_survival_system(_survival)
	_exposure.attach()
	return _exposure

func _nightfall() -> void:
	_bus.emit_event(WorldClockScript.EVENT_NIGHT_STARTED, 1)

func _daybreak() -> void:
	_bus.emit_event(WorldClockScript.EVENT_DAY_STARTED, 2)

func _interior_payload() -> Dictionary:
	# This is InteriorReveal._announce()'s production payload shape. The exposure
	# rule deliberately ignores the values, but the test must cross the real
	# EventBus seam with the same value type the publisher uses.
	return {
		"building": "Farmhouse",
		"occupant": null,
		"reveal": null,
		"fade_seconds": 0.30,
	}

# --- the rule ---------------------------------------------------------------

func test_the_cold_takes_you_twice_as_fast_after_dark() -> void:
	_build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	assert_true(by_day > 0.0, "core temperature does not drain at all, so this proves nothing")
	_nightfall()
	var by_night: float = _survival.drain_rate_of(TEMPERATURE)
	assert_almost_eq(by_night, by_day * 2.0, 0.000001, "nightfall did not double the drain")

func test_daybreak_takes_the_doubling_away_again() -> void:
	_build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	_daybreak()
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"the night's doubling outlived the night"
	)

## The compounding shape this project has met before: a rule re-applied while
## its condition still holds stacks a second copy, looks right for a few
## seconds, and then kills the player. Two nightfalls in a row must be one
## doubling, not four times the drain.
func test_a_second_nightfall_does_not_double_it_again() -> void:
	_build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	_nightfall()
	_nightfall()
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day * 2.0, 0.000001,
		"the doubling compounded"
	)
	assert_eq(
		_survival.modifier_count(&"core_temperature:drain"), 1,
		"more than one night modifier is on the drain"
	)

func test_the_run_finishing_lifts_the_night_off_the_body() -> void:
	_build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	_bus.emit_event(WorldClockScript.EVENT_RUN_FINISHED, null)
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"the run ended and the night was still draining the corpse"
	)

## It must be ONE named source, so that whatever pushes on top of it -- a
## blizzard, a cold snap, a hot meal on the recovery channel -- can be removed
## without taking the night with it.
func test_the_doubling_is_removable_by_its_own_name() -> void:
	_build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	assert_eq(_survival.remove_source(NightExposureScript.SOURCE), 1, "one modifier, one source")
	assert_almost_eq(_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001, "removing it by name left something behind")

# --- the shelter seam -------------------------------------------------------

## The honest default before a threshold event: nobody is sheltered, so the
## doubling applies at night.
func test_a_body_is_outdoors_until_something_says_otherwise() -> void:
	var exposure = _build()
	assert_false(exposure.is_sheltered(), "the default must be outdoors before a threshold event")
	_nightfall()
	assert_true(exposure.is_doubling(), "outdoors after dark and the cold is not doubled")

func test_going_indoors_after_dark_lifts_the_doubling() -> void:
	var exposure = _build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	exposure.set_sheltered(true)
	assert_false(exposure.is_doubling(), "sheltered after dark and the cold is still doubled")
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"walking indoors did not lift the night off the body"
	)

func test_stepping_back_out_after_dark_puts_it_back() -> void:
	var exposure = _build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	exposure.set_sheltered(true)
	exposure.set_sheltered(false)
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day * 2.0, 0.000001,
		"stepping back out into the dark cost nothing"
	)

func test_real_interior_events_lift_and_restore_the_night_doubling() -> void:
	var exposure = _build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	_bus.emit_event(&"interior.entered", _interior_payload())
	assert_true(exposure.is_sheltered(), "the real entered event did not shelter the player")
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"entering through the EventBus left the outdoor night penalty on the body"
	)
	_bus.emit_event(&"interior.exited", _interior_payload())
	assert_false(exposure.is_sheltered(), "the real exited event left the player sheltered")
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day * 2.0, 0.000001,
		"leaving through the EventBus did not restore the outdoor night penalty"
	)

func test_duplicate_interior_events_are_idempotent_and_run_finish_clears_shelter() -> void:
	var exposure = _build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	_bus.emit_event(&"interior.entered", _interior_payload())
	_bus.emit_event(&"interior.entered", _interior_payload())
	assert_eq(
		_survival.modifier_count(&"core_temperature:drain"), 0,
		"duplicate entered events left a night modifier on a sheltered body"
	)
	_bus.emit_event(&"interior.exited", _interior_payload())
	_bus.emit_event(&"interior.exited", _interior_payload())
	assert_eq(
		_survival.modifier_count(&"core_temperature:drain"), 1,
		"duplicate exited events stacked the night modifier"
	)
	_bus.emit_event(&"interior.entered", _interior_payload())
	_bus.emit_event(WorldClockScript.EVENT_RUN_FINISHED, null)
	assert_false(exposure.is_night(), "run finish left the exposure rule at night")
	assert_false(exposure.is_sheltered(), "run finish leaked interior shelter into the next attempt")
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"run finish left an exposure modifier on the body"
	)

## Shelter is not warmth. GDD section 3 doubles the drain for being outdoors
## AFTER DARK; being indoors in daylight is simply the ordinary rate, and a
## house that halved the daytime drain would be a mechanic nobody designed.
func test_shelter_in_daylight_changes_nothing() -> void:
	var exposure = _build()
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	exposure.set_sheltered(true)
	assert_almost_eq(
		_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001,
		"shelter in daylight moved the drain"
	)
	assert_false(exposure.is_doubling(), "daylight is not doubled")

# --- what it costs in play --------------------------------------------------

## The figure the tuning has to be read against. Core temperature empties in
## 1200 s of ordinary exposure; day 1's night is 300 s. Out in it, that night
## costs half a bar rather than a quarter.
func test_a_night_outdoors_costs_twice_what_the_same_time_in_daylight_costs() -> void:
	_build()
	_survival.advance(300.0)
	var lost_by_day: float = 1.0 - _survival.fraction_of(TEMPERATURE)
	_survival.start()
	_nightfall()
	_survival.advance(300.0)
	var lost_by_night: float = 1.0 - _survival.fraction_of(TEMPERATURE)
	assert_true(lost_by_day > 0.0, "300 s of daylight cost nothing, so this proves nothing")
	assert_almost_eq(lost_by_night, lost_by_day * 2.0, 0.0001, "the night did not cost double")

# --- wiring -----------------------------------------------------------------

## Briefing trap 3. Every other test here injects its collaborators, so
## Engine.get_singleton() in place of get_node_or_null("/root/...") would be
## green all the way to a shipped game where the nights are silently as mild as
## the days -- with no HUD to contradict it.
func test_it_resolves_the_autoloaded_bus_and_body_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		return
	_exposure = NightExposureScript.new()
	tree.root.add_child(_exposure)
	_exposure.attach()
	var found_bus: bool = _exposure.has_event_bus()
	var found_body: bool = _exposure.has_survival_system()
	# Unwind before asserting: a Node left under /root leaks at exit.
	_exposure.detach()
	tree.root.remove_child(_exposure)
	assert_true(found_bus, "it did not find the EventBus autoload at /root/EventBus")
	assert_true(found_body, "it did not find the SurvivalSystem autoload at /root/SurvivalSystem")

func test_detaching_stops_it_hearing_the_clock() -> void:
	var exposure = _build()
	exposure.detach()
	assert_eq(
		_bus.subscriber_count(WorldClockScript.EVENT_NIGHT_STARTED), 0,
		"it is still subscribed after detaching"
	)
	var by_day: float = _survival.drain_rate_of(TEMPERATURE)
	_nightfall()
	assert_almost_eq(_survival.drain_rate_of(TEMPERATURE), by_day, 0.000001, "a detached rule still fired")

func test_attaching_twice_subscribes_once() -> void:
	var exposure = _build()
	exposure.attach()
	assert_eq(
		_bus.subscriber_count(WorldClockScript.EVENT_NIGHT_STARTED), 1,
		"attaching twice left two subscriptions"
	)

func test_a_rule_with_no_body_to_apply_to_is_inert_rather_than_broken() -> void:
	_bus = EventBusScript.new()
	_exposure = NightExposureScript.new()
	_exposure.set_event_bus(_bus)
	_exposure.attach()
	_nightfall()
	assert_true(_exposure.is_doubling(), "it should still know it is night")
	assert_false(_exposure.has_survival_system(), "it invented a body out of nowhere")
