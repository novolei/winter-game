extends SceneTree

## One-off generator for res://data/characters/*.tres -- the wanderer's looks.
## Run: godot --headless --path <project> --script res://tools/generate_character_schemes.gd
##
## The colours here are the only ones in the project that are not palette
## entries, and that is the owner's ruling rather than an oversight: the
## character is exempt from the Art Bible's surface rules. tools/ is where a
## colour literal is allowed to live, which is why the numbers are here rather
## than in the resource script.

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
		var path: String = "res://data/characters/%s.tres" % row["file"]
		var error := ResourceSaver.save(scheme, path)
		if error != OK:
			failures += 1
		print("generate_character_schemes: %s -> %d" % [path, error])
	quit(1 if failures > 0 else 0)
