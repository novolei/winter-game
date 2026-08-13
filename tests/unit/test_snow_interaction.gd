extends TestCase

## The common snow-interaction seam.  These tests deliberately talk only to
## TrackMask's public event boundary: a future knockdown state, an animal or a
## dragged prop must be able to leave a mark without either system holding the
## other or instantiating a Node/Decal per contact.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")

const REQUIRED_TYPES := [
	&"footprint", &"furrow", &"body_press", &"impact", &"drag",
]

var _mask: TrackMask


func before_each() -> void:
	_mask = TrackMaskScript.new()
	_mask.build_at(Vector3.ZERO)


func after_each() -> void:
	_mask.free()
	_mask = null


func test_the_five_interaction_languages_ship_as_data() -> void:
	assert_true(
		_mask.has_method(&"interaction_definition"),
		"TrackMask has no data-driven snow interaction registry"
	)
	if not _mask.has_method(&"interaction_definition"):
		return
	for interaction_id in REQUIRED_TYPES:
		var definition: Variant = _mask.call(&"interaction_definition", interaction_id)
		assert_not_null(definition, "no definition for %s" % interaction_id)
		if definition != null:
			assert_eq(definition.get("interaction_id"), interaction_id)


func test_a_body_press_is_several_contact_areas_not_one_large_black_ellipse() -> void:
	if not _mask.has_method(&"_on_snow_interaction"):
		assert_true(false, "TrackMask does not consume snow.interaction")
		return
	var before_children := _mask.get_child_count()
	_mask.call(&"_on_snow_interaction", {
		"type": &"body_press",
		"subject": &"player",
		"position": Vector3(-10.0, 0.0, -10.0),
		"forward": Vector2.RIGHT,
		"snow_depth_m": 0.48,
		"impulse_ns": 390.0,
		"contacts": [
			{"offset": Vector2(0.00, 0.00), "length": 0.62, "width": 0.34, "weight": 1.0},
			{"offset": Vector2(-0.38, 0.16), "length": 0.34, "width": 0.18, "weight": 0.72},
			{"offset": Vector2(0.35, -0.13), "length": 0.46, "width": 0.17, "weight": 0.66},
		]
	})
	assert_eq(_mask.get_child_count(), before_children, "a body contact created scene nodes")
	var marked := 0
	var saturated := 0
	for ix in range(-12, 13):
		for iz in range(-8, 9):
			var value := _mask.value_at(Vector3(-10.0 + ix * 0.05, 0.0, -10.0 + iz * 0.05))
			if value > 0.03:
				marked += 1
			if value > 0.92:
				saturated += 1
	assert_true(marked > 18, "the body made no readable contact cluster")
	assert_true(
		saturated < maxi(marked / 5, 1),
		"%d of %d contact samples saturated; this is the rejected black body ellipse"
			% [saturated, marked]
	)
	assert_almost_eq(_mask.value_at(Vector3(-8.8, 0.0, -10.0)), 0.0, 0.01)


func test_body_pressure_uses_impulse_over_contact_area_and_is_capped() -> void:
	if not _mask.has_method(&"interaction_strength"):
		assert_true(false, "TrackMask cannot derive interaction strength")
		return
	var small: float = _mask.call(&"interaction_strength", &"body_press", 0.48, 180.0, 0.25)
	var hard: float = _mask.call(&"interaction_strength", &"body_press", 0.48, 520.0, 0.25)
	var broad: float = _mask.call(&"interaction_strength", &"body_press", 0.48, 520.0, 0.75)
	var absurd: float = _mask.call(&"interaction_strength", &"impact", 2.0, 100000.0, 0.01)
	assert_true(hard > small, "more impulse did not deepen an equal contact")
	assert_true(broad < hard, "spreading the same impulse over more body area made a deeper hole")
	assert_true(absurd <= 0.86, "an uncapped impact writes a black crater: %f" % absurd)


func test_unified_furrow_is_narrower_shallower_and_locally_collapsed() -> void:
	if not _mask.has_method(&"_on_snow_interaction"):
		assert_true(false, "TrackMask does not consume snow.interaction")
		return
	var start := Vector3(-12.0, 0.0, -8.0)
	for index in range(18):
		var a := start + Vector3(float(index) * 0.06, 0.0, 0.0)
		var b := start + Vector3(float(index + 1) * 0.06, 0.0, 0.0)
		_mask.call(&"_on_snow_interaction", {
			"type": &"furrow", "from": a, "to": b,
			"half_width": 0.17, "strength": 0.72,
		})
	var low := INF
	var high := -INF
	for index in range(3, 15):
		var value := _mask.value_at(start + Vector3(float(index) * 0.06, 0.0, 0.0))
		low = minf(low, value)
		high = maxf(high, value)
	assert_true(high > 0.20 and high < 0.62, "the tuned channel peak is %f" % high)
	assert_true(high - low > 0.05, "the channel is a perfectly continuous pipe: %f..%f" % [low, high])
	assert_almost_eq(
		_mask.value_at(start + Vector3(0.54, 0.0, 0.16)), 0.0, 0.03,
		"the tuned V groove is still the old 34 cm-wide trench"
	)


func test_a_body_event_keeps_the_chunked_upload_budget() -> void:
	if not _mask.has_method(&"_on_snow_interaction"):
		assert_true(false, "TrackMask does not consume snow.interaction")
		return
	_mask.flush()
	_mask.call(&"_on_snow_interaction", {
		"type": &"body_press", "position": Vector3(-10.0, 0.0, -10.0),
		"forward": Vector2.RIGHT, "snow_depth_m": 0.45, "impulse_ns": 320.0,
		"contacts": [
			{"offset": Vector2.ZERO, "length": 0.60, "width": 0.34, "weight": 1.0},
			{"offset": Vector2(0.35, 0.12), "length": 0.42, "width": 0.16, "weight": 0.65},
		],
	})
	_mask.flush()
	assert_eq(_mask.last_upload_layer_count(), 1)
	assert_eq(_mask.last_upload_bytes(), TrackMask.UPLOAD_BYTES_PER_LAYER)


func test_drag_uses_the_same_sparse_surface_and_stays_inside_its_width() -> void:
	if not _mask.has_method(&"_on_snow_interaction"):
		assert_true(false, "TrackMask does not consume snow.interaction")
		return
	_mask.call(&"_on_snow_interaction", {
		"type": &"drag", "from": Vector3(-6.0, 0.0, 4.0),
		"to": Vector3(-4.8, 0.0, 4.0), "width": 0.24,
		"snow_depth_m": 0.35, "impulse_ns": 120.0,
	})
	assert_true(_mask.value_at(Vector3(-5.4, 0.0, 4.0)) > 0.1)
	assert_almost_eq(_mask.value_at(Vector3(-5.4, 0.0, 4.3)), 0.0, 0.02)


func test_unknown_or_malformed_interactions_are_ignored() -> void:
	if not _mask.has_method(&"_on_snow_interaction"):
		assert_true(false, "TrackMask does not consume snow.interaction")
		return
	_mask.call(&"_on_snow_interaction", {"type": &"not_shipped", "position": Vector3.ZERO})
	_mask.call(&"_on_snow_interaction", {"type": &"body_press", "position": Vector3.ZERO})
	_mask.call(&"_on_snow_interaction", null)
	assert_almost_eq(_mask.value_at(Vector3.ZERO), 0.0)
