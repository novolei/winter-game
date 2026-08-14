extends TestCase

## The field needs an actual low winter-wheat crown as well as the planted-row
## marks Farmstead bakes into the snow.  The crown is a single MultiMesh: a
## dense collection of very short tufts, distributed by a deterministic blue
## noise candidate field and thinned by a broad density field.  That is the
## important distinction from the retired tall, evenly spaced stubble.

const LOW_WHEAT_SCRIPT := "res://src/entities/winter_wheat_cover.gd"
const FarmsteadScript := preload("res://src/entities/farmstead.gd")


func test_farmstead_installs_the_low_blue_noise_wheat_cover_in_the_world() -> void:
	assert_true(
		ResourceLoader.exists(LOW_WHEAT_SCRIPT),
		"the dense winter wheat cover must live at %s" % LOW_WHEAT_SCRIPT
	)
	if not ResourceLoader.exists(LOW_WHEAT_SCRIPT):
		return
	var world := Node3D.new()
	world.name = "Main"
	var farmstead: Farmstead = FarmsteadScript.new()
	world.add_child(farmstead)
	Engine.get_main_loop().root.add_child(world)
	var cover := farmstead.get_node_or_null("WinterWheatCover")
	assert_not_null(cover, "the live Farmstead must install exactly one wheat cover under Main")
	if cover != null:
		assert_true(cover.get_script().resource_path == LOW_WHEAT_SCRIPT, "Farmstead installed a different field treatment")
	world.free()


func test_low_wheat_is_dense_short_and_blue_noise_thinned() -> void:
	if not ResourceLoader.exists(LOW_WHEAT_SCRIPT):
		return
	var cover: Node = load(LOW_WHEAT_SCRIPT).new()
	assert_true(cover.get("candidate_spacing_m") <= 0.36, "candidate cells must be close enough to read as a dense crown")
	assert_true(cover.get("tuft_height_m") <= 0.32, "winter wheat must stay below a low 32 cm silhouette")
	assert_true(cover.get("density_floor") < cover.get("density_ceil"), "density needs a real range, not a uniform field")
	assert_true(cover.get("estimated_tuft_count") >= 14000, "the field needs at least 14k short tufts before snow thinning")
	assert_true(cover.get("estimated_triangle_count") <= 200000, "the whole field must remain inside its triangle budget")
	var low := INF
	var high := -INF
	for x in range(-22, 35, 8):
		for z in range(-60, -25, 7):
			var acceptance: float = cover.call("density_at", Vector2(float(x), float(z)))
			low = minf(low, acceptance)
			high = maxf(high, acceptance)
	assert_true(high - low >= 0.08, "separated field patches need visibly different blue-noise acceptance")
	cover.free()


func test_the_dense_field_is_one_draw_and_one_static_build() -> void:
	if not ResourceLoader.exists(LOW_WHEAT_SCRIPT):
		return
	var cover: Node3D = load(LOW_WHEAT_SCRIPT).new()
	Engine.get_main_loop().root.add_child(cover)
	var crowns := cover.get_node_or_null("WinterWheatCrowns") as MultiMeshInstance3D
	assert_not_null(crowns, "the field must collapse all tufts into one MultiMesh draw")
	if crowns != null:
		assert_eq(cover.get_child_count(), 1, "the wheat cover must not create one node per tuft")
		assert_true(crowns.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "small wheat must not spend the shadow budget")
		assert_eq(cover.get("built_tuft_count"), crowns.multimesh.instance_count, "the reported tufts must be the rendered instances")
		assert_true(cover.get("built_triangle_count") <= 200000, "the rendered field must remain below 200k triangles")
	cover.free()
