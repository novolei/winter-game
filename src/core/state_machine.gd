class_name StateMachine
extends RefCounted

## A transition table with a cursor. Knows nothing about what the states
## mean.
##
## The player's walk/run/flounder states and a bear's roam/alert/charge
## states are the same machine holding different data -- which is why
## adding a third threat type needs no new behaviour code.

signal state_changed(from: StringName, to: StringName)

var _valid_states: Array[StringName] = []
var _transitions: Dictionary = {}
var _current: StringName = &""

func configure(states: Array[StringName], transitions: Dictionary, initial: StringName) -> void:
	assert(states.has(initial), "initial state '%s' is not in the configured state list" % initial)
	_valid_states = states.duplicate()
	_transitions = transitions.duplicate(true)
	_current = initial

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
