# Sparse snow cap eviction performance

## Result

`SnowDynamicDepthLayer.trim_to_limit()` no longer rescans every retained tile
for every eviction.  It now keeps one indexed min-heap keyed by the existing
eviction order: `(touched_tick, world_x, world_z)`.  Touches update their one
heap entry and removals delete it, so the index cannot accumulate stale history
over a long snowy run.

The change preserves the previous gameplay rule exactly: the least recently
changed dynamic tile is evicted first; tiles touched in the same fixed tick use
world X then Z as their deterministic tie-break.  Snapshot serialisation is
still its canonical spatial sort, and restore rebuilds the same age index before
the next weather tick.

## TDD evidence

RED command:

```text
bash tools/run_tests.sh 2015
```

After the new 2,048-tile regression was imported, the pre-change layer reached
the expected missing instrumentation call:

```text
SCRIPT ERROR: Invalid call. Nonexistent function
'last_trim_full_tile_scans' in base 'RefCounted (SnowDynamicDepthLayer)'.
```

The wrapper correctly rejected that run.  A concurrent in-progress test line
also produced an unrelated RefCounted-free console error in this RED run; it was
not modified here.  The final isolated implementation run below is clean.

GREEN command:

```text
bash tools/run_tests.sh
```

Final console summary:

```text
WinterTime test run
============================================================
2037 passed, 0 failed
```

The wrapper exited zero and reported no `SCRIPT ERROR`, `ERROR:`, `WARNING:`,
parse, leak, or in-use marker.

## Measured cap crossing

```text
D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless \
  --path "D:/Godot resource/winter-time" \
  --script res://tools/measure_snow_eviction.gd

snow_eviction tile_count=2048 evictions=256 heap_work=8005 \
full_tile_scans=0 elapsed_us=4282
```

The old implementation would inspect `2,048 * 256 = 524,288` sparse records
for this same operation.  The new measurement uses 8,005 bounded heap
operations (31.27 per eviction), below the 40-operation cap that also covers
the persisted 8,192-tile maximum.  Two local runs measured 4.105 ms and
4.282 ms; this report records the latter.  It is a focused CPU probe
rather than a frame-time claim; render, scene, input and texture upload work
are intentionally outside this layer's contract.

## Regression coverage

- crosses the production 2,048 tile cap and verifies the exact 256 oldest
  spatially tied records are evicted;
- asserts zero full-tile scans and a bounded heap-work budget;
- verifies snapshot ordering and the next post-restore eviction;
- verifies retouching moves a tile to its current fixed-tick age without
  retaining a stale history entry;
- retains the existing wind, safe-route and sparse snapshot suites, all green.

## Files

- `src/systems/snow_dynamic_depth_layer.gd`
- `tests/unit/test_snow_dynamic_depth_layer.gd`
- `tools/measure_snow_eviction.gd`
- `Docs/reports/2026-08-13-snow-eviction-performance.md`

## Self-review

The heap does not change weather response, wind transfer, safe-route filtering,
depth amounts, or terrain/raster uploads.  It only replaces the capped-store
selection mechanism.  Tie comparison still delegates to the existing canonical
world-coordinate ordering.
