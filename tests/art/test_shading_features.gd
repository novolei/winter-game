extends TestCase

## Rule 8 of the Art Bible: the banned list. Flat color only -- the light
## does the work.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

## Seeded under user://, deliberately not under a scan root: the project-wide
## test must keep measuring the project, not this fixture.
##
## One subfolder per shape, each scanned on its own, so every end-to-end test
## can still assert "reported exactly once" without the other fixtures'
## offenders inflating the count.
const FIXTURE_ROOT := "user://shading_gate_fixture"
const LOOSE_ROOT := "user://shading_gate_fixture/loose"
const LOOSE_MATERIAL := "user://shading_gate_fixture/loose/banned.tres"
const SCENE_ROOT := "user://shading_gate_fixture/scene"
const SCENE_FILE := "user://shading_gate_fixture/scene/embedded.tscn"
const SHADER_ROOT := "user://shading_gate_fixture/shader"
const SHADER_MATERIAL := "user://shading_gate_fixture/shader/custom.tres"
const GRADIENT_ROOT := "user://shading_gate_fixture/gradient"
const GRADIENT_MATERIAL := "user://shading_gate_fixture/gradient/albedo_gradient.tres"

## A real .glb, produced by tools/generate_gate_fixtures.gd and committed with
## its .import companion. Outside SCAN_ROOTS so the project-wide scan does not
## see it.
const GLB_ROOT := "res://tests/fixtures"
const GLB_FILE := "res://tests/fixtures/gate_probe_model.glb"

func before_each() -> void:
	for folder in [LOOSE_ROOT, SCENE_ROOT, SHADER_ROOT, GRADIENT_ROOT]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

	var offender := StandardMaterial3D.new()
	offender.metallic = 0.8
	ResourceSaver.save(offender, LOOSE_MATERIAL)

	ResourceSaver.save(_scene_with_a_banned_surface(), SCENE_FILE)

	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.5); }"
	shader_material.shader = shader
	ResourceSaver.save(shader_material, SHADER_MATERIAL)

	var gradient_material := StandardMaterial3D.new()
	gradient_material.albedo_texture = _gradient_texture()
	ResourceSaver.save(gradient_material, GRADIENT_MATERIAL)

func after_each() -> void:
	var paths := [
		LOOSE_MATERIAL, SCENE_FILE, SHADER_MATERIAL, GRADIENT_MATERIAL,
		LOOSE_ROOT, SCENE_ROOT, SHADER_ROOT, GRADIENT_ROOT, FIXTURE_ROOT,
	]
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Rule 8's last line bans "any form of colour gradient", and a GradientTexture2D
## is the literal article.
func _gradient_texture() -> Texture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#00FF00"))
	ramp.set_color(1, Color("#FF00FF"))
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.width = 4
	texture.height = 4
	return texture

## The shape an imported model actually has, and the one a node-property walk
## misses: the material is not on the MeshInstance3D, it is on the mesh's
## surface. Verified against a real imported .glb -- see GLB_FILE.
func _scene_with_a_banned_surface() -> PackedScene:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.metallic = 0.8
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	# Every Node this test allocated is freed here, on every path: pack() has
	# copied what it needs (briefing section 2.2).
	root.free()
	return packed

func _violations(material: BaseMaterial3D) -> PackedStringArray:
	var problems := PackedStringArray()
	# Rule 8's last line bans "any form of colour gradient", and the pipeline
	# (Art Bible section 5) generates no in-game textures at all -- 12 colours plus
	# cel shading do not need one. Checked on BaseMaterial3D rather than inside
	# the StandardMaterial3D branch below because albedo_texture is declared
	# there, so every subclass carries it.
	if material.albedo_texture != null:
		problems.append("albedo texture assigned (%s); rule 8 bans colour gradients and the pipeline generates no in-game textures" % material.albedo_texture.get_class())
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

## The gate's whole walk-load-judge body, with the roots as a parameter so the
## exact code path the project-wide scan uses can also be aimed at a seeded
## fixture root. That parameter is the only reason this gate is testable at
## all right now: the project's scan roots are empty, so a broken scan and an
## empty folder produce identical results.
func _collect_banned_feature_offenders(roots: Array[String]) -> PackedStringArray:
	var offenders := PackedStringArray()
	for root in roots:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			# Rule 8's banned list is a rule about the world. Characters are
			# exempt -- see AssetScanner.SURFACE_RULE_EXEMPT_ROOTS, and the test
			# below that proves the exemption is load-bearing.
			if AssetScannerScript.is_surface_rule_exempt(path):
				continue
			offenders.append_array(_offenders_in(path, AssetProbeScript.probe(path)))
	return offenders

## Judges one already-probed file. Split from the walk above so the
## unloadable branch is reachable from a test: a real corrupt file does return
## null from ResourceLoader, but it prints three ERROR: lines doing it and a
## run whose console is dirty is a failed run (briefing section 2.1). Everything here
## is the production path; only the way the null arrives is substituted.
func _offenders_in(path: String, probe: Dictionary) -> PackedStringArray:
	var offenders := PackedStringArray()
	if probe["error"] != "":
		offenders.append("%s %s" % [path, probe["error"]])
		return offenders
	for entry in probe["materials"]:
		offenders.append_array(
			_banned_feature_offenders_for(entry["label"], entry["resource"], AssetProbeScript.EXEMPT_SHADERS)
		)
	return offenders

## Judges one material found anywhere inside one file. Every path out of here
## either passes it, names it, or is an exemption someone wrote down -- there
## is no fourth branch that quietly does none of the three, which is what the
## old `not (resource is BaseMaterial3D): continue` amounted to.
##
## `exempt_shaders` is threaded through rather than read from the const so the
## exemption branch is reachable from a test while the shipped allowlist is
## empty.
func _banned_feature_offenders_for(label: String, material: Material, exempt_shaders: Array[String]) -> PackedStringArray:
	var offenders := PackedStringArray()
	var unreadable := AssetProbeScript.unreadable_reason(material, exempt_shaders)
	if unreadable != "":
		offenders.append("%s %s" % [label, unreadable])
		return offenders
	if not (material is BaseMaterial3D):
		# An allowlisted ShaderMaterial. Not a silent skip: the exemption *is*
		# the decision that this gate cannot read it and that someone accepted
		# that in writing. Passing one to _violations() would hand its
		# BaseMaterial3D parameter a null and abort this function mid-walk.
		return offenders
	var problems := _violations(material as BaseMaterial3D)
	if problems.size() > 0:
		offenders.append("%s violates the banned list: %s" % [label, ", ".join(problems)])
	return offenders

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

## W1-B4. Rule 8's last line bans any form of colour gradient, and the asset
## pipeline generates no in-game textures at all. Until this check existed, a
## material carrying a gradient albedo passed both this gate and the palette
## gate whenever its albedo_color happened to be on-palette -- the ban was
## written down and enforced nowhere.
func test_the_gate_catches_a_gradient_albedo_texture() -> void:
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#76889F")
	offender.metallic = 0.0
	offender.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	offender.albedo_texture = _gradient_texture()
	var problems := _violations(offender)
	assert_true(problems.size() > 0, "an on-palette material carrying a gradient albedo texture must still be flagged")

## Joins the two halves the other tests each prove separately: the predicate
## above, and the walker in test_asset_scanner.gd. Runs the real chain
## -- find_files -> ResourceLoader.load -> type filter -> offender message --
## against a real file on disk. Without this, emptying MATERIAL_SUFFIXES or
## inverting the type filter leaves the entire suite green, because the
## project's scan roots are empty and nothing would notice.
func test_the_gate_finds_a_banned_material_on_disk() -> void:
	var offenders := _collect_banned_feature_offenders([LOOSE_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the seeded material must be reported exactly once, got: %s" % report)
	assert_true(report.contains(LOOSE_MATERIAL), "the report must name the seeded file, got: %s" % report)

## W1-B2. The loaded resource is a PackedScene, not a material; the material is
## a sub-resource on a mesh surface inside it. A gate that judges only what
## ResourceLoader handed back sees nothing here and passes.
func test_the_gate_finds_a_banned_material_inside_a_scene() -> void:
	var offenders := _collect_banned_feature_offenders([SCENE_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the material inside the scene must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SCENE_FILE), "the report must name the seeded scene, got: %s" % report)

## W1-B4, end to end. The predicate test above proves the rule; this proves the
## rule is reached by the real walk over a real file.
func test_the_gate_finds_a_gradient_albedo_on_disk() -> void:
	var offenders := _collect_banned_feature_offenders([GRADIENT_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the gradient-albedo material must be reported exactly once, got: %s" % report)
	assert_true(report.contains(GRADIENT_MATERIAL), "the report must name the seeded file, got: %s" % report)

## W1-B3. A ShaderMaterial is not a BaseMaterial3D, so this gate cannot read a
## single banned feature off it. That must be a visible, deliberate exemption
## rather than a silent skip: not on the allowlist means offender.
func test_an_unlisted_shader_material_is_an_offender() -> void:
	var offenders := _collect_banned_feature_offenders([SHADER_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the unlisted ShaderMaterial must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SHADER_MATERIAL), "the report must name the seeded file, got: %s" % report)

## W1-B6. A corrupt, missing, or never-imported asset used to hit
## `resource == null: continue` and pass every gate while the engine printed an
## error nothing was reading. It is an offender now.
func test_an_unloadable_asset_is_an_offender() -> void:
	var path := "res://assets/models/props/corrupt.glb"
	var offenders := _offenders_in(path, AssetProbeScript.probe_resource(path, null))
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "an unloadable asset must be reported exactly once, got: %s" % report)
	assert_true(report.contains(path), "the report must name it, got: %s" % report)

## The other half of W1-B3, and the branch the shipped allowlist cannot reach
## while it is empty: once a shader *is* written down, this gate must leave its
## material alone rather than hand _violations() the null that
## `shader_material as BaseMaterial3D` produces, which would abort the walk and
## take every offender after it down too.
func test_an_allowlisted_shader_material_is_left_alone() -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;"
	shader.resource_path = "res://src/rendering/two_band_cel.gdshader"
	material.shader = shader
	var offenders := _banned_feature_offenders_for(
		"res://x.tres", material, ["res://src/rendering/two_band_cel.gdshader"] as Array[String]
	)
	assert_eq(offenders.size(), 0, "a written-down shader must pass without being read, got: %s" % "; ".join(offenders))

## W1-B1, end to end against a real imported model rather than a stand-in.
func test_the_gate_finds_a_banned_material_inside_a_real_glb() -> void:
	var offenders := _collect_banned_feature_offenders([GLB_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the material inside %s must be reported exactly once, got: %s" % [GLB_FILE, report])
	assert_true(report.contains(GLB_FILE), "the report must name the .glb, got: %s" % report)

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The scan roots are empty in this wave, so a
## per-asset assertion would execute zero assertions and the runner fails any
## test that does -- correctly, since it cannot tell an empty loop from one a
## runtime error aborted. The check is unchanged: it fails on exactly the same
## materials and still names every one of them and every rule they break.
func test_no_material_in_the_project_uses_a_banned_feature() -> void:
	var offenders := _collect_banned_feature_offenders(AssetScannerScript.SCAN_ROOTS)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The other half of the same decision -- see the matching test in
## test_palette.gd for why an exemption gets a test of its own. Rule 8's banned
## list is about the world; the protagonist ships with the normal, roughness and
## metallic maps it was generated with.
func test_characters_are_exempt_and_the_exemption_is_load_bearing() -> void:
	var character := "res://assets/models/characters/winter_wanderer.glb"
	assert_true(FileAccess.file_exists(character), "the exempt character must exist: %s" % character)
	assert_true(
		AssetScannerScript.is_surface_rule_exempt(character),
		"the character must be exempt from the surface rules"
	)
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/props/lantern.glb"),
		"the exemption must not reach props"
	)

	var direct := _offenders_in(character, AssetProbeScript.probe(character))
	assert_true(
		direct.size() > 0,
		"the exemption reports as load-bearing only while the character actually carries "
		+ "something this gate rejects; it now carries nothing, so either the model changed "
		+ "or the exemption is no longer needed. Decide which -- do not delete this assertion."
	)

	var report := "; ".join(_collect_banned_feature_offenders(AssetScannerScript.SCAN_ROOTS))
	assert_false(report.contains(character), "the project-wide scan must not report it: %s" % report)
