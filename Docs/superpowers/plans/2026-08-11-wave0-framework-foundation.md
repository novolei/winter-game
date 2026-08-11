# Wave 0 — Framework Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the test harness, the game-agnostic core framework (EventBus, Modifier/ModifierStack, StateMachine, ServiceRegistry), the nine Resource definition classes, three art-verification tests, and the world clock — so that every later wave has a test cycle and a data-driven substrate to build on.

**Architecture:** `src/core/` contains code that does not know this game exists — it could be copied to another project unchanged. `src/definitions/` declares the *shape* of all content as `Resource` classes; actual content lives in `data/*.tres`. `src/systems/` holds autoload singletons that own global state and communicate only through `EventBus`. Tests run headless via a custom `SceneTree` runner.

**Tech Stack:** Godot 4.7.1 (Forward+, Jolt Physics, D3D12), GDScript. No addons — the test runner is ~120 lines of first-party code, avoiding third-party addon compatibility risk against a just-released 4.7.

## Global Constraints

- **Engine binary:** `D:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe` — always the `_console` variant from a shell, or `print()` output and stack traces are lost.
- **Project path:** `D:\Godot resource\winter-time` (contains a space — always quote it).
- **Filenames:** English `snake_case` only. Polish names from the source video (`zima`, `dolina`, `drogi`, `drzewa`, `kamera`, `wrog`, `niedzwiedz`, `opal`, `bron`) are deprecated.
- **Autoloads are NOT available under `--script`.** Verified empirically. Tests must instantiate scripts directly via `preload(...).new()`, never via autoload globals.
- **No hardcoded colors.** All color values come from `data/palette/color_bible.tres`.
- **Zero direct references between systems.** Cross-system communication goes through `EventBus` only.
- **12-color palette** (authoritative): snow `#8FB0D8 #7FA0C9 #748FBB #6987B4 #5D7BA6`; structure `#33496E #2A3854 #1C2A45 #131C30`; warm `#6E2F2E #A05A35 #FFB257`.
- **Triangle budgets:** buildings ≤ 500, props ≤ 200, vegetation ≤ 300, characters ≈ 8000.
- **Banned material features:** normal maps, roughness/metallic maps, environment/screen-space reflections, specular highlights, color gradients.
- **Free every `Node` a test allocates.** `Node` is not reference-counted. An un-freed instance produces `WARNING: N ObjectDB instances were leaked at exit` and `ERROR: N resources still in use at exit`, which violates the pristine-output rule above. `RefCounted` subclasses — including `Resource`, `TestCase`, and `ModifierStack` — clean themselves up and need no `free()`. In this wave the Node-derived scripts are `EventBus`, `ServiceRegistry`, and `WorldClock`; anything instantiated from those in a test must be freed, either at the end of the test or in `after_each()`.
- **Test output must be pristine.** No `SCRIPT ERROR`, no `WARNING`, no `ERROR` — only the runner's own lines.
- **Commit after every task.** Never skip hooks or bypass signing.

## Deviations from the spec (deliberate, with reasoning)

1. **System Map task 1 ("core abstraction layer") is split into four plan tasks** (2–5 below). Each of EventBus, ModifierStack, StateMachine, and ServiceRegistry carries its own test cycle and a reviewer could reject one while approving another — the spec's granularity was too coarse to execute.
2. **The warmth-budget art test is deferred to Wave 3.** It requires a rendered frame, which requires lighting and a real scene — neither exists in Wave 0. Implementing it now would mean a test that passes vacuously, which reads as "verified" when nothing was checked. The other three art tests (palette, topology, shading features) are static analysis and land here in full. **Wave 3's plan must open with the warmth-budget test.**
3. **`src/core/definition_loader.gd` is deferred to Wave 1.** The System Map's folder tree lists it, but nothing in Wave 0 needs it: `WorldClock` receives its schedules through `load_schedules()` rather than reading the disk. Its first real consumer appears in Wave 1, where several systems need "load every `.tres` under this folder" — building it once there beats building it speculatively here. **Wave 1's plan must include it.**
4. **Content `.tres` files are generated, never hand-authored.** Typed-array properties (`Array[Color]`, `Array[StringName]`) have serialization syntax that is easy to get subtly wrong by hand and tedious to debug. Generators live in `tools/` and stay in version control.

---

### Task 1: Test harness

**Files:**
- Create: `tests/framework/test_case.gd`
- Create: `tests/framework/test_runner.gd`
- Create: `tests/unit/test_framework_selfcheck.gd`

**Interfaces:**
- Consumes: nothing (this is the root task).
- Produces: `TestCase` base class with `assert_true(value: bool, message := "")`, `assert_false(value: bool, message := "")`, `assert_eq(actual, expected, message := "")`, `assert_almost_eq(actual: float, expected: float, tolerance := 0.0001, message := "")`, `assert_not_null(value, message := "")`, `failures() -> Array[String]`, `reset_failures() -> void`, `before_each() -> void`, `after_each() -> void`. Every later test file in the project extends `TestCase` and is discovered by filename prefix `test_`.

- [ ] **Step 1: Write the TestCase base class**

Create `tests/framework/test_case.gd`:

```gdscript
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
```

- [ ] **Step 2: Write the runner**

Create `tests/framework/test_runner.gd`:

```gdscript
extends SceneTree

## Headless test runner.
## Run: godot --headless --path <project> --script res://tests/framework/test_runner.gd
## Exits 0 when everything passes, 1 when anything fails.
##
## NOTE: autoloads are NOT instantiated under --script. Tests must build
## their subjects directly with preload(...).new().

const TEST_ROOTS: Array[String] = ["res://tests/unit", "res://tests/art"]

var _passed := 0
var _failed := 0
var _failure_log: PackedStringArray = []

func _initialize() -> void:
	print("")
	print("WinterTime test run")
	print("=".repeat(60))
	for root in TEST_ROOTS:
		for path in _find_test_scripts(root):
			_run_file(path)
	_print_report()
	quit(1 if _failed > 0 else 0)

func _find_test_scripts(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_test_scripts(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failed += 1
		_failure_log.append("  %s :: <load> -- could not load script" % path)
		return
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("test_"):
			continue
		var instance = script.new()
		instance.reset_failures()
		instance.before_each()
		instance.call(method_name)
		instance.after_each()
		var fails: Array[String] = instance.failures()
		if fails.is_empty():
			_passed += 1
			print("  PASS  %s :: %s" % [path.get_file(), method_name])
		else:
			_failed += 1
			print("  FAIL  %s :: %s" % [path.get_file(), method_name])
			for f in fails:
				_failure_log.append("  %s :: %s -- %s" % [path.get_file(), method_name, f])

func _print_report() -> void:
	print("=".repeat(60))
	if not _failure_log.is_empty():
		print("FAILURES:")
		for line in _failure_log:
			print(line)
		print("")
	print("%d passed, %d failed" % [_passed, _failed])
	print("")
```

- [ ] **Step 3: Write the self-check test**

The harness has a bootstrapping problem: it cannot be tested by a framework that does not exist yet. Solve it by having the harness test *itself* — a probe `TestCase` is driven through a deliberate mismatch and its recorded failure is asserted on.

Create `tests/unit/test_framework_selfcheck.gd`:

```gdscript
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
```

- [ ] **Step 4: Run the suite and verify it passes**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: `8 passed, 0 failed`, exit code 0.

- [ ] **Step 5: Prove the runner actually reports failures**

A green suite proves nothing if the runner cannot go red. Append this method to `tests/unit/test_framework_selfcheck.gd`:

```gdscript
func test_deliberate_failure_placeholder() -> void:
	assert_true(false, "THIS MUST FAIL -- delete this method after verifying")
```

Run the command from Step 4 again.

Expected: `8 passed, 1 failed`, the FAILURES block names `test_deliberate_failure_placeholder`, and **exit code 1**. Confirm the exit code:

```bash
echo $?
```

- [ ] **Step 6: Remove the deliberate failure and confirm green**

Delete `test_deliberate_failure_placeholder` from `tests/unit/test_framework_selfcheck.gd`. Run Step 4's command again.

Expected: `8 passed, 0 failed`, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add tests/ && git commit -m "test: add headless test harness with self-check"
```

---

### Task 2: EventBus

**Files:**
- Create: `src/core/event_bus.gd`
- Create: `tests/unit/test_event_bus.gd`
- Modify: `project.godot` (add autoload)

**Interfaces:**
- Consumes: `TestCase` from Task 1.
- Produces: autoload `EventBus` with `subscribe(event: StringName, callback: Callable) -> void`, `unsubscribe(event: StringName, callback: Callable) -> void`, `emit_event(event: StringName, payload: Variant = null) -> void`, `subscriber_count(event: StringName) -> int`, `clear() -> void`. Every system in every later wave uses these four methods and never holds a reference to another system.

> **Naming note:** the spec sketched `EventBus.emit(...)`. The implementation uses `emit_event(...)` because `Node` already carries `emit_signal`, and a bare `emit` invites confusion with Godot's signal API.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_event_bus.gd`:

```gdscript
extends TestCase

const EventBusScript := preload("res://src/core/event_bus.gd")

class Probe extends Node:
	var payloads: Array = []
	func on_event(payload) -> void:
		payloads.append(payload)

func test_subscriber_receives_payload() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 42)
	assert_eq(probe.payloads.size(), 1, "subscriber should be called once")
	assert_eq(probe.payloads[0], 42, "payload should arrive intact")
	probe.free()

func test_unsubscribe_stops_delivery() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.unsubscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_true(probe.payloads.is_empty(), "unsubscribed callback must not be called")
	probe.free()

func test_emitting_with_no_subscribers_is_safe() -> void:
	var bus = EventBusScript.new()
	bus.emit_event(&"nobody.listening", 1)
	assert_eq(bus.subscriber_count(&"nobody.listening"), 0, "unknown event should report zero subscribers")

func test_duplicate_subscribe_delivers_once() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_eq(probe.payloads.size(), 1, "subscribing twice must not double-deliver")
	probe.free()

func test_freed_subscriber_is_pruned() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	probe.free()
	bus.emit_event(&"test.event", 1)
	assert_eq(bus.subscriber_count(&"test.event"), 0, "a callback on a freed object must be pruned, not crash")

func test_clear_removes_every_subscription() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"a", probe.on_event)
	bus.subscribe(&"b", probe.on_event)
	bus.clear()
	assert_eq(bus.subscriber_count(&"a"), 0, "clear must drop subscriptions for a")
	assert_eq(bus.subscriber_count(&"b"), 0, "clear must drop subscriptions for b")
	probe.free()
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — the `preload` of `res://src/core/event_bus.gd` cannot resolve because the file does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/core/event_bus.gd`:

```gdscript
extends Node

## Global publish/subscribe hub. Registered as autoload "EventBus".
##
## Systems never hold references to one another; they publish and subscribe
## here. Deleting any one system must leave the others compiling and passing
## their tests -- that property is what this class exists to protect.

var _subscribers: Dictionary = {}

func subscribe(event: StringName, callback: Callable) -> void:
	if not _subscribers.has(event):
		_subscribers[event] = []
	var list: Array = _subscribers[event]
	if not list.has(callback):
		list.append(callback)

func unsubscribe(event: StringName, callback: Callable) -> void:
	if not _subscribers.has(event):
		return
	var list: Array = _subscribers[event]
	list.erase(callback)
	if list.is_empty():
		_subscribers.erase(event)

func emit_event(event: StringName, payload: Variant = null) -> void:
	if not _subscribers.has(event):
		return
	# Iterate a copy: a callback may subscribe or unsubscribe during dispatch.
	var list: Array = (_subscribers[event] as Array).duplicate()
	for entry in list:
		var callback := entry as Callable
		if not callback.is_valid():
			unsubscribe(event, callback)
			continue
		callback.call(payload)

func subscriber_count(event: StringName) -> int:
	if not _subscribers.has(event):
		return 0
	return (_subscribers[event] as Array).size()

func clear() -> void:
	_subscribers.clear()
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command.

Expected: `15 passed, 0 failed` (5 from the harness self-check + 6 here).

- [ ] **Step 5: Register the autoload**

Add to `project.godot`, creating the `[autoload]` section if absent:

```ini
[autoload]

EventBus="*res://src/core/event_bus.gd"
```

The `*` prefix makes it a singleton Node. Verify the project still opens cleanly:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --quit
```

Expected: no errors about a missing or invalid autoload.

- [ ] **Step 6: Commit**

```bash
git add src/core/event_bus.gd tests/unit/test_event_bus.gd project.godot && git commit -m "feat: add EventBus for decoupled system communication"
```

---

### Task 3: Modifier and ModifierStack

**Files:**
- Create: `src/core/modifier.gd`
- Create: `src/core/modifier_stack.gd`
- Create: `tests/unit/test_modifier_stack.gd`

**Interfaces:**
- Consumes: `TestCase` from Task 1.
- Produces: `Modifier` (Resource) with `enum Operation { ADD, MULTIPLY, OVERRIDE }` and exported `source_id: StringName`, `operation: Operation`, `value: float`, `duration: float`. `ModifierStack` (RefCounted) with `add(mod: Modifier) -> void`, `remove_by_source(source_id: StringName) -> int`, `clear() -> void`, `size() -> int`, `tick(delta: float) -> void`, `apply(base_value: float) -> float`. `SurvivalSystem` in Wave 2 and `WeatherSystem` in Wave 3 both push modifiers through this stack.

**Evaluation order is fixed and load-bearing:** `(base + sum of ADD) * product of MULTIPLY`, then any `OVERRIDE` replaces the result outright. Last `OVERRIDE` added wins.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_modifier_stack.gd`:

```gdscript
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

func test_the_same_instance_added_twice_expires_per_slot() -> void:
	var stack = ModifierStackScript.new()
	var shared = _make(&"cold_snap", ModifierScript.Operation.ADD, 5.0, 2.0)
	stack.add(shared)
	stack.add(shared)
	assert_almost_eq(stack.apply(0.0), 10.0, 0.0001, "both slots should contribute")
	stack.tick(1.0)
	assert_eq(stack.size(), 2, "one second into a two-second duration, neither slot has expired")
	assert_almost_eq(stack.apply(0.0), 10.0, 0.0001, "both slots should still contribute")
	stack.tick(1.5)
	assert_eq(stack.size(), 0, "both slots expire once their full duration elapses")
	assert_almost_eq(stack.apply(0.0), 0.0, 0.0001, "nothing contributes after expiry")

func test_modifier_expires_exactly_at_its_duration() -> void:
	var stack = ModifierStackScript.new()
	stack.add(_make(&"gust", ModifierScript.Operation.ADD, 5.0, 2.0))
	stack.tick(2.0)
	assert_eq(stack.size(), 0, "remaining hitting exactly zero must expire")
```

> **Why `test_the_same_instance_added_twice_expires_per_slot` exists.** Godot's `ResourceLoader` caches `.tres` files, so two systems that each load the same modifier resource receive the **same instance**. An earlier design kept remaining times in a `Dictionary` keyed by the `Modifier` object, which collapsed two independent slots into one entry — consuming the duration twice as fast, then stranding the survivor so it never expired at all. Both callers were correct and the result was still wrong. This test is the regression guard.

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — `res://src/core/modifier.gd` does not exist.

- [ ] **Step 3: Write Modifier**

Create `src/core/modifier.gd`:

```gdscript
class_name Modifier
extends Resource

## One adjustment to one numeric value, from one identified source.
##
## This is the unit that makes the survival model data-driven: "low hunger
## makes body heat drain faster" is a Modifier stored in a .tres file, not
## a branch in GDScript.

enum Operation { ADD, MULTIPLY, OVERRIDE }

## Who applied this. Used to remove it again precisely.
@export var source_id: StringName = &""

@export var operation: Operation = Operation.ADD

@export var value: float = 0.0

## Seconds until this expires. Any value <= 0 means permanent until removed
## by source; -1 is the conventional way to write it.
@export var duration: float = -1.0
```

- [ ] **Step 4: Write ModifierStack**

Create `src/core/modifier_stack.gd`:

```gdscript
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
## survivor so it never expires at all.
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run the Step 2 command.

Expected: `27 passed, 0 failed` (5 harness + 6 EventBus + 10 here).

- [ ] **Step 6: Commit**

```bash
git add src/core/modifier.gd src/core/modifier_stack.gd tests/unit/test_modifier_stack.gd && git commit -m "feat: add Modifier and ModifierStack for data-driven stat effects"
```

---

### Task 4: StateMachine

**Files:**
- Create: `src/core/state_machine.gd`
- Create: `tests/unit/test_state_machine.gd`

**Interfaces:**
- Consumes: `TestCase` from Task 1.
- Produces: `StateMachine` (RefCounted) with `signal state_changed(from: StringName, to: StringName)`, `configure(states: Array[StringName], transitions: Dictionary, initial: StringName) -> void`, `current() -> StringName`, `can_transition_to(target: StringName) -> bool`, `transition_to(target: StringName) -> bool`. The player controller (Wave 2) and every threat (Wave 5) drive their behaviour through this same class, differing only in the configuration data.

`transitions` maps a state name to an `Array[StringName]` of legal targets.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_state_machine.gd`:

```gdscript
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — `res://src/core/state_machine.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/core/state_machine.gd`:

```gdscript
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

## Returns false and leaves the machine unconfigured if `initial` is not in
## `states`. Callers must check the result: an unconfigured machine rejects
## every transition, so ignoring a false return means the entity silently
## never moves.
##
## A return value rather than assert() because Godot strips assert() from
## release builds, and rather than push_error() because that would print an
## ERROR line that any covering test would then have to emit, breaking the
## pristine-output constraint.
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command.

Expected: `35 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/core/state_machine.gd tests/unit/test_state_machine.gd && git commit -m "feat: add data-configurable StateMachine shared by player and threats"
```

---

### Task 5: ServiceRegistry

**Files:**
- Create: `src/core/service_registry.gd`
- Create: `tests/unit/test_service_registry.gd`
- Modify: `project.godot` (add autoload)

**Interfaces:**
- Consumes: `TestCase` from Task 1.
- Produces: autoload `ServiceRegistry` with `register(key: StringName, service: Object) -> void`, `get_service(key: StringName) -> Object`, `has(key: StringName) -> bool`, `unregister(key: StringName) -> void`, `clear() -> void`. Later systems resolve their collaborators through this rather than naming autoloads directly, so a test can register a fake.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_service_registry.gd`:

```gdscript
extends TestCase

const ServiceRegistryScript := preload("res://src/core/service_registry.gd")

class FakeService extends RefCounted:
	var label := "real"

## ServiceRegistry extends Node, which is not reference-counted. Every
## instance a test builds is freed in after_each(), or the suite reports
## leaked ObjectDB instances and the output stops being pristine.
var _registry = null

func after_each() -> void:
	if _registry != null:
		_registry.free()
		_registry = null

func _build():
	_registry = ServiceRegistryScript.new()
	return _registry

func test_registered_service_is_returned() -> void:
	var registry = _build()
	var service := FakeService.new()
	registry.register(&"snow_field", service)
	assert_eq(registry.get_service(&"snow_field"), service, "the registered instance should come back")

func test_unknown_key_returns_null() -> void:
	var registry = _build()
	assert_eq(registry.get_service(&"nothing_here"), null, "an unregistered key should resolve to null")

func test_has_reports_registration() -> void:
	var registry = _build()
	assert_false(registry.has(&"snow_field"), "nothing is registered yet")
	registry.register(&"snow_field", FakeService.new())
	assert_true(registry.has(&"snow_field"), "the key should now be present")

func test_register_replaces_previous_binding() -> void:
	var registry = _build()
	var first := FakeService.new()
	var second := FakeService.new()
	second.label = "fake"
	registry.register(&"snow_field", first)
	registry.register(&"snow_field", second)
	assert_eq(registry.get_service(&"snow_field").label, "fake", "re-registering must replace, so tests can inject fakes")

func test_unregister_removes_the_binding() -> void:
	var registry = _build()
	registry.register(&"snow_field", FakeService.new())
	registry.unregister(&"snow_field")
	assert_false(registry.has(&"snow_field"), "unregister should remove the key")

func test_clear_removes_everything() -> void:
	var registry = _build()
	registry.register(&"a", FakeService.new())
	registry.register(&"b", FakeService.new())
	registry.clear()
	assert_false(registry.has(&"a"), "clear should drop a")
	assert_false(registry.has(&"b"), "clear should drop b")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — `res://src/core/service_registry.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/core/service_registry.gd`:

```gdscript
extends Node

## Indirection layer between systems and the singletons they use.
## Registered as autoload "ServiceRegistry".
##
## Autoloads are not instantiated when Godot runs with --script, which is
## how the test suite runs. Resolving collaborators through this registry
## is what lets a test for one system run without booting the other nine.

var _services: Dictionary = {}

func register(key: StringName, service: Object) -> void:
	_services[key] = service

func get_service(key: StringName) -> Object:
	return _services.get(key, null)

func has(key: StringName) -> bool:
	return _services.has(key)

func unregister(key: StringName) -> void:
	_services.erase(key)

func clear() -> void:
	_services.clear()
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command.

Expected: `41 passed, 0 failed`.

- [ ] **Step 5: Register the autoload**

Extend the `[autoload]` section of `project.godot`:

```ini
[autoload]

EventBus="*res://src/core/event_bus.gd"
ServiceRegistry="*res://src/core/service_registry.gd"
```

Verify:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --quit
```

Expected: no autoload errors.

- [ ] **Step 6: Commit**

```bash
git add src/core/service_registry.gd tests/unit/test_service_registry.gd project.godot && git commit -m "feat: add ServiceRegistry so systems can be tested in isolation"
```

---

### Task 6: Resource definition classes

**Files:**
- Create: `src/definitions/threshold_effect.gd`
- Create: `src/definitions/stat_definition.gd`
- Create: `src/definitions/weather_event_definition.gd`
- Create: `src/definitions/item_definition.gd`
- Create: `src/definitions/threat_definition.gd`
- Create: `src/definitions/beacon_definition.gd`
- Create: `src/definitions/lighting_preset.gd`
- Create: `src/definitions/day_schedule.gd`
- Create: `src/definitions/color_bible.gd`
- Create: `data/palette/color_bible.tres`
- Create: `tests/unit/test_definitions.gd`

**Interfaces:**
- Consumes: `Modifier` from Task 3, `TestCase` from Task 1.
- Produces: nine `Resource` subclasses named `ThresholdEffect`, `StatDefinition`, `WeatherEventDefinition`, `ItemDefinition`, `ThreatDefinition`, `BeaconDefinition`, `LightingPreset`, `DaySchedule`, `ColorBible`. `ColorBible` additionally exposes `all_colors() -> Array[Color]`, `contains(c: Color, tolerance := 0.004) -> bool`, and `is_warm(c: Color, tolerance := 0.004) -> bool`, which Task 7's palette test consumes. Every later wave authors `.tres` files against these classes.

These are data shapes with no behaviour, so they ship as one task; the test verifies each survives a `.tres` save/load round-trip, which is the only way they can actually break.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_definitions.gd`:

```gdscript
extends TestCase

const StatDefinitionScript := preload("res://src/definitions/stat_definition.gd")
const ThresholdEffectScript := preload("res://src/definitions/threshold_effect.gd")
const WeatherEventDefinitionScript := preload("res://src/definitions/weather_event_definition.gd")
const ItemDefinitionScript := preload("res://src/definitions/item_definition.gd")
const ThreatDefinitionScript := preload("res://src/definitions/threat_definition.gd")
const BeaconDefinitionScript := preload("res://src/definitions/beacon_definition.gd")
const LightingPresetScript := preload("res://src/definitions/lighting_preset.gd")
const DayScheduleScript := preload("res://src/definitions/day_schedule.gd")
const ColorBibleScript := preload("res://src/definitions/color_bible.gd")

const SCRATCH := "user://test_definitions_roundtrip.tres"

func after_each() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

func _round_trip(resource: Resource) -> Resource:
	var save_error := ResourceSaver.save(resource, SCRATCH)
	assert_eq(save_error, OK, "saving the resource should succeed")
	return ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE)

func test_stat_definition_round_trips() -> void:
	var stat = StatDefinitionScript.new()
	stat.id = &"core_temperature"
	stat.initial_value = 1.0
	stat.base_decay_per_second = 0.002
	stat.lethal_at_min = true
	var loaded = _round_trip(stat)
	assert_eq(loaded.id, &"core_temperature", "id should survive save/load")
	assert_almost_eq(loaded.base_decay_per_second, 0.002, 0.00001, "decay rate should survive save/load")
	assert_true(loaded.lethal_at_min, "lethal flag should survive save/load")

func test_stat_definition_holds_threshold_effects() -> void:
	var effect = ThresholdEffectScript.new()
	effect.watch_stat = &"hunger"
	effect.threshold = 0.3
	effect.target_stat = &"core_temperature"
	effect.value = 1.5
	var stat = StatDefinitionScript.new()
	stat.id = &"core_temperature"
	stat.threshold_effects = [effect]
	var loaded = _round_trip(stat)
	assert_eq(loaded.threshold_effects.size(), 1, "the nested effect should survive save/load")
	assert_eq(loaded.threshold_effects[0].watch_stat, &"hunger", "nested effect fields should survive")

func test_weather_event_definition_round_trips() -> void:
	var event = WeatherEventDefinitionScript.new()
	event.id = &"blizzard"
	event.tell_duration_range = Vector2(20.0, 40.0)
	event.extinguishes_beacons = true
	event.min_beacons_extinguished = 1
	var loaded = _round_trip(event)
	assert_eq(loaded.id, &"blizzard", "id should survive save/load")
	assert_true(loaded.extinguishes_beacons, "beacon flag should survive save/load")
	assert_eq(loaded.min_beacons_extinguished, 1, "beacon count should survive save/load")

func test_weather_event_tell_duration_is_within_spec() -> void:
	var event = WeatherEventDefinitionScript.new()
	assert_almost_eq(event.tell_duration_range.x, 20.0, 0.001, "spec requires a 20-40s tell window")
	assert_almost_eq(event.tell_duration_range.y, 40.0, 0.001, "spec requires a 20-40s tell window")

func test_item_definition_round_trips() -> void:
	var item = ItemDefinitionScript.new()
	item.id = &"split_log"
	item.category = ItemDefinitionScript.Category.FUEL
	item.fuel_value = 180.0
	var loaded = _round_trip(item)
	assert_eq(loaded.id, &"split_log", "id should survive save/load")
	assert_almost_eq(loaded.fuel_value, 180.0, 0.001, "fuel value should survive save/load")

func test_threat_definition_round_trips() -> void:
	var threat = ThreatDefinitionScript.new()
	threat.id = &"bear"
	threat.perception_kinds = [ThreatDefinitionScript.PerceptionKind.SCENT]
	threat.charge_speed = 8.0
	threat.warns_before_charging = true
	threat.first_active_day = 4
	var loaded = _round_trip(threat)
	assert_eq(loaded.id, &"bear", "id should survive save/load")
	assert_eq(loaded.perception_kinds.size(), 1, "perception list should survive save/load")
	assert_true(loaded.warns_before_charging, "warning flag should survive save/load")
	assert_eq(loaded.first_active_day, 4, "spec puts the bear on day 4")

func test_beacon_definition_round_trips() -> void:
	var beacon = BeaconDefinitionScript.new()
	beacon.id = &"church_tower"
	beacon.world_position = Vector3(120.0, 0.0, -85.0)
	beacon.fuel_capacity = 600.0
	var loaded = _round_trip(beacon)
	assert_eq(loaded.id, &"church_tower", "id should survive save/load")
	assert_almost_eq(loaded.world_position.x, 120.0, 0.001, "position should survive save/load")

func test_lighting_preset_round_trips() -> void:
	var preset = LightingPresetScript.new()
	preset.id = &"whiteout"
	preset.fog_density = 0.08
	preset.cel_band_threshold = 0.5
	var loaded = _round_trip(preset)
	assert_eq(loaded.id, &"whiteout", "id should survive save/load")
	assert_almost_eq(loaded.fog_density, 0.08, 0.0001, "fog density should survive save/load")

func test_day_schedule_round_trips() -> void:
	var schedule = DayScheduleScript.new()
	schedule.day_number = 7
	schedule.daylight_seconds = 240.0
	schedule.night_seconds = 660.0
	schedule.forced_weather_event = &"blizzard"
	var loaded = _round_trip(schedule)
	assert_eq(loaded.day_number, 7, "day number should survive save/load")
	assert_almost_eq(loaded.daylight_seconds, 240.0, 0.001, "daylight length should survive save/load")
	assert_eq(loaded.forced_weather_event, &"blizzard", "day 7 forces the storm")

func test_color_bible_asset_has_twelve_colors() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(bible, "the palette asset must exist at res://data/palette/color_bible.tres")
	assert_eq(bible.all_colors().size(), 12, "the palette is exactly 12 colors")
	assert_eq(bible.warm_tones.size(), 3, "exactly 3 of them are warm")

func test_color_bible_recognises_a_palette_color() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(bible.contains(Color("#8FB0D8")), "the brightest snow tone is in the palette")
	assert_true(bible.contains(Color("#FFB257")), "the amber window tone is in the palette")

func test_color_bible_rejects_an_off_palette_color() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_false(bible.contains(Color("#00FF00")), "pure green is not in the palette")
	assert_false(bible.contains(Color("#FFFFFF")), "pure white is not in the palette")

func test_color_bible_identifies_warm_tones() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(bible.is_warm(Color("#FFB257")), "amber is a warm tone")
	assert_false(bible.is_warm(Color("#8FB0D8")), "snow is not a warm tone")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — none of the definition scripts exist.

- [ ] **Step 3: Write ThresholdEffect and StatDefinition**

Create `src/definitions/threshold_effect.gd`:

```gdscript
class_name ThresholdEffect
extends Resource

## "When hunger drops below 0.3, multiply core temperature decay by 1.5."
##
## Encoding the survival model's interlocks as data is what lets a designer
## add a sixth stat, or a new interlock between two existing ones, without
## touching GDScript.

enum Comparison { BELOW, ABOVE }

## The stat being watched.
@export var watch_stat: StringName = &""

@export var comparison: Comparison = Comparison.BELOW

@export var threshold: float = 0.0

## The stat that gets modified when the condition holds.
@export var target_stat: StringName = &""

@export var operation: Modifier.Operation = Modifier.Operation.MULTIPLY

@export var value: float = 1.0
```

Create `src/definitions/stat_definition.gd`:

```gdscript
class_name StatDefinition
extends Resource

## One survival track: core temperature, hunger, thirst, fatigue, frostbite.

@export var id: StringName = &""
@export var display_name: String = ""

@export var initial_value: float = 1.0
@export var min_value: float = 0.0
@export var max_value: float = 1.0

## Baseline drain per second before any modifier applies.
@export var base_decay_per_second: float = 0.0

## When true, reaching min_value ends the run.
@export var lethal_at_min: bool = false

## Interlocks with other stats.
@export var threshold_effects: Array[ThresholdEffect] = []
```

- [ ] **Step 4: Write the remaining six definition classes**

Create `src/definitions/weather_event_definition.gd`:

```gdscript
class_name WeatherEventDefinition
extends Resource

## One weather event, in three phases: tell, active, fade.
## The tell phase is mandatory -- an unannounced storm is unfair, not hard.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Timing")
## Seconds of warning before the event lands. Spec floor: 20-40s.
@export var tell_duration_range := Vector2(20.0, 40.0)
@export var active_duration_range := Vector2(60.0, 180.0)
@export var fade_duration := 15.0

@export_group("Effects")
@export var stat_modifiers: Array[Modifier] = []
@export var visibility_multiplier := 1.0
@export var wind_speed_multiplier := 1.0
@export var snowfall_rate := 0.0

@export_group("Beacons")
@export var extinguishes_beacons := false
@export var min_beacons_extinguished := 0
```

Create `src/definitions/item_definition.gd`:

```gdscript
class_name ItemDefinition
extends Resource

## Anything the player can carry. Fuel is the real currency: water needs
## melting, melting needs fire, fire needs fuel -- and so do the beacons.

enum Category { FUEL, FOOD, WATER, MEDICINE, TOOL }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.FUEL

@export var mass_kg := 1.0

## Seconds of burn time this yields. Zero for non-fuel items.
@export var fuel_value := 0.0

@export var nutrition := 0.0
@export var hydration := 0.0

## Applied to the player's stats when used.
@export var use_modifiers: Array[Modifier] = []
```

Create `src/definitions/threat_definition.gd`:

```gdscript
class_name ThreatDefinition
extends Resource

## A threat is a data file, not a class. The bear and the scavenger run the
## same code; they differ only in these values.

enum PerceptionKind { SIGHT, SCENT, TRACKS }

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Perception")
@export var perception_kinds: Array[PerceptionKind] = []
@export var sight_range := 30.0
@export var sight_angle_degrees := 90.0
## Scent only carries downwind -- wind direction is a gameplay variable.
@export var scent_range := 120.0
@export var track_follow_range := 40.0

@export_group("Locomotion")
@export var walk_speed := 2.0
@export var charge_speed := 8.0

@export_group("Engagement")
@export var warns_before_charging := false
@export var warning_duration := 2.0
@export var can_be_scared_off := false

@export_group("Schedule")
@export var first_active_day := 1
```

Create `src/definitions/beacon_definition.gd`:

```gdscript
class_name BeaconDefinition
extends Resource

## One of the five lamps. Lighting all five and keeping them burning to
## dawn on day 8 is the win condition.

@export var id: StringName = &""
@export var display_name: String = ""

@export var world_position := Vector3.ZERO

## Seconds of burn time on a full load of fuel.
@export var fuel_capacity := 600.0

## Wind speed above which this beacon may be blown out.
@export var wind_extinguish_threshold := 18.0

## The day this beacon becomes lightable.
@export var unlock_day := 1
```

Create `src/definitions/lighting_preset.gd`:

```gdscript
class_name LightingPreset
extends Resource

## One of the six looks. Each is a dramatic beat as much as a light setup.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Key Light")
@export var sun_energy := 1.0
@export var sun_color := Color.WHITE
@export var sun_angle_degrees := 15.0
@export var shadows_enabled := true

@export_group("Ambient")
@export var ambient_color := Color(0.08, 0.11, 0.19)
@export var ambient_energy := 1.0

@export_group("Air")
@export var fog_enabled := true
@export var fog_density := 0.01
@export var glow_enabled := true
@export var glow_strength := 0.3

@export_group("Shading")
@export var cel_band_threshold := 0.5
@export var cel_band_softness := 0.05
@export var warm_accent_energy := 1.0
```

Create `src/definitions/day_schedule.gd`:

```gdscript
class_name DaySchedule
extends Resource

## The authored half of the weather model: each day's budget and its
## mandatory beats. Randomness lives inside these bounds so the dramatic
## arc survives it.

@export var day_number := 1

@export var daylight_seconds := 600.0
@export var night_seconds := 300.0

@export var primary_lighting_preset: StringName = &""

## Events that may be drawn at random today.
@export var allowed_weather_events: Array[StringName] = []

## An event that must happen today regardless of the draw. Day 7 forces
## the blizzard.
@export var forced_weather_event: StringName = &""

## The beacon that becomes lightable today, if any.
@export var beacon_unlocked: StringName = &""
```

Create `src/definitions/color_bible.gd`:

```gdscript
class_name ColorBible
extends Resource

## The twelve colors every model builds from. Nothing in the project may
## hardcode a color; everything reads this resource.

@export var snow_tones: Array[Color] = []
@export var structure_tones: Array[Color] = []
@export var warm_tones: Array[Color] = []

func all_colors() -> Array[Color]:
	var combined: Array[Color] = []
	combined.append_array(snow_tones)
	combined.append_array(structure_tones)
	combined.append_array(warm_tones)
	return combined

func _matches(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance \
		and absf(a.g - b.g) <= tolerance \
		and absf(a.b - b.b) <= tolerance

## Tolerance defaults to ~1/255, absorbing 8-bit rounding without letting
## a genuinely different color slip through.
func contains(c: Color, tolerance := 0.004) -> bool:
	for known in all_colors():
		if _matches(known, c, tolerance):
			return true
	return false

func is_warm(c: Color, tolerance := 0.004) -> bool:
	for known in warm_tones:
		if _matches(known, c, tolerance):
			return true
	return false
```

- [ ] **Step 5: Generate the palette asset**

Do **not** hand-write this `.tres`. A property typed `Array[Color]` serializes as `Array[Color]([Color(...), ...])`, not `PackedColorArray(...)`, and getting typed-array syntax wrong fails in ways that are tedious to diagnose. Let Godot write it.

Create `tools/generate_palette.gd`:

```gdscript
extends SceneTree

## One-off generator for res://data/palette/color_bible.tres.
## Run: godot --headless --path <project> --script res://tools/generate_palette.gd

func _initialize() -> void:
	var ColorBibleScript := load("res://src/definitions/color_bible.gd")
	var bible = ColorBibleScript.new()

	var snow: Array[Color] = [
		Color("#8FB0D8"), Color("#7FA0C9"), Color("#748FBB"),
		Color("#6987B4"), Color("#5D7BA6"),
	]
	var structure: Array[Color] = [
		Color("#33496E"), Color("#2A3854"), Color("#1C2A45"), Color("#131C30"),
	]
	var warm: Array[Color] = [
		Color("#6E2F2E"), Color("#A05A35"), Color("#FFB257"),
	]

	bible.snow_tones = snow
	bible.structure_tones = structure
	bible.warm_tones = warm

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/palette"))
	var error := ResourceSaver.save(bible, "res://data/palette/color_bible.tres")
	print("generate_palette: save returned %d, %d colors" % [error, bible.all_colors().size()])
	quit(0 if error == OK else 1)
```

Run it:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tools/generate_palette.gd
```

Expected: `generate_palette: save returned 0, 12 colors`

- [ ] **Step 6: Run the test to verify it passes**

Run the Step 2 command.

Expected: `54 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add src/definitions/ data/palette/ tools/generate_palette.gd tests/unit/test_definitions.gd && git commit -m "feat: add nine Resource definition classes and the 12-color palette asset"
```

---

### Task 7: Art verification suite (static analysis)

**Files:**
- Create: `tests/framework/asset_scanner.gd`
- Create: `tests/unit/test_asset_scanner.gd`
- Create: `tests/art/test_palette.gd`
- Create: `tests/art/test_topology.gd`
- Create: `tests/art/test_shading_features.gd`

**Interfaces:**
- Consumes: `ColorBible` from Task 6, `TestCase` from Task 1.
- Produces: `AssetScanner.find_files(root: String, suffixes: Array[String]) -> PackedStringArray` (static), plus three always-on build gates. Every wave that adds a model or material is checked by these automatically; no later task needs to invoke them explicitly.

These scan `res://assets/models/` and `res://scenes/`. Both are empty in Wave 0, so the project-wide assertions pass by finding nothing to reject.

**That is exactly why this task carries two extra layers of proof.** A gate that silently inspects nothing is worse than no gate — it reports "verified" forever:

1. Each gate has a pair of tests that run its check against **synthetic in-memory fixtures** — one violating, one compliant — proving the check itself discriminates.
2. `AssetScanner` has its own tests that create **real files on disk** and assert they are found, proving the walker is not a no-op.

**Deferred:** the warmth-budget test (≤ 0.5% warm pixels) needs a rendered frame and therefore lighting and a scene. It is the first task of Wave 3's plan.

- [ ] **Step 1: Write the shared asset scanner**

All three gates need the same recursive walk. Write it once.

Create `tests/framework/asset_scanner.gd`:

```gdscript
class_name AssetScanner
extends RefCounted

## Recursive file walk shared by the art gates.
##
## Returns an empty result for a missing root rather than erroring: the
## gates run against folders that do not exist yet in early waves.

## Shared across the three gates so their coverage cannot silently diverge.
const SCAN_ROOTS: Array[String] = ["res://assets/models", "res://scenes"]
const MATERIAL_SUFFIXES: Array[String] = [".tres", ".material", ".res"]
const MESH_SUFFIXES: Array[String] = [".mesh", ".res", ".tres"]

static func find_files(root: String, suffixes: Array[String]) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(find_files(full, suffixes))
		else:
			for suffix in suffixes:
				if entry.ends_with(suffix):
					found.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return found
```

- [ ] **Step 2: Prove the scanner is not a no-op**

Create `tests/unit/test_asset_scanner.gd`:

```gdscript
extends TestCase

## The art gates are only as real as this walker. If find_files() silently
## returned nothing, every gate would pass forever while inspecting zero
## assets. These tests put real files on disk and demand they be found.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

const FIXTURE_ROOT := "user://scanner_fixture"

func _write(relative_path: String) -> void:
	var handle := FileAccess.open(FIXTURE_ROOT.path_join(relative_path), FileAccess.WRITE)
	handle.store_string("fixture")
	handle.close()

func before_each() -> void:
	var absolute := ProjectSettings.globalize_path(FIXTURE_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute.path_join("nested"))
	_write("top.tres")
	_write("nested/deep.tres")
	_write("ignored.txt")

func after_each() -> void:
	var absolute := ProjectSettings.globalize_path(FIXTURE_ROOT)
	DirAccess.remove_absolute(absolute.path_join("nested/deep.tres"))
	DirAccess.remove_absolute(absolute.path_join("nested"))
	DirAccess.remove_absolute(absolute.path_join("top.tres"))
	DirAccess.remove_absolute(absolute.path_join("ignored.txt"))
	DirAccess.remove_absolute(absolute)

func test_finds_files_recursively() -> void:
	var found := AssetScannerScript.find_files(FIXTURE_ROOT, [".tres"] as Array[String])
	assert_eq(found.size(), 2, "should find top.tres and nested/deep.tres")

func test_filters_by_suffix() -> void:
	var found := AssetScannerScript.find_files(FIXTURE_ROOT, [".txt"] as Array[String])
	assert_eq(found.size(), 1, "should find only ignored.txt")

func test_missing_root_yields_empty_not_error() -> void:
	var found := AssetScannerScript.find_files("res://this_folder_does_not_exist", [".tres"] as Array[String])
	assert_eq(found.size(), 0, "a missing folder should yield an empty result, not an error")
```

- [ ] **Step 3: Write the palette test**

Create `tests/art/test_palette.gd`:

```gdscript
extends TestCase

## Rule 9 of the Art Bible: every surface is flat-shaded and its color comes
## from the 12-color palette. This test is the gate.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

var _bible

func before_each() -> void:
	_bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)

func test_the_gate_catches_an_off_palette_material() -> void:
	# Proves the check works before any real asset exists.
	var offender := StandardMaterial3D.new()
	offender.albedo_color = Color("#00FF00")
	assert_false(_bible.contains(offender.albedo_color), "a pure green material must be rejected")

func test_the_gate_accepts_an_on_palette_material() -> void:
	var good := StandardMaterial3D.new()
	good.albedo_color = Color("#6987B4")
	assert_true(_bible.contains(good.albedo_color), "a palette snow tone must be accepted")

func test_every_material_in_the_project_is_on_palette() -> void:
	for root in AssetScannerScript.SCAN_ROOTS:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is BaseMaterial3D):
				continue
			var material := resource as BaseMaterial3D
			assert_true(
				_bible.contains(material.albedo_color),
				"%s uses albedo %s, which is not in the 12-color palette" % [path, material.albedo_color.to_html(false)]
			)
```

- [ ] **Step 4: Write the topology test**

Create `tests/art/test_topology.gd`:

```gdscript
extends TestCase

## Rule 6 of the Art Bible: triangle budgets by asset class. The budget is
## keyed off the folder an asset lives in.

const BUDGETS := {
	"res://assets/models/buildings": 500,
	"res://assets/models/props": 200,
	"res://assets/models/vegetation": 300,
	"res://assets/models/characters": 8000,
}

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		# surface_get_arrays() returns null for slots the surface does not
		# use, and assigning null into a typed PackedInt32Array is a runtime
		# error that aborts this function. Non-indexed meshes hit exactly
		# that slot, so read it untyped and null-check before casting.
		var index_slot = arrays[Mesh.ARRAY_INDEX]
		if index_slot != null and (index_slot as PackedInt32Array).size() > 0:
			total += (index_slot as PackedInt32Array).size() / 3
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += vertices.size() / 3
	return total

## The gate's actual decision, factored out so it can be tested against a
## violating and a compliant case. Inlined in the scan loop it would be
## unreachable while the asset folders are empty, and a reversed or
## off-by-one comparison would pass forever.
func _within_budget(triangle_count: int, budget: int) -> bool:
	return triangle_count <= budget

func test_the_gate_counts_an_indexed_mesh() -> void:
	# A BoxMesh is 6 quads = 12 triangles, and PrimitiveMesh always indexes.
	var box := BoxMesh.new()
	assert_eq(_triangle_count(box), 12, "a box should count as 12 triangles")

func test_the_gate_counts_a_non_indexed_mesh() -> void:
	# The branch a BoxMesh never reaches. Built without an ARRAY_INDEX entry.
	var vertices := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert_eq(_triangle_count(mesh), 2, "six unindexed vertices are two triangles")

func test_the_gate_rejects_a_count_over_budget() -> void:
	assert_false(_within_budget(501, 500), "501 triangles must fail a 500 budget")

func test_the_gate_accepts_a_count_at_budget() -> void:
	assert_true(_within_budget(500, 500), "exactly the budget must pass")

func test_every_mesh_is_within_its_budget() -> void:
	for root in BUDGETS.keys():
		var budget: int = BUDGETS[root]
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MESH_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is Mesh):
				continue
			var count := _triangle_count(resource as Mesh)
			assert_true(
				_within_budget(count, budget),
				"%s has %d triangles, over the %d budget for %s" % [path, count, budget, root]
			)
```

- [ ] **Step 5: Write the shading-features test**

Create `tests/art/test_shading_features.gd`:

```gdscript
extends TestCase

## Rule 8 of the Art Bible: the banned list. Flat color only -- the light
## does the work.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

func _violations(material: BaseMaterial3D) -> PackedStringArray:
	var problems := PackedStringArray()
	# ORMMaterial3D exists to pack occlusion, roughness, and metallic into a
	# single texture -- precisely the maps rule 8 forbids. It is a
	# BaseMaterial3D but not a StandardMaterial3D, so without this branch it
	# would pass the gate no matter what it contains.
	if material is ORMMaterial3D:
		problems.append("ORMMaterial3D packs occlusion/roughness/metallic, which the banned list forbids")
		return problems
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if standard.normal_enabled:
			problems.append("normal map enabled")
		if standard.roughness_texture != null:
			problems.append("roughness texture assigned")
		if standard.metallic_texture != null:
			problems.append("metallic texture assigned")
		if standard.metallic > 0.0:
			problems.append("metallic is %f, must be 0" % standard.metallic)
		if standard.specular_mode != BaseMaterial3D.SPECULAR_DISABLED:
			problems.append("specular is enabled, must be SPECULAR_DISABLED")
	return problems

func test_the_gate_catches_a_banned_feature() -> void:
	var offender := StandardMaterial3D.new()
	offender.metallic = 0.8
	var problems := _violations(offender)
	assert_true(problems.size() > 0, "a metallic material must be flagged")

func test_the_gate_accepts_a_compliant_material() -> void:
	var good := StandardMaterial3D.new()
	good.metallic = 0.0
	good.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var problems := _violations(good)
	assert_eq(problems.size(), 0, "a flat, non-metallic, non-specular material must pass")

func test_the_gate_catches_an_orm_material() -> void:
	var offender := ORMMaterial3D.new()
	var problems := _violations(offender)
	assert_true(problems.size() > 0, "ORMMaterial3D packs the exact maps the banned list forbids")

func test_no_material_in_the_project_uses_a_banned_feature() -> void:
	for root in AssetScannerScript.SCAN_ROOTS:
		for path in AssetScannerScript.find_files(root, AssetScannerScript.MATERIAL_SUFFIXES):
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null or not (resource is BaseMaterial3D):
				continue
			var problems := _violations(resource as BaseMaterial3D)
			assert_eq(problems.size(), 0, "%s violates the banned list: %s" % [path, ", ".join(problems)])
```

- [ ] **Step 6: Create the empty asset folders**

The scanners tolerate missing folders, but creating them now documents the layout. Git does not track empty directories, so add a `.gitkeep` to each:

```bash
cd "D:/Godot resource/winter-time"
mkdir -p assets/models/buildings assets/models/props assets/models/vegetation assets/models/characters scenes/entities scenes/locations scenes/ui
touch assets/models/buildings/.gitkeep assets/models/props/.gitkeep assets/models/vegetation/.gitkeep assets/models/characters/.gitkeep scenes/entities/.gitkeep scenes/locations/.gitkeep scenes/ui/.gitkeep
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: `73 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add tests/framework/asset_scanner.gd tests/unit/test_asset_scanner.gd tests/art/ assets/ scenes/ && git commit -m "test: add shared asset scanner and three art gates"
```

---

### Task 8: WorldClock

**Files:**
- Create: `src/systems/world_clock.gd`
- Create: `data/schedule/day_01.tres` through `data/schedule/day_07.tres`
- Create: `tests/unit/test_world_clock.gd`
- Modify: `project.godot` (add autoload)

**Interfaces:**
- Consumes: `DaySchedule` from Task 6, `EventBus` from Task 2, `TestCase` from Task 1.
- Produces: autoload `WorldClock` with `load_schedules(schedules: Array) -> void`, `start() -> void`, `advance(delta: float) -> void`, `current_day() -> int` (1-based), `is_night() -> bool`, `phase_elapsed() -> float`, `phase_duration() -> float`, `is_finished() -> bool`, and `set_event_bus(bus) -> void`. Emits `clock.day_started` (payload: day number), `clock.night_started` (payload: day number), and `clock.run_finished` (payload: `null`) through the injected bus.

`advance(delta)` is public and does the work; `_process` merely forwards to it. That keeps the clock testable without a running SceneTree.

Day lengths come from GDD §4: days 1–2 are 600s/300s, days 3–4 are 480s/420s, day 5 is 420s/480s, day 6 is 300s/600s, day 7 is 240s/660s.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_world_clock.gd`:

```gdscript
extends TestCase

const WorldClockScript := preload("res://src/systems/world_clock.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const DayScheduleScript := preload("res://src/definitions/day_schedule.gd")

var _events: Array = []

## WorldClock and EventBus both extend Node, which is not reference-counted.
## Both are freed in after_each(), or the suite reports leaked ObjectDB
## instances and the output stops being pristine.
var _clock = null
var _bus = null

func before_each() -> void:
	_events = []

func after_each() -> void:
	if _clock != null:
		_clock.free()
		_clock = null
	if _bus != null:
		_bus.free()
		_bus = null

func _record_day(payload) -> void:
	_events.append(["day", payload])

func _record_night(payload) -> void:
	_events.append(["night", payload])

func _record_finish(_payload) -> void:
	_events.append(["finish", null])

func _make_schedule(day: int, daylight: float, night: float):
	var schedule = DayScheduleScript.new()
	schedule.day_number = day
	schedule.daylight_seconds = daylight
	schedule.night_seconds = night
	return schedule

func _build_clock(day_count := 2):
	_bus = EventBusScript.new()
	_bus.subscribe(&"clock.day_started", _record_day)
	_bus.subscribe(&"clock.night_started", _record_night)
	_bus.subscribe(&"clock.run_finished", _record_finish)
	_clock = WorldClockScript.new()
	_clock.set_event_bus(_bus)
	var schedules := []
	for day in range(1, day_count + 1):
		schedules.append(_make_schedule(day, 10.0, 5.0))
	_clock.load_schedules(schedules)
	return _clock

func test_starts_on_day_one_in_daylight() -> void:
	var clock = _build_clock()
	clock.start()
	assert_eq(clock.current_day(), 1, "the run starts on day 1")
	assert_false(clock.is_night(), "the run starts in daylight")

func test_start_emits_day_started() -> void:
	var clock = _build_clock()
	clock.start()
	assert_eq(_events.size(), 1, "start should emit exactly one event")
	assert_eq(_events[0][0], "day", "that event should be clock.day_started")
	assert_eq(_events[0][1], 1, "payload should be day 1")

func test_night_begins_after_daylight_elapses() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(9.0)
	assert_false(clock.is_night(), "still daylight at 9 of 10 seconds")
	clock.advance(2.0)
	assert_true(clock.is_night(), "night should have begun after 10 seconds of daylight")

func test_night_start_emits_an_event() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(11.0)
	assert_eq(_events.size(), 2, "expect day_started then night_started")
	assert_eq(_events[1][0], "night", "second event should be clock.night_started")

func test_next_day_begins_after_night_elapses() -> void:
	var clock = _build_clock()
	clock.start()
	clock.advance(10.0)
	clock.advance(5.0)
	assert_eq(clock.current_day(), 2, "day should roll over after daylight + night")
	assert_false(clock.is_night(), "the new day starts in daylight")

func test_run_finishes_after_the_last_day() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(15.0)
	clock.advance(15.0)
	assert_true(clock.is_finished(), "the run ends at dawn after the final scheduled day")

func test_run_finish_emits_an_event() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(15.0)
	clock.advance(15.0)
	var saw_finish := false
	for event in _events:
		if event[0] == "finish":
			saw_finish = true
	assert_true(saw_finish, "clock.run_finished should fire at the end of the run")

func test_advancing_after_finish_is_inert() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(100.0)
	var count_before: int = _events.size()
	clock.advance(100.0)
	assert_eq(_events.size(), count_before, "a finished clock must stop emitting")

func test_a_single_large_delta_can_cross_several_phases() -> void:
	var clock = _build_clock(2)
	clock.start()
	clock.advance(16.0)
	assert_eq(clock.current_day(), 2, "a 16s step past a 15s day should land on day 2")
	assert_false(clock.is_night(), "and 1s into its daylight")
	assert_almost_eq(clock.phase_elapsed(), 1.0, 0.0001, "the remainder should carry into the new phase")

func test_phase_duration_reports_the_active_phase() -> void:
	var clock = _build_clock()
	clock.start()
	assert_almost_eq(clock.phase_duration(), 10.0, 0.0001, "daylight phase is 10 seconds")
	clock.advance(11.0)
	assert_almost_eq(clock.phase_duration(), 5.0, 0.0001, "night phase is 5 seconds")

func test_shipped_schedule_matches_the_gdd() -> void:
	var expected := {
		1: [600.0, 300.0], 2: [600.0, 300.0], 3: [480.0, 420.0],
		4: [480.0, 420.0], 5: [420.0, 480.0], 6: [300.0, 600.0],
		7: [240.0, 660.0],
	}
	for day in expected.keys():
		var path := "res://data/schedule/day_%02d.tres" % day
		var schedule = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(schedule, "%s must exist" % path)
		assert_eq(schedule.day_number, day, "%s should declare day %d" % [path, day])
		assert_almost_eq(schedule.daylight_seconds, expected[day][0], 0.001, "%s daylight length" % path)
		assert_almost_eq(schedule.night_seconds, expected[day][1], 0.001, "%s night length" % path)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tests/framework/test_runner.gd
```

Expected: FAIL — `res://src/systems/world_clock.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/systems/world_clock.gd`:

```gdscript
extends Node

## Drives the seven-day run. Registered as autoload "WorldClock".
##
## advance() is public and carries all the logic; _process only forwards to
## it. That lets the whole clock be tested without a running SceneTree,
## which matters because autoloads do not exist under --script.

const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"

var _schedules: Array = []
var _day_index := 0
var _phase_elapsed := 0.0
var _is_night := false
var _running := false
var _finished := false
var _bus = null

func set_event_bus(bus) -> void:
	_bus = bus

func _ready() -> void:
	# In a real run the autoload wires itself to the autoloaded bus.
	# Tests inject their own via set_event_bus() before calling start().
	#
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry
	# is a node under /root and never appears in the engine's singleton
	# registry, which holds only natively-registered and GDExtension
	# singletons. Engine.has_singleton("EventBus") is false always, which
	# would leave _bus null forever -- and _emit()'s null guard would then
	# swallow every clock event with no diagnostic. That failure is
	# invisible to this wave's tests, because they all inject a bus and
	# never add WorldClock to a live scene tree, so _ready() never runs.
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")

func load_schedules(schedules: Array) -> void:
	_schedules = schedules.duplicate()

func start() -> void:
	_day_index = 0
	_phase_elapsed = 0.0
	_is_night = false
	_finished = false
	_running = true
	_emit(EVENT_DAY_STARTED, current_day())

func current_day() -> int:
	return _day_index + 1

func is_night() -> bool:
	return _is_night

func is_finished() -> bool:
	return _finished

func phase_elapsed() -> float:
	return _phase_elapsed

func phase_duration() -> float:
	if _day_index >= _schedules.size():
		return 0.0
	var schedule = _schedules[_day_index]
	return schedule.night_seconds if _is_night else schedule.daylight_seconds

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _running or _finished:
		return
	var remaining := delta
	# Loop rather than subtract once: a long frame or a fast-forward may
	# cross more than one phase boundary in a single call.
	while remaining > 0.0 and not _finished:
		var duration := phase_duration()
		if duration <= 0.0:
			_finish()
			return
		var left := duration - _phase_elapsed
		if remaining < left:
			_phase_elapsed += remaining
			return
		remaining -= left
		_phase_elapsed = 0.0
		_advance_phase()

func _advance_phase() -> void:
	if _is_night:
		_is_night = false
		_day_index += 1
		if _day_index >= _schedules.size():
			_finish()
			return
		_emit(EVENT_DAY_STARTED, current_day())
	else:
		_is_night = true
		_emit(EVENT_NIGHT_STARTED, current_day())

func _finish() -> void:
	_finished = true
	_running = false
	_emit(EVENT_RUN_FINISHED, null)

func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
```

- [ ] **Step 4: Generate the seven schedule assets**

Same reasoning as the palette: `allowed_weather_events` is `Array[StringName]`, so let Godot write the files.

Create `tools/generate_schedules.gd`:

```gdscript
extends SceneTree

## One-off generator for res://data/schedule/day_01..07.tres.
## Values come from GDD section 4.
## Run: godot --headless --path <project> --script res://tools/generate_schedules.gd

func _initialize() -> void:
	var DayScheduleScript := load("res://src/definitions/day_schedule.gd")

	# day, daylight, night, preset, allowed events, forced event, beacon
	var rows := [
		[1, 600.0, 300.0, &"pale_day",  [],                                            &"",         &"farmhouse_chimney"],
		[2, 600.0, 300.0, &"pale_day",  [&"snow_fog"],                                 &"",         &"fuel_station"],
		[3, 480.0, 420.0, &"nightfall", [&"snow_fog", &"clear_break"],                 &"",         &"church_tower"],
		[4, 480.0, 420.0, &"deep_night",[&"wind_shift", &"snow_fog"],                  &"",         &"logging_camp"],
		[5, 420.0, 480.0, &"sunrise",   [&"clear_break", &"cold_snap"],                &"",         &"power_pylon"],
		[6, 300.0, 600.0, &"nightfall", [&"cold_snap", &"freezing_rain", &"wind_shift"], &"",       &""],
		[7, 240.0, 660.0, &"whiteout",  [&"wind_shift"],                               &"blizzard", &""],
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/schedule"))
	for row in rows:
		var schedule = DayScheduleScript.new()
		schedule.day_number = row[0]
		schedule.daylight_seconds = row[1]
		schedule.night_seconds = row[2]
		schedule.primary_lighting_preset = row[3]
		var events: Array[StringName] = []
		for e in row[4]:
			events.append(e)
		schedule.allowed_weather_events = events
		schedule.forced_weather_event = row[5]
		schedule.beacon_unlocked = row[6]

		var path := "res://data/schedule/day_%02d.tres" % row[0]
		var error := ResourceSaver.save(schedule, path)
		if error != OK:
			print("generate_schedules: FAILED %s (%d)" % [path, error])
			quit(1)
		print("generate_schedules: wrote %s" % path)
	quit(0)
```

Run it:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --script res://tools/generate_schedules.gd
```

Expected: seven `wrote res://data/schedule/day_NN.tres` lines, exit code 0.

The generators stay in `tools/` and stay in version control — regenerating an asset must always be cheaper than hand-repairing one.

- [ ] **Step 5: Run the test to verify it passes**

Run the Step 2 command.

Expected: `84 passed, 0 failed`.

- [ ] **Step 6: Register the autoload**

Extend the `[autoload]` section of `project.godot`. Order matters — `WorldClock` resolves `EventBus` at `_ready`, so it must come after:

```ini
[autoload]

EventBus="*res://src/core/event_bus.gd"
ServiceRegistry="*res://src/core/service_registry.gd"
WorldClock="*res://src/systems/world_clock.gd"
```

Verify:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/Godot resource/winter-time" --quit
```

Expected: no autoload errors.

- [ ] **Step 7: Commit**

```bash
git add src/systems/world_clock.gd data/schedule/ tools/generate_schedules.gd tests/unit/test_world_clock.gd project.godot && git commit -m "feat: add WorldClock driving the seven-day run"
```

---

## Wave 0 exit criteria

All must hold before Wave 1 starts:

- [ ] `84 passed, 0 failed` from the headless runner, exit code 0
- [ ] The runner has been observed going **red** and returning exit code 1 (Task 1, Step 5)
- [ ] `project.godot` lists exactly three autoloads: `EventBus`, `ServiceRegistry`, `WorldClock`
- [ ] No hardcoded hex color outside `tools/` — the generators in `tools/` are where color values legitimately live, since they are the source that writes `data/palette/color_bible.tres`
- [ ] `src/core/` contains no reference to snow, weather, beacons, threats, or any other game noun
- [ ] `AssetScanner`'s disk-fixture tests pass, proving the art gates inspect real files rather than silently scanning nothing
- [ ] Every filename is English `snake_case`

## Handoff to Wave 1

Wave 1 (`snow_field.gd`, `track_mask.gd`, valley layout) consumes: `EventBus.emit_event/subscribe`, `ServiceRegistry.register/get_service`, `WorldClock`'s three events, and the `ColorBible` resource. Its plan must open with the deferred **warmth-budget art test** only after lighting exists in Wave 3 — Wave 1 itself has no rendering gate beyond palette and topology.
