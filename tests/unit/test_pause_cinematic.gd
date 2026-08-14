extends TestCase

## The pause camera's non-linear motion -- the EXPO OUT arrival, the QUAD IN
## return, and the bounded two-sine drift, all driven by pure functions so no
## frame has to pass for the curve to be checked.

const CinematicScript := preload("res://src/ui/pause_cinematic.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _cinematic: PauseCinematic = null


func before_each() -> void:
	_cinematic = CinematicScript.new()
	_cinematic.configure(Tokens)


func test_the_push_lands_exactly_on_both_endpoints() -> void:
	assert_eq(PauseCinematic.push_ease(0.0), 0.0,
		"the push must start from the authored gameplay framing, exactly")
	assert_eq(PauseCinematic.push_ease(1.0), 1.0,
		"the push must land on the authored tableau, exactly")


func test_the_push_is_strongly_non_linear() -> void:
	# EXPO OUT: the midpoint of the TIME is past 99% of the TRAVEL. A linear
	# drive reads as a UI zoom; this reads as detach, glide, hover.
	var mid := PauseCinematic.push_ease(0.5)
	assert_true(mid > 0.9 and mid < 1.0,
		"push midpoint %f is not the aerial glide the shot calls for" % mid)
	assert_true(PauseCinematic.push_ease(0.2) > 0.7,
		"the detachment should carry most of the travel early")


func test_the_push_never_goes_backward() -> void:
	var previous := PauseCinematic.push_ease(0.0)
	for i in range(1, 65):
		var current := PauseCinematic.push_ease(float(i) / 64.0)
		assert_true(current >= previous,
			"the push eased backwards at step %d" % i)
		previous = current


func test_the_return_accelerates_away() -> void:
	assert_eq(PauseCinematic.return_ease(0.0), 0.0)
	assert_eq(PauseCinematic.return_ease(1.0), 1.0)
	assert_almost_eq(PauseCinematic.return_ease(0.5), 0.25, 0.0001,
		"QUAD IN: half the time should carry only a quarter of the travel")


func test_the_push_is_slower_than_the_cascade_and_the_return_is_quick() -> void:
	# Content settles first, the lens keeps gliding; leaving is quicker than
	# arriving, the way a cutaway returns on action.
	assert_true(_cinematic.push_seconds > Tokens.bloom_seconds * 2.0,
		"the camera must outlast the type cascade, not end with it")
	assert_true(_cinematic.return_seconds < _cinematic.push_seconds)


func test_the_drift_stays_inside_its_amplitude() -> void:
	for i in range(200):
		var elapsed := float(i) * 0.83
		assert_true(absf(_cinematic.drift_frame(elapsed))
				<= _cinematic.drift_frame_amplitude + 0.00001,
			"the dolly drift escaped its amplitude at %fs" % elapsed)
		assert_true(absf(_cinematic.drift_yaw(elapsed))
				<= _cinematic.drift_yaw_radians + 0.00001,
			"the yaw drift escaped its amplitude at %fs" % elapsed)


func test_the_drift_is_periodic_and_starts_from_zero() -> void:
	assert_almost_eq(_cinematic.drift_frame(0.0), 0.0, 0.000001,
		"the drift must not snap the frame when the push begins")
	assert_almost_eq(
		_cinematic.drift_frame(_cinematic.drift_frame_seconds),
		_cinematic.drift_frame(0.0), 0.000001, "the dolly drift is not periodic")
	assert_almost_eq(
		_cinematic.drift_yaw(_cinematic.drift_yaw_seconds),
		_cinematic.drift_yaw(0.0), 0.000001, "the yaw drift is not periodic")


func test_the_drift_is_quiet_enough_to_not_nauseate() -> void:
	# Design spec section 2.5: a moving camera is what would nauseate. The
	# living frame is a breath, not a move -- cap the travel in one second.
	var peak_speed := _cinematic.drift_frame_amplitude * TAU / _cinematic.drift_frame_seconds
	assert_true(peak_speed < 0.005,
		"the dolly drift moves %f of the frame per second -- too fast" % peak_speed)
