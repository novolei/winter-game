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
		if row != null and not known.has(row.stat):
			orphans.append(String(row.stat))
	assert_eq(orphans.size(), 0, "readouts for stats nothing defines: %s" % "; ".join(orphans))

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
func test_the_main_clock_is_the_largest_in_both_readouts() -> void:
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

func test_the_main_clock_is_first() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var rows := _layout.ordered()
	assert_true(rows.size() > 0)
	if rows.is_empty():
		return
	assert_eq(rows[0].stat, _layout.frost_source,
		"the reading the interface's own ice is made of should lead the stack")

# --- section 6.1's ring ------------------------------------------------------

## 冻伤是局部的 (GDD section 5), so section 6.1 keeps it off the ring and grows it
## on the silhouette's own limbs instead.
func test_frostbite_is_not_on_the_ring() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	for row in _layout.ring_rows():
		assert_true(row.limb == "",
			"%s is a limb reading and must not be a ring segment" % row.stat)
	var limbs := 0
	for row in _layout.ordered():
		if row.ring_anchor != VitalReadout.Anchor.RING:
			limbs += 1
	assert_eq(limbs, 2, "section 6.1 asks for two limb arcs, hands and feet")

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
func test_every_readout_has_an_icon_on_disk() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	var missing: Array[String] = []
	for row in _layout.ordered():
		var path := "%s/%s.png" % [ICON_DIRECTORY, row.stat]
		if not ResourceLoader.exists(path):
			missing.append(path)
	assert_eq(missing.size(), 0, "readouts with no icon: %s" % "; ".join(missing))

func test_the_frost_source_is_a_stat_that_exists() -> void:
	assert_not_null(_layout)
	if _layout == null:
		return
	assert_true(_stat_ids().has(_layout.frost_source),
		"the interface's ice is bound to a stat nothing defines: %s" % _layout.frost_source)
