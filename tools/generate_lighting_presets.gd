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
## `ambient_light_disabled`. So the six looks below are made out of these world
## controls:
##
##   EXPOSURE   the only brightness control that reaches the world. It scales
##              both cel bands equally, so it cannot take the shadow band
##              off-palette the way a per-band multiply would.
##   FOG        the world's DEPTH control. It is in depth mode now, so its
##              opacity ramps with distance from the camera and it is what makes
##              a far tree a different colour from a near one. Toward the snow's
##              own tone it leaves distant snow alone and blues distant trees;
##              toward a structure tone it takes the frame's contrast away.
##   WORLD LIGHT the world's HUE control, and new in this pass. The lit cel band
##              is multiplied by a luminance-normalised light colour, which is
##              the only way warm light reaches the snow -- see SUNRISE below.
##   CEL BANDS  where the shadow band starts and how soft its edge is. Authored
##              since the last wave and inert until this one.
##   GLOW       bloom on whatever is brightest -- the warm windows, once anything
##              warm is placed, and the snow in the storm.
##   SHADOWS    cast or not. A blizzard has no sun.
##   SKY        a vertical gradient behind everything. Not in shot at any framing
##              the game uses today; see LightingPreset for why it is here anyway.
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

## ---------------------------------------------------------------------------
## THE ATMOSPHERE PASS, AND THE BOUNDARY IT IS AUTHORED INSIDE
## ---------------------------------------------------------------------------
## The twelve govern ALBEDO -- the colour of a surface, which `verify_palette`
## checks. Sky, fog, ambient and light colour are ATMOSPHERE, and are not bound
## by the table. That is the Director's ruling on `Docs/style optimization.md`
## and it is what makes a gradient sky legal at all.
##
## Everything below is still DERIVED from the palette rather than invented, and
## for two reasons. Briefing constraint 6 puts hex literals only in tools/, and a
## sky the frame never resolves toward reads as a hole in the picture rather than
## as air. `_pale()` is the one operation used: white toward the lightest snow
## tone, which is where the horizon of a cold sky actually sits.
##
## Measured against the style document's own values, which were written for a
## perspective camera and a different pipeline:
##
##   document        derived here                    delta
##   #B1D0EA horizon _pale(0.65)      -> #B6CCE6     within 8/255 per channel
##   #8CB4D9 fog     snow_tones[0]    -> #8FB0D8     within 4/255 per channel
##   #B8D4EA vol.    _pale(0.60)      -> #BCD0E8     within 6/255 per channel
##   #5D96D3 zenith  snow_tones[4]    -> #667890     restrained slate shadow
##
## The zenith is the one real departure: nothing in the twelve is as saturated as
## #5D96D3, and inventing a colour to match a suggestion is how a palette stops
## being a palette. It is a gradient in the direction the document asks for, out
## of the family the rest of the frame is in.
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const OUTPUT_DIRECTORY := "res://data/lighting"


## White toward the lightest snow tone. The pale end of every sky, and the
## volumetric albedo.
static func _pale(bible, amount: float) -> Color:
	return Color.WHITE.lerp(bible.snow_tones[0], amount)

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
	# exposure     the world's brightness
	# fog          [colour, OPACITY] -- see below; no longer a density
	# window       [begin m, end m] -- the depth window, measured from the camera
	# sky          [zenith, horizon] -- a vertical gradient, per preset
	# stars        0 none .. 1 a clear winter night. The sky is drawn by
	#              assets/shaders/aurora_sky.gdshader now rather than by a
	#              ProceduralSkyMaterial, and this is the one field the swap adds.
	#              Only the two dark looks carry any: a dusk gets the first few,
	#              DEEP NIGHT gets all of them, and the storm gets none because a
	#              whiteout has no sky. Like the gradient above it is not in shot
	#              at any framing the game uses today -- it is what makes the
	#              aurora provably semi-transparent when something does look up.
	# vapour       [enabled, density] -- style document section 39's volumetric air.
	#              SHIPPED OFF ON ALL SIX, and the densities below are what to
	#              turn back on. Measured rather than assumed: it costs almost
	#              nothing in frame time (0.714 -> 0.745 ms at 1600x1000) but it
	#              lifts the NEAREST tree in the frame from #182239 to #2F3A4F,
	#              because froxel fog in-scatters sunlight along the whole ray
	#              and the whole ray is 90 m of boom. The foreground staying
	#              near-black is the point of the aerial perspective above, so
	#              the two are in direct competition and this one loses.
	#              Neither `volumetric_fog_ambient_inject = 0` nor
	#              `sky_affect = 0` recovers it; the scattering itself is what
	#              costs the blacks.
	# glow         [enabled, strength]
	# bands        [threshold, softness] -- pushed into both cel shaders
	# world_light  [colour, strength] -- the hue the LIT cel band takes
	# warm         Art Bible rule 12's warm quota, for whatever burns
	#
	# THE FOG NUMBER CHANGED MEANING IN THIS PASS. The fog is in DEPTH mode now,
	# so Godot computes
	#
	#     fog = smoothstep(begin, end, distance from camera) * fog_density
	#
	# and `fog_density` is the fog's OPACITY where the window ends, a 0..1 blend.
	# The old exponential densities (0.0016 .. 0.0130) would be invisible under
	# it. Depth mode is what buys aerial perspective at all: the rig is
	# orthographic on a 90 m boom, so the whole farmstead sits at 69..100 m from
	# the camera, and an exponential curve over that stretch is nearly a straight
	# line starting well above zero -- fog enough to blue the far tree already
	# greys the near one. That is why every tree in the scene was the same
	# near-black whatever its distance, which was the main reason the frame read
	# flat.
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
			"window": [74.0, 118.0], "sky_affect": 0.0,
			"sky": [bible.snow_tones[4], _pale(bible, 0.65)],
				"stars": 0.0,
			"vapour": [false, 0.0],
			"glow": [false, 0.0],
			"bands": [0.12, 0.07],
			"world_light": [Color.WHITE, 0.0],
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
			# Toward the lightest snow tone at 1.0 energy, which is the whole
			# trick: the fog target IS the snow's own colour, so distant snow does
			# not move and distant TREES go blue. Fog is additive toward a colour
			# and therefore moves dark surfaces much further than light ones.
			"fog": [bible.snow_tones[0], 0.55], "fog_on": true,
			"window": [74.0, 118.0], "sky_affect": 0.0,
			"sky": [bible.snow_tones[4], _pale(bible, 0.62)],
				"stars": 0.0,
			"vapour": [false, 0.0012],
			"glow": [true, 0.12],
			"bands": [0.12, 0.07],
			"world_light": [Color.WHITE, 0.0],
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
			# COOL air under a WARM light, which is the reference sheet's own
			# reading of this beat and the opposite of what shipped. An amber fog
			# warms the whole distance and the shadows with it, and the frame goes
			# sepia; the snow tone leaves the far field and the shadow band blue,
			# and the warmth arrives only where the sun actually falls.
			"fog": [bible.snow_tones[0], 0.35], "fog_on": true,
			"window": [74.0, 118.0], "sky_affect": 0.0,
			# The one warm sky in the run, and the only one whose horizon is not
			# blue. Pale snow carried most of the way to the amber.
			"sky": [bible.snow_tones[3], _pale(bible, 0.55).lerp(bible.warm_tones[2], 0.45)],
				"stars": 0.0,
			"vapour": [false, 0.0012],
			"glow": [true, 0.50],
			# A softer, wider band: low warm light rakes rather than cuts.
			"bands": [0.10, 0.14],
			# CONCERN 3 OF THE CLOCK/LIGHTING REPORT, ANSWERED. Fog alone warmed
			# the buildings and left the snow cold lavender, because fog moves
			# dark surfaces further than light ones -- so the frame read as a warm
			# house against cold snow, which is the reference inverted. This is
			# the other half: the LIT cel band is multiplied by the sun's own
			# colour, normalised to unit luminance so it rotates the hue and does
			# not touch the exposure this preset was tuned at. The SHADE band is
			# left alone, which is both Art Bible section 4.1 and what a winter
			# dawn actually looks like.
			"world_light": [bible.warm_tones[2], 0.42],
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
			"fog": [bible.structure_tones[0], 0.62], "fog_on": true,
			"window": [70.0, 112.0], "sky_affect": 0.25,
			"sky": [bible.structure_tones[0], bible.snow_tones[1]],
				"stars": 0.25,
			"vapour": [false, 0.0015],
			"glow": [true, 0.45],
			# More of the world falls into the shadow band as the light goes.
			"bands": [0.18, 0.10],
			"world_light": [Color.WHITE, 0.0],
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
			"fog": [bible.structure_tones[1], 0.58], "fog_on": true,
			"window": [70.0, 112.0], "sky_affect": 0.35,
			"sky": [bible.structure_tones[2], bible.structure_tones[0]],
				"stars": 1.0,
			"vapour": [false, 0.0018],
			"glow": [true, 0.65],
			"bands": [0.24, 0.10],
			"world_light": [Color.WHITE, 0.0],
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
			"fog": [bible.snow_tones[0], 0.85], "fog_on": true,
			# The window closes in as well as thickening: the storm starts eating
			# the frame twenty metres nearer than the clear days do, and the sky
			# goes with it.
			"window": [56.0, 108.0], "sky_affect": 0.90,
			"sky": [bible.snow_tones[2], _pale(bible, 0.35)],
				"stars": 0.0,
			"vapour": [false, 0.0020],
			"glow": [true, 0.80],
			# Wide and soft: what little shading survives has no edge to it.
			"bands": [0.35, 0.30],
			"world_light": [Color.WHITE, 0.0],
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
		# 1.0 everywhere, so the fog target is exactly the palette tone and
		# distant snow does not move. The style document asks for 0.7; that was
		# written for a perspective camera whose far distance really is far away,
		# and here it would only darken the far field.
		preset.fog_light_energy = 1.0
		preset.fog_depth_begin = row["window"][0]
		preset.fog_depth_end = row["window"][1]
		preset.fog_sky_affect = row["sky_affect"]
		preset.sky_zenith_color = row["sky"][0]
		preset.sky_horizon_color = row["sky"][1]
		preset.sky_curve = 0.15
		preset.sky_energy = 1.0
		preset.star_amount = row["stars"]
		preset.volumetric_fog_enabled = row["vapour"][0]
		preset.volumetric_fog_density = row["vapour"][1]
		preset.volumetric_fog_albedo = _pale(bible, 0.60)
		preset.volumetric_fog_anisotropy = 0.15
		preset.volumetric_fog_ambient_inject = 0.15
		preset.world_light_color = row["world_light"][0]
		preset.world_light_strength = row["world_light"][1]
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
