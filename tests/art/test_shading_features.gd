extends TestCase

## Rule 8 of the Art Bible: the banned list. Flat color only -- the light
## does the work.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

func _violations(material: BaseMaterial3D) -> PackedStringArray:
	var problems := PackedStringArray()
	# ORMMaterial3D exists to pack occlusion, roughness, and metallic into a
	# single texture -- precisely the maps rule 8 forbids. It is a
	# BaseMaterial3D but not a StandardMaterial3D, so without this branch it
	# would pass the gate no matter what it contains.
	if material is ORMMaterial3D:
		problems.append("ORMMaterial3D packs occlusion/roughness/metallic, which the banned list forbids")
		return problems
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if standard.normal_enabled:
			problems.append("normal map enabled")
		if standard.roughness_texture != null:
			problems.append("roughness texture assigned")
		if standard.metallic_texture != null:
			problems.append("metallic texture assigned")
		if standard.metallic > 0.0:
			problems.append("metallic is %f, must be 0" % standard.metallic)
		if standard.specular_mode != BaseMaterial3D.SPECULAR_DISABLED:
			problems.append("specular is enabled, must be SPECULAR_DISABLED")
	return problems

func test_the_gate_catches_a_banned_feature() -> void:
	var offender := StandardMaterial3D.new()
	offender.metallic = 0.8
	var problems := _violations(offender)
	assert_true(problems.size() > 0, "a metallic material must be flagged")

func test_the_gate_accepts_a_compliant_material() -> void:
	var good := StandardMaterial3D.new()
	good.metallic = 0.0
	good.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var problems := _violations(good)
	assert_eq(problems.size(), 0, "a flat, non-metallic, non-specular material must pass")

func test_the_gate_catches_an_orm_material() -> void:
	var offender := ORMMaterial3D.new()
	var problems := _violations(offender)
	assert_true(problems.size() > 0, "ORMMaterial3D packs the exact maps the banned list forbids")

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The scan roots are empty in this wave, so a
## per-asset assertion would execute zero assertions and the runner fails any
## test that does -- correctly, since it cannot tell an empty loop from one a
## runtime error aborted. The check is unchanged: it fails on exactly the same
## materials and still names every one of them and every rule they break.
func test_no_material_in_the_project_uses_a_banned_feature() -> void:
	var offenders := PackedStringArray()
	for root in AssetScannerScript.SCAN_ROOTS:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is BaseMaterial3D):
				continue
			var problems := _violations(resource as BaseMaterial3D)
			if problems.size() > 0:
				offenders.append("%s violates the banned list: %s" % [path, ", ".join(problems)])
	assert_eq(offenders.size(), 0, "; ".join(offenders))
