# Snow-cover broadcast cache report

## Outcome

`TerrainRenderer` may still publish the continuous world cover every rendered
frame, but `CelPainter` now does no fan-out work until that value crosses a
new 1/255 visual-cover bucket. The change preserves the full-precision source
state for game-state readers and retains the first real source value that
enters a visible bucket for the materials and modelled roof snow.

This removes the former same-frame allocation of two weak-reference arrays,
the complete material-register walk, and every roof blend-shape write when
there is no visible cover change. Lighting, fog, particle, terrain, palette,
and snow-profile behaviour are untouched.

## Implementation

- Added `SNOW_COVER_BUCKET_STEPS = 255` and a cached bucket in
  `src/rendering/cel_painter.gd`.
- Kept `snow_cover()` as the continuous, authoritative weather value.
- Kept a separate `_visible_snow_cover`, updated only at a bucket crossing.
  Newly created materials and snow-mass meshes use that same visible value, so
  a late-spawned prop cannot disagree with the standing world.
- Returned before building the weak-reference arrays when the bucket is
  unchanged.
- Added cumulative material and mass write counters strictly as a regression
  observation API; their `Dictionary` is constructed only when a test or
  diagnostic requests it, never in the render path.

## TDD evidence

### RED

Command:

```text
bash tools/run_tests.sh
```

Before the implementation, the newly added focused test could not resolve
`CelPainter.snow_cover_write_counts()`. The wrapper reported `2015 passed, 1
failed`, named `test_cel_painter.gd`, and rejected the run for the expected
parse error. This proves the test asked for observability the former
implementation did not provide.

### GREEN at assertion level

The same wrapper after implementation reported `2036 passed, 0 failed`; the
new test proved all of the following:

1. `0.5000` then `0.5005` produces zero additional material writes and zero
   additional roof-mass writes.
2. Crossing to `0.5100` increments both write paths.
3. The material receives `0.5100` and the roof follows
   `snow_mass(0.5100)`, preserving the existing continuous curve at every
   actual visual update.

That particular wrapper invocation was not pristine because concurrent
dynamic-snow work emitted an unrelated `SnowDynamicDepthLayer` RefCounted-free
error and referenced an in-flight method. No affected source file was changed
here.

### Final clean wrapper

After that concurrent line settled, the final command was again:

```text
bash tools/run_tests.sh
```

Complete wrapper result: exit code `0`, no `SCRIPT ERROR`, `ERROR`, `WARNING`,
or leak text, and `2036 passed, 0 failed`.

## Files

- `src/rendering/cel_painter.gd`
- `tests/unit/test_cel_painter.gd`
- `Docs/reports/2026-08-13-snow-cover-broadcast-cache-report.md`

## Self-review

- The early return happens before either temporary weak-reference array is
  allocated.
- The bucket only limits visual uploads; `snow_cover()` remains full precision
  for simulation and diagnostics.
- Materials and roof masses created between source updates are stamped from the
  last visual value, preserving world consistency.
- No existing art-direction values or palette colours changed.

## Remaining verification

The cache has a static regression gate. The next runtime profiler capture
should use the F3 panel to record the reduced host-to-GPU work during a real
weather transition; it is a measurement follow-up, not a correctness blocker.
