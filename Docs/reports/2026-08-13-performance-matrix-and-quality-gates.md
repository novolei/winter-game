# D3D12 performance matrix and fixed-camera quality gates — 2026-08-13

## Status

`DONE_WITH_CONCERNS`. The requested four 60-second scenarios and the three
fixed-camera visual gates were recovered, audited and made repeatable. The
measurements establish a strong RTX 5090 baseline, but they do **not** certify a
low-end or mid-range target: the Godot editor remained open during collection,
the moving runs each contain a rare unexplained hitch, and no representative
target GPU was available.

## Environment and protocol

- Godot 4.7.1 stable, Forward+, D3D12, Windows, 1600 x 1000.
- Adapter: NVIDIA GeForce RTX 5090.
- Fixed `run_seed`: `20260813`; five real-time seconds of warm-up, followed by
  60 real-time seconds of sampling.
- The user's GUI editor remained open (`editor_open=true`). No second game or
  competing capture ran. These are useful development measurements, not the
  canonical clean-machine acceptance run.
- Frame duration is elapsed real time. The recovered JSON used the Windows
  system clock; the finalized harness uses monotonic `Time.get_ticks_usec()` so
  clock synchronization cannot move the shutter. Godot Performance monitors
  record engine process/physics/draw/memory values. The four labels
  describe the requested workload and initial snow choice: the seeded live
  field is not replaced by a constant-depth test surface, so the routes cross
  naturally varying depths.
- Evidence JSON and PNG files remain in `%TEMP%`; generated captures are not
  product assets and are intentionally not committed.

## Four-by-sixty-second result

| Scenario | Frames | frame p50 | p95 | p99 | max | >=33.3 ms | >=50 ms | distance | actual depth p50 / p95 | Track upload p99 / max | Track bytes / 60 s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| stationary | 9,601 | 6.000 ms | 8.000 ms | 8.000 ms | 27.000 ms | 0 | 0 | 0.44 m | 0.031 / 0.031 m | 0.185 / 0.424 ms | 519,937,728 |
| shallow straight | 9,558 | 6.000 ms | 8.000 ms | 9.000 ms | 239.000 ms | 2 | 1 | 91.38 m | 0.342 / 0.597 m | 0.274 / 0.958 ms | 1,063,917,292 |
| deep straight | 9,584 | 6.000 ms | 8.000 ms | 9.000 ms | 95.000 ms | 1 | 1 | 102.69 m | 0.464 / 0.592 m | 0.340 / 1.537 ms | 2,302,996,532 |
| deep diagonal | 9,566 | 6.000 ms | 8.000 ms | 9.000 ms | 233.000 ms | 1 | 1 | 110.22 m | 0.390 / 0.598 m | 0.358 / 2.218 ms | 2,356,628,320 |

The p99 baseline is 8–9 ms in all four cases, and the chunked TrackMask path
remains below 2.22 ms even at its observed maximum. At the same time, every
moving scenario contains at least one >=50 ms frame. Therefore this evidence
does not support a claim of hitch-free movement or "perfect low-end" operation.

Two interpretation limits matter:

1. `shallow straight` starts at 0.045–0.059 m in the audited runs but crosses
   the real seeded distribution; its 60-second p50 becomes 0.342 m. It is a
   shallow-print workload over the live field, not sixty seconds constrained
   to shallow terrain. The deep runs spend most of their time in medium/deep
   snow, as their p50/p95 values show.
2. The nominal stationary run settled by 0.44 m and the shipping systems still
   uploaded TrackMask layers. It is a real idle-scene baseline, not a frozen
   synthetic camera benchmark.

The observed TrackMask transfer rate is approximately 8.7 MB/s stationary,
17.7 MB/s shallow, 38.4 MB/s deep straight and 39.3 MB/s deep diagonal. That is
far below the former multi-megabyte-per-footprint behavior, but still needs a
real low-bandwidth target before it can be called harmless on low-end hardware.

## Hitch diagnosis added and measured

Every wall-clock frame over 33.3 ms now records:

- elapsed time and frame index;
- engine-reported process time;
- SnowField origin, same-frame recenter flag and recenter duration;
- TrackMask same-frame flush flag, layer count, byte count and upload duration;
- player position.

The short reruns used the same editor-open D3D12 conditions:

| Diagnostic | p50 / p95 / p99 | long-frame evidence |
|---|---:|---|
| shallow straight, 30 s | 6 / 8 / 8 ms | 210 ms at elapsed 0.924 s; process monitor 6.418 ms; no recenter; no Track flush, 0 B |
| deep diagonal, 30 s | 6 / 8 / 9 ms | 184 ms at elapsed 0.887 s; process monitor 11.651 ms; no recenter; Track 1 layer, 264,196 B, 0.064 ms |
| deep diagonal, same run | — | 34 ms at elapsed 2.679 s; recenter 24.585 ms; Track 4 layers, 1,056,784 B, 0.187 ms |

An earlier clean 60-second diagonal run recorded 233 ms at elapsed 0.931 s
with a 26.984 ms recenter and no Track upload. The recenter can contribute to a
near-budget frame, but 27 ms cannot explain a 233 ms wall frame by itself. More
importantly, the new 184–210 ms early hitches occur with no recenter at all and
negligible or zero Track work. A separate 12-second shallow probe likewise
found a 120 ms frame with no recenter and no Track upload.

**Finding:** SnowField recenter and TrackMask upload are not the root cause of
the large early-session stalls. Their repeated time near 0.9 seconds after the
measurement shutter opens is a lead for a resource/shader/streaming or external
driver stall, but current evidence does not identify which one. Godot's process
monitor also does not account for most of the wall gap on those frames, so a
RenderDoc/PIX capture or explicit first-use instrumentation is the next honest
step. No production system was changed on this inference.

## Fixed-camera shadow, fog and blizzard gate

All captures are 1600 x 1000, use the same shipping camera and seed, and change
only the disposable scene instance's authored lighting preset and snowfall
rate. The tool contains no quality-tier switch and writes no ProjectSetting.

- `pale_day`: character, building, footprints and long cast shadows remain
  distinct; no blank surface, broken fog or missing shadow was observed.
- `deep_night`: the cold silhouette and scarf accent remain readable without
  flattening the whole snowfield to black.
- `whiteout`: contrast and distance readability are deliberately reduced, but
  player and nearby structure remain identifiable and the snowfall population
  is visibly present.

This is a visual-regression gate only. It does **not** authorize a quality tier
as the default and it does not compare low/medium/high profiles. Every future
profile must pass these same three fixed shots before default enablement.

## Evidence integrity

Accepted evidence hashes:

| File in `%TEMP%` | SHA-256 |
|---|---|
| `winter_perf_stationary_editor_open.json` | `df53e35fc2124cfed902130ee40b42945f12f0f320ed54b9fc38856e0bb4fca7` |
| `winter_perf_shallow_straight_editor_open.json` | `89035306b843571421b95134ddd51092cd06d48933452e72f84a5d2de7ced8ce` |
| `winter_perf_deep_straight_editor_open.json` | `7fbdf27c1ce0b4f40bdd822ba8c45b237e23867dd6cbe1f9d7677996c9bf6d8d` |
| `winter_perf_deep_diagonal_clean_rerun.json` | `8bf57f5f9617d89dc9215091da24e9bcaff86ad374793680b9910ead30d08914` |
| `winter_perf_shallow_diag_final_30s.json` | `b7e1af9a3733b8f7ac747235c625d7d90b8a0ea5619f2a32195401844c19371e` |
| `winter_perf_deep_diagonal_final_30s.json` | `689c736682bd8e97a349b9f83877fc9c4233ebc922d4df5a4e26b250bbaf9fa9` |
| `winter_quality_pale_day.png` | `27d8a2cd48b2b20958e88dee8155e8123bc931f3d419a76bcc2960f2ef37443b` |
| `winter_quality_deep_night.png` | `9609f2c2701b6a946e6259792385431822d6d6536a24fb44caa7f061a5f89c70` |
| `winter_quality_whiteout.png` | `41d7a87dbad727422bb33bf7be7111d5de5ccda43bc63fec911ad0021eea5041` |

The four files under
`%TEMP%/winter_perf_matrix_concurrent_20260813_1648/` are explicitly rejected:
four D3D12 games were launched concurrently and each JSON contains only one
sampled frame. They are not used anywhere in this report.

## Repeatable tooling

- `tools/performance_matrix_60s.gd` and `.tscn`: the real-scene sampler.
- `tools/run_performance_matrix_60s.ps1`: the canonical sequential runner. It
  refuses to run while any Godot editor/game process exists, then collects four
  60-second JSON files and three visual captures.
- `tools/capture_visual_quality_gate.gd` and `.tscn`: fixed-camera evidence.
- `tests/unit/test_performance_matrix_harness.gd`: guards scenario duration,
  seed, requested metrics, TrackMask resolution contract, per-hitch fields,
  three visual presets and the canonical runner's clean-session refusal.

## RED / GREEN evidence

**RED (evidence audit, before the diagnostic extension):**
`winter_perf_deep_diagonal_clean_rerun.json` contained a 233 ms event with only
elapsed time, frame time, position, origin, recenter duration, upload layers and
upload time. It omitted frame index, process time, explicit same-frame flags and
upload bytes, so the large stall could not be separated from a stale metric or
an upload flush. The existing test required only the outer
`worst_frame_events` key and did not guard its schema.

**GREEN:** the two 30-second D3D12 reruns above wrote all same-frame fields and
exited 0 with clean stdout/stderr. `--check-only` on
`tools/performance_matrix_60s.gd` exited 0. A disposable focused runner executed
the five harness tests and reported:

```
PASS test_the_matrix_covers_the_four_requested_sixty_second_scenarios assertions=8
PASS test_the_matrix_records_every_required_runtime_metric assertions=29
PASS test_low_end_safety_keeps_the_existing_visual_resolution_contract assertions=4
PASS test_the_visual_gate_covers_shadow_fog_and_blizzard_without_a_quality_tier assertions=6
PASS test_the_canonical_runner_refuses_a_contaminated_godot_session assertions=9
PERFORMANCE_HARNESS_TESTS total=5 failed=0
```

The full wrapper then reached `2074 passed, 8 failed`. None of the failures are
in the harness or files owned by this job: seven are the concurrently in-flight
`test_snow_interaction.gd` RED tests and two assertions are the concurrently
in-flight thin-print visual revision in `test_track_mask.gd` (one test has two
failed assertions). Per the repository rule, the full suite is not green and
this result is not represented as a clean project-wide pass.

## Concerns and next action

1. Define the actual minimum hardware and resolution/FPS contract. An RTX 5090
   baseline cannot be transformed into a low-end result by lowering resolution
   or imposing an FPS cap.
2. Run the canonical PowerShell matrix after closing the editor on that machine.
3. Capture the repeatable ~0.9-second early hitch with PIX/RenderDoc or add
   first-use timestamps around shader pipeline creation, resource loading and
   rendering-server work. Do not tune SnowField or TrackMask to hide it: the
   same-frame evidence rules both out for the 184–210 ms cases.
4. For mid-range coverage without local hardware, a remotely rented Windows GPU
   can serve as a regression proxy, but it must not be claimed equivalent to a
   named consumer card. Final minimum-spec sign-off still needs at least one
   representative physical low-end machine.
