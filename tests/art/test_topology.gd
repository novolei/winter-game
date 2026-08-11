extends TestCase

## Rule 6 of the Art Bible: triangle budgets by asset class. The budget is
## keyed off the folder an asset lives in.

const BUDGETS := {
	"res://assets/models/buildings": 500,
	"res://assets/models/props": 200,
	"res://assets/models/vegetation": 300,
	"res://assets/models/characters": 8000,
}

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

## Seeded under user://, deliberately not under a budgeted folder: the
## project-wide test must keep measuring the project, not this fixture.
##
## One subfolder per shape, each scanned on its own, so every end-to-end test
## can still assert "reported exactly once" without the other fixtures'
## offenders inflating the count.
const FIXTURE_ROOT := "user://topology_gate_fixture"
const LOOSE_ROOT := "user://topology_gate_fixture/loose"
const LOOSE_MESH := "user://topology_gate_fixture/loose/over_budget.tres"
const SCENE_ROOT := "user://topology_gate_fixture/scene"
const SCENE_FILE := "user://topology_gate_fixture/scene/over_budget.tscn"
const POINTS_ROOT := "user://topology_gate_fixture/points"
const POINTS_MESH := "user://topology_gate_fixture/points/point_cloud.tres"
const FIXTURE_BUDGET := 200

## A real .glb, produced by tools/generate_gate_fixtures.gd and committed with
## its .import companion. Outside SCAN_ROOTS so the project-wide scan does not
## see it. It holds two triangles, so a budget of 1 makes it an offender.
const GLB_ROOT := "res://tests/fixtures"
const GLB_FILE := "res://tests/fixtures/gate_probe_model.glb"
const GLB_BUDGET := 1

func before_each() -> void:
	for folder in [LOOSE_ROOT, SCENE_ROOT, POINTS_ROOT]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	# A default SphereMesh is thousands of triangles, so it is over any budget
	# this project sets for a prop without depending on an exact count here.
	ResourceSaver.save(SphereMesh.new(), LOOSE_MESH)
	ResourceSaver.save(_scene_with_an_over_budget_mesh(), SCENE_FILE)
	# A PointMesh has a surface carrying a vertex but no triangles at all, so
	# no triangle count can be produced for it.
	ResourceSaver.save(PointMesh.new(), POINTS_MESH)

func after_each() -> void:
	var paths := [
		LOOSE_MESH, SCENE_FILE, POINTS_MESH,
		LOOSE_ROOT, SCENE_ROOT, POINTS_ROOT, FIXTURE_ROOT,
	]
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _scene_with_an_over_budget_mesh() -> PackedScene:
	var root := Node3D.new()
	root.name = "Root"
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = SphereMesh.new()
	root.add_child(instance)
	instance.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	# Every Node this test allocated is freed here, on every path: pack() has
	# copied what it needs (briefing section 2.2).
	root.free()
	return packed

## Returns {"count": int} for a mesh that could be counted, or {"error": String}
## for one that could not.
##
## A Dictionary rather than an int, and that is the entire fix for W1-B7.
##
## A GDScript runtime error inside a function does not merely log: the VM drops
## the rest of the function and returns the return type's default. For `-> int`
## that default is 0, and 0 triangles is within every budget that exists, so
## the counter's failure mode was to report the mesh as tiny and pass it. A
## sentinel like -1 fixes the branches this function chooses to take and does
## nothing at all about the abort, which never reaches a return statement. The
## default of `-> Dictionary` is {}, which carries neither key, so the abort
## itself becomes an offender.
##
## The count comes from Mesh.get_faces(), the engine's own triangulation,
## rather than from dividing a vertex or index array by three. That division is
## only right for PRIMITIVE_TRIANGLES: a triangle strip of N vertices is N-2
## triangles, so a 900-vertex strip was being counted as 300 and waved past a
## 500 budget. get_faces() is correct for indexed, non-indexed and strip
## surfaces alike -- verified on 4.7.1 against all three.
func _triangle_count(mesh: Mesh) -> Dictionary:
	var faces := mesh.get_faces()
	if faces.size() % 3 != 0:
		return {"error": "the engine triangulated it into %d vertices, which is not a whole number of triangles" % faces.size()}
	var count := faces.size() / 3
	# get_faces() returns empty both for a mesh with no triangles and for a
	# mesh it failed to read, and only one of those is a real zero. If the
	# surfaces carry vertices but produced no triangles, this gate does not
	# know how many triangles the asset has, and must say so rather than call
	# it zero.
	if count == 0 and _carries_vertices(mesh):
		return {"error": "its %d surface(s) carry vertices but the engine triangulated none of them, so it is not built from triangles and no budget can be checked against it" % mesh.get_surface_count()}
	return {"count": count}

## Whether any surface holds at least one vertex.
func _carries_vertices(mesh: Mesh) -> bool:
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		# surface_get_arrays() returns null for slots the surface does not
		# use, and assigning null into a typed PackedVector3Array is a runtime
		# error that aborts this function. Read it untyped and null-check
		# before casting (briefing trap 5).
		var vertex_slot = arrays[Mesh.ARRAY_VERTEX]
		if vertex_slot != null and (vertex_slot as PackedVector3Array).size() > 0:
			return true
	return false

## The budget for an asset at `path`: the value of the longest BUDGETS key that
## is a parent folder of it, or -1 when no key covers it.
##
## Longest match wins so a future res://assets/models/props/tiny key can
## tighten the budget for a subfolder without the parent key shadowing it.
func _budget_for(path: String, budgets: Dictionary) -> int:
	var budget := -1
	var matched := -1
	for root in budgets.keys():
		if not path.begins_with(root + "/"):
			continue
		if root.length() > matched:
			matched = root.length()
			budget = budgets[root]
	return budget

## The gate's actual decision, factored out so it can be tested against a
## violating and a compliant case. Inlined in the scan loop it would be
## unreachable while the asset folders are empty, and a reversed or
## off-by-one comparison would pass forever.
func _within_budget(triangle_count: int, budget: int) -> bool:
	return triangle_count <= budget

## The gate's whole walk-load-judge body, with the roots and the budget map as
## parameters so the exact code path the project-wide scan uses can also be
## aimed at a seeded fixture root. Those parameters are the only reason this
## gate is testable at all right now: the budgeted folders are empty, so a
## broken scan and an empty folder produce identical results.
##
## Roots and budgets are separate arguments because they answer separate
## questions. The roots say what gets walked; the budgets say what each asset
## is judged against. Walking BUDGETS.keys() conflated the two, and every mesh
## outside those four folders was therefore never walked at all.
func _collect_budget_offenders(roots: Array[String], budgets: Dictionary) -> PackedStringArray:
	var offenders := PackedStringArray()
	for root in roots:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MESH_SUFFIXES):
			offenders.append_array(_offenders_in(path, AssetProbeScript.probe(path), budgets))
	return offenders

## Judges one already-probed file. Split from the walk above so the
## unloadable branch is reachable from a test: a real corrupt file does return
## null from ResourceLoader, but it prints three ERROR: lines doing it and a
## run whose console is dirty is a failed run (briefing section 2.1). Everything here
## is the production path; only the way the null arrives is substituted.
func _offenders_in(path: String, probe: Dictionary, budgets: Dictionary) -> PackedStringArray:
	var offenders := PackedStringArray()
	if probe["error"] != "":
		offenders.append("%s %s" % [path, probe["error"]])
		return offenders
	var meshes: Array = probe["meshes"]
	if meshes.is_empty():
		return offenders
	var budget := _budget_for(path, budgets)
	# Reported once for the file rather than once per mesh: the fix is a single
	# line in BUDGETS either way, and a 40-mesh scene would otherwise bury every
	# other offender under forty copies of it.
	if budget < 0:
		offenders.append(
			"%s holds %d mesh(es) but no budget covers its path -- add a BUDGETS key for it or move the asset under one" % [path, meshes.size()]
		)
		return offenders
	for entry in meshes:
		var label: String = entry["label"]
		var counted := _triangle_count(entry["resource"])
		if not counted.has("count"):
			offenders.append(
				"%s could not be counted: %s" % [label, counted.get("error", "the counter returned nothing at all, so it aborted partway")]
			)
			continue
		var count: int = counted["count"]
		if not _within_budget(count, budget):
			offenders.append(
				"%s has %d triangles, over the %d budget" % [label, count, budget]
			)
	return offenders

func test_the_gate_counts_an_indexed_mesh() -> void:
	# A BoxMesh is 6 quads = 12 triangles, and PrimitiveMesh always indexes.
	var box := BoxMesh.new()
	# .get("count", -1) rather than ["count"]: a missing key must read as a
	# wrong answer, not abort the test with a runtime error.
	assert_eq(_triangle_count(box).get("count", -1), 12, "a box should count as 12 triangles")

func test_the_gate_counts_a_non_indexed_mesh() -> void:
	# The branch a BoxMesh never reaches. Built without an ARRAY_INDEX entry.
	var vertices := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert_eq(_triangle_count(mesh).get("count", -1), 2, "six unindexed vertices are two triangles")

## A triangle strip of N vertices is N-2 triangles, not N/3. Counting a
## 900-vertex strip as 300 triangles instead of 898 lets a mesh three times
## over its budget through -- the gate's failure mode is to pass, again.
func test_the_gate_counts_a_triangle_strip() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	assert_eq(_triangle_count(mesh).get("count", -1), 2, "a four-vertex triangle strip is two triangles")

## W1-B7 at the unit level. A PointMesh has a surface carrying a vertex and no
## triangles at all: the old counter divided that one vertex by three, got 0,
## and 0 is within every budget.
func test_an_uncountable_mesh_yields_no_count() -> void:
	var counted := _triangle_count(PointMesh.new())
	assert_false(counted.has("count"), "a mesh with no triangles must not report a triangle count, got: %s" % counted)
	assert_true(counted.get("error", "") != "", "it must say why instead, got: %s" % counted)

func test_the_gate_rejects_a_count_over_budget() -> void:
	assert_false(_within_budget(501, 500), "501 triangles must fail a 500 budget")

func test_the_gate_accepts_a_count_at_budget() -> void:
	assert_true(_within_budget(500, 500), "exactly the budget must pass")

## Joins the halves the other tests each prove separately: the counter, the
## comparison, and the walker in test_asset_scanner.gd. Runs the real chain
## -- find_files -> ResourceLoader.load -> type filter -> count -> compare --
## against a real mesh on disk. Without this, emptying MESH_SUFFIXES leaves
## the entire suite green, because the budgeted folders are empty and nothing
## would notice.
func test_the_gate_finds_an_over_budget_mesh_on_disk() -> void:
	var offenders := _collect_budget_offenders([LOOSE_ROOT] as Array[String], {LOOSE_ROOT: FIXTURE_BUDGET})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the seeded mesh must be reported exactly once, got: %s" % report)
	assert_true(report.contains(LOOSE_MESH), "the report must name the seeded file, got: %s" % report)

## W1-B2. The loaded resource is a PackedScene, not a mesh; the mesh is a
## sub-resource on a node inside it. A gate that judges only what
## ResourceLoader handed back sees nothing here and passes.
func test_the_gate_finds_an_over_budget_mesh_inside_a_scene() -> void:
	var offenders := _collect_budget_offenders([SCENE_ROOT] as Array[String], {SCENE_ROOT: FIXTURE_BUDGET})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the mesh inside the scene must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SCENE_FILE), "the report must name the seeded scene, got: %s" % report)

## W1-B5. The old gate walked BUDGETS.keys(), so a mesh anywhere else was never
## even looked at. Walking the scan roots instead means such a mesh is now
## found -- and having found it, the gate must say so rather than wave it
## through for want of a number to compare against.
func test_a_mesh_under_no_budget_is_an_offender() -> void:
	var offenders := _collect_budget_offenders([LOOSE_ROOT] as Array[String], {})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "a mesh with no budget must be reported exactly once, got: %s" % report)
	assert_true(report.contains(LOOSE_MESH), "the report must name the unbudgeted file, got: %s" % report)
	# Without this the test passes for the wrong reason: a missing budget read
	# as the sentinel -1 makes every mesh "over the -1 budget", which is an
	# offender by accident and reports a number that does not exist.
	assert_true(report.contains("no budget"), "the report must say the budget is missing, not compare against a sentinel, got: %s" % report)

## W1-B7. A mesh whose triangles cannot be counted must be an offender, not a
## zero. Zero passes every budget, which is exactly the failure mode this whole
## task exists to remove.
func test_an_uncountable_mesh_is_an_offender() -> void:
	var offenders := _collect_budget_offenders([POINTS_ROOT] as Array[String], {POINTS_ROOT: FIXTURE_BUDGET})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "an uncountable mesh must be reported exactly once, got: %s" % report)
	assert_true(report.contains(POINTS_MESH), "the report must name the uncountable file, got: %s" % report)

## W1-B6. A corrupt, missing, or never-imported asset used to hit
## `resource == null: continue` and pass every gate while the engine printed an
## error nothing was reading. It is an offender now.
func test_an_unloadable_asset_is_an_offender() -> void:
	var path := "res://assets/models/props/corrupt.glb"
	var offenders := _offenders_in(path, AssetProbeScript.probe_resource(path, null), BUDGETS)
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "an unloadable asset must be reported exactly once, got: %s" % report)
	assert_true(report.contains(path), "the report must name it, got: %s" % report)

## W1-B1, end to end against a real imported model rather than a stand-in.
func test_the_gate_finds_an_over_budget_mesh_inside_a_real_glb() -> void:
	var offenders := _collect_budget_offenders([GLB_ROOT] as Array[String], {GLB_ROOT: GLB_BUDGET})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the mesh inside %s must be reported exactly once, got: %s" % [GLB_FILE, report])
	assert_true(report.contains(GLB_FILE), "the report must name the .glb, got: %s" % report)

## BUDGETS' keys are hardcoded paths that nothing else checks. Rename or
## misspell one and find_files() returns empty for it, so that asset class
## stops being budgeted with no other test noticing -- the gate reports
## "verified" while inspecting nothing, which is the failure this suite
## exists to prevent.
func test_every_budget_root_exists_on_disk() -> void:
	for root in BUDGETS.keys():
		assert_true(
			DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)),
			"%s is a budget key but not a real folder" % root
		)

## The other half of W1-B5. The gate now walks SCAN_ROOTS and looks each asset's
## budget up by path, which is only equivalent to the old BUDGETS.keys() walk
## while every budgeted folder is inside a scan root. Add a budget for a folder
## nobody walks and that asset class is never opened at all -- the gate reports
## "verified" over an unread folder, which is the exact failure this task
## closed. Nothing else in the suite compares the two lists, and it cannot be
## caught by scanning: both folders are empty in this wave, so an unwalked one
## and a clean one produce identical results.
func test_every_budget_root_is_under_a_scan_root() -> void:
	for root in BUDGETS.keys():
		var walked := false
		for scan_root in AssetScannerScript.SCAN_ROOTS:
			if root == scan_root or (root as String).begins_with(scan_root + "/"):
				walked = true
				break
		assert_true(walked, "%s has a budget but is under no SCAN_ROOT, so nothing ever walks it" % root)

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The budgeted folders are empty in this wave,
## so a per-asset assertion would execute zero assertions and the runner fails
## any test that does -- correctly, since it cannot tell an empty loop from one
## a runtime error aborted. The check is unchanged: it fails on exactly the
## same meshes and still names every one of them.
func test_every_mesh_is_within_its_budget() -> void:
	var offenders := _collect_budget_offenders(AssetScannerScript.SCAN_ROOTS, BUDGETS)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
