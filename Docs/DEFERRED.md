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
| ~~W3-8~~ | **PARTLY CLOSED.** The owner supplied five takes and `tools/build_ambience_loops.py` has cut them into seamless loops in `assets/audio/ambience/` — `wind_low` 16.0 s, `wind_mid` 3.6 s, `wind_high` 4.6 s, `snow_fall` 5.4 s, `fire` 12.0 s, all 16-bit mono PCM with `edit/loop_mode` set to Forward and the join verified against each file's own adjacent-sample distribution. **Still owed: the six weather one-shots** in `assets/audio/weather/`, named `weather_tell_<event id>` for the six events in `data/weather/`. Also still owed and unchanged: the caws in `assets/audio/wildlife/crow/`. |
| W3-10 | **`wind_mid` is 3.6 s and that is the material, not a choice.** The take supplied as `wind_low.wav` is one 1.2 s gust with a 4.5 s decay whose second half measures 97% in 250–800 Hz — a ringing tail rather than air. Flattening its envelope bought 3.6 s of usable loop; nothing buys more. The layer is present ~24% of a valley day in bursts of a few seconds, so it is heard for one or two cycles at a time and the repeat is tolerable — but a longer mid take would be the single biggest improvement to the bed, and it is a file rather than any code. |
| W3-11 | **`fire_gain_db` is the one level derived entirely from measurement with no ear on it.** The supplied fire take has a 36 dB crest, so its peak reaches the ceiling while its average sits 17 dB under the wind loops; the map corrects for that with a +16.9 dB figure computed from BS.1770 loudness. The arithmetic is right and the result is unverified. It is also the only layer heard at close range, indoors, for minutes. One `.tres` number. |
| W3-9 | **冻雨 has the weakest audible half of the six weathers, and it is a data problem rather than a code one.** Its tell moves `snowfall_rate` 0.12 → 0.50, which the snow bed layer hears, and its `wind_speed_multiplier` of 1.1 scales `gale_metres` rather than `strength()` — so the **wind bed cannot hear it at all**. GDD §7's actual tell is 落雪声变脆, a change of TIMBRE and not of level, and a layer keyed on the rate alone can only get louder. The honest fixes are both data: give the event its own `WindMap` so the air changes as well, or author a second snow layer whose window sits above the blizzard's so "brittle" is a different file rather than a louder one. Nothing in `src/` needs to change for either. |

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

> **已关闭。门禁是 `tests/art/test_shader_compiles.gd`，四次运行的证据在
> `.superpowers/sdd/wave3/task-w3-shader-gate-report.md`。**
>
> **但下面记的机制是错的，而按那个机制写的那一行修法什么也修不上。**在 4.7.1 上重新量过：
>
> - **着色器是在资源加载时同步编译的**（`Shader.set_code()` → `RenderingServer.shader_set_code()`，
>   连 dummy 驱动也在那里解析并报错，`servers/rendering/dummy/storage/material_storage.cpp:192`）。
>   **不牵涉任何一帧。**把 `aurora_sky.gdshader` 按当初那个 `return` 重新弄坏，**在 HEAD 上、
>   不动框架一个字，套件直接就红了**——因为 `test_system_graph.gd` 自己会加载它。
> - `RenderingServer.force_draw()` 在 `--headless` 下能跑、且是安静的；在一个已经加载了的坏
>   着色器旁边调用它，**不多打印一个字**。所以它**没有被加进去**：一条无法演示自己会响的
>   门禁代码，正是这道门禁存在的理由所要终结的东西。
>
> **真正看不见的比"着色器"这个词窄，也更糟：没有任何测试加载过的着色器，从来没有被交给
> 渲染服务器，因此从来没有被解析过。**在 HEAD 上把九个项目着色器全部弄坏量了一次：七个报错，
> 两个一声不吭——`chimney_smoke.gdshader` 和 `montage_film.gdshader`。而只把
> `chimney_smoke.gdshader` 弄成语法死的，套件报 **1842 passed / 0 failed、退出 0、控制台干净**。
> 它就是每一帧画在农舍上的那道烟。
>
> 顺带量到的一件事值得单独记住：**九个着色器全坏的那一次，runner 自己的计数仍然是
> 1842 passed / 0 failed。**那七个报错**全部**是 `tools/run_tests.sh` 读控制台抓到的，
> 没有任何一条来自测试的断言。
>
> 门禁上线后对全项目跑了一遍：**九个项目着色器全部编译通过，零个被点名**；两个 addon 着色器
> 另行单独验过，也通过（它们被刻意排除在门禁之外，理由写在文件里）。

由集成覆盖那轮（`ac7183d`）发现，**不是假想的**。以下是当时的原始记录，保留以存档。

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

> **第一条已关闭。**`test_system_graph.gd` 增加了一条**对着源码**的全项目检查：`res://src` 下
> 每一个**声明**了 `set_wind` / `set_wind_strength` / `set_snowfall_rate`，或同时声明了两个
> wildlife 钩子的 `.gd`，都必须出现在 `PROJECT_*_CONSUMERS` 上。静态扫描能看见一个**从来没有
> 被任何测试实例化过**的脚本，这正是运行时图检查够不到的那一半——环境音那次就在图外。
>
> 量出来的实况：全项目有 **11 个脚本声明风词汇**（16 处声明），图里只列了 3 个；**8 个在图外**，
> 其中包括 `chimney_smoke.gd`、`spindrift.gd`、`wind_sway.gd`、`wind_pendulum.gd`、
> `snowfall_layer.gd`、`breath_fog.gd`、`snow_load.gd`、`bird_flock.gd`。把项目名单临时缩回图
> 的三个，这条检查**红了 13 次并逐个点名文件**——这是它的 RED 证据。
>
> 它看不见的（写明而非假装覆盖）：从基类**继承**而非声明的钩子，以及运行时装上去的方法。
>
> **第二条（`_step()` 漂移）没有做，而且不便宜。**要让它不再是模拟，就得让套件在测试之间真的
> 过帧；而整个套件跑在 runner 的**一次** `_process()` 里（见 `test_runner.gd` 的注释，那个位置
> 本身是承重的）。那是对 runner 结构的改造，不是一条断言，应当单独排期。

---

## Director 裁决 — 极光的代价保留，并且永远不许挂奖励（`28de56b` 引出）

`NightExposure` 使入夜后寒冷加倍，而极光只在夜里出现。所以照实现，**这个游戏里最美的东西，看它是要付代价的**。实现者列了四个缓和选项、一个都没擅自采用。

**裁决：保持原样，一个字都不改。**

理由：**免费的美是装饰，有代价的美是一个选择。**而地面泛光已经把它从陷阱变成了选择——玩家先看见雪泛绿、知道有事发生，然后自己决定要不要停下来抬头。他不是被骗着挨冻的。这个结构已经对了，任何缓和都是在把选择改回装饰。

支撑这个判断的两个实测数字：**不到一半的 run 会出现，每次持续 2.4–3.4 分钟。**绝对代价很小，所以"保留代价"不会变成惩罚；稀有度又保证它不会因常见而失去分量。**这两个数字任何一个被改动，这条裁决必须重算。**

### 附带的守卫：不要给它挂奖励

**未来不得把"观看极光"接到任何数值收益上，尤其不得恢复精神值。**

现在写下来，是因为这个提议一定会出现：极光只在第 3–5 天出现，正是玩家最难受的时候，而五条状态里恰好有"精神"这一条。

**那是错的，而且错得隐蔽。**一旦看极光给数值，玩家站在那里就不再是因为它美，而是因为 +精神；**代价也随之从"牺牲"降级成"价钱"**——不再是在冷与美之间做选择，只是在付费买 buff。这个游戏最好的三分钟会变成一个有漂亮皮肤的杂活。

它现在的样子已经在说一句只有沉默能说的话：整个游戏是一个想弄死你的世界，而在第四天的夜里，它做了一件和你完全无关的、漂亮的事，并且看它要收你的钱。**那就是第三支柱（沉默即叙事）本来的意思，它不需要一个机制来替它说。**

---

## Director 裁决 — 沙漏在 0.500 处的窄弦予以接受，并且不许放宽门槛（`a676819` 引出）

`fatigue` 改画为沙漏之后，在 `tools/measure_icon_fill.py` 的二十个填充步里**恰好有一步**低于 0.30 的弦宽下限：**填充 0.500，液面正落在沙漏的腰上，实测 0.26**。三次独立生成分别是 0.25 / 0.27 / 0.26 —— **这是这个物体的几何，不是提示词没调好**，再生成多少次都一样。

**裁决：接受这一步，不改图标，并且明确禁止为它放宽下限。**

理由是这条下限**量得对，但对这个形状问错了问题**。它存在的目的写得很清楚：抓那种**消失的末梢**——火焰的尖、闪电的尾——液面横切过去，那里根本没有墨可切，于是数值无处可读。那是形状的**意外**。

**而沙漏的腰不是意外，它就是这个物体本身。**液面停在腰上是沙漏最好认的一个状态——下半球全满，线卡在最细处，一眼就是「过去一半了」。用"末梢消失"的尺子去量一个"刻意的对称收束"，量出来的数字是准的，它回答的却是另一个问题。这一类在简报里已经有条目（**正确的测量回答了错误的问题**），这是又一个实例。

两个支撑事实：**0.500 是显示区间的上端**，也就是这条读数**开始出现**的那个值，所以它是玩家看到最多的一个状态；而它恰恰是读得最清楚的那个状态。

### 守卫：不许用放宽下限来解决它

**这条下限一个字都不许动。**简报里已经记着同一个陷阱的另一次发作：缩放门禁对四个角色全部误报，而**「把区间放宽到它们都能过」会顺手放进那只 15 毫米的狼**——正是那道门禁存在的理由。

所以这是一条**逐个具名、附带理由的豁免**，不是一个被调低的阈值。**如果将来又有别的图标需要同样的宽限，那是下限本身有问题的证据，而不是把这条豁免扩大的理由**——那时要重新审的是尺子，不是被量的东西。

**重算条件**：`fatigue` 不再是沙漏，或者显示区间变动、0.500 不再是上端。任一条成立，这条裁决作废重议。
