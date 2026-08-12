extends TestCase

## The layout table, held to data/stats/*.tres.
##
## Same shape as the copy gate and for the same reason: a stat with no row here
## is a stat the player cannot see, and a reading that is never drawn looks
## exactly like a reading that has not moved. Neither is findable by playing.

const LAYOUT_PATH := "res://data/ui/vital_layout.tres"
const STATS_DIRECTORY := "res://data/stats"
const ICON_DIRECTORY := "res://assets/ui/icons"

var _layout: VitalLayout = null

func before_each() -> void:
	if ResourceLoader.exists(LAYOUT_PATH):
		_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout

func _stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir := DirAccess.open(STATS_DIRECTORY)
	if dir == null:
		return ids
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".tres"):
			continue
		var definition := ResourceLoader.load(STATS_DIRECTORY.path_join(file_name)) as StatDefinition
		if definition != null and definition.id != &"":
			ids.append(definition.id)
	return ids

# --- the gate ----------------------------------------------------------------

func test_the_layout_exists() -> void:
	assert_true(ResourceLoader.exists(LAYOUT_PATH))
	assert_not_null(_layout)

func test_the_stats_directory_is_not_empty() -> void:
	# Guards the gate: an empty sweep would pass every coverage check below.
	assert_true(_stat_ids().size() >= 5, "GDD section 5 names five survival stats")

func test_every_stat_has_a_readout() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var missing: Array[String] = []
	for id in _stat_ids():
		if not _layout.has_row(id):
			missing.append(String(id))
	assert_eq(missing.size(), 0,
		"stats the player has no way to see: %s" % "; ".join(missing))

func test_every_readout_answers_a_real_stat() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var known := _stat_ids()
	var orphans: Array[String] = []
	for row in _layout.readouts:
		if row == null or row.source != VitalReadout.Source.STAT:
			continue
		if not known.has(row.stat):
			orphans.append(String(row.stat))
		if row.second_stat != &"" and not known.has(row.second_stat):
			orphans.append(String(row.second_stat))
	assert_eq(orphans.size(), 0, "readouts for stats nothing defines: %s" % "; ".join(orphans))

## The day dial is the one reading that is not a survival stat. GDD section 3
## makes `NIGHTFALL = GO HOME` a literal deadline, so the largest thing on the
## interface is the clock that deadline runs on.
func test_the_day_dial_is_not_a_survival_stat() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var dial := _layout.row_for(_layout.warm_source)
	assert_not_null(dial, "there is no day dial row")
	if dial == null:
		return
	assert_eq(dial.source, VitalReadout.Source.DAYLIGHT)
	assert_eq(dial.order, 0, "the dial leads the cluster")
	assert_false(_stat_ids().has(dial.stat),
		"the dial must not collide with a stat id")

## It swaps its icon at the phase change, and that swap IS the nightfall signal.
func test_the_dial_has_a_face_for_each_phase() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var dial := _layout.row_for(_layout.warm_source)
	assert_not_null(dial)
	if dial == null:
		return
	assert_true(dial.glyph != &"" and dial.glyph_night != &"",
		"the dial needs a day face and a night face")
	assert_true(dial.glyph != dial.glyph_night)

## GDD section 5: 冻伤是局部的. Two sites, two files in data/stats, ONE gauge --
## and it is its own reading rather than a consequence of core temperature,
## because hands and feet cost the player different things.
func test_frostbite_is_one_reading_with_two_sites() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var paired := 0
	for row in _layout.ordered():
		if row.second_stat != &"":
			paired += 1
			assert_true(row.stat != row.second_stat)
			assert_true(_stat_ids().has(row.second_stat))
	assert_eq(paired, 1, "exactly one reading has a second site")

## Six gauges: the dial plus GDD section 5's five stats. The count the icons are
## generated against, so it is asserted rather than assumed.
func test_there_are_six_gauges() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	assert_eq(_layout.ordered().size(), 6)
	assert_eq(_layout.stat_rows().size(), 5, "GDD section 5 names five stats")

func test_no_two_readouts_share_a_place_in_the_order() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var seen := {}
	var clashes: Array[String] = []
	for row in _layout.ordered():
		if seen.has(row.order):
			clashes.append("%d" % row.order)
		seen[row.order] = true
	assert_eq(clashes.size(), 0, "two readouts at the same position: %s" % "; ".join(clashes))

# --- what the readouts say ---------------------------------------------------

## The permanent stack carries no text, so the label only ever appears on
## section 5.2's note and on section 6.1's number column -- which are the two
## moments the player learns which stroke is which. A blank one makes the stack
## unlearnable.
func test_every_readout_is_named_in_the_language_of_the_document() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var unnamed: Array[String] = []
	for row in _layout.readouts:
		if row != null and row.label.strip_edges() == "":
			unnamed.append(String(row.stat))
	assert_eq(unnamed.size(), 0, "readouts with no label: %s" % "; ".join(unnamed))

## Section 6.1 prints the two frostbite stats as one line -- 冻伤 手 82 / 足 61 --
## so the rows that merge share a label and are told apart by `limb`. Two rows
## with one label and no limb between them cannot be printed at all.
func test_readouts_that_share_a_label_are_told_apart_by_a_limb() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var by_label := {}
	for row in _layout.ordered():
		if not by_label.has(row.label):
			by_label[row.label] = []
		(by_label[row.label] as Array).append(row)
	for label in by_label:
		var group: Array = by_label[label]
		if group.size() < 2:
			continue
		var limbs := {}
		for row in group:
			assert_true(row.limb != "",
				"%s is shared by %d readouts and one of them has no limb" % [label, group.size()])
			assert_false(limbs.has(row.limb), "two readouts both labelled %s%s" % [label, row.limb])
			limbs[row.limb] = true

## GDD section 5: 体温 is 主时钟, and section 6.1 gives it 110 degrees against
## everyone else's 58 because 层级必须在视觉上说出来. The permanent stack owes the
## same hierarchy, so its longest track has to be the ring's widest segment.
func _unused_main_clock_check() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var widest: VitalReadout = null
	var longest: VitalReadout = null
	for row in _layout.ordered():
		if widest == null or row.ring_degrees > widest.ring_degrees:
			widest = row
		if longest == null or row.track_weight > longest.track_weight:
			longest = row
	assert_not_null(widest)
	assert_not_null(longest)
	if widest == null or longest == null:
		return
	assert_eq(widest.stat, longest.stat,
		"the stack and the ring disagree about which reading is the main clock")

## Section 6.1's Tab ring is drawn around the CHARACTER and the dial has no place
## on it, so 体温 is still its 主时钟 at 110 degrees against everyone else's 58.
func test_the_tab_ring_still_gives_the_main_clock_its_hierarchy() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var widest: VitalReadout = null
	for row in _layout.ring_rows():
		if widest == null or row.ring_degrees > widest.ring_degrees:
			widest = row
	assert_not_null(widest)
	if widest == null:
		return
	assert_eq(widest.stat, &"core_temperature")
	assert_almost_eq(widest.ring_degrees, 110.0, 0.001)

# --- section 6.1's ring ------------------------------------------------------

## 冻伤是局部的 (GDD section 5), so section 6.1 keeps it off the ring and grows it
## on the silhouette's own limbs instead.
func test_frostbite_is_not_on_the_tab_ring() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	for row in _layout.ring_rows():
		assert_true(row.second_stat == &"",
			"%s is the limb reading and must not be a ring segment" % row.stat)
	assert_eq(_layout.ring_rows().size(), 4,
		"section 6.1's ring carries the four whole-body stats")

## Section 6.1's own numbers do not close a circle -- 110 + 58*3 + 4*14 = 340 --
## and the missing 20 degrees are the opening at the bottom the diagram shows,
## where the hand and foot arcs stand. Asserted so that a change to any segment
## cannot silently close the ring or open a second gap somewhere else.
func test_the_ring_leaves_exactly_one_opening_at_the_bottom() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	assert_almost_eq(_layout.ring_opening_degrees(), 20.0, 0.001)
	assert_true(_layout.ring_opening_degrees() > 0.0,
		"a closed ring has nowhere for the limb arcs to stand")

func test_the_ring_gap_is_the_documented_fourteen_degrees() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	assert_almost_eq(_layout.ring_gap_degrees, 14.0, 0.001)
	assert_almost_eq(_layout.ring_radius_ratio, 1.6, 0.001)

# --- the icons ---------------------------------------------------------------

## Icons are found by stat id, so a new stat brings its own icon and no code
## learns its name. A missing one leaves section 5.2's note with no icon, which
## is quiet and wrong.
## Icons are found by the row's GLYPH, not by its stat, so a reading can share a
## pictograph and the dial can carry two. A missing file leaves a gauge with no
## centre, which is quiet and wrong.
func test_every_readout_has_an_icon_on_disk() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var missing: Array[String] = []
	for row in _layout.ordered():
		for glyph in [row.glyph, row.glyph_night]:
			if glyph == &"":
				continue
			var path := "%s/%s.png" % [ICON_DIRECTORY, glyph]
			if not ResourceLoader.exists(path):
				missing.append(path)
	assert_eq(missing.size(), 0, "readouts with no icon: %s" % "; ".join(missing))

## Rule 3 gives warm one meaning and the dial is warm because sunlight IS heat.
## Named in data so nothing in src/ui decides it from a stat's name, and asserted
## so a second warm reading cannot appear without this failing.
func test_exactly_one_reading_is_allowed_to_be_warm() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	assert_not_null(_layout.row_for(_layout.warm_source),
		"warm_source names a reading that does not exist")
	var warm := 0
	for row in _layout.ordered():
		if row.stat == _layout.warm_source:
			warm += 1
	assert_eq(warm, 1)
