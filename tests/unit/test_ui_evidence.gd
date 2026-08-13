extends TestCase

const Evidence := preload("res://tools/ui_evidence.gd")


func _solid(size := Vector2i(8, 8), colour := Color.WHITE) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return image


func test_delivered_ink_measures_the_core_against_its_actual_plate() -> void:
	var plate := _solid()
	var shot := _solid()
	for y in range(2, 6):
		for x in range(2, 6):
			shot.set_pixel(x, y, Color.BLACK)
	var report: Dictionary = Evidence.measure_delivered_ink(
		plate, shot, Vector2(8, 8), Rect2(1, 1, 6, 6))
	assert_true(bool(report.get("ok", false)), str(report))
	assert_eq(int(report.get("ink_pixels", 0)), 16)
	assert_almost_eq(float(report.get("core_contrast", 0.0)), 21.0, 0.01)


func test_measurement_rejects_a_rect_that_contains_no_delivered_ink() -> void:
	var plate := _solid()
	var report: Dictionary = Evidence.measure_delivered_ink(
		plate, plate, Vector2(8, 8), Rect2(1, 1, 6, 6))
	assert_false(bool(report.get("ok", false)))
	assert_true(str(report.get("reason", "")).contains("no delivered ink"))


func test_boundary_occupancy_enforces_a_small_in_frame_transient() -> void:
	var report: Dictionary = Evidence.boundary_occupancy(
		Rect2(54, 274, 138, 22), Vector2(1152, 720))
	assert_true(bool(report.get("inside_frame", false)))
	assert_true(float(report.get("frame_fraction", 1.0)) < Evidence.TRANSIENT_MAX_FRAME_OCCUPANCY)
	assert_true(Evidence.is_anchored_to_edge(
		Rect2(54, 274, 138, 22), Vector2(1152, 720), 54.0, &"left"))
	assert_false(Evidence.is_anchored_to_edge(
		Rect2(55, 274, 138, 22), Vector2(1152, 720), 54.0, &"left"))


func test_key_ink_occlusion_counts_only_ink_lost_to_a_front_layer() -> void:
	var plate := _solid()
	var clear := _solid()
	var front := _solid()
	for x in range(2, 6):
		clear.set_pixel(x, 3, Color.BLACK)
		front.set_pixel(x, 3, Color.BLACK)
	front.set_pixel(2, 3, Color(0.5, 0.5, 0.5))
	var report: Dictionary = Evidence.key_ink_occlusion_fraction(
		plate, clear, front, Vector2(8, 8), Rect2(1, 1, 6, 6))
	assert_true(bool(report.get("ok", false)), str(report))
	assert_almost_eq(float(report.get("fraction", 0.0)), 0.25, 0.001)


func test_occlusion_gate_requires_more_than_a_quarter_second_of_failure() -> void:
	assert_false(Evidence.exceeds_sustained_occlusion([0.11, 0.11], 0.10))
	assert_true(Evidence.exceeds_sustained_occlusion([0.11, 0.11, 0.11], 0.10))
	assert_false(Evidence.exceeds_sustained_occlusion([0.11, 0.0, 0.11, 0.11], 0.10))
