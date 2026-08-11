class_name ModifierStack
extends RefCounted

## Holds every Modifier currently affecting one value and folds them into
## a final result.
##
## Evaluation order is fixed:
##     (base + sum of ADD) * product of MULTIPLY
## then any OVERRIDE replaces the result outright; the last one added wins.

var _modifiers: Array[Modifier] = []
var _remaining: Dictionary = {}

func add(mod: Modifier) -> void:
	_modifiers.append(mod)
	if mod.duration > 0.0:
		_remaining[mod] = mod.duration

func remove_by_source(source_id: StringName) -> int:
	var removed := 0
	for i in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[i].source_id == source_id:
			_remaining.erase(_modifiers[i])
			_modifiers.remove_at(i)
			removed += 1
	return removed

func clear() -> void:
	_modifiers.clear()
	_remaining.clear()

func size() -> int:
	return _modifiers.size()

func tick(delta: float) -> void:
	for i in range(_modifiers.size() - 1, -1, -1):
		var mod := _modifiers[i]
		if not _remaining.has(mod):
			continue
		var left: float = float(_remaining[mod]) - delta
		if left <= 0.0:
			_remaining.erase(mod)
			_modifiers.remove_at(i)
		else:
			_remaining[mod] = left

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
