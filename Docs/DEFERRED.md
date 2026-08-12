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
| ~~W3-4~~ | **CLOSED** by `src/definitions/weather_tell.gd` + `src/systems/weather_system.gd`. A tell now names a sound, a lighting preset with a lead fraction, a `WindMap`, a snowfall rate and whether the birds go up — all as data, all on hooks that already existed. `tests/unit/test_weather.gd` fails any shipped event whose tell cannot be read with the sound off. |
| W3-5 | **寒流's 燃料消耗 ×2 has nowhere to land.** GDD §7 doubles fuel burn during a cold snap. `FuelEconomy` owns the store and `Stove` owns the burn, and neither takes a rate modifier — fuel is not a `StatDefinition`, so `WeatherEventDefinition.stat_modifiers` cannot express it either. The event ships with its temperature drain only; the doubling is absent, not merely unwired. Whoever gives `Stove` a burn-rate modifier should take it by source id, the way `SurvivalSystem` does, and `WeatherSystem._apply_modifiers()` becomes two lines. |
| W3-6 | **`extinguishes_beacons` is published and nothing consumes it.** `weather.arrived` carries `extinguishes_beacons` and `min_beacons_extinguished`, which is GDD §7's "暴雪 必定吹灭至少一座信标". There is no beacon system yet (`BeaconDefinition` exists, nothing runs it), so the storm currently blows nothing out. The payload is the seam; the subscriber is Wave 4's. |
| W3-7 | **Only three of the six lighting presets are weather.** `pale_day`, `nightfall` and `whiteout` are looks a weather can wear; `sunrise` is a dawn, `deep_night` is a night, and `flat` is the debug reference (`test_lighting_presets.gd` says a day using it would be "a day with no weather"). So 冻雨 and 雪雾 both land on `nightfall` and are told apart by their snow, wind and visibility rather than by the sky. Authoring a weather-specific preset is pure data for `LightingDirector` — it scans the directory — but `test_the_six_presets_of_the_art_bible_all_ship` asserts exactly six, and a seventh would also need a `Snowfall.storm_by_preset` row, which is a `.gd` default. That last coupling is the real blocker and is worth one line of thought before Wave 4 adds a look. |

## Wave 4 — with the procedural terrain

| # | Finding |
|---|---|
| W4-1 | **The snow field has no middle.** Measured on the shipped `SnowField` by the footprint agent (`c332434`) and re-raised by the contrast investigation (`task-w2-contrast-report.md`): the world is **35% bare** and **41% past the wading gate**, and there is **no 12 m square anywhere in it whose mean depth falls between 0.02 m and 0.32 m**. The middle of the depth range effectively does not exist. Every behaviour that was tuned against depth is therefore close to binary in practice — print size and core (`print_thin_scale`, `print_core_thin`/`_deep`), the scuff, the furrow gate (`furrow_depth_start_m` 0.42), and the trudge speed all interpolate across a band the world does not contain, so they read as two states with a step between them rather than as a range. This is a terrain-**generation** problem, not a consumer problem: nothing downstream can be tuned out of it, and each of those four systems will look wrong in a different way until the distribution has a middle. Belongs with Wave 4's procedural work; the four consumers should be re-tuned *after* it, not before. |

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

## Wave 2 — from roads and dynamic accumulation (`b9e1490`)

| # | Finding |
|---|---|
| W2-4 | **At full accumulation the roofs go white and the buildings lose their silhouette.** Compare `roads-snow/road-00.png` with `road-03.png`: at day 1 the farmhouse reads as a dark shape with pale roof panels, and at full accumulation the roof is white and only the vertical walls still carry the shape. The Art Bible's whole value logic is dark solids against bright snow, so this is the composition weakening at exactly the point in the seven-day arc where the picture should be at its most desperate. Not a defect — arguably the correct narrative, the world being buried — but it must be judged with the day-1-to-day-7 arc played end to end, not from single frames. Whoever owns that playthrough owns this call. |
| W2-5 | **Day 1's pitched roof carries no shader snow**; only flat tops accumulate at that level. The implementer asked whether it should start sooner. **Director's ruling: no.** A steep roof shedding snow is real, and the dark pitch is what makes the house read against the field. One constant if this is ever revisited. |
| W2-6 | **No roof cap mesh shipped, deliberately.** Every model that needs one already carries geometry for it (the farmhouse's six roof slabs, the shed and well-house slabs, the truck's three panels, the pole's crossarm plate) and the shader grows snow *between* them. Growing a cap would need vertex displacement, which cracks every hard edge on these split-vertex models. Accepted; recorded so the style document's roof-cap line is not re-raised as an omission. |

---

## Director 裁决 — `SurvivalSystem` 的作用域（`0cef365` 引出）

火源可发现性那轮报告指出：`survival.threshold_crossed` / `stat_depleted` / `stat_recovered` / `died` 全都只说是哪条数值，**从不说是谁的身体**。它称之为"最大的一处潜伏实例"，并且正确地判断这不是改载荷能解决的——它取决于 `SurvivalSystem` 是否继续是一个全局 autoload，而这个问题必须在波次 5 给饿汉真正的饥饿之前回答。

**裁决：`SurvivalSystem` 保持玩家专属，并且必须把这件事明写出来。**

理由：

1. GDD §5 那五条互相咬合的状态是**玩家的游戏体验本身**——体温、疲劳、饥饿、精神、冻伤。熊不需要 `core_temperature`，僵尸不需要疲劳。把这个模型泛化到所有生物身上，是为一个不存在的需求付架构代价。
2. 一旦确认它是玩家专属的，那些事件就**不存在歧义**——它们永远在说玩家。缺失的主语不是缺陷，是未被写下来的前提。
3. 将来某个威胁真的需要状态模型时，它应该拿到一个**为它自己造的、小的**模型，而不是把这个撑大。

**要做的**：在 `SurvivalSystem` 的类文档里写明作用域，并在事件命名或文档中让这个边界可见。**不要**为了假想的通用性去加主语字段。

**与已知问题的关系**：波次 5「零新增代码」目标本就被登记为当前架构不支持（`StateMachine` 无数据化状态图）。威胁的状态模型是同一个问题的另一面，两者应当一起解决，而不是各自打补丁。

---

## 框架 — 第七类假通过：整个套件看不见坏掉的着色器

由集成覆盖那轮（`ac7183d`）发现，**不是假想的**。

**着色器在更晚的一帧编译，而整个测试套件活在第一帧之内。**所以一个语法上已经死掉的 `.gdshader` 可以：每一次真实运行都在控制台报 `SHADER ERROR`、把画面画错或画不出来，**而套件停在 1324 passed / 0 failed，控制台门禁也一个字都抓不到**。

发现方式：一个 tick 到第一帧之后的探针，立刻打印出

```
SHADER ERROR: Using 'return' in the 'sky' processor function
```

——来自当时另一个 agent 正在写的 `aurora_sky.gdshader:296`。

**这一类的规模**：这个项目的美术方向几乎全部压在着色器上（雪地、cel 两段、积雪、雪壳、遮挡淡化、烟、天空、极光……）。它们当中任何一个的编译失败，今天都是不可见的。

**修法已知且只需一行**：在测试框架里 `RenderingServer.force_draw()`，把 tick 推过第一帧。

**为什么还没做**：发现它的 agent 刻意没有加，理由正确——当时极光的着色器是未提交的在飞状态，加上去等于**把别人未完成的工作变成所有人的红套件**。这是对门禁的改动，不是对某个测试的改动，所以由 Director 排期。

**执行条件**：等着色器工作线全部落地、工作区安静时加。加完之后必须验证它真的会红——把一个已知的坏着色器放回去，确认套件失败并指名文件。**一个复现不了它所要防的缺陷的门禁，本身就是下一类。**

**同轮记录的两条较小缺口**：词汇规则检查的是那七个系统组成的**图**，不是整个**项目**——那十个在图外的系统上若出现一个走神的 `set_wind()`，仍然看不见；以及 `_step()` 是对引擎 tick 的模拟，会和真实 tick 漂移。
