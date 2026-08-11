extends SceneTree

## One-off generator for res://data/palette/color_bible.tres.
## Run: godot --headless --path <project> --script res://tools/generate_palette.gd

func _initialize() -> void:
	var ColorBibleScript := load("res://src/definitions/color_bible.gd")
	var bible = ColorBibleScript.new()

	var snow: Array[Color] = [
		Color("#8FB0D8"), Color("#7FA0C9"), Color("#748FBB"),
		Color("#6987B4"), Color("#5D7BA6"),
	]
	var structure: Array[Color] = [
		Color("#33496E"), Color("#2A3854"), Color("#1C2A45"), Color("#131C30"),
	]
	var warm: Array[Color] = [
		Color("#6E2F2E"), Color("#A05A35"), Color("#FFB257"),
	]

	bible.snow_tones = snow
	bible.structure_tones = structure
	bible.warm_tones = warm

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/palette"))
	var error := ResourceSaver.save(bible, "res://data/palette/color_bible.tres")
	print("generate_palette: save returned %d, %d colors" % [error, bible.all_colors().size()])
	quit(0 if error == OK else 1)
