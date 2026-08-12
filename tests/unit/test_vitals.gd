extends TestCase

## The five survival readings, permanently, in the breathing margin.
##
## ---------------------------------------------------------------------------
## THE TEST THAT MATTERS MOST IS THE ONE ABOUT _ready()
## ---------------------------------------------------------------------------
## This project has twice shipped a listener that could only ever learn about
## transitions and therefore never learned the state it was born into. Here the
## fix is structural -- the state is derived from the value, and the value is
## asked for on ready -- so the test is written against the symptom rather than
## against the mechanism: a stack built while a stat is ALREADY in trouble must
## be in trouble on its first frame, with no event ever having been sent.

const VitalsScript := preload("res://src/ui/vitals.gd")
const SurvivalScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"

var _vitals: Vitals = null
var _model: Node = null
var _bus: Node = null
var _tokens: UITokens = null

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_bus = EventBusScript.new()
	_model = SurvivalScript.new()
	_model.set_event_bus(_bus)
	_model.load_from_directory()
	_vitals = VitalsScript.new()
	_vitals.set_tokens(_tokens)

func after_each() -> void:
	# Node is not reference counted (briefing constraint 2). The stack owns its
	# strokes, so freeing it is also what proves it adopted them.
	if _vitals != null:
		_vitals.free()
		_vitals = null
	if _model != null:
		_model.free()
		_model = null
	if _bus != null:
		_bus.free()
		_bus = null

func _wire() -> void:
	_vitals.set_model(_model)
	_vitals.set_event_bus(_bus)
	_vitals.build()

# --- it is built from data ---------------------------------------------------

func test_it_draws_one_reading_per_stat_the_model_carries() -> void:
	_wire()
	assert_eq(_vitals.stroke_count(), _model.stat_ids().size(),
		"a stat with no stroke is a stat the player cannot see")

## Constraint 4. Nothing in src/ui counts the stats; the count comes out of
## data/ui/vital_layout.tres, so a sixth stat is a new row and no code change.
func test_nothing_in_the_element_knows_how_many_stats_there_are() -> void:
	_wire()
	assert_not_null(_vitals.layout())
	assert_eq(_vitals.stroke_count(), _vitals.layout().ordered().size())

func test_each_stroke_is_the_stat_its_row_names() -> void:
	_wire()
	for id in _model.stat_ids():
		assert_not_null(_vitals.stroke_for(id), "no stroke for %s" % id)

# --- it asks, and it listens -------------------------------------------------

## The one this file exists for. No event is ever sent; the stack is simply
## built after the body has already gone cold, which is what happens every time
## a scene is reloaded, a montage ends, or a readout is added mid-run.
func test_a_stack_born_into_trouble_is_in_trouble_on_its_first_frame() -> void:
	_model.start()
	# Cold enough to be past section 6.1's alarm threshold before anything that
	# could listen exists.
	_model.push_modifier(&"core_temperature", &"test", Modifier.Operation.MULTIPLY, 900.0)
	_model.advance(120.0)
	assert_true(_model.fraction_of(&"core_temperature") < VitalTone.ALARM_BELOW,
		"the fixture has to actually put the body in trouble")

	_wire()
	var stroke := _vitals.stroke_for(&"core_temperature")
	assert_not_null(stroke)
	if stroke == null:
		return
	assert_true(stroke.state() != VitalTone.State.STEADY,
		"the stack learned nothing from a state that changed before it existed")

func test_it_subscribes_to_all_three_survival_events() -> void:
	_wire()
	assert_eq(_bus.subscriber_count(&"survival.threshold_crossed"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_depleted"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_recovered"), 1)

func test_it_lets_go_of_the_bus_when_it_is_handed_another() -> void:
	_wire()
	var second := EventBusScript.new()
	_vitals.set_event_bus(second)
	assert_eq(_bus.subscriber_count(&"survival.threshold_crossed"), 0,
		"a stack that never unsubscribes leaks a callback into the old bus")
	assert_eq(second.subscriber_count(&"survival.threshold_crossed"), 1)
	second.free()

# --- what a crossing does ----------------------------------------------------

## Emphasis by MATERIAL. The ice on that one reading thickens at once and then
## clears by itself, so nothing is added to the screen and nothing has to be
## remembered and taken away.
func test_a_crossing_thickens_the_ice_on_that_reading_alone() -> void:
	_wire()
	var cold := _vitals.stroke_for(&"core_temperature")
	var hungry := _vitals.stroke_for(&"hunger")
	assert_not_null(cold)
	assert_not_null(hungry)
	if cold == null or hungry == null:
		return
	var before: float = hungry.paint().rime
	_bus.emit_event(&"survival.threshold_crossed", {
		"stat": &"core_temperature", "threshold": 0.5, "active": true,
	})
	assert_almost_eq(cold.paint().rime, 1.0, 0.0001)
	assert_almost_eq(hungry.paint().rime, before, 0.0001,
		"a crossing on one reading must not thicken the others")

## `active` false is the stat coming back UP through a threshold. Thickening on
## good news would make the material mean two opposite things.
func test_coming_back_up_through_a_threshold_does_not_thicken_the_ice() -> void:
	_wire()
	var cold := _vitals.stroke_for(&"core_temperature")
	assert_not_null(cold)
	if cold == null:
		return
	var before: float = cold.paint().rime
	_bus.emit_event(&"survival.threshold_crossed", {
		"stat": &"core_temperature", "threshold": 0.5, "active": false,
	})
	assert_almost_eq(cold.paint().rime, before, 0.0001)

func test_a_stat_bottoming_out_thickens_the_ice() -> void:
	_wire()
	var tired := _vitals.stroke_for(&"fatigue")
	assert_not_null(tired)
	if tired == null:
		return
	_bus.emit_event(&"survival.stat_depleted", {"stat": &"fatigue", "value": 0.0})
	assert_almost_eq(tired.paint().rime, 1.0, 0.0001)

func test_an_event_about_a_stat_it_has_never_heard_of_is_harmless() -> void:
	_wire()
	_bus.emit_event(&"survival.threshold_crossed", {
		"stat": &"spirit", "threshold": 0.5, "active": true,
	})
	_bus.emit_event(&"survival.stat_depleted", {"stat": &"spirit"})
	_bus.emit_event(&"survival.threshold_crossed", null)
	assert_eq(_vitals.stroke_count(), _model.stat_ids().size())

# --- emphasis is form, and it is per reading ---------------------------------

## The settled look, 「刻度」Engraved: a gauge is a ring of ticks, and when the
## reading crosses a threshold the ticks give way to one continuous arc. That is
## emphasis by a CHANGE OF FORM, which is the only channel rule 3 leaves once
## colour is spent on meaning.
func test_a_reading_in_trouble_stops_being_a_scale() -> void:
	_model.start()
	_wire()
	var hungry := _vitals.stroke_for(&"hunger")
	assert_not_null(hungry)
	if hungry == null:
		return
	hungry.set_reading(0.9, false, false)
	hungry.advance(5.0)
	assert_false(hungry.paint().is_solid(), "a healthy reading is a scale")
	hungry.set_reading(0.1, false, false)
	hungry.advance(5.0)
	assert_true(hungry.paint().is_solid(),
		"a reading past its threshold has to change FORM -- colour is not available")

## And ONLY that reading. The emphasis used to be bound to how cold the body was,
## which came from the withdrawn frost language; under the settled look that
## would turn every gauge solid at once and destroy the thing the solid arc is
## for.
func test_one_reading_in_trouble_does_not_change_the_others() -> void:
	_model.start()
	_wire()
	var hungry := _vitals.stroke_for(&"hunger")
	var tired := _vitals.stroke_for(&"fatigue")
	assert_not_null(hungry)
	assert_not_null(tired)
	if hungry == null or tired == null:
		return
	hungry.set_reading(0.05, false, false)
	tired.set_reading(0.9, false, false)
	hungry.advance(5.0)
	tired.advance(5.0)
	assert_true(hungry.paint().is_solid())
	assert_false(tired.paint().is_solid(), "a healthy reading went solid with its neighbour")

# --- rule 2, and the corner -------------------------------------------------

## 中心 85% 永远是世界. Permanent does not mean large, and it does not mean central.
## The cluster lives in the top-left corner and must not creep inward as it grows.
func test_the_cluster_stays_in_its_corner() -> void:
	_wire()
	for canvas in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(2560, 1080),
			Vector2(1080, 1920)]:
		_vitals._viewport = canvas
		_vitals.relayout()
		var right: float = _vitals.position.x + _vitals.size.x
		var bottom: float = _vitals.position.y + _vitals.size.y
		assert_true(right < canvas.x * 0.5,
			"at %s the gauges reached %.0f px, half way into the frame" % [canvas, right])
		assert_true(bottom < canvas.y * 0.3,
			"at %s the gauges hung down to %.0f px, into the world" % [canvas, bottom])
		assert_true(_vitals.position.x >= _tokens.edge_pixels(canvas) - 0.001
				and _vitals.position.y >= _tokens.edge_pixels(canvas) - 0.001,
			"the cluster broke the breathing border at %s" % canvas)

## ANCHORED to the corner, not positioned by remembered coordinates. Under
## `canvas_items` / `expand` the canvas changes shape with the window and extra
## screen area is revealed rather than letterboxed, so a fixed offset walks off
## the edge of every aspect but the one it was authored at.
func test_it_is_anchored_to_the_corner_at_every_aspect() -> void:
	_wire()
	var seen: Array[Vector2] = []
	for canvas in [Vector2(1920, 1080), Vector2(3440, 1080), Vector2(1920, 1200)]:
		_vitals._viewport = canvas
		_vitals.relayout()
		seen.append(_vitals.position)
	# Same short edge, same inset: a wider window shows MORE VALLEY and does not
	# move the readouts.
	assert_almost_eq(seen[0].x, seen[1].x, 0.001)
	assert_almost_eq(seen[0].y, seen[1].y, 0.001)
	# A taller window has a larger short edge only if the width is unchanged, so
	# the inset grows with it rather than staying at a remembered pixel count.
	assert_true(seen[2].x >= seen[0].x)

## Section 6.1 gives the main clock nearly twice the ring, and rule 3 turns that
## into the design: the biggest gauge is the only warm one, and it is warmth.
func test_the_heat_gauge_is_visibly_the_largest() -> void:
	_wire()
	_vitals._viewport = Vector2(1920, 1080)
	_vitals.relayout()
	var main := _vitals.stroke_for(_vitals.layout().frost_source)
	assert_not_null(main)
	if main == null:
		return
	for id in _model.stat_ids():
		if id == _vitals.layout().frost_source:
			continue
		var other := _vitals.stroke_for(id)
		if other == null:
			continue
		assert_true(main.size.x > other.size.x * 1.3,
			"%s is nearly as large as the main clock" % id)

## And it is the ONLY warm one. Rule 3 survived every change of look.
func test_only_the_heat_gauge_is_ever_warm() -> void:
	_wire()
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres") as ColorBible
	assert_not_null(palette)
	if palette == null:
		return
	for id in _model.stat_ids():
		var is_heat: bool = id == _vitals.layout().frost_source
		for state in [VitalTone.State.STEADY, VitalTone.State.ALARM,
				VitalTone.State.CRITICAL, VitalTone.State.EMPTY]:
			var colour := VitalTone.colour_for(_tokens, state, is_heat)
			if is_heat:
				continue
			assert_true(colour != _tokens.life_warm and colour != _tokens.life_ember,
				"%s reached for the colour of heat in state %d" % [id, state])
	assert_true(VitalTone.heat_colour_for(_tokens, VitalTone.State.STEADY)
		== _tokens.life_warm, "a holding body must read as heat present")

## Every gauge on one centre line, so the row reads as one instrument.
func test_every_gauge_shares_a_centre_line() -> void:
	_wire()
	_vitals._viewport = Vector2(1920, 1080)
	_vitals.relayout()
	var line := -1.0
	for id in _model.stat_ids():
		var stroke := _vitals.stroke_for(id)
		if stroke == null:
			continue
		var mid: float = stroke.position.y + stroke.size.y * 0.5
		if line < 0.0:
			line = mid
		assert_almost_eq(mid, line, 0.5, "%s is off the centre line" % id)

## Gauges must not overlap, at any aspect. Two rings touching is the one layout
## fault that reads as a rendering bug rather than as a layout choice.
func test_no_two_gauges_overlap() -> void:
	_wire()
	for canvas in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(3440, 1440)]:
		_vitals._viewport = canvas
		_vitals.relayout()
		var ordered := _vitals.layout().ordered()
		for index in range(ordered.size() - 1):
			var a := _vitals.stroke_for(ordered[index].stat)
			var b := _vitals.stroke_for(ordered[index + 1].stat)
			if a == null or b == null:
				continue
			var a_centre: float = a.position.x + a.size.x * 0.5
			var b_centre: float = b.position.x + b.size.x * 0.5
			var need: float = _radius_of(a) + _radius_of(b)
			assert_true(b_centre - a_centre >= need,
				"%s and %s overlap at %s" % [ordered[index].stat, ordered[index + 1].stat, canvas])

func _radius_of(stroke: VitalStroke) -> float:
	return stroke.size.x * 0.5 - _tokens.design_px(
		VitalStroke.PAD_DESIGN_PX, _vitals._viewport)

# --- the eye goes to the one that matters ------------------------------------

## Colour is spent on rule 3, so the only way to take the eye to one reading is
## to make the others quieter.
func test_a_crossing_dims_the_other_readings() -> void:
	_wire()
	_bus.emit_event(&"survival.threshold_crossed", {
		"stat": &"hunger", "threshold": 0.3, "active": true,
	})
	_vitals.advance(0.05)
	assert_true(_vitals._focus == &"hunger")
	assert_true(_vitals._focus_left > 0.0)
	# And it levels out again by the time section 5.2's words have gone.
	_vitals.advance(Vitals.FOCUS_SECONDS + 0.1)
	assert_almost_eq(_vitals._focus_left, 0.0, 0.0001,
		"the cluster must come back level, or the dimming becomes the new normal")

# --- driving -----------------------------------------------------------------

# --- it is born, and it is never taken away ----------------------------------

## Section 1.2: 没有任何元素可以跳过其中任何一段. A permanent element still arrives.
func test_it_is_invisible_on_the_frame_it_is_built() -> void:
	_wire()
	assert_almost_eq(_vitals.modulate.a, 0.0, 0.0001,
		"appearing at full strength for one frame and then blooming is a flash")

func test_it_blooms_to_full_and_settles_at_its_own_size() -> void:
	_wire()
	_vitals.advance(_tokens.bloom_seconds)
	assert_almost_eq(_vitals.modulate.a, 1.0, 0.001)
	assert_almost_eq(_vitals.scale.x, 1.0, 0.001, "the overshoot has to come back to 1")

## THE RULE 4 EXEMPTION, MECHANICALLY. Everything else in this interface carries
## its own death; this one does not, and that is the entire difference.
func test_it_never_dies() -> void:
	_wire()
	_vitals.advance(1.0)
	_vitals.advance(3600.0)
	assert_almost_eq(_vitals.modulate.a, 1.0, 0.001,
		"the five survival readings are the one thing that does not drift away")
	assert_eq(_vitals.stroke_count(), _model.stat_ids().size())

## It is a child of the layer so it is composited with the rest of the
## interface, but the layer must never have been given custody of it -- UILayer
## frees what it holds.
func test_the_layer_is_never_given_custody_of_it() -> void:
	var layer := preload("res://src/ui/ui_layer.gd").new()
	layer.build()
	layer.add_child(_vitals)
	_vitals.set_model(_model)
	_vitals.set_event_bus(_bus)
	_vitals.build()
	assert_eq(layer.live_count(), 0,
		"a permanent element handed to the layer is an element the layer will kill")
	layer.remove_child(_vitals)
	layer.free()

func test_advancing_grows_the_ice_on_every_reading() -> void:
	_wire()
	_vitals.advance(Frost.GROWTH_SECONDS + 0.01)
	for id in _model.stat_ids():
		var stroke := _vitals.stroke_for(id)
		assert_not_null(stroke)
		if stroke != null:
			assert_almost_eq(stroke.paint().growth, 1.0, 0.0001, "%s never finished growing" % id)

func test_it_survives_having_no_model_at_all() -> void:
	_vitals.build()
	_vitals.read_model()
	_vitals.advance(1.0)
	assert_true(_vitals.stroke_count() > 0,
		"a scene with no run going should still show a well man, not an empty screen")
