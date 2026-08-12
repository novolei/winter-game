extends TestCase

## Section 5.2 阈值浮现: a crossing announcing itself in the left breathing
## border, and then dying.
##
## Permanence and emergence are not alternatives. The margin stack makes a
## reading AVAILABLE; this makes a crossing ANNOUNCE ITSELF, and it is the only
## place the strokes are ever named -- so the interface teaches its own
## vocabulary at the moment the vocabulary matters and at no other time.

const SurfacingScript := preload("res://src/ui/threshold_surfacing.gd")
const UILayerScript := preload("res://src/ui/ui_layer.gd")
const SurvivalScript := preload("res://src/systems/survival_system.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

var _surfacing: ThresholdSurfacing = null
var _layer: UILayer = null
var _model: Node = null
var _bus: Node = null

func before_each() -> void:
	_layer = UILayerScript.new()
	_layer.build()
	_bus = EventBusScript.new()
	_model = SurvivalScript.new()
	_model.set_event_bus(_bus)
	_model.load_from_directory()
	_surfacing = SurfacingScript.new()
	_surfacing.set_layer(_layer)
	_surfacing.set_model(_model)
	_surfacing.build()
	_surfacing.set_event_bus(_bus)

func after_each() -> void:
	# Order matters. The surfacing frees anything still waiting out its stagger;
	# the layer owns everything it has already been handed. Freeing the layer
	# first would leave a pending note with no owner (briefing constraint 2).
	if _surfacing != null:
		_surfacing.free()
		_surfacing = null
	if _layer != null:
		_layer.free()
		_layer = null
	if _model != null:
		_model.free()
		_model = null
	if _bus != null:
		_bus.free()
		_bus = null

func _cross(stat: StringName, threshold: float, active := true) -> void:
	_bus.emit_event(&"survival.threshold_crossed", {
		"stat": stat, "threshold": threshold, "active": active,
		"comparison": "below", "value": threshold - 0.01, "targets": [],
	})

func _first_live():
	if _surfacing.live_count() == 0:
		return null
	return _surfacing._live[0]

# --- it says the words the table holds ---------------------------------------

func test_a_crossing_surfaces_the_line_of_copy_for_that_threshold() -> void:
	_cross(&"frostbite_hands", 0.5)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note, "a crossing surfaced nothing")
	if note == null:
		return
	assert_eq(note.text(), "手指不听使唤了")
	assert_eq(note.stat(), &"frostbite_hands")

## 说后果，不说数字. The whole reason GDD section 11 can say Tab is the only moment
## the game shows a number.
func test_the_words_never_contain_the_value() -> void:
	_cross(&"core_temperature", 0.15)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	for character in note.text():
		assert_false(character >= "0" and character <= "9",
			"a number reached the screen: \"%s\"" % note.text())

## Section 5.2's 恢复 row specifies the arc collapsing and the warm mark walking
## back, and NO copy. Printing 手指不听使唤了 at the moment the fingers came back
## would be worse than silence.
func test_coming_back_up_says_nothing() -> void:
	_cross(&"frostbite_hands", 0.5, false)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note, "a recovery still surfaces -- it just has no words")
	if note == null:
		return
	assert_eq(note.text(), "")

## The floor is not one of the authored thresholds, so it borrows the most
## severe row the designer wrote -- which is already true at zero. GDD section 5:
## 疲劳 ... 归零后果: 无法奔跑.
func test_a_stat_at_its_floor_gets_the_worst_thing_written_about_it() -> void:
	_bus.emit_event(&"survival.stat_depleted", {"stat": &"fatigue", "value": 0.0})
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	assert_eq(note.text(), "跑不动了")

## A threshold with no row surfaces as silence, which is why
## tests/unit/test_ui_threshold_copy.gd exists. Here we only prove the element
## does not invent a placeholder to fill the gap.
func test_a_threshold_with_no_copy_invents_nothing() -> void:
	_cross(&"core_temperature", 0.77)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	assert_eq(note.text(), "")

# --- the stagger and the stack -----------------------------------------------

## 第 N 条延迟 160×N ms. Four lines arriving on one frame is a wall.
func test_notes_arriving_together_are_staggered() -> void:
	_cross(&"core_temperature", 0.5)
	_cross(&"hunger", 0.3)
	_cross(&"thirst", 0.3)
	assert_eq(_surfacing.pending_count(), 3)
	assert_eq(_surfacing.live_count(), 0, "nothing may appear before it is due")

	_surfacing.advance(0.01)
	assert_eq(_surfacing.live_count(), 1, "the first is immediate")
	_surfacing.advance(ThresholdSurfacing.STAGGER_SECONDS)
	assert_eq(_surfacing.live_count(), 2)
	_surfacing.advance(ThresholdSurfacing.STAGGER_SECONDS)
	assert_eq(_surfacing.live_count(), 3)
	assert_eq(_surfacing.pending_count(), 0)

## 纵向堆叠，间距 8px. Stacked downward from 38% of the height, never on top of
## one another.
func test_notes_stack_downward_rather_than_overlapping() -> void:
	_cross(&"core_temperature", 0.5)
	_cross(&"hunger", 0.3)
	_surfacing.advance(0.01)
	_surfacing.advance(ThresholdSurfacing.STAGGER_SECONDS)
	assert_eq(_surfacing.live_count(), 2)
	var first = _surfacing._live[0]
	var second = _surfacing._live[1]
	assert_true(second.position.y >= first.position.y + first.size.y,
		"two notes were laid on top of each other")
	assert_almost_eq(first.position.x, second.position.x, 0.001,
		"the stack must be a column, not a staircase")

## 左侧呼吸边界内，垂直 38% 高度.
func test_the_first_note_stands_where_the_document_puts_it() -> void:
	_cross(&"core_temperature", 0.5)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	var canvas := Vector2(1920.0, 1080.0)
	assert_almost_eq(note.position.y, canvas.y * ThresholdSurfacing.TOP_FRACTION, 0.001)
	assert_true(note.position.x >= _layer.tokens().edge_pixels(canvas),
		"a note must not break the breathing border")
	assert_true(note.position.x < canvas.x * 0.25,
		"and it is still a margin element, not a banner")

## The permanent readings stand in the same margin, so the notes are indented
## past them. Written as a test because the collision is invisible in code and
## obvious in a frame: the first capture with both systems live had six lines of
## copy laid straight across the six readings they were naming.
func test_a_note_never_lies_across_the_readings_it_names() -> void:
	_cross(&"core_temperature", 0.5)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	var canvas := Vector2(1920.0, 1080.0)
	var tokens := _layer.tokens()
	var layout := ResourceLoader.load(ThresholdSurfacing.LAYOUT_PATH) as VitalLayout
	var cluster := Vitals.cluster_size(tokens, layout, canvas)
	var cluster_bottom: float = tokens.edge_pixels(canvas) + cluster.y
	assert_true(note.position.y >= cluster_bottom,
		"the note stands at y %.0f px, across the gauges that end at %.0f px"
			% [note.position.y, cluster_bottom])

# --- rule 4 still binds HERE -------------------------------------------------

## The rule 4 exemption covers the five survival readings and nothing else. A
## note is not one of them: it is born with a death on it and the layer carries
## out the sentence.
func test_a_note_dies_on_its_own() -> void:
	_cross(&"core_temperature", 0.5)
	_surfacing.advance(0.01)
	assert_eq(_layer.live_count(), 1)
	var tokens := _layer.tokens()
	var whole_breath := tokens.bloom_seconds + ThresholdSurfacing.HOLD_SECONDS \
		+ tokens.drift_seconds + 0.01
	_layer.advance(whole_breath)
	assert_eq(_layer.live_count(), 0, "a note outlived its own breath")
	assert_eq(_surfacing.live_count(), 0, "the surfacing kept a reference to a freed note")

## Section 5.2's timing: 呵 200 / 持 2400 / 散 900. Only the hold is this
## section's own; the other two come from the tokens, which is how section 5.6's
## cold snap reaches this element at all.
func test_it_holds_for_the_documented_two_point_four_seconds() -> void:
	assert_almost_eq(ThresholdSurfacing.HOLD_SECONDS, 2.4, 0.0001)

func test_the_stack_reopens_once_a_note_has_gone() -> void:
	_cross(&"core_temperature", 0.5)
	_surfacing.advance(0.01)
	var tokens := _layer.tokens()
	_layer.advance(tokens.bloom_seconds + ThresholdSurfacing.HOLD_SECONDS
		+ tokens.drift_seconds + 0.01)
	_cross(&"hunger", 0.3)
	_surfacing.advance(0.01)
	var note = _first_live()
	assert_not_null(note)
	if note == null:
		return
	assert_almost_eq(note.position.y, 1080.0 * ThresholdSurfacing.TOP_FRACTION, 0.001,
		"the second note should start at the top again, not below a note that is gone")

# --- the wiring --------------------------------------------------------------

func test_it_subscribes_to_all_three_survival_events() -> void:
	assert_eq(_bus.subscriber_count(&"survival.threshold_crossed"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_depleted"), 1)
	assert_eq(_bus.subscriber_count(&"survival.stat_recovered"), 1)

## Section 5.2: UI 不需要自己判断任何东西. This file never compares a value with a
## threshold, so a model that sub-steps to catch a crossing inside one long frame
## cannot be second-guessed into missing it.
##
## Proved by taking the announcement away and leaving everything else: the body
## really does cross thresholds over ten minutes -- the same run WITH a bus
## surfaces several -- and with the bus detached the interface has nothing to
## say, because it was never watching the values in the first place.
func test_it_surfaces_nothing_that_was_not_announced() -> void:
	_model.set_event_bus(null)
	_model.start()
	_model.advance(600.0)
	_surfacing.advance(600.0)
	assert_eq(_surfacing.live_count(), 0,
		"the surfacing found a crossing by looking rather than by listening")
	assert_true(_model.active_threshold_count() > 0,
		"the fixture has to actually cross something, or this proves nothing")

func test_a_stat_with_no_layout_row_surfaces_nothing() -> void:
	_cross(&"spirit", 0.5)
	_surfacing.advance(0.01)
	assert_eq(_surfacing.live_count(), 0,
		"an unlabelled mark is worse than silence")

func test_a_malformed_payload_is_harmless() -> void:
	_bus.emit_event(&"survival.threshold_crossed", null)
	_bus.emit_event(&"survival.stat_depleted", "not a dictionary")
	_bus.emit_event(&"survival.stat_recovered", 7)
	_surfacing.advance(1.0)
	assert_eq(_surfacing.live_count(), 0)

func test_a_pending_note_is_freed_rather_than_orphaned() -> void:
	_cross(&"core_temperature", 0.5)
	_cross(&"hunger", 0.3)
	# Two queued, none released. after_each() frees the surfacing, which must
	# take the one still waiting with it -- the layer never saw it, so nothing
	# else ever will.
	assert_eq(_surfacing.pending_count(), 2)
