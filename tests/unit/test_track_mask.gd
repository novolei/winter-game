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


## An event carrying a payload this system does not understand must be ignored,
## not crash the dispatch loop for every other subscriber.
func test_a_footprint_event_stamps_and_a_junk_payload_does_not() -> void:
	_mask._on_footprint({"position": Vector3(2.0, 0.0, 3.0), "radius": 0.3, "strength": 0.7})
	assert_almost_eq(_mask.value_at(Vector3(2.0, 0.0, 3.0)), 0.7, 0.02)
	_mask._on_footprint(null)
	_mask._on_footprint("not a footprint")
	assert_almost_eq(_mask.value_at(Vector3(2.0, 0.0, 3.0)), 0.7, 0.02)
