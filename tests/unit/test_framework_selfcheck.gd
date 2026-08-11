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

## The assertion counter exists so the runner can fail a test that ran no
## assertion at all -- the signature of a method aborted by a runtime
## error, which records no failure and would otherwise be printed as PASS.
## It therefore has to count executions, not successes.

func test_assertion_count_counts_a_passing_assertion() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(true, "probe")
	assert_eq(probe.assertion_count(), 1, "a passing assertion must still be counted")

func test_assertion_count_counts_a_failing_assertion() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(false, "probe")
	assert_eq(probe.assertion_count(), 1, "the counter must track execution, not outcome")

func test_assertion_count_sums_every_assertion_kind() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(true, "probe")
	probe.assert_false(false, "probe")
	probe.assert_eq(1, 1, "probe")
	probe.assert_almost_eq(1.0, 1.0, 0.001, "probe")
	probe.assert_not_null(probe, "probe")
	assert_eq(probe.assertion_count(), 5, "every assert_* method must increment the counter")

func test_reset_failures_zeroes_the_assertion_count() -> void:
	var probe = TestCaseScript.new()
	probe.assert_true(false, "probe")
	assert_eq(probe.assertion_count(), 1, "the probe must have counted its one assertion first")
	probe.reset_failures()
	assert_true(probe.failures().is_empty(), "reset_failures must empty the failure list")
	assert_eq(probe.assertion_count(), 0, "reset_failures must also zero the assertion counter")
