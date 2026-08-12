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

## 已安装但尚未采用的第三方资源

两样东西装在项目里，都**有意暂不使用**。记在这里，免得日后有人以为它们已经在用，或者忘了它们存在。

| 资源 | 状态 | 何时重估 |
|---|---|---|
| **GodotGAS**（纯 GDScript 的 Gameplay Ability System） | 已装、**已停用**。它注册的 `GameplayCueManager` autoload 在 `--script` 下也会跑，而其内置 `.tres` 引用作者机器上的 UID，导致每次测试运行都产生两行 `WARNING:`，套件因此在 248/0 全绿时仍退出 1 | **波次 4** |
| **Free RPG Character Animation Sample Pack**（64 个 FBX，39 MB，解压在项目根目录） | 未使用。骨架与 Meshy 角色不同，需跨骨架重定向 | 按需 |

**为什么 GAS 暂不采用**：它提供 attributes、gameplay effects、tags，而波次 0 已经建成 `StatDefinition`、`Modifier`/`ModifierStack`（含按槽位过期、按来源移除、三种运算）与数据配置的 `StateMachine`，并有测试覆盖。现在引入意味着要么**并存两套属性系统**——数值从哪来会变成日常困惑——要么**删掉可用且有覆盖的代码**换一套等价物。两者都是净损失。

它真正可能划算的时点是**波次 4-5**：点信标、劈柴、开枪一旦需要冷却、前摇、打断、互斥标签，GAS 的那套会比手搓强。**接入一个能力层，远比现在替换属性层便宜。**

**为什么 RPG 动画包暂不使用**：它与缺失清单的交集是 `Getup1`、`Pickup`、`Idle` 系列，但熊击倒动作**本身已包含起身**（击中→抛出→翻滚→手膝撑地→站起），`道具交互` 已由新 Meshy 包提供。跨骨架重定向是真实工作量且结果常不理想，为已被覆盖的动作付这个成本不划算。将来若需要 Meshy 生不出的具体动作（睡觉躺下、劈柴挥斧），它是现成来源。

**待办**：动画包目前**解压在项目根目录**（含 `__MACOSX` 残留），Godot 每次导入都会扫这 64 个 FBX。应移入 `assets/source/animations/` 并加 `.gdignore`。等并行任务结束后处理，现在移动会让正在跑测试的 agent 撞上重导入。

---

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

---

## Wave 2 — from the interior reveal (`5863467`)

The SDD workspace is gitignored and gets deleted at wave end, so the parts of
that agent's report worth keeping are copied here.

| # | Finding |
|---|---|
| W2-1 | **The porch roof hides the door at 45°.** The door was built to swing, and at our fixed camera angle the swing barely reads — what the player actually perceives is the reveal firing or not firing. Not worth animating better; worth deciding whether the porch roof should be shortened, or the door moved to a wall the camera can see. An art call, not a bug. |
| W2-2 | **`MINIMUM_TESTS` is a floor, not a census.** Set to 533 = 467 + that agent's own 66, deliberately *not* to the observed total, because three other agents were adding and removing test files concurrently and a floor including their in-flight work would false-alarm on them. Whoever closes Wave 2 should re-baseline it once against a quiet tree. |
| W2-3 | `tests/art/test_warmth_budget.gd` does not exist yet, and W3-1 above schedules it. When it is written it **must** stat warm pixels per region, not per frame — see the Director's ruling appended to Art Bible rule 12 (`ff48b9a`). A whole-frame ratio would fail every interior shot by design. |

**Acted on, not deferred** — and the diagnosis was wrong, which is the part worth
keeping. The reveal agent reported the farmhouse floor buried under up to 0.59 m
of snow with the player floating 0.39 m above it, and the Director dispatched
W2-J as "the snow height field does not know buildings exist."

The implementer measured the site before writing anything and found **the snow in
the main room is 7 mm deep**. What buries the floor is the *bare ground*: the
house stands on a wind-scoured crest that runs 0.6 m over the floorboards.
Carving snow alone would have changed nothing in the room that needed changing.

So a building now levels the ground to its own floor **and** keeps the snow off
it — both writes into rasters the field already had, no shader opened. Snow over
the floorboards went from 240 of 252 sample points to 6, all of them the doorway
drift. Fixed in `29bfada`.

**Two lessons, both already paid for twice:** a symptom reported in metres is not
a diagnosis, and the agent standing in the scene with a probe outranks the
director reasoning from a screenshot. The same correction happened earlier with
the "character lying down" report, which measurement showed was flat shading plus
a 45-degree camera, not a broken take.
