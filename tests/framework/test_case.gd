class_name TestCase
extends RefCounted

## Base class for all WinterTime tests.
## Subclass it, name the file test_*.gd, and name test methods test_*.
## Assertions record failures rather than halting, so one test reports
## every problem it finds instead of only the first.

var _failures: Array[String] = []

func before_each() -> void:
	pass

func after_each() -> void:
	pass

func failures() -> Array[String]:
	return _failures

func reset_failures() -> void:
	_failures.clear()

func _fail(message: String) -> void:
	_failures.append(message)

func assert_true(value: bool, message := "") -> void:
	if not value:
		_fail("assert_true failed. %s" % message)

func assert_false(value: bool, message := "") -> void:
	if value:
		_fail("assert_false failed. %s" % message)

func assert_eq(actual, expected, message := "") -> void:
	if actual != expected:
		_fail("assert_eq failed: expected <%s>, got <%s>. %s" % [expected, actual, message])

func assert_almost_eq(actual: float, expected: float, tolerance := 0.0001, message := "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("assert_almost_eq failed: expected <%f> +/- <%f>, got <%f>. %s" % [expected, tolerance, actual, message])

func assert_not_null(value, message := "") -> void:
	if value == null:
		_fail("assert_not_null failed. %s" % message)
