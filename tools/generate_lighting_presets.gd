extends SceneTree

## One-off generator for res://data/lighting/*.tres -- Art Bible section 4.2's
## six presets. Run:
##
##   godot --headless --path <project> --script res://tools/generate_lighting_presets.gd
##
## Every colour here is read out of data/palette/color_bible.tres. Nothing below
## is a hex literal (briefing constraint 6), and the files are generated rather
## than hand-authored (constraint 7).
##
## ---------------------------------------------------------------------------
## WHAT ACTUALLY MOVES WHEN YOU CHANGE A ROW
## ---------------------------------------------------------------------------
## The world is drawn by two cel shaders that SELECT a palette colour outright
## and read nothing from a light but its shadow term. Sun energy, sun colour and
## ambient reach the world NOT AT ALL -- both shaders declare
## `ambient_light_disabled`. So the six looks below are made out of exactly four
## world controls:
##
##   EXPOSURE   the only brightness control that reaches the world. It scales
##              both cel bands equally, so it cannot take the shadow band
##              off-palette the way a per-band multiply would.
##   FOG        the only HUE control that reaches the world. The camera is
##              orthographic on a 90 m boom, so every fragment sits at very
##              nearly the same depth and the fog is close to a flat, full-frame
##              wash whose strength is the density and whose colour is the tint.
##              This is why the fog colours below carry the dramatic weight.
##   GLOW       bloom on whatever is brightest -- the warm windows, once anything
##              warm is placed, and the snow in the storm.
##   SHADOWS    cast or not. A blizzard has no sun.
##
## and two character controls -- sun energy/colour and the ambient fill -- which
## exist to keep the man in step with whatever the world is doing. The pairing is
## machine-checked by tests/unit/test_lighting_presets.gd.
##
## ---------------------------------------------------------------------------
## THE AMBIENT FILL IS NEUTRAL, NOT PALETTE-BLUE, AND THAT IS DELIBERATE
## ---------------------------------------------------------------------------
## Every world shader disables ambient, so the Environment's ambient reaches
## exactly one object: the character, the only thing in the game on a stock
## StandardMaterial3D. It is a character control that happens to live on the
## Environment.
##
## It is mixed from WHITE toward the palette's lightest snow tone rather than
## being a palette tone outright. Measured at four energies: filling with a snow
## tone clips the coat's blue channel while its red is still at a quarter, and
## the coat renders saturated blue instead of the blue-grey it is painted. The
## tint column below is how much of the snow it keeps, so the figure stays in the
## frame's colour family without being dyed by it.
##
## The energies are far above a physical ambient because they stand in for a
## studio render's whole light rig on a model whose albedo was authored for one.
## THE DAY A WORLD OBJECT ARRIVES THAT IS NOT ON A CEL SHADER, it will blow out;
## give the character his own cull-masked fill beside PlayerController's key and
## hand these numbers back to the world.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const OUTPUT_DIRECTORY := "res://data/lighting"

## Art Bible rule 10, and the one number no preset may move: shadow length is
## height / tan(elevation), whose derivative is savage down here. At 11 degrees a
## centimetre of vertical movement became five centimetres of shadow and the walk
## lurched; at 21.5 the shadow runs 2.5x its caster, still a low raking winter
## sun, and the amplification is halved.
const SUN_ELEVATION := 21.5

func _initialize() -> void:
	var bible = load(PALETTE_PATH)
	if bible == null:
		print("generate_lighting_presets: FAILED -- no palette at %s" % PALETTE_PATH)
		quit(1)
		return

	var LightingPresetScript := load("res://src/definitions/lighting_preset.gd")

	# The six, in the order of Art Bible section 4.2's own table.
	#
	# fill_tint    how much of snow_tones[0] the character's neutral fill keeps
	# fill         ambient energy -- the character, and nothing else
	# sun          directional energy -- the character, and nothing else
	# exposure     the world's only brightness control
	# fog          [colour, density] -- the world's only hue control
	# glow         [enabled, strength]
	# bands        [threshold, softness] -- authored; see LightingPreset
	# warm         Art Bible rule 12's warm quota, for whatever burns
	var rows := [
		{
			"id": &"flat", "name": "FLAT", "subtitle": "correct and dead",
			# The debug reference, and never in play. It is the shipped rig with
			# every piece of atmosphere switched off: what the geometry and the
			# palette look like before anyone has an opinion. If a model reads
			# wrong here it is wrong, and no preset will save it.
			"sun_color": bible.snow_tones[0], "sun": 1.0, "shadows": true,
			"fill_tint": 0.20, "fill": 3.2,
			"exposure": 1.30,
			"fog": [bible.snow_tones[0], 0.0], "fog_on": false,
			"glow": [false, 0.0],
			"bands": [0.12, 0.07],
			"warm": 0.0,
		},
		{
			"id": &"pale_day", "name": "PALE DAY", "subtitle": "nothing at stake",
			# Days 1-2. Brighter than FLAT and with air in it: a whisper of
			# aerial perspective so the far side of a 120 m field is not a wall
			# of one colour, and just enough bloom that a lit window registers.
			# The safest the game ever looks, which is the entire point -- the
			# player has to have seen this to feel day 6 take it away.
			"sun_color": bible.snow_tones[0], "sun": 1.0, "shadows": true,
			"fill_tint": 0.22, "fill": 3.2,
			"exposure": 1.38,
			"fog": [bible.snow_tones[0], 0.0016], "fog_on": true,
			"glow": [true, 0.12],
			"bands": [0.12, 0.07],
			"warm": 0.5,
		},
		{
			"id": &"sunrise", "name": "SUNRISE", "subtitle": "twenty warm minutes",
			# Day 5. The only warm light in the run, and GDD section 4 calls it
			# 可消耗的暖 -- warmth you spend. The amber haze is the whole beat:
			# it is the one time the frame is not blue, it lasts twenty minutes
			# of a 420-second day, and the player is meant to resent losing it.
			# The sun's own colour goes warm too, which reaches the character and
			# nothing else -- so the man warms up a beat before the world does.
			"sun_color": bible.warm_tones[2], "sun": 0.90, "shadows": true,
			"fill_tint": 0.10, "fill": 2.6,
			"exposure": 1.10,
			"fog": [bible.warm_tones[2], 0.0022], "fog_on": true,
			"glow": [true, 0.50],
			# A softer, wider band: low warm light rakes rather than cuts.
			"bands": [0.10, 0.14],
			"warm": 1.2,
		},
		{
			"id": &"nightfall", "name": "NIGHTFALL", "subtitle": "go home",
			# Days 2-3's dusk and day 6's whole daylight. `NIGHTFALL = GO HOME`
			# is a literal deadline -- this is the look the player learns to read
			# as "turn around now", and it has to be legible at a glance from the
			# far end of the map. Hence the mid structure tone in the air: the
			# frame loses its light and its contrast together, which is what
			# distance actually looks like at dusk.
			"sun_color": bible.snow_tones[0], "sun": 0.50, "shadows": true,
			"fill_tint": 0.28, "fill": 2.3,
			"exposure": 0.78,
			"fog": [bible.structure_tones[0], 0.0070], "fog_on": true,
			"glow": [true, 0.45],
			# More of the world falls into the shadow band as the light goes.
			"bands": [0.18, 0.10],
			"warm": 1.6,
		},
		{
			"id": &"deep_night", "name": "DEEP NIGHT", "subtitle": "moonlight",
			# Day 4, and every night from day 3 on. The darkest the game gets --
			# a third of FLAT's exposure -- and the frame is held together by the
			# warm accents rather than by the sun, which is why the warm quota is
			# at its highest here. Navy in the air rather than black: the palette
			# has no black and the shadow band is a chosen colour, so the dark
			# has to arrive as a colour too.
			"sun_color": bible.snow_tones[0], "sun": 0.28, "shadows": true,
			"fill_tint": 0.32, "fill": 1.5,
			"exposure": 0.42,
			"fog": [bible.structure_tones[1], 0.0090], "fog_on": true,
			"glow": [true, 0.65],
			"bands": [0.24, 0.10],
			"warm": 2.2,
		},
		{
			"id": &"whiteout", "name": "WHITEOUT", "subtitle": "the storm",
			# Day 7. GDD section 4: 能见度归零，只靠暖点导航 -- visibility goes to
			# nothing and the player navigates by the warm points alone. So the
			# air is nearly opaque and the only thing that survives it is the
			# glow off whatever is burning.
			#
			# SHADOWS OFF is the load-bearing one. A blizzard has no sun, and
			# without shadows the frame loses all its form at once: after six days
			# of raking light everything goes flat and directionless, and the
			# player cannot tell where anything is. That reading is the day.
			#
			# Bright, not dark -- a whiteout is a bright thing. It is frightening
			# because it takes the world away, not because it takes the light.
			"sun_color": bible.snow_tones[0], "sun": 0.35, "shadows": false,
			"fill_tint": 0.12, "fill": 2.9,
			"exposure": 1.15,
			"fog": [bible.snow_tones[0], 0.0130], "fog_on": true,
			"glow": [true, 0.80],
			# Wide and soft: what little shading survives has no edge to it.
			"bands": [0.35, 0.30],
			"warm": 1.8,
		},
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var failed := false
	for row in rows:
		var preset = LightingPresetScript.new()
		preset.id = row["id"]
		preset.display_name = row["name"]
		preset.sun_energy = row["sun"]
		preset.sun_color = row["sun_color"]
		preset.sun_angle_degrees = SUN_ELEVATION
		preset.shadows_enabled = row["shadows"]
		# WHITE toward the palette, not a palette tone outright. See the header.
		preset.ambient_color = Color.WHITE.lerp(bible.snow_tones[0], row["fill_tint"])
		preset.ambient_energy = row["fill"]
		preset.fog_enabled = row["fog_on"]
		preset.fog_color = row["fog"][0]
		preset.fog_density = row["fog"][1]
		preset.glow_enabled = row["glow"][0]
		preset.glow_strength = row["glow"][1]
		preset.cel_band_threshold = row["bands"][0]
		preset.cel_band_softness = row["bands"][1]
		preset.tonemap_exposure = row["exposure"]
		preset.warm_accent_energy = row["warm"]

		var path := "%s/%s.tres" % [OUTPUT_DIRECTORY, row["id"]]
		var error := ResourceSaver.save(preset, path)
		if error != OK:
			print("generate_lighting_presets: FAILED %s (%d)" % [path, error])
			failed = true
			continue
		print("generate_lighting_presets: wrote %s -- %s, %s" % [path, row["name"], row["subtitle"]])
	# SceneTree.quit() only REQUESTS exit at the end of the current iteration; it
	# does not return from the function. Accumulate the failure and quit exactly
	# once, as the last statement -- the same shape generate_schedules.gd uses,
	# and for the same defect it was written to stop regrowing.
	quit(1 if failed else 0)
