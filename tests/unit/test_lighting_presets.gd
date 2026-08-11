extends TestCase

## The six looks, as data on disk. Art Bible section 4.2.
##
## Each preset is a dramatic beat as much as a light setup, and every one of them
## is named by a day in GDD section 4 -- so these are two gates in one file: the
## six exist and are internally coherent, and the seven days point at six that
## exist.
##
## ---------------------------------------------------------------------------
## WHAT A PRESET CAN AND CANNOT MOVE -- read this before tuning one
## ---------------------------------------------------------------------------
## There are two lighting rigs on screen and a preset carries a row for each.
##
##   THE WORLD is on the two cel shaders, which take their colour from the
##   palette outright and read nothing from a light but ATTENUATION -- the shadow
##   term. Sun energy and sun colour reach it NOT AT ALL, and neither does
##   ambient: both shaders declare `ambient_light_disabled`. What does reach it
##   is the tonemap exposure, the fog, the glow and whether the sun casts.
##
##   THE CHARACTER is the one thing drawn with a stock StandardMaterial3D. He is
##   lit by the sun's energy and colour, by his own cull-masked key light, and by
##   the Environment's ambient -- which reaches nothing else in the frame.
##
## So `ambient_energy` and `sun_energy` are a CHARACTER control and
## `tonemap_exposure` is a WORLD control, and a preset that moves one without the
## other moves half the picture. The two that move both together are the exposure
## and the fog. test_the_character_never_outruns_the_world_he_stands_in is that
## rule as a gate.

const PRESET_DIRECTORY := "res://data/lighting"
const SCHEDULE_DIRECTORY := "res://data/schedule"
const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Art Bible section 4.2, in the order of its own table.
const EXPECTED := {
	&"flat": "FLAT",
	&"nightfall": "NIGHTFALL",
	&"deep_night": "DEEP NIGHT",
	&"whiteout": "WHITEOUT",
	&"sunrise": "SUNRISE",
	&"pale_day": "PALE DAY",
}

## The elevation is not a preset's to move. Shadow length is height over
## tan(elevation), and the derivative of that is savage down here: at 11 degrees
## a centimetre of vertical movement on the character became six centimetres of
## shadow and the walk lurched. 21.5 was measured and chosen. A preset may vary
## colour, energy, fog and ambient freely; if one ever genuinely needs a
## different sun height, this constant is the conversation.
const TUNED_SUN_ELEVATION := 21.5

func _load_presets() -> Dictionary:
	var presets := {}
	var dir := DirAccess.open(PRESET_DIRECTORY)
	if dir == null:
		return presets
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var preset = ResourceLoader.load(
			PRESET_DIRECTORY.path_join(file_name), "", ResourceLoader.CACHE_MODE_IGNORE
		)
		if preset is LightingPreset:
			presets[file_name.trim_suffix(".tres")] = preset
	return presets

## Linear luminance of the light the ambient actually puts on the character --
## the same arithmetic tests/art/test_character_lighting.gd does on the built
## Environment, done here on the authored value.
func _fill_luma(preset) -> float:
	var linear: Color = preset.ambient_color.srgb_to_linear()
	var energy: float = preset.ambient_energy
	return (0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b) * energy

# --- the six exist ----------------------------------------------------------

func test_the_six_presets_of_the_art_bible_all_ship() -> void:
	var presets := _load_presets()
	assert_eq(presets.size(), 6, "Art Bible section 4.2 names exactly six presets")
	for id in EXPECTED:
		assert_true(presets.has(String(id)), "no res://data/lighting/%s.tres" % id)

func test_every_file_declares_the_id_it_is_named_after() -> void:
	var presets := _load_presets()
	for name in presets:
		assert_eq(
			presets[name].id, StringName(name),
			"%s.tres declares id '%s'" % [name, presets[name].id]
		)

func test_every_preset_carries_its_subtitle_from_the_art_bible() -> void:
	var presets := _load_presets()
	for id in EXPECTED:
		if not presets.has(String(id)):
			continue
		assert_eq(
			presets[String(id)].display_name, EXPECTED[id],
			"%s is named '%s' in Art Bible section 4.2" % [id, EXPECTED[id]]
		)

# --- what must not move -----------------------------------------------------

## The one number a preset may not have an opinion about. See TUNED_SUN_ELEVATION.
func test_no_preset_moves_the_sun_off_its_tuned_elevation() -> void:
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		assert_almost_eq(
			presets[name].sun_angle_degrees, TUNED_SUN_ELEVATION, 0.001,
			"%s puts the sun at %.1f degrees; shadow length is height/tan(elevation) and "
				% [name, presets[name].sun_angle_degrees]
				+ "moving it lower makes every step lurch"
		)

## THE CEL BAND, PINNED TO WHAT THE WORLD ACTUALLY SHIPS WITH.
##
## `cel_band_threshold` is the slope at which snow turns dark, and it is
## authored on every preset but not yet wired to the shaders -- TerrainRenderer
## and CelPainter set the uniform once at startup from their own exports. The
## value in TerrainRenderer was retuned to 0.12 against the drift profile
## (measured: 79% of the establishing frame lit before, 97% after), and the
## daylight presets have to carry the same number.
##
## Otherwise the day the wiring lands, PALE DAY silently changes -- a look
## nobody touched, moved by a commit about plumbing. The dark presets are
## deliberately above it, and that is the whole authored intent of the field:
## more of the world falls into the shadow band as the light goes.
func test_the_daylight_presets_carry_the_band_the_terrain_is_tuned_to() -> void:
	var renderer := TerrainRenderer.new()
	var tuned: float = renderer.band_threshold
	# MeshInstance3D is a Node (briefing constraint 2), and _ready() never ran.
	renderer.free()
	var presets := _load_presets()
	for name in ["flat", "pale_day"]:
		if not presets.has(name):
			continue
		assert_almost_eq(
			presets[name].cel_band_threshold, tuned, 0.001,
			"%s asks for a band of %.3f but the terrain ships at %.3f, so wiring the "
				% [name, presets[name].cel_band_threshold, tuned]
				+ "presets up would move a look nobody touched"
		)
	for name in ["nightfall", "deep_night", "whiteout"]:
		if not presets.has(name):
			continue
		assert_true(
			presets[name].cel_band_threshold > tuned,
			"%s does not put more of the world into the shadow band than daylight does" % name
		)

## Rule 9: nothing in the frame may be a colour that is not in the twelve. Fog
## lands on every surface at once, so an off-palette fog colour pulls the WHOLE
## frame off-palette -- and no art gate would see it, because they scan meshes
## and materials, and this is a float and a colour on a Resource.
func test_every_fog_colour_is_a_palette_tone() -> void:
	var bible = ResourceLoader.load(PALETTE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(bible, "the palette asset must exist")
	if bible == null:
		return
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		assert_true(
			bible.contains(presets[name].fog_color),
			"%s fogs the frame with #%s, which is not in the palette"
				% [name, presets[name].fog_color.to_html(false)]
		)

## The sun's colour reaches the character and nothing else -- the world's cel
## shaders ignore LIGHT_COLOR outright -- but it is still a colour in the frame,
## so it comes out of the twelve like everything else.
func test_every_sun_colour_is_a_palette_tone() -> void:
	var bible = ResourceLoader.load(PALETTE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bible == null:
		return
	var presets := _load_presets()
	for name in presets:
		assert_true(
			bible.contains(presets[name].sun_color),
			"%s lights the figure with #%s, which is not in the palette"
				% [name, presets[name].sun_color.to_html(false)]
		)

# --- the beats --------------------------------------------------------------

## "Correct and dead", and the subtitle is a specification: FLAT is the debug
## reference and never appears in play, so it carries no atmosphere at all.
## Every other preset is atmosphere.
func test_flat_is_the_reference_and_has_no_atmosphere() -> void:
	var presets := _load_presets()
	if not presets.has("flat"):
		return
	var flat = presets["flat"]
	assert_false(flat.fog_enabled, "FLAT is the reference; fog is a look")
	assert_false(flat.glow_enabled, "FLAT is the reference; bloom is a look")
	assert_true(flat.shadows_enabled, "FLAT is correct, and shadows are correct")
	assert_almost_eq(flat.warm_accent_energy, 0.0, 0.001, "FLAT holds no warm accent")

## "The storm". Whiteout is the densest air in the game by definition -- GDD
## section 4 gives day 7 能见度归零, visibility reduced to nothing.
func test_whiteout_holds_the_thickest_air_of_the_six() -> void:
	var presets := _load_presets()
	if not presets.has("whiteout"):
		return
	var whiteout = presets["whiteout"]
	for name in presets:
		if name == "whiteout":
			continue
		assert_true(
			whiteout.fog_density > presets[name].fog_density,
			"%s fogs the frame as hard as the storm does" % name
		)
	# A blizzard has no sun to cast anything. This is also what makes the day-7
	# frame read as flat and directionless when everything else has form.
	assert_false(whiteout.shadows_enabled, "a storm casts no shadows")

## The dramatic ladder, as one assertion. GDD section 4 walks the run from
## "nothing at stake" down to the dark, and the exposure is what the player
## actually experiences that as.
func test_the_presets_darken_in_the_order_the_run_uses_them() -> void:
	var presets := _load_presets()
	for pair in [
		["pale_day", "nightfall"],
		["nightfall", "deep_night"],
		["sunrise", "nightfall"],
	]:
		if not (presets.has(pair[0]) and presets.has(pair[1])):
			continue
		assert_true(
			presets[pair[0]].tonemap_exposure > presets[pair[1]].tonemap_exposure,
			"%s is not brighter than %s" % [pair[0], pair[1]]
		)

## Art Bible rule 12: the warm accents are the lit windows and the firebox, and
## they are the whole warm quota of the frame. They are worth nothing at noon
## and everything after dark -- that inversion is the reason the quota exists.
func test_the_warm_accent_is_worth_more_after_dark() -> void:
	var presets := _load_presets()
	for dark in ["nightfall", "deep_night", "whiteout"]:
		if not (presets.has(dark) and presets.has("pale_day")):
			continue
		assert_true(
			presets[dark].warm_accent_energy > presets["pale_day"].warm_accent_energy,
			"%s does not lift the warm accent above a bright day" % dark
		)

## "Twenty warm minutes". Sunrise is the one preset in the game whose light is
## warm, and it is a resource the player spends -- GDD section 4 calls the fifth
## day's dawn 可消耗的暖, warmth you can use up.
func test_sunrise_is_the_only_warm_light_in_the_run() -> void:
	var bible = ResourceLoader.load(PALETTE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bible == null:
		return
	var presets := _load_presets()
	if not presets.has("sunrise"):
		return
	assert_true(bible.is_warm(presets["sunrise"].sun_color), "SUNRISE does not light with a warm tone")
	for name in presets:
		if name == "sunrise":
			continue
		assert_false(
			bible.is_warm(presets[name].sun_color),
			"%s also lights with a warm tone, so sunrise is not a beat any more" % name
		)

# --- the two rigs -----------------------------------------------------------

## THE COUPLING GATE, and the one worth reading before changing any preset.
##
## Ambient is a character-only control, because every world shader declares
## `ambient_light_disabled`; the tonemap exposure is a world control that the
## character rides along with. So a preset that darkens the world without pulling
## the character's fill down with it leaves a man glowing in a dark frame -- and
## with no HUD, that reads as art direction rather than as a bug.
##
## Judged as a ratio against FLAT, which is the reference by definition: as the
## world goes down, the fill may not go up.
func test_the_character_never_outruns_the_world_he_stands_in() -> void:
	var presets := _load_presets()
	if not presets.has("flat"):
		return
	var reference = presets["flat"]
	var reference_fill := _fill_luma(reference)
	assert_true(reference_fill > 0.0, "FLAT lights the character with nothing, so this proves nothing")
	for name in presets:
		var world_ratio: float = presets[name].tonemap_exposure / reference.tonemap_exposure
		var fill_ratio: float = _fill_luma(presets[name]) / reference_fill
		if world_ratio >= 1.0:
			continue
		assert_true(
			fill_ratio <= 1.0,
			"%s darkens the world to %.2f of FLAT and brightens the character to %.2f: "
				% [name, world_ratio, fill_ratio]
				+ "he will glow out of the frame"
		)

## The other half of the same coupling, from tests/art/test_character_lighting.gd:
## a figure standing on a snowfield is filled by the snow, not by less than it.
## That file checks the Environment the director builds; this checks all six
## presets it can be asked to build, including the five that file never sees.
func test_no_preset_fills_the_character_with_less_than_the_snow_does() -> void:
	var bible = ResourceLoader.load(PALETTE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bible == null:
		return
	var darkest: Color = bible.snow_tones[bible.snow_tones.size() - 1].srgb_to_linear()
	var snow_luma := 0.2126 * darkest.r + 0.7152 * darkest.g + 0.0722 * darkest.b
	var presets := _load_presets()
	for name in presets:
		assert_true(
			_fill_luma(presets[name]) >= snow_luma,
			"%s fills the character at %f against the darkest snow tone's %f"
				% [name, _fill_luma(presets[name]), snow_luma]
		)

## The tint, from the same file and for the same measured reason: a fill this
## blue drives the coat's blue channel to clipping while its red is still at a
## quarter, and the coat stops reading as the blue-grey it is painted.
func test_no_preset_fills_the_character_with_a_saturated_colour() -> void:
	var presets := _load_presets()
	for name in presets:
		var fill: Color = presets[name].ambient_color.srgb_to_linear()
		var high := maxf(fill.r, maxf(fill.g, fill.b))
		var low := minf(fill.r, minf(fill.g, fill.b))
		assert_true(low > 0.0, "%s has a zero channel in its fill" % name)
		if low <= 0.0:
			continue
		assert_true(
			high / low <= 1.6,
			"%s spans %f between its brightest and dimmest fill channel; past about "
				% [name, high / low]
				+ "1.6 the coat renders as saturated blue rather than blue-grey"
		)

# --- the seven days point at the six ----------------------------------------

func _load_schedules() -> Dictionary:
	var schedules := {}
	for day in range(1, 8):
		var schedule = ResourceLoader.load(
			"res://data/schedule/day_%02d.tres" % day, "", ResourceLoader.CACHE_MODE_IGNORE
		)
		if schedule is DaySchedule:
			schedules[day] = schedule
	return schedules

## The gate that would have caught a typo in either file. A day naming a preset
## that does not exist is a day the lighting silently does not change on.
func test_every_day_names_presets_that_exist() -> void:
	var presets := _load_presets()
	var schedules := _load_schedules()
	assert_eq(schedules.size(), 7, "seven days ship")
	for day in schedules:
		var schedule = schedules[day]
		assert_true(
			presets.has(String(schedule.primary_lighting_preset)),
			"day %d asks for daylight preset '%s', which does not exist"
				% [day, schedule.primary_lighting_preset]
		)
		assert_true(
			presets.has(String(schedule.night_lighting_preset)),
			"day %d asks for night preset '%s', which does not exist"
				% [day, schedule.night_lighting_preset]
		)

## GDD section 4's 主导光照 column, day by day, including the two rows it writes
## as a transition: day 2 is PALE DAY -> NIGHTFALL and day 6 NIGHTFALL ->
## WHITEOUT. Those arrows are the daylight preset and the night preset, which is
## what makes the seven-day arc something the player watches happen rather than
## something the design document asserts.
func test_the_seven_days_light_the_way_the_gdd_says() -> void:
	var expected := {
		1: [&"pale_day", &"nightfall"],
		2: [&"pale_day", &"nightfall"],
		3: [&"nightfall", &"deep_night"],
		4: [&"deep_night", &"deep_night"],
		5: [&"sunrise", &"deep_night"],
		6: [&"nightfall", &"whiteout"],
		7: [&"whiteout", &"whiteout"],
	}
	var schedules := _load_schedules()
	for day in expected:
		if not schedules.has(day):
			continue
		assert_eq(
			schedules[day].primary_lighting_preset, expected[day][0],
			"day %d daylight" % day
		)
		assert_eq(
			schedules[day].night_lighting_preset, expected[day][1],
			"day %d night" % day
		)

## FLAT is a debug reference. A day that used it would be a day with no weather
## and no time of day at all -- Art Bible section 4.2 says 非游戏内使用 in as
## many words.
func test_no_day_in_the_run_uses_the_debug_reference() -> void:
	var schedules := _load_schedules()
	for day in schedules:
		assert_true(
			schedules[day].primary_lighting_preset != &"flat",
			"day %d plays in FLAT, which is the debug reference and never in play" % day
		)
		assert_true(
			schedules[day].night_lighting_preset != &"flat",
			"the night of day %d plays in FLAT" % day
		)
