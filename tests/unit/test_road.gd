extends TestCase

## The road, as a composition.
##
## Art Bible rule 11 is the whole reason this has a test file of its own: the
## snow is nearly textureless, so every scrap of detail in the picture comes
## from the lines in it, and a road is the longest and most legible line the
## scene can have. What makes it read as a road rather than as two pencil lines
## is a graded profile -- faint drifted verge, packed carriageway, hard worn
## strips, hard ruts -- and that grading is not decoration. It is what makes the
## snow BURY the road correctly: the shader raises the whole baked layer to a
## power, so the weak edges go first and the deep ruts stay, and the road
## narrows to what traffic wore rather than dissolving evenly.
##
## Get the profile the wrong way round and the burial does the opposite: the
## ruts vanish and a broad faint band is left behind, which is not a road under
## snow, it is a smudge. That failure is invisible on day 1 and obvious on day 7,
## which is exactly the kind of thing a test should hold.

const FarmsteadScript := preload("res://src/entities/farmstead.gd")
const TrackMaskScript := preload("res://src/systems/track_mask.gd")

var _farmstead: Farmstead


func before_each() -> void:
	_farmstead = FarmsteadScript.new()


## Node is not reference counted (briefing section 2.2).
func after_each() -> void:
	if _farmstead != null:
		_farmstead.free()
		_farmstead = null


# ---------------------------------------------------------------------------
# The profile
# ---------------------------------------------------------------------------


## Outside in: wider and fainter, then narrower and harder. Every neighbouring
## pair, so a single element moved out of order is named rather than merely
## making the whole thing red.
func test_the_profile_is_graded_from_a_faint_verge_to_a_hard_rut() -> void:
	var profile := [
		["verge", _farmstead.road_verge_radius, _farmstead.road_verge_strength],
		["carriageway", _farmstead.road_bed_radius, _farmstead.road_bed_strength],
		["worn strip", _farmstead.worn_radius, _farmstead.worn_strength],
		["rut", _farmstead.rut_radius, _farmstead.rut_strength],
	]
	var offenders := PackedStringArray()
	for index in range(profile.size() - 1):
		var outer: Array = profile[index]
		var inner: Array = profile[index + 1]
		if float(outer[1]) <= float(inner[1]):
			offenders.append(
				"%s is %.2f m wide and %s inside it is %.2f -- the profile has to narrow"
					% [outer[0], outer[1], inner[0], inner[1]]
			)
		if float(outer[2]) >= float(inner[2]):
			offenders.append(
				"%s cuts at %.2f and %s inside it at %.2f -- the road has to deepen toward "
					% [outer[0], outer[2], inner[0], inner[2]]
					+ "where the wheels ran, or the snow buries the ruts and leaves the verge"
			)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The road's carriageway has to be wide enough to hold both worn strips and the
## crown of snow between them. A bed narrower than the gauge draws two isolated
## lines with nothing joining them, which is the shape this replaced.
func test_the_carriageway_is_wider_than_the_wheels_are_apart() -> void:
	assert_true(
		_farmstead.road_bed_radius > _farmstead.rut_gauge + _farmstead.worn_radius,
		"the bed reaches %.2f m and the outer edge of a worn strip is at %.2f, so the road "
			% [_farmstead.road_bed_radius, _farmstead.rut_gauge + _farmstead.worn_radius]
			+ "has nothing between and around its wheel tracks"
	)


## ...and the two strips must not merge into one band down the middle. A road
## with no crown between the wheel tracks is a cleared strip, not a used one.
func test_the_two_worn_strips_do_not_meet_in_the_middle() -> void:
	assert_true(
		_farmstead.rut_gauge > _farmstead.worn_radius,
		"the strips are %.2f m from the centre line and %.2f m wide either side, so they "
			% [_farmstead.rut_gauge, _farmstead.worn_radius]
			+ "overlap and the crown of snow between the wheels is gone"
	)


# ---------------------------------------------------------------------------
# 道路会被积雪覆盖一部分 -- the wear along the length
# ---------------------------------------------------------------------------


## The road is not evenly clear. Drifts lie across it and between them it is
## worn to the packed snow, and that is where "partly covered" comes from: the
## mask composites with max() so nothing here can erase, and the only way to
## leave a stretch snowed over is not to draw it.
func test_the_road_is_worn_in_some_places_and_drifted_over_in_others() -> void:
	var wear := _farmstead._wear_noise()
	var clearest := 0.0
	var deepest := 1.0
	var distance := 0.0
	while distance <= 100.0:
		var worn: float = _farmstead._wear_at(wear, distance)
		clearest = maxf(clearest, worn)
		deepest = minf(deepest, worn)
		distance += 0.25
	assert_true(
		clearest > 0.97,
		"the road never reaches full strength anywhere along its length (best %.2f), so it "
			% clearest
			+ "reads as uniformly faint rather than as used"
	)
	assert_true(
		deepest < 0.45,
		"the road never drops below %.2f anywhere along its length, so nothing has drifted "
			% deepest
			+ "across it and it is a ruled line"
	)


## And the wear itself does not step, for the same reason nothing else in this
## task does: a step in the strength is a step in the picture. This is the one
## place the road could have popped -- in space rather than in time, along its
## own length -- and it is worth its own assertion.
func test_the_wear_never_steps_along_the_road() -> void:
	var wear := _farmstead._wear_noise()
	var worst := 0.0
	var previous: float = _farmstead._wear_at(wear, 0.0)
	var distance := 0.05
	while distance <= 100.0:
		var worn: float = _farmstead._wear_at(wear, distance)
		worst = maxf(worst, absf(worn - previous))
		previous = worn
		distance += 0.05
	assert_true(
		worst < 0.03,
		"the wear moves %.3f in five centimetres, which is a visible seam across the road"
			% worst
	)


## Deterministic. The static layer is baked once at startup and a road whose
## drifts reshuffled on every load is a road nobody could compose the shot
## against.
func test_the_same_road_is_baked_every_time() -> void:
	var first := _farmstead._wear_noise()
	var second := _farmstead._wear_noise()
	for distance in [0.0, 7.3, 19.0, 44.5, 88.25]:
		assert_almost_eq(
			_farmstead._wear_at(first, distance),
			_farmstead._wear_at(second, distance),
			0.0001,
			"the road wears differently on a second load, at %.2f m" % distance
		)


# ---------------------------------------------------------------------------
# The line across the frame
# ---------------------------------------------------------------------------


## Rule 11 again: a road is the strongest line the scene has, and a line that
## stops in open snow needs a reason. Both ends leave the establishing shot,
## which is about 70 m across the farmstead.
func test_the_road_leaves_the_picture_at_both_ends() -> void:
	var road: Array = FarmsteadScript.ROAD
	var first: Vector3 = road[0]
	var last: Vector3 = road[road.size() - 1]
	var centre: Vector3 = FarmsteadScript.BAKE_CENTRE
	for named in [["the near end", first], ["the far end", last]]:
		var point: Vector3 = named[1]
		var reach := maxf(absf(point.x - centre.x), absf(point.z - centre.z))
		assert_true(
			reach > 35.0,
			"%s of the road is %.1f m from the composition's centre, which is inside the "
				% [named[0], reach]
				+ "establishing frame -- the eye will find where the road stops"
		)


## ...and still inside the baked window, because a stroke outside it draws
## nothing at all and says nothing about it. tests/art/test_farmstead_placement
## asserts this over every line the farmstead bakes; this is the road's own
## copy, with the verge's half-width included, which that one cannot see.
func test_the_road_and_its_verge_fit_inside_the_baked_window() -> void:
	var centre: Vector3 = FarmsteadScript.BAKE_CENTRE
	var half: float = TrackMaskScript.STATIC_EXTENT_M * 0.5
	var reach: float = _farmstead.road_verge_radius
	var offenders := PackedStringArray()
	for point: Vector3 in FarmsteadScript.ROAD:
		if absf(point.x - centre.x) + reach > half or absf(point.z - centre.z) + reach > half:
			offenders.append("(%.1f, %.1f)" % [point.x, point.z])
	assert_eq(
		offenders.size(), 0,
		"%s put the road's shoulder outside the %.0f m baked window" % [
			", ".join(offenders), TrackMaskScript.STATIC_EXTENT_M
		]
	)


# ---------------------------------------------------------------------------
# The two helpers the shape depends on
# ---------------------------------------------------------------------------


## Cutting a polyline up for the wear must not change the road's shape. Every
## bend the composition authored has to survive as a vertex.
func test_resampling_keeps_every_bend_the_composition_authored() -> void:
	var cut: Array = _farmstead._resample(FarmsteadScript.ROAD, 3.0)
	var offenders := PackedStringArray()
	for point: Vector3 in FarmsteadScript.ROAD:
		var found := false
		for candidate: Vector3 in cut:
			if candidate.distance_to(point) < 0.001:
				found = true
				break
		if not found:
			offenders.append("(%.1f, %.1f)" % [point.x, point.z])
	assert_eq(offenders.size(), 0, "resampling rounded off the bends at %s" % ", ".join(offenders))
	assert_true(
		cut.size() > FarmsteadScript.ROAD.size(),
		"resampling produced no sub-segments, so the wear has nothing to vary along"
	)


## No piece longer than the step, or the wear is sampled too coarsely and the
## joints between strokes of different strength start to show.
func test_no_resampled_piece_is_longer_than_the_step() -> void:
	var step := 1.2
	var cut: Array = _farmstead._resample(FarmsteadScript.ROAD, step)
	var longest := 0.0
	for index in range(cut.size() - 1):
		longest = maxf(longest, (cut[index] as Vector3).distance_to(cut[index + 1]))
	assert_true(
		longest <= step + 0.001,
		"a resampled piece is %.2f m against a step of %.2f" % [longest, step]
	)


## The pair of wheel tracks stays a fixed gauge apart around a bend rather than
## crossing on the inside of it, which is what an offset taken from one leg
## rather than from the run through a point does.
func test_the_wheel_tracks_stay_a_fixed_gauge_apart_around_the_bends() -> void:
	var gauge: float = _farmstead.rut_gauge
	var left: Array = _farmstead._offset(FarmsteadScript.ROAD, -gauge)
	var right: Array = _farmstead._offset(FarmsteadScript.ROAD, gauge)
	assert_eq(left.size(), right.size(), "the two sides came out different lengths")
	var offenders := PackedStringArray()
	for index in range(mini(left.size(), right.size())):
		var apart: float = (left[index] as Vector3).distance_to(right[index])
		if absf(apart - gauge * 2.0) > 0.001:
			offenders.append("point %d is %.3f m across against %.3f" % [index, apart, gauge * 2.0])
	assert_eq(offenders.size(), 0, "; ".join(offenders))
