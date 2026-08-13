extends TestCase

## The snow field's arithmetic, which is the part of it that has a right
## answer. How the drifts *look* is judged from a screenshot; where a world
## position lands in the raster, and whether treading on it does what it claims,
## are not things you can see by looking.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const SnowShelterScript := preload("res://src/definitions/snow_shelter_definition.gd")

var _field: SnowField


func before_each() -> void:
	_field = SnowFieldScript.new()
	# build_at() rather than adding to the tree: _ready() would also register
	# the field in ServiceRegistry and subscribe it to EventBus, and a unit
	# test that leaves either behind poisons every test after it.
	_field.build_at(Vector3.ZERO)


func after_each() -> void:
	# Node is not reference counted (briefing section 2.2).
	_field.free()
	_field = null


func _single_channel(values: Array) -> Image:
	var size := int(sqrt(float(values.size())))
	var image := Image.create_empty(size, size, false, Image.FORMAT_RF)
	for y in range(size):
		for x in range(size):
			image.set_pixel(x, y, Color(values[y * size + x], 0.0, 0.0, 1.0))
	return image


func test_bilinear_reads_a_texel_centre_exactly() -> void:
	var image := _single_channel([0.0, 1.0, 0.25, 0.75])
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 0.0, 0.0), 0.0)
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 1.0, 0.0), 1.0)
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 0.0, 1.0), 0.25)
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 1.0, 1.0), 0.75)


func test_bilinear_interpolates_between_texels() -> void:
	var image := _single_channel([0.0, 1.0, 0.25, 0.75])
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 0.5, 0.0), 0.5, 0.001)
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 0.0, 0.5), 0.125, 0.001)
	# The centre is the mean of all four.
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 0.5, 0.5), 0.5, 0.001)


## The window is finite and the player is not obliged to stay inside it. An
## unclamped read would index off the end of the image, which is a runtime
## error that aborts whatever was walking the field at the time.
func test_bilinear_clamps_outside_the_image() -> void:
	var image := _single_channel([0.0, 1.0, 0.25, 0.75])
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, -12.0, -12.0), 0.0)
	assert_almost_eq(SnowFieldScript.sample_bilinear(image, 99.0, 99.0), 0.75)


func test_cell_coordinates_are_measured_from_the_window_origin() -> void:
	var origin := _field.origin()
	assert_almost_eq(_field.cell_of(origin).x, 0.0, 0.001)
	assert_almost_eq(_field.cell_of(origin).y, 0.0, 0.001)
	var one_texel := origin + Vector2(SnowField.CELL_M, SnowField.CELL_M * 3.0)
	assert_almost_eq(_field.cell_of(one_texel).x, 1.0, 0.001)
	assert_almost_eq(_field.cell_of(one_texel).y, 3.0, 0.001)


## The shader multiplies this same depth into the vertex height, so a depth
## outside the declared range would show up as terrain punching through the
## world rather than as a number being slightly wrong.
func test_depth_stays_inside_the_declared_range() -> void:
	var worst := 0.0
	var best := _field.max_depth_m
	for step in range(40):
		var offset := -50.0 + float(step) * 2.5
		var depth: float = _field.depth_at(Vector3(offset, 0.0, offset * 0.7))
		worst = maxf(worst, depth)
		best = minf(best, depth)
	assert_true(worst <= _field.max_depth_m, "deepest sample %f exceeds max_depth_m %f" % [worst, _field.max_depth_m])
	assert_true(best >= 0.0, "shallowest sample %f is below zero" % best)


## A wind-scoured crest may carry almost no structural snow, but the authored
## opening valley is not bare ground.  The compressible surface veneer gives a
## boot material to displace without charging that cosmetic cover to movement.
func test_open_crests_keep_imprintable_cover_without_adding_wade() -> void:
	assert_true(_field.has_method(&"visible_depth_at"),
		"SnowField has no separate visible/compressible snow depth")
	if not _field.has_method(&"visible_depth_at"):
		return
	var shallowest := Vector3.ZERO
	var structural := INF
	for z in range(-48, 49, 3):
		for x in range(-48, 49, 3):
			var spot := Vector3(float(x), 0.0, float(z))
			var depth: float = _field.depth_at(spot)
			if depth < structural:
				structural = depth
				shallowest = spot
	assert_true(structural < 0.01,
		"fixture found no scoured opening; shallowest structural depth was %.3f m" % structural)
	var before_wade := _field.wade_factor(shallowest)
	var visible: float = _field.call(&"visible_depth_at", shallowest)
	assert_true(visible >= 0.079,
		"scoured opening exposes only %.1f mm, so a boot cannot leave a cavity" % (visible * 1000.0))
	assert_almost_eq(_field.wade_factor(shallowest), before_wade, 0.000001,
		"the imprint veneer silently increased the movement penalty")


func test_full_packing_removes_the_imprint_veneer() -> void:
	assert_true(_field.has_method(&"visible_depth_at"))
	if not _field.has_method(&"visible_depth_at"):
		return
	var spot := Vector3(9.0, 0.0, 9.0)
	for _repeat in range(30):
		_field.pack_at(spot, 0.5, 1.0)
	assert_true(_field.packed_at(spot) >= 0.999)
	assert_almost_eq(_field.call(&"visible_depth_at", spot), 0.0, 0.0001,
		"packed/building-clear ground retained a false snow veneer")


func test_visible_cover_is_world_anchored_across_recentre() -> void:
	assert_true(_field.has_method(&"visible_depth_at"))
	if not _field.has_method(&"visible_depth_at"):
		return
	var spot := Vector3(6.0, 0.0, 6.0)
	var before: float = _field.call(&"visible_depth_at", spot)
	assert_true(_field.follow(Vector3(35.0, 0.0, 24.0)))
	assert_almost_eq(_field.call(&"visible_depth_at", spot), before, 0.01,
		"the compressible opening cover moved with the raster window")


## W4-1 was based on the claim that no 12 m square had a mean depth in the
## intermediate band.  This is a characterization gate, not a balance target:
## final distribution thresholds need product approval before they belong here.
func test_12m_windows_include_an_intermediate_mean_depth() -> void:
	const SAMPLE_M := 0.5
	const SPAN_M := 80.0
	const BLOCK_M := 12.0
	const STRIDE_M := 1.0
	const LOW_M := 0.02
	const HIGH_M := 0.32
	var cells := int(round(SPAN_M / SAMPLE_M))
	var block_cells := int(round(BLOCK_M / SAMPLE_M))
	var stride_cells := int(round(STRIDE_M / SAMPLE_M))
	var width := cells + 1
	var sums: Array[float] = []
	sums.resize(width * width)
	for y in range(cells):
		var row_sum := 0.0
		for x in range(cells):
			var depth: float = _field.depth_at(Vector3(
				-SPAN_M * 0.5 + (float(x) + 0.5) * SAMPLE_M,
				0.0,
				-SPAN_M * 0.5 + (float(y) + 0.5) * SAMPLE_M
			))
			row_sum += depth
			sums[(y + 1) * width + (x + 1)] = sums[y * width + (x + 1)] + row_sum

	var middle_windows := 0
	var total_windows := 0
	for y in range(0, cells - block_cells + 1, stride_cells):
		for x in range(0, cells - block_cells + 1, stride_cells):
			var x2 := x + block_cells
			var y2 := y + block_cells
			var total := sums[y2 * width + x2] - sums[y * width + x2] - sums[y2 * width + x] + sums[y * width + x]
			var mean := total / float(block_cells * block_cells)
			total_windows += 1
			if mean >= LOW_M and mean <= HIGH_M:
				middle_windows += 1
	assert_true(
		middle_windows > 0,
		"0/%d 12 m windows had a %.2f..%.2f m mean; W4-1's absence has returned" % [
			total_windows, LOW_M, HIGH_M,
		]
	)


## Phase B: a run owns one initial snow layout.  It must be a fact of the
## world, not a frame of the moving height window: the same seed has the same
## answer before and after a recenter, while another seed changes an open route.
func test_a_run_seed_replays_the_same_open_snow_after_a_recentre() -> void:
	const SEED := 1729
	var open_spot := Vector3(-20.0, 0.0, 20.0)
	_field.set_run_seed(SEED)
	var before: float = _field.depth_at(open_spot)
	assert_true(_field.follow(Vector3(37.0, 0.0, 28.0)), "setup failed: the field did not recentre")
	var after: float = _field.depth_at(open_spot)
	assert_almost_eq(
		after, before, 0.0001,
		"seed %d changed the initial snow at one world position after a recenter" % SEED
	)


## A recentre is part of walking, not a loading screen.  The opening snow may
## vary by seed, but its raster must never be rebuilt through a per-texel
## GDScript loop on the frame that moves the window.  This is intentionally a
## measured boundary rather than a cosmetic timing assertion: the live probe
## crossed the same edge every eight metres and stopped for more than a second.
func test_a_seeded_recentre_stays_bounded_and_keeps_the_same_world_snow() -> void:
	const SEED := 24681357
	const BUDGET_MS := 25.0
	var open_spot := Vector3(-20.0, 0.0, 20.0)
	_field.set_run_seed(SEED)
	var before: float = _field.depth_at(open_spot)
	assert_true(_field.follow(Vector3(15.0, 0.0, 0.0)), "setup failed: the field did not recentre")
	assert_true(
		_field.last_recentre_duration_ms() < BUDGET_MS,
		"seeded recentre took %.3f ms; moving the snow window must stay under %.1f ms" % [
			_field.last_recentre_duration_ms(), BUDGET_MS,
		]
	)
	assert_almost_eq(
		_field.depth_at(open_spot), before, 0.0001,
		"the bounded seeded recentre changed snow at one fixed world point"
	)


## The production injection path.  SnowField must receive the owner through the
## registry before it builds, otherwise farm props settle against one seed and
## the rendered field changes under them on the first process frame.
func test_the_registered_run_owner_injects_the_seed_before_the_field_builds() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the test runner must expose /root for injection wiring")
	if tree == null:
		return
	var registry := tree.root.get_node_or_null("ServiceRegistry")
	assert_not_null(registry, "the run-seed contract needs ServiceRegistry")
	if registry == null:
		return
	var previous: Object = registry.get_service(&"run_seed")
	var owner := _RunSeedOwner.new()
	owner.seed = 1729
	registry.register(&"run_seed", owner)
	var field: SnowField = SnowFieldScript.new()
	tree.root.add_child(field)
	var received := field.current_run_seed()
	tree.root.remove_child(field)
	field.free()
	owner.free()
	if previous != null:
		registry.register(&"run_seed", previous)
	else:
		registry.unregister(&"run_seed")
	assert_eq(received, 1729, "SnowField built before the registered run owner supplied its seed")


func test_the_same_run_seed_rebuilds_the_same_open_snow_field() -> void:
	const SEED := 1729
	var second: SnowField = SnowFieldScript.new()
	second.set_run_seed(SEED)
	second.build_at(Vector3(31.0, 0.0, -22.0))
	_field.set_run_seed(SEED)
	var largest_delta := 0.0
	# The two windows overlap only across this rectangle.  Sampling beyond it
	# would compare one world texel with the other's clamped border, which tests
	# Image sampling rather than seed determinism.
	for x in range(-20, 45, 11):
		for z in range(-40, 35, 11):
			var spot := Vector3(float(x), 0.0, float(z))
			largest_delta = maxf(largest_delta, absf(_field.depth_at(spot) - second.depth_at(spot)))
	second.free()
	assert_almost_eq(largest_delta, 0.0, 0.0001, "one run seed rebuilt two different fields")


func test_different_run_seeds_change_only_open_snow() -> void:
	var first: SnowField = SnowFieldScript.new()
	var second: SnowField = SnowFieldScript.new()
	first.set_run_seed(1729)
	second.set_run_seed(8191)
	first.build_at(Vector3.ZERO)
	second.build_at(Vector3.ZERO)
	var largest_open_delta := 0.0
	for x in range(-48, 49, 4):
		for z in range(-48, 49, 4):
			var spot := Vector3(float(x), 0.0, float(z))
			largest_open_delta = maxf(largest_open_delta, absf(first.depth_at(spot) - second.depth_at(spot)))
	first.free()
	second.free()
	assert_true(
		largest_open_delta >= 0.015,
		"two run seeds made no meaningful initial-snow difference; largest delta was %.4f m" % largest_open_delta
	)


## The road, yard and spur already encode the farmstead's authored navigable
## network.  The first-day shelter line begins at Player's zero transform and
## ends at the farmhouse doorstep's scene transform.  This test deliberately
## reads those production anchors instead of inventing a new safety route.
func test_run_seed_does_not_change_the_authored_first_day_safe_routes() -> void:
	var first: SnowField = SnowFieldScript.new()
	var second: SnowField = SnowFieldScript.new()
	first.set_run_seed(1729)
	second.set_run_seed(8191)
	first.build_at(Vector3.ZERO)
	second.build_at(Vector3.ZERO)
	var worst_delta := 0.0
	for route in _authored_safe_routes():
		for index in range(route.size() - 1):
			var from: Vector3 = route[index]
			var to: Vector3 = route[index + 1]
			var length := from.distance_to(to)
			var steps := maxi(int(ceilf(length / 0.5)), 1)
			for step in range(steps + 1):
				var spot := from.lerp(to, float(step) / float(steps))
				worst_delta = maxf(worst_delta, absf(first.depth_at(spot) - second.depth_at(spot)))
	first.free()
	second.free()
	assert_almost_eq(
		worst_delta, 0.0, 0.001,
		"a run seed changed an authored first-day-safe route by %.4f m" % worst_delta
	)


## The render path receives the profile's real variable-length corridors rather
## than a second, copied set of route coordinates.  That is what lets native
## mature-noise image generation stay fast while the visual and physical safe
## routes remain the same authored fact.
func test_mature_route_shader_data_carries_every_authored_safe_route() -> void:
	var data := _field.mature_route_shader_data()
	var points: PackedVector2Array = data["points"]
	var offsets: PackedInt32Array = data["offsets"]
	var counts: PackedInt32Array = data["counts"]
	var half_widths: PackedFloat32Array = data["half_widths"]
	var feathers: PackedFloat32Array = data["feathers"]
	assert_eq(offsets.size(), counts.size(), "each shader route needs one point range")
	assert_eq(counts.size(), half_widths.size(), "each shader route needs its authored width")
	assert_eq(counts.size(), feathers.size(), "each shader route needs its authored feather")
	assert_true(counts.size() > 0, "the production profile provided no protected route data")
	var reconstructed_points := 0
	for index in range(counts.size()):
		assert_true(counts[index] >= 2, "shader route %d has no segment" % index)
		assert_eq(offsets[index], reconstructed_points, "shader route points are not contiguous")
		reconstructed_points += counts[index]
	assert_eq(reconstructed_points, points.size(), "shader route data dropped or duplicated points")
	assert_true(
		counts.size() <= SnowFieldScript.MATURE_ROUTE_CAPACITY
			and points.size() <= SnowFieldScript.MATURE_ROUTE_POINT_CAPACITY,
		"the shipped profile exceeds the shader transport capacity"
	)


## Phase C's first acceptance boundary.  A weather response does not write a
## frame-dependent height map: its scalar input is consumed only on SnowField's
## fixed simulation tick, and the result is an added world depth.
func test_dynamic_snow_waits_for_a_fixed_tick_then_accumulates() -> void:
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.deposition_m_per_second = 0.001
	response.maximum_added_depth_m = 0.2
	var open_spot := Vector3(-30.0, 0.0, 30.0)
	_field.set_snow_response(response, 1.0)
	_field.advance_dynamic(0.49)
	assert_almost_eq(_field.dynamic_depth_at(open_spot), 0.0, 0.000001)
	_field.advance_dynamic(0.01)
	assert_true(
		_field.dynamic_depth_at(open_spot) > 0.0,
		"a full fixed tick of snowfall left the open field unchanged"
	)


## The base seed is replayable and so is the weather history laid on top of it.
## A later save/replay layer will serialise the sparse tiles; this phase proves
## the inputs themselves are already independent of field recentering and frame
## chunking.
func test_dynamic_snow_is_deterministic_for_same_seed_and_ticks() -> void:
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.deposition_m_per_second = 0.0008
	response.maximum_added_depth_m = 0.2
	var first: SnowField = SnowFieldScript.new()
	var second: SnowField = SnowFieldScript.new()
	first.set_run_seed(1729)
	second.set_run_seed(1729)
	first.build_at(Vector3.ZERO)
	second.build_at(Vector3.ZERO)
	first.set_snow_response(response, 0.75)
	second.set_snow_response(response, 0.75)
	first.advance_dynamic(18.0)
	for _step in range(36):
		second.advance_dynamic(0.5)
	var spot := Vector3(-30.0, 0.0, 30.0)
	assert_almost_eq(first.dynamic_depth_at(spot), second.dynamic_depth_at(spot), 0.000001)
	assert_almost_eq(first.depth_at(spot), second.depth_at(spot), 0.000001)
	first.free()
	second.free()


## The run seed's authored safety corridors also suppress dynamic deposition.
## Otherwise a route which opens safe could silently become a Day-1 wade after
## one ordinary snowfall.
func test_dynamic_snow_preserves_authored_safe_routes() -> void:
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.deposition_m_per_second = 0.001
	response.maximum_added_depth_m = 0.2
	_field.set_snow_response(response, 1.0)
	_field.advance_dynamic(2.0)
	assert_almost_eq(_field.dynamic_depth_at(Vector3.ZERO), 0.0, 0.000001)
	assert_true(
		_field.dynamic_depth_at(Vector3(-30.0, 0.0, 30.0)) > 0.0,
		"the open field did not receive the snowfall used to test the protected route"
	)


## The public gameplay seam is the same EventBus footprint that writes the
## visible TrackMask.  SnowField must compact the *whole* column after fresh
## snow has arrived; compacting only the initial mature layer would leave a
## new-storm path physically unchanged.
func test_a_real_footprint_event_compacts_deposited_dynamic_snow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the integration seam needs the live EventBus autoload")
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("EventBus")
	assert_not_null(bus, "the live tree has no EventBus")
	if bus == null:
		return
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.deposition_m_per_second = 0.001
	response.maximum_added_depth_m = 0.2
	var field: SnowField = SnowFieldScript.new()
	tree.root.add_child(field)
	var open_spot := Vector3(-30.0, 0.0, 30.0)
	bus.emit_event(field.SNOW_INPUTS_CHANGED_EVENT, {"response": response, "snowfall": 1.0})
	field.advance_dynamic(field.dynamic_tick_seconds)
	var dynamic_before: float = field.dynamic_depth_at(open_spot)
	var surface_before: float = field.depth_at(open_spot)
	assert_true(dynamic_before > 0.0, "setup failed: the live weather input deposited no snow")
	bus.emit_event(field.FOOTPRINT_EVENT, {
		"subject": &"player", "position": open_spot, "pack_radius": 0.5, "pack_amount": 0.8,
	})
	assert_almost_eq(
		field.dynamic_depth_at(open_spot), dynamic_before, 0.000001,
		"a footprint must compact the column, not destroy the deposited mass"
	)
	assert_true(
		field.depth_at(open_spot) < surface_before,
		"the real track.footprint event did not compact deposited dynamic snow"
	)
	tree.root.remove_child(field)
	field.free()


## Wind transport is deliberately a transfer, not a global subtraction.  A
## single exposed tile carries a finite amount only to the tile downwind of it;
## reversing the wind reverses that destination without creating material.
func test_wind_transport_reverses_with_the_wind_direction_and_conserves_mass() -> void:
	var response := _wind_response()
	var source_key := Vector2i(8, 8)
	var source: Vector2 = _field._dynamic_snow.tile_centre(source_key)
	_field._dynamic_snow.add_at(source, 0.10, response.maximum_added_depth_m)
	_field.wind_transport_tile_budget = 1
	_field.set_dynamic_focus(Vector3(source.x, 0.0, source.y))
	_field.set_snow_response(response, 0.0)
	_field.set_wind_input(Vector2.RIGHT, 1.0)
	var east_before: float = _field.dynamic_total_depth_m()
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	var east_destination := source + Vector2.RIGHT * response.wind_sample_distance_m
	assert_true(
		_field.dynamic_depth_at(Vector3(east_destination.x, 0.0, east_destination.y)) > 0.0,
		"an east wind did not deposit finite snow in the eastward tile"
	)
	assert_almost_eq(_field.dynamic_total_depth_m(), east_before, 0.000001,
		"an in-window wind transfer created or destroyed snow")

	_field.clear_dynamic_snow()
	_field._dynamic_snow.add_at(source, 0.10, response.maximum_added_depth_m)
	_field.set_wind_input(Vector2.LEFT, 1.0)
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	var west_destination := source + Vector2.LEFT * response.wind_sample_distance_m
	assert_true(
		_field.dynamic_depth_at(Vector3(west_destination.x, 0.0, west_destination.y)) > 0.0,
		"a west wind did not reverse the downwind destination"
	)


## A lee behind an authored shelter is a physical preference, not an arbitrary
## snow bonus: the same exposed source gives more of its finite material to the
## sheltered downwind pocket than to equally distant open snow.
func test_wind_transport_prefers_a_sheltered_lee_over_open_downwind_snow() -> void:
	var response := _wind_response()
	var shelter: SnowShelterDefinition = SnowShelterScript.new()
	shelter.centre = Vector2(15.0, 15.0)
	shelter.radius_m = 1.0
	shelter.lee_length_m = 8.0
	shelter.lee_half_width_m = 3.0
	shelter.shelter_strength = 1.0
	_field._snow_profile.shelters = [shelter]
	var source_key := _field._dynamic_snow.tile_key(Vector2(11.25, 15.0))
	var source := _field._dynamic_snow.tile_centre(source_key)
	_field._dynamic_snow.add_at(source, 0.10, response.maximum_added_depth_m)
	_field.wind_transport_tile_budget = 1
	_field.set_dynamic_focus(Vector3(source.x, 0.0, source.y))
	_field.set_snow_response(response, 0.0)
	_field.set_wind_input(Vector2.RIGHT, 1.0)
	var lee := source + Vector2.RIGHT * response.wind_sample_distance_m
	assert_true(
		_field.shelter_weight_at(lee, Vector2.RIGHT) > 0.5,
		"test setup did not place the receiver in the shelter's lee"
	)
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	var sheltered_depth := _field.dynamic_depth_at(Vector3(lee.x, 0.0, lee.y))
	var open_field: SnowField = SnowFieldScript.new()
	open_field.build_at(Vector3.ZERO)
	open_field._snow_profile.shelters = []
	open_field._dynamic_snow.add_at(source, 0.10, response.maximum_added_depth_m)
	open_field.wind_transport_tile_budget = 1
	open_field.set_dynamic_focus(Vector3(source.x, 0.0, source.y))
	open_field.set_snow_response(response, 0.0)
	open_field.set_wind_input(Vector2.RIGHT, 1.0)
	open_field.advance_dynamic(open_field.dynamic_tick_seconds)
	var open_depth := open_field.dynamic_depth_at(Vector3(lee.x, 0.0, lee.y))
	open_field.free()
	assert_true(
		sheltered_depth > open_depth,
		"a sheltered lee received %.6f m, no more than the equally distant open snow %.6f m" % [
			sheltered_depth, open_depth,
		]
	)


## The response cap bounds new deposits, not material already deposited by a
## stronger earlier front.  A lower-cap wind-shift event must transfer it, not
## erase the difference while staging a source delta.
func test_wind_transport_keeps_mass_when_the_next_response_has_a_lower_cap() -> void:
	var deep_response := _wind_response()
	deep_response.maximum_added_depth_m = 0.20
	var shift_response := _wind_response()
	shift_response.maximum_added_depth_m = 0.12
	var key := Vector2i(8, 8)
	var source := _field._dynamic_snow.tile_centre(key)
	_field._dynamic_snow.add_at(source, 0.18, deep_response.maximum_added_depth_m)
	_field.wind_transport_tile_budget = 1
	_field.set_dynamic_focus(Vector3(source.x, 0.0, source.y))
	_field.set_snow_response(shift_response, 0.0)
	_field.set_wind_input(Vector2.RIGHT, 1.0)
	var before := _field.dynamic_total_depth_m()
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	assert_almost_eq(_field.dynamic_total_depth_m(), before, 0.000001,
		"a lower-cap response destroyed snow deposited by the earlier storm")


## The authored Day-1 corridors are hard constraints for wind as well as for
## snowfall.  A route cannot become unsafe just because a gale turned.
func test_wind_transport_does_not_scour_or_deposit_on_a_protected_route() -> void:
	var response := _wind_response()
	var protected_key := _field._dynamic_snow.tile_key(Vector2.ZERO)
	var protected_centre := _field._dynamic_snow.tile_centre(protected_key)
	_field._dynamic_snow.add_at(protected_centre, 0.10, response.maximum_added_depth_m)
	_field.wind_transport_tile_budget = 1
	_field.set_dynamic_focus(Vector3(protected_centre.x, 0.0, protected_centre.y))
	_field.set_snow_response(response, 0.0)
	_field.set_wind_input(Vector2.RIGHT, 1.0)
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	assert_almost_eq(
		_field.dynamic_depth_at(Vector3(protected_centre.x, 0.0, protected_centre.y)), 0.10, 0.000001,
		"wind modified a protected Day-1 route"
	)


## Sparse means bounded work.  A long-lived world may hold many dynamic tiles,
## but one fixed wind tick must inspect only its local budget, never every tile
## ever touched elsewhere in the valley.
func test_wind_transport_work_is_bounded_by_the_local_tile_budget() -> void:
	var response := _wind_response()
	_field.wind_transport_tile_budget = 9
	for x in range(-15, 16):
		for y in range(-15, 16):
			_field._dynamic_snow.add_at(Vector2(float(x) * 4.0, float(y) * 4.0), 0.02,
				response.maximum_added_depth_m)
	_field.set_dynamic_focus(Vector3.ZERO)
	_field.set_snow_response(response, 0.0)
	_field.set_wind_input(Vector2.RIGHT, 1.0)
	_field.advance_dynamic(_field.dynamic_tick_seconds)
	assert_true(
		_field.last_wind_transport_tile_work() <= _field.wind_transport_tile_budget,
		"wind inspected %d tiles with a budget of %d" % [
			_field.last_wind_transport_tile_work(), _field.wind_transport_tile_budget,
		]
	)
	assert_true(
		_field.last_wind_transport_tile_work() < _field.dynamic_tile_count(),
		"wind transport walked every sparse tile instead of the local activity window"
	)


## A run owner saves the opening seed, current weather inputs and only the
## sparse mutable layer.  The receiver is prepared from that seed before its
## normal native field build, then restores the sparse state without a raster
## rebuild.  This keeps a resumed run exactly on its prior weather timeline.
func test_persistence_snapshot_round_trips_seed_sparse_depth_and_inputs() -> void:
	var response := _wind_response()
	response.deposition_m_per_second = 0.0007
	_field.set_run_seed(1729)
	_field.set_snow_response(response, 0.65)
	_field.set_wind_input(Vector2(0.6, -0.8), 0.72)
	_field.set_dynamic_focus(Vector3(18.0, 0.0, -27.0))
	_field.advance_dynamic(0.2)
	_field._dynamic_snow.add_at(Vector2(-30.0, 30.0), 0.071, response.maximum_added_depth_m)
	_field._dynamic_snow.add_at(Vector2(26.0, -21.0), 0.113, response.maximum_added_depth_m)
	var snapshot: Dictionary = _field.create_persistence_snapshot()

	assert_eq(snapshot["run_seed"], 1729, "the run seed was not saved")
	assert_eq((snapshot["dynamic"] as Dictionary)["tiles"].size(), 2,
		"the save stored something other than the two sparse dynamic tiles")
	assert_eq(_field.last_persistence_tile_work(), 2,
		"snapshot work was not proportional to the two stored sparse tiles")

	var restored: SnowField = SnowFieldScript.new()
	assert_true(restored.inject_run_seed_from_persistence_snapshot(snapshot),
		"a valid snapshot did not provide its run seed before field construction")
	restored.build_at(Vector3.ZERO)
	assert_true(restored.restore_persistence_snapshot(snapshot),
		"a prepared field rejected its own valid snapshot")
	assert_eq(restored.current_run_seed(), _field.current_run_seed())
	assert_eq(restored.dynamic_tile_count(), _field.dynamic_tile_count())
	assert_almost_eq(
		restored.dynamic_depth_at(Vector3(-30.0, 0.0, 30.0)),
		_field.dynamic_depth_at(Vector3(-30.0, 0.0, 30.0)), 0.000001
	)
	assert_almost_eq(
		restored.dynamic_depth_at(Vector3(26.0, 0.0, -21.0)),
		_field.dynamic_depth_at(Vector3(26.0, 0.0, -21.0)), 0.000001
	)
	assert_almost_eq(restored._dynamic_tick_elapsed, _field._dynamic_tick_elapsed, 0.000001)
	assert_almost_eq(restored._snow_intensity, _field._snow_intensity, 0.000001)
	assert_almost_eq(restored._wind_strength, _field._wind_strength, 0.000001)
	assert_almost_eq(restored._wind_direction.distance_to(_field._wind_direction), 0.0, 0.000001)
	restored.free()


## Save after a time split, prepare a fresh field with the saved seed, and
## continue the exact same fixed-tick inputs.  A resumed field must reach the
## same surface fact as a field which never stopped.
func test_persistence_resume_matches_an_uninterrupted_dynamic_run() -> void:
	var response := _wind_response()
	response.deposition_m_per_second = 0.0006
	var uninterrupted: SnowField = SnowFieldScript.new()
	uninterrupted.set_run_seed(2468)
	uninterrupted.build_at(Vector3.ZERO)
	uninterrupted.set_snow_response(response, 0.8)
	uninterrupted.set_wind_input(Vector2.RIGHT, 0.6)
	uninterrupted.set_dynamic_focus(Vector3(-30.0, 0.0, 30.0))
	uninterrupted.advance_dynamic(1.7)

	var interrupted: SnowField = SnowFieldScript.new()
	interrupted.set_run_seed(2468)
	interrupted.build_at(Vector3.ZERO)
	interrupted.set_snow_response(response, 0.8)
	interrupted.set_wind_input(Vector2.RIGHT, 0.6)
	interrupted.set_dynamic_focus(Vector3(-30.0, 0.0, 30.0))
	interrupted.advance_dynamic(1.7)
	var snapshot: Dictionary = interrupted.create_persistence_snapshot()
	var resumed: SnowField = SnowFieldScript.new()
	assert_true(resumed.inject_run_seed_from_persistence_snapshot(snapshot))
	resumed.build_at(Vector3.ZERO)
	assert_true(resumed.restore_persistence_snapshot(snapshot))

	# The restore reconstructed its own response object from values, so this
	# continuation must not depend on retaining the first field's Resource.
	uninterrupted.advance_dynamic(2.3)
	resumed.advance_dynamic(2.3)
	for spot in [Vector3(-30.0, 0.0, 30.0), Vector3(18.0, 0.0, -18.0), Vector3(31.0, 0.0, 22.0)]:
		assert_almost_eq(resumed.dynamic_depth_at(spot), uninterrupted.dynamic_depth_at(spot), 0.000001,
			"resumed depth diverged at %s" % spot)
		assert_almost_eq(resumed.depth_at(spot), uninterrupted.depth_at(spot), 0.000001,
			"resumed surface diverged at %s" % spot)
	interrupted.free()
	uninterrupted.free()
	resumed.free()


## The Day-1 route and building-carve rules cannot be overwritten by a save.
## A snapshot carries the registered carve facts for the world owner to replay,
## while dynamic snowfall itself remains excluded from authored safe routes.
func test_persistence_snapshot_preserves_route_and_registered_carve_constraints() -> void:
	var response := _wind_response()
	response.deposition_m_per_second = 0.001
	_field.set_run_seed(1729)
	_field.set_snow_response(response, 1.0)
	_field.carve_building(_persistence_carve())
	_field.advance_dynamic(1.0)
	var snapshot: Dictionary = _field.create_persistence_snapshot()
	assert_eq((snapshot["carves"] as Array).size(), 1, "registered building carve was not saved")
	assert_almost_eq(_field.dynamic_depth_at(Vector3.ZERO), 0.0, 0.000001,
		"setup let dynamic snow enter the authored safe route")
	var restored: SnowField = SnowFieldScript.new()
	assert_true(restored.inject_run_seed_from_persistence_snapshot(snapshot))
	restored.build_at(Vector3.ZERO)
	restored.carve_building(_persistence_carve())
	assert_true(restored.restore_persistence_snapshot(snapshot),
		"a field with the saved building registrations rejected its snapshot")
	assert_eq(restored.carved_count(), 1)
	assert_almost_eq(restored.dynamic_depth_at(Vector3.ZERO), 0.0, 0.000001)
	restored.free()


## Invalid data must leave a prepared field unchanged.  A failed save load is
## not an excuse to drop live snow, rebuild the terrain, or invent a new seed.
func test_persistence_snapshot_rejects_corrupt_and_version_mismatched_data_safely() -> void:
	var response := _wind_response()
	_field.set_run_seed(1729)
	_field.set_snow_response(response, 1.0)
	_field._dynamic_snow.add_at(Vector2(-30.0, 30.0), 0.08, response.maximum_added_depth_m)
	var valid: Dictionary = _field.create_persistence_snapshot()
	var target: SnowField = SnowFieldScript.new()
	assert_true(target.inject_run_seed_from_persistence_snapshot(valid))
	target.build_at(Vector3.ZERO)
	target._dynamic_snow.add_at(Vector2(26.0, -21.0), 0.06, response.maximum_added_depth_m)
	var existing_depth := target.dynamic_depth_at(Vector3(26.0, 0.0, -21.0))
	var existing_origin := target._origin
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt["dynamic"] = {"version": 1, "tiles": [{"x": 1, "z": 2, "depth_m": -1.0}]}
	assert_false(target.restore_persistence_snapshot(corrupt), "negative depth was accepted")
	var incompatible: Dictionary = valid.duplicate(true)
	incompatible["schema_version"] = 999
	assert_false(target.restore_persistence_snapshot(incompatible), "unknown schema was accepted")
	assert_almost_eq(target.dynamic_depth_at(Vector3(26.0, 0.0, -21.0)), existing_depth, 0.000001)
	assert_eq(target._origin, existing_origin, "a rejected restore recentred or rebuilt the terrain")
	target.free()


## Persistence is a sparse-copy operation.  It neither follows/recentres the
## terrain window nor touches its shader texture path, and it copies no more
## records than the tile store is allowed to retain.
func test_persistence_snapshot_work_is_bounded_by_sparse_tile_count_without_recentre() -> void:
	_field.maximum_dynamic_tiles = 11
	_field._dynamic_snow.maximum_tiles = _field.maximum_dynamic_tiles
	for x in range(-4, 5):
		for z in range(-4, 5):
			_field._dynamic_snow.add_at(Vector2(float(x) * 4.0, float(z) * 4.0), 0.02, 0.2)
	_field._dynamic_snow.trim_to_limit()
	_field.flush()
	var origin_before := _field._origin
	var dirty_before := _field._packed_dirty
	var recenter_before := _field.last_recentre_duration_ms()
	var snapshot: Dictionary = _field.create_persistence_snapshot()
	assert_true(_field.last_persistence_tile_work() <= _field.maximum_dynamic_tiles,
		"save copied %d records for a %d-tile store" % [
			_field.last_persistence_tile_work(), _field.maximum_dynamic_tiles,
		])
	assert_eq((snapshot["dynamic"] as Dictionary)["tiles"].size(), _field.dynamic_tile_count())
	assert_eq(_field._origin, origin_before, "saving moved the terrain window")
	assert_eq(_field._packed_dirty, dirty_before, "saving dirtied the packed texture")
	assert_almost_eq(_field.last_recentre_duration_ms(), recenter_before, 0.000001,
		"saving altered recenter timing state")


func _persistence_carve() -> Dictionary:
	return {
		"id": 812,
		"areas": [{
			"centre": Vector2(32.0, 32.0), "axis_x": Vector2.RIGHT, "axis_z": Vector2.DOWN,
			"half": Vector2(1.0, 1.0),
		}],
		"floor_y": 0.0,
		"doorways": [],
	}


func _wind_response() -> SnowResponseDefinition:
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.maximum_added_depth_m = 0.20
	response.wind_transport_m_per_second = 0.03
	response.wind_minimum_strength = 0.05
	response.wind_sample_distance_m = 3.75
	response.wind_shelter_deposition_gain = 1.5
	return response


func _authored_safe_routes() -> Array:
	var routes: Array = []
	routes.append([
		Vector3.ZERO,
		# Farmhouse (13, -12) + Doorstep (1.8, 1.2), from scenes/main.tscn.
		Vector3(14.8, 0.0, -10.8),
	])
	routes.append(_road_route())
	routes.append([
		Vector3(2.7, 0.0, -25.6),
		Vector3(4.6, 0.0, -22.2),
		# Truck transform in scenes/main.tscn; _spur() deliberately continues
		# beneath it, so the authored line is protected through the truck.
		Vector3(4.85, 0.0, -18.16),
	])
	routes.append(_yard_route())
	routes.append(_east_trail())
	routes.append(_well_trail())
	return routes


## These values are the world anchors in scenes/main.tscn today.  They live in
## this unit rather than importing Farmstead because Farmstead preloads models,
## and unit-level snow arithmetic must remain runnable when a visual asset cache
## is intentionally absent.  `tools/generate_snow_field_profile.gd` is the
## production source and imports Farmstead's authored constants directly.
func _road_route() -> Array:
	return [
		Vector3(45.0, 0.0, -59.0), Vector3(30.0, 0.0, -46.0), Vector3(20.0, 0.0, -37.0),
		Vector3(11.0, 0.0, -29.5), Vector3(2.7, 0.0, -25.6), Vector3(-9.0, 0.0, -28.5),
		Vector3(-24.0, 0.0, -34.0), Vector3(-41.0, 0.0, -40.0),
	]


func _yard_route() -> Array:
	return [
		Vector3(4.2, 0.0, -20.6), Vector3(6.4, 0.0, -16.4),
		Vector3(10.6, 0.0, -12.4), Vector3(14.4, 0.0, -9.6),
	]


func _east_trail() -> Array:
	return [
		Vector3(16.5, 0.0, -8.5), Vector3(24.0, 0.0, 3.0),
		Vector3(30.0, 0.0, 13.0), Vector3(37.2, 0.0, 24.9),
	]


func _well_trail() -> Array:
	return [
		Vector3(13.5, 0.0, -8.0), Vector3(8.6, 0.0, -0.4), Vector3(4.4, 0.0, 3.2),
		Vector3(-1.0, 0.0, 10.5), Vector3(-4.6, 0.0, 17.5),
	]


class _RunSeedOwner extends Node:
	var seed := 0

	func current_run_seed() -> int:
		return seed


## Finds somewhere with snow actually in it. Since the wind scours the crests,
## a hardcoded coordinate can legitimately land on bare ground, and a test that
## fails for that reason is testing the noise seed rather than the code.
func _snowy_spot() -> Vector3:
	var best := Vector3.ZERO
	var deepest := -1.0
	for step in range(60):
		var spot := Vector3(-40.0 + float(step) * 1.4, 0.0, 25.0 - float(step) * 0.9)
		var depth: float = _field.depth_at(spot)
		if depth > deepest:
			deepest = depth
			best = spot
	return best


## The whole point of the packed layer: a path you have beaten down is a path
## you can move faster along next time.
func test_treading_the_snow_makes_it_shallower() -> void:
	var spot := _snowy_spot()
	var before: float = _field.depth_at(spot)
	assert_true(before > 0.0, "no sampled spot had any snow in it; deepest was %f" % before)
	_field.pack_at(spot, 0.4, 0.5)
	var after: float = _field.depth_at(spot)
	assert_true(after < before, "packing left the depth at %f, was %f" % [after, before])


## The field responds to the track, not to the player. `subject` is mandatory
## so every downstream consumer can tell who made it, but no species list is
## allowed here: adding a new walker is a payload/data change, not a ground-code
## change.
func test_a_named_non_player_track_packs_the_snow_and_an_unnamed_one_does_not() -> void:
	var wolf_spot := _snowy_spot()
	var wolf_before: float = _field.packed_at(wolf_spot)
	_field._on_footprint({
		"subject": &"wolf", "position": wolf_spot, "pack_radius": 0.4, "pack_amount": 0.5,
	})
	assert_true(
		_field.packed_at(wolf_spot) > wolf_before,
		"a named non-player track did not pack the field"
	)

	var unnamed_spot := wolf_spot + Vector3(4.0, 0.0, 0.0)
	var unnamed_before: float = _field.packed_at(unnamed_spot)
	_field._on_footprint({"position": unnamed_spot, "pack_radius": 0.4, "pack_amount": 0.5})
	assert_almost_eq(
		_field.packed_at(unnamed_spot), unnamed_before, 0.001,
		"an unnamed footprint must be rejected before it changes the field"
	)


## The claim the whole terrain model rests on: the wind strips the crests and
## fills the hollows, so depth is a function of ground height rather than an
## independent noise. If this inverts, you get deep snow piled on the ridges and
## the relief you can see stops matching the speed you can feel.
func test_hollows_hold_the_snow_and_crests_are_scoured() -> void:
	var lowest := Vector3.ZERO
	var highest := Vector3.ZERO
	var min_height := INF
	var max_height := -INF
	for step in range(80):
		var spot := Vector3(-45.0 + float(step) * 1.1, 0.0, -30.0 + float(step) * 0.75)
		var height: float = _field.terrain_height_at(spot)
		if height < min_height:
			min_height = height
			lowest = spot
		if height > max_height:
			max_height = height
			highest = spot
	assert_true(
		max_height - min_height > 0.5,
		"the sampled line is nearly flat (%f m of relief); it cannot test the relationship" % (max_height - min_height)
	)
	assert_true(
		_field.depth_at(lowest) > _field.depth_at(highest),
		"the hollow at %.1f m holds %.2f m of snow and the crest at %.1f m holds %.2f m" % [
			min_height, _field.depth_at(lowest), max_height, _field.depth_at(highest),
		]
	)


func test_packing_saturates_rather_than_running_away() -> void:
	var spot := Vector3(-8.0, 0.0, 11.0)
	for _repeat in range(30):
		_field.pack_at(spot, 0.4, 0.5)
	assert_true(_field.packed_at(spot) <= 1.0, "packed layer reached %f, must not exceed 1" % _field.packed_at(spot))
	assert_true(_field.depth_at(spot) >= 0.0, "depth went negative: %f" % _field.depth_at(spot))


## Recentring is the one operation that can quietly destroy state: the window
## moves, every texel index changes, and a footprint that is not carried across
## simply disappears. This is the test that says the field is world-anchored
## rather than camera-anchored.
func test_a_trodden_patch_survives_the_window_moving() -> void:
	var spot := Vector3(6.0, 0.0, 6.0)
	_field.pack_at(spot, 0.6, 0.9)
	var before: float = _field.packed_at(spot)
	assert_true(before > 0.1, "setup failed: packed value at the spot was only %f" % before)

	var cell_before := _field.cell_of(Vector2(spot.x, spot.z))
	assert_true(_field.follow(Vector3(35.0, 0.0, 24.0)), "the window should have moved")
	var cell_after := _field.cell_of(Vector2(spot.x, spot.z))
	assert_true(
		cell_before.distance_to(cell_after) > 1.0,
		"the window did not actually move: texel %s then %s" % [cell_before, cell_after]
	)
	assert_almost_eq(_field.packed_at(spot), before, 0.01)


func test_staying_near_the_middle_does_not_move_the_window() -> void:
	var origin := _field.origin()
	assert_false(_field.follow(Vector3(1.0, 0.0, -1.0)), "a metre of drift must not rebuild the window")
	assert_almost_eq(_field.origin().x, origin.x)
	assert_almost_eq(_field.origin().y, origin.y)


## The player controller turns this into a speed. A value outside 0..1 would
## extrapolate past both the run and the wade speed.
func test_wade_factor_is_bounded() -> void:
	for step in range(20):
		var factor: float = _field.wade_factor(Vector3(float(step) * 3.0, 0.0, float(step) * -2.0))
		assert_true(factor >= 0.0 and factor <= 1.0, "wade factor %f is outside 0..1" % factor)


## ---------------------------------------------------------------------------
## The drift profile
## ---------------------------------------------------------------------------


## `drift_relief` is the one piece of the relief that is pure arithmetic, so it
## is the one piece that can be pinned exactly. The shape is the whole tuning:
## gentle near the noise's mean, full amplitude only out at its tails.
func test_the_drift_profile_is_gentle_at_the_mean_and_full_at_the_extremes() -> void:
	var flatten := 0.34
	var sharpness := 3.0
	# At the mean the ground is flat whatever the gain is.
	assert_almost_eq(SnowField.drift_relief(0.0, flatten, sharpness), 0.0)
	# At the extremes the gain reaches exactly 1, so amplitude means what its
	# name says: peak-to-trough over the whole range.
	assert_almost_eq(SnowField.drift_relief(0.5, flatten, sharpness), 0.5)
	assert_almost_eq(SnowField.drift_relief(-0.5, flatten, sharpness), -0.5)
	# And halfway out it is far below the straight line, which is the point --
	# a straight line here is what made the 70 m frame read as rolling dunes.
	var midway := SnowField.drift_relief(0.25, flatten, sharpness)
	assert_true(
		midway < 0.25 * 0.5,
		"halfway out the profile gives %f of the amplitude; anything near the linear 0.25 is not a drift profile" % midway
	)


## Odd, and monotonic. Odd because a hollow is the mirror of a crest and a field
## that rose faster than it fell would drift upward everywhere; monotonic
## because a non-monotonic profile turns a single noise peak into a ring, and
## the symptom would be a crater where a drift should be.
func test_the_drift_profile_is_odd_and_monotonic() -> void:
	var flatten := 0.34
	var sharpness := 3.0
	var previous := -INF
	for step in range(101):
		var signed := -0.5 + float(step) / 100.0
		var here := SnowField.drift_relief(signed, flatten, sharpness)
		assert_almost_eq(here, -SnowField.drift_relief(-signed, flatten, sharpness), 0.0001)
		assert_true(here > previous - 0.0001, "the profile falls back at %f" % signed)
		previous = here


## THE CLAIM THE WHOLE CHANGE RESTS ON, and the one a reviewer should be able to
## check without reading a screenshot: flattening the *drawn* relief does not
## touch the snow depth. Deep snow is a function of the normalised height, which
## the profile never sees, so the wade gradient and the footprint depths still
## run their full range no matter how flat the field is made to look.
##
## If this ever fails, the relief tuning has quietly become a gameplay change.
func test_the_drift_profile_does_not_touch_the_snow_depth() -> void:
	var spots: Array[Vector3] = []
	for step in range(40):
		spots.append(Vector3(-40.0 + float(step) * 2.1, 0.0, -30.0 + float(step) * 1.4))
	var before: Array[float] = []
	for spot in spots:
		before.append(_field.depth_at(spot))
	var flatten := _field.drift_flatten
	var sharpness := _field.drift_sharpness
	var amplitude := _field.terrain_amplitude_m
	_field.drift_flatten = 1.0
	_field.drift_sharpness = 1.0
	_field.terrain_amplitude_m = amplitude * 3.0
	var moved := 0.0
	for index in range(spots.size()):
		moved = maxf(moved, absf(_field.depth_at(spots[index]) - before[index]))
	_field.drift_flatten = flatten
	_field.drift_sharpness = sharpness
	_field.terrain_amplitude_m = amplitude
	assert_almost_eq(moved, 0.0, 0.0001)
	# ...and the sample line has to have had real depth variation in it, or the
	# assertion above passes over a row of zeroes.
	var lowest := INF
	var highest := -INF
	for value in before:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	assert_true(
		highest - lowest > _field.max_depth_m * 0.5,
		"the sampled line only swings %.3f m of depth; it cannot show that the profile left the depth alone" % (highest - lowest)
	)
