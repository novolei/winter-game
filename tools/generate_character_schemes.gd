extends SceneTree

## One-off generator for res://data/characters/*.tres -- the wanderer's looks.
## Run: godot --headless --path <project> --script res://tools/generate_character_schemes.gd
##
## The colours here are the only ones in the project that are not palette
## entries, and that is the owner's ruling rather than an oversight: the
## character is exempt from the Art Bible's surface rules. tools/ is where a
## colour literal is allowed to live, which is why the numbers are here rather
## than in the resource script.

## Where the occlusion ghost's colour comes from.
##
## Read out of the palette rather than typed here, which is the opposite of what
## the header says about the character's colours -- and deliberately so. The
## tint below paints the *figure*, which is exempt from the 12-colour table. The
## ghost is drawn over the *world*: over trees at `#131C30` and walls two steps
## down from `#33496E`. Rule 12 caps warm pixels at half a percent of frame and
## reserves them for fire, windows, beacons, the scarf and the truck, and a
## silhouette showing through the farmhouse is a good deal more than half a
## percent of frame. So it takes a world colour, and the brightest cool one
## there is, because what it has to separate from is the darkest thing on
## screen.
const PALETTE_PATH := "res://data/palette/color_bible.tres"

## How much of the ghost reaches the screen.
##
## The number the acceptance criteria pin from both ends: high enough that the
## figure reads clearly through a trunk, low enough that the trunk still reads
## as solid. Judged at gameplay framing with the figure at 11% of frame height
## -- see .superpowers/sdd/wave2/shots/.
##
## SWEPT, NOT CHOSEN: 0.22, 0.32, 0.42 and 0.55 were rendered from the same
## standing position 1.2 m behind a trunk, and the two ends both fail. At 0.55
## the trunk crossing the figure came out at #6d87a8 -- brighter than the snow
## shadow beside it, so the tree stopped reading as wood. At 0.22 the figure was
## a smear. The blend is linear, which is why this is so sensitive: the ghost is
## the palette's brightest snow tone and a tree is `#131C30`, so even a quarter
## of it doubles the trunk's luminance.
##
## The house pulls the other way -- its lit wall and its roof snow are far
## brighter than a tree, so the same alpha reads much weaker over them -- and
## 0.38 is where both frames are acceptable at once.
const GHOST_ALPHA := 0.38

const SCHEMES := [
	{
		"file": "wanderer_pale",
		"id": &"pale",
		"name": "Pale — the model's own colours",
		# Measured, not chosen. At tint 1.0 the coat renders #738CAD -- close to
		# the Meshy render's #8FA0B8 -- but the scarf's red channel clips outright
		# at 1.105, and a clipped channel is exactly what makes a coral read as
		# fluorescent orange: the highlight goes flat and the hue skews. 0.80
		# brings the red back inside range with headroom to spare, and takes the
		# whole figure a step toward the muted, cold read of Refs/game ref
		# /level.jpg without going anywhere near the silhouette. Measured after:
		# coat #5B6F8A, scarf #F87549.
		"tint": Color(0.80, 0.80, 0.82),
		"key": 1.6,
	},
	{
		"file": "wanderer_dark",
		"id": &"dark",
		"name": "Dark — the silhouette",
		# The look this project shipped before the fill was corrected, kept
		# deliberately: it separates from bright snow at gameplay distance in a
		# way a mid-tone figure does not. 0.34 puts the coat at roughly #232B38,
		# close to the #23385A the old dark-navy ambient produced, with the scarf
		# surviving as the one warm accent instead of clipping.
		"tint": Color(0.34, 0.34, 0.36),
		# A silhouette has no interior form to model, so the key light that
		# exists to reveal the coat's quilting has nothing to do here.
		"key": 0.0,
	},
]


func _initialize() -> void:
	var SchemeScript := load("res://src/definitions/character_scheme.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/characters"))
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		printerr("generate_character_schemes: no palette at %s" % PALETTE_PATH)
		quit(1)
		return
	var ghost: Color = bible.snow_tones[0]
	ghost.a = GHOST_ALPHA
	var failures := 0
	for row in SCHEMES:
		# Annotated, not `var x =`: an untyped local is a Variant and a typed
		# setter rejects what the compiler then hands it, aborting the function
		# without a message (briefing trap 4).
		var scheme: CharacterScheme = SchemeScript.new()
		scheme.id = row["id"]
		scheme.display_name = row["name"]
		scheme.albedo_tint = row["tint"]
		scheme.key_energy = row["key"]
		# Both looks ghost the same, and that is a decision rather than an
		# oversight: what the ghost has to separate from is the geometry in
		# front of the figure, which is the same geometry whichever way the
		# figure itself is painted.
		scheme.ghost_color = ghost
		var path: String = "res://data/characters/%s.tres" % row["file"]
		var error := ResourceSaver.save(scheme, path)
		if error != OK:
			failures += 1
		print("generate_character_schemes: %s -> %d" % [path, error])
	quit(1 if failures > 0 else 0)
