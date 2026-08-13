extends TestCase

## UI design document section 5.2's note, and the one question its colours have
## to answer: can the player see it.
##
## ---------------------------------------------------------------------------
## WHY THIS FILE EXISTS
## ---------------------------------------------------------------------------
## Section 5.2's own table gives the note `ink/primary`, which is `snow_tones[0]`
## -- the palette entry the snow itself is made of. Captured through
## tools/capture_threshold_note.tscn, on `pale_day`, in the real scene:
##
##   ground under the note   0.5766   (#A6CBF9, the lit snow band)
##   the ink in the frame    0.4185   (#8FB0D8, exactly the authored hex)
##   contrast                1.34 : 1
##
## and on the shade band it is WORSE -- 1.12 : 1 -- because `ink/primary` sits
## INSIDE the snow's own tonal range rather than above or below it. There is no
## snow at any time of day that it separates from.
##
## The numbers below are those measurements, hardcoded on purpose. Reading the
## ground back out of the thing being tested would make every assertion here
## true by construction; the whole point is that these came off a frame.
##
## ---------------------------------------------------------------------------
## THE FLOORS, AND WHY THEY ARE NOT 4.5
## ---------------------------------------------------------------------------
## WCAG's 4.5 : 1 for body text is not reachable on this palette at night and
## saying otherwise would be a test that has to be weakened later. The light half
## of these twelve IS the snow (1.00 to 2.00 : 1 against it, measured twice this
## project), so separation on a bright ground comes from being DARK, and on a
## dark ground the ceiling is what `ink/primary` can do against it.
##
## So the floors asserted are the palette's own ceilings: 3.5 : 1 on any ground
## bright enough to take the dark ink, and 2.5 : 1 on a night ground.

const TOKENS_PATH := "res://data/ui/tokens.tres"
const LAYOUT_PATH := "res://data/ui/vital_layout.tres"
const PRESET_DIRECTORY := "res://data/lighting"

## Measured through tools/capture_threshold_note.tscn at 1600x1000, sampling the
## frame under the element's own rect. `offset` is where the man was standing,
## because the note keeps a fixed place on the SCREEN and the only way to change
## the ground beneath it is to change the shot.
##
##   name              preset      offset     ground
const MEASURED_GROUNDS := [
	["bright day snow", "pale_day", "8,0", 0.5766],
	["the shade band", "pale_day", "0,-10", 0.3851],
	["a bright weather event", "whiteout", "8,0", 0.4616],
	["dusk", "nightfall", "8,0", 0.2269],
	["a night ground", "deep_night", "0,0", 0.1156],
]

const BRIGHT_GROUND_FLOOR := 3.5
const NIGHT_GROUND_FLOOR := 2.5

## How much of the better ink's contrast the deliberate bias toward a light ink
## on a dark frame is allowed to spend. The bias is a real argument -- a
## near-black stroke on a night frame competes with every shadow in the picture
## while a pale one competes with nothing -- but an argument with no bound on it
## is how a crossover walks up into the daylight.
const MIN_SHARE_OF_BEST := 0.85

var _tokens: UITokens = null
var _layout: VitalLayout = null


func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout


## WCAG relative luminance, written here rather than asked of the subject. A
## contrast test that borrowed the shipped code's own arithmetic would agree with
## it however wrong both were.
func _luminance(colour: Color) -> float:
	var out := 0.0
	var weights := [0.2126, 0.7152, 0.0722]
	var channels := [colour.r, colour.g, colour.b]
	for index in range(3):
		var c: float = clampf(float(channels[index]), 0.0, 1.0)
		var linear: float = c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4)
		out += float(weights[index]) * linear
	return out


func _contrast(colour: Color, ground: float) -> float:
	var ink := _luminance(colour)
	return (maxf(ink, ground) + 0.05) / (minf(ink, ground) + 0.05)


func _note(fraction: float, depleted := false, ground := 0.5) -> ThresholdNote:
	var note := ThresholdNote.new()
	note.build(_tokens, null, _layout.row_for(&"core_temperature"), "呼吸变快了",
		fraction, depleted, false)
	note.set_ground(ground)
	return note


# --- the defect ---------------------------------------------------------------

## The measurement that made this file necessary, asserted from the palette so
## that it cannot quietly stop being true. `ink/primary` IS `snow_tones[0]`.
func test_the_documents_own_ink_is_invisible_on_every_snow_ground() -> void:
	for row in MEASURED_GROUNDS:
		var ground := float(row[3])
		if ground < UIInk.DARK_GROUND_BELOW:
			continue
		assert_true(_contrast(_tokens.ink_primary, ground) < 2.0,
			"%s: section 5.2's own ink measures %.2f:1 -- if this now passes 2:1 the "
			% [row[0], _contrast(_tokens.ink_primary, ground)]
			+ "palette moved and this whole file should be re-measured")


# --- the fix ------------------------------------------------------------------

func test_on_a_bright_ground_the_note_takes_the_dark_ink() -> void:
	var note := _note(0.5, false, 0.5766)
	assert_true(note.ink() == _tokens.line_deep,
		"on lit snow the light ink IS the snow")
	note.free()


func test_on_a_dark_ground_the_note_is_the_document_unchanged() -> void:
	var note := _note(0.5, false, 0.1156)
	assert_true(note.ink() == _tokens.ink_primary,
		"section 5.2's own colour, which is right wherever it can be seen")
	note.free()


## The icon says WHICH reading, the arc says how far gone it is, and the line
## says what it means. Three parts of one statement: if the ground can move one
## of them and not the others the note comes apart.
func test_the_icon_the_arc_and_the_words_are_one_colour() -> void:
	for ground in [0.5766, 0.1156]:
		for fraction in [0.5, 0.2, 0.1]:
			var note := _note(fraction, false, ground)
			assert_true(note.words_ink() == note.ink(),
				"ground %.4f, fraction %.2f: the copy left the mark behind" % [ground, fraction])
			assert_not_null(note.arc())
			if note.arc() != null:
				assert_true(note.arc().reading_colour() == note.ink(),
					"ground %.4f, fraction %.2f: the arc and the icon disagree"
					% [ground, fraction])
			note.free()


## Section 5.2: 濒危（<0.15）转 `alarm/blood`. It is the palette's darkest warm
## entry and it reads on snow, so on a bright ground the document stands.
func test_a_reading_in_trouble_on_snow_is_still_alarm_blood() -> void:
	var note := _note(0.10, false, 0.5766)
	assert_true(note.ink() == _tokens.alarm_blood)
	assert_true(_contrast(note.ink(), 0.5766) > 4.5,
		"alarm/blood on lit snow")
	note.free()


## AND THE ONE PLACE SECTION 5.2 CANNOT BE FOLLOWED.
##
## `alarm/blood` is #6E2F2E, luminance 0.055. Against the measured night ground
## it is 1.57 : 1 -- so on the one ground where a man is most likely to be
## freezing, the document's alarm colour is the least visible ink in the note.
## There is no light red in these twelve and rule 3 forbids reaching for a warm
## one, so urgency falls back to the two channels section 5.2 already gives it:
## weight, and 颤.
func test_a_reading_in_trouble_at_night_keeps_the_legible_ink_and_gains_its_weight() -> void:
	assert_true(_contrast(_tokens.alarm_blood, 0.1156) < 2.0,
		"if alarm/blood ever clears 2:1 on a night ground this rule can go")
	var note := _note(0.10, false, 0.1156)
	assert_true(note.ink() == _tokens.ink_primary,
		"a warning nobody can see is not a warning")
	assert_true(
		VitalTone.fill_design_px(VitalTone.State.CRITICAL)
			> VitalTone.fill_design_px(VitalTone.State.STEADY),
		"with the colour spent, weight has to still be carrying it")
	assert_true(VitalTone.shivers(VitalTone.State.CRITICAL),
		"and so does 颤")
	note.free()


# --- the grounds it must survive ----------------------------------------------

## Every ground in MEASURED_GROUNDS, against the ink the rule picks for it.
func test_the_note_clears_the_palette_ceiling_on_every_ground_measured() -> void:
	for row in MEASURED_GROUNDS:
		var ground := float(row[3])
		var note := _note(0.5, false, ground)
		var ratio := _contrast(note.ink(), ground)
		var floor_here := (
			NIGHT_GROUND_FLOOR if ground < UIInk.DARK_GROUND_BELOW else BRIGHT_GROUND_FLOOR)
		assert_true(ratio >= floor_here,
			"%s (ground %.4f): %.2f:1, under the %.1f:1 floor" % [
				row[0], ground, ratio, floor_here])
		note.free()


## THE CROSSOVER IS A RELATIONSHIP, NOT A CONSTANT.
##
## Three measurements bound it and all three are asserted, so that a palette
## change or a preset retune fails HERE, naming the bound it broke, rather than
## in a frame nobody thought to capture. This project has now recorded that
## failure four times (a cooldown against a clip's length, a warm quota against a
## frame, a chord floor against a waist, and this).
func test_the_crossover_is_bounded_from_both_sides_by_measurements() -> void:
	var light := _luminance(_tokens.ink_primary)
	var dark := _luminance(_tokens.line_deep)
	# (light + .05) / (g + .05) == (g + .05) / (dark + .05)
	var equal_at := sqrt((light + 0.05) * (dark + 0.05)) - 0.05
	assert_true(UIInk.DARK_GROUND_BELOW > equal_at,
		"the crossover (%.4f) must sit above the arithmetic one (%.4f), or a dark "
			% [UIInk.DARK_GROUND_BELOW, equal_at]
		+ "frame is handed the ink that reads worse on it")

	# The estimator is inaccurate at the dark end -- it puts `deep_night` at 0.148
	# where the frame measures 0.1156 -- so the crossover has to clear the
	# ESTIMATE, not the measurement, or a genuinely dark frame flips.
	var night := ResourceLoader.load("%s/deep_night.tres" % PRESET_DIRECTORY) as LightingPreset
	assert_not_null(night)
	if night != null:
		assert_true(UIInk.DARK_GROUND_BELOW > UIInk.ground_for(night),
			"the crossover (%.4f) must sit above what ground_for() estimates for the "
				% UIInk.DARK_GROUND_BELOW
			+ "darkest authored preset (%.4f)" % UIInk.ground_for(night))

	# And below the darkest ground a real frame produced that reads better dark.
	for row in MEASURED_GROUNDS:
		var ground := float(row[3])
		if _contrast(_tokens.line_deep, ground) <= _contrast(_tokens.ink_primary, ground):
			continue
		assert_true(UIInk.DARK_GROUND_BELOW < ground,
			"%s measured %.4f and reads better in the dark ink (%.2f:1 against "
				% [row[0], ground, _contrast(_tokens.line_deep, ground)]
			+ "%.2f:1), so the crossover must be below it" % _contrast(_tokens.ink_primary, ground))


## The estimate the choice is made from, against the frames it was fitted to.
## Kept in step with TimeArc's, because two crossovers in one interface is two
## elements that will one day disagree about what a dark scene is.
func test_the_note_and_the_time_prompt_read_the_same_ground() -> void:
	assert_almost_eq(UIInk.DARK_GROUND_BELOW, TimeArc.DARK_GROUND_BELOW, 0.0001)
	for ambient in [1.5, 2.3, 2.9, 3.2]:
		var preset := LightingPreset.new()
		preset.ambient_energy = ambient
		assert_almost_eq(UIInk.ground_for(preset), TimeArc.ground_for(preset), 0.0001,
			"ambient %.1f" % ambient)


## Every authored preset gets an ink, and never the worse of the two by more than
## the bias is allowed to cost.
##
## NOT a flat contrast floor, and the difference matters: the ground fed to this
## rule in the running game is always the ESTIMATE, which is known to be wrong by
## up to 0.12. Asserting an absolute ratio against a number that is wrong would be
## the project's own recorded failure -- 正确的测量，回答错误的问题. What the
## estimate is actually responsible for is landing on the right SIDE, so what is
## asserted is the chosen ink against the best either ink could have done there.
func test_every_authored_preset_takes_the_best_ink_the_palette_has_for_it() -> void:
	var directory := DirAccess.open(PRESET_DIRECTORY)
	assert_not_null(directory)
	if directory == null:
		return
	var seen := 0
	for file in directory.get_files():
		# .import and .uid sidecars are entries in this listing too (trap 17), so
		# the suffix is allowlisted rather than the known bad ones excluded.
		if not file.ends_with(".tres"):
			continue
		seen += 1
		var preset := ResourceLoader.load("%s/%s" % [PRESET_DIRECTORY, file]) as LightingPreset
		assert_not_null(preset, file)
		if preset == null:
			continue
		var ground := UIInk.ground_for(preset)
		assert_true(ground >= 0.0 and ground <= 1.0, "%s: ground %.4f" % [file, ground])
		var best := maxf(
			_contrast(_tokens.ink_primary, ground), _contrast(_tokens.line_deep, ground))
		assert_true(best >= NIGHT_GROUND_FLOOR,
			"%s (ground %.4f): the palette's own best is %.2f:1, so no choice made "
				% [file, ground, best]
			+ "here can save it")
		var note := _note(0.5, false, ground)
		assert_true(_contrast(note.ink(), ground) >= best * MIN_SHARE_OF_BEST,
			"%s (ground %.4f): chose %.2f:1 where %.2f:1 was available"
				% [file, ground, _contrast(note.ink(), ground), best])
		note.free()
	assert_true(seen >= 6, "expected the six authored presets, found %d" % seen)


# --- the rules it still has to keep -------------------------------------------

## Constraint 6: every colour is one of the twelve in the colour bible. A ground
## conditional that synthesised a value would be a thirteenth colour, which is
## what the deleted night lift was.
func test_every_ink_the_note_can_draw_is_one_of_the_twelve() -> void:
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres")
	assert_not_null(palette)
	if palette == null:
		return
	var legal: Array[Color] = []
	for group in [palette.snow_tones, palette.structure_tones, palette.warm_tones]:
		for colour in group:
			legal.append(colour)
	for ground in [0.0, 0.1156, 0.2269, 0.3851, 0.4616, 0.5766, 1.0]:
		for fraction in [1.0, 0.5, 0.2, 0.1, 0.0]:
			var note := _note(fraction, fraction <= 0.0, ground)
			for ink in [note.ink(), note.words_ink()]:
				var found := false
				for colour in legal:
					if colour.is_equal_approx(ink):
						found = true
				assert_true(found,
					"ground %.4f fraction %.2f drew %s, which is not in the twelve"
						% [ground, fraction, ink.to_html(false)])
			note.free()


## RULE 3. 暖色在 UI 里只有一个含义：热量的存在. `alarm/blood` is the stated
## exception and is 仅 damage and death; nothing else warm may appear, on any
## ground, however hard the ground is to read against.
func test_no_ground_ever_makes_the_note_reach_for_a_warm_ink() -> void:
	for ground in [0.0, 0.1156, 0.2269, 0.3851, 0.4616, 0.5766, 1.0]:
		for fraction in [1.0, 0.5, 0.2, 0.1]:
			var note := _note(fraction, false, ground)
			for ink in [note.ink(), note.words_ink()]:
				assert_true(ink != _tokens.life_warm and ink != _tokens.life_ember,
					"ground %.4f fraction %.2f reached for the colour of heat" % [ground, fraction])
			note.free()


## Rule 1: 没有矩形. The answer to a contrast problem is not a plate behind the
## text, and this is the guard on that -- read off disk, because a panel added
## later would be a draw call nobody here would think to look for.
func test_the_contrast_is_solved_in_the_ink_and_not_with_a_plate() -> void:
	var file := FileAccess.open("res://src/ui/threshold_note.gd", FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var source := file.get_as_text()
	file.close()
	for forbidden in ["draw_rect(", "draw_style_box(", "StyleBox", "ColorRect"]:
		assert_false(source.contains(forbidden),
			"`%s` is a plate, and rule 1 does not allow one" % forbidden)
