extends TestCase

## Rule 9 of the Art Bible: every surface is flat-shaded and its color comes
## from the 12-color palette. This test is the gate.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

## Seeded under user://, deliberately not under a scan root: the project-wide
## test must keep measuring the project, not this fixture.
##
## One subfolder per shape, each scanned on its own, so every end-to-end test
## can still assert "reported exactly once" without the other fixtures'
## offenders inflating the count.
const FIXTURE_ROOT := "user://palette_gate_fixture"
const LOOSE_ROOT := "user://palette_gate_fixture/loose"
const LOOSE_MATERIAL := "user://palette_gate_fixture/loose/off_palette.tres"
const SCENE_ROOT := "user://palette_gate_fixture/scene"
const SCENE_FILE := "user://palette_gate_fixture/scene/embedded.tscn"
const SHADER_ROOT := "user://palette_gate_fixture/shader"
const SHADER_MATERIAL := "user://palette_gate_fixture/shader/custom.tres"

## A real .glb, produced by tools/generate_gate_fixtures.gd and committed with
## its .import companion. Outside SCAN_ROOTS so the project-wide scan does not
## see it.
const GLB_ROOT := "res://tests/fixtures"
const GLB_FILE := "res://tests/fixtures/gate_probe_model.glb"

var _bible

func before_each() -> void:
	_bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	for folder in [LOOSE_ROOT, SCENE_ROOT, SHADER_ROOT]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	ResourceSaver.save(offender, LOOSE_MATERIAL)

	ResourceSaver.save(_scene_with_an_off_palette_surface(), SCENE_FILE)

	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.0, 1.0, 0.0); }"
	shader_material.shader = shader
	ResourceSaver.save(shader_material, SHADER_MATERIAL)

func after_each() -> void:
	for path in [LOOSE_MATERIAL, SCENE_FILE, SHADER_MATERIAL, LOOSE_ROOT, SCENE_ROOT, SHADER_ROOT, FIXTURE_ROOT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## The shape an imported model actually has, and the one a node-property walk
## misses: the material is not on the MeshInstance3D, it is on the mesh's
## surface. Verified against a real imported .glb -- see GLB_FILE.
func _scene_with_an_off_palette_surface() -> PackedScene:
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
	material.albedo_color = Color("#00FF00")
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

## Judges one material found anywhere inside one file. Every path out of here
## either passes it, names it, or is an exemption someone wrote down -- there
## is no fourth branch that quietly does none of the three, which is what the
## old `not (resource is BaseMaterial3D): continue` amounted to.
##
## `exempt_shaders` is threaded through rather than read from the const so the
## exemption branch is reachable from a test while the shipped allowlist is
## empty.
func _palette_offenders_for(label: String, material: Material, exempt_shaders: Array[String]) -> PackedStringArray:
	var problems := PackedStringArray()
	var unreadable := AssetProbeScript.unreadable_reason(material, exempt_shaders)
	if unreadable != "":
		problems.append("%s %s" % [label, unreadable])
		return problems
	if not (material is BaseMaterial3D):
		# An allowlisted ShaderMaterial. Not a silent skip: the exemption *is*
		# the decision that this gate cannot read it and that someone accepted
		# that in writing. Reaching the cast below with one of these would hand
		# BaseMaterial3D a null and abort this function mid-walk.
		return problems
	var base := material as BaseMaterial3D
	if not _bible.contains(base.albedo_color):
		problems.append(
			"%s uses albedo %s, which is not in the 12-color palette" % [label, base.albedo_color.to_html(false)]
		)
	return problems

## The gate's whole walk-load-judge body, with the roots as a parameter so the
## exact code path the project-wide scan uses can also be aimed at a seeded
## fixture root. That parameter is the only reason this gate is testable at
## all right now: the project's scan roots are empty, so a broken scan and an
## empty folder produce identical results.
func _collect_palette_offenders(roots: Array[String]) -> PackedStringArray:
	var offenders := PackedStringArray()
	for root in roots:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			# Rule 9 is a rule about the world. Characters are exempt -- see
			# AssetScanner.SURFACE_RULE_EXEMPT_ROOTS, and the test below that
			# proves the exemption is load-bearing rather than decorative.
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
			_palette_offenders_for(entry["label"], entry["resource"], AssetProbeScript.EXEMPT_SHADERS)
		)
	return offenders

func test_the_gate_catches_an_off_palette_material() -> void:
	# Proves the check works before any real asset exists.
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	assert_false(_bible.contains(offender.albedo_color), "a pure green material must be rejected")

func test_the_gate_accepts_an_on_palette_material() -> void:
	var good := StandardMaterial3D.new()
	good.albedo_color = Color("#76889F")
	assert_true(_bible.contains(good.albedo_color), "a palette snow tone must be accepted")

## Joins the two halves the other tests each prove separately: the predicate
## above, and the walker in test_asset_scanner.gd. Runs the real chain
## -- find_files -> ResourceLoader.load -> type filter -> offender message --
## against a real file on disk. Without this, emptying MATERIAL_SUFFIXES or
## inverting the type filter leaves the entire suite green, because the
## project's scan roots are empty and nothing would notice.
func test_the_gate_finds_an_off_palette_material_on_disk() -> void:
	var offenders := _collect_palette_offenders([LOOSE_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the seeded material must be reported exactly once, got: %s" % report)
	assert_true(report.contains(LOOSE_MATERIAL), "the report must name the seeded file, got: %s" % report)

## W1-B2. The loaded resource is a PackedScene, not a material; the material is
## a sub-resource on a mesh surface inside it. A gate that judges only what
## ResourceLoader handed back sees nothing here and passes.
func test_the_gate_finds_an_off_palette_material_inside_a_scene() -> void:
	var offenders := _collect_palette_offenders([SCENE_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the material inside the scene must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SCENE_FILE), "the report must name the seeded scene, got: %s" % report)

## W1-B3. A ShaderMaterial is not a BaseMaterial3D, so no palette check can
## read its colours. That must be a visible, deliberate exemption rather than a
## silent skip: not on the allowlist means offender. The allowlist starts
## empty, so this shader -- which is not even a file -- is one.
func test_an_unlisted_shader_material_is_an_offender() -> void:
	var offenders := _collect_palette_offenders([SHADER_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the unlisted ShaderMaterial must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SHADER_MATERIAL), "the report must name the seeded file, got: %s" % report)

## The other half of W1-B3, and the branch the shipped allowlist cannot reach
## while it is empty: once a shader *is* written down, this gate must leave its
## material alone rather than cast it to BaseMaterial3D and abort mid-walk on
## the null that produces. Verified on 4.7.1: `shader_material as
## BaseMaterial3D` is null, and reading albedo_color off it is a SCRIPT ERROR
## that drops the rest of the function -- which would have taken every offender
## after it in the same walk down with it.
func test_an_allowlisted_shader_material_is_left_alone() -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;"
	shader.resource_path = "res://src/rendering/two_band_cel.gdshader"
	material.shader = shader
	var problems := _palette_offenders_for(
		"res://x.tres", material, ["res://src/rendering/two_band_cel.gdshader"] as Array[String]
	)
	assert_eq(problems.size(), 0, "a written-down shader must pass without being read, got: %s" % "; ".join(problems))

## W1-B6. A corrupt, missing, or never-imported asset used to hit
## `resource == null: continue` and pass every gate while the engine printed an
## error nothing was reading. It is an offender now.
func test_an_unloadable_asset_is_an_offender() -> void:
	var path := "res://assets/models/props/corrupt.glb"
	var offenders := _offenders_in(path, AssetProbeScript.probe_resource(path, null))
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "an unloadable asset must be reported exactly once, got: %s" % report)
	assert_true(report.contains(path), "the report must name it, got: %s" % report)

## W1-B1, end to end against a real imported model rather than a stand-in.
## This is the only test in the suite that proves ResourceLoader hands back
## something the gate can descend into for a file Godot *imports* rather than
## loads directly.
func test_the_gate_finds_an_off_palette_material_inside_a_real_glb() -> void:
	var offenders := _collect_palette_offenders([GLB_ROOT] as Array[String])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the material inside %s must be reported exactly once, got: %s" % [GLB_FILE, report])
	assert_true(report.contains(GLB_FILE), "the report must name the .glb, got: %s" % report)

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


## Characters are exempt from rule 9 by the owner's ruling. The exemption is the
## dangerous kind of change -- it makes a gate stop reporting -- so this pins all
## three things a silent skip could never demonstrate:
##
##   it exists, and names a file that is really there;
##   it is scoped to characters and waives nothing else;
##   it is LOAD-BEARING -- the shipped character genuinely is something this
##   gate would report, so the green above is the exemption working and not the
##   gate having quietly found nothing to look at.
##
## The third is the one worth the lines. A gate that is silent for the wrong
## reason is worse than one that fails, and this project has already shipped
## three gates that were green having inspected nothing.
func test_characters_are_exempt_and_the_exemption_is_load_bearing() -> void:
	var character := "res://assets/models/characters/winter_wanderer.glb"
	assert_true(FileAccess.file_exists(character), "the exempt character must exist: %s" % character)
	assert_true(
		AssetScannerScript.is_surface_rule_exempt(character),
		"the character must be exempt from the surface rules"
	)
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/buildings/farmhouse.glb"),
		"the exemption must not reach buildings"
	)
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://scenes/main.tscn"),
		"the exemption must not reach scenes"
	)

	var direct := _offenders_in(character, AssetProbeScript.probe(character))
	assert_true(
		direct.size() > 0,
		"the exemption reports as load-bearing only while the character actually carries "
		+ "something this gate rejects; it now carries nothing, so either the model changed "
		+ "or the exemption is no longer needed. Decide which -- do not delete this assertion."
	)

	var report := "; ".join(_collect_palette_offenders(AssetScannerScript.SCAN_ROOTS))
	assert_false(report.contains(character), "the project-wide scan must not report it: %s" % report)
