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

## [stat, label, limb, order, track_weight, ring_degrees, ring_anchor, glyph].
## Clockwise from the top, which is section 6.1's 段序.
##
## `track_weight` doubles as the gauge hierarchy in the corner cluster: the heat
## reading is the large ring and everything else is small. 1.4 against 1.0 is
## section 6.1's 110-against-58 rounded to what fits a corner without creeping
## toward the middle of the frame.
##
## TWO OF THE GLYPHS ARE HONEST PLACEHOLDERS. Warmth, hunger, thirst and fatigue
## have settled pictographic traditions and the strokes below are recognisable
## instances of them. FROSTBITE HAS NO SUCH TRADITION -- there is no drawing
## everyone reads as "this limb is freezing" -- so the two limb readings carry a
## branching crystal, which says the material and the place but not the injury.
## That is a design question rather than a drawing one and it is flagged as open
## rather than guessed at.
const TABLE := [
	[&"core_temperature", "体温", "", 0, 1.4, 110.0, RING, &"heat"],
	[&"hunger", "饥饿", "", 1, 1.0, 58.0, RING, &"hunger"],
	[&"thirst", "口渴", "", 2, 1.0, 58.0, RING, &"thirst"],
	[&"fatigue", "疲劳", "", 3, 1.0, 58.0, RING, &"fatigue"],
	[&"frostbite_hands", "冻伤", "手", 4, 0.72, 34.0, HANDS, &"unresolved"],
	[&"frostbite_feet", "冻伤", "足", 5, 0.72, 34.0, FEET, &"unresolved"],
]

const RING_GAP_DEGREES := 14.0
const RING_RADIUS_RATIO := 1.6


func _initialize() -> void:
	var RowScript := load("res://src/definitions/vital_readout.gd")
	var LayoutScript := load("res://src/definitions/vital_layout.gd")

	var rows: Array[VitalReadout] = []
	for entry in TABLE:
		var row = RowScript.new()
		row.stat = entry[0]
		row.label = entry[1]
		row.limb = entry[2]
		row.order = int(entry[3])
		row.track_weight = float(entry[4])
		row.ring_degrees = float(entry[5])
		row.ring_anchor = int(entry[6])
		row.glyph = entry[7]
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
		print("  %d  %-18s %s%s  track ×%.2f  ring %.0f° anchor %d  glyph %s" % [
			row.order, row.stat, row.label, row.limb, row.track_weight,
			row.ring_degrees, row.ring_anchor, row.glyph,
		])
	print("  ring opening at the bottom: %.0f°" % written.ring_opening_degrees())
	quit(0 if error == OK else 1)
