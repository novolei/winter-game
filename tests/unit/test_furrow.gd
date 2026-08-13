extends TestCase

## The ploughed furrow, judged as GEOMETRY rather than as a look.
##
## In snow past wading depth you cannot lift your feet clear of it -- you drag
## them, and a dragged boot does not stamp, it ploughs. What it leaves is a
## groove with an inverted-triangle cross-section: deepest along the centre line,
## rising in a straight taper to the surface at both edges.
##
## Two earlier passes at this shipped and were rejected, and the second failure
## is the reason this file exists at all. It was GEOMETRIC, not a matter of
## degree: the groove was emitted as one segment per footfall, so the trail was a
## polyline by construction and every change of direction was a hard corner. No
## reduction in strength fixes a corner and noise does not hide one -- it gives
## you a noisy corner. 需要避免之前那种连续的折线的感官.
##
## So the furrow is sampled from the walker's REAL position every physics tick
## and stamped along the path actually travelled. That claim is what the corner
## test below measures, and it is measured in degrees rather than looked at,
## because a screenshot of a straight walk cannot tell the two versions apart.

const PlayerScript := preload("res://src/entities/player/player_controller.gd")

## A physics tick, and a comfortable walking pace. Together they are what makes
## the sampling fine: 2.3 cm of ground per tick.
const TICK := 1.0 / 60.0
const PACE := 1.4
const TRACK_RESPONSE_DEPTH_M := 0.16

var _player: PlayerController


func before_each() -> void:
	# .new() rather than a tree: _ready() would load the model, register the
	# body in ServiceRegistry and subscribe it to EventBus (briefing trap 1).
	# advance_furrow() is deliberately free of all three.
	_player = PlayerScript.new()


func after_each() -> void:
	# CharacterBody3D is a Node, and Node is not reference counted (briefing 2.2).
	_player.free()
	_player = null


## Walks a path and collects every furrow sample it earns. `path` is a Callable
## taking the distance walked so far and returning a world position, so a test
## can hand over an arc as easily as a straight line.
func _walk(distance_m: float, path: Callable, depth: Callable) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	var walked := 0.0
	var step := PACE * TICK
	while walked <= distance_m:
		var here: Vector3 = path.call(walked)
		var here_depth: float = depth.call(walked)
		var samples: Array[Dictionary] = _player.advance_furrow(here, here_depth, _max_depth())
		collected.append_array(samples)
		walked += step
	return collected


## What SnowField calls a full hollow. Held here rather than read off the field
## so these tests exercise the controller alone.
func _max_depth() -> float:
	return 0.6


func _straight(along: float) -> Vector3:
	return Vector3(along, 0.0, 0.0)


## A left-hand arc of `ARC_RADIUS`, parameterised by arc length so the walker
## covers ground at a constant pace all the way round it.
const ARC_RADIUS := 2.0


func _arc(along: float) -> Vector3:
	var angle := along / ARC_RADIUS
	return Vector3(sin(angle) * ARC_RADIUS, 0.0, ARC_RADIUS - cos(angle) * ARC_RADIUS)


func _deep(_along: float) -> float:
	return 0.58


func _thin(_along: float) -> float:
	return 0.20


## ---------------------------------------------------------------------------
## The gate
## ---------------------------------------------------------------------------
## Below it there is nothing at all -- isolated prints, exactly as before. The
## threshold is the whole point of the feature: it is what makes deep snow behave
## differently, instead of the world wearing a permanent smear.


func test_thin_snow_leaves_no_furrow_at_all() -> void:
	var samples := _walk(6.0, _straight, _thin)
	assert_eq(samples.size(), 0, "thin snow must leave the prints isolated, got %d samples" % samples.size())


func test_deep_snow_opens_a_furrow() -> void:
	var samples := _walk(6.0, _straight, _deep)
	assert_true(samples.size() > 0, "the deepest snow must plough a furrow")
	for sample in samples:
		assert_true(
			float(sample["depth"]) > 0.3,
			"a furrow in 0.58 m of snow must be unmistakable, got depth %f" % sample["depth"]
		)
		assert_true(
			float(sample["half_width"]) > 0.1,
			"...and wide enough to read, got half-width %f" % sample["half_width"]
		)


## The gate is a depth in METRES, not a fraction of whatever the field's maximum
## happens to be that week. Stated so it can be checked against the ground: at
## the default it is SnowField.deep_depth_m, the depth the game already calls
## "reduced to a trudge".
func test_the_gate_is_a_depth_in_metres() -> void:
	var gate: float = _player.furrow_depth_start_m
	assert_true(gate >= 0.4, "the gate must be a genuinely deep snow depth, got %f m" % gate)
	assert_true(gate < _max_depth(), "a gate at or above the maximum would never open")

	var below := _walk(4.0, _straight, func(_a: float) -> float: return gate - 0.01)
	assert_eq(below.size(), 0, "a centimetre under the gate must leave the snow alone")

	_player.free()
	_player = PlayerScript.new()
	var above := _walk(4.0, _straight, func(_a: float) -> float: return gate + 0.001)
	assert_true(above.size() > 0, "a millimetre over the gate must start the furrow")


## ---------------------------------------------------------------------------
## Depth-responsive, and computed live
## ---------------------------------------------------------------------------


func test_deeper_snow_ploughs_deeper_and_wider() -> void:
	var shallow := _walk(6.0, _straight, func(_a: float) -> float: return 0.47)
	_player.free()
	_player = PlayerScript.new()
	var deep := _walk(6.0, _straight, _deep)
	assert_true(shallow.size() > 0 and deep.size() > 0, "both runs must produce a furrow")
	assert_true(
		_mean(deep, "depth") > _mean(shallow, "depth") + 0.05,
		"0.58 m must plough deeper than 0.47 m: %f vs %f"
			% [_mean(deep, "depth"), _mean(shallow, "depth")]
	)
	assert_true(
		_mean(deep, "half_width") > _mean(shallow, "half_width") + 0.01,
		"...and wider: %f vs %f" % [_mean(deep, "half_width"), _mean(shallow, "half_width")]
	)


## The old square-root onset made the first centimetre past the wading gate dig
## almost as strongly as a mature channel.  The transition must instead be
## continuous in virtual millimetres: twice the snow excess gives twice the
## nominal visual height, with no visible step at 0.42 m.
func test_furrow_depth_starts_continuously_at_the_gate() -> void:
	_player.furrow_depth_wobble = 0.0
	var gate: float = _player.furrow_depth_start_m
	var first_mm := _nominal_visual_height_m(gate + 0.001)
	var second_mm := _nominal_visual_height_m(gate + 0.002)
	assert_true(
		first_mm > 0.0 and first_mm < 0.001,
		"one millimetre over the gate must begin below 1 virtual mm, got %.3f virtual mm"
			% (first_mm * 1000.0)
	)
	assert_almost_eq(
		second_mm / maxf(first_mm, 0.000001), 2.0, 0.02,
		"the onset is not linear and continuous: %.3f then %.3f virtual mm"
			% [first_mm * 1000.0, second_mm * 1000.0]
	)


## These two depths bracket the problem seen in play: 0.43 m is only just into
## wading snow and must not read as a trench, while 0.58 m is a real drift and
## still needs a clearly traceable channel.  Values are the TrackMask response
## converted to virtual height, with longitudinal wobble disabled.
func test_furrow_visual_height_matches_shallow_and_deep_drift_targets() -> void:
	_player.furrow_depth_wobble = 0.0
	var onset_depth := _nominal_visual_height_m(0.43)
	var deep_depth := _nominal_visual_height_m(0.58)
	assert_almost_eq(
		onset_depth, 0.0041, 0.0006,
		"0.43 m snow must leave about 4 virtual mm, got %.2f virtual mm"
			% (onset_depth * 1000.0)
	)
	assert_almost_eq(
		deep_depth, 0.0654, 0.002,
		"0.58 m snow must retain about 65 virtual mm, got %.2f virtual mm"
			% (deep_depth * 1000.0)
	)
	assert_true(
		deep_depth >= 0.06,
		"deep drift furrows must remain trackable, got %.2f virtual mm"
			% (deep_depth * 1000.0)
	)
	assert_almost_eq(
		_player.furrow_half_width_m, 0.17, 0.0001,
		"depth tuning must not narrow the accepted 34 cm channel"
	)


## A walker crossing off a drift onto thin snow must see the furrow taper out and
## die on its own -- no second rule for the edge case. The proof is that the last
## thing drawn before it stops is a shadow of the deepest part, rather than a
## full-strength groove cut off square.
func test_walking_off_a_drift_tapers_the_furrow_out() -> void:
	var samples := _walk(
		10.0, _straight,
		# 0.60 m at the start, 0.30 m at the end: a drift running out into a
		# scoured patch.
		func(along: float) -> float: return lerpf(0.60, 0.30, clampf(along / 10.0, 0.0, 1.0))
	)
	assert_true(samples.size() > 4, "setup: the drift half of the walk must plough")
	var deepest := float(samples[0]["depth"])
	var last := float(samples[samples.size() - 1]["depth"])
	assert_true(
		last < deepest * 0.4,
		"the furrow must thin out before it stops, not be cut off square: %f then %f"
			% [deepest, last]
	)
	assert_true(
		float(samples[samples.size() - 1]["from"].x) < 9.0,
		"the furrow must have died before the walk ended, it reached x = %f"
			% samples[samples.size() - 1]["from"].x
	)


## ---------------------------------------------------------------------------
## The failure that killed the second pass
## ---------------------------------------------------------------------------
## A groove built from one segment per footfall is a polyline BY CONSTRUCTION,
## and every change of direction is a visible hard corner. This is the assertion
## that says the third pass is not that: the walk is a two-metre-radius arc, and
## the angle between consecutive furrow segments is measured in degrees.


func test_a_curved_walk_never_turns_a_hard_corner() -> void:
	var samples := _walk(PI * ARC_RADIUS * 0.5, _arc, _deep)
	assert_true(samples.size() > 20, "setup: a quarter arc must produce many samples")

	var sharpest := 0.0
	var previous := Vector2.ZERO
	for sample in samples:
		var from: Vector3 = sample["from"]
		var to: Vector3 = sample["to"]
		var heading := Vector2(to.x - from.x, to.z - from.z)
		if heading.length_squared() < 1e-9:
			continue
		heading = heading.normalized()
		if previous != Vector2.ZERO:
			sharpest = maxf(sharpest, rad_to_deg(absf(previous.angle_to(heading))))
		previous = heading
	# One segment per footfall on this arc would turn stride_length / ARC_RADIUS
	# at every joint -- 20.6 degrees at the shipped stride. Anything in that
	# region is the rejected version wearing different numbers.
	var footfall_corner := rad_to_deg(_player.stride_length / ARC_RADIUS)
	assert_true(
		sharpest < 5.0,
		"the sharpest corner is %.1f degrees; one segment per footfall would be %.1f"
			% [sharpest, footfall_corner]
	)


## ...and the same claim from the other side: the samples come from the PATH, at
## a spacing far finer than a stride, rather than one per footfall.
func test_the_furrow_is_sampled_from_the_path_and_not_from_the_stride() -> void:
	var walked := 6.0
	var samples := _walk(walked, _straight, _deep)
	var footfalls := walked / _player.stride_length
	assert_true(
		float(samples.size()) > footfalls * 4.0,
		"%d samples over %.1f m is not finer than the %.0f footfalls in it"
			% [samples.size(), walked, footfalls]
	)
	for sample in samples:
		var from: Vector3 = sample["from"]
		var to: Vector3 = sample["to"]
		var length := from.distance_to(to)
		assert_true(
			length <= _player.furrow_sample_m + 0.001,
			"a furrow segment must stay under the sample spacing, got %f m" % length
		)
		# Short relative to the groove's own width is the property that matters:
		# it is what makes the union of the segments the exact swept region of
		# the path rather than a chain of visibly joined capsules.
		assert_true(
			length < float(sample["half_width"]),
			"a segment (%f m) must be shorter than the furrow is wide (%f m)"
				% [length, sample["half_width"]]
		)


## The walk has to be continuous: each sample must start where the last one
## ended, or the furrow is a dashed line.
func test_the_samples_join_end_to_end() -> void:
	var samples := _walk(4.0, _arc, _deep)
	assert_true(samples.size() > 10, "setup: the arc must produce samples")
	for index in range(1, samples.size()):
		var gap: float = samples[index - 1]["to"].distance_to(samples[index]["from"])
		assert_almost_eq(gap, 0.0, 0.0001, "sample %d starts %f m from where the last ended" % [index, gap])


## ---------------------------------------------------------------------------
## Noise along its length
## ---------------------------------------------------------------------------


## An extruded ribbon is the thing to avoid, so depth and width both wander down
## the run. Both halves are asserted: that it varies at all, and that it varies
## SMOOTHLY -- per-sample randomness would satisfy the first and would read as a
## chewed edge rather than as snow.
func test_the_furrow_wobbles_down_its_length() -> void:
	var samples := _walk(12.0, _straight, _deep)
	assert_true(samples.size() > 50, "setup: a twelve-metre walk must produce samples")

	var depth_low := INF
	var depth_high := -INF
	var width_low := INF
	var width_high := -INF
	var roughest := 0.0
	for index in range(samples.size()):
		var depth := float(samples[index]["depth"])
		var width := float(samples[index]["half_width"])
		depth_low = minf(depth_low, depth)
		depth_high = maxf(depth_high, depth)
		width_low = minf(width_low, width)
		width_high = maxf(width_high, width)
		if index > 0:
			roughest = maxf(roughest, absf(depth - float(samples[index - 1]["depth"])))

	assert_true(
		depth_high > depth_low * 1.1,
		"the furrow's depth must wander: %f .. %f" % [depth_low, depth_high]
	)
	assert_true(
		width_high > width_low * 1.1,
		"...and so must its width: %f .. %f" % [width_low, width_high]
	)
	# Smooth: no single 6 cm step may cover more than a fifth of the whole run's
	# swing. Uncorrelated per-sample noise would routinely cover all of it.
	assert_true(
		roughest < (depth_high - depth_low) * 0.2,
		"the wobble must be smooth along the run: one step moved %f of a %f range"
			% [roughest, depth_high - depth_low]
	)


## ---------------------------------------------------------------------------
## What must never happen
## ---------------------------------------------------------------------------


## A respawn, a scene restart or a teleport puts the walker somewhere he did not
## walk to. Joining the two would rule a furrow across untouched snow.
func test_a_jump_across_the_world_rules_no_line() -> void:
	assert_eq(_player.advance_furrow(Vector3.ZERO, 0.58, _max_depth()).size(), 0)
	var jumped := _player.advance_furrow(Vector3(40.0, 0.0, -25.0), 0.58, _max_depth())
	assert_eq(jumped.size(), 0, "a 47 m jump must not be joined up")
	# ...and the walker carries on ploughing from where he landed.
	var after := _player.advance_furrow(Vector3(40.1, 0.0, -25.0), 0.58, _max_depth())
	assert_true(after.size() > 0, "the furrow must resume from the new position")
	assert_almost_eq(after[0]["from"].x, 40.0, 0.001)


func test_standing_still_ploughs_nothing() -> void:
	_player.advance_furrow(Vector3(3.0, 0.0, 3.0), 0.58, _max_depth())
	for _tick in range(120):
		assert_eq(_player.advance_furrow(Vector3(3.0, 0.0, 3.0), 0.58, _max_depth()).size(), 0)


func _mean(samples: Array[Dictionary], key: String) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += float(sample[key])
	return total / float(samples.size())


func _nominal_visual_height_m(snow_depth_m: float) -> float:
	var sample: Dictionary = _player._furrow_sample(
		Vector3.ZERO, Vector3(0.05, 0.0, 0.0), snow_depth_m, _max_depth()
	)
	return float(sample.get("depth", 0.0)) * TRACK_RESPONSE_DEPTH_M
