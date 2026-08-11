extends TestCase

## Rule 9 of the Art Bible: every surface is flat-shaded and its color comes
## from the 12-color palette. This test is the gate.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

## Seeded under user://, deliberately not under a scan root: the project-wide
## test must keep measuring the project, not this fixture.
const FIXTURE_ROOT := "user://palette_gate_fixture"
const FIXTURE_MATERIAL := "user://palette_gate_fixture/off_palette.tres"

var _bible

func before_each() -> void:
	_bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	ResourceSaver.save(offender, FIXTURE_MATERIAL)

func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_MATERIAL))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))

## The gate's whole walk-load-judge body, with the roots as a parameter so the
## exact code path the project-wide scan uses can also be aimed at a seeded
## fixture root. That parameter is the only reason this gate is testable at
## all right now: the project's scan roots are empty, so a broken scan and an
## empty folder produce identical results.
func _collect_palette_offenders(roots: Array[String]) -> PackedStringArray:
	var offenders := PackedStringArray()
	for root in roots:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is BaseMaterial3D):
				continue
			var material := resource as BaseMaterial3D
			if not _bible.contains(material.albedo_color):
				offenders.append(
					"%s uses albedo %s, which is not in the 12-color palette" % [path, material.albedo_color.to_html(false)]
				)
	return offenders

func test_the_gate_catches_an_off_palette_material() -> void:
	# Proves the check works before any real asset exists.
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	assert_false(_bible.contains(offender.albedo_color), "a pure green material must be rejected")

func test_the_gate_accepts_an_on_palette_material() -> void:
	var good := StandardMaterial3D.new()
	good.albedo_color = Color("#6987B4")
	assert_true(_bible.contains(good.albedo_color), "a palette snow tone must be accepted")

## Joins the two halves the other tests each prove separately: the predicate
## above, and the walker in test_asset_scanner.gd. Runs the real chain
## -- find_files -> ResourceLoader.load -> type filter -> offender message --
## against a real file on disk. Without this, emptying MATERIAL_SUFFIXES or
## inverting the type filter leaves the entire suite green, because the
## project's scan roots are empty and nothing would notice.
func test_the_gate_finds_an_off_palette_material_on_disk() -> void:
	var offenders := _collect_palette_offenders([FIXTURE_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the seeded material must be reported exactly once, got: %s" % report)
	assert_true(report.contains(FIXTURE_MATERIAL), "the report must name the seeded file, got: %s" % report)

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The scan roots are empty in this wave, so a
## per-asset assertion would execute zero assertions and the runner fails any
## test that does -- correctly, since it cannot tell an empty loop from one a
## runtime error aborted. The check is unchanged: it fails on exactly the same
## assets and still names every one of them. Placing the assertion after the
## walk also keeps the runner's guard meaningful here, because an error inside
## the loop aborts before the assertion runs and the guard still fires.
func test_every_material_in_the_project_is_on_palette() -> void:
	var offenders := _collect_palette_offenders(AssetScannerScript.SCAN_ROOTS)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
