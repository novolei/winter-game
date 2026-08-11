extends TestCase

const StateMachineScript := preload("res://src/core/state_machine.gd")

var _observed_from: StringName = &""
var _observed_to: StringName = &""
var _change_count := 0

func before_each() -> void:
	_observed_from = &""
	_observed_to = &""
	_change_count = 0

func _on_state_changed(from: StringName, to: StringName) -> void:
	_observed_from = from
	_observed_to = to
	_change_count += 1

func _build():
	var machine = StateMachineScript.new()
	machine.configure(
		[&"walking", &"running", &"floundering"] as Array[StringName],
		{
			&"walking": [&"running", &"floundering"] as Array[StringName],
			&"running": [&"walking"] as Array[StringName],
			&"floundering": [&"walking"] as Array[StringName],
		},
		&"walking"
	)
	return machine

func test_configure_sets_the_initial_state() -> void:
	var machine = _build()
	assert_eq(machine.current(), &"walking", "initial state should be walking")

func test_configure_rejects_an_initial_state_not_in_the_list() -> void:
	var machine = StateMachineScript.new()
	var ok: bool = machine.configure(
		[&"walking"] as Array[StringName],
		{&"walking": [] as Array[StringName]},
		&"swimming"
	)
	assert_false(ok, "configure must reject an initial state that is not in the state list")
	assert_eq(machine.current(), &"", "a rejected configure must leave the machine unconfigured, not half-set")
	assert_false(machine.can_transition_to(&"walking"), "an unconfigured machine must reject every transition")

## The transition table is the half of configure() that Wave 2 and Wave 5 will
## feed from .tres. A key naming a state that does not exist is a graph the
## machine can never leave by that route, and it fails silently -- which is
## exactly what configure()'s bool return exists to stop one level up.
func test_configure_rejects_a_transition_key_not_in_the_state_list() -> void:
	var machine = StateMachineScript.new()
	var ok: bool = machine.configure(
		[&"walking", &"running"] as Array[StringName],
		{
			&"walking": [&"running"] as Array[StringName],
			&"swimming": [&"walking"] as Array[StringName],
		},
		&"walking"
	)
	assert_false(ok, "configure must reject a transition key that is not a declared state")
	assert_eq(machine.current(), &"", "a rejected configure must leave the machine unconfigured, not half-set")
	assert_false(machine.can_transition_to(&"running"), "an unconfigured machine must reject every transition")

func test_configure_rejects_a_transition_target_not_in_the_state_list() -> void:
	var machine = StateMachineScript.new()
	var ok: bool = machine.configure(
		[&"walking", &"running"] as Array[StringName],
		{
			&"walking": [&"running", &"swimming"] as Array[StringName],
			&"running": [&"walking"] as Array[StringName],
		},
		&"walking"
	)
	assert_false(ok, "configure must reject a transition target that is not a declared state")
	assert_eq(machine.current(), &"", "a rejected configure must leave the machine unconfigured, not half-set")
	assert_false(machine.can_transition_to(&"running"), "an unconfigured machine must reject every transition")

## configure() deep-copies the transition table. Without that, every entity
## configured from one shared dictionary -- the normal case once graphs come
## from a cached .tres, see briefing trap 6 -- would share one graph, and
## mutating one machine's transitions would silently rewrite the others'.
## Swapping duplicate(true) for duplicate() copies the outer dictionary but
## leaves the inner Arrays aliased, which nothing else here would notice.
func test_configure_deep_copies_the_transition_table() -> void:
	var transitions := {
		&"walking": [&"running", &"floundering"] as Array[StringName],
		&"running": [&"walking"] as Array[StringName],
		&"floundering": [&"walking"] as Array[StringName],
	}
	var machine = StateMachineScript.new()
	machine.configure(
		[&"walking", &"running", &"floundering"] as Array[StringName],
		transitions,
		&"walking"
	)
	# Mutate the arrays INSIDE the caller's dictionary, both directions:
	# grant a transition the machine must not gain, and revoke one it must
	# not lose. A shallow copy shares these arrays and would follow both.
	(transitions[&"running"] as Array).append(&"floundering")
	(transitions[&"walking"] as Array).erase(&"running")
	assert_true(machine.can_transition_to(&"running"), "revoking a target in the caller's array must not revoke it in the machine")
	machine.transition_to(&"running")
	assert_eq(machine.current(), &"running", "the transition the caller revoked must still work")
	assert_false(machine.can_transition_to(&"floundering"), "granting a target in the caller's array must not grant it in the machine")

func test_legal_transition_succeeds() -> void:
	var machine = _build()
	var ok: bool = machine.transition_to(&"running")
	assert_true(ok, "walking -> running is declared legal")
	assert_eq(machine.current(), &"running", "state should now be running")

func test_legal_transition_emits_signal() -> void:
	var machine = _build()
	machine.state_changed.connect(_on_state_changed)
	machine.transition_to(&"running")
	assert_eq(_change_count, 1, "one transition should emit one signal")
	assert_eq(_observed_from, &"walking", "signal should report the previous state")
	assert_eq(_observed_to, &"running", "signal should report the new state")

func test_illegal_transition_is_rejected() -> void:
	var machine = _build()
	machine.transition_to(&"running")
	var ok: bool = machine.transition_to(&"floundering")
	assert_false(ok, "running -> floundering is not declared, so it must be rejected")
	assert_eq(machine.current(), &"running", "a rejected transition must not change state")

func test_illegal_transition_emits_nothing() -> void:
	var machine = _build()
	machine.transition_to(&"running")
	machine.state_changed.connect(_on_state_changed)
	machine.transition_to(&"floundering")
	assert_eq(_change_count, 0, "a rejected transition must not emit state_changed")

func test_unknown_target_is_rejected() -> void:
	var machine = _build()
	var ok: bool = machine.transition_to(&"swimming")
	assert_false(ok, "a state not in the configured list must be rejected")
	assert_eq(machine.current(), &"walking", "state must be unchanged")

func test_can_transition_to_reports_without_mutating() -> void:
	var machine = _build()
	assert_true(machine.can_transition_to(&"running"), "walking -> running should be reported legal")
	assert_false(machine.can_transition_to(&"swimming"), "unknown state should be reported illegal")
	assert_eq(machine.current(), &"walking", "can_transition_to must not change state")
