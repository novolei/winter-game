extends SceneTree

## One-off generator for res://data/rendering/occluder_fade.tres.
## Run: godot --headless --path <project> --script res://tools/generate_occluder_fade.gd
##
## ---------------------------------------------------------------------------
## THE ONE COLOUR LITERAL, AND WHY IT IS HERE
## ---------------------------------------------------------------------------
## `tools/` is the only place in this project where a colour may be written down
## rather than resolved from `data/palette/color_bible.tres`, and this is one of
## the few that has to be: the owner ruled the occluder tint a **rendering
## affordance rather than an albedo**, on the same footing as the sky, the fog
## and the ambient, and therefore not bound by the 12-colour table.
##
## The palette was tried first, as the ruling asks. Nothing in it is 浅灰黑:
##
##   * the nine snow tones are pale blue -- a faded building in one of them is
##     brighter than the snow behind it and stops being a silhouette at all;
##   * the three warm tones are barred outright by rule 12;
##   * `#131C30`, the structure family's darkest and the colour the trees are
##     painted, is the nearest candidate and is plainly blue rather than grey:
##     R 19, G 28, B 48. A faded farmhouse in it reads as translucent navy,
##     which is "a ghost of its own colour" -- the exact read the ruling rejects.
##
## So: a neutral near-black with the faintest cool cast, so it sits in a blue
## picture without introducing a hue of its own.
##
##   #16181C -- R 22, G 24, B 28. Luma 0.093.
##
## The spread between channels is 6/255, against the palette's own 29/255 on its
## darkest entry. That is the difference between "grey" and "blue".
const TINT := Color(0x16 / 255.0, 0x18 / 255.0, 0x1C / 255.0)

## How much of it reaches the screen.
##
## The composite is what was judged, not the number: over lit snow (`#8FB0D8`)
## this lands the faded shape at roughly `#637A99`, a clear step darker than the
## snow around it, which is what makes it read as a silhouette rather than as
## the object having been deleted. Lower and the occluder vanishes; higher and
## the character behind it stops reading.
const OPACITY := 0.55

## The motion, and it is the half of this effect a screenshot cannot show.
##
## Two durations rather than one: a fence post and a farmhouse are the same
## gesture at different masses, and a house that changes state as briskly as a
## post reads as a light switch rather than as a building. Both are eased rather
## than linear -- see OccluderFader.curve_for() for why neither of them
## overshoots, on a building least of all.
const FADE_SECONDS := 0.26
const FADE_SECONDS_LARGE := 0.40
const LARGE_METRES := 4.0

## A bounded dwell before an occluder is released, so a single ray does not
## chatter when the player skims an edge. Deliberately much shorter than the
## fade: it must never be able to look like the release failing.
const DWELL_SECONDS := 0.10

## Where the ray is aimed, as a fraction of the character's height: the top of
## his chest. His origin is at his ankles, which is the one part of him whose
## being covered nobody minds.
const AIM_HEIGHT := 0.78


func _initialize() -> void:
	var SettingsScript := load("res://src/definitions/occluder_fade_settings.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/rendering"))
	# Annotated, not `var x =`: an untyped local is a Variant and a typed setter
	# rejects what the compiler then hands it, aborting the function without a
	# message (briefing trap 4).
	var settings: OccluderFadeSettings = SettingsScript.new()
	settings.tint = Color(TINT.r, TINT.g, TINT.b, OPACITY)
	settings.fade_seconds = FADE_SECONDS
	settings.fade_seconds_large = FADE_SECONDS_LARGE
	settings.large_metres = LARGE_METRES
	settings.dwell_seconds = DWELL_SECONDS
	settings.aim_height = AIM_HEIGHT
	var path := "res://data/rendering/occluder_fade.tres"
	var error := ResourceSaver.save(settings, path)
	print("generate_occluder_fade: %s -> %d" % [path, error])
	quit(1 if error != OK else 0)
