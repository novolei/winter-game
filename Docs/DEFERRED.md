# Deferred Findings Register

Every finding this project accepted but did not fix, with the wave that owns it.

**This file is the durable record.** Per-wave ledgers live under `.superpowers/`, which is gitignored and deleted when a wave closes — anything not promoted here before that is gone. Wave 0's final review flagged exactly that as a structural silent-discard risk, which is why this file exists.

**Rule:** every row claimed for wave N must be closed, or explicitly re-deferred with a reason, before wave N can be declared complete. That is a wave exit criterion, not a suggestion.

Opened after Wave 0's final whole-branch review, 2026-08-11.

---

## Wave 1 — blockers (must be the first task, before any asset lands)

These share one defect class: **the gate's failure mode is to pass.** Close them together; fixing only some leaves live instances of the same class behind.

| # | Finding | Where | Why it matters |
|---|---|---|---|
| W1-B1 | Art gates match only `.tres` / `.res` / `.material` / `.mesh` | `tests/framework/asset_scanner.gd` `MATERIAL_SUFFIXES`, `MESH_SUFFIXES` | The asset pipeline builds models with Blender Python scripts. Whatever it exports — `.glb`, `.gltf`, `.blend` — is invisible to all three gates. The first real models would enter the repo with every gate green having inspected nothing. |
| W1-B2 | `.tscn` absent from both suffix lists | same | Materials and meshes embedded as scene sub-resources are never loaded, so never checked. |
| W1-B3 | `ShaderMaterial` silently exempt | `test_palette.gd`, `test_shading_features.gd` type filter | Not a `BaseMaterial3D`, so it skips both gates entirely. Decide: ban it, or give it its own check. |
| W1-B4 | `_violations()` never reads `albedo_texture` | `tests/art/test_shading_features.gd` | The Art Bible's ban on colour gradients is **currently unenforced**. A gradient-albedo material passes both gates whenever its `albedo_color` happens to be on-palette. |
| W1-B5 | Topology iterates `BUDGETS.keys()`, not `SCAN_ROOTS` | `tests/art/test_topology.gd` | A mesh outside those four folders has no budget and passes silently. |
| W1-B6 | Unloadable assets are silently exempt (`resource == null → continue`) | all three gates | A corrupt `.tres` prints an engine error and passes every gate. Make it an offender, not a skip. |
| W1-B7 | `_triangle_count` returns 0 on an internal abort, which reads as "within budget" | `tests/art/test_topology.gd` | A gate whose failure mode is "pass" needs its counter to be total. |

## Wave 1 — decisions owed

| # | Finding | Why now |
|---|---|---|
| W1-D1 | **Decide what `ServiceRegistry` is for, in code.** It has six tests and **zero production callers**. The first system that needed a collaborator (`WorldClock` → `EventBus`) routed around it with a node-path lookup. What actually made Wave 0 testable was constructor injection. | Either every autoload self-registers in `_ready()` and every system resolves through it, or delete it and standardise on injection. Leaving it unused is the worst option — it looks like architecture and isn't. |
| W1-D2 | **`definition_loader.gd` has no implementation.** Listed in System Map §1, deferred through Wave 0 for want of a consumer. | Wave 1 is its first real consumer. |
| W1-D3 | **Reference integrity is unvalidated.** `forced_weather_event`, `beacon_unlocked`, `primary_lighting_preset`, `allowed_weather_events`, `watch_stat`, `target_stat` are bare `StringName`s that nothing resolves or checks. A typo is a silent no-op today. | Land a gate with `definition_loader.gd`: load every `.tres` under `data/` and assert every id-shaped field names an existing definition. |
| W1-D4 | **Machine-check the exit criteria.** Three of Wave 0's seven were enforced by a human reading output, and two of those three were violated while being reported met. | Each is ~15 lines: a `MINIMUM_TESTS` floor (done), a scan of `src/` + `data/` for `Color(`, and a game-noun scan of `src/core/`. The criteria list grows every wave. |
| W1-D5 | **The game-noun criterion is the wrong shape of check.** A word list caught the named instance but missed `service_registry.gd`'s "the other nine" — a real coupling violation no word list can detect. `event_bus.gd:3` and `service_registry.gd:4` still name this project's autoload registration. | Restate it as a property (`src/core/` must not reference this project's systems, count, or names) and decide how to check that. |
| W1-D6 | **`MINIMUM_TESTS` is manual and will rot.** Set to the exact current count, so it has zero slack. | Consider deriving it, or accept the maintenance and note it in the wave checklist. |

## Wave 1 — small, cheap

| # | Finding | Where |
|---|---|---|
| W1-S1 | `get_service()` returns a raw `Object`; a freed Node stays registered and `has()` keeps returning true, handing callers a dangling instance | `src/core/service_registry.gd` — add an `is_instance_valid()` check |
| W1-S2 | No test that `get_service()` returns null after `unregister()` | `tests/unit/test_service_registry.gd` |
| W1-S3 | No `subscriber_count > 1` assertion for multiple distinct callbacks | `tests/unit/test_event_bus.gd` |
| W1-S4 | No self-check for `assert_false` / `assert_not_null` *outcomes* (the counter path is covered) | `tests/unit/test_framework_selfcheck.gd` |
| W1-S5 | `find_test_scripts`'s recursion and dotfile-skip have no direct test | `tests/unit/test_test_discovery.gd` |
| W1-S6 | Generated `.tres` carry no `uid://`; the editor rewrites all of them on first open, producing a dirty tree Wave 1 did not cause | `data/` — settle **before** the first editor session |
| W1-S7 | `configure()` hardens state *names* but not *shapes*: a non-Array value for a transition key aborts with a `SCRIPT ERROR` instead of returning `false` | `src/core/state_machine.gd` |
| W1-S8 | `load_schedules([])` then `start()` emits `day_started` for a day that does not exist | `src/systems/world_clock.gd` — `definition_loader.gd` will be the first caller that can pass empty |
| W1-S9 | `EventBus` has no re-entrancy guard; a handler emitting its own event recurses unbounded | `src/core/event_bus.gd` |
| W1-S10 | `ModifierStack.add(null)` crashes; no enumeration API, so a HUD cannot render *why* a stat is moving; `remove_by_source` is the only removal, so two effects from one system need composite source ids | `src/core/modifier_stack.gd` |

## Wave 2 — before the survival system is built

| # | Finding |
|---|---|
| W2-1 | **`StateMachine` has no data home for state graphs.** Nothing in `src/definitions/` can express states or transitions — `ThreatDefinition` carries perception ranges and speeds, not a graph. And `StateMachine` has no per-state behaviour hook, only `state_changed(from, to)`, so consumers will `match` on state names, which *is* new behaviour code per entity. **Wave 5's "a third threat needs zero new behaviour code" is not supported today.** A ~15-line `behaviour_definition.gd` costs nothing now and is the difference between that criterion being true and being a slogan. |
| W2-2 | `ModifierStack`'s NAN sentinel cannot distinguish "OVERRIDE of NAN" from "no OVERRIDE". A `has_override` bool is strictly better and free. Do it when `SurvivalSystem` first uses OVERRIDE. |

## Wave 3 — with lighting and the first rendered frame

| # | Finding |
|---|---|
| W3-1 | **Warmth-budget art gate (≤ 0.5% warm pixels).** Deferred from Wave 0 because it needs a rendered frame. Must be Wave 3's first task. |
| W3-2 | `ColorBible.contains()` allocates a fresh 12-element array per call. Only matters if the warmth gate calls it per pixel — fix with that gate. |
| W3-3 | A `DaySchedule` with a zero-length phase ends the run instead of skipping the phase; `phase_duration()` cannot distinguish "no schedule left" from "this phase is 0 seconds". |
| W3-4 | A weather event's *tell* has a duration but no sound, visual, or lighting hook — and the mandatory tell is a design pillar. Not expressible in data yet. |

## Wave 5 — threats

| # | Finding |
|---|---|
| W5-1 | Threat perception is three enum kinds with fixed scalar ranges. The System Map's `PerceptionModule` / `EngagementBehavior` composition, and the "wolf pack group behaviour" case, have no representation. |

---

## Closed

Fixed during Wave 0's final fix wave (`3f30a1e`), recorded so they are not re-raised:

game nouns in `src/core/modifier.gd` and the `src/core/` sweep · off-palette `ambient_color` default in `lighting_preset.gd` · `_round_trip` disarming the zero-assertion guard · no minimum-test-count floor · `configure()` not validating the transition table · no regression test for the `/root/EventBus` wiring · `Modifier` carrying no target stat (`StatModifier` added) · undocumented single-payload contract on `EventBus` · no test locking `configure()`'s deep copy · vacuous `ItemDefinition.category` assertion · nested modifier arrays never round-tripped · inconsistent `.uid` tracking.

Dropped as not real issues, with reasons, in Wave 0's final review triage: unreachable null guard in `test_methods` · a garbled subtotal in a gitignored report · `register()` overwriting silently (load-bearing for fake injection) · `_write()` missing a null check · two report arithmetic wrinkles · hardcoded hex in *tests* — a test asserting "`#8FB0D8` is in the palette" **must** hardcode the literal, since reading it from the resource under test is circular. The criterion is restated as: **no hardcoded colour in `src/`, `data/`, `scenes/`, `assets/`; tests may hardcode expected values.**
