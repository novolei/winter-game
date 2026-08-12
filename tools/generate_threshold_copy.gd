extends SceneTree

## Generator for res://data/ui/threshold_copy.tres -- UI design document
## section 5.2's copy table.
##
## Run: godot --headless --path <project> --script res://tools/generate_threshold_copy.gd
##
## ---------------------------------------------------------------------------
## WHY THE TABLE IS GENERATED AND NOT TYPED INTO THE .tres
## ---------------------------------------------------------------------------
## Briefing constraint 7. `entries` is a typed array, and a typed array
## serialises as `Array[ExtResource("...")]([...])` rather than as a plain list;
## hand-authoring that form is a way to spend an afternoon. It is also how the
## table gets checked: this file fails the run if two rows claim the same
## threshold, which a hand-written file would carry silently and which would make
## one of the two rows unreachable forever.
##
## ---------------------------------------------------------------------------
## THE THIRD COLUMN IS NOT DECORATION
## ---------------------------------------------------------------------------
## Section 5.2's table has three columns: the threshold, 数据里真正发生的事, and
## 浮现文案. All three are carried onto the row. The middle one is never drawn --
## it is there so that a reviewer reading a line of copy can see the mechanic it
## is supposed to describe without opening data/stats/*.tres and decoding a
## ThresholdEffect. The defect it guards against is a row whose words are good
## Chinese and describe the wrong mechanic, which no test can catch and which
## reads perfectly in review.
##
## ---------------------------------------------------------------------------
## THE COPY IS COPIED, NOT COMPOSED
## ---------------------------------------------------------------------------
## Every string below is section 5.2's, verbatim. Nothing here paraphrases: the
## design document is the acceptance standard for the words as much as for the
## pixels, and a generator that improved on a line would put the shipped text out
## of reach of the document that reviews it.

const OUT_DIR := "res://data/ui"
const OUT_PATH := "res://data/ui/threshold_copy.tres"

## [stat, threshold, what the data does, what the player is told].
## Section 5.2's table, in its order.
const TABLE := [
	[&"core_temperature", 0.50, "breath:rate ×1.25", "呼吸变快了"],
	[&"core_temperature", 0.35, "手足冻伤开始累积", "手脚开始发僵"],
	[&"core_temperature", 0.20, "breath:rate ×1.5", "牙齿在打颤"],
	[&"core_temperature", 0.15, "冻伤速率 ×2.0", "四肢正在失去知觉"],
	[&"hunger", 0.30, "core_temperature 漏失 ×1.5", "身体产不出热了"],
	[&"hunger", 0.05, "core_temperature 漏失 ×2.0", "身体在烧自己取暖"],
	[&"thirst", 0.30, "fatigue:recovery ×0.5 · vision:focus ×0.85", "眼前有些发花"],
	[&"thirst", 0.05, "fatigue:recovery ×0.0", "再怎么歇也缓不过来"],
	[&"fatigue", 0.30, "locomotion:speed ×0.85 · snow_cost ×1.35", "腿开始沉"],
	[&"fatigue", 0.10, "locomotion:speed ×0.85（叠乘）", "每一步都要想一下"],
	[&"fatigue", 0.02, "locomotion:run_speed ×0.0", "跑不动了"],
	[&"frostbite_hands", 0.50, "ignition:speed ×0.6 · aim:steadiness ×0.7", "手指不听使唤了"],
	[&"frostbite_hands", 0.20, "ignition:speed ×0.5 · aim:steadiness ×0.6", "手已经不算是手了"],
	[&"frostbite_feet", 0.50, "fatigue 漏失 ×1.25 · locomotion:speed ×0.85", "脚底没有知觉"],
	[&"frostbite_feet", 0.20, "locomotion:speed ×0.8", "每一步都踩在别人的脚上"],
]


func _initialize() -> void:
	var RowScript := load("res://src/definitions/threshold_copy.gd")
	var MapScript := load("res://src/definitions/threshold_copy_map.gd")

	var rows: Array[ThresholdCopy] = []
	var seen := {}
	var duplicates: Array[String] = []
	for row in TABLE:
		var key := "%s|%.4f" % [row[0], row[1]]
		if seen.has(key):
			duplicates.append(key)
			continue
		seen[key] = true
		var entry = RowScript.new()
		entry.stat = row[0]
		entry.threshold = float(row[1])
		entry.effect = row[2]
		entry.text = row[3]
		rows.append(entry)

	if not duplicates.is_empty():
		# Two rows for one threshold means one of them can never fire, and
		# ThresholdCopyMap.row_for() would return whichever came first with no
		# way to tell from the outside.
		printerr("generate_threshold_copy: duplicate rows: %s" % ", ".join(duplicates))
		quit(1)
		return

	var map = MapScript.new()
	# Annotated, because `entries` is a typed array and an untyped local would
	# hand the setter an untyped Array -- which it rejects, aborting this
	# function outright with no error a reader would connect to this line
	# (briefing trap 4). The generator would then save an EMPTY table and print
	# success.
	var typed: Array[ThresholdCopy] = rows
	map.entries = typed

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(map, OUT_PATH)
	print("generate_threshold_copy: save returned %d, %d rows" % [error, map.entries.size()])
	# Printed back out of the saved resource rather than out of TABLE, because
	# the thing worth checking by eye is what actually reached the file --
	# briefing trap 9's lesson: read what the engine produced.
	var written := ResourceLoader.load(OUT_PATH) as ThresholdCopyMap
	if written == null:
		printerr("generate_threshold_copy: the saved file does not load back")
		quit(1)
		return
	for entry in written.entries:
		print("  %-18s %.2f  %s" % [entry.stat, entry.threshold, entry.text])
	quit(0 if error == OK else 1)
