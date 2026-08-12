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

	data.hours_between = 4.0
	data.hours_per_day = 24.0
	data.hold_seconds = 4.0

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
