# Deep-snow furrow onset refinement

## Scope

This pass changes only the player-side dynamic furrow visual-height response. It does
not alter TrackMask rasterisation, the snow shader, footprint profiles, furrow
width, sample spacing, turn handling, or any baked track.

## Root cause

The previous response applied a square root to the normalised snow excess and
then multiplied it by a `0.72` mask strength. That curve is discontinuous in
visual weight at the 0.42 m wading boundary: a location only 0.01 m beyond the
gate already produced 0.1697 mask units, or **27.15 virtual mm** at the shipped
0.16 m TrackMask visual height response. In 0.58 m snow it reached **108.61
virtual mm**. The final
footprint cavity lighting makes that excessive early trench more legible rather
than causing it.

## Change

- `furrow_onset`: `0.5` (square-root) to `1.0` (linear)
- `furrow_strength`: `0.72` to `0.46`
- `furrow_half_width_m`: unchanged at `0.17` m

With longitudinal wobble disabled for the nominal measurement, the new curve
produces:

| Snow depth | Previous visual height | New visual height | Intent |
|---|---:|---:|---|
| 0.421 m | 8.59 virtual mm | 0.41 virtual mm | continuous opening at the gate |
| 0.430 m | 27.15 virtual mm | 4.09 virtual mm | a beginning drag, not a trench |
| 0.580 m | 108.61 virtual mm | 65.42 virtual mm | a clearly traceable mature channel |

The formula remains monotonic and reaches 73.6 virtual mm at the 0.60 m authored
field maximum. Existing longitudinal depth and width wobble are preserved after
this nominal response, so the in-game channel does not become a uniform ribbon.

## TDD evidence

The focused CPU/headless run covers all 13 contracts in `test_furrow.gd`,
including the existing end-to-end gap, teleport, sample spacing, taper, wobble,
and curved-turn protections.

RED, before the production change:

```text
one millimetre over gate: 8.587 virtual mm
onset ratio for 1 mm -> 2 mm excess: 1.414214
0.43 m snow: 27.153 virtual mm
0.58 m snow: 108.612 virtual mm
furrow focused: 11 passed, 2 failed
```

GREEN, after the production change:

```text
furrow focused: 13 passed, 0 failed
```

Both runs completed in one second. No D3D12 rendering, visual capture, full
suite, or long-duration performance work was run.
