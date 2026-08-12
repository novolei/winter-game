extends TestCase

## The moment the roof comes off.
##
## System Map section 4.4 states the technique and states it deliberately
## unclever: an Area3D threshold, a FIXED EXPORTED LIST of parts, a 0.30 s tween
## both ways. No ray, no occlusion culling, no camera-relative test. These tests
## exist to keep it that way, because every one of those "improvements" is a
## thing somebody will reach for later and each of them costs predictability.
##
## What is actually being protected:
##
##   1. THE LIST IS DATA. A reveal is handed a list of names and a building to
##      look in. Nothing here knows what a farmhouse is -- wave 4 adds four more
##      buildings and each must be scene setup, not a new script.
##
##   2. THE SHADOW MOVES WITH THE FADE. Measured on this build: a part at
##      transparency 1.0 still casts, and mid-fade it casts hardest. A roof you
##      cannot see, throwing a shadow you can, puts the revealed room in the
##      dark -- which is the one failure that makes the whole feature pointless.
##
##   3. NOTHING OUTSIDE THE LIST IS TOUCHED. The floor, the furniture and the
##      walls the reveal is supposed to leave standing must come out of a full
##      reveal byte-identical to how they went in.
##
## Every subject here is built with .new() and never enters the tree, so the
## fade snaps instead of tweening and the endpoints can be asserted with no
## wall-clock and no flake. fade_duration_to() is what covers the timing rule.

const InteriorRevealScript := preload("res://src/entities/interior/interior_reveal.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

## Two to fade, two to leave alone. The names are farmhouse names only so the
## test reads like the real thing; nothing in the subject knows them.
const FADED := [&"FH_Fade_Roof", &"FH_Fade_Front"]
const KEPT := [&"FH_Room", &"FH_Furniture"]

var _building: Node3D = null
var _bus = null
var _occupant: Node3D = null
var _events: Array = []


func before_each() -> void:
	_events = []


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2). Freeing the
	# building takes the reveal and every part with it.
	for node in [_building, _bus, _occupant]:
		if node != null:
			node.free()
	_building = null
	_bus = null
	_occupant = null


# --- helpers ---------------------------------------------------------------

## A building with four named MeshInstance3D under it and a reveal beneath that,
## wired to fade two of them. Deliberately shaped like the farmhouse's own
## Farmhouse/Model/FH_* nesting so find_child has to descend.
func _build(names := FADED) -> InteriorReveal:
	_building = Node3D.new()
	_building.name = "Farmhouse"
	var model := Node3D.new()
	model.name = "Model"
	_building.add_child(model)
	for part_name in FADED + KEPT:
		var part := MeshInstance3D.new()
		part.name = String(part_name)
		model.add_child(part)
	var reveal: InteriorReveal = InteriorRevealScript.new()
	# Annotated, not `var x =`: an untyped local makes the array literal an
	# untyped Array, the typed setter rejects it and the VM abandons the rest of
	# this function without failing anything (briefing trap 4).
	var list: Array[StringName] = []
	list.assign(names)
	reveal.fade_parts = list
	_building.add_child(reveal)
	return reveal


func _part(reveal: InteriorReveal, part_name: StringName) -> GeometryInstance3D:
	return _building.find_child(String(part_name), true, false) as GeometryInstance3D


func _with_bus(reveal: InteriorReveal) -> void:
	_bus = EventBusScript.new()
	_bus.subscribe(InteriorRevealScript.EVENT_ENTERED, _record.bind("in"))
	_bus.subscribe(InteriorRevealScript.EVENT_EXITED, _record.bind("out"))
	reveal.set_event_bus(_bus)


func _record(payload, tag: String) -> void:
	_events.append({"tag": tag, "payload": payload})


func _tags() -> PackedStringArray:
	var tags := PackedStringArray()
	for event in _events:
		tags.append(event["tag"])
	return tags


# --- the list is data ------------------------------------------------------

func test_it_finds_the_parts_it_was_handed_by_name() -> void:
	var reveal := _build()
	reveal.resolve()
	var found := PackedStringArray()
	for part in reveal.parts():
		found.append(part.name)
	assert_eq(found.size(), 2, "two names were given, %d parts resolved" % found.size())
	assert_true(found.has("FH_Fade_Roof"), "FH_Fade_Roof did not resolve; got %s" % ", ".join(found))
	assert_true(found.has("FH_Fade_Front"), "FH_Fade_Front did not resolve; got %s" % ", ".join(found))


## A name with no mesh behind it is the failure mode the farmhouse report warns
## about: the building keeps a wall in front of the camera and nothing reports
## it. It has to be visible to a caller, not just to a console.
func test_a_name_the_building_does_not_have_is_reported() -> void:
	var reveal := _build([&"FH_Fade_Roof", &"FH_Fade_Chimney"])
	reveal.resolve()
	assert_eq(reveal.parts().size(), 1, "only one of the two names exists in the building")
	assert_eq(
		Array(reveal.unresolved()), ["FH_Fade_Chimney"],
		"the name that does not resolve must be nameable; got %s" % ", ".join(reveal.unresolved())
	)


func test_an_empty_list_reveals_nothing_and_complains_about_nothing() -> void:
	var reveal := _build([])
	reveal.resolve()
	assert_eq(reveal.parts().size(), 0, "an empty list resolves to no parts")
	assert_eq(reveal.unresolved().size(), 0, "an empty list has nothing unresolved")


# --- the fade --------------------------------------------------------------

func test_a_fresh_reveal_is_concealed() -> void:
	var reveal := _build()
	reveal.resolve()
	assert_false(reveal.is_revealed(), "a building starts with its roof on")
	assert_almost_eq(reveal.fade(), 0.0, 0.0001, "a building starts fully opaque")


func test_revealing_makes_every_listed_part_transparent() -> void:
	var reveal := _build()
	reveal.reveal()
	assert_true(reveal.is_revealed(), "reveal() must put it inside")
	for part_name in FADED:
		assert_almost_eq(
			_part(reveal, part_name).transparency, 1.0, 0.0001,
			"%s must be fully faded once the player is inside" % part_name
		)


func test_concealing_puts_every_listed_part_back() -> void:
	var reveal := _build()
	reveal.reveal()
	reveal.conceal()
	assert_false(reveal.is_revealed(), "conceal() must put it back outside")
	for part_name in FADED:
		assert_almost_eq(
			_part(reveal, part_name).transparency, 0.0, 0.0001,
			"%s must be solid again once the player leaves" % part_name
		)


## The one that makes the feature worth having. Measured on 4.7.1: a mesh at
## transparency 1.0 still renders into the shadow map, so a faded roof lays its
## own shadow across the room it just uncovered.
func test_a_faded_part_stops_casting_its_shadow() -> void:
	var reveal := _build()
	reveal.reveal()
	for part_name in FADED:
		assert_eq(
			_part(reveal, part_name).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s is invisible but still casting; the revealed room would be in its shadow" % part_name
		)


func test_a_restored_part_casts_again() -> void:
	var reveal := _build()
	reveal.reveal()
	reveal.conceal()
	for part_name in FADED:
		assert_eq(
			_part(reveal, part_name).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"%s is solid again and must throw its shadow again" % part_name
		)


## Mid-fade is where the shadow is worst -- a half-transparent roof is drawn at
## half strength and shadowed at full. So the shadow goes at the first frame of
## the fade, not at the last.
func test_the_shadow_goes_at_the_first_frame_of_the_fade_not_the_last() -> void:
	var reveal := _build()
	reveal.apply_fade(0.01)
	for part_name in FADED:
		assert_almost_eq(_part(reveal, part_name).transparency, 0.01, 0.0001, "%s must be barely faded" % part_name)
		assert_eq(
			_part(reveal, part_name).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s must stop casting as soon as it starts fading" % part_name
		)


func test_the_fade_is_clamped_to_a_sane_range() -> void:
	var reveal := _build()
	reveal.apply_fade(4.0)
	assert_almost_eq(reveal.fade(), 1.0, 0.0001, "a fade above 1 must clamp rather than push transparency out of range")
	reveal.apply_fade(-4.0)
	assert_almost_eq(reveal.fade(), 0.0, 0.0001, "a fade below 0 must clamp")


## Section 4.4's number, and it is a number rather than a feel: 0.30 s, both
## directions. A reversal partway through runs at the same rate, so the roof
## never snaps.
func test_the_fade_takes_three_tenths_of_a_second_in_both_directions() -> void:
	var reveal := _build()
	assert_almost_eq(reveal.fade_seconds, 0.30, 0.0001, "System Map 4.4 fixes the fade at 0.30 s")
	assert_almost_eq(reveal.fade_duration_to(1.0), 0.30, 0.0001, "going in must take the full 0.30 s")
	reveal.apply_fade(1.0)
	assert_almost_eq(reveal.fade_duration_to(0.0), 0.30, 0.0001, "coming out must take the full 0.30 s")
	reveal.apply_fade(0.5)
	assert_almost_eq(reveal.fade_duration_to(1.0), 0.15, 0.0001, "a reversal from halfway runs at the same rate, not for the same time")


# --- what must never be touched --------------------------------------------

func test_a_part_that_is_not_on_the_list_is_never_touched() -> void:
	var reveal := _build()
	reveal.reveal()
	for part_name in KEPT:
		var part := _part(reveal, part_name)
		assert_almost_eq(part.transparency, 0.0, 0.0001, "%s is not on the fade list and must stay solid" % part_name)
		assert_eq(
			part.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"%s is not on the fade list and must keep casting" % part_name
		)


# --- crossing the threshold ------------------------------------------------

func test_crossing_in_announces_it() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	reveal.on_body_entered(_occupant)
	assert_eq(Array(_tags()), ["in"], "crossing in must announce exactly once; got %s" % ", ".join(_tags()))
	assert_true(reveal.is_revealed(), "crossing in must reveal")


func test_crossing_back_out_announces_it() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	reveal.on_body_entered(_occupant)
	reveal.on_body_exited(_occupant)
	assert_eq(Array(_tags()), ["in", "out"], "crossing back must announce; got %s" % ", ".join(_tags()))
	assert_false(reveal.is_revealed(), "crossing back must conceal")


## The threshold is the doorway, and a doorway is a place a player dithers in.
## Two entered signals in a row -- one per collision shape, which is exactly
## what a two-shape threshold produces -- must not announce twice.
func test_dithering_on_the_threshold_announces_once() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	reveal.on_body_entered(_occupant)
	reveal.on_body_entered(_occupant)
	reveal.on_body_exited(_occupant)
	reveal.on_body_exited(_occupant)
	assert_eq(Array(_tags()), ["in", "out"], "a repeated crossing must be idempotent; got %s" % ", ".join(_tags()))


func test_the_announcement_names_the_building_it_came_from() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	reveal.on_body_entered(_occupant)
	assert_eq(_events.size(), 1, "expected one announcement")
	if _events.is_empty():
		return
	var payload = _events[0]["payload"]
	assert_true(payload is Dictionary, "the payload must be a Dictionary, not %s" % [payload])
	if not (payload is Dictionary):
		return
	assert_eq(
		payload.get("building", ""), "Farmhouse",
		"an audio director subscribing to this has to know WHICH interior; got %s" % [payload]
	)


## ...AND WHO WENT IN. An event about something that does not say what it is
## about is invisible while there is exactly one character in the world, and
## every listener quietly assumes it means the player.
##
## It stops being invisible in wave 4. The bear walks through doors, wave 5's
## threats walk through doors, and a listener that cannot tell whose crossing
## this was applies it to all of them -- which is not a hypothetical: the snow
## load had to ask the building who its occupant was, because the payload would
## not say, and without that fix every walker in the valley thawed the moment
## the player stepped indoors.
func test_the_announcement_names_who_went_in() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	_occupant.name = "Player"
	reveal.set_occupant(_occupant)
	reveal.on_body_entered(_occupant)
	reveal.on_body_exited(_occupant)
	assert_eq(_events.size(), 2, "expected one announcement each way")
	if _events.size() < 2:
		return
	assert_eq(
		(_events[0]["payload"] as Dictionary).get("occupant", null), _occupant,
		"the crossing in named the building but not who crossed it"
	)
	assert_eq(
		(_events[1]["payload"] as Dictionary).get("occupant", null), _occupant,
		"the crossing out named the building but not who left it"
	)


## Nothing else in the valley may take the roof off. A threat walking past the
## door, a dropped item, a beacon -- all of them are bodies.
func test_only_the_occupant_trips_the_threshold() -> void:
	var reveal := _build()
	_with_bus(reveal)
	_occupant = Node3D.new()
	reveal.set_occupant(_occupant)
	var bear := Node3D.new()
	reveal.on_body_entered(bear)
	assert_false(reveal.is_revealed(), "something that is not the occupant must not take the roof off")
	assert_eq(_tags().size(), 0, "and must not announce anything")
	bear.free()


func test_with_no_occupant_known_nothing_trips_the_threshold() -> void:
	var reveal := _build()
	var stranger := Node3D.new()
	reveal.on_body_entered(stranger)
	assert_false(reveal.is_revealed(), "an unresolved occupant must fail closed, not open")
	stranger.free()
