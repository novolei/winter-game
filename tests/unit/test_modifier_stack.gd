extends TestCase

const ModifierScript := preload("res://src/core/modifier.gd")
const ModifierStackScript := preload("res://src/core/modifier_stack.gd")

func _make(source: StringName, op: int, value: float, duration := -1.0):
	var mod = ModifierScript.new()
	mod.source_id = source
	mod.operation = op
	mod.value = value
	mod.duration = duration
	return mod

func test_empty_stack_returns_base_unchanged() -> void:
	var stack = ModifierStackScript.new()
	assert_almost_eq(stack.apply(10.0), 10.0, 0.0001, "an empty stack must not alter the base value")

func test_add_operations_sum() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.ADD, 3.0))
	stack.add(_make(&"b", ModifierScript.Operation.ADD, 2.0))
	assert_almost_eq(stack.apply(10.0), 15.0, 0.0001, "10 + 3 + 2 = 15")

func test_multiply_applies_after_add() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.ADD, 10.0))
	stack.add(_make(&"b", ModifierScript.Operation.MULTIPLY, 2.0))
	assert_almost_eq(stack.apply(10.0), 40.0, 0.0001, "(10 + 10) * 2 = 40, not 10 + (10 * 2)")

func test_multiply_operations_compound() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.MULTIPLY, 2.0))
	stack.add(_make(&"b", ModifierScript.Operation.MULTIPLY, 1.5))
	assert_almost_eq(stack.apply(10.0), 30.0, 0.0001, "10 * 2 * 1.5 = 30")

func test_override_replaces_everything() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.ADD, 100.0))
	stack.add(_make(&"b", ModifierScript.Operation.MULTIPLY, 9.0))
	stack.add(_make(&"c", ModifierScript.Operation.OVERRIDE, 5.0))
	assert_almost_eq(stack.apply(10.0), 5.0, 0.0001, "OVERRIDE must discard adds and multiplies")

func test_last_override_wins() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.OVERRIDE, 5.0))
	stack.add(_make(&"b", ModifierScript.Operation.OVERRIDE, 7.0))
	assert_almost_eq(stack.apply(10.0), 7.0, 0.0001, "the most recently added OVERRIDE wins")

func test_remove_by_source_drops_all_matching() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"hunger", ModifierScript.Operation.ADD, 1.0))
	stack.add(_make(&"hunger", ModifierScript.Operation.ADD, 2.0))
	stack.add(_make(&"wind", ModifierScript.Operation.ADD, 4.0))
	var removed: int = stack.remove_by_source(&"hunger")
	assert_eq(removed, 2, "both hunger modifiers should be removed")
	assert_almost_eq(stack.apply(0.0), 4.0, 0.0001, "only the wind modifier should remain")

func test_timed_modifier_expires() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"gust", ModifierScript.Operation.ADD, 5.0, 2.0))
	stack.tick(1.0)
	assert_almost_eq(stack.apply(0.0), 5.0, 0.0001, "modifier should still apply before expiry")
	stack.tick(1.5)
	assert_almost_eq(stack.apply(0.0), 0.0, 0.0001, "modifier should be gone after its duration elapses")
	assert_eq(stack.size(), 0, "expired modifier should be removed from the stack")

func test_permanent_modifier_survives_ticks() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"coat", ModifierScript.Operation.ADD, 5.0, -1.0))
	stack.tick(1000.0)
	assert_almost_eq(stack.apply(0.0), 5.0, 0.0001, "duration -1 means permanent until removed by source")

func test_clear_empties_the_stack() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"a", ModifierScript.Operation.ADD, 1.0))
	stack.clear()
	assert_eq(stack.size(), 0, "clear must empty the stack")
	assert_almost_eq(stack.apply(10.0), 10.0, 0.0001, "a cleared stack must not alter the base value")
