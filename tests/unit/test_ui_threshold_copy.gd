extends TestCase

## UI design document section 11's 文案覆盖 gate.
##
## ---------------------------------------------------------------------------
## WHAT THIS TEST IS FOR, AND WHY IT IS NOT A NICE-TO-HAVE
## ---------------------------------------------------------------------------
## Section 5.2's copy table is a contract between the design document and
## data/stats/*.tres. Section 11 makes it a machine constraint: 「加一条阈值而不写
## 文案，测试就红。没有它，第一条被遗忘的阈值会静默地什么都不显示，而这种失败在屏幕
## 上和"这条阈值还没触发"完全一样.」
##
## That last clause is the whole reason this file exists. A forgotten row is not
## a visible defect. The stat crosses, the surfacing node asks for words, gets an
## empty string, and shows nothing -- which is pixel-for-pixel identical to a
## threshold that has simply not been reached yet. It cannot be found by playing
## and it cannot be found by looking at a screenshot. It can only be found here.
##
## ---------------------------------------------------------------------------
## THE TEST READS THE STAT FILES, NOT A LIST
## ---------------------------------------------------------------------------
## It walks data/stats/*.tres and enumerates the ThresholdEffects that are really
## there. A test that compared the copy map against a second list of expected
## thresholds would pass forever after somebody added a threshold to neither.

const COPY_MAP_PATH := "res://data/ui/threshold_copy.tres"
const STATS_DIRECTORY := "res://data/stats"

func _copy_map() -> ThresholdCopyMap:
	if not ResourceLoader.exists(COPY_MAP_PATH):
		return null
	return ResourceLoader.load(COPY_MAP_PATH) as ThresholdCopyMap

## Every (stat, threshold) the stat files actually author, deduplicated the same
## way SurvivalSystem._rebuild_groups() deduplicates them -- one crossing event
## per (watch_stat, comparison, threshold), however many effects hang off it. So
## core_temperature 0.35, which carries a hands effect AND a feet effect, wants
## ONE line of copy and not two.
func _authored_thresholds() -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	var dir := DirAccess.open(STATS_DIRECTORY)
	if dir == null:
		return found
	var file_names := dir.get_files()
	file_names.sort()
	for file_name in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var definition := ResourceLoader.load(STATS_DIRECTORY.path_join(file_name)) as StatDefinition
		if definition == null:
			continue
		for effect in definition.threshold_effects:
			if effect == null or effect.watch_stat == &"":
				continue
			var key := "%s|%d|%.6f" % [effect.watch_stat, effect.comparison, effect.threshold]
			if seen.has(key):
				continue
			seen[key] = true
			found.append({"stat": effect.watch_stat, "threshold": effect.threshold})
	return found

# --- the gate ---------------------------------------------------------------

func test_the_copy_map_exists_and_loads() -> void:
	assert_true(ResourceLoader.exists(COPY_MAP_PATH),
		"section 5.2's copy table must exist at %s" % COPY_MAP_PATH)
	assert_not_null(_copy_map(),
		"%s must load as a ThresholdCopyMap" % COPY_MAP_PATH)

func test_the_stat_files_actually_author_some_thresholds() -> void:
	# Guards the gate itself. If the stats directory ever stops loading, every
	# coverage assertion below would sweep an empty list and pass.
	assert_true(_authored_thresholds().size() >= 15,
		"data/stats/*.tres should author at least the 15 thresholds of section 5.2")

func test_every_authored_threshold_has_a_line_of_copy() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var uncovered: Array[String] = []
	for row in _authored_thresholds():
		if not map.has_row(row["stat"], row["threshold"]):
			uncovered.append("%s @ %.2f" % [row["stat"], row["threshold"]])
	assert_eq(uncovered.size(), 0,
		"thresholds with no line of copy -- they would surface as nothing: %s"
			% "; ".join(uncovered))

## The other direction. A row for a threshold nobody authors is copy that can
## never fire, and it is how the table rots: a stat is retuned from 0.30 to 0.35
## and the old row goes on looking correct in the file forever.
func test_every_line_of_copy_answers_a_real_threshold() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var authored := _authored_thresholds()
	var orphans: Array[String] = []
	for entry in map.entries:
		if entry == null:
			continue
		var matched := false
		for row in authored:
			if row["stat"] != entry.stat:
				continue
			if absf(float(row["threshold"]) - entry.threshold) <= ThresholdCopyMap.MATCH_TOLERANCE:
				matched = true
				break
		if not matched:
			orphans.append("%s @ %.2f (\"%s\")" % [entry.stat, entry.threshold, entry.text])
	assert_eq(orphans.size(), 0,
		"copy for thresholds nothing authors -- it can never fire: %s" % "; ".join(orphans))

# --- what the copy is allowed to say ----------------------------------------

func test_no_row_is_empty() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var blank: Array[String] = []
	for entry in map.entries:
		if entry == null or entry.text.strip_edges() == "":
			blank.append(str(entry.stat) if entry != null else "<null>")
	assert_eq(blank.size(), 0, "blank copy is the failure this gate exists to catch: %s"
		% "; ".join(blank))

## Section 5.2: 说后果，不说数字. The copy describes what the body is doing, and a
## digit in it would mean somebody wrote "冻伤 34%" after all -- which is the one
## thing the whole section forbids, and the reason GDD section 11 can say Tab is
## the only moment in the game that shows numbers.
func test_no_line_of_copy_contains_a_digit() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var offenders: Array[String] = []
	for entry in map.entries:
		if entry == null:
			continue
		for character in entry.text:
			if character >= "0" and character <= "9":
				offenders.append("%s: \"%s\"" % [entry.stat, entry.text])
				break
	assert_eq(offenders.size(), 0,
		"section 5.2 says 说后果，不说数字 -- copy with a number in it: %s"
			% "; ".join(offenders))

## Every row also carries what the mechanic really does, so a reviewer can check
## the words against the data without decoding a ThresholdEffect.
func test_every_row_records_the_mechanic_it_answers() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var undocumented: Array[String] = []
	for entry in map.entries:
		if entry != null and entry.effect.strip_edges() == "":
			undocumented.append("%s @ %.2f" % [entry.stat, entry.threshold])
	assert_eq(undocumented.size(), 0,
		"rows with no record of what the data does there: %s" % "; ".join(undocumented))

# --- the lookups the surfacing node depends on ------------------------------

func test_a_stat_that_hit_its_floor_gets_the_worst_row() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var lowest := map.lowest_row_for(&"fatigue")
	assert_not_null(lowest, "fatigue must have copy for the surfacing node to use at zero")
	if lowest == null:
		return
	# GDD section 5's own table: 疲劳 ... 归零后果: 无法奔跑.
	assert_almost_eq(lowest.threshold, 0.02, 0.0001,
		"the floor should borrow the most severe authored row, not the mildest")

func test_an_unknown_threshold_returns_no_words_rather_than_a_placeholder() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	assert_eq(map.text_for(&"core_temperature", 0.77), "")
	assert_eq(map.text_for(&"spirit", 0.5), "", "a stat that does not exist must not resolve")

## A threshold is matched with a tolerance, and the tolerance must be far too
## small to let one row answer for its neighbour -- 0.15 and 0.20 are the closest
## pair in the whole model.
func test_the_match_tolerance_cannot_reach_the_next_threshold() -> void:
	var map := _copy_map()
	assert_not_null(map)
	if map == null:
		return
	var at_fifteen := map.text_for(&"core_temperature", 0.15)
	var at_twenty := map.text_for(&"core_temperature", 0.20)
	assert_true(at_fifteen != "" and at_twenty != "")
	assert_true(at_fifteen != at_twenty, "two distinct thresholds resolved to one row")
	assert_true(ThresholdCopyMap.MATCH_TOLERANCE < 0.025,
		"the tolerance must be far below half the 0.05 gap between 0.15 and 0.20")
