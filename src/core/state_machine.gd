class_name StateMachine
extends RefCounted

## A transition table with a cursor. Knows nothing about what the states
## mean.
##
## Callers configure it with their own state names and transition data, so
## two entities with completely different behaviour share this one file and
## differ only in the data they pass to configure().

signal state_changed(from: StringName, to: StringName)

var _valid_states: Array[StringName] = []
var _transitions: Dictionary = {}
var _current: StringName = &""

func configure(states: Array[StringName], transitions: Dictionary, initial: StringName) -> bool:
	if not states.has(initial):
		return false
	_valid_states = states.duplicate()
	_transitions = transitions.duplicate(true)
	_current = initial
	return true

func current() -> StringName:
	return _current

func can_transition_to(target: StringName) -> bool:
	if not _valid_states.has(target):
		return false
	if not _transitions.has(_current):
		return false
	return (_transitions[_current] as Array).has(target)

func transition_to(target: StringName) -> bool:
	if not can_transition_to(target):
		return false
	var previous := _current
	_current = target
	state_changed.emit(previous, target)
	return true
