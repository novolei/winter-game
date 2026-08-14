extends TestCase

## The two transient pictures in the friendly-pigeon interaction.  The crumbs
## are not navigation data inferred from particles: one deterministic ballistic
## plan drives both the visible pieces and the food patch the pigeon walks to.
## The heart is equally explicit -- one short pop, rise and fade, never a label
## left hovering over the bird forever.

const BreadcrumbScatterScript := preload("res://src/entities/wildlife/breadcrumb_scatter.gd")
const PigeonAffectionScript := preload("res://src/entities/wildlife/pigeon_affection.gd")

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if node != null and is_instance_valid(node):
			node.free()
	_made.clear()


func test_breadcrumbs_follow_a_short_forward_arc_and_settle_as_one_food_patch() -> void:
	assert_true(
		BreadcrumbScatterScript.SETTLED_LIFETIME_SECONDS >= 10.5,
		"crumbs disappear before an edge-of-range pigeon can walk over and finish pecking"
	)
	var scatter = BreadcrumbScatterScript.new()
	_made.append(scatter)
	var origin := Vector3(0.0, 1.05, 0.28)
	var target := Vector3(0.0, 0.0, 1.10)
	scatter.scatter(origin, target, 20260813)

	assert_true(scatter.crumb_count() >= 12, "the throw is too sparse to read as scattered crumbs")
	var opening: Array[Vector3] = scatter.crumb_positions()
	scatter.advance(0.22)
	var arcing: Array[Vector3] = scatter.crumb_positions()
	var rose := false
	for index in mini(opening.size(), arcing.size()):
		if arcing[index].y > opening[index].y + 0.02:
			rose = true
			break
	assert_true(rose, "every crumb fell straight down; the feed has no throwing arc")

	for _step in range(120):
		scatter.advance(1.0 / 60.0)
	assert_eq(scatter.settled_count(), scatter.crumb_count(), "crumbs are still floating two seconds later")
	var landed: Array[Vector3] = scatter.crumb_positions()
	for point in landed:
		assert_true(absf(point.x - target.x) <= 0.46, "a crumb missed the authored lateral scatter")
		assert_true(absf(point.z - target.z) <= 0.38, "a crumb landed outside the food patch")
		assert_almost_eq(point.y, target.y, 0.001, "a settled crumb is not on the ground")


func test_the_affection_heart_pops_overshoots_rises_and_then_clears() -> void:
	assert_almost_eq(PigeonAffectionScript.scale_for(0.0), 0.0, 0.0001, "the heart appears at full size")
	var peak := 0.0
	for step in range(31):
		peak = maxf(peak, PigeonAffectionScript.scale_for(float(step) / 60.0))
	assert_true(peak > 1.08, "the heart has no juicy overshoot")
	assert_true(PigeonAffectionScript.rise_for(0.85) >= 0.16, "the heart does not float clear of the head")
	assert_almost_eq(PigeonAffectionScript.alpha_for(0.0), 0.0, 0.0001, "the heart starts as a hard cut")
	assert_true(PigeonAffectionScript.alpha_for(0.22) > 0.95, "the heart never reaches a readable hold")
	assert_almost_eq(PigeonAffectionScript.alpha_for(1.1), 0.0, 0.0001, "the heart remains over the pigeon")


func test_affection_uses_one_large_and_one_small_randomised_head_top_heart() -> void:
	var first: Array[Dictionary] = PigeonAffectionScript.heart_specs_for(20260813)
	var second: Array[Dictionary] = PigeonAffectionScript.heart_specs_for(20260814)
	assert_eq(first.size(), 2, "one meal does not produce two hearts")
	if first.size() != 2 or second.size() != 2:
		return
	assert_true(int(first[0]["font_size"]) >= 64, "the main heart was not enlarged")
	assert_true(int(first[0]["font_size"]) > int(first[1]["font_size"]),
		"the two hearts have no clear large/small hierarchy")
	var first_big: Vector3 = first[0]["offset"]
	var first_small: Vector3 = first[1]["offset"]
	assert_true(first_big.y > 0.0 and first_small.y > 0.0,
		"a heart was placed below the pigeon's head anchor")
	assert_true(first_big.distance_to(first_small) >= 0.10,
		"the large and small hearts overlap into one symbol")
	assert_true(
		(first[0]["offset"] as Vector3).distance_to(second[0]["offset"] as Vector3) > 0.01,
		"different meals reuse the same supposedly random heart placement"
	)
