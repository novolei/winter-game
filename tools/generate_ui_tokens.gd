extends SceneTree

## Generator for res://data/ui/tokens.tres -- the design tokens of the UI design
## document, sections 2.1 through 2.4.
##
## Run: godot --headless --path <project> --script res://tools/generate_ui_tokens.gd
##
## ---------------------------------------------------------------------------
## THIS GENERATOR HOLDS NO COLOUR OF ITS OWN
## ---------------------------------------------------------------------------
## tools/generate_palette.gd is the ONE place in the project where a hex literal
## is authored, and briefing constraint 6 is only meaningful while that stays
## true. So this file LOADS color_bible.tres and indexes into it. Writing
## `Color("#8FB0D8")` here would compile, look tidy, and quietly create a second
## source of truth that could disagree with the first.
##
## The index-to-token mapping below IS the design decision -- section 2.1's table
## -- and it is asserted independently in tests/unit/test_ui_tokens.gd, so a
## finger slip here fails the suite rather than shipping.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const OUT_DIR := "res://data/ui"
const OUT_PATH := "res://data/ui/tokens.tres"

const FONT_DIR := "res://assets/fonts/"

func _initialize() -> void:
	var bible = load(PALETTE_PATH)
	if bible == null:
		printerr("generate_ui_tokens: no palette at %s" % PALETTE_PATH)
		quit(1)
		return
	if bible.snow_tones.size() < 5 or bible.structure_tones.size() < 4 or bible.warm_tones.size() < 3:
		printerr("generate_ui_tokens: palette is short -- 5 snow / 4 structure / 3 warm expected")
		quit(1)
		return

	var UITokensScript := load("res://src/definitions/ui_tokens.gd")
	var tokens = UITokensScript.new()

	# Section 2.1's table, read out of the palette rather than written down.
	tokens.ink_primary = bible.snow_tones[0]      # #8FB0D8 snow, brightest
	tokens.ink_secondary = bible.snow_tones[2]    # #748FBB snow, mid
	tokens.ink_muted = bible.snow_tones[4]        # #667890 snow, darkest
	tokens.line_hairline = bible.structure_tones[0]  # #33496E structure, lit
	tokens.line_deep = bible.structure_tones[2]      # #1C2A45 structure, dark
	tokens.scrim_veil = bible.structure_tones[3]     # #131C30 structure, darkest
	tokens.life_warm = bible.warm_tones[2]        # #FFB257 amber -- heat exists
	tokens.life_ember = bible.warm_tones[1]       # #A05A35 rust -- heat is going
	tokens.alarm_blood = bible.warm_tones[0]      # #6E2F2E deep red -- damage only

	# Typed-array property, so the local must be annotated or the setter rejects
	# an untyped literal and ABORTS this function mid-way (briefing trap 4). The
	# generator would then save a half-built resource and report success.
	var ladder: PackedFloat32Array = PackedFloat32Array([1.0, 0.72, 0.48, 0.24, 0.12])
	tokens.opacity_steps = ladder

	# Section 2.3
	tokens.reference_height = 1080
	tokens.grid_unit = 8
	tokens.edge_fraction = 0.075

	# Section 2.4
	tokens.bloom_seconds = 0.20
	tokens.bloom_heavy_seconds = 0.32
	tokens.hold_seconds = 2.00
	tokens.drift_seconds = 0.90
	tokens.drift_fast_seconds = 0.40
	tokens.drift_long_seconds = 1.60
	tokens.breathe_seconds = 4.00        # 0.25 Hz
	tokens.breathe_amplitude = 0.14
	tokens.shiver_hertz = 12.0
	tokens.shiver_pixels = 1.0
	tokens.ripple_seconds = 0.30
	tokens.cold_snap_scale = 1.40

	# Section 2.2. Latin first in each pair -- see UIFonts for why the order is
	# load-bearing rather than cosmetic.
	tokens.display_latin_path = FONT_DIR + "CormorantGaramond-VF.ttf"
	tokens.display_latin_weight = 300
	tokens.display_cjk_path = FONT_DIR + "NotoSerifSC-VF.otf"
	tokens.display_cjk_weight = 200
	tokens.interface_latin_path = FONT_DIR + "Inter-VF.ttf"
	tokens.interface_latin_weight = 300
	tokens.interface_cjk_path = FONT_DIR + "NotoSansSC-VF.otf"
	tokens.interface_cjk_weight = 300
	tokens.instrument_path = FONT_DIR + "IBMPlexMono-Light.ttf"

	# Section 3's breath layer, which owns no background and may have no plate
	# under it. THESE ARE SECTION 5.9'S OWN TWO NUMBERS: the document already made
	# this call for the same layer's world-space form -- 一行字立在山谷里，背后是一
	# 整片 62% 亮度的雪，没有任何底 -- and moved that type to 600 CJK / 500 Latin.
	# The screen-space half of the layer stands on the same snow, so it is the same
	# decision rather than a new one.
	#
	# Confirmed by measurement rather than assumed: tools/measure_type_weight.tscn
	# swept the axis at the shipped Body 17 on lit `pale_day` snow, and 600 is
	# where the threshold note's sentence delivers 7.03 : 1 at its stroke core
	# against a nominal 8.09, and the time prompt's word 4.10 against its own
	# ceiling of 4.36. 700 buys 0.4 more and costs the family its character; 300
	# reaches the ink on no pixel at all. The sweep is in
	# .superpowers/sdd/wave3/task-w3-type-weight-report.md and the relationships
	# the suite holds are in tests/unit/test_breath_type_weight.gd.
	tokens.breath_cjk_weight = 600
	tokens.breath_latin_weight = 500

	var missing: Array[String] = []
	for path in tokens.font_paths():
		if not FileAccess.file_exists(path):
			missing.append(path)
	if not missing.is_empty():
		# Loud, and it does not stop the write: the tokens are still correct and
		# the suite's own font test is the gate. A generator that refused to run
		# because an art asset had not landed yet would block the wrong person.
		printerr("generate_ui_tokens: font file(s) not on disk: %s" % ", ".join(missing))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(tokens, OUT_PATH)
	print("generate_ui_tokens: save returned %d, %d colour tokens, %d fonts"
		% [error, tokens.colour_token_names().size(), tokens.font_paths().size()])
	quit(0 if error == OK else 1)
