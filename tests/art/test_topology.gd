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

## Offenders are collected and asserted on once, after the walk, rather than
## asserted per asset inside it. The budgeted folders are empty in this wave,
## so a per-asset assertion would execute zero assertions and the runner fails
## any test that does -- correctly, since it cannot tell an empty loop from one
## a runtime error aborted. The check is unchanged: it fails on exactly the
## same meshes and still names every one of them.
func test_every_mesh_is_within_its_budget() -> void:
	var offenders := PackedStringArray()
	for root in BUDGETS.keys():
		var budget: int = BUDGETS[root]
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MESH_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is Mesh):
				continue
			var count := _triangle_count(resource as Mesh)
			if not _within_budget(count, budget):
				offenders.append(
					"%s has %d triangles, over the %d budget for %s" % [path, count, budget, root]
				)
	assert_eq(offenders.size(), 0, "; ".join(offenders))
