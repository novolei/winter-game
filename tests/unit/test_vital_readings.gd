extends TestCase

## The seam between the survival model and everything that shows it.
##
## ---------------------------------------------------------------------------
## WHERE THIS COVERAGE CAME FROM
## ---------------------------------------------------------------------------
## Most of it is tests/unit/test_vitals.gd's, moved rather than written. That
## file tested a permanent corner cluster the owner has since deleted, and about
## a third of what it asserted was not about the cluster at all -- it was about
## reading the model: one row per stat and none invented in code, frostbite
## folding to the worse limb, and a reading being correct on its first ask with
## no event ever sent.
##
## Deleting the view would have deleted that coverage with it, and two other
## readouts are about to be built on exactly this. So it lives here now, against
## an object with no pixels in it.
##
## ---------------------------------------------------------------------------
## THE ONE THAT MATTERS MOST IS STILL THE ONE ABOUT BEING BORN LATE
## ---------------------------------------------------------------------------
## This project has three times shipped a listener that could only ever learn
## about transitions and therefore never learned the state it was born into. The
## fix here is structural -- VitalReadings caches nothing, so there is nowhere
## for a stale answer to live -- and the test is written against the SYMPTOM
## rather than the mechanism: a reader built after the body has already gone cold
## must report a cold body, with no event ever having been sent.

const ReadingsScript := preload("res://src/ui/vital_readings.gd")
const SurvivalScript := preload("res://src/systems/survival_system.gd")

var _readings: VitalReadings = null
var _model: Node = null

func before_each() -> void:
	_model = SurvivalScript.new()
	_model.load_from_directory()
	_readings = ReadingsScript.new()
	_readings.build()
	_readings.set_model(_model)

func after_each() -> void:
	# VitalReadings is RefCounted and frees itself. The model is a Node and does
	# not (briefing constraint 2).
	_readings = null
	if _model != null:
		_model.free()
		_model = null

# --- it is built from data ---------------------------------------------------

## Constraint 4. Nothing in src/ui counts the stats; the rows come out of
## data/ui/vital_layout.tres, so a sixth stat is a new row and no code change.
func test_nothing_here_knows_how_many_stats_there_are() -> void:
	assert_not_null(_readings.layout())
	if _readings.layout() == null:
		return
	assert_eq(_readings.rows().size(), _readings.layout().ordered().size())

## GDD section 5 names five: 体温 · 饥饿 · 口渴 · 疲劳 · 冻伤.
func test_there_are_five_readings_for_six_stat_files() -> void:
	assert_eq(_readings.rows().size(), 5)
	assert_true(_model.stat_ids().size() == 6,
		"the fixture assumes frostbite is two files and one reading")

func test_every_stat_reaches_a_reading() -> void:
	for id in _model.stat_ids():
		assert_not_null(_readings.row_for(id),
			"%s has no readout row -- the player can never be told about it" % id)

func test_nothing_reads_a_value_from_the_clock_any_more() -> void:
	# The day dial was the sixth row and it was not a survival stat at all. It
	# went with the cluster; the clock is section 5.10's time prompt now.
	assert_true(_readings.row_for(&"daylight") == null,
		"the day dial is still in the layout, and nothing draws it")
	for row in _readings.rows():
		assert_true(_model.has_stat(row.stat),
			"%s is a reading the survival model cannot answer" % row.stat)

# --- what a value means ------------------------------------------------------

func test_a_full_reserve_is_steady() -> void:
	_model.start()
	var reading := _readings.read(&"hunger")
	assert_almost_eq(float(reading["fraction"]), 1.0, 0.05)
	assert_eq(int(reading["state"]), VitalTone.State.STEADY)

## Section 6.1's table, reached through the seam rather than restated here.
func test_the_state_is_the_threshold_table_and_not_a_second_opinion() -> void:
	_model.start()
	for id in _model.stat_ids():
		var reading := _readings.read_site(id)
		assert_eq(int(reading["state"]),
			int(VitalTone.state_for(float(reading["fraction"]), bool(reading["depleted"]))),
			"%s disagrees with VitalTone about what its own value means" % id)

# --- frostbite: one reading, two sites ---------------------------------------

## GDD section 5 makes frostbite local and the player acts on whichever limb is
## further gone, so an average would hide the one that matters behind the one
## that does not.
func test_the_frostbite_reading_shows_the_worse_of_the_two_limbs() -> void:
	_model.start()
	# ADD, not MULTIPLY: the frostbite stats carry no base decay at all -- they
	# only accumulate through core_temperature's threshold effects -- so scaling
	# zero leaves it at zero and the fixture proves nothing.
	_model.push_modifier(&"frostbite_feet", &"test", Modifier.Operation.ADD, 0.02)
	_model.advance(60.0)
	assert_true(_model.fraction_of(&"frostbite_feet")
		< _model.fraction_of(&"frostbite_hands"), "the fixture has to hurt one limb only")
	var folded := _readings.read(&"frostbite_hands")
	assert_almost_eq(float(folded["fraction"]), _model.fraction_of(&"frostbite_feet"), 0.0001,
		"the reading showed the healthy limb")
	assert_true(int(folded["state"]) != VitalTone.State.STEADY,
		"the reading stayed calm while one limb was freezing")

## And the unfolded form, which is what an announcement naming a limb needs:
## 手指不听使唤了 beside the feet's number would be a lie.
func test_a_single_site_is_read_without_the_fold() -> void:
	_model.start()
	_model.push_modifier(&"frostbite_feet", &"test", Modifier.Operation.ADD, 0.02)
	_model.advance(60.0)
	var hands := _readings.read_site(&"frostbite_hands")
	assert_almost_eq(float(hands["fraction"]), _model.fraction_of(&"frostbite_hands"), 0.0001,
		"read_site folded, and the words would then name the wrong limb")
	assert_true(float(hands["fraction"]) > float(_readings.read(&"frostbite_hands")["fraction"]),
		"the fixture has to make the two forms differ")

## Reading the second site by its own name must not fold it into itself.
func test_reading_the_second_site_by_name_is_that_site() -> void:
	_model.start()
	_model.push_modifier(&"frostbite_feet", &"test", Modifier.Operation.ADD, 0.02)
	_model.advance(60.0)
	assert_almost_eq(float(_readings.read(&"frostbite_feet")["fraction"]),
		_model.fraction_of(&"frostbite_feet"), 0.0001)

# --- it asks, and there is nowhere for a stale answer to live ----------------

## The one this file exists for. No event is ever sent; the reader is simply
## built after the body has already gone cold, which is what happens every time
## a scene is reloaded, a montage ends, or a readout is added mid-run.
func test_a_reader_built_after_the_body_went_cold_reports_a_cold_body() -> void:
	_model.start()
	_model.push_modifier(&"core_temperature", &"test", Modifier.Operation.MULTIPLY, 900.0)
	_model.advance(120.0)
	assert_true(_model.fraction_of(&"core_temperature") < VitalTone.ALARM_BELOW,
		"the fixture has to actually put the body in trouble")

	var late: VitalReadings = ReadingsScript.new()
	late.build()
	late.set_model(_model)
	assert_true(int(late.state_of(&"core_temperature")) != VitalTone.State.STEADY,
		"the reader learned nothing from a state that changed before it existed")

func test_a_reading_follows_the_model_without_being_told_to() -> void:
	_model.start()
	var before := _readings.fraction_of(&"core_temperature")
	_model.push_modifier(&"core_temperature", &"test", Modifier.Operation.MULTIPLY, 900.0)
	_model.advance(60.0)
	assert_true(_readings.fraction_of(&"core_temperature") < before,
		"the reader is holding a value from an earlier frame")

# --- the worst reading -------------------------------------------------------

## Published because "how badly is he doing" has one right answer and several
## callers: the Tab ring's hierarchy, and anything in the world that reacts to
## the man's condition.
func test_the_worst_reading_is_the_one_in_the_most_trouble() -> void:
	_model.start()
	_model.push_modifier(&"thirst", &"test", Modifier.Operation.MULTIPLY, 900.0)
	_model.advance(60.0)
	var worst := _readings.worst()
	assert_false(worst.is_empty())
	if worst.is_empty():
		return
	assert_eq(StringName(worst["stat"]), &"thirst")

func test_the_worst_reading_of_a_well_man_is_still_a_reading() -> void:
	_model.start()
	var worst := _readings.worst()
	assert_false(worst.is_empty(), "a well man has readings too")
	if not worst.is_empty():
		assert_eq(int(worst["state"]), VitalTone.State.STEADY)

# --- it is inert rather than fatal -------------------------------------------

## A scene with no run going, a screenshot harness, a menu. Better a well man
## than a dead one, and better either than a crash.
func test_it_survives_having_no_model_at_all() -> void:
	var bare: VitalReadings = ReadingsScript.new()
	bare.build()
	assert_eq(bare.rows().size(), 5, "the layout is data and does not need a model")
	var reading := bare.read(&"core_temperature")
	assert_almost_eq(float(reading["fraction"]), 1.0, 0.0001)
	assert_eq(int(reading["state"]), VitalTone.State.STEADY)
	assert_false(bare.worst().is_empty())

func test_a_stat_it_has_never_heard_of_is_harmless() -> void:
	_model.start()
	var reading := _readings.read(&"spirit")
	assert_almost_eq(float(reading["fraction"]), 1.0, 0.0001)
	assert_false(_readings.has(&"spirit"))
	assert_eq(int(_readings.state_of(&"")), VitalTone.State.STEADY)
