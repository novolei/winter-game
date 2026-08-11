extends TestCase

## The snow field's arithmetic, which is the part of it that has a right
## answer. How the drifts *look* is judged from a screenshot; where a world
## position lands in the raster, and whether treading on it does what it claims,
## are not things you can see by looking.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")

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
