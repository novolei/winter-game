extends TestCase

## The mask is the slice's whole visual payload -- Art Bible rule 11 says the
## lines in the snow are the only detail in an otherwise empty field. A print
## that lands in the wrong texel, or that evaporates when the window scrolls,
## is a defect you can stare straight at in a screenshot and not see.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")

var _mask: TrackMask


func before_each() -> void:
	_mask = TrackMaskScript.new()
	# build_at() rather than adding to the tree: _ready() would also register
	# the mask in ServiceRegistry and subscribe it to EventBus.
	_mask.build_at(Vector3.ZERO)


func after_each() -> void:
	# Node is not reference counted (briefing section 2.2).
	_mask.free()
	_mask = null


func test_a_fresh_mask_is_empty() -> void:
	assert_almost_eq(_mask.value_at(Vector3.ZERO), 0.0)
	assert_almost_eq(_mask.value_at(Vector3(12.0, 0.0, -7.0)), 0.0)


func test_a_print_marks_the_spot_it_was_made_on() -> void:
	_mask.stamp(Vector3(3.0, 0.0, -2.0), 0.3, 0.8)
	assert_almost_eq(_mask.value_at(Vector3(3.0, 0.0, -2.0)), 0.8, 0.02)


## A large print with a compact edge, which is the shape actually asked for: a
## boot leaves a defined hollow with a rim, not a smudge that blends away over a
## metre. So the profile is a flat core and a short fall, and this pins both
## halves of that -- a plain "it decreases with distance" assertion would pass
## just as happily for the wide gentle halo this replaced.
func test_a_print_has_a_solid_core_and_a_compact_edge() -> void:
	_mask.stamp(Vector3.ZERO, 0.4, 1.0)
	var middle: float = _mask.value_at(Vector3.ZERO)
	var inner: float = _mask.value_at(Vector3(0.16, 0.0, 0.0))
	var rim: float = _mask.value_at(Vector3(0.34, 0.0, 0.0))
	var outside: float = _mask.value_at(Vector3(0.9, 0.0, 0.0))
	assert_almost_eq(middle, 1.0, 0.02)
	assert_true(inner > 0.9, "the core must still be pressed at 40%% of the radius, got %f" % inner)
	assert_true(rim < 0.35, "the edge must have fallen away by 85%% of the radius, got %f" % rim)
	assert_almost_eq(outside, 0.0)


## Composited with max(), not added. Walking the same line twenty times has to
## leave a track rather than a blown-out white streak.
func test_walking_the_same_line_does_not_burn_a_hole_in_it() -> void:
	for _repeat in range(25):
		_mask.stamp(Vector3(1.0, 0.0, 1.0), 0.3, 0.6)
	assert_almost_eq(_mask.value_at(Vector3(1.0, 0.0, 1.0)), 0.6, 0.02)


func test_a_stronger_print_overwrites_a_weaker_one() -> void:
	_mask.stamp(Vector3(1.0, 0.0, 1.0), 0.3, 0.3)
	_mask.stamp(Vector3(1.0, 0.0, 1.0), 0.3, 0.9)
	assert_almost_eq(_mask.value_at(Vector3(1.0, 0.0, 1.0)), 0.9, 0.02)
	# ...and a weaker one after does not erase it.
	_mask.stamp(Vector3(1.0, 0.0, 1.0), 0.3, 0.2)
	assert_almost_eq(_mask.value_at(Vector3(1.0, 0.0, 1.0)), 0.9, 0.02)


## The window scrolls under the player and every texel index changes with it.
## A trail that is not carried across the move is a trail that vanishes behind
## you as you walk -- which is the exact opposite of what this system is for.
func test_a_trail_stays_where_it_was_walked_when_the_window_moves() -> void:
	var spot := Vector3(5.0, 0.0, -4.0)
	_mask.stamp(spot, 0.35, 0.85)
	var before: float = _mask.value_at(spot)
	assert_true(before > 0.5, "setup failed: the print only reached %f" % before)

	var texel_before := _mask.cell_of(Vector2(spot.x, spot.z))
	assert_true(_mask.follow(Vector3(28.0, 0.0, -19.0)), "the window should have moved")
	var texel_after := _mask.cell_of(Vector2(spot.x, spot.z))
	assert_true(
		texel_before.distance_to(texel_after) > 1.0,
		"the window did not actually move: texel %s then %s" % [texel_before, texel_after]
	)
	assert_almost_eq(_mask.value_at(spot), before, 0.02)


## Everything the window has scrolled past is gone, and that has to be a clean
## zero rather than the border texel smeared outward.
func test_a_trail_left_far_behind_reads_as_untouched_snow() -> void:
	var spot := Vector3(2.0, 0.0, 2.0)
	_mask.stamp(spot, 0.35, 0.9)
	_mask.follow(Vector3(200.0, 0.0, 200.0))
	assert_almost_eq(_mask.value_at(spot), 0.0)


func test_staying_near_the_middle_does_not_scroll_the_window() -> void:
	var origin := _mask.origin()
	assert_false(_mask.follow(Vector3(1.5, 0.0, 0.5)), "a metre and a half must not scroll the window")
	assert_almost_eq(_mask.origin().x, origin.x)
	assert_almost_eq(_mask.origin().y, origin.y)


## "No two steps alike" is a claim about the data, not about how it looks, so it
## is worth pinning: two prints made with different edge seeds must not be the
## same shape, and the same seed must reproduce exactly. The second half is what
## guarantees a print cannot shimmer or redraw itself differently once laid
## down, which the alternative -- a randf() inside stamp() -- could not promise.
func test_two_prints_differ_but_a_seed_reproduces_one() -> void:
	var probes := [
		Vector3(0.26, 0.0, 0.0), Vector3(-0.26, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.26), Vector3(0.0, 0.0, -0.26),
		Vector3(0.19, 0.0, 0.19), Vector3(-0.19, 0.0, -0.19),
	]
	var first: Array[float] = []
	var second: Array[float] = []
	var repeat: Array[float] = []

	_mask.stamp(Vector3.ZERO, 0.3, 1.0, Vector2.RIGHT, 1.5, 0.55, 0.35, 11.0)
	for probe in probes:
		first.append(_mask.value_at(probe))

	_mask.build_at(Vector3.ZERO)
	_mask.stamp(Vector3.ZERO, 0.3, 1.0, Vector2.RIGHT, 1.5, 0.55, 0.35, 271.0)
	for probe in probes:
		second.append(_mask.value_at(probe))

	_mask.build_at(Vector3.ZERO)
	_mask.stamp(Vector3.ZERO, 0.3, 1.0, Vector2.RIGHT, 1.5, 0.55, 0.35, 11.0)
	for probe in probes:
		repeat.append(_mask.value_at(probe))

	assert_true(first != second, "two seeds produced the identical outline: %s" % [first])
	assert_eq(repeat, first, "the same seed must redraw the same print")


## The mask is a plan view of a surface that is not flat, so a print on a flank
## has to be stored stretched along the fall line -- otherwise it reads as
## punched vertically into a tilted surface instead of placed on it. Checked as
## a shape claim rather than by eye: the mark must reach further downhill than
## it does across the slope, and not move its centre doing it.
func test_a_print_on_a_slope_reaches_further_downhill() -> void:
	var fall := Vector2(1.0, 0.0)
	_mask.stamp(Vector3.ZERO, 0.3, 1.0, Vector2.ZERO, 1.0, 0.55, 0.0, 0.0, fall, 1.4)
	var downhill: float = _mask.value_at(Vector3(0.36, 0.0, 0.0))
	var across: float = _mask.value_at(Vector3(0.0, 0.0, 0.36))
	assert_true(
		downhill > across,
		"downhill reach %f must exceed across-slope reach %f" % [downhill, across]
	)
	assert_almost_eq(_mask.value_at(Vector3.ZERO), 1.0, 0.02)


## ...and level ground must be left exactly as it was. The slope transform is
## skipped rather than applied with an identity, so this is the test that says
## the skip is correct rather than merely fast.
func test_a_print_on_level_ground_is_unchanged_by_the_slope_path() -> void:
	_mask.stamp(Vector3.ZERO, 0.3, 1.0, Vector2.ZERO, 1.0, 0.55, 0.0, 0.0, Vector2.ZERO, 1.0)
	var east: float = _mask.value_at(Vector3(0.2, 0.0, 0.0))
	var north: float = _mask.value_at(Vector3(0.0, 0.0, 0.2))
	assert_almost_eq(east, north, 0.02)


## ---------------------------------------------------------------------------
## The shape of a print, judged against a photograph of real ones
## ---------------------------------------------------------------------------
## Three claims, and none of them is a matter of degree:
##
##   a print is a hole that fell in on itself, not an oval with noise on it;
##   a mark in thin snow is a SCRAPE, which is a different event and not a
##     smaller hole;
##   where the walker stopped or turned, the prints churn together into one
##     broken patch rather than into a clean plateau.
##
## Each is measured here rather than looked at, because the difference between
## "torn" and "rippled" -- and between "churned" and "flattened" -- is invisible
## in a still until you already know which one you are looking at.

## The shipped deep-snow print, from PlayerController's print block. Duplicated
## rather than read off the controller because these tests are about what the
## mask does with the numbers, and a test that reads its inputs from the thing it
## is testing cannot fail.
const DEEP_RADIUS := 0.28
const DEEP_CORE := 0.66
const DEEP_IRREGULARITY := 0.46
const STRIDE := 0.72


## The outline, in `samples` directions, as the distance at which the mark falls
## away. Measured on a CIRCULAR print so that everything this returns is the tear
## and none of it is the boot's own oval.
func _outline(strength: float, seed_value: float, samples: int) -> Array[float]:
	_mask.build_at(Vector3.ZERO)
	_mask.stamp(
		Vector3.ZERO, DEEP_RADIUS, strength, Vector2.ZERO, 1.0, DEEP_CORE,
		DEEP_IRREGULARITY, seed_value
	)
	var edges: Array[float] = []
	for index in range(samples):
		var angle := TAU * float(index) / float(samples)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach := 0.0
		var probe := 0.02
		while probe < DEEP_RADIUS * 1.6:
			if _mask.value_at(direction * probe) > strength * 0.15:
				reach = probe
			probe += 0.01
		edges.append(reach)
	return edges


## A TORN outline and not a rippled one, which is the whole of the difference
## between "an oval with noise applied" and "a hole that fell in on itself".
##
## Two assertions, and it takes both: the spread says the outline moves, and the
## crossing count says it moves in a few big lobes rather than in a fine wobble.
## A high-frequency ripple of the same amplitude passes the first and fails the
## second, and it is exactly what this replaced.
func test_the_outline_is_torn_into_a_few_coarse_lobes() -> void:
	var samples := 64
	var edges := _outline(1.0, 4.0, samples)
	var lowest := INF
	var highest := -INF
	var total := 0.0
	for reach in edges:
		lowest = minf(lowest, reach)
		highest = maxf(highest, reach)
		total += reach
	var mean := total / float(samples)
	assert_true(
		highest - lowest > mean * 0.25,
		"the outline only moves %.3f m about a mean of %.3f -- that is an oval"
			% [highest - lowest, mean]
	)

	var crossings := 0
	for index in range(samples):
		var here := edges[index] - mean
		var next := edges[(index + 1) % samples] - mean
		if (here < 0.0) != (next < 0.0):
			crossings += 1
	assert_true(
		crossings <= 12,
		"the outline crosses its own mean %d times in one turn, which is %d lobes -- "
			% [crossings, crossings / 2]
			+ "a fine wobble on an oval rather than a torn edge"
	)


## ...and the tear must not go so far that the mark stops being one mark. Left
## ungated, a warp this coarse tears the print into three or four islands, which
## is not a bite out of a hole -- it is the ring of hard little fragments that
## was put around every print once and rejected.
func test_a_torn_print_is_still_one_mark_and_not_a_scatter_of_fragments() -> void:
	for seed_value in [0.0, 37.3, 74.6, 211.9]:
		_mask.build_at(Vector3.ZERO)
		_mask.stamp(
			Vector3.ZERO, DEEP_RADIUS, 1.0, Vector2.ZERO, 1.0, DEEP_CORE,
			DEEP_IRREGULARITY, seed_value
		)
		for index in range(24):
			var angle := TAU * float(index) / 24.0
			var probe := Vector3(cos(angle), 0.0, sin(angle)) * DEEP_RADIUS * 0.45
			assert_true(
				_mask.value_at(probe) > 0.6,
				"seed %.1f: the middle of the print is holed at %s, reading %f"
					% [seed_value, probe, _mask.value_at(probe)]
			)


## THE GUARD ON THE FURROW, and the reason the tear leans inward.
##
## Two prints are one stride apart and the snow between them has to stay snow. An
## outline free to grow by the full irregularity closes an 0.16 m gap on a 0.28 m
## half-length, and a chain of prints that touch is the continuous ribbon the
## furrow work spent three passes escaping.
func test_two_prints_a_stride_apart_do_not_run_together() -> void:
	for seed_value in [0.0, 37.3, 74.6, 211.9, 400.1]:
		_mask.build_at(Vector3.ZERO)
		_mask.stamp(
			Vector3.ZERO, DEEP_RADIUS, 1.0, Vector2.RIGHT, 1.5, DEEP_CORE,
			DEEP_IRREGULARITY, seed_value
		)
		_mask.stamp(
			Vector3(STRIDE, 0.0, 0.0), DEEP_RADIUS, 1.0, Vector2.RIGHT, 1.5, DEEP_CORE,
			DEEP_IRREGULARITY, seed_value + 13.0
		)
		var between: float = _mask.value_at(Vector3(STRIDE * 0.5, 0.0, 0.0))
		assert_true(
			between < 0.25,
			"seed %.1f: the snow between two prints reads %f, so the chain has joined up"
				% [seed_value, between]
		)


## A DUSTING RECORDS A LIGHT BOOT, NOT A LONG SMEAR.  The previous snow-depth
## language stretched a thin print by 70%, narrowed it and removed its floor;
## in the gameplay camera that read as a foot dragged through paint.  Thin snow
## may chip the outline, but heel, waist and forefoot still belong to one planted
## sole and its reach stays close to the deeper print.
func test_a_profiled_thin_print_is_a_light_complete_boot_not_a_long_scuff() -> void:
	var profile: TrackProfileDefinition = _mask.profile_for_subject(&"player")
	assert_not_null(profile, "the player boot profile did not load")
	if profile == null:
		return
	var hole := _profiled_mark(profile, 0.0, 1.0)
	var dust := _profiled_mark(profile, 1.0, 0.22)
	assert_true(
		dust.x <= hole.x * 1.10,
		"the dusting runs %.3f m along the walk against the deep print's %.3f -- "
			% [dust.x, hole.x]
			+ "it is still the rejected dragged smear"
	)
	assert_true(
		dust.y >= hole.y * 0.72,
		"the dusting narrowed to %.3f m against the boot's %.3f; the sole disappeared"
			% [dust.y, hole.y]
	)
	assert_true(
		dust.z >= 0.10 and dust.z < 0.24,
		"the thin sole reads %.3f at the waist; it must be light but anatomically whole"
			% dust.z
	)


## (reach along the walk, reach across it, the depth a third of the way out) for
## one mark, averaged over four steps.
##
## The reaches are the extent of the whole mark rather than the range of one ray
## outward: the outline is torn, so a ray lands in whatever bite happens to be in
## front of it and measures the bite instead of the print.
func _mark(scuff: float) -> Vector3:
	var along := 0.0
	var across := 0.0
	var floor_depth := 0.0
	var seeds := [5.0, 61.0, 143.0, 289.0]
	for seed_value in seeds:
		_mask.build_at(Vector3.ZERO)
		_mask.stamp(
			Vector3.ZERO, DEEP_RADIUS, 0.5, Vector2.RIGHT, 1.5, DEEP_CORE, 0.34,
			seed_value, Vector2.ZERO, 1.0, scuff
		)
		var probe_x := -0.7
		while probe_x <= 0.7:
			var probe_z := -0.7
			while probe_z <= 0.7:
				if _mask.value_at(Vector3(probe_x, 0.0, probe_z)) > 0.03:
					along = maxf(along, absf(probe_x))
					across = maxf(across, absf(probe_z))
				probe_z += 0.01
			probe_x += 0.01
		floor_depth += _mask.value_at(Vector3(DEEP_RADIUS * 0.4, 0.0, 0.0))
	return Vector3(along, across, floor_depth / float(seeds.size()))


func _profiled_mark(
	profile: TrackProfileDefinition, scuff: float, strength: float
) -> Vector3:
	_mask.build_at(Vector3.ZERO)
	_mask.stamp_profiled(
		Vector3.ZERO, DEEP_RADIUS, strength, Vector2.RIGHT, 1.5, DEEP_CORE, 0.34,
		71.0, Vector2.ZERO, 1.0, scuff, profile
	)
	var along := 0.0
	var across := 0.0
	var probe_x := -0.7
	while probe_x <= 0.7:
		var probe_z := -0.7
		while probe_z <= 0.7:
			if _mask.value_at(Vector3(probe_x, 0.0, probe_z)) > 0.025:
				along = maxf(along, absf(probe_x))
				across = maxf(across, absf(probe_z))
			probe_z += 0.01
		probe_x += 0.01
	return Vector3(
		along, across,
		_mask.value_at(Vector3(-DEEP_RADIUS * 0.05, 0.0, 0.0))
	)


## WHERE HE STOPPED OR TURNED. Prints composite with max(), and max() of two
## marks that each carry their own private floor noise is SMOOTHER than either --
## the peaks of one fill the troughs of the other, and a churned patch converges
## on a flat plateau. The break is therefore sampled in world space, where every
## print overlapping a place agrees about it, and this is the test that says so:
## move that noise back into the print's own frame and the patch flattens.
func test_prints_trodden_over_each_other_churn_rather_than_flatten() -> void:
	var spots := [
		Vector2(0.0, 0.0), Vector2(0.16, 0.09), Vector2(-0.13, 0.14),
		Vector2(0.07, -0.15), Vector2(-0.18, -0.06), Vector2(0.2, 0.02),
	]
	for index in range(spots.size()):
		var spot: Vector2 = spots[index]
		_mask.stamp(
			Vector3(spot.x, 0.0, spot.y), DEEP_RADIUS, 1.0, Vector2.RIGHT, 1.5,
			DEEP_CORE, DEEP_IRREGULARITY, float(index) * 61.7
		)
	var lowest := INF
	var highest := -INF
	var probe_x := -0.3
	while probe_x <= 0.3:
		var probe_z := -0.3
		while probe_z <= 0.3:
			var value: float = _mask.value_at(Vector3(probe_x, 0.0, probe_z))
			if value > 0.5:
				lowest = minf(lowest, value)
				highest = maxf(highest, value)
			probe_z += 0.02
		probe_x += 0.02
	assert_true(highest > 0.9, "setup: the trodden patch never reached full depth")
	assert_true(
		highest - lowest > 0.12,
		"six prints trodden over each other left a patch flat to within %f -- "
			% (highest - lowest)
			+ "that is a plateau, not churned snow"
	)


## The break is SIGNED, and this is what that buys: it lifts the shoulder as
## often as it drops it, so a torn print is not simply a shallower print. The
## deepest point is still exactly as deep as the caller asked for.
func test_tearing_a_print_does_not_quietly_make_it_shallower() -> void:
	_mask.stamp(
		Vector3.ZERO, DEEP_RADIUS, 0.9, Vector2.RIGHT, 1.5, DEEP_CORE,
		DEEP_IRREGULARITY, 91.0
	)
	assert_almost_eq(
		_mask.value_at(Vector3.ZERO), 0.9, 0.02,
		"a torn print no longer reaches the depth it was asked for"
	)


## ---------------------------------------------------------------------------
## The ploughed furrow
## ---------------------------------------------------------------------------
## A footprint is a soft dome. A furrow is a V, and getting that cross-section
## right is most of what makes it read as ploughed rather than as a ribbon laid
## on the snow. See TrackMask.plough().


## Snapped to the mask's own texel grid. value_at() reads the NEAREST texel, so a
## probe landing half a texel off the centre line reads the profile half a texel
## out -- worth 5% of the depth on a groove seven texels wide, which is a
## property of the probe and not of the groove.
func _grid(x: float, z: float) -> Vector3:
	var cell := TrackMask.CELL_M
	return Vector3(roundf(x / cell) * cell, 0.0, roundf(z / cell) * cell)


## THE SHAPE, asserted as arithmetic. The profile has to be LINEAR across the
## width -- depth * (1 - |across| / half_width) -- so the two flanks are flat
## facets that take different palette tones under a low sun. The flat-cored
## smoothstep the footprints use would sit at full depth across half the groove
## and read as a channel with a floor, which is the thing that was rejected.
func test_a_furrow_has_an_inverted_triangle_cross_section() -> void:
	var cell := TrackMask.CELL_M
	# Eight texels of half-width, so the profile can be read off the grid at
	# exact fractions instead of through the nearest-texel rounding.
	var half_width := cell * 8.0
	var centre := _grid(0.0, 0.0)
	_mask.plough(centre - Vector3(1.0, 0.0, 0.0), centre + Vector3(1.0, 0.0, 0.0), half_width, 0.9)
	var peak: float = _mask.value_at(centre)
	assert_almost_eq(peak, 0.9, 0.01, "the centre line carries the full depth")
	for texels in [2, 4, 6]:
		var across := centre + Vector3(0.0, 0.0, cell * float(texels))
		assert_almost_eq(
			_mask.value_at(across), 0.9 * (1.0 - float(texels) / 8.0), 0.01,
			"at %d of the 8 texels of half-width the taper must be straight" % texels
		)
	# ...and explicitly not a dome: a flat core would still be at full depth a
	# quarter of the way out.
	assert_true(
		_mask.value_at(centre + Vector3(0.0, 0.0, cell * 2.0)) < peak * 0.85,
		"the groove must taper from the centre line, not sit flat across a core"
	)


func test_a_furrow_is_symmetrical_about_its_centre_line() -> void:
	_mask.plough(Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.30, 0.8)
	for offset in [0.08, 0.16, 0.24]:
		assert_almost_eq(
			_mask.value_at(Vector3(0.0, 0.0, offset)),
			_mask.value_at(Vector3(0.0, 0.0, -offset)),
			0.02,
			"the two flanks must match at %f m off the line" % offset
		)


## The groove is a swept segment, not a line across the world: everything past
## its ends and everything wider than its own width is untouched snow.
func test_a_furrow_stays_inside_its_own_width_and_ends() -> void:
	_mask.plough(Vector3.ZERO, Vector3(0.6, 0.0, 0.0), 0.16, 0.7)
	# The centre first, or every assertion below is satisfied by drawing nothing.
	assert_almost_eq(_mask.value_at(Vector3(0.3, 0.0, 0.0)), 0.7, 0.02)
	assert_almost_eq(_mask.value_at(Vector3(0.3, 0.0, 0.2)), 0.0, 0.01)
	assert_almost_eq(_mask.value_at(Vector3(-0.25, 0.0, 0.0)), 0.0, 0.01)
	assert_almost_eq(_mask.value_at(Vector3(0.85, 0.0, 0.0)), 0.0, 0.01)


## Composited with max() like everything else here, so the boot pockets either
## side of the channel keep their outline and their rim. A furrow strong enough
## to swallow the prints is the failure mode, not the goal.
func test_a_furrow_does_not_swallow_the_prints_beside_it() -> void:
	var first := Vector3.ZERO
	var second := Vector3(0.72, 0.0, 0.0)
	var between := Vector3(0.36, 0.0, 0.0)
	_mask.stamp(first, 0.28, 1.0)
	_mask.stamp(second, 0.28, 1.0)
	assert_almost_eq(
		_mask.value_at(between), 0.0,
		0.01, "setup: two prints a stride apart must not already touch"
	)

	_mask.plough(first, second, 0.17, 0.62)
	var groove: float = _mask.value_at(between)
	assert_true(groove > 0.4, "the gap between two prints must be joined, got %f" % groove)
	assert_true(
		groove < _mask.value_at(first) - 0.2,
		"the groove (%f) must stay clearly shallower than the print (%f)"
			% [groove, _mask.value_at(first)]
	)


## A run of short segments is how the furrow is actually drawn -- one per physics
## tick, each shorter than the groove is wide. The union of those has to be the
## exact swept region of the path, with no dip where two of them meet: a dip at
## every joint is a bead pattern down the trail, which is the polyline failure
## wearing a smaller stride.
func test_a_run_of_segments_leaves_an_even_channel() -> void:
	var step := 0.06
	var half_width := 0.17
	for index in range(40):
		_mask.plough(
			Vector3(float(index) * step, 0.0, 0.0),
			Vector3(float(index + 1) * step, 0.0, 0.0),
			half_width, 0.7
		)
	var low := INF
	var high := -INF
	var probe := 0.3
	while probe < 2.1:
		var value: float = _mask.value_at(Vector3(probe, 0.0, 0.0))
		low = minf(low, value)
		high = maxf(high, value)
		probe += 0.02
	assert_true(high - low < 0.05, "the channel dips %f between its joints" % (high - low))
	assert_almost_eq(high, 0.7, 0.02)


## A furrow event with both ends draws; one missing an end draws nothing rather
## than a groove from the world origin, which is the mistake the trench payload
## it replaces made once already.
func test_a_furrow_event_ploughs_and_a_half_specified_one_does_not() -> void:
	_mask._on_furrow({
		"from": Vector3.ZERO, "to": Vector3(0.6, 0.0, 0.0), "half_width": 0.16, "depth": 0.7,
	})
	var tuned := _mask.value_at(Vector3(0.3, 0.0, 0.0))
	assert_true(tuned > 0.35 and tuned < 0.56, "legacy furrow bypassed its data definition: %f" % tuned)

	_mask._on_furrow({"from": Vector3(5.0, 0.0, 0.0), "half_width": 0.16, "depth": 0.7})
	assert_almost_eq(_mask.value_at(Vector3(5.3, 0.0, 0.0)), 0.0, 0.01)
	_mask._on_furrow(null)
	_mask._on_furrow("not a furrow")
	assert_almost_eq(_mask.value_at(Vector3(0.3, 0.0, 0.0)), tuned, 0.01)


## Two prints on a wind-scoured crest carry no furrow between them, and the snow
## between them must be left alone. This is the half of the gate a screenshot
## cannot show, because "no groove here" and "a groove too faint to see" look
## identical.
func test_two_footprints_alone_leave_the_snow_between_untouched() -> void:
	_mask._on_footprint({"subject": &"player", "position": Vector3.ZERO, "radius": 0.28, "strength": 0.9})
	_mask._on_footprint({"subject": &"player", "position": Vector3(0.72, 0.0, 0.0), "radius": 0.28, "strength": 0.9})
	assert_almost_eq(_mask.value_at(Vector3(0.36, 0.0, 0.0)), 0.0, 0.01)


## The furrow lives on the DYNAMIC layer, so the wind and the falling snow work
## on it exactly as they work on a footprint. A groove that outlived the trail it
## belongs to would leave the player's route legible long after the prints that
## made it had gone -- which is GDD section 8's whole mechanic, inverted.
func test_a_furrow_fills_in_with_the_weather_like_a_print() -> void:
	var spot := _grid(3.0, -2.0)
	_mask.plough(spot - Vector3(0.5, 0.0, 0.0), spot + Vector3(0.5, 0.0, 0.0), 0.17, 0.8)
	var fresh: float = _mask.value_at(spot)
	assert_almost_eq(fresh, 0.8, 0.01, "setup: the furrow only reached %f" % fresh)
	assert_almost_eq(_mask.static_value_at(spot), 0.0, 0.001, "a furrow is not baked terrain")

	for _slice in range(80):
		_mask.decay(0.5)
	assert_true(
		_mask.value_at(spot) < fresh - 0.2,
		"forty seconds of still weather left the furrow at %f, from %f"
			% [_mask.value_at(spot), fresh]
	)


## An event carrying a payload this system does not understand must be ignored,
## not crash the dispatch loop for every other subscriber.
func test_a_footprint_event_stamps_and_a_junk_payload_does_not() -> void:
	# The mask does not know the species that pressed the snow. A future wolf,
	# bear, or any other named walker writes through this one event unchanged.
	_mask._on_footprint({"subject": &"wolf", "position": Vector3(2.0, 0.0, 3.0), "radius": 0.3, "strength": 0.7})
	assert_almost_eq(_mask.value_at(Vector3(2.0, 0.0, 3.0)), 0.7, 0.02)
	_mask._on_footprint({"position": Vector3(-2.0, 0.0, 3.0), "radius": 0.3, "strength": 0.7})
	_mask._on_footprint({"subject": &"", "position": Vector3(-3.0, 0.0, 3.0), "radius": 0.3, "strength": 0.7})
	_mask._on_footprint(null)
	_mask._on_footprint("not a footprint")
	assert_almost_eq(_mask.value_at(Vector3(2.0, 0.0, 3.0)), 0.7, 0.02)
	assert_almost_eq(_mask.value_at(Vector3(-2.0, 0.0, 3.0)), 0.0, 0.001)
	assert_almost_eq(_mask.value_at(Vector3(-3.0, 0.0, 3.0)), 0.0, 0.001)


## ---------------------------------------------------------------------------
## The static layer
## ---------------------------------------------------------------------------
## Art Bible section 3: the mask has two layers, and the whole reason for the
## split is that the wind will erase one of them and must never touch the other.
## There is no wind yet, so the property that can be asserted today is the
## structural half -- the baked layer is independent of the scrolling one, does
## not move with it, and survives everything that happens to it.


func test_a_fresh_static_layer_is_empty() -> void:
	assert_almost_eq(_mask.static_value_at(Vector3.ZERO), 0.0)
	assert_almost_eq(_mask.static_value_at(Vector3(9.0, 0.0, -14.0)), 0.0)
	assert_almost_eq(_mask.combined_value_at(Vector3.ZERO), 0.0)


func test_a_baked_stroke_marks_the_ground_it_was_baked_on() -> void:
	_mask.bake_stroke(Vector3(-4.0, 0.0, 2.0), Vector3(4.0, 0.0, 2.0), 0.2, 0.8)
	assert_true(_mask.static_value_at(Vector3(0.0, 0.0, 2.0)) > 0.7, "the middle of the stroke is not marked")
	assert_true(_mask.static_value_at(Vector3(3.5, 0.0, 2.0)) > 0.7, "the far end of the stroke is not marked")
	assert_almost_eq(_mask.static_value_at(Vector3(0.0, 0.0, 4.0)), 0.0)


## The one that matters. The dynamic window scrolls with the player and drops
## whatever it scrolls past; if the baked layer were carried along with it, the
## first long walk would take the ploughed field with it.
func test_the_baked_layer_does_not_move_when_the_dynamic_window_does() -> void:
	var spot := Vector3(6.0, 0.0, -3.0)
	_mask.bake_stroke(spot - Vector3(3.0, 0.0, 0.0), spot + Vector3(3.0, 0.0, 0.0), 0.2, 0.9)
	var before: float = _mask.static_value_at(spot)
	var origin_before := _mask.static_origin()
	assert_true(before > 0.8, "setup failed: the stroke only reached %f" % before)

	assert_true(_mask.follow(Vector3(30.0, 0.0, 26.0)), "the dynamic window should have moved")
	assert_almost_eq(_mask.static_value_at(spot), before, 0.001)
	assert_almost_eq(_mask.static_origin().x, origin_before.x)
	assert_almost_eq(_mask.static_origin().y, origin_before.y)

	# ...and even a walk far enough to empty the dynamic layer entirely.
	_mask.follow(Vector3(400.0, 0.0, 400.0))
	assert_almost_eq(_mask.static_value_at(spot), before, 0.001)


## Two layers, not one image written twice. A footprint must not appear in the
## baked layer and a furrow must not be scrollable.
func test_the_two_layers_are_independent() -> void:
	var spot := Vector3(1.0, 0.0, 1.0)
	_mask.stamp(spot, 0.3, 0.9)
	assert_almost_eq(_mask.static_value_at(spot), 0.0, 0.001)

	var baked := Vector3(-2.0, 0.0, -2.0)
	_mask.bake_stroke(baked, baked + Vector3(2.0, 0.0, 0.0), 0.2, 0.7)
	assert_almost_eq(_mask.value_at(baked), 0.0, 0.001)


## What the shader draws is the deeper of the two, so a boot in a furrow is one
## mark in the snow rather than a hole twice as deep.
func test_the_combined_read_is_the_deeper_of_the_two_layers() -> void:
	var spot := Vector3(3.0, 0.0, -1.0)
	_mask.bake_stroke(spot - Vector3(1.0, 0.0, 0.0), spot + Vector3(1.0, 0.0, 0.0), 0.25, 0.4)
	assert_almost_eq(_mask.combined_value_at(spot), 0.4, 0.03)
	_mask.stamp(spot, 0.3, 0.85)
	assert_almost_eq(_mask.combined_value_at(spot), 0.85, 0.03)
	# ...and the weaker layer does not pull the result down.
	assert_true(_mask.combined_value_at(spot) >= _mask.value_at(spot) - 0.001)


## A ploughed field has to read as separate passes. The assertion is the *gap*:
## a band of furrows whose spacing has collapsed, or whose width has run away,
## is a grey smear and there is nothing in a screenshot that would say which.
func test_furrows_are_separate_passes_with_clean_snow_between_them() -> void:
	var origin := Vector3(-5.0, 0.0, 0.0)
	_mask.bake_furrows(origin, Vector2(1.0, 0.0), 10.0, 1.0, 4, 0.12, 0.7)
	# Sampled two metres in, which every pass covers whatever its own start and
	# end wobble did.
	for index in range(4):
		var on := Vector3(-1.0, 0.0, float(index))
		assert_true(
			_mask.static_value_at(on) > 0.3,
			"furrow %d is missing at %s, got %f" % [index, on, _mask.static_value_at(on)]
		)
	for index in range(3):
		var between := Vector3(-1.0, 0.0, float(index) + 0.5)
		assert_almost_eq(_mask.static_value_at(between), 0.0, 0.02)


## A winter field must retain the direction of its worked rows without becoming
## an evenly spaced screen-wide hatch.  The long-run assertion is deliberately
## in metres rather than pixels: the static mask is the shared source for every
## camera framing, so the source itself must contain regular snow breaks.
func test_broken_furrows_keep_worked_direction_without_continuous_rows() -> void:
	var origin := Vector3(-24.0, 0.0, -18.0)
	var length := 36.0
	var segment_max := 6.0
	_mask.bake_broken_furrows(
		origin, Vector2.RIGHT, length, 4.0, 4, 0.16, 0.6,
		3.0, segment_max, 3.0, 6.0, 41077, 0.2
	)
	var marked_rows := 0
	var worst_continuous_run := 0.0
	for row in range(4):
		var marked := 0
		var current_run := 0.0
		for step in range(145):
			var point := origin + Vector3(float(step) * 0.25, 0.0, float(row) * 4.0)
			if _mask.static_value_at(point) > 0.08:
				marked += 1
				current_run += 0.25
				worst_continuous_run = maxf(worst_continuous_run, current_run)
			else:
				current_run = 0.0
		if marked > 0:
			marked_rows += 1
	assert_eq(marked_rows, 4, "each authored row needs at least one surviving winter trace")
	assert_true(
		worst_continuous_run < segment_max + 1.0,
		"a %.2f m uninterrupted row exceeds the %.2f m gesture budget and will read as hatching" % [
			worst_continuous_run, segment_max,
		]
	)


## Rebaking is how a composition is re-sited, and it has to be a clean slate --
## a second bake over the top of a first would accumulate every furrow the field
## ever had.
func test_baking_again_clears_what_was_there() -> void:
	var spot := Vector3(2.0, 0.0, 5.0)
	_mask.bake_stroke(spot - Vector3(1.0, 0.0, 0.0), spot + Vector3(1.0, 0.0, 0.0), 0.2, 0.8)
	assert_true(_mask.static_value_at(spot) > 0.7)
	_mask.bake_at(Vector3.ZERO)
	assert_almost_eq(_mask.static_value_at(spot), 0.0)


## Outside the baked window there is nothing ploughed, and it has to read as a
## clean zero rather than as the border texel smeared out to the horizon --
## the same guarantee value_at() gives for the dynamic layer.
func test_outside_the_baked_window_reads_as_untouched_snow() -> void:
	var far := Vector3(TrackMask.STATIC_EXTENT_M, 0.0, TrackMask.STATIC_EXTENT_M)
	_mask.bake_stroke(far, far + Vector3(4.0, 0.0, 0.0), 0.3, 1.0)
	assert_almost_eq(_mask.static_value_at(far), 0.0)
	assert_almost_eq(_mask.combined_value_at(far), 0.0)


## The low-end transport contract: the canonical CPU mask remains 2048-square,
## but one ordinary step must not send all four MiB to the GPU.  A 514-square R8
## layer includes the one-texel bilinear gutter and is still under 260 KiB.
func test_an_ordinary_step_uploads_one_guttered_layer_not_the_whole_mask() -> void:
	_mask.flush()
	assert_true(_mask.texture() is Texture2DArray)
	assert_eq(_mask.last_upload_layer_count(), TrackMask.UPLOAD_LAYER_COUNT)

	# Well inside one chunk: neither the print nor its one-texel gutter reaches a
	# transport boundary.
	_mask.stamp(Vector3(-10.0, 0.0, -10.0), 0.28, 1.0)
	_mask.flush()
	assert_eq(_mask.last_upload_layer_count(), 1)
	assert_eq(_mask.last_upload_bytes(), TrackMask.UPLOAD_BYTES_PER_LAYER)
	assert_true(
		_mask.last_upload_bytes() < 300 * 1024,
		"one footprint uploaded %d bytes; it should stay below 300 KiB including gutters"
			% _mask.last_upload_bytes()
	)
	assert_true(_mask.last_upload_duration_ms() >= 0.0)

	# A clean frame must generate no driver upload at all.
	_mask.flush()
	assert_eq(_mask.last_upload_layer_count(), 0)
	assert_eq(_mask.last_upload_bytes(), 0)


## At an intersection of four cores, each layer needs the changed texels in its
## gutter. Four bounded uploads are correct; one layer would leave a visible
## horizontal, vertical or corner seam.
func test_a_print_on_a_four_layer_corner_updates_every_observer() -> void:
	_mask.flush()
	var boundary := -TrackMask.EXTENT_M * 0.5 + TrackMask.UPLOAD_CHUNK * TrackMask.CELL_M
	_mask.stamp(Vector3(boundary, 0.0, boundary), 0.28, 1.0)
	_mask.flush()
	assert_eq(_mask.last_upload_layer_count(), 4)
	assert_eq(_mask.last_upload_bytes(), TrackMask.UPLOAD_BYTES_PER_LAYER * 4)


## The source values on both sides of a transport border remain one continuous
## footprint after upload. Reading the array layers back is intentionally a GPU
## transport assertion rather than another assertion against the canonical CPU
## image which stamping already tests elsewhere in this file.
func test_layer_gutters_duplicate_the_real_neighbour_texels() -> void:
	_mask.flush()
	var boundary := -TrackMask.EXTENT_M * 0.5 + TrackMask.UPLOAD_CHUNK * TrackMask.CELL_M
	_mask.stamp(Vector3(boundary, 0.0, boundary), 0.28, 1.0)
	_mask.flush()
	# The headless dummy renderer cannot read a Texture2DArray back. These are
	# the exact reusable Images passed to update_layer(), exposed read-only by
	# TrackMask so the same transport can still be pinned under CI.
	var north_west: Image = _mask.upload_layer_image(0)
	var north_east: Image = _mask.upload_layer_image(1)
	var south_west: Image = _mask.upload_layer_image(4)
	var south_east: Image = _mask.upload_layer_image(5)
	var edge := TrackMask.UPLOAD_LAYER_SIZE - 1
	assert_eq(north_west.get_pixel(edge, edge), south_east.get_pixel(1, 1))
	assert_eq(north_east.get_pixel(0, edge), south_east.get_pixel(0, 1))
	assert_eq(north_west.get_pixel(edge, 1), north_east.get_pixel(1, 1))
	assert_eq(north_west.get_pixel(1, edge), south_west.get_pixel(1, 1))


## A long zigzag crosses every layer boundary and recentres dozens of times.
## Its retained CPU trail is already the gameplay truth; the transport budget
## here proves that ordinary frames stay bounded while recentres are the only
## frames allowed to refresh all sixteen layers.
func test_a_hundred_metre_zigzag_keeps_uploads_bounded() -> void:
	_mask.flush()
	var saw_recentre := false
	for step in range(101):
		var point := Vector3(float(step), 0.0, -12.0 if step % 2 == 0 else 12.0)
		if _mask.follow(point):
			saw_recentre = true
		_mask.stamp(point, 0.28, 0.8, Vector2.RIGHT, 2.0)
		_mask.flush()
		assert_true(
			_mask.last_upload_layer_count() <= TrackMask.UPLOAD_LAYER_COUNT,
			"zigzag step %d uploaded %d layers" % [step, _mask.last_upload_layer_count()]
		)
	assert_true(saw_recentre, "100 m did not exercise the scrolling window")
	assert_true(_mask.value_at(Vector3(100.0, 0.0, -12.0)) > 0.1)
