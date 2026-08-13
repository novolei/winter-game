# Snow persistence and replay report

## Result

Implemented the Phase D2 persistence seam for dynamic snow only.  A snapshot is
an in-memory, Variant-serialisable dictionary owned by the future run/save
owner; this task intentionally adds no file path, no GameState ownership, and
no death/retry choice.

The snapshot stores the run seed, persistence schema/profile version, normal
window centre, fixed-tick remainder, semantic snow/wind inputs, sparse dynamic
tile records, and registered building-carve identity records.  Dynamic records
are deterministically ordered and bounded by their existing sparse-store limit.
Loading is deliberately two-stage: inject the seed before the fresh field's
normal build; restore static building registrations through their normal owner;
then atomically validate and apply the sparse snapshot.  A mismatched schema,
profile, tile format, numeric value, or carve registry is rejected without
modifying live snow.

The API is policy-neutral.  GameState may later reuse a snapshot for a retry or
mint a fresh seed; this change does not select either behaviour.

## TDD evidence

RED: added five persistence tests to `tests/unit/test_snow_field.gd` before
implementing the APIs.  `bash tools/run_tests.sh` failed because the new public
methods did not exist; after the initial test edit it also surfaced local type
inference errors, which were corrected before implementation.  The subsequent
first implementation run caught a genuine replay discrepancy (the control run
advanced 4.0 s before its 2.3 s continuation rather than the intended 1.7 s
pre-save interval).  The test was corrected to model the documented split.

GREEN command:

```text
bash tools/run_tests.sh
```

Final console summary (the wrapper exited 0 and reported no `SCRIPT ERROR`,
`ERROR:`, `WARNING:`, `Parse Error`, leak, or in-use markers):

```text
WinterTime test run
============================================================
2021 passed, 0 failed
```

## Regression coverage

- exact seed/sparse tile/input/tick round-trip;
- resume plus continuation equals an uninterrupted simulation;
- authored Day-1 route and building-carve constraints remain mandatory;
- corrupt and incompatible snapshots reject without mutating the live field;
- persistence work is no greater than sparse tile count and leaves recenter and
  packed-texture state untouched.

## Files

- `src/systems/snow_dynamic_depth_layer.gd`
- `src/systems/snow_field.gd`
- `src/definitions/snow_field_profile.gd`
- `tools/generate_snow_field_profile.gd`
- `tests/unit/test_snow_field.gd`
- `Docs/snow_depth_dynamic_design.md`

## Self-review and concern

This deliberately serialises only SnowField-owned simulation state.  World
clock/weather-run random stream and the actual file/container format remain
future GameState/save-owner work; duplicating those systems here would violate
the zero-direct-reference boundary.  Building geometry is not re-applied by
the snapshot because applying a carve regenerates raster state; saved carve
records instead prove the normal building owner has re-registered the same
constraints before the sparse restore proceeds.
