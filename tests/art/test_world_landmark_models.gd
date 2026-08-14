extends TestCase

## The owner's second authored world batch: one scene-scale vehicle matching the
## farm trucks, plus the four missing beacon landmarks named by the GDD. These
## are procedural Blender deliveries, so this gate pins the outputs that matter
## in Godot: identity, silhouette scale, one-mesh draw cost and the Art Bible's
## per-class runaway triangle guards. Readability, not a 200-triangle target,
## controls the authored silhouette for this batch.

const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

const DELIVERIES := {
	"res://assets/models/props/panel_van.glb": {
		"mesh": "Panel_Van", "safety_budget": 5000,
		"minimum": Vector3(2.6, 2.3, 5.7), "maximum": Vector3(3.2, 3.2, 7.0),
	},
	"res://assets/models/buildings/gas_station/gas_station.glb": {
		"mesh": "Gas_Station", "safety_budget": 5000,
		"minimum": Vector3(6.0, 3.0, 4.0), "maximum": Vector3(10.0, 6.0, 8.0),
	},
	"res://assets/models/buildings/church/church.glb": {
		"mesh": "Church", "safety_budget": 5000,
		"minimum": Vector3(4.0, 7.0, 7.0), "maximum": Vector3(7.0, 12.0, 12.0),
	},
	"res://assets/models/buildings/logging_camp/logging_camp.glb": {
		"mesh": "Logging_Camp", "safety_budget": 5000,
		"minimum": Vector3(7.0, 3.0, 5.0), "maximum": Vector3(12.0, 6.0, 9.0),
	},
	"res://assets/models/buildings/transmission_tower/transmission_tower.glb": {
		"mesh": "Transmission_Tower", "safety_budget": 5000,
		"minimum": Vector3(6.0, 12.0, 3.0), "maximum": Vector3(10.0, 18.0, 7.0),
	},
}


func _mesh_instances(path: String) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var packed := load(path) as PackedScene
	if packed == null:
		return found
	var root := packed.instantiate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			found.append(node as MeshInstance3D)
	# Keep the instances alive for the caller while freeing the imported wrapper.
	for instance in found:
		var parent := instance.get_parent()
		if parent != null:
			parent.remove_child(instance)
	root.free()
	return found


func _triangle_count(path: String) -> int:
	var probe := AssetProbeScript.probe(path)
	if probe["error"] != "":
		return -1
	var total := 0
	for entry in probe["meshes"]:
		var mesh: Mesh = entry["resource"]
		total += mesh.get_faces().size() / 3
	return total


func test_every_authored_world_delivery_imports_as_one_named_mesh() -> void:
	for path in DELIVERIES:
		assert_true(ResourceLoader.exists(path), "%s is missing" % path)
		if not ResourceLoader.exists(path):
			continue
		var instances := _mesh_instances(path)
		assert_eq(instances.size(), 1, "%s must be one mesh, not %d draw pieces" % [path, instances.size()])
		if instances.size() != 1:
			for instance in instances:
				instance.free()
			continue
		assert_eq(String(instances[0].name), String(DELIVERIES[path]["mesh"]), "%s carries the wrong mesh identity" % path)
		instances[0].free()


func test_every_delivery_stays_inside_its_authored_budget() -> void:
	assert_true(not DELIVERIES.is_empty(), "the authored delivery table is empty")
	for path in DELIVERIES:
		if not ResourceLoader.exists(path):
			continue
		var count := _triangle_count(path)
		assert_true(count >= 0, "%s could not be counted" % path)
		assert_true(count <= int(DELIVERIES[path]["safety_budget"]), "%s has %d triangles and tripped the %d-triangle runaway guard" % [
			path, count, DELIVERIES[path]["safety_budget"]])


func test_every_delivery_has_the_scene_scale_its_silhouette_requires() -> void:
	assert_true(not DELIVERIES.is_empty(), "the authored delivery table is empty")
	for path in DELIVERIES:
		if not ResourceLoader.exists(path):
			continue
		var instances := _mesh_instances(path)
		if instances.size() != 1:
			for instance in instances:
				instance.free()
			continue
		var size := instances[0].mesh.get_aabb().size
		var minimum: Vector3 = DELIVERIES[path]["minimum"]
		var maximum: Vector3 = DELIVERIES[path]["maximum"]
		assert_true(size.x >= minimum.x and size.x <= maximum.x, "%s width %.2f m is outside %.2f..%.2f" % [path, size.x, minimum.x, maximum.x])
		assert_true(size.y >= minimum.y and size.y <= maximum.y, "%s height %.2f m is outside %.2f..%.2f" % [path, size.y, minimum.y, maximum.y])
		assert_true(size.z >= minimum.z and size.z <= maximum.z, "%s depth %.2f m is outside %.2f..%.2f" % [path, size.z, minimum.z, maximum.z])
		instances[0].free()


func test_every_surface_is_authored_through_the_shared_palette_slots() -> void:
	assert_true(not DELIVERIES.is_empty(), "the authored delivery table is empty")
	for path in DELIVERIES:
		if not ResourceLoader.exists(path):
			continue
		var probe := AssetProbeScript.probe(path)
		assert_eq(probe["error"], "", "%s could not be inspected" % path)
		for entry in probe["materials"]:
			var material: Material = entry["resource"]
			assert_true(material.resource_name.begins_with("PAL_"), "%s ships non-palette material %s" % [path, material.resource_name])
