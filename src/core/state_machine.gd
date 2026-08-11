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

## Returns false and changes nothing if the graph is not internally
## consistent: the initial state must be declared, and so must every
## transition key and every target in every transition list. An undeclared
## name is not a harmless no-op -- can_transition_to() rejects it, so the
## route simply never fires, and a machine that can never leave a state looks
## identical to one that is merely idle. Validating here is what makes the
## bool return worth checking once graphs arrive as data rather than as
## literals a human proof-read.
func configure(states: Array[StringName], transitions: Dictionary, initial: StringName) -> bool:
	if not states.has(initial):
		return false
	for key in transitions:
		if not states.has(key):
			return false
		for target in (transitions[key] as Array):
			if not states.has(target):
				return false
	_valid_states = states.duplicate()
	# Deep, not shallow: a shallow copy leaves the inner target Arrays aliased
	# to the caller's, so two entities configured from one dictionary -- the
	# normal case for a graph loaded from a cached .tres, see trap 6 -- would
	# share one mutable graph.
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
