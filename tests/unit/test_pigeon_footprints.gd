extends TestCase

const FootprintsScript := preload("res://src/entities/wildlife/pigeon_footprints.gd")
const PigeonScript := preload("res://src/entities/wildlife/pigeon.gd")
const PALETTE: ColorBible = preload("res://data/palette/color_bible.tres")


func test_many_pigeon_marks_remain_one_small_multimesh_draw() -> void:
	var marks := FootprintsScript.new()
	marks.setup()
	assert_not_null(marks.multimesh, "the footprint pool did not build")
	assert_eq(marks.multimesh.instance_count, 48, "the bounded pool changed size")
	assert_eq(marks.multimesh.mesh.get_faces().size() / 3, 8, "the four-toed silhouette stopped being a tiny mesh")
	for index in 40:
		marks.stamp(Vector3(float(index) * 0.03, 0.0, 0.0), Vector3.FORWARD, 0.2)
	assert_eq(marks.active_count(), 40, "forty marks became forty nodes instead of pooled instances")
	assert_eq(marks.get_child_count(), 0, "the pooled renderer created one node per footprint")
	assert_true(marks.custom_aabb.has_volume(), "the live pool has no culling bounds and will never draw")
	assert_true(
		marks.multimesh.mesh.get_aabb().size.x >= 0.09,
		"the calligraphic foot is below the readable width of the widest camera framing"
	)
	assert_true(
		PigeonScript.FOOTSTEP_WIDTH_M * 2.0 >= marks.multimesh.mesh.get_aabb().size.x,
		"left and right prints overlap into the dark dash the bird-track shape replaced"
	)
	var ink := marks.material_override as StandardMaterial3D
	assert_not_null(ink, "the tracks have no snow-contrast material")
	if ink != null:
		assert_eq(ink.albedo_color, PALETTE.snow_tones[3], "the track returned to near-black ink")
		assert_eq(ink.cull_mode, BaseMaterial3D.CULL_DISABLED, "flat toes disappear from above")
	marks.free()


func test_wind_erases_a_pigeon_track_quickly_and_without_a_pop() -> void:
	var marks := FootprintsScript.new()
	marks.setup()
	var calm := marks.lifetime_for(0.0)
	var gale := marks.lifetime_for(1.0)
	assert_true(gale < calm, "wind does not shorten the mark's already brief life")
	assert_true(calm <= 6.0 and gale <= 2.5, "pigeon prints linger like the traveller's physical trail")
	marks.stamp(Vector3.ZERO, Vector3.FORWARD, 1.0)
	var opening_scale := marks.instance_scale(0)
	marks.advance(gale * 0.75)
	var fading_scale := marks.instance_scale(0)
	assert_true(fading_scale > 0.0 and fading_scale < opening_scale, "the mark popped instead of snow closing over it")
	marks.advance(gale)
	assert_eq(marks.active_count(), 0, "the gale-aged print never disappeared")
	assert_almost_eq(marks.instance_scale(0), 0.0, 0.0001, "an expired print still draws")
	marks.free()
