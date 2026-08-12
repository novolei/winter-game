extends SceneTree

## Generator for res://data/ui/vital_layout.tres -- the order and the shape of
## the five survival readings, for the permanent stack in the breathing margin
## and for UI design document section 6.1's ring.
##
## Run: godot --headless --path <project> --script res://tools/generate_vital_layout.gd
##
## ---------------------------------------------------------------------------
## FIVE STATS, SIX ROWS, AND WHY THAT IS NOT A MISTAKE
## ---------------------------------------------------------------------------
## GDD section 5 names five: 体温 · 饥饿 · 口渴 · 疲劳 · 冻伤. data/stats holds
## six files, because 冻伤是局部的 -- frostbite accumulates per limb and the two
## limbs cost the player different things (hands: lighting a fire and aiming;
## feet: speed). Section 6.1 shows the same split on screen: 冻伤 手 82 / 足 61,
## one row of numbers made of two stats.
##
## So there are six readings and five labels, and the two frostbite rows share a
## label and differ only in `limb`. Whoever prints them can merge on that.
##
## ---------------------------------------------------------------------------
## THE NUMBERS ARE SECTION 6.1'S, NOT PREFERENCES
## ---------------------------------------------------------------------------
## 体温 110° · 饥饿 58° · 口渴 58° · 疲劳 58° · 冻伤 34° × 2, gaps of 14°. The
## permanent stack's `track_weight` is the same hierarchy expressed as length:
## 110 / 58 = 1.9, rounded to 1.4 for a stack where the tallest reading also has
## to fit inside the breathing margin without reaching the world. The RATIO is
## what section 6.1 is protecting -- 它是主时钟，层级必须在视觉上说出来 -- and a
## reading that is merely first in the list does not say it.

const OUT_DIR := "res://data/ui"
const OUT_PATH := "res://data/ui/vital_layout.tres"

const RING := 0
const HANDS := 1
const FEET := 2
const DIAL := 3

const FROM_STAT := 0
const FROM_DAYLIGHT := 1

## [source, stat, second_stat, label, limb, order, track_weight, ring_degrees,
##  ring_anchor, glyph, glyph_night].
##
## SIX GAUGES: the day dial, large, plus GDD section 5's five stats, small.
##
## The dial is first and largest and is the only warm one. Rule 3 turned into the
## design: the biggest thing on the interface is the only warm thing on it, and
## it is sunlight, which in this game is heat. It drains as the day runs down and
## goes out at nightfall.
##
## FROSTBITE IS ONE READING WITH TWO SITES, not two readings and not a
## consequence of core temperature. GDD section 5: 冻伤是局部的 -- hands slow
## fire-lighting and spoil aim, feet cost speed until treated at a fire. Two
## files in data/stats, one gauge here, and the gauge shows the WORST of them
## (see Vitals) because the player acts on whichever limb is further gone.
##
## `track_weight` is the gauge hierarchy: 2.0 against 1.0 is section 6.1's
## 110-against-58 rounded to what a corner will hold without creeping toward the
## middle of the frame.
const TABLE := [
	[FROM_DAYLIGHT, &"daylight", &"", "日", "", 0, 2.0, 0.0, DIAL, &"day_sun", &"night_moon"],
	[FROM_STAT, &"core_temperature", &"", "体温", "", 1, 1.0, 110.0, RING, &"core_temperature", &""],
	[FROM_STAT, &"hunger", &"", "饥饿", "", 2, 1.0, 58.0, RING, &"hunger", &""],
	[FROM_STAT, &"thirst", &"", "口渴", "", 3, 1.0, 58.0, RING, &"thirst", &""],
	[FROM_STAT, &"fatigue", &"", "疲劳", "", 4, 1.0, 58.0, RING, &"fatigue", &""],
	[FROM_STAT, &"frostbite_hands", &"frostbite_feet", "冻伤", "", 5, 1.0, 34.0, HANDS,
		&"frostbite_hands", &""],
]

## Section 6.1's Tab ring is unchanged by any of this: 体温 110° is still its 主
## 时钟 and still nearly twice everything else, because that readout is drawn
## around the CHARACTER and the day dial has no place on it. The corner cluster's
## hierarchy is carried by `track_weight` instead, which is why the two are
## separate fields rather than one.
const RING_GAP_DEGREES := 14.0
const RING_RADIUS_RATIO := 1.6


func _initialize() -> void:
	var RowScript := load("res://src/definitions/vital_readout.gd")
	var LayoutScript := load("res://src/definitions/vital_layout.gd")

	var rows: Array[VitalReadout] = []
	for entry in TABLE:
		var row = RowScript.new()
		row.source = int(entry[0])
		row.stat = entry[1]
		row.second_stat = entry[2]
		row.label = entry[3]
		row.limb = entry[4]
		row.order = int(entry[5])
		row.track_weight = float(entry[6])
		row.ring_degrees = float(entry[7])
		row.ring_anchor = int(entry[8])
		row.glyph = entry[9]
		row.glyph_night = entry[10]
		rows.append(row)

	var layout = LayoutScript.new()
	# Annotated: `readouts` is typed, and an untyped local would hand the setter
	# an untyped Array, which it rejects by ABORTING this function with no error
	# a reader would connect to this line (briefing trap 4). The generator would
	# then save an empty layout and print success.
	var typed: Array[VitalReadout] = rows
	layout.readouts = typed
	layout.ring_gap_degrees = RING_GAP_DEGREES
	layout.ring_radius_ratio = RING_RADIUS_RATIO
	layout.warm_source = &"daylight"

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(layout, OUT_PATH)
	print("generate_vital_layout: save returned %d, %d readouts" % [error, layout.readouts.size()])

	# Read back and printed, rather than reported from TABLE -- briefing trap 9's
	# lesson: when you generate a resource in code, print what the ENGINE
	# produced and read it.
	var written := ResourceLoader.load(OUT_PATH) as VitalLayout
	if written == null:
		printerr("generate_vital_layout: the saved file does not load back")
		quit(1)
		return
	for row in written.ordered():
		print("  %d  %-18s %-6s track ×%.2f  glyph %s%s%s" % [
			row.order, row.stat, row.label, row.track_weight, row.glyph,
			" / " + row.glyph_night if row.glyph_night != &"" else "",
			"  + " + row.second_stat if row.second_stat != &"" else "",
		])
	print("  ring opening at the bottom: %.0f°" % written.ring_opening_degrees())
	quit(0 if error == OK else 1)
