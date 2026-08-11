class_name TestCase
extends RefCounted

## Base class for all WinterTime tests.
## Subclass it, name the file test_*.gd, and name test methods test_*.
## Assertions record failures rather than halting, so one test reports
## every problem it finds instead of only the first.
##
## Every assert_* call also bumps an assertion counter, whether it passes
## or fails. The counter measures execution, not outcome: a GDScript
## runtime error aborts the rest of the method and returns silently, so a
## test killed mid-flight records zero failures and would otherwise be
## reported as a PASS. test_runner.gd turns a zero count into a failure.

var _failures: Array[String] = []
var _assertions := 0

func before_each() -> void:
	pass

func after_each() -> void:
	pass

func failures() -> Array[String]:
	return _failures

## How many assert_* calls this instance executed, passing or failing.
func assertion_count() -> int:
	return _assertions

## Clears every piece of per-test state: the failure log and the
## assertion counter. The runner calls it before each test method.
func reset_failures() -> void:
	_failures.clear()
	_assertions = 0

func _fail(message: String) -> void:
	_failures.append(message)

func assert_true(value: bool, message := "") -> void:
	_assertions += 1
	if not value:
		_fail("assert_true failed. %s" % message)

func assert_false(value: bool, message := "") -> void:
	_assertions += 1
	if value:
		_fail("assert_false failed. %s" % message)

func assert_eq(actual, expected, message := "") -> void:
	_assertions += 1
	if actual != expected:
		_fail("assert_eq failed: expected <%s>, got <%s>. %s" % [expected, actual, message])

func assert_almost_eq(actual: float, expected: float, tolerance := 0.0001, message := "") -> void:
	_assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("assert_almost_eq failed: expected <%f> +/- <%f>, got <%f>. %s" % [expected, tolerance, actual, message])

func assert_not_null(value, message := "") -> void:
	_assertions += 1
	if value == null:
		_fail("assert_not_null failed. %s" % message)
