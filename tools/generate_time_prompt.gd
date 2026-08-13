extends SceneTree

## Generator for res://data/ui/time_prompt.tres -- UI design document section
## 5.10's periodic time prompt.
##
## Run: godot --headless --path <project> --script res://tools/generate_time_prompt.gd

const OUT_DIR := "res://data/ui"
const OUT_PATH := "res://data/ui/time_prompt.tres"


func _initialize() -> void:
	var Script := load("res://src/definitions/time_prompt_data.gd")
	var data = Script.new()

	# The owner's own example reads 夜晚 4.
	data.day_label = "白天"
	data.night_label = "夜晚"

	# THE OWNER'S RULING: 最好加上 Day 不需要说第几天.
	#
	# Shipped bare, the line was `夜晚 1`, and nothing in it says whether the 1 is
	# the day or an index of the night -- which is half of 信息不够清晰. `Day` is
	# the label he chose, in preference to the 第 N 日 form, which he ruled out by
	# name.
	#
	# NO DENOMINATOR, and no room left for one. `Day 3 / 7` is a countdown, and
	# that is a dramatic decision about a game whose seventh day is the point; the
	# owner declined it. See TimePromptData.day_word.
	#
	# A Latin word in a Chinese interface is a deviation from section 5.10's own
	# copy (夜晚 4), and it is recorded as one in the document rather than made
	# quietly. Section 2.2 provisions a Latin face for every family and gives a
	# rule for mixing the two on one line, so the document permits the shape even
	# though this section did not ask for it.
	data.day_word = "Day"

	data.hours_between = 4.0
	data.hours_per_day = 24.0

	# EIGHT SECONDS, and the exit that goes with it is section 5.4's 散·长.
	#
	# The owner asked for the dwell to double. At four seconds the prompt was
	# readable; at eight it can be read, looked away from, and looked back at,
	# which is what a deadline you are planning against actually needs (GDD
	# section 3's NIGHTFALL = GO HOME).
	#
	# What doubling costs is measured rather than assumed. The period is a
	# twenty-fourth of the authored day times four -- 150 s on every day the
	# schedule currently authors -- so the whole envelope, 0.32 + 8.00 + 1.60,
	# occupies 6.6% of the run against 3.5% before. tools/measure_prompt_traffic.gd
	# is what says so, and it also says how often that lands on top of a section
	# 5.2 note.
	data.hold_seconds = 8.0

	data.arc_degrees = 60.0
	# CHOSEN AGAINST THE BREATHING BORDER, not for looks. At 60 degrees an arc's
	# chord equals its radius, so this is also the radius, and the sagitta is
	# 0.134 of it. The whole element -- apex clearance, arc, icons, gap, one line
	# of Body -- has to fit inside 7.5% of the short edge (81 design px), and
	# these numbers land it at about 74. A wider arc is a deeper curve, and the
	# depth is what runs out of border first.
	#
	# A multiple of the 8 px grid, section 2.3.
	data.arc_width_design_px = 192.0
	data.icon_design_px = 20.0
	data.gap_design_px = 8.0

	data.label_design_px = 17.0
	data.label_tracking_em = 0.08

	data.day_glyph = &"day_sun"
	data.night_glyph = &"night_moon"

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(data, OUT_PATH)
	print("generate_time_prompt: save returned %d" % error)

	# Read back and printed rather than reported from the values above -- briefing
	# trap 9: when you generate a resource in code, print what the ENGINE
	# produced and read it.
	var written := ResourceLoader.load(OUT_PATH) as TimePromptData
	if written == null:
		printerr("generate_time_prompt: the saved file does not load back")
		quit(1)
		return
	print("  every %.0f of %.0f hours, held %.1f s" % [
		written.hours_between, written.hours_per_day, written.hold_seconds])
	print("  arc %.0f° over %.0f design px, icons %.0f px: %s / %s" % [
		written.arc_degrees, written.arc_width_design_px, written.icon_design_px,
		written.night_glyph, written.day_glyph])
	print("  labels: %s / %s" % [written.day_label, written.night_label])
	quit(0 if error == OK else 1)
