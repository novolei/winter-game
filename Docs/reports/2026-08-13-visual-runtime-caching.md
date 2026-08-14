# Visual-runtime caching report — 2026-08-13

## Outcome

Three render-side costs were bounded without changing shader code, authored
particle counts, particle density, fade curves, palette values, snow relief, or
occlusion geometry.

| Boundary | Before | After | Visual contract |
|---|---:|---:|---|
| Terrain settled frame | roughly 31 repeated material submissions | 0 unchanged submissions | A changed lighting value, texture RID, origin, cover, or tuning value still submits on that frame |
| Spindrift, 10 s below onset | 40 full 4096-point image rebuilds/uploads | 0 | First active frame bakes immediately; active cadence remains 4 Hz and particle density is unchanged |
| Occlusion, 1 s at 60 FPS | 60 multi-hit physics query stacks while moving; 60 while still | 19–21 while moving; 1 initial sample while still | Orthographic camera rotation is included; a >=1 m camera/subject jump samples immediately; existing tween and dwell logic still runs every frame |

## Implementation

### TerrainRenderer

All snow-ground uniforms now cross one value cache. Mutable `ImageTexture`
resources keep the same RID when their pixels are updated, so rebinding the
same resource does no useful work; a replacement resource compares different
and is submitted immediately. The same applies to SnowField/TrackMask origins,
invariant shape values, safe-route arrays and static-track bindings.

Lighting and accumulation are still evaluated every frame. During a lighting
crossfade the values genuinely change and therefore continue to submit every
frame. Once the preset settles, the three lighting submissions stop. Inspector
tuning also remains live because `_stamp_marks()` and the field continuity
check still run; only a changed property crosses the material boundary.

### Spindrift

Below `stream_onset`, `_process()` no longer rebuilds and uploads its 4096-point
RGBF emission texture every 0.25 seconds. Idle time is discarded rather than
banked. Crossing the onset performs one immediate wind-aligned bake, then keeps
the existing 0.25-second cadence while the sheet is visible. `amount`,
`amount_ratio`, pulse shaping, streak geometry, emission-point count and all
material values are untouched.

### OccluderFader

The exact multi-hit query result is cached. A moving orthographic camera or
subject refreshes it at 20 Hz; an unchanged pair reuses it indefinitely. Both
translation and camera basis are considered because this project ships an
orthographic camera. A camera or subject jump of at least 1 m bypasses the
interval. Fade target evaluation, reveal handoff, dwell and tween updates still
execute every frame from the latest exact blocking set.

## TDD evidence

RED command:

```text
bash tools/run_tests.sh
```

Expected failures before implementation:

```text
SCRIPT ERROR: Nonexistent function 'reset_material_parameter_write_count'
SCRIPT ERROR: Nonexistent function 'reset_bake_count'
SCRIPT ERROR: Nonexistent function 'reset_occlusion_sampling'
test_visual_runtime_budget.gd: 3 tests executed no assertions
```

GREEN evidence after implementation: all four tests in
`tests/unit/test_visual_runtime_budget.gd` pass in the full runner. The latest
runner had no failure, warning or engine error attributable to these files.
The repository-wide run could not become pristine while another live job was
editing pigeon tests/resources: its latest external state was `2026 passed, 9
failed`, including a pigeon-test indentation parse error and shared `user://`
fixture interference. Those files are outside this job and were not modified.

All three production scripts separately pass Godot `--check-only` under 4.7.1.

## Files changed

- `src/rendering/terrain_renderer.gd`
- `src/rendering/spindrift.gd`
- `src/rendering/occluder_fader.gd`
- `tests/unit/test_visual_runtime_budget.gd`
- `tests/unit/test_visual_runtime_budget.gd.uid`

## Self-review

- The caches suppress only equal values; no update is time-throttled in the
  terrain material path.
- Spindrift active density and cadence are unchanged. Only invisible/lull work
  is removed.
- Occlusion latency during ordinary motion is bounded to 50 ms, below the
  authored fade gesture. Teleports bypass that latency.
- No scene, shader, palette, project setting, particle count or quality preset
  was changed.

## Concern

The 20 Hz occlusion gate assumes occlusion proxies are static, matching the
existing one-discovery design. If a future feature introduces genuinely moving
occlusion proxies, that feature must explicitly invalidate the cached sample or
publish its transform change; a blind return to per-frame physics is not needed.
