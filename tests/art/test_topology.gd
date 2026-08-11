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

## Seeded under user://, deliberately not under a budgeted folder: the
## project-wide test must keep measuring the project, not this fixture.
const FIXTURE_ROOT := "user://topology_gate_fixture"
const FIXTURE_MESH := "user://topology_gate_fixture/over_budget.tres"
const FIXTURE_BUDGET := 200

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))
	# A default SphereMesh is thousands of triangles, so it is over any budget
	# this project sets for a prop without depending on an exact count here.
	ResourceSaver.save(SphereMesh.new(), FIXTURE_MESH)

func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_MESH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))

func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		# surface_get_arrays() returns null for slots the surface does not
		# use, and assigning null into a typed PackedInt32Array is a runtime
		# error that aborts this function. Non-indexed meshes hit exactly
		# that slot, so read it untyped and null-check before casting.
		var index_slot = arrays[Mesh.ARRAY_INDEX]
		if index_slot != null and (index_slot as PackedInt32Array).size() > 0:
			total += (index_slot as PackedInt32Array).size() / 3
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += vertices.size() / 3
	return total

## The gate's actual decision, factored out so it can be tested against a
## violating and a compliant case. Inlined in the scan loop it would be
## unreachable while the asset folders are empty, and a reversed or
## off-by-one comparison would pass forever.
func _within_budget(triangle_count: int, budget: int) -> bool:
	return triangle_count <= budget

## The gate's whole walk-load-judge body, with the budget map as a parameter
## so the exact code path the project-wide scan uses can also be aimed at a
## seeded fixture root. That parameter is the only reason this gate is
## testable at all right now: the budgeted folders are empty, so a broken scan
## and an empty folder produce identical results. It takes the map rather than
## a root list because the budget is keyed off the folder.
func _collect_budget_offenders(budgets: Dictionary) -> PackedStringArray:
	var offenders := PackedStringArray()
	for root in budgets.keys():
		var budget: int = budgets[root]
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MESH_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is Mesh):
				continue
			var count := _triangle_count(resource as Mesh)
			if not _within_budget(count, budget):
				offenders.append(
					"%s has %d triangles, over the %d budget for %s" % [path, count, budget, root]
				)
	return offenders

func test_the_gate_counts_an_indexed_mesh() -> void:
	# A BoxMesh is 6 quads = 12 triangles, and PrimitiveMesh always indexes.
	var box := BoxMesh.new()
	assert_eq(_triangle_count(box), 12, "a box should count as 12 triangles")

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
	assert_eq(_triangle_count(mesh), 2, "six unindexed vertices are two triangles")

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
	var offenders := _collect_budget_offenders({FIXTURE_ROOT: FIXTURE_BUDGET})
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the seeded mesh must be reported exactly once, got: %s" % report)
	assert_true(report.contains(FIXTURE_MESH), "the report must name the seeded file, got: %s" % report)

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

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The budgeted folders are empty in this wave,
## so a per-asset assertion would execute zero assertions and the runner fails
## any test that does -- correctly, since it cannot tell an empty loop from one
## a runtime error aborted. The check is unchanged: it fails on exactly the
## same meshes and still names every one of them.
func test_every_mesh_is_within_its_budget() -> void:
	var offenders := _collect_budget_offenders(BUDGETS)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
