extends SceneTree

## One-off generator for res://data/aurora/*.tres. Run:
##
##   godot --headless --path <project> --script res://tools/generate_aurora.gd
##
## Content `.tres` is generated, never hand-authored (briefing constraint 7), and
## `tools/` is the one place a colour literal is allowed (constraint 6).
##
## ---------------------------------------------------------------------------
## WHY THE COLOURS BELOW ARE NOT IN THE TWELVE, AND WHY THAT IS NOT A BREACH
## ---------------------------------------------------------------------------
## The 12-colour table governs ALBEDO -- the colour of a surface -- and is what
## `verify_palette` checks. Sky, fog, ambient and light colour are ATMOSPHERE and
## are not bound by it: that is the Director's ruling recorded against
## `Docs/style optimization.md`, and it is the same ruling that makes a gradient
## sky legal at all.
##
## An aurora is sky, and it is its own light source. Its cast on the snow is
## LIGHT and not albedo -- `LightingDirector` normalises it to unit luminance
## before any shader sees it, so it rotates hue and can neither brighten nor
## darken a thing, and it reaches the LIT cel band only. The shade band stays
## exactly the palette colour Art Bible section 4.1 chose for it.
##
## ---------------------------------------------------------------------------
## THE THREE CURTAIN COLOURS, READ OFF THE OWNER'S REFERENCE FRAME
## ---------------------------------------------------------------------------
## Teal and green curtains against a dark blue night, several bands at different
## brightnesses, the whole forest below washed in the same teal. So:
##
##   #58E39C  the near band, and the brightest -- the green edge
##   #2FBFA6  the middle band -- teal, the colour the reference is mostly made of
##   #1E7F9C  the far band -- deep cyan, the diffuse top of the picture
##
## and the ground takes a DESATURATED teal rather than any of the three. That is
## deliberate: at unit luminance a saturated green rotates the snow's hue hard
## enough to read as green snow, and what the reference shows is snow WASHED
## teal. `#7FD6C0` is that wash. The strength is the dial and it was measured on
## a rendered frame, not chosen -- see tools/capture_aurora.gd.
##
## ---------------------------------------------------------------------------
## RARITY
## ---------------------------------------------------------------------------
## Only a `deep_night` night can carry one, which in the shipped seven-day
## schedule is nights 3, 4 and 5 -- nights 1 and 2 wear NIGHTFALL, which is a
## dusk, and nights 6 and 7 are the storm. One showing per run at most. Drawn at
## 0.20 on each of the three, which puts an aurora in a little under half of all
## runs and never two in one.
##
## It has to be rare or it is not a surprise; it has to be possible or it is
## content nobody ever sees. That trade is `chance_per_night` and it is one line.

const OUTPUT_DIRECTORY := "res://data/aurora"


func _initialize() -> void:
	var AuroraScript := load("res://src/definitions/aurora_definition.gd")

	var rows := [
		{
			"id": &"boreal_curtain",
			"name": "BOREAL CURTAIN",
			# --- rarity ---
			"chance": 0.20,
			"once": true,
			"nights": [&"deep_night"] as Array[StringName],
			"clear_only": true,
			# Never at the top of the night: the player has just been driven
			# indoors by NIGHTFALL, and something already there when the dark
			# arrives reads as part of the preset rather than as an event.
			"window": Vector2(0.18, 0.46),
			# --- arc ---
			# Against a 420-second night this is between 2.4 and 3.4 minutes,
			# ramps included. A visit, not the evening's weather.
			"rise": 34.0,
			"hold": Vector2(70.0, 130.0),
			"fall": 42.0,
			# --- curtain ---
			# The camera's fixed yaw is -35 degrees, which is a world heading of
			# +35: this range brackets it, so an upward lean finds the curtain
			# wherever in the range it was drawn, and still varies per showing.
			"bearing": Vector2(8.0, 62.0),
			# 55 is a HALF width -- 110 degrees of horizon, most of the visible
			# half of the sky. 巨幕.
			"span": 55.0,
			# LOW AND SHALLOW, and the numbers are set by the LEAN rather than by
			# the picture. 挂在远远天际 puts it on the horizon at a great
			# distance, never overhead -- and the camera cue that will one day find
			# it is a brief LEAN under the Art Bible rule 1 exception, not a
			# sky-gaze. A lean that reaches horizontal at a 62-degree field of view
			# frames roughly -31 to +31 degrees of elevation, so a curtain whose
			# mass sits above that is a curtain the game can never show.
			#
			# The first pass put the hem at 11 and the highest band's crown at 74.6.
			# It captured beautifully from a camera aimed 28 degrees up and would
			# have been entirely off the top of a lean. Measured on the sky shot;
			# corrected here rather than in the shot.
			# never overhead.
			"base_elevation": 6.0,
			"top_elevation": 32.0,
			# ANNOTATED, and it has to be: briefing trap 4. A bare `[Color(...)]`
			# literal is an untyped Array, and reading it back out of this
			# Dictionary hands the typed `band_colors` setter something it rejects
			# -- which is a runtime error that ABORTS this function and takes every
			# line after it with it. `as Array[StringName]` on "nights" below is
			# the same guard, and this one was found the hard way.
			"bands": [Color("#58E39C"), Color("#2FBFA6"), Color("#1E7F9C")] as Array[Color],
			"band_opacity": Vector3(1.0, 0.72, 0.45),
			# How far each band is lifted, as a fraction of the first band's own
			# depth. Small for the same reason the crown came down: at 0.72 the
			# third band's top reached 74 degrees, which is overhead.
			"band_lift": Vector3(0.0, 0.25, 0.50),
			"band_offset": Vector3(0.0, -0.31, 0.47),
			"sky_opacity": 1.0,
			# THE STRIATIONS. 5.4 puts roughly nineteen coarse rays across the
			# 110-degree span with filaments inside them, which at the widest
			# framing a look-up could use is a ray every few degrees -- fine
			# enough to read as rays, coarse enough to survive an 8-bit frame.
			"ray_frequency": 5.4,
			"ray_sharpness": 2.2,
			"ray_shear": 0.55,
			# Slow. The three bands drift at this times 1, 1.618 and 0.577; the
			# ratios are irrational, so the combined figure has no period a
			# session could contain and the curtain never repeats.
			"drift": 0.035,
			# --- ground ---
			"cast_color": Color("#7FD6C0"),
			# MEASURED, NOT PICKED. tools/capture_aurora.gd --cast sweeps this and
			# prints the rendered lit and shade bands beside every frame; the four
			# stops were read off the pictures at DEEP NIGHT:
			#
			#   0.30  lit #576d87 -> #506f86   "is the snow slightly different?"
			#   0.45  lit #576d87 -> #4c7186   a clear shift, still reads as blue
			#   0.60  lit #576d87 -> #487285   unmistakably teal, shadows still cold
			#   0.75  lit #576d87 -> #437384   a filter; the frame stops being winter
			#
			# 0.60 is the one. The Director's requirement is that the GROUND is what
			# the player notices -- 他看向天空是因为雪变绿了 -- and 0.45 is a
			# question rather than a tell.
			"cast_strength": 0.60,
			"fill_share": 0.55,
		},
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var failed := false
	for row in rows:
		# Annotated, NOT `var x = ...`: briefing trap 4. An untyped local makes
		# the compiler emit an untyped Array for `band_colors` below, the typed
		# setter rejects it, and the VM breaks out of this function -- silently,
		# taking every line after it.
		var aurora: AuroraDefinition = AuroraScript.new()
		aurora.id = row["id"]
		aurora.display_name = row["name"]
		aurora.chance_per_night = row["chance"]
		aurora.once_per_run = row["once"]
		aurora.allowed_night_presets = row["nights"]
		aurora.requires_clear_weather = row["clear_only"]
		aurora.start_window = row["window"]
		aurora.rise_seconds = row["rise"]
		aurora.hold_seconds = row["hold"]
		aurora.fall_seconds = row["fall"]
		aurora.bearing_degrees = row["bearing"]
		aurora.span_degrees = row["span"]
		aurora.base_elevation_degrees = row["base_elevation"]
		aurora.top_elevation_degrees = row["top_elevation"]
		aurora.band_colors = row["bands"]
		aurora.band_opacity = row["band_opacity"]
		aurora.band_lift = row["band_lift"]
		aurora.band_offset = row["band_offset"]
		aurora.sky_opacity = row["sky_opacity"]
		aurora.ray_frequency = row["ray_frequency"]
		aurora.ray_sharpness = row["ray_sharpness"]
		aurora.ray_shear = row["ray_shear"]
		aurora.drift_speed = row["drift"]
		aurora.ground_cast_color = row["cast_color"]
		aurora.ground_cast_strength = row["cast_strength"]
		aurora.character_fill_share = row["fill_share"]

		var path := "%s/%s.tres" % [OUTPUT_DIRECTORY, row["id"]]
		var error := ResourceSaver.save(aurora, path)
		if error != OK:
			print("generate_aurora: FAILED %s (%d)" % [path, error])
			failed = true
			continue
		print("generate_aurora: wrote %s -- %s" % [path, row["name"]])
	# SceneTree.quit() only REQUESTS exit at the end of the current iteration; it
	# does not return from the function. Accumulate and quit exactly once, as the
	# last statement -- the shape generate_lighting_presets.gd uses.
	quit(1 if failed else 0)
