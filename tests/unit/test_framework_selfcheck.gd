extends TestCase

const TestCaseScript := preload("res://tests/framework/test_case.gd")

func test_assert_eq_records_a_failure_on_mismatch() -> void:
	var probe = TestCaseScript.new()
	probe.assert_eq(1, 2, "probe")
	assert_eq(probe.failures().size(), 1, "a mismatched assert_eq must record exactly one failure")

func test_assert_eq_records_nothing_on_match() -> void:
	var probe = TestCaseScript.new()
	probe.assert_eq(1, 1, "probe")
	assert_true(probe.failures().is_empty(), "a matching assert_eq must record no failure")

func test_assert_true_records_a_failure_when_false() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(false, "probe")
	assert_eq(probe.failures().size(), 1, "assert_true(false) must record one failure")

func test_assert_almost_eq_respects_tolerance() -> void:
	var probe = TestCaseScript.new()
	probe.assert_almost_eq(1.0, 1.00005, 0.001, "within tolerance")
	assert_true(probe.failures().is_empty(), "a difference inside tolerance must not fail")
	probe.assert_almost_eq(1.0, 1.5, 0.001, "outside tolerance")
	assert_eq(probe.failures().size(), 1, "a difference outside tolerance must fail")

func test_reset_failures_clears_the_log() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(false, "probe")
	probe.reset_failures()
	assert_true(probe.failures().is_empty(), "reset_failures must empty the failure list")
