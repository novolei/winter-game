class_name ModifierStack
extends RefCounted

## Holds every Modifier currently affecting one value and folds them into
## a final result.
##
## Evaluation order is fixed:
##     (base + sum of ADD) * product of MULTIPLY
## then any OVERRIDE replaces the result outright; the last one added wins.

var _modifiers: Array[Modifier] = []

## Seconds left for the modifier at the same index; INF means permanent.
## Deliberately parallel to _modifiers rather than a Dictionary keyed by
## Modifier: Godot's ResourceLoader caches .tres files, so two systems
## loading the same modifier resource get the SAME instance. Keying by
## object identity would collapse two independent slots into one expiry
## entry, consuming the duration twice as fast and then stranding the
## remaining slot so it never expires at all.
var _remaining: Array[float] = []

func add(mod: Modifier) -> void:
	_modifiers.append(mod)
	_remaining.append(mod.duration if mod.duration > 0.0 else INF)

func remove_by_source(source_id: StringName) -> int:
	var removed := 0
	for i in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[i].source_id == source_id:
			_modifiers.remove_at(i)
			_remaining.remove_at(i)
			removed += 1
	return removed

func clear() -> void:
	_modifiers.clear()
	_remaining.clear()

func size() -> int:
	return _modifiers.size()

func tick(delta: float) -> void:
	for i in range(_modifiers.size() - 1, -1, -1):
		if is_inf(_remaining[i]):
			continue
		_remaining[i] -= delta
		if _remaining[i] <= 0.0:
			_modifiers.remove_at(i)
			_remaining.remove_at(i)

func apply(base_value: float) -> float:
	var additive := 0.0
	var multiplier := 1.0
	var override_value := NAN
	for mod in _modifiers:
		match mod.operation:
			Modifier.Operation.ADD:
				additive += mod.value
			Modifier.Operation.MULTIPLY:
				multiplier *= mod.value
			Modifier.Operation.OVERRIDE:
				override_value = mod.value
	if not is_nan(override_value):
		return override_value
	return (base_value + additive) * multiplier
