extends SceneTree

## Writes data/scale/*.tres -- how big every asset class, and every creature, is
## allowed to be.
##
## Run:
##   godot --headless --path <project> --script res://tools/generate_asset_scales.gd
##
## ---------------------------------------------------------------------------
## EVERY NUMBER BELOW IS A REAL-WORLD SIZE, NOT A MEASUREMENT OF THE FILE
## ---------------------------------------------------------------------------
## This generator does not open a single model, and that is the point. A
## generator that measured each asset and wrote a band around what it found
## would have accepted the 15 mm wolf of `Docs/asset-inventory-low-poly-animals.md`
## section 1.1 and printed "verified" doing it -- the same circularity CLAUDE.md
## forbids when it says a palette test may not read its expected colour out of
## the palette.
##
## So each band carries the animal or the object it describes and where the
## figure comes from. `tools/measure_model_scale.gd` prints what the files
## actually measure; comparing the two lists is a person's job once, and
## `tests/art/test_asset_scale.gd`'s job on every run after that.
##
## THE FOLDER BANDS ARE DELIBERATELY WIDE and the per-asset ones deliberately
## tight. A folder band's job is to make it impossible for a new asset to arrive
## unjudged; a per-asset band's job is to notice a re-export that drifted. A wide
## folder band that never fires is doing its job, in the same way a fuse is.

const ScaleScript := preload("res://src/definitions/asset_scale.gd")

const OUT := "res://data/scale"

## [file name, covers, smallest_m, largest_m, reason]
##
## Ordered widest first so the file reads as the hierarchy it is.
const BANDS: Array = [
	# --- the class bands -------------------------------------------------------
	[
		"class_buildings", "res://assets/models/buildings", 1.5, 40.0,
		"A building runs from a privy to a barn. The valley's own are a well house at 2.9 m and the farmhouse at 10.5 m.",
	],
	[
		"class_vegetation", "res://assets/models/vegetation", 0.3, 25.0,
		"A shrub to a mature bare tree. The five shipped trees run 3.7 m to 10.6 m.",
	],
	[
		"class_props", "res://assets/models/props", 0.05, 12.0,
		"A hand tool to a power pole. The shipped set runs from a 1 m unit of wire to a 9 m pole.",
	],
	[
		"class_characters", "res://assets/models/characters", 0.08, 4.0,
		"Anything rigged and alive, from a squirrel at 0.16 m to a bear at 2.6 m. The floor is well under the smallest animal in the package and still a hundred times the 15 mm a wrongly-scaled import arrives at.",
	],

	# --- the creatures, each pinned to what that animal is -----------------------
	[
		"crow", "res://assets/models/characters/crow/crow.fbx", 0.70, 1.30,
		"A carrion crow's wingspan is 0.93 m to 1.04 m; a raven's reaches 1.3 m. The bind pose is wings-spread, so the wingspan is the longest side.",
	],
	[
		"pigeon", "res://assets/models/characters/pigeon/pigeon.fbx", 0.55, 0.90,
		"A rock dove's wingspan is 0.62 m to 0.72 m and its body 0.30 m to 0.35 m. Wings-spread bind pose, so the wingspan is the longest side.",
	],
	# The three dogs. One band each rather than one for the folder, because the
	# whole point of them is that they are three different sizes -- a band wide
	# enough for a chihuahua AND a great dane would be wider than the class band
	# it sits inside and would catch nothing at all.
	#
	# The pack shipped them at TWO different import scales (1.0 for the
	# chihuahua, 100.0 for the other two) and the Unity re-export normalised all
	# three. These bands are what says so on every run.
	[
		"dog_chihuahua", "res://assets/models/characters/dogs/chihuahua.glb", 0.20, 0.50,
		"A chihuahua stands 0.15 m to 0.23 m at the shoulder and measures about 0.30 m to 0.40 m nose to tail base. The bind pose is standing with the tail out, so the longest side is its length.",
	],
	[
		"dog_golden_retriever", "res://assets/models/characters/dogs/golden_retriever.glb", 0.85, 1.45,
		"A golden retriever stands 0.55 m to 0.61 m at the withers and measures 0.90 m to 1.15 m nose to tail base, with a 0.30 m tail behind that.",
	],
	[
		"dog_great_dane", "res://assets/models/characters/dogs/great_dane.glb", 1.00, 1.90,
		"A great dane stands 0.71 m to 0.86 m at the withers and measures 1.20 m to 1.60 m nose to tail. The pack's is at the short end of that and the floor allows for it.",
	],
	[
		"bear", "res://assets/models/characters/bear/bear.glb", 1.80, 3.20,
		"A grizzly measures 2.0 m to 2.8 m nose to tail. The bone hull is a little inside the mesh, so the floor allows for that.",
	],
	[
		"winter_wanderer", "res://assets/models/characters/winter_wanderer.glb", 1.40, 2.10,
		"A standing man. The longest side is his height.",
	],
	[
		"scavenger", "res://assets/models/characters/scavenger/scavenger.glb", 1.30, 2.60,
		"A standing man whose bind pose holds his arms out, so the longest side is his reach rather than his height.",
	],
	[
		"zombie", "res://assets/models/characters/zombie/zombie.glb", 1.30, 2.60,
		"As the scavenger: an arms-out bind pose, so the span is the longest side.",
	],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for row in BANDS:
		var band: AssetScale = ScaleScript.new()
		band.covers = row[1]
		band.smallest_m = row[2]
		band.largest_m = row[3]
		band.reason = row[4]
		var path: String = OUT.path_join("%s.tres" % row[0])
		var status := ResourceSaver.save(band, path)
		print("%s  %s  %.3f..%.3f m  (%s)" % [
			"ok " if status == OK else "FAIL", path, band.smallest_m, band.largest_m, band.covers])
	quit()
