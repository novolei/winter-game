extends TestCase

## Rule 9 of the Art Bible: every surface is flat-shaded and its color comes
## from the 12-color palette. This test is the gate.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

var _bible

func before_each() -> void:
	_bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)

func test_the_gate_catches_an_off_palette_material() -> void:
	# Proves the check works before any real asset exists.
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	assert_false(_bible.contains(offender.albedo_color), "a pure green material must be rejected")

func test_the_gate_accepts_an_on_palette_material() -> void:
	var good := StandardMaterial3D.new()
	good.albedo_color = Color("#6987B4")
	assert_true(_bible.contains(good.albedo_color), "a palette snow tone must be accepted")

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The scan roots are empty in this wave, so a
## per-asset assertion would execute zero assertions and the runner fails any
## test that does -- correctly, since it cannot tell an empty loop from one a
## runtime error aborted. The check is unchanged: it fails on exactly the same
## assets and still names every one of them. Placing the assertion after the
## walk also keeps the runner's guard meaningful here, because an error inside
## the loop aborts before the assertion runs and the guard still fires.
func test_every_material_in_the_project_is_on_palette() -> void:
	var offenders := PackedStringArray()
	for root in AssetScannerScript.SCAN_ROOTS:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is BaseMaterial3D):
				continue
			var material := resource as BaseMaterial3D
			if not _bible.contains(material.albedo_color):
				offenders.append(
					"%s uses albedo %s, which is not in the 12-color palette" % [path, material.albedo_color.to_html(false)]
				)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
